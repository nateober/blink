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

  func testHeldSizeSettlesOnlyWhenActiveOrOutOfAnyWindow() {
    XCTAssertTrue(ResizeRules.settles(sceneState: true))
    XCTAssertTrue(ResizeRules.settles(sceneState: nil))
    XCTAssertFalse(ResizeRules.settles(sceneState: false))
  }

  func testHeldGridIgnoresTheScrollViewRefittingItself() {
    XCTAssertTrue(ScrollRules.reportsScroll(gridHeld: false, movedForPage: false))
    XCTAssertTrue(ScrollRules.reportsScroll(gridHeld: false, movedForPage: true))
    XCTAssertTrue(ScrollRules.reportsScroll(gridHeld: true, movedForPage: true))
    XCTAssertFalse(ScrollRules.reportsScroll(gridHeld: true, movedForPage: false))
  }

  // docs/bugs.md 2026-11-18: the iPad key toolbar never showed because nothing told the
  // app the keyboard on screen was a software one.
  func testKeyboardFrameHeightTellsSoftwareFromHardware() {
    XCTAssertEqual(KeyboardRules.isHardwareKeyboard(frameHeight: 69), true)
    XCTAssertEqual(KeyboardRules.isHardwareKeyboard(frameHeight: 55), true)
    XCTAssertEqual(KeyboardRules.isHardwareKeyboard(frameHeight: 320), false)
    XCTAssertEqual(KeyboardRules.isHardwareKeyboard(frameHeight: 471), false)
    XCTAssertNil(KeyboardRules.isHardwareKeyboard(frameHeight: 0))
  }
}
