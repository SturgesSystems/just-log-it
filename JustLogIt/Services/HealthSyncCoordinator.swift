import Foundation
import OSLog
import SwiftData

enum HealthSyncOutcome: Equatable {
  case disabled
  case synced
  case denied(String)
  case failed(String)

  var message: String? {
    switch self {
    case .disabled:
      "Turn on Save nutrition to Apple Health in Settings before trying again."
    case .synced:
      "This entry was saved to Apple Health."
    case .denied(let message), .failed(let message):
      message
    }
  }

  var offersSettingsRecovery: Bool {
    switch self {
    case .disabled, .denied: true
    case .synced, .failed: false
    }
  }
}

enum HealthEntryDeletionOutcome: Equatable {
  case deleted
  case pending(String)
  case failed(String)
}

struct HealthReconciliationSummary: Equatable {
  var writesCompleted = 0
  var writesFailed = 0
  var deletionsCompleted = 0
  var deletionsFailed = 0
  var persistenceFailures = 0

  var attemptedCount: Int {
    writesCompleted + writesFailed + deletionsCompleted + deletionsFailed
  }

  /// True when the lifecycle banner should read as a warning rather than a success note.
  var needsAttention: Bool {
    writesFailed + deletionsFailed > 0 || persistenceFailures > 0
  }

  var message: String? {
    guard attemptedCount > 0 || persistenceFailures > 0 else { return nil }
    if persistenceFailures > 0 {
      return
        "JustLogIt couldn’t confirm some Apple Health updates. Your food is saved here; status will refresh later."
    }
    let failures = writesFailed + deletionsFailed
    let successes = writesCompleted + deletionsCompleted
    if failures > 0 {
      let entryWord = failures == 1 ? "entry" : "entries"
      if successes > 0 {
        // Partial sync: some Health updates landed; others still need a retry from Entries.
        return
          "Some Apple Health updates finished; \(failures) \(entryWord) still need attention. Your food stays in JustLogIt — open an entry to try again."
      }
      return
        "Apple Health couldn’t update \(failures) \(entryWord). Your food stays in JustLogIt — open an entry to try again."
    }
    let entryWord = attemptedCount == 1 ? "entry" : "entries"
    return "Apple Health is up to date for \(attemptedCount) \(entryWord)."
  }
}

/// A narrow persistence boundary so coordinator ordering and failure behavior can be tested without
/// making external HealthKit calls. Production always uses `live`; tests can deterministically fail
/// an individual fetch or save operation.
@MainActor
struct HealthSyncPersistence {
  var fetchEntries: (ModelContext) throws -> [FoodLogEntryRecord]
  var fetchTombstones: (ModelContext) throws -> [HealthDeletionTombstone]
  var save: (ModelContext) throws -> Void
  var rollback: (ModelContext) -> Void

  static let live = HealthSyncPersistence(
    fetchEntries: { try $0.fetch(FetchDescriptor<FoodLogEntryRecord>()) },
    fetchTombstones: { try $0.fetch(FetchDescriptor<HealthDeletionTombstone>()) },
    save: { try $0.save() },
    rollback: { $0.rollback() }
  )
}

@MainActor
enum HealthSyncCoordinator {
  static let preferenceKey = "healthSyncEnabled"
  static let maximumAutomaticRetries = 3

  @discardableResult
  static func syncIfEnabled(
    _ entry: FoodLogEntryRecord,
    modelContext: ModelContext,
    writer: any HealthNutritionWriting = HealthKitNutritionWriter.shared,
    defaults: UserDefaults = .standard,
    persistence: HealthSyncPersistence = .live
  ) async -> HealthSyncOutcome {
    guard defaults.bool(forKey: preferenceKey) else { return .disabled }
    return await save(
      entry, modelContext: modelContext, writer: writer, persistence: persistence)
  }

  static func retry(
    _ entry: FoodLogEntryRecord,
    modelContext: ModelContext,
    writer: any HealthNutritionWriting = HealthKitNutritionWriter.shared,
    defaults: UserDefaults = .standard,
    persistence: HealthSyncPersistence = .live
  ) async -> HealthSyncOutcome {
    guard defaults.bool(forKey: preferenceKey) else { return .disabled }

    do {
      let summary = try await writer.requestAuthorization()
      guard summary.canWrite else {
        return finishDenied(
          entry,
          message: "Apple Health access wasn’t granted. You can review access in Settings.",
          modelContext: modelContext,
          persistence: persistence
        )
      }
    } catch let error as HealthKitWriteError {
      // Authorization failures are user-visible and must never crash. Disallowed /
      // permission issues offer Settings recovery; unavailability is a hard failure.
      switch error {
      case .authorizationDisallowed, .noAuthorizedNutrients:
        return finishDenied(
          entry,
          message: error.localizedDescription,
          modelContext: modelContext,
          persistence: persistence
        )
      case .unavailable:
        return finishFailed(
          entry,
          message: error.localizedDescription,
          modelContext: modelContext,
          persistence: persistence
        )
      }
    } catch {
      let message =
        (error as? LocalizedError)?.errorDescription
        ?? "Apple Health access couldn’t be requested."
      return finishFailed(
        entry, message: message, modelContext: modelContext, persistence: persistence)
    }

    entry.healthSyncRetryCount = 0
    entry.healthSyncNextRetryAt = nil
    return await save(
      entry, modelContext: modelContext, writer: writer, persistence: persistence)
  }

  static func reconcile(
    modelContext: ModelContext,
    writer: any HealthNutritionWriting = HealthKitNutritionWriter.shared,
    defaults: UserDefaults = .standard,
    now: Date = .now,
    persistence: HealthSyncPersistence = .live
  ) async -> HealthReconciliationSummary {
    var summary = HealthReconciliationSummary()

    if defaults.bool(forKey: preferenceKey) {
      do {
        let entries = try persistence.fetchEntries(modelContext)
        for entry in entries where shouldRetryWrite(entry, now: now) && !Task.isCancelled {
          let outcome = await save(
            entry,
            modelContext: modelContext,
            writer: writer,
            automaticRetryAt: now,
            persistence: persistence)
          switch outcome {
          case .synced: summary.writesCompleted += 1
          case .failed, .denied: summary.writesFailed += 1
          case .disabled: break
          }
        }
      } catch {
        observePersistenceFailure(.reconciliationEntryFetch)
        summary.persistenceFailures += 1
      }
    }

    do {
      let tombstones = try persistence.fetchTombstones(modelContext)
      if !tombstones.isEmpty {
        let entries = try persistence.fetchEntries(modelContext)
        let entriesByID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        for tombstone in tombstones
        where shouldRetryDeletion(tombstone, now: now)
          && !Task.isCancelled
        {
          recordDeletionAttempt(tombstone, now: now)
          do {
            try persistence.save(modelContext)
          } catch {
            persistence.rollback(modelContext)
            observePersistenceFailure(.reconciliationDeletionPreflightSave)
            summary.deletionsFailed += 1
            summary.persistenceFailures += 1
            continue
          }

          do {
            try await writer.delete(
              entryID: tombstone.entryID, version: tombstone.healthSyncVersion)
          } catch {
            recordDeletionError(tombstone, error: error)
            if let entry = entriesByID[tombstone.entryID] {
              entry.healthSyncStatus = .deletionPending
              entry.healthSyncError = tombstone.lastError
            }
            do {
              try persistence.save(modelContext)
            } catch {
              persistence.rollback(modelContext)
              observePersistenceFailure(.reconciliationDeletionFailureSave)
              summary.persistenceFailures += 1
            }
            summary.deletionsFailed += 1
            continue
          }

          if let entry = entriesByID[tombstone.entryID] { modelContext.delete(entry) }
          modelContext.delete(tombstone)
          do {
            try persistence.save(modelContext)
            summary.deletionsCompleted += 1
          } catch {
            persistence.rollback(modelContext)
            observePersistenceFailure(.reconciliationDeletionCompletionSave)
            summary.deletionsFailed += 1
            summary.persistenceFailures += 1
          }
        }
      }
    } catch {
      observePersistenceFailure(.reconciliationDeletionFetch)
      summary.persistenceFailures += 1
    }

    return summary
  }

  static func deleteEntry(
    _ entry: FoodLogEntryRecord,
    modelContext: ModelContext,
    writer: any HealthNutritionWriting = HealthKitNutritionWriter.shared,
    now: Date = .now,
    persistence: HealthSyncPersistence = .live
  ) async -> HealthEntryDeletionOutcome {
    guard entry.healthSyncStatus == .synced || entry.healthSyncStatus == .deletionPending else {
      modelContext.delete(entry)
      do {
        try persistence.save(modelContext)
        return .deleted
      } catch {
        persistence.rollback(modelContext)
        observePersistenceFailure(.localDeletionSave)
        return .failed("Your entry is still saved. Please try again.")
      }
    }

    let deletionTombstone: HealthDeletionTombstone
    let existingTombstone: HealthDeletionTombstone?
    do {
      existingTombstone = try tombstone(for: entry.id, in: modelContext)
    } catch {
      observePersistenceFailure(.deletionTombstoneFetch)
      return .failed("Your entry is still saved. Apple Health deletion wasn’t started.")
    }
    if let existing = existingTombstone {
      deletionTombstone = existing
      deletionTombstone.retryCount = 0
      deletionTombstone.nextRetryAt = nil
    } else {
      deletionTombstone = HealthDeletionTombstone(
        entryID: entry.id, healthSyncVersion: entry.healthSyncVersion, createdAt: now)
      modelContext.insert(deletionTombstone)
    }
    entry.healthSyncStatus = .deletionPending
    entry.healthSyncError = nil

    do {
      try persistence.save(modelContext)
    } catch {
      persistence.rollback(modelContext)
      observePersistenceFailure(.deletionPreflightSave)
      return .failed("Your entry is still saved. Apple Health deletion wasn’t started.")
    }

    do {
      try await writer.delete(entryID: entry.id, version: entry.healthSyncVersion)
    } catch {
      recordDeletionFailure(deletionTombstone, error: error, now: now)
      entry.healthSyncError = deletionTombstone.lastError
      do {
        try persistence.save(modelContext)
      } catch {
        persistence.rollback(modelContext)
        observePersistenceFailure(.deletionFailureSave)
      }
      return .pending(
        "The entry is still saved. Apple Health cleanup will retry when JustLogIt becomes active."
      )
    }

    modelContext.delete(deletionTombstone)
    modelContext.delete(entry)
    do {
      try persistence.save(modelContext)
      return .deleted
    } catch {
      persistence.rollback(modelContext)
      observePersistenceFailure(.deletionCompletionSave)
      return .pending(
        "Apple Health cleanup finished, but the local entry couldn’t be removed. JustLogIt will reconcile it later."
      )
    }
  }

  private static func save(
    _ entry: FoodLogEntryRecord,
    modelContext: ModelContext,
    writer: any HealthNutritionWriting,
    automaticRetryAt: Date? = nil,
    persistence: HealthSyncPersistence
  ) async -> HealthSyncOutcome {
    if let automaticRetryAt {
      recordWriteRetry(entry, now: automaticRetryAt)
    }
    entry.healthSyncStatus = .pending
    entry.healthSyncError = nil
    do {
      try persistence.save(modelContext)
    } catch {
      persistence.rollback(modelContext)
      observePersistenceFailure(.writePreflightSave)
      return .failed(
        "Apple Health wasn’t updated because JustLogIt couldn’t save its pending status. Please try again."
      )
    }

    do {
      try await writer.save(
        entryID: entry.id,
        version: entry.healthSyncVersion,
        foodName: entry.displayName,
        consumedAt: entry.consumedAt,
        source: entry.source,
        fdcID: entry.fdcID,
        nutrients: entry.nutrients
      )
    } catch let error as HealthKitWriteError {
      switch error {
      case .noAuthorizedNutrients, .authorizationDisallowed:
        return finishDenied(
          entry,
          message: error.localizedDescription,
          modelContext: modelContext,
          persistence: persistence)
      case .unavailable:
        return finishFailed(
          entry,
          message: error.localizedDescription,
          modelContext: modelContext,
          persistence: persistence)
      }
    } catch is CancellationError {
      return finishFailed(
        entry,
        message: "Apple Health update was interrupted. It will retry later.",
        modelContext: modelContext,
        persistence: persistence)
    } catch {
      return finishFailed(
        entry,
        message: "Apple Health couldn’t be updated.",
        modelContext: modelContext,
        persistence: persistence)
    }

    entry.healthSyncStatus = .synced
    entry.healthSyncedAt = .now
    entry.healthSyncError = nil
    entry.healthSyncRetryCount = 0
    entry.healthSyncNextRetryAt = nil
    do {
      try persistence.save(modelContext)
      return .synced
    } catch {
      persistence.rollback(modelContext)
      observePersistenceFailure(.writeCompletionSave)
      return .failed(
        "Apple Health may have been updated, but JustLogIt couldn’t confirm it. It will reconcile later."
      )
    }
  }

  private static func shouldRetryWrite(_ entry: FoodLogEntryRecord, now: Date) -> Bool {
    guard entry.healthSyncStatus == .pending || entry.healthSyncStatus == .failed,
      entry.healthSyncRetryCount < maximumAutomaticRetries
    else { return false }
    return entry.healthSyncNextRetryAt.map { $0 <= now } ?? true
  }

  private static func shouldRetryDeletion(
    _ tombstone: HealthDeletionTombstone,
    now: Date
  ) -> Bool {
    guard tombstone.retryCount < maximumAutomaticRetries else { return false }
    return tombstone.nextRetryAt.map { $0 <= now } ?? true
  }

  private static func recordWriteRetry(
    _ entry: FoodLogEntryRecord,
    now: Date
  ) {
    entry.healthSyncRetryCount += 1
    entry.healthSyncNextRetryAt = now.addingTimeInterval(
      retryDelay(after: entry.healthSyncRetryCount))
  }

  private static func recordDeletionFailure(
    _ tombstone: HealthDeletionTombstone,
    error: any Error,
    now: Date
  ) {
    recordDeletionAttempt(tombstone, now: now)
    recordDeletionError(tombstone, error: error)
  }

  private static func recordDeletionAttempt(
    _ tombstone: HealthDeletionTombstone,
    now: Date
  ) {
    tombstone.retryCount += 1
    tombstone.nextRetryAt = now.addingTimeInterval(retryDelay(after: tombstone.retryCount))
  }

  private static func recordDeletionError(
    _ tombstone: HealthDeletionTombstone,
    error: any Error
  ) {
    tombstone.lastError =
      (error as? LocalizedError)?.errorDescription
      ?? "Apple Health cleanup couldn’t be completed."
  }

  private static func retryDelay(after attempt: Int) -> TimeInterval {
    switch attempt {
    case 0...1: 60
    case 2: 5 * 60
    default: 30 * 60
    }
  }

  private static func tombstone(
    for entryID: UUID,
    in modelContext: ModelContext
  ) throws -> HealthDeletionTombstone? {
    let descriptor = FetchDescriptor<HealthDeletionTombstone>(
      predicate: #Predicate { $0.entryID == entryID })
    return try modelContext.fetch(descriptor).first
  }

  private static func finishDenied(
    _ entry: FoodLogEntryRecord,
    message: String,
    modelContext: ModelContext,
    persistence: HealthSyncPersistence
  ) -> HealthSyncOutcome {
    entry.healthSyncStatus = .denied
    entry.healthSyncError = message
    do {
      try persistence.save(modelContext)
      return .denied(message)
    } catch {
      persistence.rollback(modelContext)
      observePersistenceFailure(.deniedStateSave)
      return .failed(
        "Apple Health access wasn’t granted, but JustLogIt couldn’t save that status. Please try again."
      )
    }
  }

  private static func finishFailed(
    _ entry: FoodLogEntryRecord,
    message: String,
    modelContext: ModelContext,
    persistence: HealthSyncPersistence
  ) -> HealthSyncOutcome {
    entry.healthSyncStatus = .failed
    entry.healthSyncError = message
    do {
      try persistence.save(modelContext)
      return .failed(message)
    } catch {
      persistence.rollback(modelContext)
      observePersistenceFailure(.failedStateSave)
      return .failed(
        "Apple Health couldn’t be updated, and JustLogIt couldn’t save the retry status. Please try again."
      )
    }
  }
}

private enum HealthPersistenceOperation: String {
  case reconciliationEntryFetch = "reconciliation_entry_fetch"
  case reconciliationDeletionFetch = "reconciliation_deletion_fetch"
  case reconciliationDeletionPreflightSave = "reconciliation_deletion_preflight_save"
  case reconciliationDeletionFailureSave = "reconciliation_deletion_failure_save"
  case reconciliationDeletionCompletionSave = "reconciliation_deletion_completion_save"
  case localDeletionSave = "local_deletion_save"
  case deletionTombstoneFetch = "deletion_tombstone_fetch"
  case deletionPreflightSave = "deletion_preflight_save"
  case deletionFailureSave = "deletion_failure_save"
  case deletionCompletionSave = "deletion_completion_save"
  case writePreflightSave = "write_preflight_save"
  case writeCompletionSave = "write_completion_save"
  case deniedStateSave = "denied_state_save"
  case failedStateSave = "failed_state_save"
}

private let healthPersistenceLogger = Logger(
  subsystem: Bundle.main.bundleIdentifier ?? "JustLogIt",
  category: "HealthPersistence"
)

private func observePersistenceFailure(_ operation: HealthPersistenceOperation) {
  healthPersistenceLogger.error(
    "persistence_failure operation=\(operation.rawValue, privacy: .public)"
  )
}
