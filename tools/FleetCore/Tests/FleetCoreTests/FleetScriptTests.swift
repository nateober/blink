import XCTest
@testable import FleetCore

final class FleetScriptTests: XCTestCase {
  func testBuildsBase64Pipeline() {
    // "echo hi\n" → base64 "ZWNobyBoaQo="
    XCTAssertEqual(
      FleetScript.command(script: "echo hi\n", interpreter: "bash"),
      "printf %s 'ZWNobyBoaQo=' | base64 --decode | bash"
    )
  }
  func testInterpreterIsHonored() {
    XCTAssertTrue(FleetScript.command(script: "print(1)", interpreter: "python3").hasSuffix("| python3"))
  }
  func testArbitraryContentStaysSafelyBase64Encoded() {
    // Quotes, newlines, and shell metacharacters must not escape the single-quoted arg —
    // base64 output is only [A-Za-z0-9+/=], so the command shape is always safe.
    let nasty = "echo 'a'; rm -rf /\n$(whoami)\n\"x\"\n"
    let cmd = FleetScript.command(script: nasty, interpreter: "bash")
    let b64 = cmd.dropFirst("printf %s '".count).prefix { $0 != "'" }
    XCTAssertTrue(b64.allSatisfy { "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=".contains($0) })
    XCTAssertEqual(String(decoding: Data(base64Encoded: String(b64))!, as: UTF8.self), nasty)
  }
}
