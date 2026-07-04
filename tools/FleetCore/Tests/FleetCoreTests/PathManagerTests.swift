import XCTest
@testable import FleetCore

final class PathManagerTests: XCTestCase {
  func testPrependAddsDirsInFront() {
    XCTAssertEqual(PathManager.prepend(["/a", "/b"], to: "/x:/y"), "/a:/b:/x:/y")
  }
  func testPrependDoesNotDuplicateExisting() {
    XCTAssertEqual(PathManager.prepend(["/a", "/b"], to: "/b:/c"), "/a:/b:/c")
  }
  func testPrependDedupesWithinNewDirs() {
    XCTAssertEqual(PathManager.prepend(["/a", "/a"], to: "/c"), "/a:/c")
  }
  func testPrependOntoEmptyPath() {
    XCTAssertEqual(PathManager.prepend(["/a"], to: ""), "/a")
  }
  func testPrependEmptyDirsLeavesPathUnchanged() {
    XCTAssertEqual(PathManager.prepend([], to: "/x:/y"), "/x:/y")
  }
  func testRemoveDropsDir() {
    XCTAssertEqual(PathManager.remove("/b", from: "/a:/b:/c"), "/a:/c")
  }
  func testRemoveMissingDirIsNoop() {
    XCTAssertEqual(PathManager.remove("/z", from: "/a:/b"), "/a:/b")
  }
  func testRemoveOnlyEntryYieldsEmpty() {
    XCTAssertEqual(PathManager.remove("/a", from: "/a"), "")
  }
}
