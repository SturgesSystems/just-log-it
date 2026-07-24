import Testing

@testable import JustLogItCore

@Test func incidentalPortionMetadataCannotChooseAnUnstatedSize() {
  let parsed = ParsedFoodRequest(
    productName: "eggs", quantity: 2, unit: "eggs", quantityText: "two eggs")
  let food = FoodDetails(
    fdcID: 101,
    description: "Egg, whole, cooked",
    dataType: "Foundation",
    foodPortions: [
      USDAFoodPortion(gramWeight: 44, amount: 1, portionDescription: "1 small egg"),
      USDAFoodPortion(
        gramWeight: 61,
        amount: 1,
        modifier: "large",
        portionDescription: "1 large egg",
        measureUnitName: "item"),
    ],
    nutrientsPer100Grams: [NutrientAmount(key: .energy, amount: 148)])

  guard case .needsClarification = ServingResolutionService().resolve(parsed, against: food) else {
    Issue.record("Incidental metadata must not choose one materially different egg size")
    return
  }
}

@Test func explicitCountRequiresAUSDAUnitBridge() {
  let parsed = ParsedFoodRequest(
    productName: "cookies", quantity: 2, unit: "cookies", quantityText: "two cookies")
  let food = FoodDetails(
    fdcID: 102,
    description: "Cookies",
    dataType: "Branded",
    servingSize: 100,
    servingSizeUnit: "g",
    nutrientsPer100Grams: [NutrientAmount(key: .energy, amount: 480)])

  guard case .needsClarification = ServingResolutionService().resolve(parsed, against: food) else {
    Issue.record("Two items must not be treated as two generic 100 g servings")
    return
  }
}

@Test func sizeMismatchedHouseholdServingRequiresClarification() {
  let parsed = ParsedFoodRequest(
    productName: "eggs",
    quantity: 2,
    unit: "eggs",
    quantityText: "two small eggs",
    descriptors: ["small"])
  let food = FoodDetails(
    fdcID: 103,
    description: "Egg, whole, cooked",
    dataType: "Foundation",
    servingSize: 61,
    servingSizeUnit: "g",
    householdServing: "1 large egg",
    nutrientsPer100Grams: [NutrientAmount(key: .energy, amount: 148)])

  guard case .needsClarification = ServingResolutionService().resolve(parsed, against: food) else {
    Issue.record("A small request must not use a large household serving")
    return
  }
}

@Test func mealVesselDoesNotEqualAnUnrelatedHouseholdServing() {
  let parsed = ParsedFoodRequest(
    productName: "cereal", quantity: 2, unit: "bowls", quantityText: "two bowls")
  let food = FoodDetails(
    fdcID: 104,
    description: "Cereal",
    dataType: "Branded",
    servingSize: 40,
    servingSizeUnit: "g",
    householdServing: "1 cup",
    nutrientsPer100Grams: [NutrientAmount(key: .energy, amount: 357)])

  guard case .needsClarification = ServingResolutionService().resolve(parsed, against: food) else {
    Issue.record("An undefined bowl must not silently equal one cup or one gram serving")
    return
  }
}

@Test func mealVesselResolvesWhenUSDASuppliesTheSameHouseholdUnit() {
  let parsed = ParsedFoodRequest(
    productName: "soup", quantity: 2, unit: "bowls", quantityText: "two bowls")
  let food = FoodDetails(
    fdcID: 105,
    description: "Soup",
    dataType: "Branded",
    servingSize: 250,
    servingSizeUnit: "g",
    householdServing: "1 bowl",
    nutrientsPer100Grams: [NutrientAmount(key: .energy, amount: 50)])

  guard case .resolved(let resolution) = ServingResolutionService().resolve(parsed, against: food)
  else {
    Issue.record("A matching USDA bowl household measure should resolve")
    return
  }
  #expect(resolution.consumedGrams == 500)
}

@Test func matchingSizedHouseholdServingRemainsAValidCountBridge() {
  let parsed = ParsedFoodRequest(
    productName: "eggs",
    quantity: 2,
    unit: "eggs",
    quantityText: "two large eggs",
    descriptors: ["large"])
  let food = FoodDetails(
    fdcID: 106,
    description: "Egg, whole, cooked",
    dataType: "Foundation",
    servingSize: 61,
    servingSizeUnit: "g",
    householdServing: "1 large",
    nutrientsPer100Grams: [NutrientAmount(key: .energy, amount: 148)])

  guard case .resolved(let resolution) = ServingResolutionService().resolve(parsed, against: food)
  else {
    Issue.record("A matching explicit size-only household measure should remain usable")
    return
  }
  #expect(resolution.consumedGrams == 122)
}

@Test func explicitHouseholdCountStillResolvesBrandedFood() {
  let parsed = ParsedFoodRequest(
    productName: "cookies", quantity: 2, unit: "cookies", quantityText: "two cookies")
  let food = FoodDetails(
    fdcID: 107,
    description: "Chocolate chip cookie",
    dataType: "Branded",
    servingSize: 28,
    servingSizeUnit: "g",
    householdServing: "1 cookie",
    nutrientsPerServing: [NutrientAmount(key: .energy, amount: 140)])

  guard case .resolved(let resolution) = ServingResolutionService().resolve(parsed, against: food)
  else {
    Issue.record("A matching branded household count should resolve")
    return
  }
  #expect(resolution.consumedGrams == 56)
  #expect(resolution.servingMultiplier == 2)
}

@Test(arguments: [1.0, 2.0, 3.0])
func scrambledEggCountUsesEggPortionInsteadOfCupDefault(count: Double) {
  let parsed = ParsedFoodRequest(
    productName: "scrambled eggs",
    quantity: count,
    unit: "eggs",
    quantityText: count == 2 ? "two scrambled eggs" : nil,
    preparation: "scrambled"
  )
  let food = FoodDetails(
    fdcID: 108,
    description: "Egg, whole, cooked, scrambled",
    dataType: "Survey (FNDDS)",
    // USDA may designate a volume row as the record's default serving even though a
    // count-compatible row is also present. Counts must scale the egg row, not the cup.
    servingSize: 180,
    servingSizeUnit: "g",
    householdServing: "1 cup",
    foodPortions: [
      USDAFoodPortion(
        gramWeight: 180, amount: 1, portionDescription: "1 cup", measureUnitName: "cup"),
      USDAFoodPortion(
        gramWeight: 50, amount: 1, portionDescription: "1 large egg", measureUnitName: "item"),
    ],
    nutrientsPer100Grams: [NutrientAmount(key: .energy, amount: 148)]
  )

  guard case .resolved(let resolution) = ServingResolutionService().resolve(parsed, against: food)
  else {
    Issue.record("A countable egg amount should resolve through USDA's egg portion")
    return
  }

  #expect(resolution.basis == .grams)
  #expect(resolution.consumedGrams == 50 * count)
  #expect(resolution.displayText == (count == 2 ? "two scrambled eggs" : "\(Int(count)) eggs"))
}

@Test func multiEggUSDAPortionScalesByItsPublishedAmount() {
  let parsed = ParsedFoodRequest(
    productName: "scrambled eggs",
    quantity: 2,
    unit: "eggs",
    quantityText: "2 scrambled eggs",
    preparation: "scrambled"
  )
  let food = FoodDetails(
    fdcID: 109,
    description: "Eggs, scrambled",
    dataType: "Survey (FNDDS)",
    servingSize: 180,
    servingSizeUnit: "g",
    householdServing: "1 cup",
    foodPortions: [
      USDAFoodPortion(gramWeight: 180, amount: 1, portionDescription: "1 cup"),
      USDAFoodPortion(gramWeight: 100, amount: 2, portionDescription: "2 eggs"),
    ],
    nutrientsPer100Grams: [NutrientAmount(key: .energy, amount: 148)]
  )

  guard case .resolved(let resolution) = ServingResolutionService().resolve(parsed, against: food)
  else {
    Issue.record("The published multi-egg amount should be honored")
    return
  }
  #expect(resolution.consumedGrams == 100)
  #expect(resolution.displayText == "2 scrambled eggs")
}
