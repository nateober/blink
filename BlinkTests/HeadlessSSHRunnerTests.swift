import XCTest
@testable import Blink

/// Behavioral test for HeadlessSSHRunner. Skips unless a local SSH target is
/// available — set BLINK_TEST_KEY_PATH to an unencrypted private key whose public
/// half is authorized on `BLINK_TEST_USER@127.0.0.1` (sshd / Remote Login on).
/// Run natively (Mac Catalyst) so host loopback + filesystem are reachable.
final class HeadlessSSHRunnerTests: XCTestCase {
  func testRunEchoOverSSH() async throws {
    let env = ProcessInfo.processInfo.environment
    let keyPath = env["BLINK_TEST_KEY_PATH"] ?? "/tmp/blink_test_key"
    let user = env["BLINK_TEST_USER"] ?? NSUserName()
    try XCTSkipUnless(FileManager.default.fileExists(atPath: keyPath),
                      "no test key at \(keyPath) — skipping live SSH test")
    let pem = try String(contentsOfFile: keyPath, encoding: .utf8)
    let marker = "hello-blink-\(Int.random(in: 10000...99999))"

    let result = try await HeadlessSSHRunner.run(
      host: "127.0.0.1",
      user: user,
      port: "22",
      command: "echo \(marker)",
      privateKey: pem
    )
    XCTAssertTrue(result.stdout.contains(marker),
                  "expected stdout to contain \(marker), got: \(result.stdout)")
  }
}
