import XCTest

@testable import JustLogIt

@MainActor
final class VoiceInputControllerTests: XCTestCase {
  func testActiveSessionIncludesPreparationListeningAndStopping() {
    XCTAssertFalse(VoiceInputController.State.idle.hasActiveSession)
    XCTAssertTrue(VoiceInputController.State.preparing.hasActiveSession)
    XCTAssertTrue(VoiceInputController.State.listening.hasActiveSession)
    XCTAssertTrue(VoiceInputController.State.stopping.hasActiveSession)
  }

  func testProgressiveSegmentsAreJoinedWithoutDamagingExistingWhitespace() {
    XCTAssertEqual(VoiceInputController.join("two scrambled", "eggs"), "two scrambled eggs")
    XCTAssertEqual(VoiceInputController.join("two scrambled ", "eggs"), "two scrambled eggs")
    XCTAssertEqual(VoiceInputController.join("", "two eggs"), "two eggs")
  }
}
