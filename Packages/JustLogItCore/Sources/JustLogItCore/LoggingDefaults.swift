import Foundation

/// Fills in a missing amount only after a selected food proves that “one serving”
/// has a usable nutrition basis. Before USDA details exist, missing stays missing.
public enum ParsedQuantityDefault {
  public static func applyingDefaultIfNeeded(
    _ parsed: ParsedFoodRequest,
    sourceText: String? = nil,
    selectedFood: FoodDetails? = nil
  ) -> ParsedFoodRequest {
    if parsed.quantity != nil || parsed.fractionOfWhole != nil {
      return parsed
    }
    if let sourceText,
      ParsedQuantityRecovery.containsExplicitAmount(in: sourceText, for: parsed)
    {
      return parsed
    }
    guard let selectedFood, hasUsableServingBasis(selectedFood) else { return parsed }

    var next = parsed
    next.quantity = 1
    next.unit = next.unit ?? "serving"
    if next.quantityText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
      next.quantityText = "1 \(next.unit ?? "serving")"
    }
    next.quantityNeedsClarification = false
    return next
  }

  private static func hasUsableServingBasis(_ food: FoodDetails) -> Bool {
    let hasEnergy = food.nutrientsPerServing.contains {
      $0.key == .energy && $0.amount.isFinite && $0.amount >= 0
    }
    guard hasEnergy else { return false }

    // A preferred/labeled USDA serving is not proof that it represents the
    // user's unstated quantity when the same food exposes materially different
    // portions (for example small egg, large egg, and cup). In that case the
    // user still needs to say which portion they ate.
    guard hasUnambiguousPortions(food.foodPortions) else { return false }

    let hasSizedServing = food.servingSize.map { $0.isFinite && $0 > 0 } == true
      && food.servingSizeUnit?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    let hasHouseholdServing =
      food.householdServing?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    let hasPortion = food.foodPortions.contains {
      $0.gramWeight.map { $0.isFinite && $0 > 0 } == true
    }
    return hasSizedServing || hasHouseholdServing || hasPortion
  }

  private static func hasUnambiguousPortions(_ portions: [USDAFoodPortion]) -> Bool {
    guard !portions.isEmpty else { return true }

    let gramsPerUnit = portions.compactMap { portion -> Double? in
      guard let grams = portion.gramWeight, grams.isFinite, grams > 0 else { return nil }
      let amount = portion.amount ?? 1
      guard amount.isFinite, amount > 0 else { return nil }
      return grams / amount
    }
    guard !gramsPerUnit.isEmpty else { return false }
    guard let minimum = gramsPerUnit.min(), let maximum = gramsPerUnit.max() else { return false }

    let tolerance = max(1, maximum * 0.01)
    return maximum - minimum <= tolerance
  }
}

/// Decides when the top USDA hit is confident enough to skip the picker.
///
/// Auto-select is reserved for one unique, exact, distinctive identity. A sole
/// result is not evidence by itself, and derivative or close alternatives keep
/// the picker visible. Remembered choices never grant selection permission.
public enum FoodSearchAutoSelect {
  public static func highConfidencePick(
    ranked: [FoodSearchResult],
    for parsed: ParsedFoodRequest,
    preferredFdcIDs: Set<Int> = []
  ) -> FoodSearchResult? {
    guard let top = ranked.first else { return nil }

    if ranked.contains(where: { preferredFdcIDs.contains($0.fdcID) }) {
      return nil
    }

    let intentTokens = identityTokens(for: parsed)
    guard !intentTokens.isEmpty, isStrongExactMatch(top, parsed: parsed, intent: intentTokens)
    else { return nil }

    let hasCloseAlternative = ranked.dropFirst().contains {
      isCompetingMatch($0, parsed: parsed, intent: intentTokens)
    }
    return hasCloseAlternative ? nil : top
  }

  // MARK: - Token helpers (aligned with FoodSearchResultRanker)

  private static let connectorTokens: Set<String> = [
    "a", "an", "and", "containing", "contains", "for", "in", "made", "of", "the", "with",
  ]

  private static func productTokens(for parsed: ParsedFoodRequest) -> [String] {
    let product = contentTokens(parsed.productName)
    if !product.isEmpty { return product }
    return contentTokens(parsed.searchTerms)
  }

  private static func identityTokens(for parsed: ParsedFoodRequest) -> [String] {
    var result = productTokens(for: parsed)
    let qualifiers = [parsed.preparation] + parsed.descriptors.map(Optional.some)
    for token in contentTokens(qualifiers.compactMap { $0 }.joined(separator: " "))
    where !result.contains(where: { matches($0, token) }) {
      result.append(token)
    }
    return result
  }

  private static func isStrongExactMatch(
    _ result: FoodSearchResult,
    parsed: ParsedFoodRequest,
    intent: [String]
  ) -> Bool {
    let brand = contentTokens(parsed.brand ?? "")
    if !brand.isEmpty {
      let metadata = contentTokens(
        [result.brandName, result.brandOwner].compactMap { $0 }.joined(separator: " "))
      guard tokensMatchAll(brand, inTokens: metadata) else { return false }
    } else {
      // A generic single-token identity is never strong enough to choose nutrition.
      guard intent.count >= 2 else { return false }
    }

    var candidate = contentTokens(removingParentheticalText(from: result.description))
    if !brand.isEmpty {
      candidate.removeAll { token in brand.contains(where: { matches($0, token) }) }
    }
    return tokensMatchExactly(intent, candidate)
  }

  private static func isCompetingMatch(
    _ result: FoodSearchResult,
    parsed: ParsedFoodRequest,
    intent: [String]
  ) -> Bool {
    let brand = contentTokens(parsed.brand ?? "")
    if !brand.isEmpty {
      let metadata = contentTokens(
        [result.brandName, result.brandOwner].compactMap { $0 }.joined(separator: " "))
      guard tokensMatchAll(brand, inTokens: metadata) else { return false }
    }
    return tokensMatchAll(intent, in: result.description)
  }

  private static func contentTokens(_ value: String) -> [String] {
    tokens(value).filter { !connectorTokens.contains($0) }
  }

  private static func tokens(_ value: String) -> [String] {
    value.precomposedStringWithCanonicalMapping
      .lowercased()
      .unicodeScalars
      .map { CharacterSet.alphanumerics.contains($0) ? String($0) : " " }
      .joined()
      .split(whereSeparator: { $0.isWhitespace })
      .map(String.init)
  }

  private static func tokensMatchAll(_ query: [String], in haystack: String) -> Bool {
    tokensMatchAll(query, inTokens: tokens(haystack))
  }

  private static func tokensMatchAll(_ query: [String], inTokens haystack: [String]) -> Bool {
    query.allSatisfy { q in haystack.contains { matches(q, $0) } }
  }

  private static func tokensMatchExactly(_ lhs: [String], _ rhs: [String]) -> Bool {
    guard lhs.count == rhs.count else { return false }
    var remaining = rhs
    for token in lhs {
      guard let index = remaining.firstIndex(where: { matches(token, $0) }) else { return false }
      remaining.remove(at: index)
    }
    return remaining.isEmpty
  }

  private static func removingParentheticalText(from value: String) -> String {
    var result = ""
    var depth = 0
    for character in value {
      if character == "(" {
        depth += 1
      } else if character == ")" {
        depth = max(0, depth - 1)
      } else if depth == 0 {
        result.append(character)
      }
    }
    return result
  }

  private static func matches(_ lhs: String, _ rhs: String) -> Bool {
    !tokenForms(lhs).isDisjoint(with: tokenForms(rhs))
  }

  private static func tokenForms(_ token: String) -> Set<String> {
    var forms: Set<String> = [token]
    if token.count > 3, token.hasSuffix("s") {
      forms.insert(String(token.dropLast()))
    }
    if token.count > 4, token.hasSuffix("ies") {
      forms.insert(String(token.dropLast(3)) + "y")
    }
    if token.count > 4, token.hasSuffix("es") {
      forms.insert(String(token.dropLast(2)))
    }
    return forms
  }
}
