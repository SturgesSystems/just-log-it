import Foundation

/// One USDA `foodPortions[]` row (SR Legacy / FNDDS / Foundation).
/// Branded foods usually use `servingSize` + `householdServingFullText` instead.
public struct USDAFoodPortion: Sendable, Equatable, Codable {
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
  enum MatchOutcome: Equatable {
    case matched(USDAFoodPortion, portionAmount: Double)
    case ambiguous
    case none
  }

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

  /// Selects a USDA portion that actually describes the user's unit, instead of relying on
  /// the single portion chosen as the record's default serving. This matters for records that
  /// publish alternatives such as `1 cup`, `1 tbsp`, and `1 large egg`.
  static func match(
    userUnit: String,
    quantityText: String?,
    descriptors: [String],
    portions: [USDAFoodPortion]
  ) -> MatchOutcome {
    let userFamily = UnitConversion.family(userUnit)
    let userDimension = UnitConversion.dimension(of: userUnit)
    guard userDimension == .count || userDimension == .volume else { return .none }

    let requestTokens = tokens(
      ([quantityText] + descriptors).compactMap { $0 }.joined(separator: " "))
    let requestedSizes = sizeTokens(in: requestTokens)
    let genericWholeUnits: Set<String> = ["item", "each", "piece"]

    let candidates:
      [(
        portion: USDAFoodPortion, amount: Double, semanticScore: Int, metadataScore: Int
      )] = portions.compactMap { portion in
        guard let grams = portion.gramWeight, grams.isFinite, grams > 0,
          let text = householdText(for: portion),
          !isUnspecifiedQuantity(text)
        else { return nil }

        // USDA is inconsistent about where it puts the useful noun/size: some records use
        // `portionDescription`, others use `modifier` or `measureUnit`. Consider all of them.
        let semanticText = [
          text, portion.modifier, portion.measureUnitName, portion.measureUnitAbbreviation,
        ].compactMap(nonEmpty).joined(separator: " ")
        let portionTokens = tokens(semanticText)
        let portionFamilies = portionTokens.map(UnitConversion.family)
        let portionDimensions = portionTokens.map(UnitConversion.dimension)
        let exactFamily = portionFamilies.contains(userFamily)
        let compatibleFamily = portionTokens.contains {
          UnitConversion.unitsCompatible(userUnit, $0)
        }
        let descriptiveGenericItem =
          genericWholeUnits.contains(userFamily)
          && !portionDimensions.contains(.mass)
          && !portionDimensions.contains(.volume)
          && !portionDimensions.contains(.serving)

        guard exactFamily || compatibleFamily || descriptiveGenericItem else { return nil }

        let candidateSizes = sizeTokens(in: portionTokens)
        if !requestedSizes.isEmpty, !candidateSizes.isEmpty,
          requestedSizes.isDisjoint(with: candidateSizes)
        {
          return nil
        }

        let amount = positive(portion.amount) ?? leadingAmount(in: tokens(text)) ?? 1
        var semanticScore = exactFamily ? 100 : (compatibleFamily ? 70 : 30)
        semanticScore += requestedSizes.intersection(candidateSizes).count * 60
        return (portion, amount, semanticScore, score(portion))
      }

    guard let bestSemanticScore = candidates.map(\.semanticScore).max() else { return .none }
    let semanticallyBest = candidates.filter { $0.semanticScore == bestSemanticScore }
    guard let first = semanticallyBest.first else { return .none }

    // Incidental USDA metadata (a modifier, measure name, or amount near one) must not choose
    // between semantically equivalent portions with different weights. First establish that
    // all equally compatible rows mean the same grams per unit; only then use metadata as a
    // deterministic tie-breaker.
    let firstGramsPerUnit = (first.portion.gramWeight ?? 0) / first.amount
    let materiallyDifferent = semanticallyBest.dropFirst().contains {
      guard let grams = $0.portion.gramWeight else { return false }
      return abs((grams / $0.amount) - firstGramsPerUnit) > 0.01
    }
    guard !materiallyDifferent else { return .ambiguous }
    let chosen =
      semanticallyBest.max { lhs, rhs in
        lhs.metadataScore < rhs.metadataScore
      } ?? first
    return .matched(chosen.portion, portionAmount: chosen.amount)
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

  private static func tokens(_ text: String) -> [String] {
    text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
      .split { !$0.isLetter && !$0.isNumber && $0 != "/" }
      .map(String.init)
  }

  private static func sizeTokens(in tokens: [String]) -> Set<String> {
    var sizes = Set<String>()
    for (index, token) in tokens.enumerated() {
      switch token {
      case "small", "medium", "jumbo":
        sizes.insert(token)
      case "large":
        let isExtraLarge = index > 0 && tokens[index - 1] == "extra"
        sizes.insert(isExtraLarge ? "extra-large" : "large")
      default:
        continue
      }
    }
    return sizes
  }

  private static func positive(_ value: Double?) -> Double? {
    guard let value, value.isFinite, value > 0 else { return nil }
    return value
  }

  private static func leadingAmount(in tokens: [String]) -> Double? {
    guard let token = tokens.first else { return nil }
    if let value = Double(token), value.isFinite, value > 0 { return value }
    let pieces = token.split(separator: "/")
    if pieces.count == 2,
      let numerator = Double(pieces[0]),
      let denominator = Double(pieces[1]),
      denominator > 0
    {
      return numerator / denominator
    }
    return nil
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
