import Foundation
import JustLogItCore
import XCTest

@testable import JustLogIt

final class USDAFoodDataProviderContractTests: XCTestCase {
  override func setUp() {
    super.setUp()
    URLProtocolStub.reset()
  }

  override func tearDown() {
    URLProtocolStub.reset()
    super.tearDown()
  }

  #if DEBUG
    func testDirectSearchRequestUsesExpectedMethodBodyAndRedactedAPIKeyQuery() async throws {
      let apiKey = "contract-test-key-not-a-secret"
      let url = try XCTUnwrap(
        URL(string: "https://api.nal.usda.gov/fdc/v1/foods/search?api_key=\(apiKey)"))
      URLProtocolStub.register(
        url: url,
        response: .json(
          #"{"totalHits":1,"currentPage":2,"totalPages":3,"foods":[{"fdcId":42,"description":"Egg, whole","dataType":"Foundation"}]}"#
        ))
      let provider = USDAFoodDataProvider(
        endpoint: .directUSDA(apiKey: apiKey), session: makeStubbedSession())
      let request = FoodSearchRequest(
        query: "large eggs",
        normalizedKey: "large eggs",
        dataTypes: ["Foundation", "Branded"],
        page: 2,
        pageSize: 25)

      let response = try await provider.search(request)

      XCTAssertEqual(response.foods.first?.fdcID, 42)
      XCTAssertEqual(response.currentPage, 2)
      let captured = try XCTUnwrap(URLProtocolStub.capturedRequest(for: url))
      XCTAssertEqual(captured.httpMethod, "POST")
      XCTAssertEqual(captured.url?.scheme, "https")
      XCTAssertEqual(captured.url?.host, "api.nal.usda.gov")
      XCTAssertEqual(captured.url?.path, "/fdc/v1/foods/search")
      XCTAssertEqual(
        URLComponents(url: try XCTUnwrap(captured.url), resolvingAgainstBaseURL: false)?
          .queryItems,
        [URLQueryItem(name: "api_key", value: apiKey)])
      XCTAssertEqual(captured.value(forHTTPHeaderField: "Content-Type"), "application/json")

      let body = try XCTUnwrap(captured.httpBody)
      let object = try XCTUnwrap(
        JSONSerialization.jsonObject(with: body) as? [String: Any])
      XCTAssertEqual(object["query"] as? String, "large eggs")
      XCTAssertEqual(object["pageSize"] as? Int, 25)
      XCTAssertEqual(object["pageNumber"] as? Int, 2)
      XCTAssertEqual(object["dataType"] as? [String], ["Foundation", "Branded"])
      XCTAssertFalse(String(decoding: body, as: UTF8.self).contains(apiKey))
    }

    func testDirectDetailsPathAndRichUSDAFixtureMapping() async throws {
      let apiKey = "details-contract-key-not-a-secret"
      let fdcID = 123_456
      let url = try XCTUnwrap(
        URL(string: "https://api.nal.usda.gov/fdc/v1/food/\(fdcID)?api_key=\(apiKey)"))
      URLProtocolStub.register(url: url, response: .json(Self.richDetailsFixture))
      let provider = USDAFoodDataProvider(
        endpoint: .directUSDA(apiKey: apiKey), session: makeStubbedSession())

      let details = try await provider.foodDetails(fdcID: fdcID)

      let captured = try XCTUnwrap(URLProtocolStub.capturedRequest(for: url))
      XCTAssertEqual(captured.httpMethod, "GET")
      XCTAssertEqual(captured.url?.path, "/fdc/v1/food/123456")
      XCTAssertNil(captured.httpBody)
      XCTAssertEqual(details.fdcID, fdcID)
      XCTAssertEqual(details.description, "Egg, whole, cooked, sample fixture")
      XCTAssertEqual(details.brandOwner, "Redacted Test Foods")
      XCTAssertEqual(details.publicationDate, "2025-01-02")
      XCTAssertEqual(details.servingSize, 50)
      XCTAssertEqual(details.servingSizeUnit, "g")
      XCTAssertEqual(details.householdServing, "1 large egg")

      XCTAssertEqual(details.foodPortions.count, 3)
      XCTAssertEqual(details.foodPortions[0].gramWeight, 243)
      XCTAssertEqual(details.foodPortions[0].measureUnitName, "cup")
      XCTAssertEqual(details.foodPortions[1].modifier, "large")
      XCTAssertEqual(details.foodPortions[1].portionDescription, "1 large egg")
      XCTAssertEqual(details.foodPortions[2].amount, 1)
      XCTAssertEqual(details.foodPortions[2].measureUnitAbbreviation, "tbsp")

      XCTAssertEqual(try nutrient(.energy, in: details.nutrientsPer100Grams).amount, 143)
      XCTAssertEqual(try nutrient(.protein, in: details.nutrientsPer100Grams).amount, 12.6)
      XCTAssertEqual(try nutrient(.sodium, in: details.nutrientsPer100Grams).amount, 142)
      XCTAssertEqual(try nutrient(.energy, in: details.nutrientsPerServing).amount, 90)
      XCTAssertEqual(try nutrient(.protein, in: details.nutrientsPerServing).amount, 6)
      XCTAssertEqual(
        try nutrient(.carbohydrate, in: details.nutrientsPerServing).amount,
        0.35,
        accuracy: 0.000_1)
      XCTAssertEqual(
        try nutrient(.sodium, in: details.nutrientsPerServing).amount,
        71,
        accuracy: 0.000_1)
    }
  #endif

  func testProxySearchRequestUsesExpectedMethodPathBodyAndNoSecretTransport() async throws {
    let baseURL = try XCTUnwrap(URL(string: "https://proxy.example.test/"))
    let url = baseURL.appending(path: "v1/foods/search")
    URLProtocolStub.register(
      url: url,
      response: .json(#"{"totalHits":0,"currentPage":1,"totalPages":0,"foods":[]}"#))
    let provider = USDAFoodDataProvider(endpoint: .proxy(baseURL), session: makeStubbedSession())
    let request = FoodSearchRequest(
      query: "plain yogurt",
      normalizedKey: "plain yogurt",
      dataTypes: ["Foundation", "FNDDS"],
      page: 3,
      pageSize: 40
    )

    _ = try await provider.search(request)

    let captured = try XCTUnwrap(URLProtocolStub.capturedRequest(for: url))
    XCTAssertEqual(captured.httpMethod, "POST")
    XCTAssertEqual(captured.url?.scheme, "https")
    XCTAssertEqual(captured.url?.host, "proxy.example.test")
    XCTAssertEqual(captured.url?.path, "/v1/foods/search")
    XCTAssertNil(captured.url?.query)
    XCTAssertEqual(captured.value(forHTTPHeaderField: "Content-Type"), "application/json")
    XCTAssertNil(captured.value(forHTTPHeaderField: "Authorization"))
    XCTAssertNil(captured.value(forHTTPHeaderField: "X-API-Key"))
    XCTAssertFalse(
      captured.allHTTPHeaderFields?.keys.contains(where: {
        $0.localizedCaseInsensitiveContains("api-key")
          || $0.localizedCaseInsensitiveContains("apikey")
      }) ?? false
    )

    let body = try XCTUnwrap(captured.httpBody)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
    XCTAssertEqual(object["query"] as? String, "plain yogurt")
    XCTAssertEqual(object["pageSize"] as? Int, 40)
    XCTAssertEqual(object["pageNumber"] as? Int, 3)
    XCTAssertEqual(object["dataType"] as? [String], ["Foundation", "FNDDS"])
    XCTAssertEqual(Set(object.keys), ["query", "pageSize", "pageNumber", "dataType"])
  }

  func test400MapsToInvalidRequest() async throws {
    let baseURL = try XCTUnwrap(URL(string: "https://bad-request.example.test/"))
    let url = baseURL.appending(path: "v1/foods/search")
    URLProtocolStub.register(url: url, response: .init(statusCode: 400))
    let provider = USDAFoodDataProvider(endpoint: .proxy(baseURL), session: makeStubbedSession())

    do {
      _ = try await provider.search(Self.searchRequest)
      XCTFail("Expected invalid request")
    } catch let error as FoodDataError {
      XCTAssertEqual(error, .invalidRequest)
    }
  }

  func test401And403MapToUnauthorized() async throws {
    for statusCode in [401, 403] {
      URLProtocolStub.reset()
      let baseURL = try XCTUnwrap(URL(string: "https://auth-\(statusCode).example.test/"))
      let url = baseURL.appending(path: "v1/foods/search")
      URLProtocolStub.register(url: url, response: .init(statusCode: statusCode))
      let provider = USDAFoodDataProvider(endpoint: .proxy(baseURL), session: makeStubbedSession())

      do {
        _ = try await provider.search(Self.searchRequest)
        XCTFail("Expected unauthorized for HTTP \(statusCode)")
      } catch let error as FoodDataError {
        XCTAssertEqual(error, .unauthorized)
      }
    }
  }

  func testURLSessionTimeoutPropagatesAsTimedOutTransportError() async throws {
    let baseURL = try XCTUnwrap(URL(string: "https://timeout.example.test/"))
    let url = baseURL.appending(path: "v1/foods/search")
    URLProtocolStub.register(url: url, failure: .timedOut)
    let observations = USDAContractObservationRecorder()
    let provider = USDAFoodDataProvider(
      endpoint: .proxy(baseURL),
      session: makeStubbedSession(),
      observer: observations.observer)

    do {
      _ = try await provider.search(Self.searchRequest)
      XCTFail("Expected a URLSession timeout")
    } catch let error as URLError {
      XCTAssertEqual(error.code, .timedOut)
    }
    XCTAssertEqual(
      observations.events,
      [.transport(resource: .search, outcome: .timedOut)])
  }

  func testTransportFailuresAreClassifiedWithoutChangingPropagatedError() async throws {
    let cases: [(URLError.Code, AppObservability.USDATransportOutcome)] = [
      (.notConnectedToInternet, .offline),
      (.networkConnectionLost, .offline),
      (.dnsLookupFailed, .offline),
      (.cannotFindHost, .offline),
      (.cannotConnectToHost, .offline),
      (.cancelled, .cancelled),
      (.badServerResponse, .other),
    ]

    for (index, testCase) in cases.enumerated() {
      URLProtocolStub.reset()
      let baseURL = try XCTUnwrap(URL(string: "https://transport-\(index).example.test/"))
      let url = baseURL.appending(path: "v1/foods/search")
      URLProtocolStub.register(url: url, failure: testCase.0)
      let observations = USDAContractObservationRecorder()
      let provider = USDAFoodDataProvider(
        endpoint: .proxy(baseURL),
        session: makeStubbedSession(),
        observer: observations.observer)

      do {
        _ = try await provider.search(Self.searchRequest)
        XCTFail("Expected transport error \(testCase.0)")
      } catch let error as URLError {
        XCTAssertEqual(error.code, testCase.0, "Provider must propagate the original URL error")
      }
      XCTAssertEqual(
        observations.events,
        [.transport(resource: .search, outcome: testCase.1)])
    }
  }

  func testNonHTTPResponseMapsToInvalidResponse() async throws {
    let baseURL = try XCTUnwrap(URL(string: "https://non-http.example.test/"))
    let url = baseURL.appending(path: "v1/foods/search")
    URLProtocolStub.registerNonHTTP(url: url, data: Data(#"{"foods":[]}"#.utf8))
    let provider = USDAFoodDataProvider(endpoint: .proxy(baseURL), session: makeStubbedSession())

    do {
      _ = try await provider.search(Self.searchRequest)
      XCTFail("Expected a non-HTTP response to fail validation")
    } catch let error as FoodDataError {
      XCTAssertEqual(error, .invalidResponse)
    }
  }

  func testNullableSearchAndDetailDTOsDecodeAcrossAllUSDADataTypes() async throws {
    let baseURL = try XCTUnwrap(URL(string: "https://nullable.example.test/"))
    let searchURL = baseURL.appending(path: "v1/foods/search")
    let types = ["Branded", "Survey (FNDDS)", "SR Legacy", "Foundation"]
    let foods: [[String: Any]] = types.enumerated().map { index, dataType in
      [
        "fdcId": 1_000 + index,
        "description": "Nullable fixture \(dataType)",
        "dataType": dataType,
        "brandOwner": NSNull(),
        "brandName": NSNull(),
        "gtinUpc": NSNull(),
        "servingSize": NSNull(),
        "servingSizeUnit": NSNull(),
        "householdServingFullText": NSNull(),
      ]
    }
    let searchData = try JSONSerialization.data(withJSONObject: ["foods": foods])
    URLProtocolStub.register(
      url: searchURL,
      response: .init(
        statusCode: 200,
        headers: ["Content-Type": "application/json"],
        data: searchData
      )
    )
    for (index, dataType) in types.enumerated() {
      let fdcID = 1_000 + index
      let detailsURL = baseURL.appending(path: "v1/foods/\(fdcID)")
      let detail: [String: Any] = [
        "fdcId": fdcID,
        "description": "Nullable fixture \(dataType)",
        "dataType": dataType,
        "brandOwner": NSNull(),
        "servingSize": NSNull(),
        "servingSizeUnit": NSNull(),
        "householdServingFullText": NSNull(),
        "publicationDate": NSNull(),
        "foodNutrients": NSNull(),
        "labelNutrients": NSNull(),
        "foodPortions": NSNull(),
      ]
      URLProtocolStub.register(
        url: detailsURL,
        response: .init(
          statusCode: 200,
          headers: ["Content-Type": "application/json"],
          data: try JSONSerialization.data(withJSONObject: detail)
        )
      )
    }
    let provider = USDAFoodDataProvider(endpoint: .proxy(baseURL), session: makeStubbedSession())

    let search = try await provider.search(Self.searchRequest)

    XCTAssertEqual(search.totalHits, 4)
    XCTAssertEqual(search.currentPage, 1)
    XCTAssertEqual(search.totalPages, 1)
    XCTAssertEqual(search.foods.map(\.dataType), types)
    for food in search.foods {
      XCTAssertNil(food.brandOwner)
      XCTAssertNil(food.brandName)
      XCTAssertNil(food.servingSize)
      let details = try await provider.foodDetails(fdcID: food.fdcID)
      XCTAssertEqual(details.dataType, food.dataType)
      XCTAssertNil(details.brandOwner)
      XCTAssertNil(details.servingSize)
      XCTAssertNil(details.servingSizeUnit)
      XCTAssertNil(details.householdServing)
      XCTAssertTrue(details.foodPortions.isEmpty)
      XCTAssertTrue(details.nutrientsPer100Grams.isEmpty)
      XCTAssertTrue(details.nutrientsPerServing.isEmpty)
    }
  }

  func testEverySupportedNutrientMapsToItsCanonicalUnit() async throws {
    let baseURL = try XCTUnwrap(URL(string: "https://nutrients.example.test/"))
    let fdcID = 77_777
    let url = baseURL.appending(path: "v1/foods/\(fdcID)")
    let specs = Self.canonicalNutrientSpecs
    XCTAssertEqual(Set(specs.map(\.key)), Set(NutrientKey.allCases))
    let foodNutrients: [[String: Any]] = specs.map { spec in
      [
        "nutrient": ["id": spec.id, "name": spec.name, "unitName": spec.sourceUnit],
        "amount": spec.sourceAmount,
      ]
    }
    let fixture: [String: Any] = [
      "fdcId": fdcID,
      "description": "Canonical nutrient fixture",
      "dataType": "Foundation",
      "foodNutrients": foodNutrients,
    ]
    URLProtocolStub.register(
      url: url,
      response: .init(
        statusCode: 200,
        headers: ["Content-Type": "application/json"],
        data: try JSONSerialization.data(withJSONObject: fixture)
      )
    )
    let provider = USDAFoodDataProvider(endpoint: .proxy(baseURL), session: makeStubbedSession())

    let details = try await provider.foodDetails(fdcID: fdcID)

    XCTAssertEqual(Set(details.nutrientsPer100Grams.map(\.key)), Set(NutrientKey.allCases))
    for spec in specs {
      let mapped = try nutrient(spec.key, in: details.nutrientsPer100Grams)
      XCTAssertEqual(mapped.unit, spec.key.canonicalUnit, "Wrong unit for \(spec.key)")
      XCTAssertEqual(
        mapped.amount,
        spec.expectedAmount,
        accuracy: 0.000_001,
        "Wrong amount for \(spec.key)"
      )
    }
  }

  func testDetails404MapsToNotFound() async throws {
    let baseURL = try XCTUnwrap(URL(string: "https://not-found.example.test/"))
    let url = baseURL.appending(path: "v1/foods/987")
    URLProtocolStub.register(url: url, response: .init(statusCode: 404))
    let provider = USDAFoodDataProvider(endpoint: .proxy(baseURL), session: makeStubbedSession())

    do {
      _ = try await provider.foodDetails(fdcID: 987)
      XCTFail("Expected a 404 error")
    } catch let error as FoodDataError {
      XCTAssertEqual(error, .notFound)
    }
  }

  func test429NormalizesRetryAfterBeforeUserFacingCopy() async throws {
    let baseURL = try XCTUnwrap(URL(string: "https://rate-limit.example.test/"))
    let url = baseURL.appending(path: "v1/foods/search")
    URLProtocolStub.register(
      url: url,
      response: .init(statusCode: 429, headers: ["Retry-After": "120"]))
    let provider = USDAFoodDataProvider(endpoint: .proxy(baseURL), session: makeStubbedSession())

    do {
      _ = try await provider.search(Self.searchRequest)
      XCTFail("Expected a rate-limit error")
    } catch let error as FoodDataError {
      XCTAssertEqual(error, .rateLimited(retryAfter: "120 seconds"))
      XCTAssertEqual(
        error.errorDescription,
        "Food search is temporarily rate-limited. Try again after 120 seconds, or enter nutrition manually."
      )
    }
  }

  func testUntrustedRetryAfterTextIsNotReflectedIntoUserFacingCopy() async throws {
    let baseURL = try XCTUnwrap(URL(string: "https://unsafe-header.example.test/"))
    let url = baseURL.appending(path: "v1/foods/search")
    let untrustedValue = "later <script>alert(1)</script>"
    URLProtocolStub.register(
      url: url,
      response: .init(statusCode: 429, headers: ["Retry-After": untrustedValue]))
    let provider = USDAFoodDataProvider(endpoint: .proxy(baseURL), session: makeStubbedSession())

    do {
      _ = try await provider.search(Self.searchRequest)
      XCTFail("Expected a rate-limit error")
    } catch let error as FoodDataError {
      XCTAssertEqual(error, .rateLimited(retryAfter: nil))
      XCTAssertFalse(error.errorDescription?.contains(untrustedValue) ?? true)
      XCTAssertEqual(
        error.errorDescription,
        "Food search is temporarily rate-limited. Try again later, or enter nutrition manually."
      )
    }
  }

  func test5xxMapsToServerErrorWithoutReflectingResponseBody() async throws {
    let baseURL = try XCTUnwrap(URL(string: "https://server-error.example.test/"))
    let url = baseURL.appending(path: "v1/foods/search")
    URLProtocolStub.register(
      url: url,
      response: .init(
        statusCode: 503,
        data: Data("upstream internal diagnostics".utf8)))
    let provider = USDAFoodDataProvider(endpoint: .proxy(baseURL), session: makeStubbedSession())

    do {
      _ = try await provider.search(Self.searchRequest)
      XCTFail("Expected a server error")
    } catch let error as FoodDataError {
      XCTAssertEqual(error, .server(status: 503))
      XCTAssertEqual(
        error.errorDescription,
        "The food service is temporarily unavailable. Try again later, or enter nutrition manually."
      )
      XCTAssertFalse(error.errorDescription?.contains("diagnostics") ?? true)
    }
  }

  func testMalformedSuccessfulSearchJSONMapsToInvalidResponse() async throws {
    let baseURL = try XCTUnwrap(URL(string: "https://malformed.example.test/"))
    let url = baseURL.appending(path: "v1/foods/search")
    URLProtocolStub.register(
      url: url,
      response: .init(statusCode: 200, data: Data(#"{"foods":"not-an-array"}"#.utf8)))
    let provider = USDAFoodDataProvider(endpoint: .proxy(baseURL), session: makeStubbedSession())

    do {
      _ = try await provider.search(Self.searchRequest)
      XCTFail("Expected malformed JSON to fail")
    } catch let error as FoodDataError {
      XCTAssertEqual(error, .invalidResponse)
    }
  }

  private static let searchRequest = FoodSearchRequest(
    query: "eggs", normalizedKey: "eggs", dataTypes: [], page: 1, pageSize: 20)

  private func makeStubbedSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [URLProtocolStub.self]
    return URLSession(configuration: configuration)
  }

  private func nutrient(_ key: NutrientKey, in values: [NutrientAmount]) throws -> NutrientAmount {
    try XCTUnwrap(values.first { $0.key == key }, "Missing \(key.rawValue) nutrient")
  }

  private static let richDetailsFixture = #"""
    {
      "fdcId": 123456,
      "description": "Egg, whole, cooked, sample fixture",
      "dataType": "Foundation",
      "brandOwner": "Redacted Test Foods",
      "servingSize": 50,
      "servingSizeUnit": "g",
      "householdServingFullText": "1 large egg",
      "publicationDate": "2025-01-02",
      "foodPortions": [
        {
          "gramWeight": 243,
          "amount": 1,
          "portionDescription": "1 cup",
          "measureUnit": { "name": "cup", "abbreviation": "cup" }
        },
        {
          "gramWeight": 50,
          "amount": 1,
          "modifier": "large",
          "portionDescription": "1 large egg",
          "measureUnit": { "name": "item", "abbreviation": "item" }
        },
        {
          "gramWeight": 15,
          "value": 1,
          "portionDescription": "1 tablespoon",
          "measureUnit": { "name": "tablespoon", "abbreviation": "tbsp" }
        }
      ],
      "foodNutrients": [
        { "nutrient": { "id": 1008, "name": "Energy", "unitName": "kcal" }, "amount": 143 },
        { "nutrient": { "id": 1003, "name": "Protein", "unitName": "g" }, "amount": 12.6 },
        { "nutrient": { "id": 1004, "name": "Total lipid (fat)", "unitName": "g" }, "amount": 9.5 },
        { "nutrient": { "id": 1005, "name": "Carbohydrate, by difference", "unitName": "g" }, "amount": 0.7 },
        { "nutrient": { "id": 1093, "name": "Sodium, Na", "unitName": "mg" }, "amount": 142 }
      ],
      "labelNutrients": {
        "calories": { "value": 90 },
        "protein": { "value": 6 }
      }
    }
    """#

  private struct NutrientSpec {
    let key: NutrientKey
    let id: Int
    let name: String
    let sourceUnit: String
    let sourceAmount: Double
    let expectedAmount: Double
  }

  private static let canonicalNutrientSpecs: [NutrientSpec] = [
    .init(
      key: .energy, id: 1008, name: "Energy", sourceUnit: "kcal", sourceAmount: 10,
      expectedAmount: 10),
    .init(
      key: .protein, id: 1003, name: "Protein", sourceUnit: "mg", sourceAmount: 2_000,
      expectedAmount: 2),
    .init(
      key: .carbohydrate, id: 1005, name: "Carbohydrate, by difference", sourceUnit: "g",
      sourceAmount: 3, expectedAmount: 3),
    .init(
      key: .totalFat, id: 1004, name: "Total lipid (fat)", sourceUnit: "g", sourceAmount: 4,
      expectedAmount: 4),
    .init(
      key: .saturatedFat, id: 1258, name: "Fatty acids, total saturated", sourceUnit: "g",
      sourceAmount: 5, expectedAmount: 5),
    .init(
      key: .monounsaturatedFat, id: 1292, name: "Fatty acids, total monounsaturated",
      sourceUnit: "g", sourceAmount: 6, expectedAmount: 6),
    .init(
      key: .polyunsaturatedFat, id: 1293, name: "Fatty acids, total polyunsaturated",
      sourceUnit: "g", sourceAmount: 7, expectedAmount: 7),
    .init(
      key: .cholesterol, id: 1253, name: "Cholesterol", sourceUnit: "g", sourceAmount: 0.008,
      expectedAmount: 8),
    .init(
      key: .fiber, id: 1079, name: "Fiber, total dietary", sourceUnit: "g", sourceAmount: 9,
      expectedAmount: 9),
    .init(
      key: .totalSugar, id: 2000, name: "Sugars, total including NLEA", sourceUnit: "g",
      sourceAmount: 10, expectedAmount: 10),
    .init(
      key: .addedSugar, id: 1235, name: "Sugars, added", sourceUnit: "g", sourceAmount: 11,
      expectedAmount: 11),
    .init(
      key: .sodium, id: 1093, name: "Sodium, Na", sourceUnit: "mg", sourceAmount: 12,
      expectedAmount: 12),
    .init(
      key: .calcium, id: 1087, name: "Calcium, Ca", sourceUnit: "g", sourceAmount: 0.013,
      expectedAmount: 13),
    .init(
      key: .iron, id: 1089, name: "Iron, Fe", sourceUnit: "mg", sourceAmount: 14, expectedAmount: 14
    ),
    .init(
      key: .potassium, id: 1092, name: "Potassium, K", sourceUnit: "mg", sourceAmount: 15,
      expectedAmount: 15),
    .init(
      key: .vitaminD, id: 1114, name: "Vitamin D (D2 + D3)", sourceUnit: "mg", sourceAmount: 0.016,
      expectedAmount: 16),
    .init(
      key: .caffeine, id: 1057, name: "Caffeine", sourceUnit: "mg", sourceAmount: 17,
      expectedAmount: 17),
    .init(
      key: .water, id: 1078, name: "Water", sourceUnit: "g", sourceAmount: 18, expectedAmount: 18),
    .init(
      key: .biotin, id: 1176, name: "Biotin", sourceUnit: "ug", sourceAmount: 19, expectedAmount: 19
    ),
    .init(
      key: .chloride, id: 1088, name: "Chloride, Cl", sourceUnit: "mg", sourceAmount: 20,
      expectedAmount: 20),
    .init(
      key: .chromium, id: 1096, name: "Chromium, Cr", sourceUnit: "ug", sourceAmount: 21,
      expectedAmount: 21),
    .init(
      key: .copper, id: 1098, name: "Copper, Cu", sourceUnit: "mg", sourceAmount: 22,
      expectedAmount: 22),
    .init(
      key: .folate, id: 1177, name: "Folate, total", sourceUnit: "ug", sourceAmount: 23,
      expectedAmount: 23),
    .init(
      key: .iodine, id: 1100, name: "Iodine, I", sourceUnit: "ug", sourceAmount: 24,
      expectedAmount: 24),
    .init(
      key: .magnesium, id: 1090, name: "Magnesium, Mg", sourceUnit: "mg", sourceAmount: 25,
      expectedAmount: 25),
    .init(
      key: .manganese, id: 1101, name: "Manganese, Mn", sourceUnit: "mg", sourceAmount: 26,
      expectedAmount: 26),
    .init(
      key: .molybdenum, id: 1102, name: "Molybdenum, Mo", sourceUnit: "ug", sourceAmount: 27,
      expectedAmount: 27),
    .init(
      key: .niacin, id: 1167, name: "Niacin", sourceUnit: "mg", sourceAmount: 28, expectedAmount: 28
    ),
    .init(
      key: .pantothenicAcid, id: 1170, name: "Pantothenic acid", sourceUnit: "mg", sourceAmount: 29,
      expectedAmount: 29),
    .init(
      key: .phosphorus, id: 1091, name: "Phosphorus, P", sourceUnit: "mg", sourceAmount: 30,
      expectedAmount: 30),
    .init(
      key: .riboflavin, id: 1166, name: "Riboflavin", sourceUnit: "mg", sourceAmount: 31,
      expectedAmount: 31),
    .init(
      key: .selenium, id: 1103, name: "Selenium, Se", sourceUnit: "ug", sourceAmount: 32,
      expectedAmount: 32),
    .init(
      key: .thiamin, id: 1165, name: "Thiamin", sourceUnit: "mg", sourceAmount: 33,
      expectedAmount: 33),
    .init(
      key: .vitaminA, id: 1106, name: "Vitamin A, RAE", sourceUnit: "ug", sourceAmount: 34,
      expectedAmount: 34),
    .init(
      key: .vitaminB12, id: 1178, name: "Vitamin B-12", sourceUnit: "ug", sourceAmount: 35,
      expectedAmount: 35),
    .init(
      key: .vitaminB6, id: 1175, name: "Vitamin B-6", sourceUnit: "mg", sourceAmount: 36,
      expectedAmount: 36),
    .init(
      key: .vitaminC, id: 1162, name: "Vitamin C, total ascorbic acid", sourceUnit: "g",
      sourceAmount: 0.037, expectedAmount: 37),
    .init(
      key: .vitaminE, id: 1109, name: "Vitamin E (alpha-tocopherol)", sourceUnit: "mg",
      sourceAmount: 38, expectedAmount: 38),
    .init(
      key: .vitaminK, id: 1185, name: "Vitamin K (phylloquinone)", sourceUnit: "ug",
      sourceAmount: 39, expectedAmount: 39),
    .init(
      key: .zinc, id: 1095, name: "Zinc, Zn", sourceUnit: "mg", sourceAmount: 40, expectedAmount: 40
    ),
  ]
}

private final class USDAContractObservationRecorder: @unchecked Sendable {
  private let queue = DispatchQueue(label: "USDAContractObservationRecorder")
  private var storedEvents: [AppObservability.USDAEvent] = []

  var observer: AppObservability.USDAObserver {
    { [weak self] event in self?.record(event) }
  }

  var events: [AppObservability.USDAEvent] {
    queue.sync { storedEvents }
  }

  private func record(_ event: AppObservability.USDAEvent) {
    queue.sync { storedEvents.append(event) }
  }
}

private final class URLProtocolStub: URLProtocol, @unchecked Sendable {
  struct Response: Sendable {
    let statusCode: Int
    let headers: [String: String]
    let data: Data

    init(statusCode: Int, headers: [String: String] = [:], data: Data = Data()) {
      self.statusCode = statusCode
      self.headers = headers
      self.data = data
    }

    static func json(_ value: String, statusCode: Int = 200) -> Response {
      Response(
        statusCode: statusCode,
        headers: ["Content-Type": "application/json"],
        data: Data(value.utf8))
    }
  }

  private static let lock = NSLock()
  private enum Outcome: Sendable {
    case response(Response)
    case failure(URLError.Code)
    case nonHTTP(Data)
  }

  nonisolated(unsafe) private static var outcomes: [String: Outcome] = [:]
  nonisolated(unsafe) private static var requests: [String: URLRequest] = [:]

  static func register(url: URL, response: Response) {
    lock.lock()
    outcomes[url.absoluteString] = .response(response)
    lock.unlock()
  }

  static func register(url: URL, failure: URLError.Code) {
    lock.lock()
    outcomes[url.absoluteString] = .failure(failure)
    lock.unlock()
  }

  static func registerNonHTTP(url: URL, data: Data = Data()) {
    lock.lock()
    outcomes[url.absoluteString] = .nonHTTP(data)
    lock.unlock()
  }

  static func reset() {
    lock.lock()
    outcomes.removeAll()
    requests.removeAll()
    lock.unlock()
  }

  static func capturedRequest(for url: URL) -> URLRequest? {
    lock.lock()
    defer { lock.unlock() }
    return requests[url.absoluteString]
  }

  override class func canInit(with request: URLRequest) -> Bool { true }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    guard let url = request.url else {
      client?.urlProtocol(self, didFailWithError: URLError(.badURL))
      return
    }

    var capturedRequest = request
    if capturedRequest.httpBody == nil, let stream = capturedRequest.httpBodyStream {
      capturedRequest.httpBody = Self.readAllBytes(from: stream)
    }
    Self.lock.lock()
    Self.requests[url.absoluteString] = capturedRequest
    let outcome = Self.outcomes[url.absoluteString]
    Self.lock.unlock()

    guard let outcome else {
      client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
      return
    }
    switch outcome {
    case .failure(let code):
      client?.urlProtocol(self, didFailWithError: URLError(code))
    case .nonHTTP(let data):
      let response = URLResponse(
        url: url,
        mimeType: "application/json",
        expectedContentLength: data.count,
        textEncodingName: "utf-8"
      )
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: data)
      client?.urlProtocolDidFinishLoading(self)
    case .response(let response):
      guard
        let httpResponse = HTTPURLResponse(
          url: url,
          statusCode: response.statusCode,
          httpVersion: "HTTP/1.1",
          headerFields: response.headers)
      else {
        client?.urlProtocol(self, didFailWithError: URLError(.cannotParseResponse))
        return
      }
      client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: response.data)
      client?.urlProtocolDidFinishLoading(self)
    }
  }

  override func stopLoading() {}

  private static func readAllBytes(from stream: InputStream) -> Data {
    stream.open()
    defer { stream.close() }
    var result = Data()
    var buffer = [UInt8](repeating: 0, count: 4_096)
    while stream.hasBytesAvailable {
      let count = stream.read(&buffer, maxLength: buffer.count)
      guard count > 0 else { break }
      result.append(buffer, count: count)
    }
    return result
  }
}
