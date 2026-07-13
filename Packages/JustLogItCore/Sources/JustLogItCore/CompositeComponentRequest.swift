import Foundation

/// Builds a per-component `ParsedFoodRequest` for composite meal lookup.
///
/// Component labels often keep a leading count from the original meal
/// ("1 Big Mac", "2 eggs"). The composite queue must not drop that quantity,
/// or selection always falls back to "Enter the amount you ate."
public enum CompositeComponentRequest {
  /// - Parameter label: One component name from `beginComposite` (may include amount).
  public static func make(from label: String) -> ParsedFoodRequest {
    let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return ParsedFoodRequest(productName: "", searchTerms: "")
    }

    if let parsed = leadingCount(in: trimmed) {
      return ParsedFoodRequest(
        productName: parsed.name,
        searchTerms: parsed.name,
        quantity: parsed.quantity,
        unit: parsed.unit,
        quantityText: parsed.quantityText
      )
    }

    // Bare component ("large fries", "side salad") → one serving by default.
    return ParsedFoodRequest(
      productName: trimmed,
      searchTerms: trimmed,
      quantity: 1,
      unit: "serving",
      quantityText: "1 serving"
    )
  }

  // MARK: - Private

  private struct LeadingCount {
    let quantity: Double
    let unit: String
    let name: String
    let quantityText: String
  }

  /// "1 Big Mac", "2 large eggs", "1.5 cups rice" — not "Big Mac".
  private static func leadingCount(in text: String) -> LeadingCount? {
    let pattern = #"^(\d+(?:[.,]\d+)?)\s+(.+)$"#
    guard let regex = try? NSRegularExpression(pattern: pattern),
      let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
      let qtyRange = Range(match.range(at: 1), in: text),
      let restRange = Range(match.range(at: 2), in: text)
    else { return nil }

    let qtyString = String(text[qtyRange]).replacingOccurrences(of: ",", with: ".")
    guard let quantity = Double(qtyString), quantity.isFinite, quantity > 0 else { return nil }

    let rest = String(text[restRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !rest.isEmpty else { return nil }

    // Optional unit token before the food name when it's a known measure/count word.
    let tokens = rest.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    if let first = tokens.first,
      tokens.count >= 2,
      isExplicitUnit(first)
    {
      let unit = first
      let name = tokens.dropFirst().joined(separator: " ")
      guard !name.isEmpty else { return nil }
      return LeadingCount(
        quantity: quantity,
        unit: unit,
        name: name,
        quantityText: "\(format(quantity)) \(unit)"
      )
    }

    // "1 Big Mac" → 1 item of Big Mac (not unit "Big").
    return LeadingCount(
      quantity: quantity,
      unit: "item",
      name: rest,
      quantityText: "\(format(quantity)) item"
    )
  }

  private static func isExplicitUnit(_ token: String) -> Bool {
    let dim = UnitConversion.dimension(of: token)
    switch dim {
    case .mass, .volume, .serving, .count:
      return true
    case .unknown:
      return false
    }
  }

  private static func format(_ value: Double) -> String {
    if value.rounded() == value { return String(Int(value)) }
    return String(format: "%g", value)
  }
}
