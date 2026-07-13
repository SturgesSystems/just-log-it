import Foundation

/// Parses casual relative time phrases into absolute dates for `consumedAt`.
public enum RelativeTimeParser: Sendable {
  public struct ParseResult: Equatable, Sendable {
    public let date: Date
    /// `false` when the text was not recognized and the date fell back to `relativeTo`.
    public let wasParsed: Bool

    public init(date: Date, wasParsed: Bool) {
      self.date = date
      self.wasParsed = wasParsed
    }
  }

  /// Interprets freeform text such as "just now", "an hour ago", "2 hours ago", or "yesterday".
  /// Empty / whitespace-only text is treated as "now" and considered parsed.
  public static func parse(
    _ text: String,
    relativeTo now: Date = .now,
    calendar: Calendar = .current
  ) -> ParseResult {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
      return ParseResult(date: now, wasParsed: true)
    }

    let lower = trimmed.lowercased()
      .replacingOccurrences(of: "’", with: "'")

    if lower == "just now" || lower == "now" || lower == "right now" {
      return ParseResult(date: now, wasParsed: true)
    }

    if lower == "yesterday" {
      let date = calendar.date(byAdding: .day, value: -1, to: now) ?? now
      return ParseResult(date: date, wasParsed: true)
    }

    if lower == "an hour ago" || lower == "a hour ago" || lower == "1 hour ago"
      || lower == "one hour ago"
    {
      let date = calendar.date(byAdding: .hour, value: -1, to: now) ?? now
      return ParseResult(date: date, wasParsed: true)
    }

    if lower == "a minute ago" || lower == "1 minute ago" || lower == "one minute ago" {
      let date = calendar.date(byAdding: .minute, value: -1, to: now) ?? now
      return ParseResult(date: date, wasParsed: true)
    }

    if let hours = matchCount(in: lower, singular: "hour", plural: "hours") {
      let date = calendar.date(byAdding: .hour, value: -hours, to: now) ?? now
      return ParseResult(date: date, wasParsed: true)
    }

    if let minutes = matchCount(in: lower, singular: "minute", plural: "minutes") {
      let date = calendar.date(byAdding: .minute, value: -minutes, to: now) ?? now
      return ParseResult(date: date, wasParsed: true)
    }

    if let days = matchCount(in: lower, singular: "day", plural: "days") {
      let date = calendar.date(byAdding: .day, value: -days, to: now) ?? now
      return ParseResult(date: date, wasParsed: true)
    }

    return ParseResult(date: now, wasParsed: false)
  }

  /// Matches "N unit(s) ago" or "N unit(s)".
  private static func matchCount(in lower: String, singular: String, plural: String) -> Int? {
    let patterns = [
      "^(\\d+)\\s+\(plural)\\s+ago$",
      "^(\\d+)\\s+\(singular)\\s+ago$",
      "^(\\d+)\\s+\(plural)$",
      "^(\\d+)\\s+\(singular)$",
    ]
    for pattern in patterns {
      guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
      let range = NSRange(lower.startIndex..., in: lower)
      guard let match = regex.firstMatch(in: lower, range: range),
        match.numberOfRanges >= 2,
        let countRange = Range(match.range(at: 1), in: lower),
        let value = Int(lower[countRange]), value >= 0
      else { continue }
      return value
    }
    return nil
  }
}
