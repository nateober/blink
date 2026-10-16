import XCTest
@testable import FleetCore

final class FleetScriptTests: XCTestCase {
  func testPassesScriptAsArgumentNotStdin() {
    // "echo hi\n" → base64 "ZWNobyBoaQo="
    XCTAssertEqual(
      FleetScript.command(script: "echo hi\n", interpreter: "bash"),
      "bash -c \"$(printf %s 'ZWNobyBoaQo=' | base64 --decode)\""
    )
  }
  func testInterpreterIsHonored() {
    XCTAssertTrue(FleetScript.command(script: "print(1)", interpreter: "python3").hasPrefix("python3 -c "))
  }

  // A line that reads stdin (cat, claude -p) must not swallow the lines after it, which is
  // what happened when the script itself was piped into the interpreter.
  func testStdinReaderDoesNotEatTheRestOfTheScript() throws {
    let cmd = ExitTrailer.wrap(FleetScript.command(script: "cat\necho second\n", interpreter: "bash"))
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/bash")
    p.arguments = ["-c", cmd]
    let out = Pipe()
    p.standardOutput = out
    try p.run()
    p.waitUntilExit()
    let r = ExitTrailer.parse(String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
    XCTAssertEqual(r.output.trimmingCharacters(in: .newlines), "second")
    XCTAssertEqual(r.exitCode, 0)
  }
  func testArbitraryContentStaysSafelyBase64Encoded() {
    // Quotes, newlines, and shell metacharacters must not escape the single-quoted arg —
    // base64 output is only [A-Za-z0-9+/=], so the command shape is always safe.
    let nasty = "echo 'a'; rm -rf /\n$(whoami)\n\"x\"\n"
    let cmd = FleetScript.command(script: nasty, interpreter: "bash")
    let b64 = cmd.dropFirst("bash -c \"$(printf %s '".count).prefix { $0 != "'" }
    XCTAssertTrue(b64.allSatisfy { "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=".contains($0) })
    XCTAssertEqual(String(decoding: Data(base64Encoded: String(b64))!, as: UTF8.self), nasty)
  }
}
