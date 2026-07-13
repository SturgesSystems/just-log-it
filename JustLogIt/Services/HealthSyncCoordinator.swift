import Foundation
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

  var attemptedCount: Int {
    writesCompleted + writesFailed + deletionsCompleted + deletionsFailed
  }

  var message: String? {
    guard attemptedCount > 0 else { return nil }
    let failures = writesFailed + deletionsFailed
    if failures > 0 {
      return
        "Apple Health still needs attention for \(failures) \(failures == 1 ? "entry" : "entries")."
    }
    return
      "Apple Health finished updating \(attemptedCount) \(attemptedCount == 1 ? "entry" : "entries")."
  }
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
    defaults: UserDefaults = .standard
  ) async -> HealthSyncOutcome {
    guard defaults.bool(forKey: preferenceKey) else { return .disabled }
    return await save(entry, modelContext: modelContext, writer: writer)
  }

  static func retry(
    _ entry: FoodLogEntryRecord,
    modelContext: ModelContext,
    writer: any HealthNutritionWriting = HealthKitNutritionWriter.shared,
    defaults: UserDefaults = .standard
  ) async -> HealthSyncOutcome {
    guard defaults.bool(forKey: preferenceKey) else { return .disabled }

    do {
      let summary = try await writer.requestAuthorization()
      guard summary.canWrite else {
        return finishDenied(
          entry,
          message: "Apple Health access wasn’t granted. You can review access in Settings.",
          modelContext: modelContext
        )
      }
    } catch {
      let message =
        (error as? LocalizedError)?.errorDescription
        ?? "Apple Health access couldn’t be requested."
      return finishFailed(entry, message: message, modelContext: modelContext)
    }

    entry.healthSyncRetryCount = 0
    entry.healthSyncNextRetryAt = nil
    return await save(entry, modelContext: modelContext, writer: writer)
  }

  static func reconcile(
    modelContext: ModelContext,
    writer: any HealthNutritionWriting = HealthKitNutritionWriter.shared,
    defaults: UserDefaults = .standard,
    now: Date = .now
  ) async -> HealthReconciliationSummary {
    var summary = HealthReconciliationSummary()

    if defaults.bool(forKey: preferenceKey),
      let entries = try? modelContext.fetch(FetchDescriptor<FoodLogEntryRecord>())
    {
      for entry in entries where shouldRetryWrite(entry, now: now) {
        let outcome = await save(
          entry, modelContext: modelContext, writer: writer, automaticRetryAt: now)
        switch outcome {
        case .synced: summary.writesCompleted += 1
        case .failed, .denied: summary.writesFailed += 1
        case .disabled: break
        }
      }
    }

    if let tombstones = try? modelContext.fetch(FetchDescriptor<HealthDeletionTombstone>()),
      let entries = try? modelContext.fetch(FetchDescriptor<FoodLogEntryRecord>())
    {
      let entriesByID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
      for tombstone in tombstones where shouldRetryDeletion(tombstone, now: now) {
        recordDeletionAttempt(tombstone, now: now)
        try? modelContext.save()
        do {
          try await writer.delete(
            entryID: tombstone.entryID, version: tombstone.healthSyncVersion)
          if let entry = entriesByID[tombstone.entryID] { modelContext.delete(entry) }
          modelContext.delete(tombstone)
          try? modelContext.save()
          summary.deletionsCompleted += 1
        } catch {
          recordDeletionError(tombstone, error: error)
          if let entry = entriesByID[tombstone.entryID] {
            entry.healthSyncStatus = .deletionPending
            entry.healthSyncError = tombstone.lastError
          }
          try? modelContext.save()
          summary.deletionsFailed += 1
        }
      }
    }

    return summary
  }

  static func deleteEntry(
    _ entry: FoodLogEntryRecord,
    modelContext: ModelContext,
    writer: any HealthNutritionWriting = HealthKitNutritionWriter.shared,
    now: Date = .now
  ) async -> HealthEntryDeletionOutcome {
    guard entry.healthSyncStatus == .synced || entry.healthSyncStatus == .deletionPending else {
      modelContext.delete(entry)
      do {
        try modelContext.save()
        return .deleted
      } catch {
        modelContext.rollback()
        return .failed("Your entry is still saved. Please try again.")
      }
    }

    let deletionTombstone: HealthDeletionTombstone
    if let existing = try? tombstone(for: entry.id, in: modelContext) {
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
      try modelContext.save()
    } catch {
      modelContext.rollback()
      return .failed("Your entry is still saved. Apple Health deletion wasn’t started.")
    }

    do {
      try await writer.delete(entryID: entry.id, version: entry.healthSyncVersion)
      modelContext.delete(deletionTombstone)
      modelContext.delete(entry)
      try modelContext.save()
      return .deleted
    } catch {
      recordDeletionFailure(deletionTombstone, error: error, now: now)
      entry.healthSyncError = deletionTombstone.lastError
      try? modelContext.save()
      return .pending(
        "The entry is still saved. Apple Health cleanup will retry when JustLogIt becomes active."
      )
    }
  }

  private static func save(
    _ entry: FoodLogEntryRecord,
    modelContext: ModelContext,
    writer: any HealthNutritionWriting,
    automaticRetryAt: Date? = nil
  ) async -> HealthSyncOutcome {
    if let automaticRetryAt {
      recordWriteRetry(entry, now: automaticRetryAt, in: modelContext)
    }
    entry.healthSyncStatus = .pending
    entry.healthSyncError = nil
    try? modelContext.save()

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
      entry.healthSyncStatus = .synced
      entry.healthSyncedAt = .now
      entry.healthSyncError = nil
      entry.healthSyncRetryCount = 0
      entry.healthSyncNextRetryAt = nil
      try? modelContext.save()
      return .synced
    } catch let error as HealthKitWriteError {
      let outcome: HealthSyncOutcome
      switch error {
      case .foodAccessDenied, .noAuthorizedNutrients:
        outcome = finishDenied(
          entry, message: error.localizedDescription, modelContext: modelContext)
      case .unavailable:
        outcome = finishFailed(
          entry, message: error.localizedDescription, modelContext: modelContext)
      }
      return outcome
    } catch {
      let outcome = finishFailed(
        entry, message: "Apple Health couldn’t be updated.", modelContext: modelContext)
      return outcome
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
    now: Date,
    in modelContext: ModelContext
  ) {
    entry.healthSyncRetryCount += 1
    entry.healthSyncNextRetryAt = now.addingTimeInterval(
      retryDelay(after: entry.healthSyncRetryCount))
    try? modelContext.save()
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
    modelContext: ModelContext
  ) -> HealthSyncOutcome {
    entry.healthSyncStatus = .denied
    entry.healthSyncError = message
    try? modelContext.save()
    return .denied(message)
  }

  private static func finishFailed(
    _ entry: FoodLogEntryRecord,
    message: String,
    modelContext: ModelContext
  ) -> HealthSyncOutcome {
    entry.healthSyncStatus = .failed
    entry.healthSyncError = message
    try? modelContext.save()
    return .failed(message)
  }
}
