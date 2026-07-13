import Foundation

/// Infers `consumedAt` from casual wording in the original log message.
///
/// Extremely clear cues (just ate / for breakfast / …) are marked `isClear` so the
/// app can put the time on the review card and skip a separate “when?” step.
public struct MealTimeInference: Equatable, Sendable {
  public let date: Date
  /// Short label for the UI (“Just now”, “Breakfast”, “Lunch”).
  public let displayLabel: String
  /// When true, do not ask “When did you eat?” — review already carries the time.
  public let isClear: Bool

  public init(date: Date, displayLabel: String, isClear: Bool) {
    self.date = date
    self.displayLabel = displayLabel
    self.isClear = isClear
  }
}

public enum MealTimeInferenceService: Sendable {
  /// Default chips when the log message did not make timing obvious.
  public static let fallbackSuggestionChips = [
    "Just now", "An hour ago", "Breakfast", "Lunch", "Dinner",
  ]

  /// Chips tailored to a prior inference (still useful if the user reopens when-eaten).
  public static func suggestionChips(for inference: MealTimeInference?) -> [String] {
    guard let inference, inference.isClear else { return fallbackSuggestionChips }
    var chips = [inference.displayLabel]
    for item in fallbackSuggestionChips where !chips.contains(item) {
      chips.append(item)
    }
    return chips
  }

  /// Scan freeform source text (full user message) for clear meal-time cues.
  public static func infer(
    from sourceText: String,
    relativeTo now: Date = .now,
    calendar: Calendar = .current
  ) -> MealTimeInference {
    let lower = normalize(sourceText)
    if lower.isEmpty {
      return MealTimeInference(date: now, displayLabel: "Just now", isClear: false)
    }

    // Immediate past — extremely clear.
    if matchesJustAte(lower) {
      return MealTimeInference(date: now, displayLabel: "Just now", isClear: true)
    }

    // Named meal periods.
    if matchesMeal(lower, keys: ["breakfast", "this morning", "in the morning"]) {
      return meal(
        hour: 8, minute: 0, label: "Breakfast", now: now, calendar: calendar, clear: true)
    }
    if matchesMeal(lower, keys: ["brunch"]) {
      return meal(
        hour: 10, minute: 30, label: "Brunch", now: now, calendar: calendar, clear: true)
    }
    if matchesMeal(lower, keys: ["lunch", "at noon", "this afternoon for lunch"]) {
      return meal(
        hour: 12, minute: 30, label: "Lunch", now: now, calendar: calendar, clear: true)
    }
    if matchesMeal(lower, keys: ["dinner", "supper", "this evening", "tonight for dinner"]) {
      return meal(
        hour: 18, minute: 30, label: "Dinner", now: now, calendar: calendar, clear: true)
    }
    // Softer evening cue without "dinner" word — still clear enough to skip ask.
    if matchesMeal(lower, keys: ["for dinner", "for supper", "for lunch", "for breakfast"]) {
      // Already covered above via contains; kept for clarity.
    }
    if lower.contains("tonight") || lower.contains("this evening") {
      return meal(
        hour: 18, minute: 30, label: "Dinner", now: now, calendar: calendar, clear: true)
    }
    if lower.contains("this afternoon") {
      return meal(
        hour: 15, minute: 0, label: "This afternoon", now: now, calendar: calendar, clear: true)
    }

    // Relative phrases already supported by RelativeTimeParser when used as answers.
    let relative = RelativeTimeParser.parse(sourceText, relativeTo: now, calendar: calendar)
    if relative.wasParsed, !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      // Only auto-skip when the *whole* message is basically a time phrase — rare for food logs.
      // e.g. user edited to "2 hours ago" alone. For mixed "I ate eggs 2 hours ago" try match.
      if looksLikeStandaloneTimePhrase(lower) {
        return MealTimeInference(
          date: relative.date,
          displayLabel: sourceText.trimmingCharacters(in: .whitespacesAndNewlines),
          isClear: true
        )
      }
      if containsRelativeAgo(lower) {
        return MealTimeInference(
          date: relative.date,
          displayLabel: relativeDisplay(for: lower) ?? "Earlier",
          isClear: true
        )
      }
    }

    return MealTimeInference(date: now, displayLabel: "Just now", isClear: false)
  }

  /// Resolve a when-eaten chip or freeform answer (Breakfast / Just now / 2 hours ago).
  public static func resolveAnswer(
    _ text: String,
    relativeTo now: Date = .now,
    calendar: Calendar = .current
  ) -> (date: Date, displayLabel: String, wasParsed: Bool) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
      return (now, "Just now", true)
    }
    let lower = normalize(trimmed)

    switch lower {
    case "just now", "now", "right now":
      return (now, "Just now", true)
    case "breakfast":
      let m = meal(hour: 8, minute: 0, label: "Breakfast", now: now, calendar: calendar, clear: true)
      return (m.date, m.displayLabel, true)
    case "brunch":
      let m = meal(hour: 10, minute: 30, label: "Brunch", now: now, calendar: calendar, clear: true)
      return (m.date, m.displayLabel, true)
    case "lunch":
      let m = meal(
        hour: 12, minute: 30, label: "Lunch", now: now, calendar: calendar, clear: true)
      return (m.date, m.displayLabel, true)
    case "dinner", "supper":
      let m = meal(hour: 18, minute: 30, label: "Dinner", now: now, calendar: calendar, clear: true)
      return (m.date, m.displayLabel, true)
    case "this afternoon":
      let m = meal(
        hour: 15, minute: 0, label: "This afternoon", now: now, calendar: calendar, clear: true)
      return (m.date, m.displayLabel, true)
    default:
      break
    }

    let relative = RelativeTimeParser.parse(trimmed, relativeTo: now, calendar: calendar)
    return (relative.date, trimmed, relative.wasParsed)
  }

  // MARK: - Private

  private static func normalize(_ text: String) -> String {
    text.trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
      .replacingOccurrences(of: "’", with: "'")
  }

  private static func matchesJustAte(_ lower: String) -> Bool {
    let needles = [
      "just ate", "just finished", "just had", "just got done", "just done eating",
      "i just ate", "i just finished", "i just had", "just finished eating",
      "finished just now", "ate just now", "had just now", "just now ate",
      "just grabbed", "just polished off",
    ]
    return needles.contains { lower.contains($0) }
  }

  private static func matchesMeal(_ lower: String, keys: [String]) -> Bool {
    keys.contains { lower.contains($0) }
  }

  private static func containsRelativeAgo(_ lower: String) -> Bool {
    lower.contains(" ago")
      || lower.contains("an hour ago")
      || lower.contains("a minute ago")
      || lower == "yesterday"
  }

  private static func looksLikeStandaloneTimePhrase(_ lower: String) -> Bool {
    let standalone = [
      "just now", "now", "right now", "yesterday", "an hour ago", "a hour ago",
      "1 hour ago", "one hour ago", "a minute ago",
    ]
    if standalone.contains(lower) { return true }
    // "2 hours ago", "30 minutes ago"
    let pattern = #"^\d+\s+(hour|hours|minute|minutes|day|days)(\s+ago)?$"#
    return lower.range(of: pattern, options: .regularExpression) != nil
  }

  private static func relativeDisplay(for lower: String) -> String? {
    if lower.contains("hour") && lower.contains("ago") { return "Earlier today" }
    if lower.contains("minute") && lower.contains("ago") { return "Just now" }
    if lower == "yesterday" || lower.contains("yesterday") { return "Yesterday" }
    return nil
  }

  private static func meal(
    hour: Int,
    minute: Int,
    label: String,
    now: Date,
    calendar: Calendar,
    clear: Bool
  ) -> MealTimeInference {
    var components = calendar.dateComponents([.year, .month, .day], from: now)
    components.hour = hour
    components.minute = minute
    components.second = 0
    let date = calendar.date(from: components) ?? now
    return MealTimeInference(date: date, displayLabel: label, isClear: clear)
  }
}
