import Foundation

/// Fills in a missing amount when the person named a food without a count
/// ("a Big Mac", "oatmeal") so logging can proceed to review. They can change
/// the amount later; we do not block on a quantity question for bare identity.
public enum ParsedQuantityDefault {
  /// When neither quantity nor fraction is set, assume **1 serving**.
  public static func applyingDefaultIfNeeded(_ parsed: ParsedFoodRequest) -> ParsedFoodRequest {
    if parsed.quantity != nil || parsed.fractionOfWhole != nil {
      return parsed
    }
    var next = parsed
    next.quantity = 1
    next.unit = next.unit ?? "serving"
    if next.quantityText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
      next.quantityText = "1 \(next.unit ?? "serving")"
    }
    next.quantityNeedsClarification = false
    return next
  }
}

/// Decides when the top USDA hit is confident enough to skip the picker.
///
/// Auto-select is for strong identity matches (multi-token product, stated brand,
/// remembered FDC, or a single hit). Generic one-word foods stay on the picker.
public enum FoodSearchAutoSelect {
  public static func highConfidencePick(
    ranked: [FoodSearchResult],
    for parsed: ParsedFoodRequest,
    preferredFdcIDs: Set<Int> = []
  ) -> FoodSearchResult? {
    guard let top = ranked.first else { return nil }

    if preferredFdcIDs.contains(top.fdcID) {
      return top
    }
    if let remembered = ranked.first(where: { preferredFdcIDs.contains($0.fdcID) }) {
      return remembered
    }

    let intentTokens = productTokens(for: parsed)
    guard !intentTokens.isEmpty else { return nil }
    guard tokensMatchAll(intentTokens, in: top.description) else { return nil }

    if let brand = parsed.brand?.trimmingCharacters(in: .whitespacesAndNewlines), !brand.isEmpty {
      let brandHay = [top.brandName, top.brandOwner, top.description]
        .compactMap { $0 }
        .joined(separator: " ")
      let brandTokens = contentTokens(brand)
      guard !brandTokens.isEmpty, tokensMatchAll(brandTokens, in: brandHay) else { return nil }
      return top
    }

    // Single clear hit after ranking.
    if ranked.count == 1 { return top }

    // Multi-token products ("big mac", "oreo cookie") — identity is specific enough.
    if intentTokens.count >= 2 { return top }

    // One-word generic ("rice", "eggs", "milk") → keep the picker.
    return nil
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
    let hay = tokens(haystack)
    return query.allSatisfy { q in
      hay.contains { matches(q, $0) }
    }
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
