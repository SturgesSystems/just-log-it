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
    let observations = USDAObservationRecorder()
    let removals = LockedCounter()
    let provider = makeProvider(
      upstream: upstream,
      io: cacheIO(recordingRemovalsIn: removals),
      observations: observations)

    let response = try await provider.search(request)

    XCTAssertEqual(response, sampleSearchResponse())
    let calls = await upstream.searchCalls
    XCTAssertEqual(calls, 1)
    XCTAssertTrue(observations.events.contains(.cache(resource: .search, outcome: .corrupt)))
    XCTAssertEqual(removals.value, 1, "A corrupt entry should be removed before cache refill")
  }

  func testExpiredSearchEnvelopeIsTreatedAsMissButKeptForOfflineStale() async throws {
    let request = sampleSearchRequest()
    let url = cacheFileURL(kind: "search", key: searchKey(for: request))
    let stale = sampleSearchResponse(description: "Stale cache")
    try writeEnvelope(value: stale, expiresAt: fixedNow.addingTimeInterval(-60), to: url)

    let upstream = FakeUpstream(searchResponse: sampleSearchResponse(description: "Fresh"))
    let observations = USDAObservationRecorder()
    let removals = LockedCounter()
    let provider = makeProvider(
      upstream: upstream,
      io: cacheIO(recordingRemovalsIn: removals),
      observations: observations)

    let response = try await provider.search(request)

    XCTAssertEqual(response.foods.first?.description, "Fresh")
    let calls = await upstream.searchCalls
    XCTAssertEqual(calls, 1)
    XCTAssertTrue(observations.events.contains(.cache(resource: .search, outcome: .expired)))
    XCTAssertEqual(
      removals.value, 0, "Expired entries stay on disk so offline can serve them if refill fails")
  }

  func testExpiredSearchIsServedWhenUpstreamIsOffline() async throws {
    let request = sampleSearchRequest()
    let url = cacheFileURL(kind: "search", key: searchKey(for: request))
    try writeEnvelope(
      value: sampleSearchResponse(description: "Cached offline"),
      expiresAt: fixedNow.addingTimeInterval(-60),
      to: url)

    let upstream = FakeUpstream(searchError: URLError(.notConnectedToInternet))
    let observations = USDAObservationRecorder()
    let provider = makeProvider(upstream: upstream, observations: observations)

    let response = try await provider.search(request)

    XCTAssertEqual(response.foods.first?.description, "Cached offline")
    let calls = await upstream.searchCalls
    XCTAssertEqual(calls, 1)
    XCTAssertTrue(observations.events.contains(.cache(resource: .search, outcome: .expired)))
    XCTAssertTrue(observations.events.contains(.cache(resource: .search, outcome: .stale)))
  }

  func testExpiredDetailsAreServedWhenUpstreamIsOffline() async throws {
    let fdcID = 77
    let url = cacheFileURL(kind: "details", key: String(fdcID))
    try writeEnvelope(
      value: sampleDetails(fdcID: fdcID, description: "Stale details"),
      expiresAt: fixedNow.addingTimeInterval(-1),
      to: url)

    let upstream = FakeUpstream(detailsError: URLError(.notConnectedToInternet))
    let observations = USDAObservationRecorder()
    let provider = makeProvider(upstream: upstream, observations: observations)

    let response = try await provider.foodDetails(fdcID: fdcID)

    XCTAssertEqual(response.description, "Stale details")
    let calls = await upstream.detailsCalls
    XCTAssertEqual(calls, 1)
    XCTAssertTrue(observations.events.contains(.cache(resource: .details, outcome: .stale)))
  }

  func testUnexpiredSearchEnvelopeIsCacheHit() async throws {
    let request = sampleSearchRequest()
    let url = cacheFileURL(kind: "search", key: searchKey(for: request))
    let cached = sampleSearchResponse(description: "Cached hit")
    try writeEnvelope(value: cached, expiresAt: fixedNow.addingTimeInterval(3_600), to: url)

    let upstream = FakeUpstream(searchResponse: sampleSearchResponse(description: "Upstream"))
    let observations = USDAObservationRecorder()
    let provider = makeProvider(upstream: upstream, observations: observations)

    let response = try await provider.search(request)

    XCTAssertEqual(response.foods.first?.description, "Cached hit")
    let calls = await upstream.searchCalls
    XCTAssertEqual(calls, 0)
    XCTAssertEqual(observations.events, [.cache(resource: .search, outcome: .hit)])
  }

  func testWriteFailureStillReturnsUpstreamSearchResult() async throws {
    // Place a regular file where the cache directory should live so createDirectory fails.
    let blockedParent = FileManager.default.temporaryDirectory
      .appending(path: "JustLogItFoodCacheBlocked-\(UUID().uuidString)")
    try Data("not-a-directory".utf8).write(to: blockedParent)
    defer { try? FileManager.default.removeItem(at: blockedParent) }

    let blockedDirectory = blockedParent.appending(path: "child", directoryHint: .isDirectory)
    let upstream = FakeUpstream(searchResponse: sampleSearchResponse())
    let observations = USDAObservationRecorder()
    let provider = DiskCachedFoodDataProvider(
      upstream: upstream,
      directory: blockedDirectory,
      now: { [fixedNow] in fixedNow! },
      observer: observations.observer
    )

    let response = try await provider.search(sampleSearchRequest())

    XCTAssertEqual(response, sampleSearchResponse())
    let calls = await upstream.searchCalls
    XCTAssertEqual(calls, 1)
    XCTAssertTrue(observations.events.contains(.cache(resource: .search, outcome: .missing)))
    XCTAssertTrue(observations.events.contains(.cache(resource: .search, outcome: .writeIO)))
  }

  func testMissingEntryRecordsMissingWithoutLeakingItsKey() async throws {
    let observations = USDAObservationRecorder()
    let provider = makeProvider(
      upstream: FakeUpstream(searchResponse: sampleSearchResponse()),
      observations: observations)

    _ = try await provider.search(sampleSearchRequest(query: "private input", normalizedKey: "x"))

    XCTAssertEqual(
      observations.events.first,
      .cache(resource: .search, outcome: .missing))
  }

  func testExistingUnreadableEntryRecordsReadIOAndFallsThrough() async throws {
    let request = sampleSearchRequest()
    let url = cacheFileURL(kind: "search", key: searchKey(for: request))
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    let observations = USDAObservationRecorder()
    let upstream = FakeUpstream(searchResponse: sampleSearchResponse())
    let provider = makeProvider(upstream: upstream, observations: observations)

    let response = try await provider.search(request)

    XCTAssertEqual(response, sampleSearchResponse())
    XCTAssertTrue(observations.events.contains(.cache(resource: .search, outcome: .readIO)))
    let calls = await upstream.searchCalls
    XCTAssertEqual(calls, 1)
  }

  func testPruneFailureIsObservedButDoesNotReplaceUpstreamResult() async throws {
    enum ExpectedFailure: Error { case prune }
    let live = FoodDataCacheIO.live
    let failingPruneIO = FoodDataCacheIO(
      fileExists: live.fileExists,
      read: live.read,
      createDirectory: live.createDirectory,
      write: live.write,
      contents: { _ in throw ExpectedFailure.prune },
      modificationDate: live.modificationDate,
      remove: live.remove)
    let observations = USDAObservationRecorder()
    let upstream = FakeUpstream(searchResponse: sampleSearchResponse())
    let provider = DiskCachedFoodDataProvider(
      upstream: upstream,
      directory: directory,
      now: { [fixedNow] in fixedNow! },
      io: failingPruneIO,
      observer: observations.observer)

    let response = try await provider.search(sampleSearchRequest())

    XCTAssertEqual(response, sampleSearchResponse())
    XCTAssertTrue(observations.events.contains(.cache(resource: .search, outcome: .pruneIO)))
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

  func testLegacyUnversionedDetailsEnvelopeIsIgnored() async throws {
    let fdcID = 43
    let legacyURL = legacyCacheFileURL(kind: "details", key: String(fdcID))
    try writeEnvelope(
      value: sampleDetails(fdcID: fdcID, description: "Collapsed legacy details"),
      expiresAt: fixedNow.addingTimeInterval(86_400),
      to: legacyURL
    )

    let upstream = FakeUpstream(
      details: sampleDetails(fdcID: fdcID, description: "Current portion-aware details"))
    let provider = makeProvider(upstream: upstream)

    let response = try await provider.foodDetails(fdcID: fdcID)

    XCTAssertEqual(response.description, "Current portion-aware details")
    let calls = await upstream.detailsCalls
    XCTAssertEqual(calls, 1)
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

  func testApproximateCacheSizeDescribesEmptyAndNonEmptyDirectories() throws {
    XCTAssertEqual(
      DiskCachedFoodDataProvider.approximateCacheSizeDescription(at: directory),
      "Empty"
    )

    let fileURL = directory.appending(path: "sample.json")
    try Data(repeating: 0x61, count: 2_048).write(to: fileURL)

    let description = DiskCachedFoodDataProvider.approximateCacheSizeDescription(at: directory)
    XCTAssertTrue(description.hasPrefix("About "), description)
    XCTAssertGreaterThan(
      DiskCachedFoodDataProvider.approximateCacheByteCount(at: directory), 0)
  }

  func testCacheIsBoundedByMaxEntries() async throws {
    let upstream = FakeUpstream(details: sampleDetails(fdcID: 1, description: "food"))
    let provider = DiskCachedFoodDataProvider(
      upstream: upstream,
      directory: directory,
      now: { [fixedNow] in fixedNow! },
      maxEntries: 3
    )

    // Eight distinct fdcIDs → eight distinct cache files, pruned to the cap.
    for id in 1...8 {
      _ = try await provider.foodDetails(fdcID: id)
    }

    let files = try FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: nil)
    XCTAssertGreaterThan(files.count, 0)
    XCTAssertLessThanOrEqual(files.count, 3, "Disk cache must stay bounded by maxEntries")
  }

  // MARK: - Helpers

  private func makeProvider(
    upstream: FakeUpstream,
    io: FoodDataCacheIO = .live,
    observations: USDAObservationRecorder = USDAObservationRecorder()
  ) -> DiskCachedFoodDataProvider {
    DiskCachedFoodDataProvider(
      upstream: upstream,
      directory: directory,
      now: { [fixedNow] in fixedNow! },
      io: io,
      observer: observations.observer
    )
  }

  private func cacheIO(recordingRemovalsIn counter: LockedCounter) -> FoodDataCacheIO {
    let live = FoodDataCacheIO.live
    return FoodDataCacheIO(
      fileExists: live.fileExists,
      read: live.read,
      createDirectory: live.createDirectory,
      write: live.write,
      contents: live.contents,
      modificationDate: live.modificationDate,
      remove: { url in
        counter.increment()
        try live.remove(url)
      })
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
    return directory.appending(
      path: "v\(DiskCachedFoodDataProvider.cacheSchemaVersion)-\(kind)-\(safe).json")
  }

  private func legacyCacheFileURL(kind: String, key: String) -> URL {
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

private final class USDAObservationRecorder: @unchecked Sendable {
  private let queue = DispatchQueue(label: "USDAObservationRecorder")
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

private final class LockedCounter: @unchecked Sendable {
  private let queue = DispatchQueue(label: "LockedCounter")
  private var storedValue = 0

  var value: Int { queue.sync { storedValue } }

  func increment() {
    queue.sync { storedValue += 1 }
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
  var searchError: (any Error)?
  var detailsError: (any Error)?

  init(
    searchResponse: FoodSearchResponse = FoodSearchResponse(
      foods: [], totalHits: 0, currentPage: 1, totalPages: 1
    ),
    details: FoodDetails = FoodDetails(
      fdcID: 0, description: "stub", dataType: "Survey (FNDDS)"
    ),
    searchError: (any Error)? = nil,
    detailsError: (any Error)? = nil
  ) {
    self.searchResponse = searchResponse
    self.details = details
    self.searchError = searchError
    self.detailsError = detailsError
  }

  func search(_ request: FoodSearchRequest) async throws -> FoodSearchResponse {
    searchCalls += 1
    if let searchError { throw searchError }
    return searchResponse
  }

  func foodDetails(fdcID: Int) async throws -> FoodDetails {
    detailsCalls += 1
    if let detailsError { throw detailsError }
    return details
  }
}
