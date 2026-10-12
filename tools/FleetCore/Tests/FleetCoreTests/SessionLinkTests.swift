import XCTest
@testable import FleetCore

final class SessionLinkTests: XCTestCase {
  private func parse(_ s: String) -> Result<SessionLink, SessionLink.ParseError> {
    SessionLink.parse(URL(string: s)!)
  }

  func testRunLinkCarriesTheDecodedCommand() throws {
    let link = try parse("blinkshell://run?cmd=ssh%20-t%20ada%20tmux%20attach%20-t%20swifty&id=swifty&key=K1").get()
    XCTAssertEqual(link.kind, .run)
    XCTAssertEqual(link.command, "ssh -t ada tmux attach -t swifty")
    XCTAssertEqual(link.id, "swifty")
    XCTAssertEqual(link.key, "K1")
  }

  func testRunNeedsACommand() {
    XCTAssertEqual(parse("blinkshell://run"), .failure(.missingCommand))
    XCTAssertEqual(parse("blinkshell://run?cmd=%20%20"), .failure(.missingCommand))
  }

  func testLineBreaksAndControlCharactersAreRefused() {
    XCTAssertEqual(parse("blinkshell://run?cmd=echo%20hi%0Arm%20x"), .failure(.badCommand))
    XCTAssertEqual(parse("blinkshell://run?cmd=echo%1B%5B2J"), .failure(.badCommand))
    XCTAssertEqual(parse("blinkshell://run?cmd=" + String(repeating: "a", count: 2001)), .failure(.badCommand))
  }

  func testHostLinkBuildsTheConnectCommand() throws {
    XCTAssertEqual(try parse("blinkshell://host/ada").get().command, "ssh ada")
    XCTAssertEqual(try parse("blinkshell://host/nate@ada.ober?cmd=tmux%20a").get().command, "ssh -t nate@ada.ober tmux a")
    XCTAssertEqual(try parse("blinkshell://host/ada?mosh=1").get().command, "mosh ada")
    XCTAssertEqual(try parse("blinkshell://host/ada?mosh=1&cmd=tmux%20a").get().command, "mosh ada -- tmux a")
  }

  func testHostMustBeAPlainName() {
    XCTAssertEqual(parse("blinkshell://host/-oProxyCommand=x"), .failure(.badHost))
    XCTAssertEqual(parse("blinkshell://host/a%20b"), .failure(.badHost))
    XCTAssertEqual(parse("blinkshell://host/a;rm"), .failure(.badHost))
    XCTAssertEqual(parse("blinkshell://host/"), .failure(.badHost))
  }

  func testFocusNeedsAnID() throws {
    XCTAssertEqual(try parse("blinkshell://focus?id=swifty").get().kind, .focus)
    XCTAssertEqual(parse("blinkshell://focus"), .failure(.badID))
    XCTAssertEqual(parse("blinkshell://run?cmd=ls&id=a%20b"), .failure(.badID))
  }

  func testOtherLinksAreNotOurs() {
    XCTAssertEqual(parse("blinkshell://x-success/123"), .failure(.notASessionLink))
    XCTAssertEqual(parse("ssh://ada"), .failure(.notASessionLink))
  }

  func testNothingRunsWhileLinkActionsAreOff() throws {
    let link = try parse("blinkshell://run?cmd=ls&key=K1").get()
    XCTAssertEqual(SessionLinkPolicy.decide(link: link, sessionExists: false, enabled: false, userKey: "K1"), .refuse)
  }

  func testACommandRunsUnaskedOnlyWithTheUsersKey() throws {
    let keyed = try parse("blinkshell://run?cmd=ls&key=K1").get()
    let wrong = try parse("blinkshell://run?cmd=ls&key=nope").get()
    let bare = try parse("blinkshell://host/ada").get()
    XCTAssertEqual(SessionLinkPolicy.decide(link: keyed, sessionExists: false, enabled: true, userKey: "K1"), .run)
    XCTAssertEqual(SessionLinkPolicy.decide(link: wrong, sessionExists: false, enabled: true, userKey: "K1"), .confirm)
    XCTAssertEqual(SessionLinkPolicy.decide(link: bare, sessionExists: false, enabled: true, userKey: "K1"), .confirm)
    XCTAssertEqual(SessionLinkPolicy.decide(link: keyed, sessionExists: false, enabled: true, userKey: ""), .confirm)
  }

  func testGoingBackToAnOpenSessionNeedsNoKey() throws {
    let bare = try parse("blinkshell://run?cmd=ls&id=s1").get()
    let focus = try parse("blinkshell://focus?id=s1").get()
    XCTAssertEqual(SessionLinkPolicy.decide(link: bare, sessionExists: true, enabled: true, userKey: "K1"), .run)
    XCTAssertEqual(SessionLinkPolicy.decide(link: focus, sessionExists: false, enabled: true, userKey: "K1"), .run)
  }

  func testGeneratedKeysAreUsable() {
    let key = SessionLinkPolicy.makeKey()
    XCTAssertEqual(key.count, 16)
    XCTAssertTrue(SessionLink.isToken(key, maxLength: 64))
  }
}
