import Foundation

/// One USDA `foodPortions[]` row (SR Legacy / FNDDS / Foundation).
/// Branded foods usually use `servingSize` + `householdServingFullText` instead.
public struct USDAFoodPortion: Sendable, Equatable {
  public let gramWeight: Double?
  public let amount: Double?
  public let modifier: String?
  public let portionDescription: String?
  public let measureUnitName: String?
  public let measureUnitAbbreviation: String?

  public init(
    gramWeight: Double? = nil,
    amount: Double? = nil,
    modifier: String? = nil,
    portionDescription: String? = nil,
    measureUnitName: String? = nil,
    measureUnitAbbreviation: String? = nil
  ) {
    self.gramWeight = gramWeight
    self.amount = amount
    self.modifier = modifier
    self.portionDescription = portionDescription
    self.measureUnitName = measureUnitName
    self.measureUnitAbbreviation = measureUnitAbbreviation
  }
}

/// Fills missing branded-style serving fields from USDA `foodPortions`.
///
/// SR Legacy / Survey foods often omit `servingSize` and `householdServingFullText`
/// but list gram weights on portions (e.g. Big Mac → 219 g / item). Without this,
/// "1 serving" cannot resolve and nutrition stays stuck.
public enum FoodPortionServing {
  public struct Resolved: Sendable, Equatable {
    public let servingSize: Double?
    public let servingSizeUnit: String?
    public let householdServing: String?

    public init(
      servingSize: Double? = nil,
      servingSizeUnit: String? = nil,
      householdServing: String? = nil
    ) {
      self.servingSize = servingSize
      self.servingSizeUnit = servingSizeUnit
      self.householdServing = householdServing
    }
  }

  /// Prefer labeled serving fields; when size or household is missing, fill from portions.
  public static func resolve(
    servingSize: Double?,
    servingSizeUnit: String?,
    householdServing: String?,
    portions: [USDAFoodPortion]
  ) -> Resolved {
    let labeledSize =
      (servingSize.flatMap { $0.isFinite && $0 > 0 ? $0 : nil })
    let labeledUnit = nonEmpty(servingSizeUnit)
    let labeledHousehold = nonEmpty(householdServing)

    if let labeledSize, let labeledUnit {
      return Resolved(
        servingSize: labeledSize,
        servingSizeUnit: labeledUnit,
        householdServing: labeledHousehold
      )
    }

    guard let portion = preferredPortion(portions),
      let grams = portion.gramWeight, grams.isFinite, grams > 0
    else {
      return Resolved(
        servingSize: labeledSize,
        servingSizeUnit: labeledUnit,
        householdServing: labeledHousehold
      )
    }

    return Resolved(
      servingSize: grams,
      servingSizeUnit: "g",
      householdServing: labeledHousehold ?? householdText(for: portion)
    )
  }

  /// Best default portion: positive grams, real description over "Quantity not specified",
  /// prefer amount ≈ 1 (a single item/serving).
  public static func preferredPortion(_ portions: [USDAFoodPortion]) -> USDAFoodPortion? {
    let viable = portions.filter {
      guard let g = $0.gramWeight else { return false }
      return g.isFinite && g > 0
    }
    guard !viable.isEmpty else { return nil }
    return viable.max(by: { score($0) < score($1) })
  }

  public static func householdText(for portion: USDAFoodPortion) -> String? {
    if let description = nonEmpty(portion.portionDescription),
      !isUnspecifiedQuantity(description)
    {
      return description
    }

    let amount = portion.amount.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? 1
    if let modifier = nonEmpty(portion.modifier) {
      return "\(formatAmount(amount)) \(modifier)"
    }

    if let unit = nonEmpty(portion.measureUnitAbbreviation) ?? nonEmpty(portion.measureUnitName),
      !isUndeterminedMeasure(unit)
    {
      return "\(formatAmount(amount)) \(unit)"
    }

    return "1 serving"
  }

  // MARK: - Private

  private static func score(_ portion: USDAFoodPortion) -> Int {
    var value = 0
    if let description = nonEmpty(portion.portionDescription) {
      value += isUnspecifiedQuantity(description) ? -50 : 100
    }
    if let amount = portion.amount, amount.isFinite, amount > 0 {
      if amount <= 1.01 { value += 30 } else if amount <= 2 { value += 10 }
    } else {
      value += 15
    }
    if nonEmpty(portion.modifier) != nil { value += 10 }
    if let unit = nonEmpty(portion.measureUnitName) ?? nonEmpty(portion.measureUnitAbbreviation),
      !isUndeterminedMeasure(unit)
    {
      value += 10
    }
    // Prefer a typical sandwich/item weight over multi-item bulk when scores tie-ish.
    if let grams = portion.gramWeight, grams.isFinite, grams > 0, grams <= 400 {
      value += 5
    }
    return value
  }

  private static func isUnspecifiedQuantity(_ text: String) -> Bool {
    text.lowercased().contains("quantity not specified")
  }

  private static func isUndeterminedMeasure(_ text: String) -> Bool {
    text.lowercased() == "undetermined"
  }

  private static func nonEmpty(_ text: String?) -> String? {
    guard let text else { return nil }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  private static func formatAmount(_ value: Double) -> String {
    if value.rounded() == value { return String(Int(value)) }
    return String(format: "%g", value)
  }
}
