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

  #if DEBUG
    func testDebugKeyIsReportedInDebugBuild() {
      let configuration = AppConfiguration(proxyBaseURL: nil, debugUSDAAPIKey: "development-key")

      XCTAssertEqual(configuration.providerDescription, "Direct USDA (Debug)")
    }
  #endif
}
