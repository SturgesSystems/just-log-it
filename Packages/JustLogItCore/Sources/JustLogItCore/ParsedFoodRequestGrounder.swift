import Foundation

public struct ParsedFoodRequestGrounder: Sendable {
  public init() {}

  public func ground(_ candidate: ParsedFoodRequest, in source: String) -> ParsedFoodRequest {
    let evidence = SourceEvidence(source)
    var result = candidate

    result.productName =
      evidence.containsProductIntent(candidate.productName) ? candidate.productName : ""
    result.searchTerms = result.productName
    result.brand = groundedPhrase(candidate.brand, evidence: evidence)
    result.preparation = groundedPhrase(candidate.preparation, evidence: evidence)
    result.descriptors = candidate.descriptors.filter { evidence.containsPhrase($0) }
    result.quantityText = groundedPhrase(candidate.quantityText, evidence: evidence)

    if !evidence.supportsPair(number: candidate.quantity, unit: candidate.unit) {
      result.quantity = nil
      result.unit = nil
    }
    if !evidence.supportsFraction(candidate.fractionOfWhole, whole: candidate.wholeUnit) {
      result.fractionOfWhole = nil
      result.wholeUnit = nil
    }
    if !evidence.supportsPair(number: candidate.containerSize, unit: candidate.containerSizeUnit) {
      result.containerSize = nil
      result.containerSizeUnit = nil
    }
    if !evidence.supportsPair(number: candidate.alternateQuantity, unit: candidate.alternateUnit) {
      result.alternateQuantity = nil
      result.alternateUnit = nil
    }

    result.isApproximate = candidate.isApproximate && evidence.containsApproximation
    result.containsMultipleFoods = candidate.containsMultipleFoods && evidence.containsConjunction
    // Components must appear in the source (or as product intent tokens).
    result.componentNames = candidate.componentNames
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .filter { evidence.containsPhrase($0) || evidence.containsProductIntent($0) }
    // Free-form notes only survive when their wording is source-grounded (anti-contamination).
    result.ambiguityNotes = groundedPhrase(candidate.ambiguityNotes, evidence: evidence)

    // Clarification fields are model judgments for the policy/UI layer — not source phrases.
    // Keep them. Do not invent or rewrite the prompt. Only drop detail flags contradicted
    // by facts that survived grounding; leave the prompt unless every detail flag cleared
    // *and* identity/multi-food no longer need a question.
    result.quantityNeedsClarification = candidate.quantityNeedsClarification
    result.preparationNeedsClarification = candidate.preparationNeedsClarification
    result.clarificationPrompt = cleanedOptional(candidate.clarificationPrompt)
    result.clarificationSuggestions = candidate.clarificationSuggestions
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }

    if result.quantity != nil || result.fractionOfWhole != nil {
      result.quantityNeedsClarification = false
    }
    if result.preparation != nil {
      result.preparationNeedsClarification = false
    }

    let hasIdentity = !result.productName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    // Amount/prep only make sense once a real food is known.
    if !hasIdentity {
      result.quantityNeedsClarification = false
      result.preparationNeedsClarification = false
    }

    // If the model still has nothing to ask and identity is ready, drop leftover prompt.
    let stillNeedsSoftClarify =
      result.quantityNeedsClarification
      || result.preparationNeedsClarification
      || !hasIdentity
      || result.containsMultipleFoods
    if !stillNeedsSoftClarify {
      result.clarificationPrompt = nil
      result.clarificationSuggestions = []
    }
    return result
  }

  private func cleanedOptional(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  private func groundedPhrase(_ phrase: String?, evidence: SourceEvidence) -> String? {
    guard let phrase, evidence.containsPhrase(phrase) else { return nil }
    return phrase
  }
}

private struct SourceEvidence {
  private struct NumberEvidence {
    let value: Double
    let range: Range<Int>
    let blocksOtherPairs: Bool

    var index: Int { range.lowerBound }
  }

  private let tokens: [String]
  private let numbers: [NumberEvidence]
  private let sourceContainsApproximationSymbol: Bool

  init(_ source: String) {
    tokens = Self.tokens(source)
    numbers = Self.numberEvidence(in: tokens)
    sourceContainsApproximationSymbol = source.contains("~") || source.contains("≈")
  }

  var containsApproximation: Bool {
    sourceContainsApproximationSymbol
      || !Set(tokens).isDisjoint(
        with: [
          "about", "almost", "approx", "approximate", "approximately", "around", "circa",
          "nearly", "roughly", "few", "some", "several", "couple", "handful", "many", "lots",
        ])
  }

  var containsConjunction: Bool {
    !Set(tokens).isDisjoint(with: ["and", "with", "plus"])
  }

  func containsPhrase(_ phrase: String) -> Bool {
    let phraseTokens = Self.tokens(phrase)
    guard !phraseTokens.isEmpty, phraseTokens.count <= tokens.count else { return false }
    return tokens.indices.contains { start in
      let end = start + phraseTokens.count
      guard end <= tokens.count else { return false }
      return zip(tokens[start..<end], phraseTokens).allSatisfy(Self.tokensMatch)
    }
  }

  func containsProductIntent(_ product: String) -> Bool {
    let productTokens = Self.tokens(product)
    guard !productTokens.isEmpty else { return false }
    return tokens.indices.contains { start in
      guard Self.tokensMatch(tokens[start], productTokens[0]) else { return false }
      var sourceIndex = tokens.index(after: start)
      for productToken in productTokens.dropFirst() {
        guard
          let match = tokens[sourceIndex...].firstIndex(where: {
            Self.tokensMatch($0, productToken)
          }),
          tokens[sourceIndex..<match].allSatisfy(Self.productFillers.contains)
        else { return false }
        sourceIndex = tokens.index(after: match)
      }
      return true
    }
  }

  func supportsPair(number: Double?, unit: String?) -> Bool {
    guard let number, number.isFinite, number > 0, let unit else { return false }
    let unitStarts = unitStartIndices(unit)
    return numbers.contains { numeric in
      approximatelyEqual(numeric.value, number)
        && unitStarts.contains { unitIndex in
          unitIndex >= numeric.range.upperBound
            && unitIndex - numeric.index <= 6
            && !containsBoundary(in: numeric.range.upperBound..<unitIndex, includeOf: true)
            && !numbers.contains { other in
              other.blocksOtherPairs
                && other.index >= numeric.range.upperBound
                && other.index < unitIndex
            }
        }
    }
  }

  func supportsFraction(_ fraction: Double?, whole: String?) -> Bool {
    guard let fraction, fraction.isFinite, fraction > 0, fraction <= 1, let whole else {
      return false
    }
    let wholeStarts = unitStartIndices(whole)
    return numbers.contains { numeric in
      numeric.blocksOtherPairs
        && approximatelyEqual(numeric.value, fraction)
        && wholeStarts.contains { wholeIndex in
          wholeIndex >= numeric.range.upperBound
            && wholeIndex - numeric.index <= 8
            && !containsBoundary(in: numeric.range.upperBound..<wholeIndex, includeOf: false)
        }
    }
  }

  private func containsBoundary(in range: Range<Int>, includeOf: Bool) -> Bool {
    let boundaries: Set<String> =
      includeOf
      ? ["and", "of", "plus", "with"] : ["and", "plus", "with"]
    return tokens[range].contains(where: boundaries.contains)
  }

  private func unitStartIndices(_ unit: String) -> [Int] {
    let target = Self.canonicalUnit(Self.tokens(unit))
    guard !target.isEmpty else { return [] }
    return tokens.indices.filter { start in
      (1...min(3, tokens.count - start)).contains { length in
        Self.canonicalUnit(Array(tokens[start..<(start + length)])) == target
      }
    }
  }

  private func phraseStartIndices(_ phrase: String) -> [Int] {
    let phraseTokens = Self.tokens(phrase)
    guard !phraseTokens.isEmpty, phraseTokens.count <= tokens.count else { return [] }
    return tokens.indices.filter { start in
      let end = start + phraseTokens.count
      guard end <= tokens.count else { return false }
      return zip(tokens[start..<end], phraseTokens).allSatisfy(Self.tokensMatch)
    }
  }

  private func approximatelyEqual(_ lhs: Double, _ rhs: Double) -> Bool {
    abs(lhs - rhs) <= max(0.000_001, abs(rhs) * 0.000_001)
  }

  private static func tokens(_ text: String) -> [String] {
    text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
      .split { character in
        !character.isLetter && !character.isNumber && character != "/"
      }
      .map(String.init)
  }

  private static func tokensMatch(_ lhs: String, _ rhs: String) -> Bool {
    lhs == rhs || singular(lhs) == singular(rhs)
  }

  private static func singular(_ token: String) -> String {
    if token.count > 3, token.hasSuffix("s") { return String(token.dropLast()) }
    return token
  }

  private static func canonicalUnit(_ unitTokens: [String]) -> String {
    let normalized = unitTokens.map(singular)
    let joined = normalized.joined(separator: " ")
    return switch joined {
    case "oz", "ounce": "ounce"
    case "fl oz", "fluid oz", "fluid ounce": "fluid ounce"
    case "lb", "lbs", "pound": "pound"
    case "mg", "milligram": "milligram"
    case "mcg", "ug", "µg", "microgram": "microgram"
    case "g", "gram": "gram"
    case "kg", "kilogram": "kilogram"
    case "ml", "milliliter", "millilitre": "milliliter"
    case "cl", "centiliter", "centilitre": "centiliter"
    case "dl", "deciliter", "decilitre": "deciliter"
    case "l", "liter", "litre": "liter"
    case "tsp", "teaspoon": "teaspoon"
    case "tbsp", "tablespoon": "tablespoon"
    case "pt", "pint": "pint"
    case "qt", "quart": "quart"
    case "serving": "serving"
    default: joined
    }
  }

  private static let productFillers: Set<String> = ["a", "an", "of", "the"]

  private static func numberEvidence(in tokens: [String]) -> [NumberEvidence] {
    var result: [NumberEvidence] = []
    for (index, token) in tokens.enumerated() {
      if let value = numericValue(token) {
        result.append(
          NumberEvidence(
            value: value,
            range: index..<(index + 1),
            blocksOtherPairs: token != "a" && token != "an"
          ))
      }
      guard index + 1 < tokens.count,
        let numerator = numeratorValue(tokens[index]),
        let denominator = denominatorValue(tokens[index + 1])
      else { continue }
      result.append(
        NumberEvidence(
          value: numerator / denominator,
          range: index..<(index + 2),
          blocksOtherPairs: true
        ))
    }

    for index in tokens.indices {
      guard let whole = wholeNumberValue(tokens[index]) else { continue }
      if index + 1 < tokens.count, let fraction = fractionValue(tokens[index + 1]) {
        result.append(
          NumberEvidence(
            value: whole + fraction,
            range: index..<(index + 2),
            blocksOtherPairs: true
          ))
      }
      guard index + 2 < tokens.count, tokens[index + 1] == "and" else { continue }
      if let fraction = fractionValue(tokens[index + 2]) {
        result.append(
          NumberEvidence(
            value: whole + fraction,
            range: index..<(index + 3),
            blocksOtherPairs: true
          ))
      }
      if index + 3 < tokens.count,
        let numerator = numeratorValue(tokens[index + 2]),
        let denominator = denominatorValue(tokens[index + 3])
      {
        result.append(
          NumberEvidence(
            value: whole + numerator / denominator,
            range: index..<(index + 4),
            blocksOtherPairs: true
          ))
      }
    }
    return result
  }

  private static func wholeNumberValue(_ token: String) -> Double? {
    guard let value = numericValue(token), value.rounded() == value, value >= 0 else { return nil }
    return value
  }

  private static func numericValue(_ token: String) -> Double? {
    if let value = Double(token), value.isFinite { return value }
    if let slash = fractionValue(token) { return slash }
    return switch token {
    case "a", "an", "one": 1
    case "two": 2
    case "three": 3
    case "four": 4
    case "five": 5
    case "six": 6
    case "seven": 7
    case "eight": 8
    case "nine": 9
    case "ten": 10
    case "eleven": 11
    case "twelve": 12
    case "half", "½": 0.5
    case "quarter", "¼": 0.25
    case "¾": 0.75
    case "⅓": 1.0 / 3.0
    case "⅔": 2.0 / 3.0
    case "⅛": 0.125
    case "⅜": 0.375
    case "⅝": 0.625
    case "⅞": 0.875
    default: nil
    }
  }

  private static func numeratorValue(_ token: String) -> Double? {
    switch token {
    case "a", "an", "one": 1
    case "two": 2
    case "three": 3
    case "four": 4
    case "five": 5
    case "six": 6
    case "seven": 7
    default: Double(token)
    }
  }

  private static func denominatorValue(_ token: String) -> Double? {
    switch token {
    case "half", "halves": 2
    case "third", "thirds": 3
    case "quarter", "quarters", "fourth", "fourths": 4
    case "fifth", "fifths": 5
    case "sixth", "sixths": 6
    case "seventh", "sevenths": 7
    case "eighth", "eighths": 8
    default: nil
    }
  }

  private static func fractionValue(_ token: String) -> Double? {
    let parts = token.split(separator: "/")
    guard parts.count == 2,
      let numerator = Double(parts[0]),
      let denominator = Double(parts[1]),
      denominator != 0
    else { return nil }
    return numerator / denominator
  }
}
