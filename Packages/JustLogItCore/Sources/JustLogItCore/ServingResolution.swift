import Foundation

public enum CalculationBasis: String, Sendable, Codable {
  case servings
  case grams
  case manual
}

public struct ServingResolution: Sendable, Equatable, Codable {
  public let basis: CalculationBasis
  public let servingMultiplier: Double?
  public let consumedGrams: Double?
  public let displayText: String

  public init(
    basis: CalculationBasis, servingMultiplier: Double?, consumedGrams: Double?, displayText: String
  ) {
    self.basis = basis
    self.servingMultiplier = servingMultiplier
    self.consumedGrams = consumedGrams
    self.displayText = displayText
  }
}

public enum ServingResolutionOutcome: Sendable, Equatable {
  case resolved(ServingResolution)
  case needsClarification(String)
}

/// Maps a grounded quantity onto a USDA food's serving / mass basis.
///
/// **Exact:**
/// - Mass ↔ mass, volume ↔ volume via `UnitConversion`
/// - User volume × (USDA grams ÷ household volume) when household is also volume
/// - Count matches when unit families match (cookie, egg, …)
///
/// **Approximate (last resort, display marked):**
/// - User volume when USDA only lists mass + a non-volume household (e.g. "1 pack (200 g)")
///   using published culinary grams-per-cup for common cooked staples (rice, oats, …).
///   A pack mass is **not** the same as “1 cup” — that path never equates pack=cup.
public struct ServingResolutionService: Sendable {
  public init() {}

  public func resolve(_ parsed: ParsedFoodRequest, against food: FoodDetails)
    -> ServingResolutionOutcome
  {
    // 1) Fraction of an explicitly sized container (½ of a 12 oz bottle → mass).
    if let fraction = parsed.fractionOfWhole,
      let containerSize = parsed.containerSize,
      let containerUnit = parsed.containerSizeUnit,
      let grams = UnitConversion.toGrams(
        quantity: fraction * containerSize, unit: containerUnit)
    {
      let display =
        parsed.quantityText
        ?? "\(format(fraction)) of a \(format(containerSize)) \(containerUnit) container"
      return resolveMass(grams, food: food, display: display)
    }

    // 2) User amount already in mass units.
    if let quantity = parsed.quantity, let unit = parsed.unit,
      let grams = UnitConversion.toGrams(quantity: quantity, unit: unit)
    {
      return resolveMass(
        grams, food: food, display: parsed.quantityText ?? "\(format(quantity)) \(unit)")
    }

    // 3) Resolve against the complete USDA portion list. A record's preferred/default
    // serving may be `1 cup`, while another row is the user's exact `1 large egg`.
    if let quantity = parsed.quantity, let unit = parsed.unit, !food.foodPortions.isEmpty {
      switch FoodPortionServing.match(
        userUnit: unit,
        quantityText: parsed.quantityText,
        descriptors: parsed.descriptors,
        portions: food.foodPortions
      ) {
      case .matched(let portion, let portionAmount):
        guard let grams = portion.gramWeight else { break }
        let display = parsed.quantityText ?? "\(format(quantity)) \(unit)"
        return resolveMass(grams * (quantity / portionAmount), food: food, display: display)
      case .ambiguous:
        return .needsClarification(
          "USDA lists more than one matching size for this food. Choose a size or enter grams."
        )
      case .none:
        break
      }
    }

    // 4) User volume + household volume + gram serving → exact scale for this food.
    if let quantity = parsed.quantity, let unit = parsed.unit,
      UnitConversion.dimension(of: unit) == .volume,
      let household = householdAmount(food.householdServing),
      UnitConversion.dimension(of: household.unit) == .volume,
      let oneServingG = servingGrams(food)
    {
      if let userML = UnitConversion.toMilliliters(quantity: quantity, unit: unit),
        let householdML = UnitConversion.toMilliliters(
          quantity: household.amount, unit: household.unit),
        householdML > 0
      {
        let display = parsed.quantityText ?? "\(format(quantity)) \(unit)"
        return resolveMass(oneServingG * (userML / householdML), food: food, display: display)
      }
    }

    // 5) User count/volume-as-count matches USDA household text (2 cookies vs "1 cookie").
    if let quantity = parsed.quantity, let unit = parsed.unit,
      let household = householdAmount(food.householdServing)
    {
      let requestedSizes = sizeTokens(
        in: ([parsed.quantityText, parsed.unit] + parsed.descriptors.map(Optional.some))
          .compactMap { $0 }
          .joined(separator: " "))
      let householdSizes = sizeTokens(in: food.householdServing ?? "")
      if !requestedSizes.isEmpty, !householdSizes.isEmpty,
        requestedSizes.isDisjoint(with: householdSizes)
      {
        return .needsClarification(
          "USDA lists a different size for this food. Choose a matching size or enter grams."
        )
      }

      let hasCompatibleHouseholdUnit = UnitConversion.unitsCompatible(unit, household.unit)
      let hasMatchingSizeOnlyHousehold =
        UnitConversion.dimension(of: unit) == .count
        && !requestedSizes.isEmpty
        && requestedSizes == householdSizes
        && sizeTokens(in: household.unit) == householdSizes
      if hasCompatibleHouseholdUnit || hasMatchingSizeOnlyHousehold {
        let multiplier = quantity / household.amount
        let display = parsed.quantityText ?? "\(format(quantity)) \(unit)"
        if let oneServingG = servingGrams(food) {
          return resolveMass(oneServingG * multiplier, food: food, display: display)
        }
        return validatedServings(multiplier, display: display, food: food)
      }
    }

    // A bowl, plate, or glass is not a standard serving size. A matching USDA household
    // measure already resolved above; otherwise ask rather than equating the vessel to one
    // generic gram serving.
    if let unit = parsed.unit, isMealVessel(unit) {
      return .needsClarification(
        "USDA does not define the size of that \(UnitConversion.family(unit)). Enter grams, cups, or servings."
      )
    }

    // 6) Fraction of a whole item matching household unit (⅜ pizza vs "¼ pizza").
    if let fraction = parsed.fractionOfWhole, let whole = parsed.wholeUnit,
      let household = householdAmount(food.householdServing),
      UnitConversion.unitsCompatible(whole, household.unit)
    {
      let multiplier = fraction / household.amount
      let display = parsed.quantityText ?? "\(format(fraction)) \(whole)"
      if let oneServingG = servingGrams(food) {
        return resolveMass(oneServingG * multiplier, food: food, display: display)
      }
      return validatedServings(multiplier, display: display, food: food)
    }

    // 7) Explicit "N servings".
    if let quantity = parsed.quantity, let unit = parsed.unit,
      UnitConversion.dimension(of: unit) == .serving
    {
      return validatedServings(quantity, display: "\(format(quantity)) servings", food: food)
    }

    // 8) Alternate quantity pair (e.g. "1 cup / 240 g").
    if let alternate = parsed.alternateQuantity, let alternateUnit = parsed.alternateUnit {
      var alternateParsed = parsed
      alternateParsed.quantity = alternate
      alternateParsed.unit = alternateUnit
      alternateParsed.alternateQuantity = nil
      alternateParsed.alternateUnit = nil
      return resolve(alternateParsed, against: food)
    }

    // 9) Volume without a volume household: approximate using culinary grams/cup for
    // known staples. Never treat "1 pack (200 g)" as equal to 1 cup.
    if let quantity = parsed.quantity, let unit = parsed.unit,
      UnitConversion.dimension(of: unit) == .volume,
      let userML = UnitConversion.toMilliliters(quantity: quantity, unit: unit),
      let cupML = UnitConversion.toMilliliters(quantity: 1, unit: "cup"), cupML > 0,
      let gPerCup = CulinaryDensity.gramsPerCup(matching: food.description)
    {
      let grams = gPerCup * (userML / cupML)
      let display =
        (parsed.quantityText ?? "\(format(quantity)) \(unit)") + " (approx.)"
      return resolveMass(grams, food: food, display: display)
    }

    if parsed.quantity == nil && parsed.fractionOfWhole == nil {
      return .needsClarification("Enter the amount you ate.")
    }

    let userAmount =
      parsed.quantityText
      ?? [parsed.quantity.map(format), parsed.unit].compactMap { $0 }.joined(separator: " ")
    let packNote: String = {
      let household = food.householdServing?.lowercased() ?? ""
      if household.contains("pack") || household.contains("pouch") || household.contains("bag") {
        return
          " That \(foodServingDescription(food)) is a package weight, not a cup measure — so it isn’t the same as \(userAmount.isEmpty ? "your amount" : userAmount)."
      }
      return ""
    }()
    return .needsClarification(
      "USDA lists \(foodServingDescription(food)), which can’t be converted from \(userAmount.isEmpty ? "that amount" : userAmount) without a volume household serving.\(packNote) Enter servings, grams, or cups if this food supports them."
    )
  }

  public func manualServings(_ servings: Double, food: FoodDetails) -> ServingResolutionOutcome {
    validatedServings(servings, display: "\(format(servings)) USDA servings", food: food)
  }

  public func manualGrams(_ grams: Double, food: FoodDetails) -> ServingResolutionOutcome {
    resolveMass(grams, food: food, display: "\(format(grams)) g")
  }

  // MARK: - Apply mass / servings

  private func resolveMass(_ grams: Double, food: FoodDetails, display: String)
    -> ServingResolutionOutcome
  {
    guard grams.isFinite, grams > 0 else {
      return .needsClarification("Enter a positive, finite amount.")
    }

    if !food.nutrientsPer100Grams.isEmpty {
      let multiplier = servingGrams(food).map { grams / $0 }
      return .resolved(
        ServingResolution(
          basis: .grams, servingMultiplier: multiplier, consumedGrams: grams, displayText: display))
    }

    if let oneServingG = servingGrams(food), oneServingG > 0, !food.nutrientsPerServing.isEmpty {
      return .resolved(
        ServingResolution(
          basis: .servings,
          servingMultiplier: grams / oneServingG,
          consumedGrams: grams,
          displayText: display))
    }

    return .needsClarification(
      "This USDA record has nutrients per serving but no gram serving size, so \(display) can’t be converted automatically. Enter the number of USDA servings instead."
    )
  }

  private func validatedServings(_ multiplier: Double, display: String, food: FoodDetails)
    -> ServingResolutionOutcome
  {
    guard multiplier.isFinite, multiplier > 0 else {
      return .needsClarification("Enter a positive, finite amount.")
    }

    let hasServingNutrients = !food.nutrientsPerServing.isEmpty
    let grams = servingGrams(food).map { $0 * multiplier }

    if !hasServingNutrients, let grams {
      return resolveMass(grams, food: food, display: display)
    }

    guard hasServingNutrients || grams != nil else {
      return .needsClarification(
        "This item does not provide enough serving information for that amount. Enter grams if you know them."
      )
    }

    return .resolved(
      ServingResolution(
        basis: .servings, servingMultiplier: multiplier, consumedGrams: grams, displayText: display)
    )
  }

  private func servingGrams(_ food: FoodDetails) -> Double? {
    UnitConversion.toGrams(quantity: food.servingSize ?? .nan, unit: food.servingSizeUnit ?? "")
      .flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
      ?? {
        guard let size = food.servingSize, let unit = food.servingSizeUnit else { return nil }
        return UnitConversion.toGrams(quantity: size, unit: unit)
      }()
  }

  // MARK: - Household parsing

  private func householdAmount(_ text: String?) -> (amount: Double, unit: String)? {
    guard let text else { return nil }
    var cleaned =
      text
      .lowercased()
      .replacingOccurrences(of: "-", with: " ")
      .replacingOccurrences(of: "(", with: " ")
      .replacingOccurrences(of: ")", with: " ")
    // Keep "fl oz" as one token family.
    cleaned = cleaned.replacingOccurrences(of: "fl oz", with: "floz")
    cleaned = cleaned.replacingOccurrences(of: "fl. oz", with: "floz")
    cleaned = cleaned.replacingOccurrences(of: "fluid ounce", with: "floz")
    cleaned = cleaned.replacingOccurrences(of: "fluid ounces", with: "floz")

    let parts = cleaned.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    guard !parts.isEmpty else { return nil }

    let ignored = Set([
      "a", "an", "about", "approximately", "approx", "of", "the", "serving", "servings",
    ])
    var amount: Double?
    var unit: String?

    for (index, part) in parts.enumerated() {
      if amount == nil, let value = parseNumber(part), value > 0 {
        amount = value
        if let next = parts.dropFirst(index + 1).first(where: { !ignored.contains($0) }) {
          unit = next
        }
        break
      }
    }

    if amount == nil,
      let first = parts.first(where: { !ignored.contains($0) && parseNumber($0) == nil })
    {
      amount = 1
      unit = first
    }

    guard let amount, let unit, amount > 0 else { return nil }
    return (amount, unit)
  }

  private func parseNumber(_ text: String) -> Double? {
    if let value = Double(text) { return value }
    let pieces = text.split(separator: "/")
    if pieces.count == 2, let numerator = Double(pieces[0]), let denominator = Double(pieces[1]),
      denominator != 0
    {
      return numerator / denominator
    }
    return nil
  }

  private func foodServingDescription(_ food: FoodDetails) -> String {
    if let household = food.householdServing, !household.isEmpty {
      if let size = food.servingSize, let unit = food.servingSizeUnit {
        return "\(household) (\(format(size)) \(unit))"
      }
      return household
    }
    if let size = food.servingSize, let unit = food.servingSizeUnit {
      return "\(format(size)) \(unit)"
    }
    return "an incomplete serving"
  }

  private func sizeTokens(in text: String) -> Set<String> {
    let tokens =
      text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
      .split { !$0.isLetter && !$0.isNumber }
      .map(String.init)
    var sizes = Set<String>()
    for (index, token) in tokens.enumerated() {
      switch token {
      case "small", "medium", "jumbo":
        sizes.insert(token)
      case "large":
        sizes.insert(index > 0 && tokens[index - 1] == "extra" ? "extra-large" : "large")
      default:
        continue
      }
    }
    return sizes
  }

  private func isMealVessel(_ unit: String) -> Bool {
    let normalized = unit.lowercased().filter(\.isLetter)
    return ["bowl", "bowls", "plate", "plates", "glass", "glasses"].contains(normalized)
  }

  private func format(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(0...3)))
  }
}

/// Approximate culinary mass for household volumes when USDA omits a volume household.
///
/// Values are USDA/FNDDS-style averages for **prepared** staples (not invented packing
/// densities). Used only after exact USDA household bridges fail.
public enum CulinaryDensity: Sendable {
  /// Grams per US cup for description keyword matches (first match wins).
  private static let gramsPerCupByKeyword: [(keywords: [String], grams: Double)] = [
    // Cooked rice (white/jasmine/basmati ~ USDA 158 g/cup cooked).
    (
      ["jasmine", "basmati", "cooked rice", "rice, cooked", "white rice", "brown rice", "rice"], 158
    ),
    (["oatmeal", "oats, cooked", "porridge"], 234),
    (["cooked pasta", "pasta, cooked", "spaghetti, cooked", "noodles, cooked"], 140),
    (["mashed potato", "potato, mashed"], 210),
    (["beans, cooked", "lentils, cooked", "chickpeas, cooked"], 170),
    (["milk", "nonfat milk", "skim milk", "whole milk", "2% milk"], 244),
    (["yogurt"], 245),
    (["flour"], 125),
    (["sugar"], 200),
  ]

  public static func gramsPerCup(matching description: String) -> Double? {
    let hay = description.lowercased()
    for entry in gramsPerCupByKeyword {
      if entry.keywords.contains(where: { hay.contains($0) }) {
        return entry.grams
      }
    }
    return nil
  }
}
