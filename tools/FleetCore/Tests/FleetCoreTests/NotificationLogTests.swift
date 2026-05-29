import XCTest
@testable import FleetCore

final class NotificationLogTests: XCTestCase {
  private func tmpURL() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("notiflog-\(UUID().uuidString).plist")
  }

  private func rec(_ title: String, at t: TimeInterval) -> NotificationRecord {
    NotificationRecord(receivedAt: Date(timeIntervalSince1970: t),
                       title: title, body: "b", kind: "done", host: "ada", session: nil)
  }

  func testAppendThenRecentReturnsIt() {
    let log = NotificationLog(storeURL: tmpURL())
    log.append(rec("hello", at: 100))
    let r = log.recent()
    XCTAssertEqual(r.count, 1)
    XCTAssertEqual(r.first?.title, "hello")
  }

  func testRecentIsNewestFirst() {
    let log = NotificationLog(storeURL: tmpURL())
    log.append(rec("old", at: 100))
    log.append(rec("new", at: 200))
    XCTAssertEqual(log.recent().map { $0.title }, ["new", "old"])
  }

  func testRecentRespectsLimit() {
    let log = NotificationLog(storeURL: tmpURL())
    log.append(rec("a", at: 1)); log.append(rec("b", at: 2)); log.append(rec("c", at: 3))
    XCTAssertEqual(log.recent(limit: 2).map { $0.title }, ["c", "b"])
  }

  func testCapTrimsOldest() {
    let log = NotificationLog(storeURL: tmpURL(), cap: 2)
    log.append(rec("a", at: 1)); log.append(rec("b", at: 2)); log.append(rec("c", at: 3))
    XCTAssertEqual(log.recent().map { $0.title }, ["c", "b"])
  }

  func testPersistsAcrossInstances() {
    let url = tmpURL()
    NotificationLog(storeURL: url).append(rec("persisted", at: 100))
    XCTAssertEqual(NotificationLog(storeURL: url).recent().first?.title, "persisted")
  }

  func testClearEmpties() {
    let log = NotificationLog(storeURL: tmpURL())
    log.append(rec("x", at: 1))
    log.clear()
    XCTAssertTrue(log.recent().isEmpty)
  }
}
