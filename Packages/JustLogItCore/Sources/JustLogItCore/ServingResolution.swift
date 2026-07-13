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

public struct ServingResolutionService: Sendable {
  public init() {}

  public func resolve(_ parsed: ParsedFoodRequest, against food: FoodDetails)
    -> ServingResolutionOutcome
  {
    // A fraction of a sized container is more specific than either number in isolation.
    // For example, half of a 12-ounce bottle means 6 ounces consumed, not 0.5 ounce.
    if let fraction = parsed.fractionOfWhole,
      let containerSize = parsed.containerSize,
      let containerUnit = parsed.containerSizeUnit,
      let grams = grams(quantity: fraction * containerSize, unit: containerUnit)
    {
      let display =
        parsed.quantityText
        ?? "\(format(fraction)) of a \(format(containerSize)) \(containerUnit) container"
      return resolveMass(grams, food: food, display: display)
    }

    if let quantity = parsed.quantity, let unit = parsed.unit,
      let grams = grams(quantity: quantity, unit: unit)
    {
      return resolveMass(grams, food: food, display: "\(format(quantity)) \(unit)")
    }

    if let quantity = parsed.quantity, let unit = parsed.unit,
      let serving = householdAmount(food.householdServing),
      unitsMatch(unit, serving.unit)
    {
      let multiplier = quantity / serving.amount
      return validatedServings(
        multiplier, display: parsed.quantityText ?? "\(format(quantity)) \(unit)", food: food)
    }

    if let fraction = parsed.fractionOfWhole, let whole = parsed.wholeUnit,
      let serving = householdAmount(food.householdServing),
      unitsMatch(whole, serving.unit)
    {
      let multiplier = fraction / serving.amount
      return validatedServings(
        multiplier, display: parsed.quantityText ?? "\(format(fraction)) \(whole)", food: food)
    }

    if let quantity = parsed.quantity, let unit = parsed.unit,
      normalized(unit) == "serving" || normalized(unit) == "servings"
    {
      return validatedServings(quantity, display: "\(format(quantity)) servings", food: food)
    }

    if let alternate = parsed.alternateQuantity, let alternateUnit = parsed.alternateUnit {
      var alternateParsed = parsed
      alternateParsed.quantity = alternate
      alternateParsed.unit = alternateUnit
      alternateParsed.alternateQuantity = nil
      alternateParsed.alternateUnit = nil
      return resolve(alternateParsed, against: food)
    }

    let userAmount =
      parsed.quantityText
      ?? [parsed.quantity.map(format), parsed.unit].compactMap { $0 }.joined(separator: " ")
    let sourceAmount =
      food.householdServing
      ?? [food.servingSize.map(format), food.servingSizeUnit].compactMap { $0 }.joined(
        separator: " ")
    return .needsClarification(
      "USDA lists \(sourceAmount.isEmpty ? "an incomplete serving" : sourceAmount), which cannot be safely matched to \(userAmount.isEmpty ? "the amount eaten" : userAmount)."
    )
  }

  public func manualServings(_ servings: Double, food: FoodDetails) -> ServingResolutionOutcome {
    validatedServings(servings, display: "\(format(servings)) USDA servings", food: food)
  }

  public func manualGrams(_ grams: Double, food: FoodDetails) -> ServingResolutionOutcome {
    resolveMass(grams, food: food, display: "\(format(grams)) g")
  }

  private func resolveMass(_ grams: Double, food: FoodDetails, display: String)
    -> ServingResolutionOutcome
  {
    guard grams.isFinite, grams > 0 else {
      return .needsClarification("Enter a positive, finite amount.")
    }
    if !food.nutrientsPer100Grams.isEmpty {
      let multiplier = food.servingSize.flatMap {
        servingGrams(size: $0, unit: food.servingSizeUnit)
      }.map { grams / $0 }
      return .resolved(
        ServingResolution(
          basis: .grams, servingMultiplier: multiplier, consumedGrams: grams, displayText: display))
    }
    if let size = food.servingSize,
      let servingGrams = servingGrams(size: size, unit: food.servingSizeUnit),
      !food.nutrientsPerServing.isEmpty
    {
      return .resolved(
        ServingResolution(
          basis: .servings, servingMultiplier: grams / servingGrams, consumedGrams: grams,
          displayText: display))
    }
    return .needsClarification("This item does not provide a compatible mass-based nutrient basis.")
  }

  private func validatedServings(_ multiplier: Double, display: String, food: FoodDetails)
    -> ServingResolutionOutcome
  {
    guard multiplier.isFinite, multiplier > 0 else {
      return .needsClarification("Enter a positive, finite amount.")
    }
    guard
      !food.nutrientsPerServing.isEmpty
        || (!food.nutrientsPer100Grams.isEmpty
          && servingGrams(size: food.servingSize, unit: food.servingSizeUnit) != nil)
    else {
      return .needsClarification(
        "This item does not provide enough serving information for that amount.")
    }
    let grams = servingGrams(size: food.servingSize, unit: food.servingSizeUnit).map {
      $0 * multiplier
    }
    return .resolved(
      ServingResolution(
        basis: .servings, servingMultiplier: multiplier, consumedGrams: grams, displayText: display)
    )
  }

  private func grams(quantity: Double, unit: String) -> Double? {
    guard quantity.isFinite, quantity > 0 else { return nil }
    return switch normalized(unit) {
    case "g", "gram", "grams": quantity
    case "kg", "kilogram", "kilograms": quantity * 1_000
    case "oz", "ounce", "ounces": quantity * 28.349_523_125
    case "lb", "lbs", "pound", "pounds": quantity * 453.592_37
    default: nil
    }
  }

  private func servingGrams(size: Double?, unit: String?) -> Double? {
    guard let size, let unit else { return nil }
    return grams(quantity: size, unit: unit)
  }

  private func householdAmount(_ text: String?) -> (amount: Double, unit: String)? {
    guard let text else { return nil }
    let cleaned = text.lowercased().replacingOccurrences(of: "-", with: " ")
    let parts = cleaned.split(whereSeparator: { $0.isWhitespace })
    guard let first = parts.first, let amount = parseNumber(String(first)), amount > 0 else {
      return nil
    }
    let ignored = Set(["a", "an", "about", "approximately"])
    guard let unit = parts.dropFirst().map(String.init).first(where: { !ignored.contains($0) })
    else { return nil }
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

  private func unitsMatch(_ lhs: String, _ rhs: String) -> Bool {
    let a = normalized(lhs)
    let b = normalized(rhs)
    return a == b
      || a.trimmingCharacters(in: CharacterSet(charactersIn: "s"))
        == b.trimmingCharacters(in: CharacterSet(charactersIn: "s"))
  }

  private func normalized(_ unit: String) -> String {
    unit.lowercased().trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines))
  }

  private func format(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(0...3)))
  }
}
