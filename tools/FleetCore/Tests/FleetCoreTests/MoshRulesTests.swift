import XCTest
@testable import FleetCore

final class MoshRulesTests: XCTestCase {
  // What mosh 1.4 printed in the simulator after its server was killed (2026-11-13).
  private let banner = Array("\u{1b}[?25l\r\u{1b}[0;1;37;44mmosh: Last contact 9 seconds ago. [To quit: Ctrl-^ .]\u{1b}[0;37;44m".utf8)
  private let tick = Array("\u{1b}[1;21H\u{1b}[0;1;37;44m3\u{1b}[1;6H\u{1b}[0m".utf8)
  private let rollover = Array("\u{1b}[1;20H\u{1b}[0;1;37;44m1:00 ago. [To quit:\u{1b}[1;40HCtrl-^ .]\u{1b}[0;37;44m      \u{1b}[1;6H\u{1b}[0m".utf8)
  private let nothing = Array("\u{1b}[0;1;37;44mmosh: Nothing received from server on UDP port 60002. [To quit: Ctrl-^ .]".utf8)
  private let screen = [UInt8](repeating: 0x41, count: 600)

  func testKindsOfOutput() {
    XCTAssertEqual(MoshLiveness.kind(of: banner), .banner)
    XCTAssertEqual(MoshLiveness.kind(of: nothing), .banner)
    XCTAssertEqual(MoshLiveness.kind(of: tick), .tick)
    XCTAssertEqual(MoshLiveness.kind(of: rollover), .tick)
    XCTAssertEqual(MoshLiveness.kind(of: screen), .other)
    XCTAssertEqual(MoshLiveness.kind(of: Array("\u{1b}[1;21Hplain".utf8)), .other)
    XCTAssertEqual(MoshLiveness.kind(of: []), .other)
  }

  /// What the app's output tap really receives (captured in the simulator, 2026-11-13): every
  /// write is wrapped in a hide-cursor and a cursor restore.
  func testKindsOfOutputAsTheAppSeesThem() {
    func bytes(_ hex: String) -> [UInt8] {
      stride(from: 0, to: hex.count, by: 2).map {
        let a = hex.index(hex.startIndex, offsetBy: $0)
        return UInt8(hex[a..<hex.index(a, offsetBy: 2)], radix: 16)!
      }
    }
    let first = bytes("1b5b3f32356c1b5b313b31481b5b303b313b33373b34346d6d6f73683a204c61737420636f6e74616374203920736563")
    let ten = bytes("1b5b3f32356c1b5b313b3230481b5b303b313b33373b34346d3130207365636f6e64732061676f2e205b546f20717569")
    let one = bytes("1b5b3f32356c1b5b313b3231481b5b303b313b33373b34346d311b5b31333b3430481b5b3f3235681b5b306d")
    let twenty = bytes("1b5b3f32356c1b5b313b3230481b5b303b313b33373b34346d32301b5b31333b3430481b5b3f3235681b5b306d")
    let prompt = bytes("1b5b3f32356c0d1b5b303b313b33316de29e9c20201b5b303b313b33366d7e1b5b306d206d6f73682073696d74657374")
    XCTAssertEqual(MoshLiveness.kind(of: first), .banner)
    XCTAssertEqual(MoshLiveness.kind(of: ten), .tick)
    XCTAssertEqual(MoshLiveness.kind(of: one), .tick)
    XCTAssertEqual(MoshLiveness.kind(of: twenty), .tick)
    XCTAssertEqual(MoshLiveness.kind(of: prompt), .other)

    var live = MoshLiveness(restored: true)
    live.saw(first, at: 0)
    live.saw(ten, at: 1)
    for s in 2...12 { live.saw(s == 11 ? twenty : one, at: Double(s)) }
    XCTAssertTrue(live.looksDead(at: 12.5))
  }

  func testBannerThatKeepsTickingIsADeadServer() {
    var live = MoshLiveness(restored: true)
    live.saw(banner, at: 100)
    for s in 1...11 { live.saw(tick, at: 100 + Double(s)) }
    XCTAssertFalse(live.looksDead(at: 111))
    live.saw(tick, at: 112)
    XCTAssertTrue(live.looksDead(at: 112.5))
  }

  func testSlowTicksAfterAMinuteStillCount() {
    var live = MoshLiveness(restored: true)
    live.saw(banner, at: 0)
    for s in stride(from: 1.0, through: 60, by: 1) { live.saw(tick, at: s) }
    live.saw(rollover, at: 61)
    live.saw(tick, at: 64)
    XCTAssertTrue(live.looksDead(at: 66))
  }

  func testBannerThatGoesAwayIsNotDead() {
    var live = MoshLiveness(restored: true)
    live.saw(banner, at: 0)
    for s in 1...8 { live.saw(tick, at: Double(s)) }
    // Contact came back: the banner stops ticking, the screen may or may not repaint.
    XCTAssertFalse(live.looksDead(at: 20))
    XCTAssertFalse(live.looksDead(at: 200))
  }

  func testTypingDuringAnOutageDoesNotHideIt() {
    var live = MoshLiveness(restored: true)
    live.saw(banner, at: 0)
    for s in 1...13 {
      live.saw(tick, at: Double(s))
      live.saw(Array("x".utf8), at: Double(s) + 0.3)
    }
    XCTAssertTrue(live.looksDead(at: 13.5))
  }

  func testAFrozenAppStartsTheCountAgain() {
    var live = MoshLiveness(restored: true)
    live.saw(banner, at: 0)
    for s in 1...10 { live.saw(tick, at: Double(s)) }
    // Ticks alone after a long gap are not an outage we saw begin.
    live.saw(tick, at: 400)
    live.saw(tick, at: 401)
    XCTAssertFalse(live.looksDead(at: 401))
    live.saw(banner, at: 402)
    for s in 1...12 { live.saw(tick, at: 402 + Double(s)) }
    XCTAssertTrue(live.looksDead(at: 414))
  }

  func testTicksWithoutABannerAreSomeProgramsBlueHeader() {
    var live = MoshLiveness(restored: true)
    for s in 0...30 { live.saw(tick, at: Double(s)) }
    XCTAssertFalse(live.looksDead(at: 30))
  }

  func testANewClientMustHearFromItsServerFirst() {
    var live = MoshLiveness(restored: false)
    live.saw([UInt8](repeating: 0x1b, count: 80), at: 0)   // its own start-up sequence
    live.saw(nothing, at: 1)
    for s in 2...20 { live.saw(tick, at: Double(s)) }
    XCTAssertFalse(live.hadContact)
    XCTAssertFalse(live.looksDead(at: 20))

    var connected = MoshLiveness(restored: false)
    connected.saw(screen, at: 0)
    XCTAssertTrue(connected.hadContact)
    connected.saw(banner, at: 50)
    for s in 1...12 { connected.saw(tick, at: 50 + Double(s)) }
    XCTAssertTrue(connected.looksDead(at: 62))
  }

  func testReconnectLandsInTheSameTmuxSession() {
    XCTAssertEqual(MoshReconnect.command(original: "mosh ada", session: "blink"),
                   "mosh ada -- tmux new-session -A -s blink")
    XCTAssertEqual(MoshReconnect.command(original: " mosh -P 2222 nate@ada ", session: "main"),
                   "mosh -P 2222 nate@ada -- tmux new-session -A -s main")
    XCTAssertEqual(MoshReconnect.command(original: "mosh ada", session: nil), "mosh ada")
  }

  func testReconnectFollowsTheSessionTheTabMovedTo() {
    XCTAssertEqual(MoshReconnect.command(original: "mosh ada -- blink-attach 6d61696e", session: "neon starship"),
                   "mosh ada -- blink-attach 6e656f6e207374617273686970")
  }

  func testReconnectFollowsItsOwnEarlierCommand() {
    XCTAssertEqual(MoshReconnect.command(original: "mosh ada -- tmux new-session -A -s blink", session: "ha"),
                   "mosh ada -- tmux new-session -A -s ha")
    XCTAssertEqual(MoshReconnect.command(original: "mosh ada -- tmux new-session -A -s blink", session: "neon starship"),
                   "mosh ada -- tmux new-session -A -s blink")
  }

  func testOnlyTheStartOfABigReadIsScanned() {
    var live = MoshLiveness(restored: false)
    live.saw(Array("abc".utf8), length: 5000, at: 0)
    XCTAssertTrue(live.hadContact)
  }

  func testReconnectLeavesOtherCommandsAlone() {
    XCTAssertEqual(MoshReconnect.command(original: "mosh ada -- htop", session: "blink"), "mosh ada -- htop")
    XCTAssertEqual(MoshReconnect.command(original: "mosh ada -- tmux -L x new -A -s repro", session: "repro"),
                   "mosh ada -- tmux -L x new -A -s repro")
    // A name that would need quoting is not put on a plain command line.
    XCTAssertEqual(MoshReconnect.command(original: "mosh ada", session: "neon starship"), "mosh ada")
    XCTAssertEqual(MoshReconnect.command(original: "mosh ada", session: "a;rm -rf x"), "mosh ada")
    XCTAssertEqual(MoshReconnect.command(original: "mosh ada", session: "-x"), "mosh ada")
    XCTAssertEqual(MoshReconnect.command(original: "ssh ada", session: "blink"), "ssh ada")
  }

  func testReconnectsAreRateLimited() {
    XCTAssertTrue(MoshReconnect.allows(lastReconnect: nil, now: 5))
    XCTAssertFalse(MoshReconnect.allows(lastReconnect: 100, now: 130))
    XCTAssertTrue(MoshReconnect.allows(lastReconnect: 100, now: 160))
  }
}
