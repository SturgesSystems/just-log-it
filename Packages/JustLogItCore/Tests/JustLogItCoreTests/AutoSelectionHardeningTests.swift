import Testing

@testable import JustLogItCore

@Test func aSingleWeakUSDAResultDoesNotAutoSelect() {
  let parsed = ParsedFoodRequest(productName: "rice", searchTerms: "rice")
  let result = FoodSearchResult(
    fdcID: 1,
    description: "Rice and vegetables",
    dataType: "Survey (FNDDS)"
  )

  #expect(FoodSearchAutoSelect.highConfidencePick(ranked: [result], for: parsed) == nil)
}

@Test func derivativeProductDoesNotAutoSelectForShorterIdentity() {
  let parsed = ParsedFoodRequest(productName: "chicken soup", searchTerms: "chicken soup")
  let derivative = FoodSearchResult(
    fdcID: 2,
    description: "Chicken soup with rice",
    dataType: "Survey (FNDDS)"
  )

  #expect(FoodSearchAutoSelect.highConfidencePick(ranked: [derivative], for: parsed) == nil)
}

@Test func closeGenericMatchesStayInPicker() {
  let parsed = ParsedFoodRequest(productName: "Greek yogurt", searchTerms: "Greek yogurt")
  let plain = FoodSearchResult(
    fdcID: 3,
    description: "Greek yogurt, plain",
    dataType: "Foundation"
  )
  let strawberry = FoodSearchResult(
    fdcID: 4,
    description: "Greek yogurt, strawberry",
    dataType: "Foundation"
  )

  #expect(
    FoodSearchAutoSelect.highConfidencePick(ranked: [plain, strawberry], for: parsed) == nil
  )
}

@Test func duplicateExactIdentitiesStayInPicker() {
  let parsed = ParsedFoodRequest(productName: "Big Mac", searchTerms: "Big Mac")
  let survey = FoodSearchResult(
    fdcID: 5,
    description: "Big Mac (McDonalds)",
    dataType: "Survey (FNDDS)"
  )
  let legacy = FoodSearchResult(
    fdcID: 6,
    description: "Big Mac",
    dataType: "SR Legacy"
  )

  #expect(FoodSearchAutoSelect.highConfidencePick(ranked: [survey, legacy], for: parsed) == nil)
}

@Test func uniqueExactDistinctiveProductMayAutoSelect() {
  let parsed = ParsedFoodRequest(productName: "Big Mac", searchTerms: "Big Mac")
  let exact = FoodSearchResult(
    fdcID: 7,
    description: "Big Mac (McDonalds)",
    dataType: "Survey (FNDDS)"
  )
  let unrelated = FoodSearchResult(
    fdcID: 8,
    description: "Macaroni salad",
    dataType: "Branded"
  )

  #expect(
    FoodSearchAutoSelect.highConfidencePick(ranked: [exact, unrelated], for: parsed)?.fdcID
      == exact.fdcID
  )
}

@Test func explicitBrandMustMatchBrandMetadataAndExactProduct() {
  let parsed = ParsedFoodRequest(
    brand: "Oreo",
    productName: "cookie",
    searchTerms: "Oreo cookie"
  )
  let brandedCookie = FoodSearchResult(
    fdcID: 9,
    description: "OREO COOKIE",
    brandOwner: "Mondelez",
    brandName: "Oreo",
    dataType: "Branded"
  )
  let restaurantDerivative = FoodSearchResult(
    fdcID: 10,
    description: "McFlurry with OREO cookies",
    brandOwner: "McDonald's",
    brandName: "McDonald's",
    dataType: "Branded"
  )

  #expect(
    FoodSearchAutoSelect.highConfidencePick(
      ranked: [brandedCookie, restaurantDerivative],
      for: parsed
    )?.fdcID == brandedCookie.fdcID
  )
  #expect(
    FoodSearchAutoSelect.highConfidencePick(
      ranked: [restaurantDerivative],
      for: parsed
    ) == nil
  )
}
