import Foundation
import SwiftData

/// Shared persistence boundary for confirmed food logs.
///
/// Used by the SwiftUI confirm path today and by future Siri / App Intent adapters
/// (see `Documentation/SIRI_AI_INTEGRATION_SPIKE.md` Spike B). Keeps insert,
/// recognized-food upsert, and save as one transactional unit with rollback on failure.
///
/// UI call sites (`confirmLog`, ManualEntryView) and future Siri intents should use
/// this type — do not add a parallel insert/upsert/save sequence.
@MainActor
struct FoodLogRepository {
  /// Stable IDs produced by a successful save transaction.
  struct SaveResult: Equatable, Sendable {
    let entryID: UUID
    let recognizedFoodID: UUID
  }

  private let context: ModelContext
  private let persist: (ModelContext) throws -> Void

  init(
    context: ModelContext,
    persist: @escaping (ModelContext) throws -> Void = { try $0.save() }
  ) {
    self.context = context
    self.persist = persist
  }

  /// Inserts `entry`, upserts a `RecognizedFoodRecord`, links `entry.recognizedFoodID`,
  /// and commits. On any failure the context is rolled back so partial inserts and
  /// in-memory recognized-food mutations never linger for a later unrelated save.
  ///
  /// - Note: Each call inserts a new entry. Callers (especially intents that may
  ///   retry) must not invoke this twice for the same logical confirmation without
  ///   their own idempotency guard.
  @discardableResult
  func save(_ entry: FoodLogEntryRecord) throws -> SaveResult {
    let recognized = try Self.commit(entry, in: context, persist: persist)
    return SaveResult(entryID: entry.id, recognizedFoodID: recognized.id)
  }

  /// Shared commit used by `FoodLogRepository` and the legacy `FoodLogSaveTransaction` helper.
  static func commit(
    _ entry: FoodLogEntryRecord,
    in context: ModelContext,
    persist: (ModelContext) throws -> Void
  ) throws -> RecognizedFoodRecord {
    do {
      context.insert(entry)
      let recognized = try RecognizedFoodRecord.upsert(from: entry, in: context)
      entry.recognizedFoodID = recognized.id
      try persist(context)
      return recognized
    } catch {
      context.rollback()
      throw error
    }
  }
}

/// Compatibility wrapper around `FoodLogRepository.commit`.
/// Prefer `FoodLogRepository` for new call sites (Siri, shared workflow).
@MainActor
enum FoodLogSaveTransaction {
  @discardableResult
  static func save(
    _ entry: FoodLogEntryRecord,
    in context: ModelContext,
    persist: (ModelContext) throws -> Void = { try $0.save() }
  ) throws -> RecognizedFoodRecord {
    try FoodLogRepository.commit(entry, in: context, persist: persist)
  }
}
