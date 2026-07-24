import Testing

@testable import JustLogItCore

@Test func numericFoodNamesAreNotRecoveredAsConsumedAmounts() {
  for (source, product) in [
    ("7 Layer Dip", "7 Layer Dip"),
    ("I had a 7 Up", "7 Up"),
    ("1% milk", "1% milk"),
  ] {
    let parsed = ParsedFoodRequest(productName: product, searchTerms: product)
    let recovered = ParsedQuantityRecovery.recoveringSimpleAmount(in: parsed, from: source)

    #expect(recovered.quantity == nil, "Numeric identity was treated as an amount: \(source)")
    #expect(!ParsedQuantityRecovery.containsExplicitAmount(in: source, for: parsed))
  }
}

@Test func quantityRecoveryIgnoresIdentityNumberButKeepsSeparateAmount() {
  let parsed = ParsedFoodRequest(productName: "7 Layer Dip", searchTerms: "7 Layer Dip")
  let source = "2 servings of 7 Layer Dip"

  let recovered = ParsedQuantityRecovery.recoveringSimpleAmount(in: parsed, from: source)

  #expect(recovered.quantity == 2)
  #expect(recovered.unit == "servings")
  #expect(recovered.quantityText == "2 servings")
  #expect(ParsedQuantityRecovery.containsExplicitAmount(in: source, for: parsed))
}

@Test func percentageDescriptorDoesNotHideASeparateQuantity() {
  let parsed = ParsedFoodRequest(productName: "1% milk", searchTerms: "1% milk")
  let source = "2 cups of 1% milk"

  let recovered = ParsedQuantityRecovery.recoveringSimpleAmount(in: parsed, from: source)

  #expect(recovered.quantity == 2)
  #expect(recovered.unit == "cups")
}

@Test func recoveryRequiresAForwardGroundedUnit() {
  let parsed = ParsedFoodRequest(productName: "apple", searchTerms: "apple")

  let recovered = ParsedQuantityRecovery.recoveringSimpleAmount(
    in: parsed,
    from: "Apple, 2"
  )

  #expect(recovered.quantity == nil)
  #expect(ParsedQuantityRecovery.containsExplicitAmount(in: "Apple, 2", for: parsed))
}

@Test func missingQuantityStaysMissingUntilSelectedFoodHasUsableServingMetadata() {
  let parsed = ParsedFoodRequest(productName: "oatmeal", searchTerms: "oatmeal")

  let beforeSelection = ParsedQuantityDefault.applyingDefaultIfNeeded(
    parsed,
    sourceText: "oatmeal"
  )
  #expect(beforeSelection.quantity == nil)
  #expect(beforeSelection.unit == nil)

  let gramsOnly = FoodDetails(
    fdcID: 1,
    description: "Oatmeal",
    dataType: "Foundation",
    nutrientsPer100Grams: [.init(key: .energy, amount: 68)]
  )
  let withoutServingBasis = ParsedQuantityDefault.applyingDefaultIfNeeded(
    parsed,
    sourceText: "oatmeal",
    selectedFood: gramsOnly
  )
  #expect(withoutServingBasis.quantity == nil)

  let servingBacked = FoodDetails(
    fdcID: 2,
    description: "Oatmeal",
    dataType: "Branded",
    servingSize: 40,
    servingSizeUnit: "g",
    householdServing: "1 packet",
    nutrientsPer100Grams: [.init(key: .energy, amount: 375)],
    nutrientsPerServing: [.init(key: .energy, amount: 150)]
  )
  let afterSelection = ParsedQuantityDefault.applyingDefaultIfNeeded(
    parsed,
    sourceText: "oatmeal",
    selectedFood: servingBacked
  )
  #expect(afterSelection.quantity == 1)
  #expect(afterSelection.unit == "serving")
  #expect(afterSelection.quantityText == "1 serving")
}

@Test func numericIdentityCanUseSelectedFoodsRealServingWithoutBecomingSevenServings() {
  let parsed = ParsedFoodRequest(productName: "7 Layer Dip", searchTerms: "7 Layer Dip")
  let selected = FoodDetails(
    fdcID: 7,
    description: "7 Layer Dip",
    dataType: "Branded",
    servingSize: 30,
    servingSizeUnit: "g",
    householdServing: "2 tbsp",
    nutrientsPerServing: [.init(key: .energy, amount: 80)]
  )

  let defaulted = ParsedQuantityDefault.applyingDefaultIfNeeded(
    parsed,
    sourceText: "7 Layer Dip",
    selectedFood: selected
  )

  #expect(defaulted.quantity == 1)
  #expect(defaulted.unit == "serving")
}

@Test func missingQuantityStaysMissingWhenUSDAExposesDifferentPortionBases() {
  let parsed = ParsedFoodRequest(productName: "scrambled eggs", searchTerms: "scrambled eggs")
  let selected = FoodDetails(
    fdcID: 8,
    description: "Egg, whole, cooked, scrambled",
    dataType: "SR Legacy",
    servingSize: 61,
    servingSizeUnit: "g",
    householdServing: "1 large egg",
    foodPortions: [
      USDAFoodPortion(gramWeight: 44, amount: 1, portionDescription: "1 small egg"),
      USDAFoodPortion(gramWeight: 61, amount: 1, portionDescription: "1 large egg"),
      USDAFoodPortion(gramWeight: 220, amount: 1, portionDescription: "1 cup"),
    ],
    nutrientsPerServing: [.init(key: .energy, amount: 90)]
  )

  let result = ParsedQuantityDefault.applyingDefaultIfNeeded(
    parsed,
    sourceText: "scrambled eggs",
    selectedFood: selected
  )

  #expect(result.quantity == nil)
  #expect(result.unit == nil)
}

@Test func equivalentUSDAPortionRowsDoNotManufactureAmbiguity() {
  let parsed = ParsedFoodRequest(productName: "yogurt", searchTerms: "yogurt")
  let selected = FoodDetails(
    fdcID: 9,
    description: "Yogurt, plain",
    dataType: "Foundation",
    foodPortions: [
      USDAFoodPortion(gramWeight: 170, amount: 1, portionDescription: "1 container"),
      USDAFoodPortion(gramWeight: 340, amount: 2, portionDescription: "2 containers"),
    ],
    nutrientsPerServing: [.init(key: .energy, amount: 100)]
  )

  let result = ParsedQuantityDefault.applyingDefaultIfNeeded(
    parsed,
    sourceText: "yogurt",
    selectedFood: selected
  )

  #expect(result.quantity == 1)
  #expect(result.unit == "serving")
}
