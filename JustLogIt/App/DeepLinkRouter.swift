import Foundation

/// Parses custom URL-scheme deep links used by Shortcuts and local testing.
///
/// Contract:
/// ```
/// justlogit://log?food=<description>&at=<ISO-8601>
/// ```
/// - `food` is required (non-empty after trim; capped at `maxFoodLength`)
/// - `at` is optional; invalid values are ignored
/// - Source is always `.shortcut`
enum DeepLinkRouter {
  static let urlScheme = "justlogit"
  static let logHost = "log"
  static let foodQueryItem = "food"
  static let atQueryItem = "at"
  static let maxFoodLength = 500

  /// Returns a `PendingFoodLog` for a recognized log URL, or `nil` if the URL is not ours / invalid.
  static func parseFoodLog(from url: URL) -> PendingFoodLog? {
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
      return nil
    }
    guard components.scheme?.lowercased() == urlScheme else { return nil }
    guard components.host?.lowercased() == logHost else { return nil }

    let items = components.queryItems ?? []
    guard let foodRaw = items.first(where: { $0.name == foodQueryItem })?.value else {
      return nil
    }
    let trimmed = foodRaw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    let food = String(trimmed.prefix(maxFoodLength))

    let consumedAt: Date?
    if let atRaw = items.first(where: { $0.name == atQueryItem })?.value {
      let atTrimmed = atRaw.trimmingCharacters(in: .whitespacesAndNewlines)
      consumedAt = atTrimmed.isEmpty ? nil : parseISO8601(atTrimmed)
    } else {
      consumedAt = nil
    }

    return PendingFoodLog(
      description: food,
      consumedAt: consumedAt,
      source: .shortcut
    )
  }

  private static func parseISO8601(_ string: String) -> Date? {
    let withFractional = ISO8601DateFormatter()
    withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = withFractional.date(from: string) { return date }

    let basic = ISO8601DateFormatter()
    basic.formatOptions = [.withInternetDateTime]
    return basic.date(from: string)
  }
}
