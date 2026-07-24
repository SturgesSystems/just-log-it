import Foundation
import JustLogItCore
import SwiftData

/// Local-only daily nutrition totals for future widgets, GetTodayNutritionSummaryIntent,
/// and in-app chrome.
///
/// Built exclusively from the caller's existing `ModelContext`. This type never opens a
/// second SwiftData store and does not use App Groups or network I/O.
struct TodayNutritionSnapshot: Equatable, Sendable {
  /// Start of the calendar day this snapshot covers.
  let dayStart: Date
  /// Number of food-log entries consumed on this day (including entries with no macros).
  let entryCount: Int
  /// Sum of energy (kcal). Missing or non-finite values contribute 0.
  let calories: Double
  /// Sum of protein (g). Missing or non-finite values contribute 0.
  let proteinGrams: Double
  /// Sum of carbohydrate (g). Missing or non-finite values contribute 0.
  let carbohydrateGrams: Double
  /// Sum of total fat (g). Missing or non-finite values contribute 0.
  let fatGrams: Double

  var isEmpty: Bool { entryCount == 0 }

  /// Spoken / Shortcuts dialog for these totals. Pure formatting — no store I/O.
  var spokenSummary: String {
    if isEmpty {
      return "You haven't logged any meals today."
    }
    let entryWord = entryCount == 1 ? "entry" : "entries"
    let cal = calories.formatted(.number.precision(.fractionLength(0)))
    let protein = proteinGrams.formatted(.number.precision(.fractionLength(0...1)))
    let carbs = carbohydrateGrams.formatted(.number.precision(.fractionLength(0...1)))
    let fat = fatGrams.formatted(.number.precision(.fractionLength(0...1)))
    return
      "Today you've logged \(entryCount) \(entryWord): \(cal) calories, \(protein) grams protein, \(carbs) grams carbs, \(fat) grams fat."
  }

  /// Zero totals for a known day boundary (e.g. no entries logged today).
  static func zero(dayStart: Date) -> TodayNutritionSnapshot {
    TodayNutritionSnapshot(
      dayStart: dayStart,
      entryCount: 0,
      calories: 0,
      proteinGrams: 0,
      carbohydrateGrams: 0,
      fatGrams: 0
    )
  }

  /// Aggregates already-fetched entries for `[dayStart, dayEnd)`.
  /// Entries outside that half-open interval are ignored.
  static func make(
    dayStart: Date,
    dayEnd: Date,
    entries: [FoodLogEntryRecord]
  ) -> TodayNutritionSnapshot {
    var calories = 0.0
    var protein = 0.0
    var carbohydrate = 0.0
    var fat = 0.0
    var count = 0

    for entry in entries {
      guard entry.consumedAt >= dayStart, entry.consumedAt < dayEnd else { continue }
      count += 1
      for nutrient in entry.nutrients {
        guard nutrient.amount.isFinite, nutrient.amount >= 0 else { continue }
        switch nutrient.key {
        case .energy:
          calories += nutrient.amount
        case .protein:
          protein += nutrient.amount
        case .carbohydrate:
          carbohydrate += nutrient.amount
        case .totalFat:
          fat += nutrient.amount
        default:
          break
        }
      }
    }

    return TodayNutritionSnapshot(
      dayStart: dayStart,
      entryCount: count,
      calories: calories,
      proteinGrams: protein,
      carbohydrateGrams: carbohydrate,
      fatGrams: fat
    )
  }

  /// Loads today's totals from `context` only — no alternate store path.
  ///
  /// - Parameters:
  ///   - context: The app's existing model context.
  ///   - now: Reference instant used to resolve "today" (injectable in tests).
  ///   - calendar: Calendar for day boundaries (defaults to the device current calendar).
  @MainActor
  static func load(
    from context: ModelContext,
    now: Date = .now,
    calendar: Calendar = .current
  ) throws -> TodayNutritionSnapshot {
    let dayStart = calendar.startOfDay(for: now)
    guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
      return .zero(dayStart: dayStart)
    }

    let descriptor = FetchDescriptor<FoodLogEntryRecord>(
      predicate: #Predicate { entry in
        entry.consumedAt >= dayStart && entry.consumedAt < dayEnd
      }
    )
    let entries = try context.fetch(descriptor)
    return make(dayStart: dayStart, dayEnd: dayEnd, entries: entries)
  }
}

/// Process-local handle to the app's already-open `ModelContainer`.
///
/// Used by foreground intents (e.g. `GetTodayNutritionSummaryIntent`) to read today's
/// totals without opening a second SwiftData store. Bound after bootstrap; cleared on
/// retry/teardown. Never creates or migrates a store.
@MainActor
enum TodayNutritionSnapshotSource {
  private static weak var liveContainer: ModelContainer?

  /// Records the live app container after bootstrap succeeds.
  static func bind(to container: ModelContainer) {
    liveContainer = container
  }

  /// Drops the live container reference (retry / failed open).
  static func unbind() {
    liveContainer = nil
  }

  /// Loads today's snapshot from the bound container's main context, or `nil` when
  /// bootstrap has not finished (or the container was unbound).
  static func loadTodayIfAvailable(
    now: Date = .now,
    calendar: Calendar = .current
  ) throws -> TodayNutritionSnapshot? {
    guard let container = liveContainer else { return nil }
    return try TodayNutritionSnapshot.load(
      from: container.mainContext,
      now: now,
      calendar: calendar
    )
  }
}
