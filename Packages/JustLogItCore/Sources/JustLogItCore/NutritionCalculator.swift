import Foundation

public enum NutritionCalculationError: Error, Equatable {
  case invalidMultiplier
  case missingCompatibleBasis
}

public struct NutritionCalculator: Sendable {
  public init() {}

  public func calculate(food: FoodDetails, resolution: ServingResolution) throws -> [NutrientAmount]
  {
    let source: [NutrientAmount]
    let multiplier: Double

    switch resolution.basis {
    case .grams:
      guard let grams = resolution.consumedGrams, grams.isFinite, grams > 0,
        !food.nutrientsPer100Grams.isEmpty
      else {
        throw NutritionCalculationError.missingCompatibleBasis
      }
      source = food.nutrientsPer100Grams
      multiplier = grams / 100
    case .servings:
      guard let servingMultiplier = resolution.servingMultiplier, servingMultiplier.isFinite,
        servingMultiplier > 0
      else {
        throw NutritionCalculationError.invalidMultiplier
      }
      if !food.nutrientsPerServing.isEmpty {
        source = food.nutrientsPerServing
        multiplier = servingMultiplier
      } else if let grams = resolution.consumedGrams, !food.nutrientsPer100Grams.isEmpty {
        source = food.nutrientsPer100Grams
        multiplier = grams / 100
      } else {
        throw NutritionCalculationError.missingCompatibleBasis
      }
    case .manual:
      source = food.nutrientsPerServing
      multiplier = 1
    }

    guard multiplier.isFinite, multiplier > 0 else {
      throw NutritionCalculationError.invalidMultiplier
    }
    return source.compactMap { nutrient in
      let result = nutrient.amount * multiplier
      guard result.isFinite, result >= 0 else { return nil }
      return NutrientAmount(key: nutrient.key, amount: result, unit: nutrient.unit)
    }
  }
}
