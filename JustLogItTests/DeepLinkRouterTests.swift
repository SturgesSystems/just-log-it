import Foundation
import XCTest

@testable import JustLogIt

final class DeepLinkRouterTests: XCTestCase {
  @MainActor
  override func tearDown() async throws {
    // `testApplyRoutesThroughAppNavigationWithShortcutSource` mutates the process-wide
    // singleton; always clear pending handoffs so later suites start clean.
    let navigation = AppNavigation.shared
    navigation.pendingFoodLog = nil
    _ = navigation.takePendingSearchQuery()
    try await super.tearDown()
  }

  func testParsesFoodAndOptionalAt() throws {
    let url = try XCTUnwrap(
      URL(string: "justlogit://log?food=two%20eggs&at=2026-07-18T12:00:00Z")
    )

    let pending = try XCTUnwrap(DeepLinkRouter.parseFoodLog(from: url))

    XCTAssertEqual(pending.description, "two eggs")
    XCTAssertEqual(pending.source, .shortcut)
    let expected = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-18T12:00:00Z"))
    XCTAssertEqual(pending.consumedAt, expected)
  }

  func testFoodOnlyOmitsConsumedAt() throws {
    let url = try XCTUnwrap(URL(string: "justlogit://log?food=oatmeal"))

    let pending = try XCTUnwrap(DeepLinkRouter.parseFoodLog(from: url))

    XCTAssertEqual(pending.description, "oatmeal")
    XCTAssertNil(pending.consumedAt)
    XCTAssertEqual(pending.source, .shortcut)
  }

  func testTrimsAndCapsFoodLength() throws {
    let long = String(repeating: "a", count: DeepLinkRouter.maxFoodLength + 40)
    var components = URLComponents()
    components.scheme = "justlogit"
    components.host = "log"
    components.queryItems = [URLQueryItem(name: "food", value: "  \(long)  ")]
    let url = try XCTUnwrap(components.url)

    let pending = try XCTUnwrap(DeepLinkRouter.parseFoodLog(from: url))

    XCTAssertEqual(pending.description.count, DeepLinkRouter.maxFoodLength)
    XCTAssertTrue(pending.description.allSatisfy { $0 == "a" })
  }

  func testRejectsWrongSchemeHostOrEmptyFood() {
    let cases = [
      "https://log?food=eggs",
      "justlogit://settings?food=eggs",
      "justlogit://log",
      "justlogit://log?food=",
      "justlogit://log?food=%20%20",
      "justlogit://log?at=2026-07-18T12:00:00Z",
    ]

    for raw in cases {
      let url = URL(string: raw)
      XCTAssertNotNil(url, raw)
      if let url {
        XCTAssertNil(DeepLinkRouter.parseFoodLog(from: url), raw)
      }
    }
  }

  func testInvalidAtIsIgnoredButFoodStillAccepted() throws {
    let url = try XCTUnwrap(
      URL(string: "justlogit://log?food=banana&at=not-a-date")
    )

    let pending = try XCTUnwrap(DeepLinkRouter.parseFoodLog(from: url))

    XCTAssertEqual(pending.description, "banana")
    XCTAssertNil(pending.consumedAt)
  }

  func testFractionalSecondsISO8601() throws {
    let url = try XCTUnwrap(
      URL(string: "justlogit://log?food=tea&at=2026-07-18T12:00:00.250Z")
    )

    let pending = try XCTUnwrap(DeepLinkRouter.parseFoodLog(from: url))
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let expected = try XCTUnwrap(formatter.date(from: "2026-07-18T12:00:00.250Z"))
    XCTAssertEqual(pending.consumedAt, expected)
  }

  func testSchemeAndHostAreCaseInsensitive() throws {
    let url = try XCTUnwrap(URL(string: "JustLogIt://LOG?food=apple"))

    let pending = try XCTUnwrap(DeepLinkRouter.parseFoodLog(from: url))
    XCTAssertEqual(pending.description, "apple")
  }

  @MainActor
  func testApplyRoutesThroughAppNavigationWithShortcutSource() throws {
    let navigation = AppNavigation.shared
    let previousTab = navigation.tab
    navigation.tab = .settings
    navigation.pendingFoodLog = nil
    defer {
      navigation.pendingFoodLog = nil
      navigation.tab = previousTab
    }

    let url = try XCTUnwrap(
      URL(string: "justlogit://log?food=two%20eggs&at=2026-07-18T12:00:00Z")
    )
    let pending = try XCTUnwrap(DeepLinkRouter.parseFoodLog(from: url))
    navigation.beginPendingFoodLog(pending)

    let installed = try XCTUnwrap(navigation.pendingFoodLog)
    XCTAssertEqual(installed.description, "two eggs")
    XCTAssertEqual(installed.source, .shortcut)
    XCTAssertEqual(navigation.tab, .log)
    let expected = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-18T12:00:00Z"))
    XCTAssertEqual(installed.consumedAt, expected)
  }
}
