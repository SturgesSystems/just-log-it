import Foundation
import JustLogItCore

/// Builds a privacy-respecting plain-text export for a single food log entry.
///
/// On-device only: no analytics, cloud, HealthKit diagnostics, or multi-entry history.
enum FoodLogEntryShareText {
  private static let macroKeys: [NutrientKey] = [
    .energy, .protein, .carbohydrate, .totalFat,
  ]

  /// Human-readable plain text for sharing one entry via the system share sheet.
  static func plainText(for entry: FoodLogEntryRecord) -> String {
    var lines: [String] = [entry.displayName]

    if let brand = entry.brand?.trimmingCharacters(in: .whitespacesAndNewlines), !brand.isEmpty {
      lines.append(brand)
    }

    lines.append("Amount: \(entry.quantityDisplay)")
    lines.append(
      "Logged: \(entry.consumedAt.formatted(date: .abbreviated, time: .shortened))"
    )

    let macroLines = macroKeys.compactMap { key -> String? in
      guard let nutrient = entry.nutrients.first(where: { $0.key == key }) else { return nil }
      let amount = nutrient.amount.formatted(.number.precision(.fractionLength(0...1)))
      return "\(key.displayName): \(amount) \(nutrient.unit)"
    }
    if !macroLines.isEmpty {
      lines.append("")
      lines.append(contentsOf: macroLines)
    }

    let original = entry.originalText.trimmingCharacters(in: .whitespacesAndNewlines)
    if !original.isEmpty {
      lines.append("")
      lines.append("Original: \(original)")
    }

    return lines.joined(separator: "\n")
  }
}
