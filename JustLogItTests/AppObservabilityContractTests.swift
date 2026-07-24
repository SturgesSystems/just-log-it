import JustLogItCore
import XCTest

@testable import JustLogIt

final class AppObservabilityContractTests: XCTestCase {
  func testOnlyClosedTelemetryValuesConformToPrivacySafeBoundary() {
    requirePrivacySafe(AppObservability.Operation.parserResponse)
    requirePrivacySafe(AppObservability.Operation.bootstrapContainerOpen)
    requirePrivacySafe(AppObservability.Operation.healthReconciliation)
    requirePrivacySafe(AppObservability.Outcome.cancelled)
    requirePrivacySafe(AppObservability.BootstrapStoreCategory.persistent)
    requirePrivacySafe(AppObservability.BootstrapMilestone.firstFrame)
    requirePrivacySafe(AppObservability.BootstrapMilestone.interactive)
    requirePrivacySafe(AppObservability.ParserAvailability.modelNotReady)
    requirePrivacySafe(AppObservability.ParserRoute.clarification)
    requirePrivacySafe(AppObservability.ParserArchitecture.deterministicFastPath)
    requirePrivacySafe(AppObservability.DeterministicSelection.countedItem)
    requirePrivacySafe(AppObservability.SemanticInvocation.skipped)
    requirePrivacySafe(AppObservability.SemanticOutcome.unavailable)
    requirePrivacySafe(AppObservability.SemanticSessionSource.prewarmed)
    requirePrivacySafe(AppObservability.CacheResource.search)
    requirePrivacySafe(AppObservability.CacheOutcome.missing)
    requirePrivacySafe(AppObservability.USDATransportOutcome.offline)
    requirePrivacySafe(
      AppObservability.USDAEvent.transport(resource: .search, outcome: .timedOut))
    requirePrivacySafe(AppObservability.USDAStatusCategory.rateLimited)
    requirePrivacySafe(AppObservability.CountCategory.rankedSearchResults)
    requirePrivacySafe(AppObservability.Count(3))
    requirePrivacySafe(AppObservability.InteractionMilestone.usdaRequestDispatch)
    requirePrivacySafe(AppObservability.BoundedDuration(.milliseconds(3)))

    XCTAssertFalse(String.self is any PrivacySafeObservationValue.Type)
    XCTAssertFalse(Substring.self is any PrivacySafeObservationValue.Type)
    XCTAssertFalse(URL.self is any PrivacySafeObservationValue.Type)
    XCTAssertFalse(UUID.self is any PrivacySafeObservationValue.Type)
    XCTAssertFalse(Data.self is any PrivacySafeObservationValue.Type)
    XCTAssertFalse(Int.self is any PrivacySafeObservationValue.Type)
  }

  func testTelemetryEnumsCannotBeConstructedFromArbitraryStrings() {
    XCTAssertFalse(AppObservability.Operation.self is any RawRepresentable.Type)
    XCTAssertFalse(AppObservability.ParserRoute.self is any RawRepresentable.Type)
    XCTAssertFalse(AppObservability.ParserArchitecture.self is any RawRepresentable.Type)
    XCTAssertFalse(AppObservability.DeterministicSelection.self is any RawRepresentable.Type)
    XCTAssertFalse(AppObservability.USDAStatusCategory.self is any RawRepresentable.Type)
    XCTAssertFalse(AppObservability.CacheOutcome.self is any RawRepresentable.Type)
    XCTAssertFalse(AppObservability.USDATransportOutcome.self is any RawRepresentable.Type)
    XCTAssertFalse(AppObservability.USDAEvent.self is any RawRepresentable.Type)
  }

  func testCountsAreNonnegativeAndContainNoAssociatedText() {
    XCTAssertEqual(AppObservability.Count(-50).value, 0)
    XCTAssertEqual(AppObservability.Count(12).value, 12)
  }

  func testDurationsAreClampedToInteractiveBounds() {
    XCTAssertEqual(AppObservability.BoundedDuration(.milliseconds(-1)).value, .zero)
    XCTAssertEqual(
      AppObservability.BoundedDuration(.seconds(900)).value,
      AppObservability.BoundedDuration.maximum
    )
    XCTAssertEqual(AppObservability.BoundedDuration(.milliseconds(42)).value, .milliseconds(42))
  }

  func testBootstrapLaunchTimelineRecordsEachMilestoneOnceFromSameOrigin() {
    let started = ContinuousClock.now
    var timeline = BootstrapLaunchTimeline(startedAt: started)

    let firstFrame = timeline.markFirstFrame(at: started.advanced(by: .milliseconds(12)))
    let interactive = timeline.markInteractive(at: started.advanced(by: .milliseconds(90)))

    XCTAssertEqual(firstFrame?.milestone, .firstFrame)
    XCTAssertEqual(firstFrame?.duration.value, .milliseconds(12))
    XCTAssertEqual(interactive?.milestone, .interactive)
    XCTAssertEqual(interactive?.duration.value, .milliseconds(90))
    XCTAssertNil(timeline.markFirstFrame(at: started.advanced(by: .seconds(1))))
    XCTAssertNil(timeline.markInteractive(at: started.advanced(by: .seconds(1))))
  }

  func testBootstrapLaunchTimelineClampsClockRegression() {
    let started = ContinuousClock.now
    var timeline = BootstrapLaunchTimeline(startedAt: started)

    let measurement = timeline.markFirstFrame(at: started.advanced(by: .milliseconds(-5)))

    XCTAssertEqual(measurement?.duration.value, .zero)
  }

  func testInteractionTimelineRecordsEachMilestoneOnceFromSameOrigin() {
    let started = ContinuousClock.now
    var timeline = FoodLogInteractionTimeline(startedAt: started)

    let dispatch = timeline.markUSDARequestDispatch(at: started.advanced(by: .milliseconds(25)))
    let actionable = timeline.markFirstActionableUI(at: started.advanced(by: .milliseconds(80)))

    XCTAssertEqual(dispatch?.milestone, .usdaRequestDispatch)
    XCTAssertEqual(dispatch?.duration.value, .milliseconds(25))
    XCTAssertEqual(actionable?.milestone, .firstActionableUI)
    XCTAssertEqual(actionable?.duration.value, .milliseconds(80))
    XCTAssertNil(timeline.markUSDARequestDispatch(at: started.advanced(by: .seconds(1))))
    XCTAssertNil(timeline.markFirstActionableUI(at: started.advanced(by: .seconds(1))))
  }

  func testInteractionTimelineClampsClockRegression() {
    let started = ContinuousClock.now
    var timeline = FoodLogInteractionTimeline(startedAt: started)

    let measurement = timeline.markFirstActionableUI(
      at: started.advanced(by: .milliseconds(-5))
    )

    XCTAssertEqual(measurement?.duration.value, .zero)
  }

  func testOperationOutcomeClassifiesCancellationSeparatelyFromFailure() {
    XCTAssertEqual(AppObservability.outcome(for: CancellationError()), .cancelled)
    XCTAssertEqual(AppObservability.outcome(for: URLError(.cancelled)), .cancelled)
    XCTAssertEqual(AppObservability.outcome(for: LifecycleTestError.expected), .failure)
  }

  func testUSDATransportErrorsMapToClosedPrivacySafeOutcomes() {
    XCTAssertEqual(
      AppObservability.usdaTransportOutcome(for: URLError(.notConnectedToInternet)), .offline)
    XCTAssertEqual(
      AppObservability.usdaTransportOutcome(for: URLError(.networkConnectionLost)), .offline)
    XCTAssertEqual(AppObservability.usdaTransportOutcome(for: URLError(.timedOut)), .timedOut)
    XCTAssertEqual(AppObservability.usdaTransportOutcome(for: URLError(.cancelled)), .cancelled)
    XCTAssertEqual(AppObservability.usdaTransportOutcome(for: CancellationError()), .cancelled)
    XCTAssertEqual(
      AppObservability.usdaTransportOutcome(for: LifecycleTestError.expected), .other)
  }

  func testSemanticOutcomeMappingIsExhaustiveAndDoesNotObserveSkippedModel() {
    XCTAssertNil(
      HybridSemanticObservation.outcome(
        modelInvoked: false,
        reasons: [.semanticUnavailable]
      )
    )
    XCTAssertEqual(
      HybridSemanticObservation.outcome(modelInvoked: true, reasons: []),
      .accepted
    )
    XCTAssertEqual(
      HybridSemanticObservation.outcome(
        modelInvoked: true,
        reasons: [.semanticUnavailable]
      ),
      .unavailable
    )
    XCTAssertEqual(
      HybridSemanticObservation.outcome(modelInvoked: true, reasons: [.semanticRefused]),
      .refused
    )
    XCTAssertEqual(
      HybridSemanticObservation.outcome(
        modelInvoked: true,
        reasons: [.invalidOnDeviceProposal]
      ),
      .invalid
    )
  }

  func testUnsafeDeterministicAmountBecomesEditableManualRecovery() {
    let result = hybridResult(
      route: .manualSearch,
      reason: .unsafeAmountBinding,
      request: .init(productName: "", searchTerms: "")
    )

    XCTAssertThrowsError(try result.appFacingRequest()) { error in
      XCTAssertEqual(
        (error as? LocalizedError)?.errorDescription,
        "That description needs a quick manual check. Edit the USDA search terms or enter nutrition manually."
      )
    }
  }

  func testDisabledDeterministicFamilyCannotBypassAppRecovery() {
    let result = hybridResult(
      route: .manualSearch,
      reason: .deterministicFamilyDisabled,
      request: .init(productName: "", searchTerms: "")
    )

    XCTAssertThrowsError(try result.appFacingRequest()) { error in
      XCTAssertTrue(error is HybridFoodParserError)
    }
  }

  func testGroundedApproximationReachesAppWithDeterministicAmountUnchanged() throws {
    let request = ParsedFoodRequest(
      productName: "eggs",
      searchTerms: "eggs",
      quantity: 2,
      unit: "eggs",
      isApproximate: true
    )
    let result = hybridResult(
      route: .onDeviceSemantic,
      reason: .groundedApproximation,
      request: request
    )

    XCTAssertEqual(try result.appFacingRequest(), request)
  }

  func testPreparedResourceIsConsumedExactlyOnceThenAcquisitionIsFresh() async throws {
    let probe = LifecycleProbe()
    let pool = OneShotPreparedResourcePool<Int> { probe.makeResource() }

    let firstPrewarm = try await pool.prewarm { _ in probe.recordPreparation() }
    let duplicatePrewarm = try await pool.prewarm { _ in probe.recordPreparation() }
    let prepared = await pool.acquire()
    let fresh = await pool.acquire()

    XCTAssertTrue(firstPrewarm)
    XCTAssertFalse(duplicatePrewarm)
    XCTAssertEqual(prepared.source, .prewarmed)
    XCTAssertEqual(fresh.source, .fresh)
    XCTAssertEqual(probe.preparationCount, 1)
    XCTAssertEqual(probe.resourceCount, 2)
  }

  func testConcurrentPrewarmPublishesOnlyOnePreparedResource() async throws {
    let probe = LifecycleProbe()
    let pool = OneShotPreparedResourcePool<Int> { probe.makeResource() }

    let preparedCount = try await withThrowingTaskGroup(of: Bool.self) { group in
      for _ in 0..<20 {
        group.addTask {
          try await pool.prewarm { _ in probe.recordPreparation() }
        }
      }
      var count = 0
      for try await didPrepare in group where didPrepare { count += 1 }
      return count
    }

    XCTAssertEqual(preparedCount, 1)
    XCTAssertEqual(probe.preparationCount, 1)
    XCTAssertEqual(probe.resourceCount, 1)
    let acquisition = await pool.acquire()
    XCTAssertEqual(acquisition.source, .prewarmed)
  }

  func testCancelledPrewarmDoesNotPublishPartiallyPreparedResource() async {
    let probe = LifecycleProbe()
    let pool = OneShotPreparedResourcePool<Int> { probe.makeResource() }

    let task = Task {
      try await pool.prewarm { _ in
        probe.recordPreparation()
        withUnsafeCurrentTask { $0?.cancel() }
      }
    }

    do {
      _ = try await task.value
      XCTFail("Expected cancellation")
    } catch is CancellationError {
      // Expected.
    } catch {
      XCTFail("Unexpected error: \(error)")
    }

    let acquisition = await pool.acquire()
    XCTAssertEqual(acquisition.source, .fresh)
    XCTAssertEqual(probe.preparationCount, 1)
    XCTAssertEqual(probe.resourceCount, 2)
  }

  func testAcquisitionBypassesBlockedPrewarmAndDiscardsItsLateResource() async throws {
    let probe = LifecycleProbe()
    let gate = BlockingPreparationGate()
    let pool = OneShotPreparedResourcePool<Int> { probe.makeResource() }
    let prewarm = Task {
      try await pool.prewarm { _ in
        probe.recordPreparation()
        gate.blockUntilReleased()
      }
    }

    await gate.waitUntilBlocked()
    let duplicatePrewarm = try await pool.prewarm { _ in probe.recordPreparation() }
    XCTAssertFalse(duplicatePrewarm)

    let acquisition = await pool.acquire()
    XCTAssertEqual(acquisition.source, .fresh)
    XCTAssertEqual(acquisition.resource, 2)

    gate.release()
    let didPublishPrewarm = try await prewarm.value
    XCTAssertFalse(didPublishPrewarm)

    let laterAcquisition = await pool.acquire()
    XCTAssertEqual(laterAcquisition.source, .fresh)
    XCTAssertEqual(laterAcquisition.resource, 3)
    XCTAssertEqual(probe.preparationCount, 1)
    XCTAssertEqual(probe.resourceCount, 3)
  }

  private func requirePrivacySafe<Value: PrivacySafeObservationValue>(_ value: Value) {
    _ = value
  }
}

private func hybridResult(
  route: FoodInterpretationRoute,
  reason: FoodInterpretationRouteReason,
  request: ParsedFoodRequest
) -> HybridFoodInterpretationResult {
  let decision = FoodInterpretationRoutingDecision(route: route, reasons: [reason])
  return HybridFoodInterpretationResult(
    evidence: .init(normalizedSource: "", identityCandidate: nil),
    initialDecision: decision,
    finalDecision: decision,
    request: request,
    modelInvoked: false
  )
}

private enum LifecycleTestError: Error {
  case expected
}

private final class LifecycleProbe: @unchecked Sendable {
  private let lock = NSLock()
  private var nextResource = 0
  private var preparations = 0

  var resourceCount: Int { lock.withLock { nextResource } }
  var preparationCount: Int { lock.withLock { preparations } }

  func makeResource() -> Int {
    lock.withLock {
      nextResource += 1
      return nextResource
    }
  }

  func recordPreparation() {
    lock.withLock { preparations += 1 }
  }
}

private final class BlockingPreparationGate: @unchecked Sendable {
  private let lock = NSLock()
  private let releaseSemaphore = DispatchSemaphore(value: 0)
  private var blocked = false
  private var blockedContinuation: CheckedContinuation<Void, Never>?

  func blockUntilReleased() {
    let continuation = lock.withLock {
      blocked = true
      defer { blockedContinuation = nil }
      return blockedContinuation
    }
    continuation?.resume()
    releaseSemaphore.wait()
  }

  func waitUntilBlocked() async {
    await withCheckedContinuation { continuation in
      let alreadyBlocked = lock.withLock {
        if blocked { return true }
        blockedContinuation = continuation
        return false
      }
      if alreadyBlocked {
        continuation.resume()
      }
    }
  }

  func release() {
    releaseSemaphore.signal()
  }
}
