import XCTest
@testable import FleetCore

final class MountManagerTests: XCTestCase {
  func testMountPointAndPathFragment() {
    XCTAssertEqual(MountManager.mountPoint(home: "/h", name: "notes"), "/h/mnt/notes")
    XCTAssertEqual(MountManager.pathFragment(home: "/h", name: "notes"), "/h/mnt/notes/bin")
  }

  func testSanitizeNameStripsSeparatorsAndDots() {
    XCTAssertEqual(MountManager.sanitized(name: "My Docs/secret"), "My Docs-secret")
    XCTAssertEqual(MountManager.sanitized(name: "../etc"), "etc")
    XCTAssertEqual(MountManager.sanitized(name: "a/b\\c"), "a-b-c")
    XCTAssertEqual(MountManager.sanitized(name: ""), "mount")
  }

  func testSanitizeTrimsWhitespace() {
    XCTAssertEqual(MountManager.sanitized(name: "  notes  "), "notes")
  }

  func testUniqueNameNoCollision() {
    XCTAssertEqual(MountManager.uniqueName(base: "Docs", existing: ["Other"]), "Docs")
  }
  func testUniqueNameOneCollision() {
    XCTAssertEqual(MountManager.uniqueName(base: "Docs", existing: ["Docs"]), "Docs-2")
  }
  func testUniqueNameChain() {
    XCTAssertEqual(MountManager.uniqueName(base: "Docs", existing: ["Docs", "Docs-2", "Docs-3"]), "Docs-4")
  }
}
