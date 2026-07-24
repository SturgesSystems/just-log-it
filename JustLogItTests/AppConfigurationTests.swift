import Foundation
import JustLogItCore
import SwiftData
import XCTest

@testable import JustLogIt

final class AppConfigurationTests: XCTestCase {
  func testReleasePolicyIgnoresUITestingAndVolatileStoreArguments() {
    let arguments = [
      "JustLogIt",
      "-ui-testing",
      "-ui-testing-volatile-store",
      "-hybrid-parser",
      "-ui-testing-hybrid-named-dish",
    ]

    XCTAssertFalse(
      AppLaunchArgumentPolicy.isUITesting(
        arguments: arguments,
        honorsDebugArguments: false
      )
    )
    XCTAssertFalse(
      AppLaunchArgumentPolicy.forcesVolatileStore(
        arguments: arguments,
        honorsDebugArguments: false
      )
    )
  }

  func testDebugVolatileStoreRequiresUITestingMarker() {
    XCTAssertFalse(
      AppLaunchArgumentPolicy.forcesVolatileStore(
        arguments: ["JustLogIt", "-ui-testing-volatile-store"],
        honorsDebugArguments: true
      )
    )
    XCTAssertTrue(
      AppLaunchArgumentPolicy.forcesVolatileStore(
        arguments: ["JustLogIt", "-ui-testing", "-ui-testing-volatile-store"],
        honorsDebugArguments: true
      )
    )
  }

  func testPendingFoodLogDescriptionRequiresUITestingAndFlag() {
    XCTAssertNil(
      AppLaunchArgumentPolicy.pendingFoodLogDescription(
        arguments: ["JustLogIt", "-ui-pending-log", "eggs"],
        environment: [:],
        honorsDebugArguments: true
      )
    )
    XCTAssertNil(
      AppLaunchArgumentPolicy.pendingFoodLogDescription(
        arguments: ["JustLogIt", "-ui-testing"],
        environment: ["UI_PENDING_LOG_TEXT": "eggs"],
        honorsDebugArguments: true
      )
    )
    XCTAssertNil(
      AppLaunchArgumentPolicy.pendingFoodLogDescription(
        arguments: ["JustLogIt", "-ui-testing", "-ui-pending-log", "eggs"],
        environment: [:],
        honorsDebugArguments: false
      )
    )
  }

  func testPendingFoodLogDescriptionPrefersEnvironmentThenArgument() {
    XCTAssertEqual(
      AppLaunchArgumentPolicy.pendingFoodLogDescription(
        arguments: ["JustLogIt", "-ui-testing", "-ui-pending-log"],
        environment: ["UI_PENDING_LOG_TEXT": "  two scrambled eggs  "],
        honorsDebugArguments: true
      ),
      "two scrambled eggs"
    )
    XCTAssertEqual(
      AppLaunchArgumentPolicy.pendingFoodLogDescription(
        arguments: ["JustLogIt", "-ui-testing", "-ui-pending-log", "oatmeal"],
        environment: [:],
        honorsDebugArguments: true
      ),
      "oatmeal"
    )
    // Env wins over the positional argument so spaces need not be encoded.
    XCTAssertEqual(
      AppLaunchArgumentPolicy.pendingFoodLogDescription(
        arguments: ["JustLogIt", "-ui-testing", "-ui-pending-log", "ignored"],
        environment: ["UI_PENDING_LOG_TEXT": "from env"],
        honorsDebugArguments: true
      ),
      "from env"
    )
    // A following flag is not treated as the food description.
    XCTAssertNil(
      AppLaunchArgumentPolicy.pendingFoodLogDescription(
        arguments: ["JustLogIt", "-ui-testing", "-ui-pending-log", "-ui-testing-egg-portions"],
        environment: [:],
        honorsDebugArguments: true
      )
    )
  }

  func testProductionParserArchitectureIsDeterministicFastPath() throws {
    XCTAssertEqual(FoodParserFactory.productionDefault, .deterministicFastPath)
    XCTAssertEqual(
      try FoodParserFactory.selectedArchitecture(
        arguments: ["JustLogIt", "-hybrid-parser"],
        honorsDebugOverrides: false
      ),
      .deterministicFastPath
    )
  }

  func testDebugParserArchitectureOverridesAreExplicitAndExclusive() throws {
    XCTAssertEqual(
      try FoodParserFactory.selectedArchitecture(
        arguments: ["JustLogIt", "-baseline-parser"], honorsDebugOverrides: true),
      .baseline22Field
    )
    XCTAssertEqual(
      try FoodParserFactory.selectedArchitecture(
        arguments: ["JustLogIt", "-deterministic-parser"], honorsDebugOverrides: true),
      .deterministicFastPath
    )
    XCTAssertEqual(
      try FoodParserFactory.selectedArchitecture(
        arguments: ["JustLogIt", "-hybrid-parser"], honorsDebugOverrides: true),
      .fullHybrid
    )
    XCTAssertThrowsError(
      try FoodParserFactory.selectedArchitecture(
        arguments: ["JustLogIt", "-baseline-parser", "-hybrid-parser"],
        honorsDebugOverrides: true
      )
    ) { error in
      XCTAssertEqual(error as? FoodParserSelectionError, .conflictingDebugOverrides)
    }
  }

  func testDeterministicFirstAdapterForwardsSpeculativePrewarmToFallback() async {
    let probe = PrewarmProbe()
    let parser = FoundationModelsDeterministicFirstFoodParser(
      fallback: EmptyFoodParser(),
      prewarmAction: { await probe.increment() }
    )

    await parser.prewarm()

    let count = await probe.count
    XCTAssertEqual(count, 1)
  }

  @MainActor
  func testAppNavigationKeepsOnlyOnePendingEntryDestination() {
    // Isolated instance — never mutate AppNavigation.shared here.
    let navigation = AppNavigation()
    let foodID = UUID()
    let entryID = UUID()

    navigation.openFood(foodID)
    XCTAssertEqual(navigation.tab, .entries)
    XCTAssertEqual(navigation.selectedFoodID, foodID)
    XCTAssertNil(navigation.selectedEntryID)

    navigation.openEntry(entryID)
    XCTAssertEqual(navigation.tab, .entries)
    XCTAssertEqual(navigation.selectedEntryID, entryID)
    XCTAssertNil(navigation.selectedFoodID)
  }

  @MainActor
  func testLogAgainMovesToLogAndCarriesFoodDescription() {
    let navigation = AppNavigation()
    navigation.tab = .entries

    navigation.logAgain("Eggs, scrambled")

    XCTAssertEqual(navigation.tab, .log)
    XCTAssertEqual(
      navigation.pendingFoodLog,
      PendingFoodLog(description: "Eggs, scrambled", consumedAt: nil, source: .inApp)
    )
  }

  @MainActor
  func testBeginPendingFoodLogPreservesConsumedAtFromSiri() {
    let navigation = AppNavigation()
    let eatenAt = Date(timeIntervalSince1970: 1_700_000_123)

    navigation.beginPendingFoodLog(
      PendingFoodLog(
        description: "two scrambled eggs",
        consumedAt: eatenAt,
        source: .siri
      )
    )

    XCTAssertEqual(navigation.tab, .log)
    XCTAssertEqual(navigation.pendingFoodLog?.description, "two scrambled eggs")
    XCTAssertEqual(navigation.pendingFoodLog?.consumedAt, eatenAt)
    XCTAssertEqual(navigation.pendingFoodLog?.source, .siri)

    let taken = navigation.takePendingFoodLog()
    XCTAssertEqual(taken?.description, "two scrambled eggs")
    XCTAssertNil(navigation.pendingFoodLog)
  }

  @MainActor
  func testBeginPendingFoodLogTrimsAndIgnoresEmpty() {
    let navigation = AppNavigation()
    navigation.tab = .entries

    navigation.beginPendingFoodLog(
      PendingFoodLog(description: "  two eggs  ", consumedAt: nil, source: .siri)
    )
    XCTAssertEqual(navigation.tab, .log)
    XCTAssertEqual(navigation.pendingFoodLog?.description, "two eggs")
    XCTAssertEqual(navigation.pendingFoodLog?.source, .siri)

    navigation.pendingFoodLog = nil
    navigation.tab = .entries
    navigation.beginPendingFoodLog(
      PendingFoodLog(description: "   ", consumedAt: nil, source: .siri)
    )
    XCTAssertNil(navigation.pendingFoodLog)
    XCTAssertEqual(navigation.tab, .entries)
  }

  @MainActor
  func testTakePendingFoodLogClearsHandoff() {
    let navigation = AppNavigation()
    navigation.beginPendingFoodLog(
      PendingFoodLog(description: "toast", consumedAt: nil, source: .shortcut)
    )
    let taken = navigation.takePendingFoodLog()
    XCTAssertEqual(taken?.description, "toast")
    XCTAssertEqual(taken?.source, .shortcut)
    XCTAssertNil(navigation.pendingFoodLog)
    XCTAssertNil(navigation.takePendingFoodLog())
  }

  @MainActor
  func testBeginPendingSearchTrimsAndCanBeTaken() {
    let navigation = AppNavigation()
    navigation.tab = .log

    navigation.beginPendingSearch("  greek yogurt  ")
    XCTAssertEqual(navigation.tab, .entries)
    XCTAssertEqual(navigation.pendingSearchQuery, "greek yogurt")

    XCTAssertEqual(navigation.takePendingSearchQuery(), "greek yogurt")
    XCTAssertNil(navigation.pendingSearchQuery)
  }

  func testPersistentStoreOpenFailurePreservesOriginalPathAndUsesVolatileStore() throws {
    let root = FileManager.default.temporaryDirectory.appending(
      path: "justlogit-store-failure-\(UUID().uuidString)",
      directoryHint: .isDirectory
    )
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    // A regular file cannot also be the parent directory of a SwiftData store.
    // This deterministically forces the persistent open to fail without touching
    // the app's real Application Support directory.
    let obstruction = root.appending(path: "not-a-directory")
    let original = Data("preserve me".utf8)
    try original.write(to: obstruction)

    let result = try ModelContainerFactory.make(
      isUITesting: false,
      persistentStoreURL: obstruction.appending(path: "default.store")
    )

    XCTAssertTrue(result.usesVolatileStore)
    XCTAssertEqual(try Data(contentsOf: obstruction), original)
  }

  func testForcedVolatileStoreIsMarkedNonDurable() throws {
    let result = try ModelContainerFactory.make(
      isUITesting: true,
      forceVolatileStore: true
    )

    XCTAssertTrue(result.usesVolatileStore)
  }

  func testLiveBootstrapBuilderPreservesTestingStoreClassifications() async throws {
    let builder = ModelContainerBootstrapBuilder()
    let testing = try await builder.build(
      for: .init(isUITesting: true, forcesVolatileStore: false)
    )
    let forced = try await builder.build(
      for: .init(isUITesting: true, forcesVolatileStore: true)
    )

    XCTAssertFalse(testing.usesVolatileStore)
    guard case .testingMemory = testing.category else {
      return XCTFail("Expected the UI-testing memory category")
    }
    XCTAssertTrue(forced.usesVolatileStore)
    guard case .forcedVolatile = forced.category else {
      return XCTFail("Expected the forced-volatile category")
    }
  }

  @MainActor
  func testBootstrapBuildDoesNotBlockMainActor() async throws {
    let operation = ControlledBootstrapOperation(blocksFirstInvocation: true)
    let bootstrap = ModelContainerBootstrap(
      builder: ModelContainerBootstrapBuilder(operation: operation.callAsFunction)
    )

    bootstrap.startIfNeeded(
      for: .init(isUITesting: false, forcesVolatileStore: false)
    )

    // Reaching this condition while the injected synchronous builder is blocked
    // proves that the builder is not occupying the main actor.
    await waitUntil { operation.invocationCount == 1 }
    XCTAssertNil(bootstrap.container)
    XCTAssertFalse(operation.firstInvocationWasOnMainThread)

    var heartbeat = false
    Task { @MainActor in heartbeat = true }
    await waitUntil { heartbeat }

    operation.releaseFirstInvocation()
    await waitUntil { bootstrap.container != nil }
  }

  @MainActor
  func testLateCancelledBootstrapCannotOverwriteNewerRetry() async throws {
    let operation = ControlledBootstrapOperation(blocksFirstInvocation: true)
    let bootstrap = ModelContainerBootstrap(
      builder: ModelContainerBootstrapBuilder(operation: operation.callAsFunction)
    )
    let mode = AppLaunchArgumentPolicy.Mode(
      isUITesting: false,
      forcesVolatileStore: false
    )

    bootstrap.startIfNeeded(for: mode)
    await waitUntil { operation.invocationCount == 1 }

    bootstrap.retry(for: mode)
    await waitUntil { operation.invocationCount == 2 && bootstrap.container != nil }
    let acceptedContainer = try XCTUnwrap(bootstrap.container)
    XCTAssertTrue(bootstrap.usesVolatileStore)

    operation.releaseFirstInvocation()
    await waitUntil { operation.firstInvocationCompleted }
    for _ in 0..<20 { await Task.yield() }

    XCTAssertTrue(bootstrap.container === acceptedContainer)
    XCTAssertTrue(bootstrap.usesVolatileStore)
  }

  @MainActor
  func testUITestBootstrapClearsRememberedFoodsForEachAttempt() async {
    var resetCount = 0
    let bootstrap = ModelContainerBootstrap(
      clearRememberedFoods: {
        dispatchPrecondition(condition: .onQueue(.main))
        resetCount += 1
      }
    )
    let mode = AppLaunchArgumentPolicy.Mode(
      isUITesting: true,
      forcesVolatileStore: false
    )

    bootstrap.startIfNeeded(for: mode)
    await waitUntil { bootstrap.container != nil }
    bootstrap.retry(for: mode)
    await waitUntil { resetCount == 2 && bootstrap.container != nil }

    XCTAssertEqual(resetCount, 2)
  }

  func testCrossTabDestinationReplacesNonemptyEntriesPath() {
    let oldFoodID = UUID()
    let oldEntryID = UUID()
    let destinationID = UUID()
    var path: [EntryRoute] = [.food(oldFoodID), .entry(oldEntryID)]

    path = EntriesNavigationPath.replacingCurrent(with: .entry(destinationID))

    XCTAssertEqual(path, [.entry(destinationID)])
  }

  func testProxyTakesPrecedenceInProviderDescription() {
    let configuration = AppConfiguration(
      proxyBaseURL: URL(string: "https://foods.example.com"),
      debugUSDAAPIKey: "development-key"
    )

    XCTAssertEqual(configuration.providerDescription, "Privacy proxy")
  }

  func testMissingConfigurationIsReported() {
    let configuration = AppConfiguration(proxyBaseURL: nil, debugUSDAAPIKey: nil)

    XCTAssertEqual(configuration.providerDescription, "Not configured")
  }

  func testAcceptsRootHTTPSProxyWithMatchingPin() {
    let url = AppConfiguration.validatedProxyURL(
      "https://foods.example.org/",
      allowedHost: "foods.example.org",
      requirePinnedHost: true
    )

    XCTAssertEqual(url?.absoluteString, "https://foods.example.org/")
  }

  func testRejectsUnsafeOrAmbiguousProxyURLs() {
    for value in [
      "http://foods.example.org",
      "//foods.example.org",
      "https://user@foods.example.org",
      "https://foods.example.org:8443",
      "https://foods.example.org/api",
      "https://bad..example.org",
      "https://-bad.example.org",
      "https://foods.example.org?mode=test",
      "https://foods.example.org#fragment",
    ] {
      XCTAssertNil(
        AppConfiguration.validatedProxyURL(
          value,
          allowedHost: "foods.example.org",
          requirePinnedHost: true
        ),
        "Expected rejection for \(value)"
      )
    }
  }

  func testReleaseStyleValidationRequiresExactHostPin() {
    XCTAssertNil(
      AppConfiguration.validatedProxyURL(
        "https://foods.example.org",
        allowedHost: nil,
        requirePinnedHost: true
      )
    )
    XCTAssertNil(
      AppConfiguration.validatedProxyURL(
        "https://foods.example.org",
        allowedHost: "other.example.org",
        requirePinnedHost: true
      )
    )
  }

  #if DEBUG
    func testDebugKeyIsReportedInDebugBuild() {
      let configuration = AppConfiguration(proxyBaseURL: nil, debugUSDAAPIKey: "development-key")

      XCTAssertEqual(configuration.providerDescription, "Direct USDA (Debug)")
    }
  #endif

  @MainActor
  private func waitUntil(
    timeout: Duration = .seconds(2),
    condition: @escaping @MainActor () -> Bool
  ) async {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while !condition(), clock.now < deadline {
      await Task.yield()
    }
    XCTAssertTrue(condition(), "Timed out waiting for bootstrap state")
  }
}

private actor PrewarmProbe {
  private(set) var count = 0

  func increment() {
    count += 1
  }
}

private struct EmptyFoodParser: FoodDescriptionParsing {
  func parse(_ input: String) async throws -> ParsedFoodRequest {
    .init(productName: "fallback", searchTerms: "fallback")
  }
}

private final class ControlledBootstrapOperation: @unchecked Sendable {
  private let lock = NSLock()
  private let firstRelease = DispatchSemaphore(value: 0)
  private let blocksFirstInvocation: Bool
  private var invocations = 0
  private var firstWasOnMainThread = false
  private var firstCompleted = false

  init(blocksFirstInvocation: Bool) {
    self.blocksFirstInvocation = blocksFirstInvocation
  }

  var invocationCount: Int { lock.withLock { invocations } }
  var firstInvocationWasOnMainThread: Bool { lock.withLock { firstWasOnMainThread } }
  var firstInvocationCompleted: Bool { lock.withLock { firstCompleted } }

  func callAsFunction(
    _: AppLaunchArgumentPolicy.Mode
  ) throws -> ModelContainerBootstrapResult {
    let invocation = lock.withLock {
      invocations += 1
      if invocations == 1 {
        firstWasOnMainThread = Thread.isMainThread
      }
      return invocations
    }

    if invocation == 1, blocksFirstInvocation {
      firstRelease.wait()
    }

    let container = try ModelContainerFactory.makeEmergencyVolatile()
    if invocation == 1 {
      lock.withLock { firstCompleted = true }
    }
    return ModelContainerBootstrapResult(
      container: container,
      usesVolatileStore: true,
      category: .forcedVolatile
    )
  }

  func releaseFirstInvocation() {
    firstRelease.signal()
  }
}
