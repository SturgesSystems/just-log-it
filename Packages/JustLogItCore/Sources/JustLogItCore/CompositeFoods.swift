import Foundation

/// Immutable nutrition snapshot for one confirmed component of a composite meal.
public struct CompositeComponentSnapshot: Codable, Sendable, Equatable {
  public var displayName: String
  public var brand: String?
  public var fdcID: Int?
  public var quantityDisplay: String
  public var nutrients: [NutrientAmount]
  public var isApproximate: Bool

  public init(
    displayName: String,
    brand: String? = nil,
    fdcID: Int? = nil,
    quantityDisplay: String,
    nutrients: [NutrientAmount],
    isApproximate: Bool = false
  ) {
    self.displayName = displayName
    self.brand = brand
    self.fdcID = fdcID
    self.quantityDisplay = quantityDisplay
    self.nutrients = nutrients
    self.isApproximate = isApproximate
  }
}

/// Transient draft for a multi-component meal prior to confirmation.
public struct CompositeDraft: Sendable, Equatable {
  public var name: String
  public var components: [CompositeComponentSnapshot]
  public var totalNutrients: [NutrientAmount]

  public init(
    name: String,
    components: [CompositeComponentSnapshot],
    totalNutrients: [NutrientAmount]
  ) {
    self.name = name
    self.components = components
    self.totalNutrients = totalNutrients
  }
}

/// Deterministic nutrient summation across component snapshots.
///
/// Missing nutrients in a component are omitted (not treated as zero). Nonfinite
/// and negative amounts are discarded. Results are ordered by `NutrientKey` case order.
public enum NutrientAggregation {
  public static func sum(_ components: [[NutrientAmount]]) -> [NutrientAmount] {
    var totals: [NutrientKey: (amount: Double, unit: String)] = [:]

    for nutrientList in components {
      for nutrient in nutrientList {
        guard nutrient.amount.isFinite, nutrient.amount >= 0 else { continue }
        let unit = nutrient.unit.isEmpty ? nutrient.key.canonicalUnit : nutrient.unit
        if var existing = totals[nutrient.key] {
          // Prefer the first seen unit for a key; amounts are assumed already normalized.
          existing.amount += nutrient.amount
          totals[nutrient.key] = existing
        } else {
          totals[nutrient.key] = (nutrient.amount, unit)
        }
      }
    }

    return NutrientKey.allCases.compactMap { key in
      guard let total = totals[key], total.amount.isFinite, total.amount >= 0 else { return nil }
      return NutrientAmount(key: key, amount: total.amount, unit: total.unit)
    }
  }
}

/// Builds a `CompositeDraft` with aggregated totals from confirmed components.
public enum CompositeDraftBuilder {
  /// Default display name when the user has not supplied one.
  public static func defaultName(for components: [CompositeComponentSnapshot]) -> String {
    let names = components.map(\.displayName).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    guard !names.isEmpty else { return "Meal" }
    if names.count == 1 { return names[0] }
    if names.count == 2 { return "\(names[0]) + \(names[1])" }
    return "\(names[0]) + \(names.count - 1) more"
  }

  public static func make(
    name: String? = nil,
    components: [CompositeComponentSnapshot]
  ) -> CompositeDraft {
    let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let resolvedName = trimmed.isEmpty ? defaultName(for: components) : trimmed
    return CompositeDraft(
      name: resolvedName,
      components: components,
      totalNutrients: NutrientAggregation.sum(components.map(\.nutrients))
    )
  }

  /// Convenience when multi-food clarification yields several confirmed component snapshots.
  public static func makeFromMultiFoodConfirmation(
    sourceText: String,
    components: [CompositeComponentSnapshot]
  ) -> CompositeDraft {
    let trimmed = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
    return make(name: trimmed.isEmpty ? nil : trimmed, components: components)
  }
}
