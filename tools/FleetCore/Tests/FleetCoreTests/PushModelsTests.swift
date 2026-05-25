import XCTest
@testable import FleetCore

final class PushModelsTests: XCTestCase {
  func testDecodeNeedsInputPayload() throws {
    let json = #"""
    {"aps":{"alert":{"title":"Claude needs you","body":"approve edit?"},"sound":"default"},
     "blink":{"kind":"needs_input","host":"ada","session":"abc"}}
    """#
    let p = try JSONDecoder().decode(BlinkPush.self, from: Data(json.utf8))
    XCTAssertEqual(p.blink.kind, .needsInput)
    XCTAssertEqual(p.blink.host, "ada")
    XCTAssertEqual(p.aps.alert?.title, "Claude needs you")
  }

  func testEncodeRoundTrip() throws {
    let push = BlinkPush(
      aps: .init(alert: .init(title: "T", body: "B"), sound: "default"),
      blink: .init(kind: .progress, host: "max", session: "s1")
    )
    let data = try JSONEncoder().encode(push)
    let back = try JSONDecoder().decode(BlinkPush.self, from: data)
    XCTAssertEqual(back.blink.kind, .progress)
    XCTAssertEqual(back.blink.host, "max")
  }

  func testKindRawValues() {
    XCTAssertEqual(BlinkPush.Meta.Kind.needsInput.rawValue, "needs_input")
    XCTAssertEqual(BlinkPush.Meta.Kind.done.rawValue, "done")
  }

  func testTokenStoreRoundTrip() throws {
    let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(UUID()).txt")
    defer { try? FileManager.default.removeItem(at: url) }
    let s = APNSTokenStore(fileURL: url)
    XCTAssertNil(s.load())
    s.save(hex: "deadbeef")
    XCTAssertEqual(APNSTokenStore(fileURL: url).load(), "deadbeef")
  }
}
