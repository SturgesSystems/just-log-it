import HealthKit
import JustLogItCore
import SwiftData
import XCTest

@testable import JustLogIt

final class HealthKitNutritionWriterTests: XCTestCase {
  func testEveryModeledNutrientExceptAddedSugarHasUniqueHealthKitMapping() {
    let mapped = NutrientKey.allCases.compactMap(HealthKitNutrientMapping.init)

    XCTAssertEqual(mapped.count, NutrientKey.allCases.count - 1)
    XCTAssertNil(HealthKitNutrientMapping(.addedSugar))
    XCTAssertEqual(Set(mapped.map(\.quantityType.identifier)).count, mapped.count)
  }

  func testCanonicalUnitsMatchHealthKitDimensions() {
    XCTAssertEqual(HealthKitNutrientMapping(.energy)?.unit, .kilocalorie())
    XCTAssertEqual(HealthKitNutrientMapping(.protein)?.unit, .gram())
    XCTAssertEqual(HealthKitNutrientMapping(.sodium)?.unit, .gramUnit(with: .milli))
    XCTAssertEqual(HealthKitNutrientMapping(.vitaminD)?.unit, .gramUnit(with: .micro))
    XCTAssertEqual(HealthKitNutrientMapping(.water)?.unit, .literUnit(with: .milli))
  }

  func testDeletionTargetsAreExactUniqueIdentifiersForOneEntry() {
    let entryID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    let identifiers = HealthKitNutrientMapping.deletionTargets(entryID: entryID)
      .map(\.syncIdentifier)

    XCTAssertEqual(identifiers.count, HealthKitNutrientMapping.allMappings.count + 1)
    XCTAssertEqual(Set(identifiers).count, identifiers.count)
    XCTAssertTrue(identifiers.contains("\(entryID.uuidString).food"))
    XCTAssertTrue(identifiers.contains("\(entryID.uuidString).energy"))
    XCTAssertTrue(identifiers.allSatisfy { $0.hasPrefix(entryID.uuidString + ".") })
  }

  @MainActor
  func testCoordinatorKeepsLocalEntryAndMarksSuccessfulWrite() async throws {
    let container = try ModelContainer(
      for: FoodLogEntryRecord.self, HealthDeletionTombstone.self, RecognizedFoodRecord.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = container.mainContext
    let entry = try FoodLogEntryRecord(
      originalText: "One egg",
      displayName: "Egg",
      quantityDisplay: "1 egg",
      isApproximate: false,
      source: .usda,
      fdcID: 123,
      calculationBasis: .servings,
      nutrients: [NutrientAmount(key: .energy, amount: 72)]
    )
    context.insert(entry)
    try context.save()
    UserDefaults.standard.set(true, forKey: HealthSyncCoordinator.preferenceKey)
    defer { UserDefaults.standard.removeObject(forKey: HealthSyncCoordinator.preferenceKey) }

    let outcome = await HealthSyncCoordinator.syncIfEnabled(
      entry, modelContext: context, writer: SuccessfulHealthWriter())

    XCTAssertEqual(outcome, .synced)
    XCTAssertEqual(entry.healthSyncStatus, .synced)
    XCTAssertNotNil(entry.healthSyncedAt)
    XCTAssertEqual(try context.fetch(FetchDescriptor<FoodLogEntryRecord>()).count, 1)
  }

  @MainActor
  func testSettingsDoesNotPersistEnabledWhileAuthorizationIsPending() async throws {
    let defaults = makeDefaults()
    let writer = DelayedAuthorizationWriter()
    let model = HealthSyncSettingsModel(writer: writer, defaults: defaults)

    let request = Task { await model.setEnabled(true) }
    while !(await writer.didStartAuthorization()) { await Task.yield() }

    XCTAssertFalse(model.isEnabled)
    XCTAssertFalse(defaults.bool(forKey: HealthSyncCoordinator.preferenceKey))
    XCTAssertTrue(model.isRequestingAccess)

    await writer.finishAuthorization(.authorized)
    await request.value

    XCTAssertTrue(model.isEnabled)
    XCTAssertTrue(defaults.bool(forKey: HealthSyncCoordinator.preferenceKey))
    XCTAssertFalse(model.isRequestingAccess)
  }

  @MainActor
  func testSettingsDenialLeavesPreferenceDisabled() async {
    let defaults = makeDefaults()
    let writer = TrackingHealthWriter(summary: .denied)
    let model = HealthSyncSettingsModel(writer: writer, defaults: defaults)

    await model.setEnabled(true)

    XCTAssertFalse(model.isEnabled)
    XCTAssertFalse(defaults.bool(forKey: HealthSyncCoordinator.preferenceKey))
    XCTAssertEqual(
      model.message, "Write access wasn’t granted. You can review access in Settings.")
  }

  @MainActor
  func testRetryReturnsDisabledOutcomeWithoutRequestingOrSaving() async throws {
    let defaults = makeDefaults()
    let writer = TrackingHealthWriter(summary: .authorized)
    let store = try makeEntry()

    let outcome = await HealthSyncCoordinator.retry(
      store.entry, modelContext: store.context, writer: writer, defaults: defaults)
    let authorizationRequests = await writer.authorizationRequestCount()
    let saveRequests = await writer.saveRequestCount()

    XCTAssertEqual(outcome, .disabled)
    XCTAssertEqual(store.entry.healthSyncStatus, .notRequested)
    XCTAssertEqual(authorizationRequests, 0)
    XCTAssertEqual(saveRequests, 0)
    withExtendedLifetime(store.container) {}
  }

  @MainActor
  func testExplicitRetryAuthorizesThenSavesWhenPreferenceIsEnabled() async throws {
    let defaults = makeDefaults()
    defaults.set(true, forKey: HealthSyncCoordinator.preferenceKey)
    let writer = TrackingHealthWriter(summary: .authorized)
    let store = try makeEntry()

    let outcome = await HealthSyncCoordinator.retry(
      store.entry, modelContext: store.context, writer: writer, defaults: defaults)
    let authorizationRequests = await writer.authorizationRequestCount()
    let saveRequests = await writer.saveRequestCount()

    XCTAssertEqual(outcome, .synced)
    XCTAssertEqual(store.entry.healthSyncStatus, .synced)
    XCTAssertEqual(authorizationRequests, 1)
    XCTAssertEqual(saveRequests, 1)
    withExtendedLifetime(store.container) {}
  }

  @MainActor
  func testExplicitRetryDenialPersistsVisibleDeniedStateWithoutSaving() async throws {
    let defaults = makeDefaults()
    defaults.set(true, forKey: HealthSyncCoordinator.preferenceKey)
    let writer = TrackingHealthWriter(summary: .denied)
    let store = try makeEntry()

    let outcome = await HealthSyncCoordinator.retry(
      store.entry, modelContext: store.context, writer: writer, defaults: defaults)
    let authorizationRequests = await writer.authorizationRequestCount()
    let saveRequests = await writer.saveRequestCount()

    XCTAssertEqual(
      outcome,
      .denied("Apple Health access wasn’t granted. You can review access in Settings."))
    XCTAssertEqual(store.entry.healthSyncStatus, .denied)
    XCTAssertNotNil(store.entry.healthSyncError)
    XCTAssertEqual(authorizationRequests, 1)
    XCTAssertEqual(saveRequests, 0)
    withExtendedLifetime(store.container) {}
  }

  @MainActor
  func testForegroundReconciliationRetriesPendingWriteWhenEnabled() async throws {
    let defaults = makeDefaults()
    defaults.set(true, forKey: HealthSyncCoordinator.preferenceKey)
    let writer = TrackingHealthWriter(summary: .authorized)
    let store = try makeEntry(status: .pending)

    let summary = await HealthSyncCoordinator.reconcile(
      modelContext: store.context, writer: writer, defaults: defaults)
    let saveRequests = await writer.saveRequestCount()

    XCTAssertEqual(summary.writesCompleted, 1)
    XCTAssertEqual(store.entry.healthSyncStatus, .synced)
    XCTAssertEqual(store.entry.healthSyncRetryCount, 0)
    XCTAssertEqual(saveRequests, 1)
    withExtendedLifetime(store.container) {}
  }

  @MainActor
  func testForegroundReconciliationDoesNotRetryWritesWhenPreferenceIsOff() async throws {
    let defaults = makeDefaults()
    let writer = TrackingHealthWriter(summary: .authorized)
    let store = try makeEntry(status: .failed)

    let summary = await HealthSyncCoordinator.reconcile(
      modelContext: store.context, writer: writer, defaults: defaults)
    let saveRequests = await writer.saveRequestCount()

    XCTAssertEqual(summary.attemptedCount, 0)
    XCTAssertEqual(store.entry.healthSyncStatus, .failed)
    XCTAssertEqual(saveRequests, 0)
    withExtendedLifetime(store.container) {}
  }

  @MainActor
  func testAutomaticWriteRetriesAreBoundedAndPersistBackoff() async throws {
    let defaults = makeDefaults()
    defaults.set(true, forKey: HealthSyncCoordinator.preferenceKey)
    let writer = TrackingHealthWriter(summary: .authorized, saveShouldFail: true)
    let store = try makeEntry(status: .failed)
    let now = Date(timeIntervalSince1970: 1_000)

    let first = await HealthSyncCoordinator.reconcile(
      modelContext: store.context, writer: writer, defaults: defaults, now: now)

    XCTAssertEqual(first.writesFailed, 1)
    XCTAssertEqual(store.entry.healthSyncRetryCount, 1)
    XCTAssertEqual(store.entry.healthSyncNextRetryAt, now.addingTimeInterval(60))

    store.entry.healthSyncRetryCount = HealthSyncCoordinator.maximumAutomaticRetries
    store.entry.healthSyncNextRetryAt = nil
    try store.context.save()
    let bounded = await HealthSyncCoordinator.reconcile(
      modelContext: store.context, writer: writer, defaults: defaults, now: now)
    let saveRequests = await writer.saveRequestCount()

    XCTAssertEqual(bounded.attemptedCount, 0)
    XCTAssertEqual(saveRequests, 1)
    withExtendedLifetime(store.container) {}
  }

  @MainActor
  func testFailedHealthDeletionKeepsEntryAndDurableTombstone() async throws {
    let writer = TrackingHealthWriter(summary: .authorized, deleteShouldFail: true)
    let store = try makeEntry(status: .synced)
    let now = Date(timeIntervalSince1970: 2_000)

    let outcome = await HealthSyncCoordinator.deleteEntry(
      store.entry, modelContext: store.context, writer: writer, now: now)
    let tombstones = try store.context.fetch(FetchDescriptor<HealthDeletionTombstone>())
    let entries = try store.context.fetch(FetchDescriptor<FoodLogEntryRecord>())

    XCTAssertEqual(
      outcome,
      .pending(
        "The entry is still saved. Apple Health cleanup will retry when JustLogIt becomes active."
      ))
    XCTAssertEqual(entries.count, 1)
    XCTAssertEqual(entries.first?.healthSyncStatus, .deletionPending)
    XCTAssertEqual(tombstones.count, 1)
    XCTAssertEqual(tombstones.first?.entryID, store.entry.id)
    XCTAssertEqual(tombstones.first?.retryCount, 1)
    XCTAssertEqual(tombstones.first?.nextRetryAt, now.addingTimeInterval(60))
    withExtendedLifetime(store.container) {}
  }

  @MainActor
  func testDeletionTombstoneReconcilesWithoutWritePreferenceAndRemovesLocalEntry() async throws {
    let failingWriter = TrackingHealthWriter(summary: .authorized, deleteShouldFail: true)
    let store = try makeEntry(status: .synced)
    let firstAttempt = Date(timeIntervalSince1970: 3_000)
    _ = await HealthSyncCoordinator.deleteEntry(
      store.entry, modelContext: store.context, writer: failingWriter, now: firstAttempt)

    let successfulWriter = TrackingHealthWriter(summary: .authorized)
    let defaults = makeDefaults()
    let summary = await HealthSyncCoordinator.reconcile(
      modelContext: store.context,
      writer: successfulWriter,
      defaults: defaults,
      now: firstAttempt.addingTimeInterval(61)
    )
    let deleteRequests = await successfulWriter.deleteRequestCount()

    XCTAssertEqual(summary.deletionsCompleted, 1)
    XCTAssertTrue(try store.context.fetch(FetchDescriptor<FoodLogEntryRecord>()).isEmpty)
    XCTAssertTrue(try store.context.fetch(FetchDescriptor<HealthDeletionTombstone>()).isEmpty)
    XCTAssertEqual(deleteRequests, 1)
    withExtendedLifetime(store.container) {}
  }

  private func makeDefaults() -> UserDefaults {
    let suiteName = "HealthKitNutritionWriterTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
  }

  @MainActor
  private func makeEntry(status: HealthSyncStatus = .notRequested) throws -> HealthTestStore {
    let container = try ModelContainer(
      for: FoodLogEntryRecord.self, HealthDeletionTombstone.self, RecognizedFoodRecord.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = container.mainContext
    let entry = try FoodLogEntryRecord(
      originalText: "One egg",
      displayName: "Egg",
      quantityDisplay: "1 egg",
      isApproximate: false,
      source: .usda,
      fdcID: 123,
      calculationBasis: .servings,
      nutrients: [NutrientAmount(key: .energy, amount: 72)]
    )
    entry.healthSyncStatus = status
    context.insert(entry)
    try context.save()
    return HealthTestStore(container: container, context: context, entry: entry)
  }
}

private struct HealthTestStore {
  let container: ModelContainer
  let context: ModelContext
  let entry: FoodLogEntryRecord
}

extension HealthAuthorizationSummary {
  fileprivate static let authorized = HealthAuthorizationSummary(
    authorizedNutrientCount: 1, requestedNutrientCount: 1)
  fileprivate static let denied = HealthAuthorizationSummary(
    authorizedNutrientCount: 0, requestedNutrientCount: 1)
}

private actor SuccessfulHealthWriter: HealthNutritionWriting {
  nonisolated let isAvailable = true

  func requestAuthorization() async throws -> HealthAuthorizationSummary {
    HealthAuthorizationSummary(authorizedNutrientCount: 1, requestedNutrientCount: 1)
  }

  func save(
    entryID: UUID,
    version: Int,
    foodName: String,
    consumedAt: Date,
    source: EntrySource,
    fdcID: Int?,
    nutrients: [NutrientAmount]
  ) async throws {}
}

private actor DelayedAuthorizationWriter: HealthNutritionWriting {
  nonisolated let isAvailable = true
  private var continuation: CheckedContinuation<HealthAuthorizationSummary, Never>?
  private var started = false

  func requestAuthorization() async throws -> HealthAuthorizationSummary {
    started = true
    return await withCheckedContinuation { continuation = $0 }
  }

  func didStartAuthorization() -> Bool { started }

  func finishAuthorization(_ summary: HealthAuthorizationSummary) {
    continuation?.resume(returning: summary)
    continuation = nil
  }

  func save(
    entryID: UUID,
    version: Int,
    foodName: String,
    consumedAt: Date,
    source: EntrySource,
    fdcID: Int?,
    nutrients: [NutrientAmount]
  ) async throws {}
}

private actor TrackingHealthWriter: HealthNutritionWriting {
  nonisolated let isAvailable = true
  private let summary: HealthAuthorizationSummary
  private var authorizationRequests = 0
  private var saveRequests = 0
  private var deleteRequests = 0
  private let saveShouldFail: Bool
  private let deleteShouldFail: Bool

  init(
    summary: HealthAuthorizationSummary,
    saveShouldFail: Bool = false,
    deleteShouldFail: Bool = false
  ) {
    self.summary = summary
    self.saveShouldFail = saveShouldFail
    self.deleteShouldFail = deleteShouldFail
  }

  func requestAuthorization() async throws -> HealthAuthorizationSummary {
    authorizationRequests += 1
    return summary
  }

  func save(
    entryID: UUID,
    version: Int,
    foodName: String,
    consumedAt: Date,
    source: EntrySource,
    fdcID: Int?,
    nutrients: [NutrientAmount]
  ) async throws {
    saveRequests += 1
    if saveShouldFail { throw HealthWriterProbeError.expected }
  }

  func delete(entryID: UUID, version: Int) async throws {
    deleteRequests += 1
    if deleteShouldFail { throw HealthWriterProbeError.expected }
  }

  func authorizationRequestCount() -> Int { authorizationRequests }
  func saveRequestCount() -> Int { saveRequests }
  func deleteRequestCount() -> Int { deleteRequests }
}

private enum HealthWriterProbeError: LocalizedError, Sendable {
  case expected

  var errorDescription: String? { "Apple Health cleanup couldn’t be completed." }
}
