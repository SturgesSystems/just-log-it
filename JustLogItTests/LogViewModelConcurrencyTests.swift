import CoreGraphics
import Foundation
import ImageIO
import JustLogItCore
import UniformTypeIdentifiers
import XCTest

@testable import JustLogIt

@MainActor
final class LogViewModelConcurrencyTests: XCTestCase {
  func testPrewarmDelegatesToParserCapability() async {
    let parser = PrewarmingFoodParser()
    let model = LogViewModel(parser: parser, provider: StubFoodProvider())

    await model.prewarmParser()

    let prewarmCount = await parser.prewarmCount()
    XCTAssertEqual(prewarmCount, 1)
  }

  func testContextualParserReceivesAssistantContextSeparatelyFromUserEvidence() async {
    let parser = ContextualParserProbe()
    let model = LogViewModel(parser: parser, provider: StubFoodProvider())
    let generation = model.beginOperation()

    await model.runInterpretation(
      parseInput: "Assistant asked a bounded question. User replied apple.",
      evidenceText: "apple",
      turnCount: 1,
      generation: generation
    )

    let captured = await parser.capturedInput()
    let legacyCount = await parser.legacyParseCount()
    XCTAssertEqual(
      captured?.semanticContext, "Assistant asked a bounded question. User replied apple.")
    XCTAssertEqual(captured?.groundingText, "apple")
    XCTAssertEqual(legacyCount, 0)
  }

  func testCancelRemainsIdleWhenObsoleteParserLaterFails() async {
    let parser = ControlledFoodParser()
    let model = LogViewModel(parser: parser, provider: StubFoodProvider())
    model.input = "one apple"

    model.submit()
    await parser.waitUntilStarted()
    XCTAssertEqual(model.stage, .parsing)

    model.cancel()
    await parser.fail(ProbeError.expected)
    await settleAsyncWork()

    XCTAssertEqual(model.stage, .idle)
    XCTAssertNil(model.message)
  }

  func testOlderSelectionFailureCannotOverwriteNewerSelection() async {
    let provider = ControlledFoodProvider()
    let model = LogViewModel(parser: StubFoodParser(), provider: provider)
    model.input = "one egg"
    model.submit()
    await waitUntil { model.stage == .choosing }

    let older = Self.result(id: 1, description: "Older result")
    let newer = Self.result(id: 2, description: "Newer result")
    model.select(older)
    await provider.waitUntilDetailsRequested(for: older.fdcID)

    model.select(newer)
    await provider.waitUntilDetailsRequested(for: newer.fdcID)
    await provider.succeedDetails(for: newer.fdcID, description: newer.description)
    await waitUntil { model.stage == .reviewing }

    await provider.failDetails(for: older.fdcID, error: ProbeError.expected)
    await settleAsyncWork()

    XCTAssertEqual(model.stage, .reviewing)
    XCTAssertEqual(model.selectedResult?.fdcID, newer.fdcID)
    XCTAssertEqual(model.details?.fdcID, newer.fdcID)
    XCTAssertNil(model.message)
  }

  func testParserFailureHasInterpretationContext() async {
    let model = LogViewModel(parser: FailingFoodParser(), provider: StubFoodProvider())
    model.input = "two large scrambled eggs"

    model.submit()
    await waitUntil { model.stage == .failed }

    XCTAssertEqual(model.failureKind, .interpretation)
    XCTAssertEqual(
      model.message,
      "On-device interpretation wasn’t available. Edit the search terms or enter nutrition manually."
    )
    // The typed text carries into manual search so recovery isn't a blank field.
    XCTAssertEqual(model.manualSearchTerms, "two large scrambled eggs")
  }

  func testSearchFailureHasSearchContext() async {
    let model = LogViewModel(parser: StubFoodParser(), provider: SearchFailingFoodProvider())
    model.input = "one egg"

    model.submit()
    await waitUntil { model.stage == .failed }

    XCTAssertEqual(model.failureKind, .search)
    XCTAssertEqual(
      model.message,
      "Couldn’t reach USDA. Try again when you’re online, or enter nutrition manually."
    )
  }

  func testOfflineSearchFailureMentionsCacheAndManualEntry() async {
    let model = LogViewModel(
      parser: StubFoodParser(),
      provider: OfflineFailingFoodProvider())
    model.input = "one egg"

    model.submit()
    await waitUntil { model.stage == .failed }

    XCTAssertEqual(model.failureKind, .search)
    XCTAssertEqual(
      model.message,
      "You’re offline. Previously downloaded foods may still match from cache — or enter nutrition manually."
    )
  }

  func testEmptySearchResultsHaveNoResultsContext() async {
    let model = LogViewModel(parser: StubFoodParser(), provider: StubFoodProvider())
    model.input = "an impossible food"

    model.submit()
    await waitUntil { model.stage == .failed }

    XCTAssertEqual(model.failureKind, .noResults)
    XCTAssertEqual(
      model.message, "No USDA foods matched. Edit the search or enter nutrition manually."
    )
  }

  func testDetailsFailureHasDetailsContext() async {
    let provider = DetailsFailingFoodProvider()
    let model = LogViewModel(parser: StubFoodParser(), provider: provider)
    model.input = "one egg"

    model.submit()
    await waitUntil { model.stage == .choosing }
    let result = try? XCTUnwrap(model.results.first)
    XCTAssertNotNil(result)
    guard let result else { return }

    model.select(result)
    await waitUntil { model.stage == .failed }

    XCTAssertEqual(model.failureKind, .details)
    XCTAssertEqual(
      model.message,
      "Couldn’t load that food. Try again when you’re online, or enter nutrition manually."
    )
  }

  func testSearchWorkflowRanksRequestedCookieAboveCompositeDessert() async {
    let model = LogViewModel(parser: OreoFoodParser(), provider: OreoSearchProvider())
    model.input = "An Oreo cookie"

    model.submit()
    // Ranking is applied before any auto-select; assert on the ranked results
    // rather than the picker stage (a high-confidence hit may auto-advance).
    await waitUntil { model.results.count == 2 }

    XCTAssertEqual(model.results.map(\.fdcID), [101, 102])
  }

  func testPhotoFlowUsesOneBoundedOrientationCorrectImageAndSendsOnlyTextToUSDA() async throws {
    let sourceData = try Self.makeJPEG(
      width: 2_400, height: 1_200, orientation: .right, usesNoise: true)
    XCTAssertGreaterThan(sourceData.count, FoodImageNormalizer.maximumByteCount)
    let proposer = RecordingImageProposer(
      proposal: ParsedFoodRequest(
        productName: "apple", searchTerms: "apple", quantity: 1, unit: "serving"))
    let provider = PhotoFoodProvider()
    let model = LogViewModel(
      parser: StubFoodParser(), imageProposer: proposer, provider: provider)

    await model.proposeFromImage(data: sourceData, caption: "A red apple")
    await waitUntil(timeout: .seconds(5)) { model.stage == .choosing }

    let receivedData = await proposer.lastImageData()
    let proposedData = try XCTUnwrap(receivedData)
    let transcriptData = try XCTUnwrap(model.transcript.compactMap(\.imageData).first)
    XCTAssertEqual(proposedData, transcriptData)
    XCTAssertNotEqual(proposedData, sourceData)
    XCTAssertLessThanOrEqual(proposedData.count, FoodImageNormalizer.maximumByteCount)

    let imageSource = try XCTUnwrap(
      CGImageSourceCreateWithData(proposedData as CFData, nil))
    let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(imageSource, 0, nil))
    XCTAssertLessThanOrEqual(
      max(image.width, image.height), FoodImageNormalizer.maximumPixelDimension)
    XCTAssertGreaterThan(
      image.height,
      image.width,
      "EXIF-right landscape pixels should be flattened into a portrait representation")

    let requests = await provider.searchRequests()
    XCTAssertEqual(requests.count, 1)
    XCTAssertEqual(requests.first?.query, "apple")
    XCTAssertLessThan(requests.first?.query.utf8.count ?? .max, 100)

    let result = try XCTUnwrap(model.results.first)
    model.select(result)
    await waitUntil(timeout: .seconds(5)) { model.stage == .reviewing }
    let record = try model.makeRecord()
    XCTAssertEqual(record.originalText, "A red apple")
    XCTAssertNotEqual(record.nutrientsData, transcriptData)
    XCTAssertNotEqual(record.componentPayload, transcriptData)
  }

  func testLowConfidencePhotoProposalClarifiesWithoutSearchingUSDA() async throws {
    let proposer = RecordingImageProposer(
      proposal: ParsedFoodRequest(
        productName: "apple or pear",
        searchTerms: "apple pear",
        isApproximate: true,
        ambiguityNotes: "The fruit shape is unclear.",
        clarificationPrompt: "Is this an apple or a pear?",
        clarificationSuggestions: ["Apple", "Pear"]))
    let provider = PhotoFoodProvider()
    let model = LogViewModel(
      parser: StubFoodParser(), imageProposer: proposer, provider: provider)

    await model.proposeFromImage(data: try Self.makeSmallJPEG(), caption: nil)
    await waitUntil(timeout: .seconds(5)) { model.stage == .awaitingClarification }

    XCTAssertEqual(model.activeQuestion?.prompt, "Is this an apple or a pear?")
    // Identity clarifications intentionally suppress ungrounded model-authored chips;
    // the person must type what the photo actually shows.
    XCTAssertEqual(model.activeQuestion?.suggestedAnswers, [])
    let requestCount = await provider.searchRequestCount()
    XCTAssertEqual(requestCount, 0)
  }

  func testMultipleFoodPhotoProposalClarifiesWithoutSearchingUSDA() async throws {
    let proposer = RecordingImageProposer(
      proposal: ParsedFoodRequest(
        productName: "mixed plate",
        searchTerms: "mixed plate",
        isApproximate: true,
        containsMultipleFoods: true,
        ambiguityNotes: "Several distinct foods are visible."))
    let provider = PhotoFoodProvider()
    let model = LogViewModel(
      parser: StubFoodParser(), imageProposer: proposer, provider: provider)

    await model.proposeFromImage(data: try Self.makeSmallJPEG(), caption: nil)
    await waitUntil(timeout: .seconds(5)) { model.stage == .awaitingClarification }

    XCTAssertEqual(model.activeQuestion?.code, .multipleFoods)
    let requestCount = await provider.searchRequestCount()
    XCTAssertEqual(requestCount, 0)
  }

  func testInvalidPhotoFailsBeforeProposerAndIsNotRetainedInTranscript() async {
    let proposer = RecordingImageProposer(
      proposal: ParsedFoodRequest(productName: "unused", searchTerms: "unused"))
    let provider = PhotoFoodProvider()
    let model = LogViewModel(
      parser: StubFoodParser(), imageProposer: proposer, provider: provider)
    let invalidData = Data(repeating: 0xA5, count: 2_000_000)

    await model.proposeFromImage(data: invalidData, caption: nil)
    await waitUntil(timeout: .seconds(5)) { model.stage == .failed }

    XCTAssertEqual(model.failureKind, .interpretation)
    XCTAssertTrue(model.message?.contains("could not be read") == true)
    XCTAssertTrue(model.transcript.compactMap(\.imageData).isEmpty)
    let proposerCalls = await proposer.callCount()
    let providerCalls = await provider.searchRequestCount()
    XCTAssertEqual(proposerCalls, 0)
    XCTAssertEqual(providerCalls, 0)
  }

  func testSupersededPhotoProposalCannotOverwriteNewerPhotoResults() async throws {
    let proposer = ControlledImageProposer()
    let provider = PhotoFoodProvider()
    let model = LogViewModel(
      parser: StubFoodParser(), imageProposer: proposer, provider: provider)
    let imageData = try Self.makeSmallJPEG()

    await model.proposeFromImage(data: imageData, caption: "first")
    await proposer.waitUntilFirstStarted()
    await model.proposeFromImage(data: imageData, caption: "second")
    await waitUntil(timeout: .seconds(5)) {
      model.results.first?.description == "Banana result"
    }

    await proposer.completeFirst()
    await settleAsyncWork()

    XCTAssertEqual(model.parsed?.productName, "banana")
    XCTAssertEqual(model.results.first?.description, "Banana result")
    let requests = await provider.searchRequests()
    XCTAssertEqual(requests.map(\.query), ["banana"])
  }

  func testOlderPhotoTransferCannotReachModelAfterNewerSelection() async {
    let loader = ControlledPhotoTransferLoader()
    let coordinator = LatestPhotoSelectionCoordinator()
    var loadedData: [Data] = []
    var finishCount = 0

    coordinator.select(
      load: { try await loader.load(selection: 1) },
      onLoaded: { loadedData.append($0) },
      onFailure: { _ in XCTFail("The superseded transfer must not report a failure") },
      onFinished: { finishCount += 1 }
    )
    await loader.waitUntilStarted(selection: 1)

    coordinator.select(
      load: { try await loader.load(selection: 2) },
      onLoaded: { loadedData.append($0) },
      onFailure: { _ in XCTFail("The latest transfer should succeed") },
      onFinished: { finishCount += 1 }
    )
    await loader.waitUntilStarted(selection: 2)

    let newerData = Data([2])
    await loader.succeed(selection: 2, data: newerData)
    await waitUntil { loadedData == [newerData] && finishCount == 1 }

    await loader.succeed(selection: 1, data: Data([1]))
    await settleAsyncWork()

    XCTAssertEqual(loadedData, [newerData])
    XCTAssertEqual(finishCount, 1)
  }

  func testCancellingPhotoTransferPreventsLateCallbacks() async {
    let loader = ControlledPhotoTransferLoader()
    let coordinator = LatestPhotoSelectionCoordinator()
    var callbackCount = 0

    coordinator.select(
      load: { try await loader.load(selection: 1) },
      onLoaded: { _ in callbackCount += 1 },
      onFailure: { _ in callbackCount += 1 },
      onFinished: { callbackCount += 1 }
    )
    await loader.waitUntilStarted(selection: 1)

    coordinator.cancel()
    await loader.succeed(selection: 1, data: Data([1]))
    await settleAsyncWork()

    XCTAssertEqual(callbackCount, 0)
  }

  private static func result(id: Int, description: String) -> FoodSearchResult {
    FoodSearchResult(
      fdcID: id,
      description: description,
      dataType: "Survey (FNDDS)",
      servingSize: 100,
      servingSizeUnit: "g",
      householdServing: "1 serving"
    )
  }

  private func waitUntil(
    timeout: Duration = .seconds(1),
    condition: @escaping @MainActor () -> Bool
  ) async {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while !condition(), clock.now < deadline {
      await Task.yield()
    }
    XCTAssertTrue(condition(), "Timed out waiting for expected state")
  }

  private func settleAsyncWork() async {
    for _ in 0..<10 { await Task.yield() }
  }

  private static func makeSmallJPEG() throws -> Data {
    try makeJPEG(width: 80, height: 40, orientation: .up, usesNoise: false)
  }

  private static func makeJPEG(
    width: Int,
    height: Int,
    orientation: CGImagePropertyOrientation,
    usesNoise: Bool
  ) throws -> Data {
    let bytesPerRow = width * 4
    var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
    var state: UInt64 = 0x4D59_5DF4_D0F3_3173
    for index in stride(from: 0, to: pixels.count, by: 4) {
      if usesNoise {
        state = state &* 6_364_136_223_846_793_005 &+ 1
        pixels[index] = UInt8(truncatingIfNeeded: state >> 24)
        pixels[index + 1] = UInt8(truncatingIfNeeded: state >> 32)
        pixels[index + 2] = UInt8(truncatingIfNeeded: state >> 40)
      } else {
        pixels[index] = 210
        pixels[index + 1] = 48
        pixels[index + 2] = 42
      }
      pixels[index + 3] = 255
    }
    let pixelData = Data(pixels)
    let provider = try XCTUnwrap(CGDataProvider(data: pixelData as CFData))
    let bitmapInfo = CGBitmapInfo.byteOrder32Big.union(
      CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue))
    let image = try XCTUnwrap(
      CGImage(
        width: width,
        height: height,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: bytesPerRow,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: bitmapInfo,
        provider: provider,
        decode: nil,
        shouldInterpolate: true,
        intent: .defaultIntent))
    let output = NSMutableData()
    let destination = try XCTUnwrap(
      CGImageDestinationCreateWithData(
        output, UTType.jpeg.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(
      destination,
      image,
      [
        kCGImageDestinationLossyCompressionQuality: 0.98,
        kCGImagePropertyOrientation: orientation.rawValue,
      ] as CFDictionary)
    XCTAssertTrue(CGImageDestinationFinalize(destination))
    return output as Data
  }
}

private actor PrewarmingFoodParser: FoodDescriptionParsing, FoodDescriptionParserPrewarming {
  private var count = 0

  func prewarm() {
    count += 1
  }

  func prewarmCount() -> Int {
    count
  }

  func parse(_ input: String) async throws -> ParsedFoodRequest {
    ParsedFoodRequest(productName: input, searchTerms: input)
  }
}

private actor ContextualParserProbe: ContextualFoodDescriptionParsing {
  private var input: SemanticFoodProposalInput?
  private var legacyCount = 0

  func parse(_ input: String) async throws -> ParsedFoodRequest {
    legacyCount += 1
    return ParsedFoodRequest(productName: "wrong", searchTerms: "wrong")
  }

  func parse(
    semanticContext: String,
    groundingText: String
  ) async throws -> ParsedFoodRequest {
    input = .init(semanticContext: semanticContext, groundingText: groundingText)
    return ParsedFoodRequest(productName: groundingText, searchTerms: groundingText)
  }

  func capturedInput() -> SemanticFoodProposalInput? { input }
  func legacyParseCount() -> Int { legacyCount }
}

private enum ProbeError: Error {
  case expected
}

private struct FailingFoodParser: FoodDescriptionParsing {
  func parse(_ input: String) async throws -> ParsedFoodRequest {
    throw ProbeError.expected
  }
}

private actor ControlledFoodParser: FoodDescriptionParsing {
  private var continuation: CheckedContinuation<ParsedFoodRequest, any Error>?
  private var startedContinuation: CheckedContinuation<Void, Never>?
  private var started = false

  func parse(_ input: String) async throws -> ParsedFoodRequest {
    started = true
    startedContinuation?.resume()
    startedContinuation = nil
    return try await withCheckedThrowingContinuation { continuation = $0 }
  }

  func waitUntilStarted() async {
    guard !started else { return }
    await withCheckedContinuation { startedContinuation = $0 }
  }

  func fail(_ error: any Error) {
    continuation?.resume(throwing: error)
    continuation = nil
  }
}

private struct StubFoodParser: FoodDescriptionParsing {
  func parse(_ input: String) async throws -> ParsedFoodRequest {
    ParsedFoodRequest(
      productName: input,
      searchTerms: input,
      quantity: 1,
      unit: "serving"
    )
  }
}

private actor ControlledPhotoTransferLoader {
  private var continuations: [Int: CheckedContinuation<Data?, any Error>] = [:]
  private var startedSelections = Set<Int>()
  private var startWaiters: [Int: CheckedContinuation<Void, Never>] = [:]

  func load(selection: Int) async throws -> Data? {
    startedSelections.insert(selection)
    startWaiters.removeValue(forKey: selection)?.resume()
    return try await withCheckedThrowingContinuation { continuations[selection] = $0 }
  }

  func waitUntilStarted(selection: Int) async {
    guard !startedSelections.contains(selection) else { return }
    await withCheckedContinuation { startWaiters[selection] = $0 }
  }

  func succeed(selection: Int, data: Data) {
    continuations.removeValue(forKey: selection)?.resume(returning: data)
  }
}

private struct OreoFoodParser: FoodDescriptionParsing {
  func parse(_ input: String) async throws -> ParsedFoodRequest {
    ParsedFoodRequest(
      brand: "Oreo",
      productName: "cookie",
      searchTerms: "Oreo cookie",
      quantity: 1,
      unit: "cookie"
    )
  }
}

private struct OreoSearchProvider: FoodDataProviding {
  func search(_ request: FoodSearchRequest) async throws -> FoodSearchResponse {
    FoodSearchResponse(
      foods: [
        FoodSearchResult(
          fdcID: 102,
          description: "McDONALD'S, McFLURRY WITH OREO COOKIES",
          brandOwner: "McDonald's Corporation",
          dataType: "Branded"
        ),
        FoodSearchResult(
          fdcID: 101,
          description: "OREO CHOCOLATE SANDWICH COOKIES",
          brandOwner: "MONDELEZ GLOBAL LLC",
          dataType: "Branded"
        ),
      ],
      totalHits: 2,
      currentPage: 1,
      totalPages: 1
    )
  }

  func foodDetails(fdcID: Int) async throws -> FoodDetails {
    throw ProbeError.expected
  }
}

private struct StubFoodProvider: FoodDataProviding {
  func search(_ request: FoodSearchRequest) async throws -> FoodSearchResponse {
    FoodSearchResponse(foods: [], totalHits: 0, currentPage: 1, totalPages: 1)
  }

  func foodDetails(fdcID: Int) async throws -> FoodDetails {
    throw ProbeError.expected
  }
}

private struct SearchFailingFoodProvider: FoodDataProviding {
  func search(_ request: FoodSearchRequest) async throws -> FoodSearchResponse {
    throw ProbeError.expected
  }

  func foodDetails(fdcID: Int) async throws -> FoodDetails {
    throw ProbeError.expected
  }
}

private struct OfflineFailingFoodProvider: FoodDataProviding {
  func search(_ request: FoodSearchRequest) async throws -> FoodSearchResponse {
    throw URLError(.notConnectedToInternet)
  }

  func foodDetails(fdcID: Int) async throws -> FoodDetails {
    throw URLError(.notConnectedToInternet)
  }
}

private struct DetailsFailingFoodProvider: FoodDataProviding {
  func search(_ request: FoodSearchRequest) async throws -> FoodSearchResponse {
    FoodSearchResponse(
      foods: [
        FoodSearchResult(
          fdcID: 42,
          description: "Eggs",
          dataType: "Survey (FNDDS)",
          servingSize: 100,
          servingSizeUnit: "g",
          householdServing: "1 serving"
        )
      ],
      totalHits: 1,
      currentPage: 1,
      totalPages: 1
    )
  }

  func foodDetails(fdcID: Int) async throws -> FoodDetails {
    throw ProbeError.expected
  }
}

private actor RecordingImageProposer: FoodImageProposing {
  private let proposal: ParsedFoodRequest
  private var receivedImageData: [Data] = []

  init(proposal: ParsedFoodRequest) {
    self.proposal = proposal
  }

  func propose(imageData: Data, caption: String?) async throws -> ParsedFoodRequest {
    receivedImageData.append(imageData)
    return proposal
  }

  func lastImageData() -> Data? {
    receivedImageData.last
  }

  func callCount() -> Int {
    receivedImageData.count
  }
}

private actor ControlledImageProposer: FoodImageProposing {
  private var firstContinuation: CheckedContinuation<ParsedFoodRequest, any Error>?
  private var firstStarted = false
  private var firstStartedWaiter: CheckedContinuation<Void, Never>?

  func propose(imageData: Data, caption: String?) async throws -> ParsedFoodRequest {
    if caption == "first" {
      firstStarted = true
      firstStartedWaiter?.resume()
      firstStartedWaiter = nil
      return try await withCheckedThrowingContinuation { firstContinuation = $0 }
    }
    return ParsedFoodRequest(
      productName: "banana", searchTerms: "banana", quantity: 1, unit: "serving")
  }

  func waitUntilFirstStarted() async {
    guard !firstStarted else { return }
    await withCheckedContinuation { firstStartedWaiter = $0 }
  }

  func completeFirst() {
    firstContinuation?.resume(
      returning: ParsedFoodRequest(
        productName: "apple", searchTerms: "apple", quantity: 1, unit: "serving"))
    firstContinuation = nil
  }
}

private actor PhotoFoodProvider: FoodDataProviding {
  private var requests: [FoodSearchRequest] = []

  func search(_ request: FoodSearchRequest) async throws -> FoodSearchResponse {
    requests.append(request)
    let name = request.query == "banana" ? "Banana result" : "Apple result"
    return FoodSearchResponse(
      foods: [
        FoodSearchResult(
          fdcID: request.query == "banana" ? 202 : 101,
          description: name,
          dataType: "Foundation",
          servingSize: 100,
          servingSizeUnit: "g",
          householdServing: "1 serving")
      ],
      totalHits: 1,
      currentPage: 1,
      totalPages: 1)
  }

  func foodDetails(fdcID: Int) async throws -> FoodDetails {
    FoodDetails(
      fdcID: fdcID,
      description: fdcID == 202 ? "Banana result" : "Apple result",
      dataType: "Foundation",
      servingSize: 100,
      servingSizeUnit: "g",
      householdServing: "1 serving",
      nutrientsPer100Grams: [NutrientAmount(key: .energy, amount: 52)])
  }

  func searchRequests() -> [FoodSearchRequest] {
    requests
  }

  func searchRequestCount() -> Int {
    requests.count
  }
}

private actor ControlledFoodProvider: FoodDataProviding {
  private var continuations: [Int: CheckedContinuation<FoodDetails, any Error>] = [:]
  private var requestWaiters: [Int: CheckedContinuation<Void, Never>] = [:]
  private var requestedIDs = Set<Int>()

  func search(_ request: FoodSearchRequest) async throws -> FoodSearchResponse {
    FoodSearchResponse(
      foods: [
        FoodSearchResult(fdcID: 1, description: "Older result", dataType: "Survey (FNDDS)"),
        FoodSearchResult(fdcID: 2, description: "Newer result", dataType: "Survey (FNDDS)"),
      ],
      totalHits: 2,
      currentPage: 1,
      totalPages: 1
    )
  }

  func foodDetails(fdcID: Int) async throws -> FoodDetails {
    requestedIDs.insert(fdcID)
    requestWaiters.removeValue(forKey: fdcID)?.resume()
    return try await withCheckedThrowingContinuation { continuations[fdcID] = $0 }
  }

  func waitUntilDetailsRequested(for fdcID: Int) async {
    guard !requestedIDs.contains(fdcID) else { return }
    await withCheckedContinuation { requestWaiters[fdcID] = $0 }
  }

  func succeedDetails(for fdcID: Int, description: String) {
    resume(
      for: fdcID,
      with: .success(
        FoodDetails(
          fdcID: fdcID,
          description: description,
          dataType: "Survey (FNDDS)",
          servingSize: 100,
          servingSizeUnit: "g",
          householdServing: "1 serving",
          nutrientsPer100Grams: [NutrientAmount(key: .energy, amount: 100)]
        )))
  }

  func failDetails(for fdcID: Int, error: any Error) {
    resume(for: fdcID, with: .failure(error))
  }

  private func resume(for fdcID: Int, with result: Result<FoodDetails, any Error>) {
    guard let continuation = continuations.removeValue(forKey: fdcID) else { return }
    continuation.resume(with: result)
  }
}
