import XCTest
@testable import FleetCore

final class ExitTrailerTests: XCTestCase {
  func testWrapAppendsTrailer() {
    XCTAssertEqual(ExitTrailer.wrap("uptime"),
                   "{ uptime\n} </dev/null; printf '\\n__BLINK_EXIT_%d__\\n' \"$?\"")
  }

  // The wrapped command must parse and report $? under every fleet login shell, not just
  // zsh (bash and sh rejected the old `\n; }` form as a syntax error).
  func testWrapRunsUnderBashShAndZsh() throws {
    for shell in ["/bin/bash", "/bin/sh", "/bin/zsh"] {
      let out = try runShell(shell, ExitTrailer.wrap("echo hi; false"))
      let r = ExitTrailer.parse(out)
      XCTAssertEqual(r.exitCode, 1, "\(shell): \(out)")
      XCTAssertEqual(r.output.trimmingCharacters(in: .newlines), "hi", shell)
    }
  }

  // A command that reads stdin must see EOF, not wait on the channel until the timeout.
  func testWrapGivesCommandEmptyStdin() throws {
    for shell in ["/bin/bash", "/bin/sh", "/bin/zsh"] {
      let out = try runShell(shell, ExitTrailer.wrap("cat; echo done"), stdinOpen: true)
      XCTAssertEqual(ExitTrailer.parse(out).output.trimmingCharacters(in: .newlines), "done", shell)
    }
  }

  private func runShell(_ shell: String, _ command: String, stdinOpen: Bool = false) throws -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: shell)
    p.arguments = ["-c", command]
    let out = Pipe()
    p.standardOutput = out
    let input = Pipe()  // kept open: a reader would block forever without the redirect
    if stdinOpen { p.standardInput = input }
    try p.run()
    let deadline = Date().addingTimeInterval(5)
    while p.isRunning && Date() < deadline { usleep(20_000) }
    if p.isRunning { p.terminate(); XCTFail("\(shell) hung reading stdin") }
    return String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
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
