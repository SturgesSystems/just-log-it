import Testing

@testable import JustLogItCore

@Test func brandedQueryRemovesQuantityAndDeduplicates() {
  let parsed = ParsedFoodRequest(
    brand: "Domino's",
    productName: "stuffed crust pepperoni pizza",
    searchTerms: "half a Domino's stuffed crust pepperoni pizza",
    quantity: 0.5,
    unit: "pizza",
    descriptors: ["stuffed crust", "pepperoni"]
  )
  let request = FoodSearchQueryBuilder().build(from: parsed)
  #expect(request.query == "Domino's stuffed crust pepperoni pizza")
  #expect(request.normalizedKey == "domino s stuffed crust pepperoni pizza")
  #expect(request.dataTypes == ["Branded"])
}

@Test func fractionOfPizzaResolvesAgainstQuarterPizzaServing() {
  let parsed = ParsedFoodRequest(
    productName: "pizza", quantityText: "3/8 pizza", fractionOfWhole: 0.375, wholeUnit: "pizza")
  let food = FoodDetails(
    fdcID: 1,
    description: "Pizza",
    dataType: "Branded",
    householdServing: "1/4 pizza",
    nutrientsPerServing: [NutrientAmount(key: .energy, amount: 300)]
  )
  let outcome = ServingResolutionService().resolve(parsed, against: food)
  #expect(
    outcome
      == .resolved(
        ServingResolution(
          basis: .servings, servingMultiplier: 1.5, consumedGrams: nil, displayText: "3/8 pizza")))
}

@Test func slicesResolveAgainstSliceServing() {
  let parsed = ParsedFoodRequest(productName: "pizza", quantity: 3, unit: "slices")
  let food = FoodDetails(
    fdcID: 1,
    description: "Pizza",
    dataType: "Branded",
    householdServing: "1 slice",
    nutrientsPerServing: [NutrientAmount(key: .energy, amount: 250)]
  )
  let outcome = ServingResolutionService().resolve(parsed, against: food)
  #expect(
    outcome
      == .resolved(
        ServingResolution(
          basis: .servings, servingMultiplier: 3, consumedGrams: nil, displayText: "3 slices")))
}

@Test func massCalculationUsesPerHundredGramBasis() throws {
  let food = FoodDetails(
    fdcID: 2,
    description: "Rice",
    dataType: "Foundation",
    nutrientsPer100Grams: [
      NutrientAmount(key: .energy, amount: 130),
      NutrientAmount(key: .protein, amount: 2.7),
    ]
  )
  let resolution = ServingResolution(
    basis: .grams, servingMultiplier: nil, consumedGrams: 250, displayText: "250 g")
  let nutrients = try NutritionCalculator().calculate(food: food, resolution: resolution)
  #expect(nutrients.first(where: { $0.key == .energy })?.amount == 325)
  #expect(nutrients.first(where: { $0.key == .protein })?.amount == 6.75)
}

@Test func halfPizzaDoesNotResolveAgainstGramOnlyServing() {
  let parsed = ParsedFoodRequest(productName: "pizza", quantity: 0.5, unit: "pizza")
  let food = FoodDetails(
    fdcID: 3,
    description: "Pizza",
    dataType: "Branded",
    servingSize: 140,
    servingSizeUnit: "g",
    nutrientsPer100Grams: [NutrientAmount(key: .energy, amount: 250)]
  )
  guard case .needsClarification = ServingResolutionService().resolve(parsed, against: food) else {
    Issue.record("Expected unresolved quantity")
    return
  }
}
