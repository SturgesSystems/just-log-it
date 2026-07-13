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
