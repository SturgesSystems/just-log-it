import Foundation

/// Reorders USDA results using only the person's parsed lookup intent and result metadata.
/// The ranker never removes a result, so a weak USDA response remains selectable.
public struct FoodSearchResultRanker: Sendable {
  public init() {}

  public func rank(
    _ results: [FoodSearchResult],
    for parsed: ParsedFoodRequest,
    preferredFdcIDs: Set<Int> = []
  ) -> [FoodSearchResult] {
    let intent = Intent(parsed)
    return results.enumerated()
      .map {
        (
          index: $0.offset,
          result: $0.element,
          score: score($0.element, intent: intent, preferredFdcIDs: preferredFdcIDs)
        )
      }
      .sorted {
        if $0.score != $1.score { return $0.score > $1.score }
        return $0.index < $1.index
      }
      .map(\.result)
  }

  /// Bounded boost for previously confirmed FDC IDs. Never removes results or auto-selects.
  public static let rememberedSelectionBoost = 50

  private func score(
    _ result: FoodSearchResult,
    intent: Intent,
    preferredFdcIDs: Set<Int>
  ) -> Int {
    let descriptionTokens = Self.tokens(result.description)
    guard !intent.productTokens.isEmpty else {
      return preferredFdcIDs.contains(result.fdcID) ? Self.rememberedSelectionBoost : 0
    }

    let matchedProductCount = intent.productTokens.filter { queryToken in
      descriptionTokens.contains { Self.matches(queryToken, $0) }
    }.count
    let productCoverage = matchedProductCount * 100 / intent.productTokens.count
    var score = productCoverage * 4

    // The last product token is generally the food form: cookie, milk, breast, pizza, and so on.
    if let foodForm = intent.productTokens.last,
      descriptionTokens.contains(where: { Self.matches(foodForm, $0) })
    {
      score += 80
    }

    let qualifierMatches = intent.qualifierTokens.filter { queryToken in
      descriptionTokens.contains { Self.matches(queryToken, $0) }
    }.count
    score += qualifierMatches * 18

    if !intent.brandTokens.isEmpty {
      let brandTokens = Self.tokens(
        [result.brandName, result.brandOwner, result.description]
          .compactMap { $0 }
          .joined(separator: " ")
      )
      let brandMatches = intent.brandTokens.filter { queryToken in
        brandTokens.contains { Self.matches(queryToken, $0) }
      }.count
      score += brandMatches * 45
      if brandMatches == 0, result.brandName != nil || result.brandOwner != nil {
        score -= 60
      }
    }

    if let firstProductIndex = descriptionTokens.firstIndex(where: { resultToken in
      intent.productTokens.contains { Self.matches($0, resultToken) }
    }) {
      let leadingTokens = descriptionTokens[..<firstProductIndex]
      let hasContainmentMarker = leadingTokens.contains(where: Self.containmentMarkers.contains)
      if hasContainmentMarker {
        // "Dessert with cookie" is a composite dish; "cookie with chocolate" is still a cookie.
        score -= 220
      }

      let relevantLeadingTokens = leadingTokens.filter { token in
        !Self.connectorTokens.contains(token)
          && !intent.brandTokens.contains(where: { Self.matches($0, token) })
          && !intent.qualifierTokens.contains(where: { Self.matches($0, token) })
      }
      score -= min(relevantLeadingTokens.count * 12, 72)
    }

    if preferredFdcIDs.contains(result.fdcID) {
      score += Self.rememberedSelectionBoost
    }

    return score
  }
}

extension FoodSearchResultRanker {
  fileprivate struct Intent {
    let productTokens: [String]
    let brandTokens: [String]
    let qualifierTokens: [String]

    init(_ parsed: ParsedFoodRequest) {
      let product = FoodSearchResultRanker.contentTokens(parsed.productName)
      productTokens =
        product.isEmpty
        ? FoodSearchResultRanker.contentTokens(parsed.searchTerms)
        : product
      brandTokens = FoodSearchResultRanker.contentTokens(parsed.brand ?? "")
      qualifierTokens = FoodSearchResultRanker.contentTokens(
        ([parsed.preparation] + parsed.descriptors.map(Optional.some))
          .compactMap { $0 }
          .joined(separator: " ")
      )
    }
  }

  fileprivate static let connectorTokens: Set<String> = [
    "a", "an", "and", "containing", "contains", "for", "in", "made", "of", "the", "with",
  ]

  fileprivate static let containmentMarkers: Set<String> = [
    "containing", "contains", "featuring", "includes", "topped", "with",
  ]

  fileprivate static func tokens(_ value: String) -> [String] {
    value.precomposedStringWithCanonicalMapping
      .lowercased()
      .unicodeScalars
      .map { CharacterSet.alphanumerics.contains($0) ? String($0) : " " }
      .joined()
      .split(whereSeparator: { $0.isWhitespace })
      .map(String.init)
  }

  fileprivate static func contentTokens(_ value: String) -> [String] {
    tokens(value).filter { !connectorTokens.contains($0) }
  }

  fileprivate static func matches(_ lhs: String, _ rhs: String) -> Bool {
    !tokenForms(lhs).isDisjoint(with: tokenForms(rhs))
  }

  fileprivate static func tokenForms(_ token: String) -> Set<String> {
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
