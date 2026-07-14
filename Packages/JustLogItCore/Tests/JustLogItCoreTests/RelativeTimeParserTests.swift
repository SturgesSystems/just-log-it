import Foundation
import Testing

@testable import JustLogItCore

@Test func relativeTimeParserJustNow() {
  let now = Date(timeIntervalSince1970: 1_700_000_000)
  let result = RelativeTimeParser.parse("Just now", relativeTo: now)
  #expect(result.wasParsed)
  #expect(result.date == now)
}

@Test func relativeTimeParserEmptyIsNow() {
  let now = Date(timeIntervalSince1970: 1_700_000_000)
  let result = RelativeTimeParser.parse("  ", relativeTo: now)
  #expect(result.wasParsed)
  #expect(result.date == now)
}

@Test func relativeTimeParserAnHourAgo() {
  let now = Date(timeIntervalSince1970: 1_700_000_000)
  let calendar = Calendar(identifier: .gregorian)
  let result = RelativeTimeParser.parse("An hour ago", relativeTo: now, calendar: calendar)
  #expect(result.wasParsed)
  let expected = calendar.date(byAdding: .hour, value: -1, to: now)
  #expect(result.date == expected)
}

@Test func relativeTimeParserTwoHoursAgo() {
  let now = Date(timeIntervalSince1970: 1_700_000_000)
  let calendar = Calendar(identifier: .gregorian)
  let result = RelativeTimeParser.parse("2 hours ago", relativeTo: now, calendar: calendar)
  #expect(result.wasParsed)
  let expected = calendar.date(byAdding: .hour, value: -2, to: now)
  #expect(result.date == expected)
}

@Test func relativeTimeParserMinutesDaysAndBareCounts() {
  let now = Date(timeIntervalSince1970: 1_700_000_000)
  let cal = Calendar(identifier: .gregorian)
  #expect(
    RelativeTimeParser.parse("30 minutes ago", relativeTo: now, calendar: cal).date
      == cal.date(byAdding: .minute, value: -30, to: now))
  #expect(
    RelativeTimeParser.parse("3 days ago", relativeTo: now, calendar: cal).date
      == cal.date(byAdding: .day, value: -3, to: now))
  // "N unit" without "ago" still parses; extra spacing is tolerated.
  #expect(
    RelativeTimeParser.parse("2   hours", relativeTo: now, calendar: cal).date
      == cal.date(byAdding: .hour, value: -2, to: now))
  // Non-integer counts are not recognized (falls back to now).
  #expect(!RelativeTimeParser.parse("2.5 hours ago", relativeTo: now).wasParsed)
}

@Test func relativeTimeParserYesterday() {
  let now = Date(timeIntervalSince1970: 1_700_000_000)
  let calendar = Calendar(identifier: .gregorian)
  let result = RelativeTimeParser.parse("yesterday", relativeTo: now, calendar: calendar)
  #expect(result.wasParsed)
  let expected = calendar.date(byAdding: .day, value: -1, to: now)
  #expect(result.date == expected)
}

@Test func relativeTimeParserUnparsedFallsBackToNow() {
  let now = Date(timeIntervalSince1970: 1_700_000_000)
  let result = RelativeTimeParser.parse("last Tuesday after yoga", relativeTo: now)
  #expect(!result.wasParsed)
  #expect(result.date == now)
}

@Test func mealTimeInfersJustAteAsClearNow() {
  let now = Date(timeIntervalSince1970: 1_700_000_000)
  let inference = MealTimeInferenceService.infer(
    from: "I just finished a Big Mac", relativeTo: now)
  #expect(inference.isClear)
  #expect(inference.displayLabel == "Just now")
  #expect(inference.date == now)
}

@Test func mealTimeInfersBreakfastAsClearMorningHour() {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(secondsFromGMT: 0)!
  // 2023-11-14 15:00 UTC
  let now = Date(timeIntervalSince1970: 1_700_000_000)
  let inference = MealTimeInferenceService.infer(
    from: "For breakfast I had eggs", relativeTo: now, calendar: calendar)
  #expect(inference.isClear)
  #expect(inference.displayLabel == "Breakfast")
  let hour = calendar.component(.hour, from: inference.date)
  #expect(hour == 8)
}

@Test func mealTimeInfersDinnerFromTonight() {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(secondsFromGMT: 0)!
  let now = Date(timeIntervalSince1970: 1_700_000_000)
  let inference = MealTimeInferenceService.infer(
    from: "tonight I had pizza", relativeTo: now, calendar: calendar)
  #expect(inference.isClear)
  #expect(inference.displayLabel == "Dinner")
  #expect(calendar.component(.hour, from: inference.date) == 18)
}

@Test func mealTimeUnclearFoodOnlyDoesNotSkipAsk() {
  let now = Date(timeIntervalSince1970: 1_700_000_000)
  let inference = MealTimeInferenceService.infer(from: "Big Mac and fries", relativeTo: now)
  #expect(!inference.isClear)
}

@Test func mealTimeResolveAnswerBreakfastChip() {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(secondsFromGMT: 0)!
  let now = Date(timeIntervalSince1970: 1_700_000_000)
  let resolved = MealTimeInferenceService.resolveAnswer(
    "Breakfast", relativeTo: now, calendar: calendar)
  #expect(resolved.wasParsed)
  #expect(resolved.displayLabel == "Breakfast")
  #expect(calendar.component(.hour, from: resolved.date) == 8)
}
