import AppIntents
import Foundation

/// Lightweight App Entity for a saved food-log entry.
///
/// Backed by the stable `FoodLogEntryRecord.id`. Exposes only fields that are
/// appropriate outside the app (display name + optional calories). Health sync
/// diagnostics and raw USDA payload details are intentionally omitted.
///
/// ## Spike A scope
/// - On-screen awareness via SwiftUI `.appEntityIdentifier` (see `EntryDetailView`
///   and `EntryRow`). Requires `import AppIntents` in those views so the
///   AppIntents↔SwiftUI cross-import overlay provides the modifier.
/// - `EntityQuery` is a stub: empty suggestions / empty lookups until a
///   store-backed query is wired without opening a second `ModelContainer`
///   (prefer the `TodayNutritionSnapshotSource` bind pattern).
/// - **Not** Spotlight-indexed (`IndexedEntity` is deliberately not adopted).
struct FoodLogEntryEntity: AppEntity {
  // Computed (not stored `static var`) so Swift 6 concurrency treats them as
  // safe — stored mutable statics fail `#MutableGlobalVariable`.
  static var typeDisplayRepresentation: TypeDisplayRepresentation {
    TypeDisplayRepresentation(name: "Food Log Entry")
  }
  static var defaultQuery: FoodLogEntryEntityQuery {
    FoodLogEntryEntityQuery()
  }

  /// Stable identity matching `FoodLogEntryRecord.id`.
  var id: UUID

  /// Human-readable food / meal name.
  var displayName: String

  /// Energy in kcal when known.
  var calories: Double?

  var displayRepresentation: DisplayRepresentation {
    if let calories {
      let cal = calories.formatted(.number.precision(.fractionLength(0)))
      return DisplayRepresentation(
        title: "\(displayName)",
        subtitle: "\(cal) cal"
      )
    }
    return DisplayRepresentation(title: "\(displayName)")
  }

  init(id: UUID, displayName: String, calories: Double? = nil) {
    self.id = id
    self.displayName = displayName
    self.calories = calories
  }

  /// Convenience from a SwiftData record (UI annotation / future query mapping).
  init(record: FoodLogEntryRecord) {
    self.id = record.id
    self.displayName = record.displayName
    self.calories = record.calories
  }
}

/// Spike A query stub. Resolves nothing until store-backed lookup is added.
///
/// Prefer reading the already-bootstrapped container (same pattern as
/// `TodayNutritionSnapshotSource`) rather than opening a second store.
struct FoodLogEntryEntityQuery: EntityQuery {
  func entities(for identifiers: [FoodLogEntryEntity.ID]) async throws -> [FoodLogEntryEntity] {
    // Empty is intentional for Spike A — on-screen identifiers still annotate views.
    _ = identifiers
    return []
  }

  func suggestedEntities() async throws -> [FoodLogEntryEntity] {
    []
  }
}
