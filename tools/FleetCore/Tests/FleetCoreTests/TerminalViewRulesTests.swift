import XCTest
@testable import FleetCore

final class TerminalViewRulesTests: XCTestCase {
  func testViewAtTheBottomFollowsNewOutput() {
    XCTAssertTrue(ScrollRules.followsNewContent(offsetY: 1200, contentHeight: 2000, viewHeight: 800, userIsScrolling: false))
    XCTAssertTrue(ScrollRules.followsNewContent(offsetY: 1199.5, contentHeight: 2000, viewHeight: 800, userIsScrolling: false))
  }

  func testScrolledUpViewStaysPut() {
    XCTAssertFalse(ScrollRules.followsNewContent(offsetY: 400, contentHeight: 2000, viewHeight: 800, userIsScrolling: false))
  }

  func testAFingerOnTheScreenIsNeverPulledDown() {
    XCTAssertFalse(ScrollRules.followsNewContent(offsetY: 1200, contentHeight: 2000, viewHeight: 800, userIsScrolling: true))
  }

  func testContentShorterThanTheViewCountsAsBottom() {
    XCTAssertTrue(ScrollRules.followsNewContent(offsetY: 0, contentHeight: 0, viewHeight: 800, userIsScrolling: false))
    XCTAssertTrue(ScrollRules.followsNewContent(offsetY: 0, contentHeight: 300, viewHeight: 800, userIsScrolling: false))
  }

  func testSizeChangesWaitWhileTheSceneIsNotActive() {
    XCTAssertTrue(ResizeRules.defersResize(sceneIsActive: false))
    XCTAssertFalse(ResizeRules.defersResize(sceneIsActive: true))
  }
}
