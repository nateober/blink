import XCTest
@testable import FleetCore

final class BookmarkStoreTests: XCTestCase {
  var dir: URL!
  override func setUpWithError() throws {
    dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  }
  override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

  func testAddListResolveRoundTrip() throws {
    let store = BookmarkStore(storeURL: dir.appendingPathComponent("marks.plist"))
    let target = dir.appendingPathComponent("folderA")
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
    let data = try target.bookmarkData()
    try store.add(name: "a", bookmark: data)
    XCTAssertEqual(store.names(), ["a"])
    let resolved = try store.resolve(name: "a")
    XCTAssertEqual(resolved.url.standardizedFileURL.path, target.standardizedFileURL.path)
  }

  func testRenameAndDelete() throws {
    let store = BookmarkStore(storeURL: dir.appendingPathComponent("marks.plist"))
    let target = dir.appendingPathComponent("folderB")
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
    try store.add(name: "b", bookmark: try target.bookmarkData())
    try store.rename(from: "b", to: "bee")
    XCTAssertEqual(store.names(), ["bee"])
    try store.delete(name: "bee")
    XCTAssertEqual(store.names(), [])
  }

  func testPersistsAcrossInstances() throws {
    let url = dir.appendingPathComponent("marks.plist")
    let target = dir.appendingPathComponent("folderC")
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
    try BookmarkStore(storeURL: url).add(name: "c", bookmark: try target.bookmarkData())
    XCTAssertEqual(BookmarkStore(storeURL: url).names(), ["c"])
  }

  func testDuplicateRejected() throws {
    let store = BookmarkStore(storeURL: dir.appendingPathComponent("marks.plist"))
    let target = dir.appendingPathComponent("folderD")
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
    try store.add(name: "d", bookmark: try target.bookmarkData())
    XCTAssertThrowsError(try store.add(name: "d", bookmark: try target.bookmarkData()))
  }

  func testStaleBookmarkSurfaced() throws {
    let store = BookmarkStore(storeURL: dir.appendingPathComponent("marks.plist"))
    try store.add(name: "g", bookmark: Data([0x00, 0x01, 0x02]))  // garbage → not resolvable
    XCTAssertThrowsError(try store.resolve(name: "g"))
  }
}
