import Foundation

public struct FoodSearchQueryBuilder: Sendable {
  public init() {}

  public func build(from parsed: ParsedFoodRequest, page: Int = 1) -> FoodSearchRequest {
    let fields =
      [parsed.brand, parsed.productName, parsed.preparation] + parsed.descriptors.map(Optional.some)
    var seen = Set<String>()
    var tokens: [String] = []

    for field in fields.compactMap({ $0 }) {
      for token in displayTokens(field) {
        let key = normalizedToken(token)
        guard !key.isEmpty, seen.insert(key).inserted else { continue }
        tokens.append(token)
      }
    }

    let query = tokens.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    let fallback = normalizeDisplay(
      parsed.searchTerms.isEmpty ? parsed.productName : parsed.searchTerms)
    let displayQuery = query.isEmpty ? fallback : query
    let normalizedKey = normalizedCacheKey(displayQuery)
    let types =
      parsed.brand?.isEmpty == false
      ? ["Branded"] : ["Foundation", "SR Legacy", "Survey (FNDDS)", "Branded"]
    return FoodSearchRequest(
      query: displayQuery, normalizedKey: normalizedKey, dataTypes: types, page: max(1, page),
      pageSize: Self.defaultPageSize)
  }

  public func manual(_ input: String, page: Int = 1) -> FoodSearchRequest {
    let query = normalizeDisplay(input)
    return FoodSearchRequest(
      query: query, normalizedKey: normalizedCacheKey(query), dataTypes: [], page: max(1, page),
      pageSize: Self.defaultPageSize)
  }

  /// Matches proxy `MAX_PAGE_SIZE` and USDA-friendly list size for the chat picker.
  public static let defaultPageSize = 50

  public func normalizedCacheKey(_ value: String) -> String {
    value.precomposedStringWithCanonicalMapping
      .lowercased()
      .replacingOccurrences(of: "’", with: "'")
      .unicodeScalars
      .map { CharacterSet.alphanumerics.contains($0) ? String($0) : " " }
      .joined()
      .split(whereSeparator: { $0.isWhitespace })
      .joined(separator: " ")
  }

  private func normalizeDisplay(_ value: String) -> String {
    value.precomposedStringWithCanonicalMapping
      .replacingOccurrences(of: "’", with: "'")
      .split(whereSeparator: { $0.isWhitespace })
      .joined(separator: " ")
  }

  private func displayTokens(_ value: String) -> [String] {
    normalizeDisplay(value)
      .split(separator: " ")
      .map(String.init)
      .filter { !$0.isEmpty }
  }

  private func normalizedToken(_ value: String) -> String {
    normalizedCacheKey(value)
  }
}
