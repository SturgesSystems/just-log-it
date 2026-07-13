import Foundation
import XCTest

@testable import JustLogIt

final class AppConfigurationTests: XCTestCase {
  func testProxyTakesPrecedenceInProviderDescription() {
    let configuration = AppConfiguration(
      proxyBaseURL: URL(string: "https://foods.example.com"),
      debugUSDAAPIKey: "development-key"
    )

    XCTAssertEqual(configuration.providerDescription, "Privacy proxy")
  }

  func testMissingConfigurationIsReported() {
    let configuration = AppConfiguration(proxyBaseURL: nil, debugUSDAAPIKey: nil)

    XCTAssertEqual(configuration.providerDescription, "Not configured")
  }

  func testAcceptsRootHTTPSProxyWithMatchingPin() {
    let url = AppConfiguration.validatedProxyURL(
      "https://foods.example.org/",
      allowedHost: "foods.example.org",
      requirePinnedHost: true
    )

    XCTAssertEqual(url?.absoluteString, "https://foods.example.org/")
  }

  func testRejectsUnsafeOrAmbiguousProxyURLs() {
    for value in [
      "http://foods.example.org",
      "//foods.example.org",
      "https://user@foods.example.org",
      "https://foods.example.org:8443",
      "https://foods.example.org/api",
      "https://bad..example.org",
      "https://-bad.example.org",
      "https://foods.example.org?mode=test",
      "https://foods.example.org#fragment",
    ] {
      XCTAssertNil(
        AppConfiguration.validatedProxyURL(
          value,
          allowedHost: "foods.example.org",
          requirePinnedHost: true
        ),
        "Expected rejection for \(value)"
      )
    }
  }

  func testReleaseStyleValidationRequiresExactHostPin() {
    XCTAssertNil(
      AppConfiguration.validatedProxyURL(
        "https://foods.example.org",
        allowedHost: nil,
        requirePinnedHost: true
      )
    )
    XCTAssertNil(
      AppConfiguration.validatedProxyURL(
        "https://foods.example.org",
        allowedHost: "other.example.org",
        requirePinnedHost: true
      )
    )
  }

  #if DEBUG
    func testDebugKeyIsReportedInDebugBuild() {
      let configuration = AppConfiguration(proxyBaseURL: nil, debugUSDAAPIKey: "development-key")

      XCTAssertEqual(configuration.providerDescription, "Direct USDA (Debug)")
    }
  #endif
}
