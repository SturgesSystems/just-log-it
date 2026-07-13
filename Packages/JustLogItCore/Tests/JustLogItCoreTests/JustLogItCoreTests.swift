import Testing

@testable import JustLogItCore

@Test func cookieResultOutranksCompositeDessertThatOnlyContainsCookie() {
  let parsed = ParsedFoodRequest(brand: "Oreo", productName: "cookie", searchTerms: "Oreo cookie")
  let cookie = FoodSearchResult(
    fdcID: 1,
    description: "OREO CHOCOLATE SANDWICH COOKIES",
    brandOwner: "MONDELEZ GLOBAL LLC",
    dataType: "Branded"
  )
  let composite = FoodSearchResult(
    fdcID: 2,
    description: "McDONALD'S, McFLURRY WITH OREO COOKIES",
    brandOwner: "McDonald's Corporation",
    dataType: "Branded"
  )

  let ranked = FoodSearchResultRanker().rank([composite, cookie], for: parsed)

  #expect(ranked.map(\.fdcID) == [1, 2])
}

@Test func primaryFoodOutranksCompositeDishForGeneralUnbrandedQuery() {
  let parsed = ParsedFoodRequest(productName: "chicken breast", preparation: "roasted")
  let salad = FoodSearchResult(
    fdcID: 10,
    description: "SALAD WITH ROASTED CHICKEN BREAST",
    dataType: "Survey (FNDDS)"
  )
  let chicken = FoodSearchResult(
    fdcID: 11,
    description: "CHICKEN BREAST, ROASTED",
    dataType: "Foundation"
  )

  let ranked = FoodSearchResultRanker().rank([salad, chicken], for: parsed)

  #expect(ranked.map(\.fdcID) == [11, 10])
}

@Test func explicitBrandAffectsRankingButAbsentBrandDoesNot() {
  let fairlife = FoodSearchResult(
    fdcID: 20,
    description: "CHOCOLATE MILK",
    brandOwner: "FAIRLIFE LLC",
    dataType: "Branded"
  )
  let other = FoodSearchResult(
    fdcID: 21,
    description: "CHOCOLATE MILK",
    brandOwner: "OTHER DAIRY",
    dataType: "Branded"
  )
  let ranker = FoodSearchResultRanker()

  let branded = ranker.rank(
    [other, fairlife],
    for: ParsedFoodRequest(brand: "Fairlife", productName: "chocolate milk")
  )
  let unbranded = ranker.rank(
    [other, fairlife],
    for: ParsedFoodRequest(productName: "chocolate milk")
  )

  #expect(branded.map(\.fdcID) == [20, 21])
  #expect(unbranded.map(\.fdcID) == [21, 20])
}

@Test func rankingNeverFiltersWeakResults() {
  let results = [
    FoodSearchResult(fdcID: 30, description: "UNRELATED FOOD", dataType: "Foundation"),
    FoodSearchResult(fdcID: 31, description: "ANOTHER FOOD", dataType: "Foundation"),
  ]

  let ranked = FoodSearchResultRanker().rank(
    results, for: ParsedFoodRequest(productName: "cookie"))

  #expect(Set(ranked.map(\.fdcID)) == Set(results.map(\.fdcID)))
  #expect(ranked.count == results.count)
}

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

@Test func fractionOfSizedContainerTakesPrecedenceOverMisleadingPrimaryMass() throws {
  let parsed = ParsedFoodRequest(
    brand: "Fairlife",
    productName: "chocolate milk",
    quantity: 0.5,
    unit: "ounce",
    quantityText: "half a 12-ounce bottle",
    fractionOfWhole: 0.5,
    wholeUnit: "bottle",
    containerSize: 12,
    containerSizeUnit: "ounce",
    isApproximate: true
  )
  let food = FoodDetails(
    fdcID: 1,
    description: "Chocolate milk",
    dataType: "Branded",
    servingSize: 340,
    servingSizeUnit: "g",
    householdServing: "1 bottle",
    nutrientsPer100Grams: [NutrientAmount(key: .energy, amount: 100)]
  )

  let outcome = ServingResolutionService().resolve(parsed, against: food)
  guard case .resolved(let resolution) = outcome else {
    Issue.record("Expected the sized container fraction to resolve")
    return
  }

  #expect(resolution.basis == .grams)
  #expect(abs((resolution.consumedGrams ?? 0) - 170.097_138_75) < 0.000_001)
  #expect(resolution.displayText == "half a 12-ounce bottle")

  let nutrients = try NutritionCalculator().calculate(food: food, resolution: resolution)
  #expect(
    abs((nutrients.first(where: { $0.key == .energy })?.amount ?? 0) - 170.097_138_75)
      < 0.000_001)
}

@Test func fractionOfSizedContainerFallsBackWhenContainerUnitCannotConvertToMass() {
  let parsed = ParsedFoodRequest(
    productName: "juice",
    quantityText: "half a 12-fluid-ounce bottle",
    fractionOfWhole: 0.5,
    wholeUnit: "bottle",
    containerSize: 12,
    containerSizeUnit: "fluid ounce"
  )
  let food = FoodDetails(
    fdcID: 1,
    description: "Juice",
    dataType: "Branded",
    servingSize: 240,
    servingSizeUnit: "g",
    householdServing: "1 bottle",
    nutrientsPer100Grams: [NutrientAmount(key: .energy, amount: 50)]
  )

  let outcome = ServingResolutionService().resolve(parsed, against: food)
  guard case .resolved(let resolution) = outcome else {
    Issue.record("Expected the household bottle fraction to resolve")
    return
  }
  #expect(resolution.servingMultiplier == 0.5)
  #expect(resolution.consumedGrams == 120)
}

@Test func groundingRemovesCrossPromptQuantityFactsFromOreo() {
  let contaminated = ParsedFoodRequest(
    brand: "Fairlife",
    productName: "Oreo cookie",
    searchTerms: "Oreo cookie",
    quantity: 0.5,
    unit: "ounce",
    quantityText: "half a 12-ounce bottle",
    fractionOfWhole: 0.5,
    wholeUnit: "bottle",
    containerSize: 12,
    containerSizeUnit: "ounce",
    alternateQuantity: 6,
    alternateUnit: "ounce",
    preparation: "chocolate",
    descriptors: ["chocolate milk", "12-ounce bottle"],
    isApproximate: true,
    ambiguityNotes: "Half a bottle"
  )

  let grounded = ParsedFoodRequestGrounder().ground(contaminated, in: "An Oreo cookie")

  #expect(grounded.productName == "Oreo cookie")
  #expect(grounded.brand == nil)
  #expect(grounded.quantity == nil)
  #expect(grounded.unit == nil)
  #expect(grounded.quantityText == nil)
  #expect(grounded.fractionOfWhole == nil)
  #expect(grounded.wholeUnit == nil)
  #expect(grounded.containerSize == nil)
  #expect(grounded.containerSizeUnit == nil)
  #expect(grounded.alternateQuantity == nil)
  #expect(grounded.alternateUnit == nil)
  #expect(grounded.preparation == nil)
  #expect(grounded.descriptors.isEmpty)
  #expect(!grounded.isApproximate)
  #expect(grounded.ambiguityNotes == nil)

  let food = FoodDetails(
    fdcID: 1,
    description: "Oreo cookie",
    dataType: "Branded",
    householdServing: "1 cookie",
    nutrientsPerServing: [NutrientAmount(key: .energy, amount: 53)]
  )
  guard case .needsClarification = ServingResolutionService().resolve(grounded, against: food)
  else {
    Issue.record("An ungrounded stale quantity must not resolve nutrition")
    return
  }
}

@Test func groundingKeepsArticleAsOneOnlyWhenPairedWithCurrentFoodUnit() {
  let candidate = ParsedFoodRequest(
    productName: "Oreo cookie",
    quantity: 1,
    unit: "cookie",
    quantityText: "An Oreo cookie"
  )
  let grounded = ParsedFoodRequestGrounder().ground(candidate, in: "An Oreo cookie")

  #expect(grounded.quantity == 1)
  #expect(grounded.unit == "cookie")
  #expect(grounded.quantityText == "An Oreo cookie")

  let food = FoodDetails(
    fdcID: 1,
    description: "Oreo cookie",
    dataType: "Branded",
    householdServing: "1 cookie",
    nutrientsPerServing: [NutrientAmount(key: .energy, amount: 53)]
  )
  guard case .resolved(let resolution) = ServingResolutionService().resolve(grounded, against: food)
  else {
    Issue.record("Expected a source-grounded single cookie to resolve")
    return
  }
  #expect(resolution.servingMultiplier == 1)
}

@Test func groundingPreservesValidSizedContainerFraction() {
  let candidate = ParsedFoodRequest(
    brand: "Fairlife",
    productName: "chocolate milk",
    quantity: 0.5,
    unit: "ounce",
    quantityText: "half a 12-ounce bottle",
    fractionOfWhole: 0.5,
    wholeUnit: "bottle",
    containerSize: 12,
    containerSizeUnit: "ounce",
    preparation: nil,
    descriptors: ["chocolate"],
    isApproximate: true
  )
  let grounded = ParsedFoodRequestGrounder().ground(
    candidate,
    in: "About half a 12-ounce bottle of Fairlife chocolate milk"
  )

  #expect(grounded.brand == "Fairlife")
  #expect(grounded.quantity == nil)
  #expect(grounded.unit == nil)
  #expect(grounded.quantityText == "half a 12-ounce bottle")
  #expect(grounded.fractionOfWhole == 0.5)
  #expect(grounded.wholeUnit == "bottle")
  #expect(grounded.containerSize == 12)
  #expect(grounded.containerSizeUnit == "ounce")
  #expect(grounded.descriptors == ["chocolate"])
  #expect(grounded.isApproximate)
}

@Test func groundingPreservesWrittenNumberAndFractionEvidence() {
  let eggs = ParsedFoodRequest(
    productName: "eggs",
    quantity: 2,
    unit: "eggs",
    preparation: "scrambled",
    descriptors: ["large"]
  )
  let groundedEggs = ParsedFoodRequestGrounder().ground(
    eggs,
    in: "Two large scrambled eggs"
  )
  #expect(groundedEggs.quantity == 2)
  #expect(groundedEggs.unit == "eggs")
  #expect(groundedEggs.preparation == "scrambled")
  #expect(groundedEggs.descriptors == ["large"])

  let pizza = ParsedFoodRequest(
    productName: "pizza",
    quantityText: "three eighths of a pizza",
    fractionOfWhole: 0.375,
    wholeUnit: "pizza"
  )
  let groundedPizza = ParsedFoodRequestGrounder().ground(
    pizza,
    in: "Three eighths of a pizza"
  )
  #expect(groundedPizza.fractionOfWhole == 0.375)
  #expect(groundedPizza.wholeUnit == "pizza")
  #expect(groundedPizza.quantityText == "three eighths of a pizza")
}

@Test func groundingRejectsStaleProductIntentAndGeneratedSearchTerms() {
  let candidate = ParsedFoodRequest(
    productName: "chocolate milk",
    searchTerms: "Fairlife chocolate milk"
  )
  let grounded = ParsedFoodRequestGrounder().ground(candidate, in: "An Oreo cookie")

  #expect(grounded.productName.isEmpty)
  #expect(grounded.searchTerms.isEmpty)
}

@Test func groundingRebuildsSearchTermsFromCurrentProduct() {
  let candidate = ParsedFoodRequest(
    productName: "Oreo cookie",
    searchTerms: "stale chocolate milk"
  )
  let grounded = ParsedFoodRequestGrounder().ground(candidate, in: "An Oreo cookie")

  #expect(grounded.productName == "Oreo cookie")
  #expect(grounded.searchTerms == "Oreo cookie")
}

@Test func groundingAllowsOnlySafeProductFillersAndInflection() {
  let candidate = ParsedFoodRequest(
    productName: "cream mushroom soups",
    searchTerms: "stale"
  )
  let grounded = ParsedFoodRequestGrounder().ground(
    candidate,
    in: "one bowl of cream of mushroom soup"
  )

  #expect(grounded.productName == "cream mushroom soups")
  #expect(grounded.searchTerms == "cream mushroom soups")

  let crossing = ParsedFoodRequest(productName: "eggs bacon", searchTerms: "stale")
  let rejected = ParsedFoodRequestGrounder().ground(crossing, in: "eggs and bacon")
  #expect(rejected.productName.isEmpty)
}

@Test func groundingRejectsCrossFoodAndBackwardQuantityPairs() {
  let crossFood = ParsedFoodRequest(
    productName: "eggs",
    quantity: 3,
    unit: "eggs"
  )
  let groundedCrossFood = ParsedFoodRequestGrounder().ground(
    crossFood,
    in: "2 eggs and 3 bacon strips"
  )
  #expect(groundedCrossFood.quantity == nil)
  #expect(groundedCrossFood.unit == nil)

  let backward = ParsedFoodRequest(
    productName: "eggs",
    quantity: 3,
    unit: "eggs"
  )
  let groundedBackward = ParsedFoodRequestGrounder().ground(backward, in: "eggs, 3")
  #expect(groundedBackward.quantity == nil)
  #expect(groundedBackward.unit == nil)

  let prepositionCrossing = ParsedFoodRequest(
    productName: "cookie crumbs",
    quantity: 1,
    unit: "cookie"
  )
  let groundedPreposition = ParsedFoodRequestGrounder().ground(
    prepositionCrossing,
    in: "a cup of cookie crumbs"
  )
  #expect(groundedPreposition.quantity == nil)
  #expect(groundedPreposition.unit == nil)
}

@Test func groundingRejectsCrossBoundaryFractionPair() {
  let candidate = ParsedFoodRequest(
    productName: "pizza",
    fractionOfWhole: 1,
    wholeUnit: "pizza"
  )
  let grounded = ParsedFoodRequestGrounder().ground(
    candidate,
    in: "half a pizza and one bottle of milk"
  )

  #expect(grounded.fractionOfWhole == nil)
  #expect(grounded.wholeUnit == nil)
}

@Test func groundingCanonicalizesMeasurementUnitAliasesInBothDirections() {
  let longCandidate = ParsedFoodRequest(
    productName: "steak",
    quantity: 6,
    unit: "ounce"
  )
  let groundedLong = ParsedFoodRequestGrounder().ground(longCandidate, in: "6 oz steak")
  #expect(groundedLong.quantity == 6)
  #expect(groundedLong.unit == "ounce")

  let abbreviatedCandidate = ParsedFoodRequest(
    productName: "steak",
    quantity: 6,
    unit: "oz"
  )
  let groundedAbbreviated = ParsedFoodRequestGrounder().ground(
    abbreviatedCandidate,
    in: "6 ounces of steak"
  )
  #expect(groundedAbbreviated.quantity == 6)
  #expect(groundedAbbreviated.unit == "oz")

  let fluidCandidate = ParsedFoodRequest(
    productName: "juice",
    containerSize: 12,
    containerSizeUnit: "fluid ounce"
  )
  let groundedFluid = ParsedFoodRequestGrounder().ground(
    fluidCandidate,
    in: "a 12 fl oz bottle of juice"
  )
  #expect(groundedFluid.containerSize == 12)
  #expect(groundedFluid.containerSizeUnit == "fluid ounce")

  let tablespoonCandidate = ParsedFoodRequest(
    productName: "oil",
    quantity: 2,
    unit: "tablespoons"
  )
  let groundedTablespoon = ParsedFoodRequestGrounder().ground(
    tablespoonCandidate,
    in: "2 tbsp olive oil"
  )
  #expect(groundedTablespoon.quantity == 2)
  #expect(groundedTablespoon.unit == "tablespoons")
}

@Test func groundingPreservesMixedWrittenAndNumericFractions() {
  let written = ParsedFoodRequest(
    productName: "rice",
    quantity: 1.5,
    unit: "cups"
  )
  let groundedWritten = ParsedFoodRequestGrounder().ground(
    written,
    in: "one and a half cups of rice"
  )
  #expect(groundedWritten.quantity == 1.5)
  #expect(groundedWritten.unit == "cups")

  let numeric = ParsedFoodRequest(
    productName: "rice",
    quantity: 1.5,
    unit: "cups"
  )
  let groundedNumeric = ParsedFoodRequestGrounder().ground(
    numeric,
    in: "1 1/2 cups of rice"
  )
  #expect(groundedNumeric.quantity == 1.5)
  #expect(groundedNumeric.unit == "cups")
}

@Test func groundingPreservesExpandedApproximationMarkers() {
  for source in [
    "nearly one cup rice",
    "approx. one cup rice",
    "~ one cup rice",
    "≈ one cup rice",
  ] {
    let candidate = ParsedFoodRequest(
      productName: "rice",
      quantity: 1,
      unit: "cup",
      isApproximate: true
    )
    let grounded = ParsedFoodRequestGrounder().ground(candidate, in: source)
    #expect(grounded.isApproximate, Comment(rawValue: source))
  }
}

@Test func foodLookupSignatureNormalizesPunctuationAndCase() {
  #expect(FoodLookupSignature.normalize("  Oreo, Cookie! ") == "oreo cookie")
  #expect(FoodLookupSignature.normalize("EGGS and BACON") == "eggs and bacon")
}

@Test func rememberedCatalogPrefersExactSignatureFdcIDs() {
  var catalog = RememberedFoodCatalog()
  catalog.remember(query: "oreo cookie", fdcID: 111, displayName: "OREO COOKIE")
  catalog.remember(query: "banana", fdcID: 222, displayName: "Banana")
  #expect(catalog.preferredFdcIDs(forQuery: "Oreo Cookie") == [111])
  #expect(catalog.preferredFdcIDs(forQuery: "apple") == [])
}

@Test func rememberedSelectionBoostsMatchingResultWithoutFiltering() {
  let parsed = ParsedFoodRequest(productName: "cookie", searchTerms: "cookie")
  let weak = FoodSearchResult(
    fdcID: 1, description: "COOKIE SANDWICH", dataType: "Branded")
  let remembered = FoodSearchResult(
    fdcID: 99, description: "GENERIC COOKIE", dataType: "Branded")
  let other = FoodSearchResult(
    fdcID: 2, description: "CRACKER", dataType: "Branded")

  let ranked = FoodSearchResultRanker().rank(
    [weak, other, remembered],
    for: parsed,
    preferredFdcIDs: [99]
  )
  #expect(ranked.map(\.fdcID).contains(2))
  #expect(
    ranked.first?.fdcID == 99 || ranked.map(\.fdcID).first == 99
      || ranked.firstIndex(where: { $0.fdcID == 99 })! < ranked.firstIndex(where: { $0.fdcID == 2 }
      )!)
  // Remembered cookie outranks unrelated cracker; full set preserved.
  #expect(Set(ranked.map(\.fdcID)) == [1, 2, 99])
}

@Test func twoCookiesResolveViaHouseholdAndGramServingSize() {
  let parsed = ParsedFoodRequest(brand: "Oreo", productName: "cookie", quantity: 2, unit: "cookies")
  let food = FoodDetails(
    fdcID: 1,
    description: "OREO COOKIES",
    dataType: "Branded",
    servingSize: 28,
    servingSizeUnit: "g",
    householdServing: "1 cookie",
    nutrientsPer100Grams: [NutrientAmount(key: .energy, amount: 480)],
    nutrientsPerServing: [NutrientAmount(key: .energy, amount: 134)]
  )
  let outcome = ServingResolutionService().resolve(parsed, against: food)
  guard case .resolved(let resolution) = outcome else {
    Issue.record("Expected 2 cookies to resolve, got \(outcome)")
    return
  }
  #expect(resolution.consumedGrams == 56)
  #expect(resolution.basis == .grams)
}

@Test func twoEggsResolveAgainstHouseholdLargeAndGramServing() {
  let parsed = ParsedFoodRequest(
    productName: "scrambled eggs", quantity: 2, unit: "eggs", quantityText: "two large")
  let food = FoodDetails(
    fdcID: 2,
    description: "Egg, whole, cooked, scrambled",
    dataType: "SR Legacy",
    servingSize: 50,
    servingSizeUnit: "g",
    householdServing: "1 large",
    nutrientsPer100Grams: [NutrientAmount(key: .energy, amount: 148)]
  )
  let outcome = ServingResolutionService().resolve(parsed, against: food)
  guard case .resolved(let resolution) = outcome else {
    Issue.record("Expected 2 eggs → 100 g, got \(outcome)")
    return
  }
  #expect(resolution.consumedGrams == 100)
}

@Test func oneHundredGramsResolvesWithPerHundredGramNutrients() {
  let parsed = ParsedFoodRequest(productName: "chicken", quantity: 100, unit: "g")
  let food = FoodDetails(
    fdcID: 3,
    description: "Chicken",
    dataType: "Foundation",
    nutrientsPer100Grams: [NutrientAmount(key: .energy, amount: 165)]
  )
  let outcome = ServingResolutionService().resolve(parsed, against: food)
  guard case .resolved(let resolution) = outcome else {
    Issue.record("Expected 100 g to resolve, got \(outcome)")
    return
  }
  #expect(resolution.consumedGrams == 100)
  #expect(resolution.basis == .grams)
}

@Test func oneCupMatchesHouseholdCupWithGramServing() {
  let parsed = ParsedFoodRequest(productName: "rice", quantity: 1, unit: "cup")
  let food = FoodDetails(
    fdcID: 4,
    description: "Rice",
    dataType: "Branded",
    servingSize: 158,
    servingSizeUnit: "g",
    householdServing: "1 cup",
    nutrientsPerServing: [NutrientAmount(key: .energy, amount: 200)]
  )
  let outcome = ServingResolutionService().resolve(parsed, against: food)
  guard case .resolved(let resolution) = outcome else {
    Issue.record("Expected 1 cup to resolve, got \(outcome)")
    return
  }
  #expect(resolution.consumedGrams == 158)
}

@Test func unitConversionMassIsExact() {
  #expect(abs((UnitConversion.toGrams(quantity: 1, unit: "oz") ?? 0) - 28.349_523_125) < 1e-9)
  #expect(abs((UnitConversion.convert(quantity: 1000, from: "g", to: "kg") ?? 0) - 1) < 1e-12)
  #expect(UnitConversion.toGrams(quantity: 1, unit: "cup") == nil)  // no invented density
}

@Test func unitConversionVolumeIsExact() {
  let cupML = UnitConversion.toMilliliters(quantity: 1, unit: "cup")!
  let tbspFromCup = UnitConversion.convert(quantity: 1, from: "cup", to: "tbsp")!
  #expect(abs(cupML - 236.588_236_5) < 1e-6)
  #expect(abs(tbspFromCup - 16) < 1e-9)
  #expect(UnitConversion.family("fl oz") == "floz")
  #expect(UnitConversion.family("oz") == "oz")  // weight ≠ fluid
}

@Test func twoTablespoonsResolveViaHouseholdVolumeAndGramServing() {
  let parsed = ParsedFoodRequest(productName: "peanut butter", quantity: 2, unit: "tbsp")
  let food = FoodDetails(
    fdcID: 9,
    description: "Peanut butter",
    dataType: "Branded",
    servingSize: 32,
    servingSizeUnit: "g",
    householdServing: "2 tbsp",
    nutrientsPer100Grams: [NutrientAmount(key: .energy, amount: 600)]
  )
  let outcome = ServingResolutionService().resolve(parsed, against: food)
  guard case .resolved(let resolution) = outcome else {
    Issue.record("Expected 2 tbsp to resolve via household bridge, got \(outcome)")
    return
  }
  #expect(resolution.consumedGrams == 32)
}

@Test func halfCupResolvesAsHalfOfOneCupHousehold() {
  let parsed = ParsedFoodRequest(productName: "rice", quantity: 0.5, unit: "cup")
  let food = FoodDetails(
    fdcID: 10,
    description: "Rice",
    dataType: "Branded",
    servingSize: 158,
    servingSizeUnit: "g",
    householdServing: "1 cup",
    nutrientsPerServing: [NutrientAmount(key: .energy, amount: 200)]
  )
  let outcome = ServingResolutionService().resolve(parsed, against: food)
  guard case .resolved(let resolution) = outcome else {
    Issue.record("Expected ½ cup to resolve, got \(outcome)")
    return
  }
  #expect(abs((resolution.consumedGrams ?? 0) - 79) < 0.001)
}

@Test func oneCupCookedRiceAgainstPackGramsUsesCulinaryDensityNotPackAsCup() {
  // Branded "1 pack (200 g)" is package weight — not equal to 1 cup.
  // Fall back to ~158 g/cup for cooked rice (approx), not 200 g.
  let parsed = ParsedFoodRequest(
    productName: "jasmine rice",
    quantity: 1,
    unit: "cup",
    quantityText: "One cup"
  )
  let food = FoodDetails(
    fdcID: 99,
    description: "JASMINE ORGANIC COOKED RICE, JASMINE",
    dataType: "Branded",
    servingSize: 200,
    servingSizeUnit: "g",
    householdServing: "1 pack",
    nutrientsPer100Grams: [NutrientAmount(key: .energy, amount: 130)],
    nutrientsPerServing: [NutrientAmount(key: .energy, amount: 260)]
  )
  let outcome = ServingResolutionService().resolve(parsed, against: food)
  guard case .resolved(let resolution) = outcome else {
    Issue.record("Expected approx cup→g for cooked rice pack food, got \(outcome)")
    return
  }
  #expect(abs((resolution.consumedGrams ?? 0) - 158) < 0.5)
  #expect(resolution.displayText.lowercased().contains("approx"))
  // Must not treat the 200 g pack as 1 cup.
  #expect(abs((resolution.consumedGrams ?? 0) - 200) > 1)
}

@Test func foodPortionsFillMissingServingForSRLegacyBigMacStyle() {
  // Mirrors FDC 170720 McDONALD'S, BIG MAC: no servingSize, one portion 219 g / item.
  let resolved = FoodPortionServing.resolve(
    servingSize: nil,
    servingSizeUnit: nil,
    householdServing: nil,
    portions: [
      USDAFoodPortion(
        gramWeight: 219,
        amount: 1,
        modifier: "item 7.6 oz",
        measureUnitName: "undetermined",
        measureUnitAbbreviation: "undetermined"
      )
    ]
  )
  #expect(resolved.servingSize == 219)
  #expect(resolved.servingSizeUnit == "g")
  #expect(resolved.householdServing == "1 item 7.6 oz")
}

@Test func foodPortionsPreferNamedItemOverQuantityNotSpecified() {
  // Mirrors FDC 2706916 Survey Big Mac (McDonalds).
  let resolved = FoodPortionServing.resolve(
    servingSize: nil,
    servingSizeUnit: nil,
    householdServing: nil,
    portions: [
      USDAFoodPortion(gramWeight: 205, portionDescription: "Quantity not specified"),
      USDAFoodPortion(gramWeight: 205, portionDescription: "1 McDonald's Big Mac"),
      USDAFoodPortion(gramWeight: 315, portionDescription: "1 McDonald's Grand Mac"),
      USDAFoodPortion(gramWeight: 135, portionDescription: "1 MCDonald's Mac Jr"),
    ]
  )
  #expect(resolved.servingSize == 205)
  #expect(resolved.servingSizeUnit == "g")
  #expect(resolved.householdServing == "1 McDonald's Big Mac")
}

@Test func foodPortionsDoNotOverrideLabeledBrandedServing() {
  let resolved = FoodPortionServing.resolve(
    servingSize: 100,
    servingSizeUnit: "g",
    householdServing: "1 bar",
    portions: [USDAFoodPortion(gramWeight: 50, amount: 1, modifier: "piece")]
  )
  #expect(resolved.servingSize == 100)
  #expect(resolved.servingSizeUnit == "g")
  #expect(resolved.householdServing == "1 bar")
}

@Test func oneServingResolvesWhenPortionsMappedToServingGrams() {
  // App path: user taps "1 serving" after picking SR Big Mac details.
  let parsed = ParsedFoodRequest(
    productName: "Big Mac", quantity: 1, unit: "serving", quantityText: "1 serving")
  let food = FoodDetails(
    fdcID: 170720,
    description: "McDONALD'S, BIG MAC",
    dataType: "SR Legacy",
    servingSize: 219,
    servingSizeUnit: "g",
    householdServing: "1 item 7.6 oz",
    nutrientsPer100Grams: [NutrientAmount(key: .energy, amount: 257)],
    nutrientsPerServing: [NutrientAmount(key: .energy, amount: 257 * 2.19)]
  )
  let outcome = ServingResolutionService().resolve(parsed, against: food)
  guard case .resolved(let resolution) = outcome else {
    Issue.record("Expected 1 serving Big Mac to resolve, got \(outcome)")
    return
  }
  #expect(abs((resolution.consumedGrams ?? 0) - 219) < 0.01)
  #expect(resolution.servingMultiplier == 1 || abs((resolution.servingMultiplier ?? 0) - 1) < 0.01)
}

@Test func compositeComponentRequestKeepsLeadingCountOnBigMac() {
  let request = CompositeComponentRequest.make(from: "1 Big Mac")
  #expect(request.productName == "Big Mac")
  #expect(request.quantity == 1)
  #expect(request.unit == "item")
  #expect(request.searchTerms == "Big Mac")
}

@Test func quantityDefaultFillsOneServingWhenAmountMissing() {
  let bare = ParsedFoodRequest(productName: "Big Mac", searchTerms: "Big Mac")
  let filled = ParsedQuantityDefault.applyingDefaultIfNeeded(bare)
  #expect(filled.quantity == 1)
  #expect(filled.unit == "serving")
  #expect(filled.quantityNeedsClarification == false)

  let already = ParsedFoodRequest(
    productName: "eggs", searchTerms: "eggs", quantity: 2, unit: "large")
  let kept = ParsedQuantityDefault.applyingDefaultIfNeeded(already)
  #expect(kept.quantity == 2)
  #expect(kept.unit == "large")
}

@Test func autoSelectsMultiTokenProductMatchLikeBigMac() {
  let ranked = [
    FoodSearchResult(
      fdcID: 2706916, description: "Big Mac (McDonalds)", dataType: "Survey (FNDDS)"),
    FoodSearchResult(
      fdcID: 1, description: "Macaroni salad", dataType: "Survey (FNDDS)"),
  ]
  let parsed = ParsedFoodRequest(productName: "Big Mac", searchTerms: "Big Mac")
  let pick = FoodSearchAutoSelect.highConfidencePick(ranked: ranked, for: parsed)
  #expect(pick?.fdcID == 2706916)
}

@Test func doesNotAutoSelectGenericSingleTokenFood() {
  let ranked = [
    FoodSearchResult(fdcID: 1, description: "Rice, white, cooked", dataType: "Foundation"),
    FoodSearchResult(fdcID: 2, description: "Brown rice, cooked", dataType: "Foundation"),
  ]
  let parsed = ParsedFoodRequest(productName: "rice", searchTerms: "rice")
  let pick = FoodSearchAutoSelect.highConfidencePick(ranked: ranked, for: parsed)
  #expect(pick == nil)
}

@Test func autoSelectsRememberedFdcEvenAmongSeveral() {
  let ranked = [
    FoodSearchResult(fdcID: 10, description: "Cookie dough", dataType: "Branded"),
    FoodSearchResult(fdcID: 99, description: "OREO cookie", dataType: "Branded"),
  ]
  let parsed = ParsedFoodRequest(productName: "cookie", searchTerms: "cookie")
  let pick = FoodSearchAutoSelect.highConfidencePick(
    ranked: ranked, for: parsed, preferredFdcIDs: [99])
  #expect(pick?.fdcID == 99)
}

@Test func compositeComponentRequestBareNameDefaultsToOneServing() {
  let request = CompositeComponentRequest.make(from: "large fries")
  #expect(request.productName == "large fries")
  #expect(request.quantity == 1)
  #expect(request.unit == "serving")
}

@Test func compositeComponentRequestKeepsExplicitUnit() {
  let request = CompositeComponentRequest.make(from: "2 cups rice")
  #expect(request.productName == "rice")
  #expect(request.quantity == 2)
  #expect(request.unit == "cups")
}
