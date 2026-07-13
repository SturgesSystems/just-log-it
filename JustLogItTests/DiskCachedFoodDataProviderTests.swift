import Foundation
import JustLogItCore
import XCTest

@testable import JustLogIt

final class DiskCachedFoodDataProviderTests: XCTestCase {
  private var directory: URL!
  private var fixedNow: Date!

  override func setUp() {
    super.setUp()
    directory = FileManager.default.temporaryDirectory
      .appending(path: "JustLogItFoodCacheTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    fixedNow = Date(timeIntervalSinceReferenceDate: 1_000_000)
  }

  override func tearDown() {
    try? FileManager.default.removeItem(at: directory)
    directory = nil
    fixedNow = nil
    super.tearDown()
  }

  func testCorruptedSearchJSONFallsThroughToUpstream() async throws {
    let request = sampleSearchRequest()
    let url = cacheFileURL(kind: "search", key: searchKey(for: request))
    try Data("{not-json".utf8).write(to: url)

    let upstream = FakeUpstream(searchResponse: sampleSearchResponse())
    let provider = makeProvider(upstream: upstream)

    let response = try await provider.search(request)

    XCTAssertEqual(response, sampleSearchResponse())
    let calls = await upstream.searchCalls
    XCTAssertEqual(calls, 1)
  }

  func testExpiredSearchEnvelopeIsTreatedAsMiss() async throws {
    let request = sampleSearchRequest()
    let url = cacheFileURL(kind: "search", key: searchKey(for: request))
    let stale = sampleSearchResponse(description: "Stale cache")
    try writeEnvelope(value: stale, expiresAt: fixedNow.addingTimeInterval(-60), to: url)

    let upstream = FakeUpstream(searchResponse: sampleSearchResponse(description: "Fresh"))
    let provider = makeProvider(upstream: upstream)

    let response = try await provider.search(request)

    XCTAssertEqual(response.foods.first?.description, "Fresh")
    let calls = await upstream.searchCalls
    XCTAssertEqual(calls, 1)
  }

  func testUnexpiredSearchEnvelopeIsCacheHit() async throws {
    let request = sampleSearchRequest()
    let url = cacheFileURL(kind: "search", key: searchKey(for: request))
    let cached = sampleSearchResponse(description: "Cached hit")
    try writeEnvelope(value: cached, expiresAt: fixedNow.addingTimeInterval(3_600), to: url)

    let upstream = FakeUpstream(searchResponse: sampleSearchResponse(description: "Upstream"))
    let provider = makeProvider(upstream: upstream)

    let response = try await provider.search(request)

    XCTAssertEqual(response.foods.first?.description, "Cached hit")
    let calls = await upstream.searchCalls
    XCTAssertEqual(calls, 0)
  }

  func testWriteFailureStillReturnsUpstreamSearchResult() async throws {
    // Place a regular file where the cache directory should live so createDirectory fails.
    let blockedParent = FileManager.default.temporaryDirectory
      .appending(path: "JustLogItFoodCacheBlocked-\(UUID().uuidString)")
    try Data("not-a-directory".utf8).write(to: blockedParent)
    defer { try? FileManager.default.removeItem(at: blockedParent) }

    let blockedDirectory = blockedParent.appending(path: "child", directoryHint: .isDirectory)
    let upstream = FakeUpstream(searchResponse: sampleSearchResponse())
    let provider = DiskCachedFoodDataProvider(
      upstream: upstream,
      directory: blockedDirectory,
      now: { [fixedNow] in fixedNow! }
    )

    let response = try await provider.search(sampleSearchRequest())

    XCTAssertEqual(response, sampleSearchResponse())
    let calls = await upstream.searchCalls
    XCTAssertEqual(calls, 1)
  }

  func testEmptySearchUsesShortTTLAndNonEmptyUsesLongTTL() async throws {
    let emptyUpstream = FakeUpstream(
      searchResponse: FoodSearchResponse(foods: [], totalHits: 0, currentPage: 1, totalPages: 1)
    )
    let emptyProvider = makeProvider(upstream: emptyUpstream)
    let emptyRequest = sampleSearchRequest(query: "noresults", normalizedKey: "noresults")
    _ = try await emptyProvider.search(emptyRequest)

    let emptyURL = cacheFileURL(kind: "search", key: searchKey(for: emptyRequest))
    let emptyEnvelope = try readEnvelope(FoodSearchResponse.self, from: emptyURL)
    XCTAssertEqual(
      emptyEnvelope.expiresAt.timeIntervalSince(fixedNow),
      15 * 60,
      accuracy: 0.001
    )

    let filledUpstream = FakeUpstream(searchResponse: sampleSearchResponse())
    let filledProvider = makeProvider(upstream: filledUpstream)
    let filledRequest = sampleSearchRequest(query: "eggs", normalizedKey: "eggs")
    _ = try await filledProvider.search(filledRequest)

    let filledURL = cacheFileURL(kind: "search", key: searchKey(for: filledRequest))
    let filledEnvelope = try readEnvelope(FoodSearchResponse.self, from: filledURL)
    XCTAssertEqual(
      filledEnvelope.expiresAt.timeIntervalSince(fixedNow),
      7 * 24 * 60 * 60,
      accuracy: 0.001
    )
  }

  func testUnexpiredDetailsEnvelopeIsCacheHit() async throws {
    let fdcID = 42
    let url = cacheFileURL(kind: "details", key: String(fdcID))
    let cached = sampleDetails(fdcID: fdcID, description: "Cached details")
    try writeEnvelope(value: cached, expiresAt: fixedNow.addingTimeInterval(86_400), to: url)

    let upstream = FakeUpstream(details: sampleDetails(fdcID: fdcID, description: "Upstream"))
    let provider = makeProvider(upstream: upstream)

    let response = try await provider.foodDetails(fdcID: fdcID)

    XCTAssertEqual(response.description, "Cached details")
    let calls = await upstream.detailsCalls
    XCTAssertEqual(calls, 0)
  }

  func testExpiredDetailsFallsThroughToUpstream() async throws {
    let fdcID = 99
    let url = cacheFileURL(kind: "details", key: String(fdcID))
    try writeEnvelope(
      value: sampleDetails(fdcID: fdcID, description: "Stale"),
      expiresAt: fixedNow.addingTimeInterval(-1),
      to: url
    )

    let upstream = FakeUpstream(details: sampleDetails(fdcID: fdcID, description: "Fresh details"))
    let provider = makeProvider(upstream: upstream)

    let response = try await provider.foodDetails(fdcID: fdcID)

    XCTAssertEqual(response.description, "Fresh details")
    let calls = await upstream.detailsCalls
    XCTAssertEqual(calls, 1)
  }

  // MARK: - Helpers

  private func makeProvider(upstream: FakeUpstream) -> DiskCachedFoodDataProvider {
    DiskCachedFoodDataProvider(
      upstream: upstream,
      directory: directory,
      now: { [fixedNow] in fixedNow! }
    )
  }

  private func sampleSearchRequest(
    query: String = "eggs",
    normalizedKey: String = "eggs",
    page: Int = 1,
    pageSize: Int = 20,
    dataTypes: [String] = []
  ) -> FoodSearchRequest {
    FoodSearchRequest(
      query: query,
      normalizedKey: normalizedKey,
      dataTypes: dataTypes,
      page: page,
      pageSize: pageSize
    )
  }

  private func sampleSearchResponse(description: String = "Eggs") -> FoodSearchResponse {
    FoodSearchResponse(
      foods: [
        FoodSearchResult(
          fdcID: 1,
          description: description,
          dataType: "Survey (FNDDS)"
        )
      ],
      totalHits: 1,
      currentPage: 1,
      totalPages: 1
    )
  }

  private func sampleDetails(fdcID: Int, description: String) -> FoodDetails {
    FoodDetails(
      fdcID: fdcID,
      description: description,
      dataType: "Survey (FNDDS)",
      servingSize: 100,
      servingSizeUnit: "g",
      nutrientsPer100Grams: [NutrientAmount(key: .energy, amount: 155)],
      nutrientsPerServing: [NutrientAmount(key: .energy, amount: 155)]
    )
  }

  private func searchKey(for request: FoodSearchRequest) -> String {
    "\(request.normalizedKey)-\(request.page)-\(request.pageSize)-\(request.dataTypes.joined(separator: ","))"
  }

  private func cacheFileURL(kind: String, key: String) -> URL {
    let safe = Data(key.utf8).base64EncodedString()
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "=", with: "")
    return directory.appending(path: "\(kind)-\(safe).json")
  }

  private func writeEnvelope<Value: Codable>(value: Value, expiresAt: Date, to url: URL) throws {
    let envelope = TestEnvelope(value: value, expiresAt: expiresAt)
    try JSONEncoder().encode(envelope).write(to: url, options: .atomic)
  }

  private func readEnvelope<Value: Codable>(_ type: Value.Type, from url: URL) throws
    -> TestEnvelope<Value>
  {
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(TestEnvelope<Value>.self, from: data)
  }
}

private struct TestEnvelope<Value: Codable>: Codable {
  let value: Value
  let expiresAt: Date
}

private actor FakeUpstream: FoodDataProviding {
  private(set) var searchCalls = 0
  private(set) var detailsCalls = 0
  var searchResponse: FoodSearchResponse
  var details: FoodDetails

  init(
    searchResponse: FoodSearchResponse = FoodSearchResponse(
      foods: [], totalHits: 0, currentPage: 1, totalPages: 1
    ),
    details: FoodDetails = FoodDetails(
      fdcID: 0, description: "stub", dataType: "Survey (FNDDS)"
    )
  ) {
    self.searchResponse = searchResponse
    self.details = details
  }

  func search(_ request: FoodSearchRequest) async throws -> FoodSearchResponse {
    searchCalls += 1
    return searchResponse
  }

  func foodDetails(fdcID: Int) async throws -> FoodDetails {
    detailsCalls += 1
    return details
  }
}
