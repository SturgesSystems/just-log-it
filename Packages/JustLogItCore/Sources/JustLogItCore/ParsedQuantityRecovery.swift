import Foundation

/// Conservatively recovers a simple, explicit amount that a model omitted.
/// Semantic interpretation remains model-owned; this only preserves one source
/// number and its nearby measurement or food-count unit.
public enum ParsedQuantityRecovery {
  public static func recoveringSimpleAmount(
    in parsed: ParsedFoodRequest,
    from source: String
  ) -> ParsedFoodRequest {
    guard parsed.quantity == nil, parsed.fractionOfWhole == nil,
      !parsed.containsMultipleFoods
    else { return parsed }

    let tokens = sourceTokens(source)
    let identityNumberIndices = identityNumberIndices(in: tokens, parsed: parsed)
    let numbers: [(index: Int, value: Double)] = tokens.indices.compactMap { index in
      guard !identityNumberIndices.contains(index) else { return nil }
      guard let value = numericValue(tokens[index]) else { return nil }
      return (index: index, value: value)
    }
    guard numbers.count == 1, let number = numbers.first, number.value > 0 else { return parsed }

    let following = tokens.indices.filter { $0 > number.index && $0 - number.index <= 6 }
    let sizeFamilies: Set<String> = ["small", "medium", "large", "extralarge", "jumbo"]
    let recognizedUnitIndex = following.first { index in
      let family = UnitConversion.family(tokens[index])
      guard !sizeFamilies.contains(family) else { return false }
      return UnitConversion.dimension(of: tokens[index]) != .unknown
    }

    let productTokens = sourceTokens(parsed.productName)
    let productUnitIndex = productTokens.last.flatMap { noun in
      following.last { sourceNoun in
        UnitConversion.family(tokens[sourceNoun]) == UnitConversion.family(noun)
      }
    }
    guard let unitIndex = recognizedUnitIndex ?? productUnitIndex else { return parsed }

    var recovered = parsed
    recovered.quantity = number.value
    recovered.unit = tokens[unitIndex]
    recovered.quantityText = tokens[number.index...unitIndex].joined(separator: " ")
    recovered.quantityNeedsClarification = false
    return recovered
  }

  /// True when the source contains a concrete number/fraction. Callers use this
  /// to prevent a failed recovery from silently turning an explicit amount into
  /// one generic serving.
  public static func containsExplicitAmount(in source: String) -> Bool {
    sourceTokens(source).contains { numericValue($0) != nil }
  }

  /// True when the source has a concrete amount after excluding numbers that
  /// belong to the parsed food identity (for example, the `7` in “7 Layer Dip”).
  public static func containsExplicitAmount(
    in source: String,
    for parsed: ParsedFoodRequest
  ) -> Bool {
    let tokens = sourceTokens(source)
    let identityNumbers = identityNumberIndices(in: tokens, parsed: parsed)
    return tokens.indices.contains { index in
      !identityNumbers.contains(index) && numericValue(tokens[index]) != nil
    }
  }

  private static func sourceTokens(_ source: String) -> [String] {
    source.folding(
      options: [.caseInsensitive, .diacriticInsensitive],
      locale: Locale(identifier: "en_US_POSIX")
    )
    // Keep percentages intact: the `1` in “1% milk” is a product descriptor,
    // not evidence that one unit was consumed.
    .split { !$0.isLetter && !$0.isNumber && $0 != "/" && $0 != "%" && $0 != "." }
    .map(String.init)
  }

  private static func identityNumberIndices(
    in sourceValues: [String],
    parsed: ParsedFoodRequest
  ) -> Set<Int> {
    let phrases =
      [parsed.productName, parsed.brand, parsed.searchTerms]
      .compactMap { value -> [String]? in
        guard let value else { return nil }
        let tokens = sourceTokens(value)
        guard tokens.contains(where: { numericValue($0) != nil }),
          tokens.contains(where: { numericValue($0) == nil })
        else { return nil }
        return tokens
      }
      + parsed.descriptors.compactMap { descriptor -> [String]? in
        let tokens = sourceTokens(descriptor)
        guard tokens.count > 1,
          tokens.contains(where: { numericValue($0) != nil }),
          tokens.contains(where: { numericValue($0) == nil })
        else { return nil }
        return tokens
      }

    var protected = Set<Int>()
    for phrase in phrases where phrase.count <= sourceValues.count {
      for start in 0...(sourceValues.count - phrase.count) {
        let indices = start..<(start + phrase.count)
        guard zip(sourceValues[indices], phrase).allSatisfy(tokensMatch) else { continue }
        for index in indices where numericValue(sourceValues[index]) != nil {
          protected.insert(index)
        }
      }
    }
    return protected
  }

  private static func tokensMatch(_ lhs: String, _ rhs: String) -> Bool {
    if lhs == rhs { return true }
    return UnitConversion.family(lhs) == UnitConversion.family(rhs)
  }

  private static func numericValue(_ token: String) -> Double? {
    if let value = Double(token), value.isFinite { return value }
    let fraction = token.split(separator: "/")
    if fraction.count == 2,
      let numerator = Double(fraction[0]),
      let denominator = Double(fraction[1]),
      denominator > 0
    {
      return numerator / denominator
    }
    return switch token {
    case "one": 1
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

}
