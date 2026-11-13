import XCTest
@testable import FleetCore

final class PermissionReplyTests: XCTestCase {
  func testButtonsBecomeTheDecideCommand() {
    let allow = PermissionReply.command(action: PermissionReply.approveAction, request: "00112233aabbccdd")
    XCTAssertEqual(allow?.hasSuffix(" blink-decide 00112233aabbccdd allow"), true)
    let deny = PermissionReply.command(action: PermissionReply.denyAction, request: "00112233aabbccdd")
    XCTAssertEqual(deny?.hasSuffix(" blink-decide 00112233aabbccdd deny"), true)
  }

  func testNothingRunsForATapOrAnIdThatIsNotOurs() {
    XCTAssertNil(PermissionReply.command(action: "com.apple.UNNotificationDefaultActionIdentifier", request: "00112233aabbccdd"))
    XCTAssertNil(PermissionReply.command(action: PermissionReply.approveAction, request: nil))
    XCTAssertNil(PermissionReply.command(action: PermissionReply.approveAction, request: "00112233aabbccd"))
    XCTAssertNil(PermissionReply.command(action: PermissionReply.approveAction, request: "0011; rm -rf ~ #"))
    XCTAssertNil(PermissionReply.command(action: PermissionReply.approveAction, request: "00112233AABBCCDD"))
    XCTAssertNil(PermissionReply.command(action: PermissionReply.approveAction, request: "００１１２２３３ａａｂｂｃｃｄｄ"))
  }

  func testOpenInClaudeOnlyOpensAClaudeSession() {
    let open = PermissionReply.openAction
    XCTAssertEqual(PermissionReply.remoteURL(action: open, address: "https://claude.ai/code/session_01AbC-d_9"),
                   "https://claude.ai/code/session_01AbC-d_9")
    XCTAssertNil(PermissionReply.remoteURL(action: PermissionReply.approveAction, address: "https://claude.ai/code/session_01"))
    XCTAssertNil(PermissionReply.remoteURL(action: open, address: nil))
    for bad in ["https://claude.ai/code/session_", "https://claude.ai.evil.example/code/session_01",
                "https://claude.ai/code/session_01?next=https://evil.example", "http://claude.ai/code/session_01",
                "https://claude.ai/code/session_01/../../x", "blinkshell://run?cmd=x"] {
      XCTAssertNil(PermissionReply.remoteURL(action: open, address: bad), bad)
    }
  }

  func testOutcomes() {
    XCTAssertEqual(PermissionReply.outcome(stdout: "ok\n", exitCode: 0, stderr: ""), .sent)
    XCTAssertEqual(PermissionReply.outcome(stdout: "expired\n", exitCode: 3, stderr: ""), .expired)
    XCTAssertEqual(PermissionReply.outcome(stdout: "", exitCode: 127, stderr: "zsh:1: command not found: blink-decide"),
                   .failed("the host has no blink-decide; run install-agent-loop.sh there"))
    XCTAssertEqual(PermissionReply.outcome(stdout: "ok", exitCode: nil, stderr: ""), .failed("the host did not confirm"))
  }

  func testOnlyAFailureIsReported() {
    XCTAssertNil(PermissionReply.failureNotice(session: "work", action: PermissionReply.approveAction, outcome: .sent))
    let expired = PermissionReply.failureNotice(session: "work", action: PermissionReply.approveAction, outcome: .expired)
    XCTAssertEqual(expired?.title, "work: already answered")
    let failed = PermissionReply.failureNotice(session: "work", action: PermissionReply.denyAction, outcome: .failed("timed out after 20s"))
    XCTAssertEqual(failed?.title, "work: Deny did not go through")
    XCTAssertEqual(failed?.body, "timed out after 20s. Tap to open the session.")
  }
}

final class DiagUploadTests: XCTestCase {
  func testNamesSortByTimeAndAreRecognised() {
    let a = DiagUpload.fileName(kind: .metrics, at: Date(timeIntervalSince1970: 1_794_600_000))
    let b = DiagUpload.fileName(kind: .diagnostics, at: Date(timeIntervalSince1970: 1_794_600_060), serial: 1)
    XCTAssertEqual(a, "blink-20261113-200000-0-metrics.json")
    XCTAssertLessThan(a, b)
    XCTAssertTrue(DiagUpload.isReportName(a))
    XCTAssertTrue(DiagUpload.isReportName(b))
  }

  func testOtherNamesNeverReachACommandLine() {
    for name in ["x.json", "blink-a'; rm -rf ~;'-metrics.json", "blink-../../x-metrics.json", "blink-1-metrics.txt", "blink-20261113-000000-0-other.json"] {
      XCTAssertFalse(DiagUpload.isReportName(name), name)
      XCTAssertEqual(DiagUpload.commands(base64: "QUJD", fileName: name), [])
    }
  }

  func testCommandsWriteIntoTheDiagDirectoryAndConfirm() {
    let name = "blink-20261113-203320-0-metrics.json"
    let big = String(repeating: "A", count: PasteUpload.chunkSize + 10)
    let commands = DiagUpload.commands(base64: big, fileName: name)
    XCTAssertEqual(commands.count, 2)
    XCTAssertTrue(commands[0].hasPrefix("mkdir -p \"$HOME/Scratch/blink-diag\" && find \"$HOME/Scratch/blink-diag\" -type f -mtime +60 -delete; "))
    XCTAssertTrue(commands[1].hasSuffix("printf %s \"$HOME/Scratch/blink-diag\"/\(name)"))
    XCTAssertTrue(DiagUpload.confirmed(stdout: "/Users/n/Scratch/blink-diag/\(name)", fileName: name))
    XCTAssertFalse(DiagUpload.confirmed(stdout: "", fileName: name))
  }

  func testPasteCommandsAreUnchanged() {
    let c = PasteUpload.commands(base64: "QUJD", fileName: "blink-20261113-100530.jpg")
    XCTAssertEqual(c, ["mkdir -p \"$HOME/Scratch/blink-paste\" && find \"$HOME/Scratch/blink-paste\" -type f -mtime +7 -delete; : > \"$HOME/Scratch/blink-paste\"/blink-20261113-100530.jpg.b64 && printf %s 'QUJD' >> \"$HOME/Scratch/blink-paste\"/blink-20261113-100530.jpg.b64 && base64 --decode < \"$HOME/Scratch/blink-paste\"/blink-20261113-100530.jpg.b64 > \"$HOME/Scratch/blink-paste\"/blink-20261113-100530.jpg && rm -f \"$HOME/Scratch/blink-paste\"/blink-20261113-100530.jpg.b64 && printf %s \"$HOME/Scratch/blink-paste\"/blink-20261113-100530.jpg"])
  }

  func testOnlyTheOldestBeyondTheLimitAreDropped() {
    let names = (0..<45).map { DiagUpload.fileName(kind: .metrics, at: Date(timeIntervalSince1970: 1_794_600_000 + Double($0) * 60)) }
    let drop = DiagUpload.overflow(names.shuffled() + ["notes.txt"])
    XCTAssertEqual(drop, Array(names.prefix(5)))
    XCTAssertEqual(DiagUpload.overflow(Array(names.prefix(3))), [])
  }
}
