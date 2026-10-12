import XCTest
@testable import FleetCore

final class TabStripRulesTests: XCTestCase {
  func testLabelNumbersTheTabAndFallsBackToBlink() {
    XCTAssertEqual(TabStripRules.label(title: "nate@ada:~/code", index: 0), "1  nate@ada:~/code")
    XCTAssertEqual(TabStripRules.label(title: nil, index: 2), "3  blink")
    XCTAssertEqual(TabStripRules.label(title: "   ", index: 0), "1  blink")
  }

  func testLeadingStatusMarksAreDropped() {
    XCTAssertEqual(TabStripRules.label(title: "✳ App refactoring", index: 1), "2  App refactoring")
    XCTAssertEqual(TabStripRules.label(title: "⠂ Running tests", index: 0), "1  Running tests")
    XCTAssertEqual(TabStripRules.label(title: "~/code/blink", index: 0), "1  ~/code/blink")
    XCTAssertEqual(TabStripRules.label(title: "✳", index: 0), "1  ✳")
  }

  func testLongTitlesAreCut() {
    let label = TabStripRules.label(title: String(repeating: "a", count: 80), index: 0)
    XCTAssertEqual(label.count, 3 + TabStripRules.maxLabelLength)
    XCTAssertTrue(label.hasSuffix("…"))
  }

  func testBarShowsOnlyWhenUseful() {
    XCTAssertTrue(TabStripRules.isVisible(enabled: true, sessions: 2, snipsInputActive: false))
    XCTAssertFalse(TabStripRules.isVisible(enabled: true, sessions: 1, snipsInputActive: false))
    XCTAssertFalse(TabStripRules.isVisible(enabled: false, sessions: 3, snipsInputActive: false))
    XCTAssertFalse(TabStripRules.isVisible(enabled: true, sessions: 3, snipsInputActive: true))
  }

  func testTerminalStartsBelowTheBar() {
    XCTAssertEqual(TabStripRules.reservedTop(visible: true, safeAreaTop: 59), 87)
    XCTAssertEqual(TabStripRules.reservedTop(visible: true, safeAreaTop: 0), 28)
    XCTAssertEqual(TabStripRules.reservedTop(visible: false, safeAreaTop: 59), 0)
  }
}
