import XCTest
@testable import FleetCore

final class SessionLinkTests: XCTestCase {
  private func parse(_ s: String) -> Result<SessionLink, SessionLink.ParseError> {
    SessionLink.parse(URL(string: s)!)
  }

  func testRunLinkCarriesTheDecodedCommand() throws {
    let link = try parse("blinkshell://run?cmd=ssh%20-t%20ada%20tmux%20attach%20-t%20swifty&id=swifty&sig=abc").get()
    XCTAssertEqual(link.kind, .run)
    XCTAssertEqual(link.command, "ssh -t ada tmux attach -t swifty")
    XCTAssertEqual(link.id, "swifty")
    XCTAssertEqual(link.sig, "abc")
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

  private let key = Data(repeating: 7, count: 32)
  private let otherKey = Data(repeating: 8, count: 32)

  private func signed(_ s: String, with k: Data? = nil) throws -> SessionLink {
    let url = try SessionLink.signedURL(URL(string: s)!, key: k ?? key).get()
    return try SessionLink.parse(url).get()
  }

  func testNothingRunsWhileLinkActionsAreOff() throws {
    let link = try signed("blinkshell://run?cmd=ls")
    XCTAssertEqual(SessionLinkPolicy.decide(link: link, sessionExists: false, enabled: false, signingKey: key), .refuse)
  }

  func testACommandRunsUnaskedOnlyWhenSignedWithTheUsersKey() throws {
    let good = try signed("blinkshell://run?cmd=ls")
    let otherSigner = try signed("blinkshell://run?cmd=ls", with: otherKey)
    let bare = try parse("blinkshell://host/ada").get()
    XCTAssertEqual(SessionLinkPolicy.decide(link: good, sessionExists: false, enabled: true, signingKey: key), .run)
    XCTAssertEqual(SessionLinkPolicy.decide(link: otherSigner, sessionExists: false, enabled: true, signingKey: key), .confirm)
    XCTAssertEqual(SessionLinkPolicy.decide(link: bare, sessionExists: false, enabled: true, signingKey: key), .confirm)
    XCTAssertEqual(SessionLinkPolicy.decide(link: good, sessionExists: false, enabled: true, signingKey: nil), .confirm)
  }

  // The old shared `key=` let one leaked link authorize any command. It no longer counts.
  func testTheOldKeyParameterIsNotTrusted() throws {
    let old = try parse("blinkshell://run?cmd=ls&key=K1").get()
    XCTAssertEqual(SessionLinkPolicy.decide(link: old, sessionExists: false, enabled: true, signingKey: key), .confirm)
  }

  // A signature covers the command, the host, mosh and the id: change any and it fails.
  func testASignatureOnlyCoversItsOwnLink() throws {
    let url = try SessionLink.signedURL(URL(string: "blinkshell://host/ada?cmd=tmux%20a&id=w")!, key: key).get()
    let sig = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?
      .queryItems?.first { $0.name == "sig" }?.value)
    for tampered in [
      "blinkshell://host/ada?cmd=rm%20-rf%20~&id=w&sig=\(sig)",
      "blinkshell://host/max?cmd=tmux%20a&id=w&sig=\(sig)",
      "blinkshell://host/ada?cmd=tmux%20a&id=w&mosh=1&sig=\(sig)",
      "blinkshell://host/ada?cmd=tmux%20a&id=x&sig=\(sig)",
      "blinkshell://run?cmd=ssh%20-t%20ada%20tmux%20a&id=w&sig=\(sig)",
    ] {
      let link = try parse(tampered).get()
      XCTAssertEqual(SessionLinkPolicy.decide(link: link, sessionExists: false, enabled: true, signingKey: key), .confirm, tampered)
    }
    XCTAssertEqual(SessionLinkPolicy.decide(link: try parse(url.absoluteString).get(), sessionExists: false, enabled: true, signingKey: key), .run)
  }

  func testSigningReplacesAnOldKeyOrSignature() throws {
    let url = try SessionLink.signedURL(URL(string: "blinkshell://run?cmd=ls&key=K1&sig=zz")!, key: key).get()
    let names = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.map(\.name) ?? []
    XCTAssertEqual(names.filter { $0 == "sig" }.count, 1)
    XCTAssertFalse(names.contains("key"))
  }

  func testSigningRefusesALinkThatWouldNotOpen() {
    XCTAssertEqual(SessionLink.signedURL(URL(string: "blinkshell://run")!, key: key), .failure(.missingCommand))
  }

  func testGoingBackToAnOpenSessionNeedsNoSignature() throws {
    let bare = try parse("blinkshell://run?cmd=ls&id=s1").get()
    let focus = try parse("blinkshell://focus?id=s1").get()
    XCTAssertEqual(SessionLinkPolicy.decide(link: bare, sessionExists: true, enabled: true, signingKey: key), .run)
    XCTAssertEqual(SessionLinkPolicy.decide(link: focus, sessionExists: false, enabled: true, signingKey: key), .run)
  }

  func testGeneratedKeysAreRandomAndFull() {
    let a = SessionLinkPolicy.makeKey(), b = SessionLinkPolicy.makeKey()
    XCTAssertEqual(a.count, 32)
    XCTAssertNotEqual(a, b)
  }

  // Invisible characters can make the confirmation show one command while another runs.
  func testInvisibleCharactersAreRefused() {
    for hidden in ["%E2%80%8B", "%E2%80%AE", "%EF%BB%BF", "%E2%81%A0", "%C2%AD", "%E3%85%A4"] {
      XCTAssertEqual(parse("blinkshell://run?cmd=echo%20hi\(hidden)x"), .failure(.badCommand), hidden)
    }
  }

  // Padding can push the real command out of sight in the confirmation. Only a link the
  // user signed may carry it.
  func testPaddedUnsignedCommandsAreRefused() throws {
    let padded = "blinkshell://run?cmd=ls" + String(repeating: "%20", count: 40) + "%3B%20rm%20-rf%20~"
    let wide = "blinkshell://run?cmd=ls%E2%80%83%3B%20rm%20x"  // em space
    for s in [padded, wide] {
      let link = try parse(s).get()
      XCTAssertEqual(SessionLinkPolicy.decide(link: link, sessionExists: false, enabled: true, signingKey: key), .refuseUnreadable, s)
    }
    let normal = try parse("blinkshell://run?cmd=echo%20%22a%20%20b%22").get()
    XCTAssertEqual(SessionLinkPolicy.decide(link: normal, sessionExists: false, enabled: true, signingKey: key), .confirm)
    XCTAssertEqual(SessionLinkPolicy.decide(link: try signed(padded), sessionExists: false, enabled: true, signingKey: key), .run)
  }
}
