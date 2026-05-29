import XCTest
@testable import FleetCore

final class ExitTrailerTests: XCTestCase {
  func testWrapAppendsTrailer() {
    XCTAssertEqual(ExitTrailer.wrap("uptime"),
                   "{ uptime\n; } ; printf '\\n__BLINK_EXIT_%d__\\n' \"$?\"")
  }
  func testParseSuccess() {
    let r = ExitTrailer.parse("hello\n__BLINK_EXIT_0__\n")
    XCTAssertEqual(r.output, "hello")
    XCTAssertEqual(r.exitCode, 0)
  }
  func testParseFailureCode() {
    let r = ExitTrailer.parse("boom\n__BLINK_EXIT_3__\n")
    XCTAssertEqual(r.output, "boom")
    XCTAssertEqual(r.exitCode, 3)
  }
  func testParseMultilineOutputPreserved() {
    let r = ExitTrailer.parse("a\nb\nc\n__BLINK_EXIT_0__\n")
    XCTAssertEqual(r.output, "a\nb\nc")
    XCTAssertEqual(r.exitCode, 0)
  }
  func testParseNegativeCode() {
    let r = ExitTrailer.parse("x\n__BLINK_EXIT_-1__\n")
    XCTAssertEqual(r.exitCode, -1)
  }
  func testParseMissingMarkerReturnsNilCode() {
    let r = ExitTrailer.parse("no marker here")
    XCTAssertEqual(r.output, "no marker here")
    XCTAssertNil(r.exitCode)
  }
  func testParseEmptyOutputWithMarker() {
    let r = ExitTrailer.parse("__BLINK_EXIT_0__\n")
    XCTAssertEqual(r.output, "")
    XCTAssertEqual(r.exitCode, 0)
  }

  // Output that itself contains a line identical to the trailer must not truncate at the
  // FIRST occurrence — the real trailer is the LAST marker line.
  func testParseRepeatedMarkerKeepsOutputBeforeLast() {
    let r = ExitTrailer.parse("x\n__BLINK_EXIT_5__\ny\n__BLINK_EXIT_5__\n")
    XCTAssertEqual(r.exitCode, 5)
    XCTAssertEqual(r.output, "x\n__BLINK_EXIT_5__\ny")
  }

  // CRLF transports leave a trailing \r on the marker line.
  func testParseToleratesCRLF() {
    let r = ExitTrailer.parse("hello\r\n__BLINK_EXIT_3__\r\n")
    XCTAssertEqual(r.exitCode, 3)
    XCTAssertTrue(r.output.hasPrefix("hello"))
  }

  // Trailing blank lines after the marker shouldn't defeat detection.
  func testParseToleratesTrailingBlankLines() {
    let r = ExitTrailer.parse("hello\n__BLINK_EXIT_0__\n\n\n")
    XCTAssertEqual(r.exitCode, 0)
    XCTAssertEqual(r.output, "hello")
  }
}
