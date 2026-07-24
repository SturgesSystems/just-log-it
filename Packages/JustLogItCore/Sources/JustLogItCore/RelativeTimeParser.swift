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

  /// Interprets freeform text such as "just now", "an hour ago", "2 hours ago",
  /// "yesterday at 7:30 pm", or "8 this morning".
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

    var lower = trimmed.lowercased()
      .replacingOccurrences(of: "’", with: "'")
      .replacingOccurrences(of: #"[,.]$"#, with: "", options: .regularExpression)
    lower = lower
      .replacingOccurrences(of: "an hour and a half", with: "1.5 hours")
      .replacingOccurrences(of: "an hour-and-a-half", with: "1.5 hours")
      .replacingOccurrences(of: "half an hour", with: "0.5 hours")
      .replacingOccurrences(of: "a couple of hours", with: "2 hours")
      .replacingOccurrences(of: "a couple hours", with: "2 hours")
      .replacingOccurrences(of: " o'clock", with: "")

    if lower == "just now" || lower == "now" || lower == "right now" {
      return ParseResult(date: now, wasParsed: true)
    }

    if let named = parseNamedDay(lower, relativeTo: now, calendar: calendar) {
      return ParseResult(date: named, wasParsed: true)
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

    if let duration = parseFlexibleDuration(lower, relativeTo: now, calendar: calendar) {
      return ParseResult(date: duration, wasParsed: true)
    }

    if let clock = parseClock(lower, on: now, relativeTo: now, calendar: calendar) {
      return ParseResult(date: clock, wasParsed: true)
    }

    return ParseResult(date: now, wasParsed: false)
  }

  /// Matches "N unit(s) ago" or "N unit(s)" where N is a non-negative integer.
  private static func matchCount(in lower: String, singular: String, plural: String) -> Int? {
    var parts = lower.split(whereSeparator: \.isWhitespace).map(String.init)
    if parts.last == "ago" { parts.removeLast() }
    guard parts.count == 2, parts[1] == singular || parts[1] == plural else { return nil }
    let digits = parts[0]
    guard digits.allSatisfy({ $0.isASCII && $0.isNumber }), let value = Int(digits), value >= 0
    else { return nil }
    return value
  }

  private static func parseFlexibleDuration(
    _ lower: String,
    relativeTo now: Date,
    calendar: Calendar
  ) -> Date? {
    let aliases: [String: Double] = [
      "a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
      "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10, "half": 0.5,
      "quarter": 0.25,
    ]
    let pattern = #"^(?:about |around |roughly )?(\d+(?:\.\d+)?|a|an|one|two|three|four|five|six|seven|eight|nine|ten|half|quarter)\s+(minute|minutes|min|mins|hour|hours|hr|hrs|day|days)(?:\s+ago)?$"#
    guard let groups = captures(pattern, in: lower), groups.count == 2 else { return nil }
    let amount = Double(groups[0]) ?? aliases[groups[0]]
    guard let amount, amount >= 0 else { return nil }

    let seconds: TimeInterval
    switch groups[1] {
    case "minute", "minutes", "min", "mins": seconds = amount * 60
    case "hour", "hours", "hr", "hrs": seconds = amount * 3_600
    case "day", "days": seconds = amount * 86_400
    default: return nil
    }
    // Calendar arithmetic is preferable for whole days across daylight-saving transitions.
    if amount.rounded() == amount, groups[1] == "day" || groups[1] == "days" {
      return calendar.date(byAdding: .day, value: -Int(amount), to: now)
    }
    return now.addingTimeInterval(-seconds)
  }

  private static func parseNamedDay(
    _ lower: String,
    relativeTo now: Date,
    calendar: Calendar
  ) -> Date? {
    let presets: [(prefix: String, dayOffset: Int, defaultHour: Int?)] = [
      ("yesterday", -1, nil),
      ("last night", -1, 20),
      ("today", 0, nil),
      ("this morning", 0, 8),
      ("this afternoon", 0, 15),
      ("this evening", 0, 19),
      ("tonight", 0, 19),
    ]

    for preset in presets {
      if lower == preset.prefix {
        let day = calendar.date(byAdding: .day, value: preset.dayOffset, to: now) ?? now
        guard let hour = preset.defaultHour else { return day }
        return settingTime(hour: hour, minute: 0, on: day, calendar: calendar)
      }

      let leadingPattern = "^" + NSRegularExpression.escapedPattern(for: preset.prefix)
        + #"(?:\s+at)?\s+(.+)$"#
      if let groups = captures(leadingPattern, in: lower), let clockText = groups.first {
        let day = calendar.date(byAdding: .day, value: preset.dayOffset, to: now) ?? now
        return parseClock(clockText, on: day, relativeTo: now, calendar: calendar)
      }

      let trailingPattern = #"^(.+?)\s+"#
        + NSRegularExpression.escapedPattern(for: preset.prefix) + "$"
      if let groups = captures(trailingPattern, in: lower), let clockText = groups.first {
        let day = calendar.date(byAdding: .day, value: preset.dayOffset, to: now) ?? now
        let periodHint: String?
        switch preset.prefix {
        case "this morning": periodHint = "am"
        case "last night", "this afternoon", "this evening", "tonight": periodHint = "pm"
        default: periodHint = nil
        }
        return parseClock(
          clockText + (periodHint.map { " \($0)" } ?? ""),
          on: day,
          relativeTo: now,
          calendar: calendar
        )
      }
    }
    return nil
  }

  private static func parseClock(
    _ raw: String,
    on day: Date,
    relativeTo now: Date,
    calendar: Calendar
  ) -> Date? {
    var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    text = text.replacingOccurrences(
      of: #"^(?:at|about|around|roughly|approximately)\s+"#,
      with: "",
      options: .regularExpression
    )
    if text == "noon" { return settingTime(hour: 12, minute: 0, on: day, calendar: calendar) }
    if text == "midnight" { return settingTime(hour: 0, minute: 0, on: day, calendar: calendar) }

    let pattern = #"^(\d{1,2})(?::(\d{1,2}))?\s*(am|pm|a\.m\.|p\.m\.)?$"#
    guard let groups = captures(pattern, in: text), groups.count == 3,
      let rawHour = Int(groups[0]), let minute = Int(groups[1].isEmpty ? "0" : groups[1]),
      (0...59).contains(minute)
    else { return nil }

    let period = groups[2].replacingOccurrences(of: ".", with: "")
    if !period.isEmpty {
      guard (1...12).contains(rawHour) else { return nil }
      let hour = rawHour % 12 + (period == "pm" ? 12 : 0)
      return settingTime(hour: hour, minute: minute, on: day, calendar: calendar)
    }
    if rawHour == 0 || rawHour > 12 {
      guard (0...23).contains(rawHour) else { return nil }
      return settingTime(hour: rawHour, minute: minute, on: day, calendar: calendar)
    }

    // With no am/pm, choose the most recent plausible occurrence. This makes a bare
    // "8:30" behave naturally at both breakfast and dinner without guessing a fixed period.
    let morning = settingTime(hour: rawHour % 12, minute: minute, on: day, calendar: calendar)
    let evening = settingTime(hour: rawHour % 12 + 12, minute: minute, on: day, calendar: calendar)
    let candidates = [morning, evening].compactMap { $0 }.filter { $0 <= now }
    return candidates.max() ?? morning
  }

  private static func settingTime(
    hour: Int,
    minute: Int,
    on day: Date,
    calendar: Calendar
  ) -> Date? {
    var components = calendar.dateComponents([.year, .month, .day], from: day)
    components.hour = hour
    components.minute = minute
    components.second = 0
    return calendar.date(from: components)
  }

  /// Returns every capture group, preserving unmatched optional groups as empty strings.
  private static func captures(_ pattern: String, in text: String) -> [String]? {
    guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
    let range = NSRange(text.startIndex..., in: text)
    guard let match = expression.firstMatch(in: text, range: range), match.range == range else {
      return nil
    }
    return (1..<match.numberOfRanges).map { index in
      let range = match.range(at: index)
      guard range.location != NSNotFound, let swiftRange = Range(range, in: text) else { return "" }
      return String(text[swiftRange])
    }
  }
}
