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

  func testUnexpectedCanonicalUnitSoftFailsToGramWithoutCrashing() {
    // Guardrail: unit mapping must never preconditionFailure on unknown strings.
    XCTAssertEqual(HealthKitNutrientMapping.unit(forCanonicalUnit: "not-a-real-unit"), .gram())
    XCTAssertEqual(HealthKitNutrientMapping.unit(forCanonicalUnit: ""), .gram())
    XCTAssertEqual(HealthKitNutrientMapping.unit(forCanonicalUnit: "kcal"), .kilocalorie())
  }

  func testAuthorizationRequestsEveryWritableNutrientType() {
    XCTAssertEqual(
      Set(HealthKitNutrientMapping.requestableShareTypes.map(\.identifier)),
      Set(HealthKitNutrientMapping.allQuantityTypes.map(\.identifier))
    )
  }

  func testAuthorizationShareTypesExcludeFoodCorrelation() {
    // CONTINUATION_HANDOFF: Food correlation is save-only. Requesting it in toShare
    // raises "Authorization to share … HKCorrelationTypeIdentifierFood is disallowed".
    // Share auth is quantity types only (requestableShareTypes == allQuantityTypes);
    // save/delete still use the Food correlation type.
    XCTAssertEqual(
      Set(HealthKitNutrientMapping.requestableShareTypes.map(\.identifier)),
      Set(HealthKitNutrientMapping.allQuantityTypes.map(\.identifier))
    )
    guard let foodType = HealthKitNutrientMapping.foodCorrelationType else {
      return XCTFail("Food correlation type must remain available for save/delete")
    }
    XCTAssertTrue(foodType is HKCorrelationType)
    XCTAssertTrue(
      HealthKitNutrientMapping.deletionTargets(entryID: UUID())
        .contains { $0.type == foodType }
    )
  }

  func testAuthorizationDisallowedErrorSurfacesUserVisibleRecoveryMessage() {
    let disallowed = HealthKitWriteError.authorizationFailure(
      from: "Authorization to share the following types is disallowed: HKCorrelationTypeIdentifierFood"
    )
    XCTAssertEqual(
      disallowed.errorDescription,
      "Apple Health couldn’t authorize nutrition write access for this build. Try again on a device, or review Health permissions in Settings."
    )

    let empty = HealthKitWriteError.authorizationFailure(from: "")
    XCTAssertEqual(
      empty.errorDescription,
      "Apple Health couldn’t open the permission sheet for this build. Check HealthKit signing and try again on a device."
    )

    let mappedFromNSError = HealthKitWriteError.authorizationFailure(
      from: NSError(
        domain: "com.apple.healthkit",
        code: 5,
        userInfo: [NSLocalizedDescriptionKey: "Authorization to share types is disallowed"]
      )
    )
    XCTAssertTrue(
      mappedFromNSError.errorDescription?.localizedCaseInsensitiveContains("couldn’t authorize")
        == true
    )
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
    let defaults = makeDefaults()
    defaults.set(true, forKey: HealthSyncCoordinator.preferenceKey)

    let outcome = await HealthSyncCoordinator.syncIfEnabled(
      entry,
      modelContext: context,
      writer: SuccessfulHealthWriter(),
      defaults: defaults
    )

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
    await writer.waitUntilAuthorizationStarts()

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
  func testSettingsAuthorizationThrowSurfacesUserVisibleErrorWithoutCrash() async {
    let defaults = makeDefaults()
    let writer = ThrowingAuthorizationWriter(
      error: HealthKitWriteError.authorizationFailure(
        from: "Authorization to share the following types is disallowed: HKCorrelationTypeIdentifierFood"
      )
    )
    let model = HealthSyncSettingsModel(writer: writer, defaults: defaults)

    await model.setEnabled(true)

    XCTAssertFalse(model.isEnabled)
    XCTAssertFalse(defaults.bool(forKey: HealthSyncCoordinator.preferenceKey))
    XCTAssertEqual(
      model.message,
      "Apple Health couldn’t authorize nutrition write access for this build. Try again on a device, or review Health permissions in Settings."
    )
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
  func testExplicitRetryAuthorizationThrowSurfacesUserVisibleErrorWithoutCrash() async throws {
    let defaults = makeDefaults()
    defaults.set(true, forKey: HealthSyncCoordinator.preferenceKey)
    let expectedMessage =
      "Apple Health couldn’t authorize nutrition write access for this build. Try again on a device, or review Health permissions in Settings."
    let writer = ThrowingAuthorizationWriter(
      error: HealthKitWriteError.authorizationFailure(
        from: "Authorization to share the following types is disallowed: HKCorrelationTypeIdentifierFood"
      )
    )
    let store = try makeEntry(status: .failed)

    let outcome = await HealthSyncCoordinator.retry(
      store.entry, modelContext: store.context, writer: writer, defaults: defaults)
    let saveRequests = await writer.saveRequestCount()

    XCTAssertEqual(outcome, .denied(expectedMessage))
    XCTAssertTrue(outcome.offersSettingsRecovery)
    XCTAssertEqual(outcome.message, expectedMessage)
    XCTAssertEqual(store.entry.healthSyncStatus, .denied)
    XCTAssertEqual(store.entry.healthSyncError, expectedMessage)
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
  func testReconciliationFetchFailureDoesNotCallHealthWriter() async throws {
    let defaults = makeDefaults()
    defaults.set(true, forKey: HealthSyncCoordinator.preferenceKey)
    let writer = TrackingHealthWriter(summary: .authorized)
    let store = try makeEntry(status: .pending)
    let persistence = HealthPersistenceFaultProbe(failEntryFetch: true).persistence

    let summary = await HealthSyncCoordinator.reconcile(
      modelContext: store.context,
      writer: writer,
      defaults: defaults,
      persistence: persistence
    )
    let saveRequests = await writer.saveRequestCount()

    XCTAssertEqual(summary.persistenceFailures, 1)
    XCTAssertEqual(summary.attemptedCount, 0)
    XCTAssertEqual(saveRequests, 0)
    XCTAssertEqual(store.entry.healthSyncStatus, .pending)
    withExtendedLifetime(store.container) {}
  }

  @MainActor
  func testPreWritePersistenceFailureRollsBackAndNeverCallsHealthWriter() async throws {
    let defaults = makeDefaults()
    defaults.set(true, forKey: HealthSyncCoordinator.preferenceKey)
    let writer = TrackingHealthWriter(summary: .authorized)
    let store = try makeEntry()
    let persistence = HealthPersistenceFaultProbe(failingSaveNumbers: [1]).persistence

    let outcome = await HealthSyncCoordinator.syncIfEnabled(
      store.entry,
      modelContext: store.context,
      writer: writer,
      defaults: defaults,
      persistence: persistence
    )
    let saveRequests = await writer.saveRequestCount()

    guard case .failed = outcome else {
      return XCTFail("A failed pending-state commit must fail the sync")
    }
    XCTAssertEqual(saveRequests, 0)
    XCTAssertEqual(store.entry.healthSyncStatus, .notRequested)
    XCTAssertNil(store.entry.healthSyncError)
    withExtendedLifetime(store.container) {}
  }

  @MainActor
  func testPostWritePersistenceFailureLeavesDurablePendingStateAndCanRecover() async throws {
    let defaults = makeDefaults()
    defaults.set(true, forKey: HealthSyncCoordinator.preferenceKey)
    let writer = TrackingHealthWriter(summary: .authorized)
    let store = try makeEntry()
    let persistence = HealthPersistenceFaultProbe(failingSaveNumbers: [2]).persistence

    let uncertain = await HealthSyncCoordinator.syncIfEnabled(
      store.entry,
      modelContext: store.context,
      writer: writer,
      defaults: defaults,
      persistence: persistence
    )
    let initialSaveRequests = await writer.saveRequestCount()

    guard case .failed(let message) = uncertain else {
      return XCTFail("A failed completion-state commit must not report synced")
    }
    XCTAssertTrue(message.contains("may have been updated"))
    XCTAssertEqual(initialSaveRequests, 1)
    XCTAssertEqual(store.entry.healthSyncStatus, .pending)
    XCTAssertNil(store.entry.healthSyncedAt)

    let recovered = await HealthSyncCoordinator.reconcile(
      modelContext: store.context,
      writer: writer,
      defaults: defaults
    )
    let recoveredSaveRequests = await writer.saveRequestCount()

    XCTAssertEqual(recovered.writesCompleted, 1)
    XCTAssertEqual(store.entry.healthSyncStatus, .synced)
    XCTAssertNotNil(store.entry.healthSyncedAt)
    XCTAssertEqual(recoveredSaveRequests, 2)
    withExtendedLifetime(store.container) {}
  }

  @MainActor
  func testFailedWriterStateSaveFailureDoesNotExposeUncommittedFailedState() async throws {
    let defaults = makeDefaults()
    defaults.set(true, forKey: HealthSyncCoordinator.preferenceKey)
    let writer = TrackingHealthWriter(summary: .authorized, saveShouldFail: true)
    let store = try makeEntry()
    let persistence = HealthPersistenceFaultProbe(failingSaveNumbers: [2]).persistence

    let outcome = await HealthSyncCoordinator.syncIfEnabled(
      store.entry,
      modelContext: store.context,
      writer: writer,
      defaults: defaults,
      persistence: persistence
    )
    let saveRequests = await writer.saveRequestCount()

    guard case .failed(let message) = outcome else {
      return XCTFail("A failed failure-state commit must remain a failed outcome")
    }
    XCTAssertTrue(message.contains("couldn’t save the retry status"))
    XCTAssertEqual(saveRequests, 1)
    XCTAssertEqual(store.entry.healthSyncStatus, .pending)
    XCTAssertNil(store.entry.healthSyncError)
    withExtendedLifetime(store.container) {}
  }

  @MainActor
  func testDeniedWriterStateSaveFailureDoesNotExposeUncommittedDeniedState() async throws {
    let defaults = makeDefaults()
    defaults.set(true, forKey: HealthSyncCoordinator.preferenceKey)
    let writer = DeniedHealthWriter()
    let store = try makeEntry()
    let persistence = HealthPersistenceFaultProbe(failingSaveNumbers: [2]).persistence

    let outcome = await HealthSyncCoordinator.syncIfEnabled(
      store.entry,
      modelContext: store.context,
      writer: writer,
      defaults: defaults,
      persistence: persistence
    )
    let saveRequests = await writer.saveRequestCount()

    guard case .failed(let message) = outcome else {
      return XCTFail("An uncommitted denied state must not be reported as durable")
    }
    XCTAssertTrue(message.contains("couldn’t save that status"))
    XCTAssertEqual(saveRequests, 1)
    XCTAssertEqual(store.entry.healthSyncStatus, .pending)
    XCTAssertNil(store.entry.healthSyncError)
    withExtendedLifetime(store.container) {}
  }

  @MainActor
  func testWriteReconciliationSaveFailureDoesNotCallHealthWriterOrConsumeRetry() async throws {
    let defaults = makeDefaults()
    defaults.set(true, forKey: HealthSyncCoordinator.preferenceKey)
    let writer = TrackingHealthWriter(summary: .authorized)
    let store = try makeEntry(status: .failed)
    let persistence = HealthPersistenceFaultProbe(failingSaveNumbers: [1]).persistence

    let summary = await HealthSyncCoordinator.reconcile(
      modelContext: store.context,
      writer: writer,
      defaults: defaults,
      now: Date(timeIntervalSince1970: 3_500),
      persistence: persistence
    )
    let saveRequests = await writer.saveRequestCount()

    XCTAssertEqual(summary.writesFailed, 1)
    XCTAssertEqual(saveRequests, 0)
    XCTAssertEqual(store.entry.healthSyncStatus, .failed)
    XCTAssertEqual(store.entry.healthSyncRetryCount, 0)
    XCTAssertNil(store.entry.healthSyncNextRetryAt)
    withExtendedLifetime(store.container) {}
  }

  @MainActor
  func testReconciliationSaveFailureDoesNotStartExternalDeletion() async throws {
    let writer = TrackingHealthWriter(summary: .authorized)
    let store = try makeEntry(status: .deletionPending)
    let tombstone = HealthDeletionTombstone(
      entryID: store.entry.id,
      healthSyncVersion: store.entry.healthSyncVersion,
      createdAt: Date(timeIntervalSince1970: 4_000)
    )
    store.context.insert(tombstone)
    try store.context.save()
    let persistence = HealthPersistenceFaultProbe(failingSaveNumbers: [1]).persistence

    let summary = await HealthSyncCoordinator.reconcile(
      modelContext: store.context,
      writer: writer,
      defaults: makeDefaults(),
      now: Date(timeIntervalSince1970: 4_001),
      persistence: persistence
    )
    let deleteRequests = await writer.deleteRequestCount()

    XCTAssertEqual(summary.deletionsFailed, 1)
    XCTAssertEqual(summary.persistenceFailures, 1)
    XCTAssertEqual(deleteRequests, 0)
    XCTAssertEqual(tombstone.retryCount, 0)
    XCTAssertNil(tombstone.nextRetryAt)
    XCTAssertEqual(store.entry.healthSyncStatus, .deletionPending)
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
    addTeardownBlock {
      UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    }
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
  private var startWaiters: [CheckedContinuation<Void, Never>] = []

  func requestAuthorization() async throws -> HealthAuthorizationSummary {
    started = true
    let waiters = startWaiters
    startWaiters.removeAll()
    for waiter in waiters { waiter.resume() }
    return await withCheckedContinuation { continuation = $0 }
  }

  func waitUntilAuthorizationStarts() async {
    guard !started else { return }
    await withCheckedContinuation { startWaiters.append($0) }
  }

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

private actor DeniedHealthWriter: HealthNutritionWriting {
  nonisolated let isAvailable = true
  private var saveRequests = 0

  func requestAuthorization() async throws -> HealthAuthorizationSummary { .authorized }

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
    throw HealthKitWriteError.noAuthorizedNutrients
  }

  func saveRequestCount() -> Int { saveRequests }
}

/// Produces a thrown authorization error so Settings/retry paths can be tested without
/// invoking real HealthKit (which may SIGABRT on disallowed share types).
private actor ThrowingAuthorizationWriter: HealthNutritionWriting {
  nonisolated let isAvailable = true
  private let error: HealthKitWriteError
  private var saveRequests = 0

  init(error: HealthKitWriteError) {
    self.error = error
  }

  func requestAuthorization() async throws -> HealthAuthorizationSummary {
    throw error
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
  }

  func saveRequestCount() -> Int { saveRequests }
}

private enum HealthWriterProbeError: LocalizedError, Sendable {
  case expected

  var errorDescription: String? { "Apple Health cleanup couldn’t be completed." }
}

@MainActor
private final class HealthPersistenceFaultProbe {
  private let failEntryFetch: Bool
  private let failingSaveNumbers: Set<Int>
  private var saveCount = 0

  init(failEntryFetch: Bool = false, failingSaveNumbers: Set<Int> = []) {
    self.failEntryFetch = failEntryFetch
    self.failingSaveNumbers = failingSaveNumbers
  }

  var persistence: HealthSyncPersistence {
    HealthSyncPersistence(
      fetchEntries: { [self] context in
        if failEntryFetch { throw HealthPersistenceProbeError.expected }
        return try context.fetch(FetchDescriptor<FoodLogEntryRecord>())
      },
      fetchTombstones: { context in
        try context.fetch(FetchDescriptor<HealthDeletionTombstone>())
      },
      save: { [self] context in
        saveCount += 1
        if failingSaveNumbers.contains(saveCount) {
          throw HealthPersistenceProbeError.expected
        }
        try context.save()
      },
      rollback: { $0.rollback() }
    )
  }
}

private enum HealthPersistenceProbeError: Error {
  case expected
}
