import Foundation

/// Extracts only facts that can be established with deterministic text rules.
/// Semantic interpretation and food-boundary resolution remain model-owned.
public struct FoodTextEvidenceExtractor: Sendable {
  public init() {}

  public func extract(from source: String) -> FoodTextEvidence {
    let normalizedSource = Self.collapseWhitespace(source)
    guard !normalizedSource.isEmpty else {
      return FoodTextEvidence(normalizedSource: "", identityCandidate: nil)
    }

    var stripped: [String] = []
    var working = Self.removeMatch(
      pattern: #"^(?:(?:please|can you|could you)\s+)?(?:log|track|record)\s+(?:that\s+)?"#,
      from: normalizedSource,
      recordingIn: &stripped
    )
    // Siri-style framing: "For breakfast I had…", "I just finished…", "tonight I ate…"
    working = Self.removeMatch(
      pattern:
        #"^(?:(?:for\s+(?:breakfast|brunch|lunch|dinner|supper)|tonight|this\s+(?:morning|afternoon|evening))\s+)?(?:i\s+)?(?:just\s+)?(?:ate|had|finished(?:\s+eating)?)\s+"#,
      from: working,
      recordingIn: &stripped
    )
    working = Self.removeMatch(
      pattern:
        #"\s+(?:for\s+(?:breakfast|brunch|lunch|dinner|supper)|just\s+now|today|tonight|yesterday|\d+(?:\.\d+)?\s+(?:minutes?|hours?|days?)\s+ago)$"#,
      from: working,
      recordingIn: &stripped
    )
    working = Self.collapseWhitespace(working)

    let lower = Self.folded(working)
    let promptInjection = Self.promptInjectionPhrases.contains { lower.contains($0) }
    let likelyNonFoodRequest = Self.isLikelyNonFoodRequest(lower)
    let approximationMarkers = Self.approximationMarkers.filter {
      Self.containsPhrase($0, in: lower)
    }
    let unresolvedReferences = Self.unresolvedReferencePhrases.filter {
      Self.containsPhrase($0, in: lower)
    }
    let connectors = Self.multipleFoodConnectors.filter {
      $0 == "&" ? lower.contains(" & ") : Self.containsPhrase($0, in: lower)
    }

    // Approximation is retained as evidence, but a leading hedge must not prevent
    // extraction of the concrete amount that follows it (for example, “about half”).
    let extractionWorking = Self.removeMatchWithoutRecording(
      pattern: #"^(?:about|almost|around|approximately|nearly|roughly)\s+"#,
      from: working
    )
    let sourceBrandRelationship = Self.explicitBrandRelationship(in: extractionWorking)
    let factWorking = sourceBrandRelationship?.identity ?? extractionWorking
    let leadingIndefiniteArticle = Self.leadingIndefiniteArticle(in: factWorking)
    let articleRepresentsSingleCount =
      leadingIndefiniteArticle.map {
        Self.articleCanRepresentSingleCount(remainder: $0.remainder)
      } ?? false
    var identityWorking = factWorking
    var fraction: FoodFractionEvidence?
    var container: FoodContainerEvidence?
    var primaryQuantity: FoodQuantityEvidence?
    var alternateQuantity: FoodQuantityEvidence?
    var fractionSourceText: String?
    var containerSourceText: String?

    if let pair = Self.explicitMeasurementPair(in: factWorking) {
      primaryQuantity = FoodQuantityEvidence(
        value: pair.primaryValue,
        unit: pair.primaryUnit,
        sourceText: pair.primarySourceText
      )
      alternateQuantity = FoodQuantityEvidence(
        value: pair.alternateValue,
        unit: pair.alternateUnit,
        sourceText: pair.alternateSourceText
      )
      identityWorking = pair.identity

    } else if let match = Self.captures(
      pattern:
        #"^(half|one\s+half|1/2|½|quarter|one\s+quarter|1/4|¼|three\s+quarters|3/4|¾)\s+(?:of\s+)?(?:a\s+|an\s+|the\s+)?(\d+(?:\.\d+)?)\s*[- ]?\s*(fl\.?\s*oz|fluid\s+ounces?|ounces?|ounce|oz|grams?|g|milliliters?|ml|liters?|l)\b(?:\s+(bottle|can|container|carton|package))?\s+(?:of\s+)?(.+)$"#,
      in: factWorking
    ),
      let fractionText = match[safe: 1] ?? nil,
      let fractionValue = Self.fractionValue(fractionText),
      let sizeText = match[safe: 2] ?? nil,
      let size = Double(sizeText),
      let unitText = match[safe: 3] ?? nil,
      let identity = match[safe: 5] ?? nil
    {
      let containerKind = (match[safe: 4] ?? nil)?.lowercased()
      fractionSourceText = fractionText
      containerSourceText = [sizeText, unitText, containerKind].compactMap { $0 }.joined(
        separator: " ")
      fraction = FoodFractionEvidence(value: fractionValue, wholeUnit: containerKind)
      container = FoodContainerEvidence(
        size: size,
        unit: UnitConversion.family(unitText),
        containerKind: containerKind
      )
      identityWorking = identity
    } else if let match = Self.captures(
      pattern:
        #"^(half|one\s+half|1/2|½|quarter|one\s+quarter|1/4|¼|three\s+quarters|3/4|¾)\s+(?:(?:of\s+)?(?:a|an|the)\s+|of\s+)(.+)$"#,
      in: factWorking
    ),
      let fractionText = match[safe: 1] ?? nil,
      let fractionValue = Self.fractionValue(fractionText),
      let identity = match[safe: 2] ?? nil
    {
      let whole = Self.words(in: identity).last
      fractionSourceText = fractionText
      fraction = FoodFractionEvidence(value: fractionValue, wholeUnit: whole)
      identityWorking = identity
    } else {
      // Strip an article before looking for a real measurement. This keeps
      // “an 8 oz steak” as identity `steak` without inventing an article count.
      identityWorking = Self.removingLeadingAmount(
        from: leadingIndefiniteArticle?.remainder ?? identityWorking
      )
    }

    identityWorking = Self.removeLeadingArticle(from: identityWorking)
    let brandRelationship =
      sourceBrandRelationship ?? Self.explicitBrandRelationship(in: identityWorking)
    if sourceBrandRelationship == nil, let brandRelationship {
      identityWorking = brandRelationship.identity
    }
    let candidate = Self.cleanedIdentity(identityWorking)
    let identityCandidate =
      Self.isVagueNonIdentity(candidate) || likelyNonFoodRequest ? nil : candidate

    let candidateWords = Self.words(in: identityCandidate ?? "")
    let preparation = candidateWords.first { Self.preparationWords.contains(Self.folded($0)) }
      .map(Self.folded)
    let descriptors = candidateWords.compactMap { word -> String? in
      let value = Self.folded(word)
      if Self.sizeDescriptors.contains(value) || value.hasSuffix("%") { return value }
      return nil
    }

    let provisional = ParsedFoodRequest(
      productName: identityCandidate ?? "",
      searchTerms: identityCandidate ?? "",
      fractionOfWhole: fraction?.value,
      wholeUnit: fraction?.wholeUnit,
      containerSize: container?.size,
      containerSizeUnit: container?.unit,
      preparation: preparation,
      descriptors: descriptors,
      isApproximate: !approximationMarkers.isEmpty
    )
    let quantityRecoverySource =
      if articleRepresentsSingleCount, let remainder = leadingIndefiniteArticle?.remainder {
        "one \(remainder)"
      } else {
        factWorking
      }
    let recovered =
      if primaryQuantity == nil {
        ParsedQuantityRecovery.recoveringSimpleAmount(
          in: provisional,
          from: quantityRecoverySource
        )
      } else {
        provisional
      }
    let hasAmbiguousQuantity = Self.matches(
      pattern:
        #"\b(?:\d+(?:\.\d+)?|one|two|three|four|five|six|seven|eight|nine|ten)\s*(?:-|to|or)\s*(?:\d+(?:\.\d+)?|one|two|three|four|five|six|seven|eight|nine|ten)\b"#,
      in: factWorking
    )
    let hasNonpositiveQuantity = Self.matches(
      pattern:
        #"\b(?:negative|minus)\s+(?:\d+(?:\.\d+)?|one|two|three|four|five|six|seven|eight|nine|ten)\b|\b(?:zero|0(?:\.0+)?)\s+(?:cups?|eggs?|grams?|g|items?|pieces?|servings?|slices?)\b"#,
      in: factWorking
    )
    let containsAmount = ParsedQuantityRecovery.containsExplicitAmount(
      in: factWorking,
      for: provisional
    )
    let hasVagueQuantity = !Set(approximationMarkers).isDisjoint(with: Self.vagueQuantityMarkers)
    let hasImplausiblyLargeCount =
      (primaryQuantity?.value ?? recovered.quantity).map { value in
        guard value > 10_000, let unit = recovered.unit else { return false }
        let dimension = UnitConversion.dimension(of: unit)
        return dimension == .count || dimension == .serving || dimension == .unknown
      } ?? false
    let hasUnresolvedQuantity =
      hasAmbiguousQuantity
      || hasNonpositiveQuantity
      || hasImplausiblyLargeCount
      || (hasVagueQuantity && primaryQuantity == nil && recovered.quantity == nil && fraction == nil
        && container == nil)
      || (containsAmount && primaryQuantity == nil && recovered.quantity == nil && fraction == nil
        && container == nil)
      || (leadingIndefiniteArticle != nil && !articleRepresentsSingleCount
        && connectors.isEmpty && primaryQuantity == nil && recovered.quantity == nil
        && fraction == nil && container == nil)
    let quantity: FoodQuantityEvidence? =
      if let primaryQuantity {
        primaryQuantity
      } else if !hasAmbiguousQuantity, !hasNonpositiveQuantity, !hasImplausiblyLargeCount,
        let value = recovered.quantity,
        let text = recovered.quantityText
      {
        FoodQuantityEvidence(
          value: value,
          unit: recovered.unit,
          sourceText: articleRepresentsSingleCount ? factWorking : text
        )
      } else {
        nil
      }

    let provenance = Self.provenance(
      normalizedSource: normalizedSource,
      identity: identityCandidate,
      brand: brandRelationship?.brand,
      preparation: preparation,
      descriptors: descriptors,
      quantity: quantity,
      fractionSourceText: fractionSourceText,
      containerSourceText: containerSourceText,
      alternateQuantity: alternateQuantity
    )

    return FoodTextEvidence(
      normalizedSource: normalizedSource,
      identityCandidate: identityCandidate,
      explicitBrand: brandRelationship?.brand,
      quantity: quantity,
      fraction: fraction,
      container: container,
      alternateQuantity: alternateQuantity,
      explicitPreparation: preparation,
      explicitDescriptors: descriptors,
      approximationMarkers: approximationMarkers,
      possibleMultipleFoodConnectors: connectors,
      unresolvedReferences: unresolvedReferences,
      strippedLoggingLanguage: stripped,
      containsPromptInjectionLanguage: promptInjection,
      hasUnresolvedQuantity: hasUnresolvedQuantity,
      provenance: provenance
    )
  }

  private static let preparationWords: Set<String> = [
    "baked", "boiled", "cooked", "fried", "grilled", "poached", "raw", "roasted",
    "sauteed", "scrambled", "steamed",
  ]
  private static let sizeDescriptors: Set<String> = [
    "extra-large", "extralarge", "jumbo", "large", "medium", "small",
  ]
  private static let approximationMarkers = [
    "about", "almost", "around", "approximately", "couple", "few", "handful", "roughly",
    "nearly", "several", "some",
  ]
  private static let vagueQuantityMarkers: Set<String> = [
    "couple", "few", "handful", "several", "some",
  ]
  private static let multipleFoodConnectors = ["and", "with", "plus", "&"]
  private static let unresolvedReferencePhrases = [
    "that", "the other", "the usual", "what i had", "same as", "earlier",
  ]
  private static let promptInjectionPhrases = [
    "developer message", "ignore all instructions", "ignore previous instructions",
    "ignore your instructions", "repeat every value", "reveal your prompt", "set productname",
    "system prompt", "this is not a food log",
  ]
  private static let vagueNonIdentities: Set<String> = [
    "", "a snack", "food", "idk", "leftovers", "n/a", "snack", "something good",
    "something yummy", "the usual", "whatever",
  ]
  private static let protectedNumericIdentityFollowers: Set<String> = [
    "grain", "grand", "layer", "spice", "up",
  ]
  private static let genericMeasureUnits: Set<String> = [
    "bar", "bottle", "bowl", "can", "container", "cup", "each", "g", "item", "kg",
    "l", "lb", "mg", "ml", "oz", "piece", "pint", "quart", "serving", "slice", "tbsp",
    "tsp",
  ]
  /// Keep article promotion identical to the deliberately small production count-noun slice.
  /// An article before any other identity is evidence that a quantity exists, but not enough
  /// deterministic evidence to bind that quantity to a safe unit.
  private static let articleCountNouns: Set<String> = [
    "apple", "banana", "cookie", "egg",
  ]

  private struct ExplicitMeasurementPair {
    let primaryValue: Double
    let primaryUnit: String
    let primarySourceText: String
    let alternateValue: Double
    let alternateUnit: String
    let alternateSourceText: String
    let identity: String
  }

  /// Recognizes only an explicitly paired leading amount such as `1 cup (240 g) yogurt` or
  /// `2 cookies / 30 g cookies`. Two free-standing numbers are deliberately not paired.
  private static func explicitMeasurementPair(in text: String) -> ExplicitMeasurementPair? {
    let amount = #"(\d+(?:\.\d+)?)"#
    let unit =
      #"(fl\.?\s*oz|fluid\s+ounces?|ounces?|ounce|oz|pounds?|lbs?|lb|kilograms?|kg|grams?|g|milliliters?|ml|liters?|l|cups?|tablespoons?|tbsp|teaspoons?|tsp|servings?|slices?|pieces?|items?|cookies?|eggs?)"#
    let separator = #"(?:\(\s*|/\s*|,\s*(?:or\s+)?)"#
    let pattern =
      #"^"# + amount + #"\s*"# + unit + #"\s*"# + separator + amount + #"\s*"# + unit
      + #"\s*\)?\s+(?:of\s+)?(.+)$"#
    guard let match = captures(pattern: pattern, in: text),
      let primaryValueText = match[safe: 1] ?? nil,
      let primaryValue = Double(primaryValueText), primaryValue.isFinite, primaryValue > 0,
      let primaryUnitText = match[safe: 2] ?? nil,
      let alternateValueText = match[safe: 3] ?? nil,
      let alternateValue = Double(alternateValueText), alternateValue.isFinite, alternateValue > 0,
      let alternateUnitText = match[safe: 4] ?? nil,
      let identity = match[safe: 5] ?? nil
    else { return nil }

    let primaryUnit = UnitConversion.family(primaryUnitText)
    let alternateUnit = UnitConversion.family(alternateUnitText)
    let primaryDimension = UnitConversion.dimension(of: primaryUnit)
    let alternateDimension = UnitConversion.dimension(of: alternateUnit)
    guard primaryDimension != .unknown, alternateDimension != .unknown else { return nil }
    if primaryDimension == alternateDimension {
      guard primaryUnit != alternateUnit,
        let converted = UnitConversion.convert(
          quantity: primaryValue,
          from: primaryUnit,
          to: alternateUnit
        ),
        abs(converted - alternateValue) / alternateValue <= 0.02
      else { return nil }
    }

    return ExplicitMeasurementPair(
      primaryValue: primaryValue,
      primaryUnit: primaryUnit,
      primarySourceText: "\(primaryValueText) \(primaryUnitText)",
      alternateValue: alternateValue,
      alternateUnit: alternateUnit,
      alternateSourceText: "\(alternateValueText) \(alternateUnitText)",
      identity: identity
    )
  }

  private struct ExplicitBrandRelationship {
    let identity: String
    let brand: String
  }

  /// Brand extraction requires an explicit `brand` label. Capitalization, `made by`, and unknown
  /// proper nouns are never treated as brand evidence because they cannot distinguish a commercial
  /// brand from a person, place, or product-line name.
  private static func explicitBrandRelationship(in text: String) -> ExplicitBrandRelationship? {
    let brand = #"([\p{L}\p{N}][\p{L}\p{N}&'’.\-]*(?:\s+[\p{L}\p{N}][\p{L}\p{N}&'’.\-]*){0,3})"#
    if let match = captures(pattern: #"^(.+?),\s*brand\s*:\s*"# + brand + #"$"#, in: text),
      let identity = match[safe: 1] ?? nil,
      let brandValue = match[safe: 2] ?? nil
    {
      return ExplicitBrandRelationship(identity: identity, brand: brandValue)
    }
    if let match = captures(pattern: #"^"# + brand + #"(?:\s+|\s*-\s*)brand\s+(.+)$"#, in: text),
      let brandValue = match[safe: 1] ?? nil,
      let identity = match[safe: 2] ?? nil
    {
      return ExplicitBrandRelationship(identity: identity, brand: brandValue)
    }
    return nil
  }

  private static func provenance(
    normalizedSource: String,
    identity: String?,
    brand: String?,
    preparation: String?,
    descriptors: [String],
    quantity: FoodQuantityEvidence?,
    fractionSourceText: String?,
    containerSourceText: String?,
    alternateQuantity: FoodQuantityEvidence?
  ) -> [FoodEvidenceProvenance] {
    var result: [FoodEvidenceProvenance] = []

    func append(_ field: FoodEvidenceField, _ sourceText: String?) {
      guard let sourceText,
        let match = sourceMatch(for: sourceText, in: normalizedSource)
      else { return }
      result.append(
        FoodEvidenceProvenance(field: field, sourceText: match.text, range: match.range)
      )
    }

    append(.identity, identity)
    append(.brand, brand)
    append(.preparation, preparation)
    for descriptor in descriptors {
      append(.descriptor, descriptor)
    }
    append(.quantity, quantity?.sourceText)
    append(.fraction, fractionSourceText)
    append(.container, containerSourceText)
    append(.alternateQuantity, alternateQuantity?.sourceText)
    return result
  }

  private static func sourceMatch(
    for sourceText: String,
    in normalizedSource: String
  ) -> (text: String, range: FoodEvidenceSourceRange)? {
    let words = sourceText.split(whereSeparator: \.isWhitespace).map(String.init)
    guard !words.isEmpty else { return nil }
    let pattern = words.map(NSRegularExpression.escapedPattern).joined(separator: #"\s*[- ]?\s*"#)
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
      let match = regex.firstMatch(
        in: normalizedSource,
        range: NSRange(
          normalizedSource.startIndex..<normalizedSource.endIndex, in: normalizedSource)
      ),
      let swiftRange = Range(match.range, in: normalizedSource)
    else { return nil }
    return (
      String(normalizedSource[swiftRange]),
      FoodEvidenceSourceRange(location: match.range.location, length: match.range.length)
    )
  }

  private struct LeadingIndefiniteArticle {
    let remainder: String
  }

  private static func leadingIndefiniteArticle(in text: String) -> LeadingIndefiniteArticle? {
    guard let match = captures(pattern: #"^(?:a|an)\s+(.+)$"#, in: text),
      let remainder = match[safe: 1] ?? nil
    else { return nil }
    return LeadingIndefiniteArticle(remainder: remainder)
  }

  private static func articleCanRepresentSingleCount(remainder: String) -> Bool {
    guard let noun = words(in: remainder).last else { return false }
    return articleCountNouns.contains(folded(noun))
  }

  private static func removingLeadingAmount(from text: String) -> String {
    let values = words(in: text)
    guard values.count >= 2 else { return text }
    let first = folded(values[0])
    let second = folded(values[1])
    if first.hasSuffix("%") || protectedNumericIdentityFollowers.contains(second) {
      return text
    }
    guard numericValue(first) != nil else { return text }

    var remainder = Array(values.dropFirst())
    if let firstRemainder = remainder.first {
      let family = UnitConversion.family(firstRemainder)
      let dimension = UnitConversion.dimension(of: firstRemainder)
      let shouldRemoveUnit =
        dimension == .mass || dimension == .volume || dimension == .serving
        || (genericMeasureUnits.contains(family) && remainder.count > 1)
      if shouldRemoveUnit {
        remainder.removeFirst()
        if remainder.first.map({ folded($0) == "of" }) == true { remainder.removeFirst() }
      }
    }
    return remainder.joined(separator: " ")
  }

  private static func removeLeadingArticle(from text: String) -> String {
    removeMatchWithoutRecording(pattern: #"^(?:a|an|the)\s+"#, from: text)
  }

  private static func cleanedIdentity(_ value: String) -> String? {
    var result = collapseWhitespace(value)
      .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    result = removeMatchWithoutRecording(pattern: #"^of\s+"#, from: result)
    return result.isEmpty ? nil : result
  }

  private static func isVagueNonIdentity(_ value: String?) -> Bool {
    guard let value else { return true }
    let normalized = folded(value)
      .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    return vagueNonIdentities.contains(normalized)
  }

  /// Rejects obvious conversation/control requests before they can become a USDA query. This is
  /// deliberately narrow: uncertainty falls through to the normal food pipeline rather than a
  /// broad English-language classifier.
  private static func isLikelyNonFoodRequest(_ value: String) -> Bool {
    if value.hasSuffix("?") { return true }
    if matches(pattern: #"^(?:hello|hi|hey)(?:\s+there)?[!.]?$"#, in: value) { return true }
    return matches(
      pattern: #"^(?:write|compose|repeat|explain|tell me|show me|set\s+productname)\b"#,
      in: value
    )
  }

  private static func fractionValue(_ value: String) -> Double? {
    switch folded(value) {
    case "half", "one half", "1/2", "½": 0.5
    case "quarter", "one quarter", "1/4", "¼": 0.25
    case "three quarters", "3/4", "¾": 0.75
    default: nil
    }
  }

  private static func numericValue(_ value: String) -> Double? {
    if let number = Double(value), number.isFinite { return number }
    return switch value {
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
    case "half": 0.5
    case "quarter": 0.25
    default: nil
    }
  }

  private static func words(in value: String) -> [String] {
    value.split { character in
      !character.isLetter && !character.isNumber && character != "/" && character != "%"
        && character != "-" && character != "."
    }.map(String.init)
  }

  private static func containsPhrase(_ phrase: String, in value: String) -> Bool {
    matches(
      pattern: #"(?:^|\b)"# + NSRegularExpression.escapedPattern(for: phrase) + #"(?:\b|$)"#,
      in: value)
  }

  private static func folded(_ value: String) -> String {
    value.folding(
      options: [.caseInsensitive, .diacriticInsensitive],
      locale: Locale(identifier: "en_US_POSIX")
    )
    .lowercased()
  }

  private static func collapseWhitespace(_ value: String) -> String {
    value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
  }

  private static func removeMatch(
    pattern: String,
    from value: String,
    recordingIn removed: inout [String]
  ) -> String {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
      return value
    }
    let range = NSRange(value.startIndex..<value.endIndex, in: value)
    guard let match = regex.firstMatch(in: value, range: range),
      let swiftRange = Range(match.range, in: value)
    else { return value }
    removed.append(String(value[swiftRange]).trimmingCharacters(in: .whitespacesAndNewlines))
    return String(value.replacingCharacters(in: swiftRange, with: ""))
  }

  private static func removeMatchWithoutRecording(pattern: String, from value: String) -> String {
    var ignored: [String] = []
    return removeMatch(pattern: pattern, from: value, recordingIn: &ignored)
  }

  private static func matches(pattern: String, in value: String) -> Bool {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
      return false
    }
    return regex.firstMatch(
      in: value,
      range: NSRange(value.startIndex..<value.endIndex, in: value)
    ) != nil
  }

  private static func captures(pattern: String, in value: String) -> [String?]? {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
      return nil
    }
    let fullRange = NSRange(value.startIndex..<value.endIndex, in: value)
    guard let match = regex.firstMatch(in: value, range: fullRange) else { return nil }
    return (0..<match.numberOfRanges).map { index in
      let range = match.range(at: index)
      guard range.location != NSNotFound, let swiftRange = Range(range, in: value) else {
        return nil
      }
      return String(value[swiftRange])
    }
  }
}

extension Array {
  fileprivate subscript(safe index: Index) -> Element? {
    indices.contains(index) ? self[index] : nil
  }
}
