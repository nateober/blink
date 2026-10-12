import XCTest
@testable import FleetCore

final class LinkRulesTests: XCTestCase {
  func testNewestLinkComesFirstWithoutRepeats() {
    let urls = LinkPicker.choices(from: ["https://a.example/1", "https://b.example", "https://a.example/1"])
    XCTAssertEqual(urls.map(\.absoluteString), ["https://a.example/1", "https://b.example"])
  }

  func testOnlyOpenableSchemesAreOffered() {
    let urls = LinkPicker.choices(from: ["javascript:alert(1)", "file:///etc/passwd", "mailto:a@b.co", "ssh://host", "not a url"])
    XCTAssertEqual(urls.map(\.absoluteString), ["ssh://host", "mailto:a@b.co"])
  }

  func testListIsCapped() {
    let many = (1...20).map { "https://example.com/\($0)" }
    let urls = LinkPicker.choices(from: many)
    XCTAssertEqual(urls.count, LinkPicker.maxChoices)
    XCTAssertEqual(urls.first?.absoluteString, "https://example.com/20")
  }

  func testLabelDropsSchemeAndCutsTheMiddle() {
    XCTAssertEqual(LinkPicker.label(for: URL(string: "https://github.com/blinksh/blink/")!), "github.com/blinksh/blink")
    let long = URL(string: "https://github.com/blinksh/blink/pull/2297/files/a2d825af0000000000000000000000000000")!
    let label = LinkPicker.label(for: long, limit: 40)
    XCTAssertEqual(label.count, 40)
    XCTAssertTrue(label.hasPrefix("github.com/blinksh/blink"))
    XCTAssertTrue(label.contains("…"))
    XCTAssertEqual(LinkPicker.label(for: URL(string: "mailto:a@b.co")!), "mailto:a@b.co")
  }
}
