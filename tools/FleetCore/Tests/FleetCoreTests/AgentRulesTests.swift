import XCTest
@testable import FleetCore

final class AgentRulesTests: XCTestCase {
  private let claude = "ada › blink › 2.1.322 › ✳ Blink refresh bugs on restore"
  private let shell = "ada › main › zsh › nateober@ada:~/code"

  func testParsesTheTmuxTitle() {
    let t = TmuxTitle.parse(claude)
    XCTAssertEqual(t?.host, "ada")
    XCTAssertEqual(t?.session, "blink")
    XCTAssertEqual(t?.command, "2.1.322")
    XCTAssertEqual(t?.paneTitle, "✳ Blink refresh bugs on restore")
    XCTAssertNil(TmuxTitle.parse("nateober@ada:~"))
    XCTAssertNil(TmuxTitle.parse(nil))
    XCTAssertNil(TmuxTitle.parse(" ›  › zsh › x"))
  }

  func testPaneTitleMayContainTheSeparator() {
    let t = TmuxTitle.parse("max › neon starship › vim › a › b")
    XCTAssertEqual(t?.session, "neon starship")
    XCTAssertEqual(t?.paneTitle, "a › b")
  }

  func testSpotsAnAgentInFront() {
    XCTAssertEqual(TmuxTitle.parse(claude)?.isAgent, true)
    XCTAssertEqual(TmuxTitle.parse("ada › x › 2.1.322 › ⠐ Working")?.isAgent, true)
    XCTAssertEqual(TmuxTitle.parse("ada › x › codex › whatever")?.isAgent, true)
    XCTAssertEqual(TmuxTitle.parse(shell)?.isAgent, false)
    XCTAssertEqual(TmuxTitle.parse("ada › x › vim › ✳ notes.md")?.isAgent, false)
    XCTAssertEqual(TmuxTitle.parse("ada › x › 2.1.322 › plain")?.isAgent, false)
  }

  func testLabel() {
    XCTAssertEqual(TmuxTitle.parse(claude)?.label, "blink: Blink refresh bugs on restore")
    XCTAssertEqual(TmuxTitle.parse(shell)?.label, "main")
  }

  func testPushTapGoesToTheTabAlreadyAttached() {
    let route = AgentRoute.decide(host: "Ada", session: "blink", alias: "ada",
                                  titles: [nil, shell, claude])
    XCTAssertEqual(route, .focus(index: 2))
  }

  func testPushTapOpensTheSessionWhenNoTabHasIt() {
    let route = AgentRoute.decide(host: "ada", session: "neon starship", alias: "ada", titles: [shell])
    XCTAssertEqual(route, .open(command: "mosh ada -- blink-attach 6e656f6e207374617273686970"))
  }

  func testSameSessionNameOnAnotherHostIsNotAMatch() {
    let route = AgentRoute.decide(host: "max", session: "main", alias: "max", titles: [shell])
    XCTAssertEqual(route, .open(command: "mosh max -- blink-attach 6d61696e"))
  }

  func testPushTapIgnoresWhatItCannotReach() {
    XCTAssertEqual(AgentRoute.decide(host: "ada", session: "x", alias: nil, titles: []), .ignore)
    XCTAssertEqual(AgentRoute.decide(host: "ada", session: "", alias: "ada", titles: []), .ignore)
    XCTAssertEqual(AgentRoute.decide(host: "ada", session: "a\nb", alias: "ada", titles: []), .ignore)
    XCTAssertEqual(AgentRoute.decide(host: "ada", session: "x", alias: "-oProxyCommand=x", titles: []), .ignore)
    XCTAssertEqual(AgentRoute.decide(host: "ada", session: "x", alias: "a b", titles: []), .ignore)
    XCTAssertEqual(AgentRoute.decide(host: "ada", session: String(repeating: "s", count: 65), alias: "ada", titles: []), .ignore)
  }

  func testNoBannerForTheSessionOnScreen() {
    XCTAssertFalse(AgentRoute.showsBanner(host: "ada", session: "blink", frontTitle: claude, appActive: true))
    XCTAssertTrue(AgentRoute.showsBanner(host: "ada", session: "main", frontTitle: claude, appActive: true))
    XCTAssertTrue(AgentRoute.showsBanner(host: "ada", session: "blink", frontTitle: claude, appActive: false))
    XCTAssertTrue(AgentRoute.showsBanner(host: nil, session: nil, frontTitle: claude, appActive: true))
  }

  func testDictationComposesOnlyForAnAgent() {
    XCTAssertEqual(DictationTarget.choose(title: claude, promptModeForAgents: true), .compose)
    XCTAssertEqual(DictationTarget.choose(title: shell, promptModeForAgents: true), .type)
    XCTAssertEqual(DictationTarget.choose(title: claude, promptModeForAgents: false), .type)
    XCTAssertEqual(DictationTarget.choose(title: "plain", promptModeForAgents: true), .type)
  }

  func testReadsAHostsSessionList() {
    let out = "main\t3\t1\t1793620868\t-\tnateober@ada:~\n"
      + "blink\t2\t1\t1793991942\tneeds_input\t✳ Blink refresh bugs\n"
      + "bad line\n"
      + "old\t1\t0\t1793000000\tdone\t✳ Done thing\n"
    let sessions = FleetSession.parse(host: "ada", output: out)
    XCTAssertEqual(sessions.map(\.name), ["main", "blink", "old"])
    XCTAssertEqual(sessions[1].state, .needsInput)
    XCTAssertEqual(sessions[1].task, "Blink refresh bugs")
    XCTAssertEqual(sessions[0].task, "")
    XCTAssertEqual(sessions[0].windows, 3)
    XCTAssertEqual(FleetSession.sorted(sessions).map(\.name), ["blink", "old", "main"])
  }

  func testAge() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    func s(_ ago: TimeInterval) -> FleetSession {
      FleetSession(host: "a", name: "n", windows: 1, attached: 0,
                   activity: now.addingTimeInterval(-ago), state: .none, title: "")
    }
    XCTAssertEqual(s(5).age(now: now), "now")
    XCTAssertEqual(s(600).age(now: now), "10m")
    XCTAssertEqual(s(7200).age(now: now), "2h")
    XCTAssertEqual(s(200_000).age(now: now), "2d")
  }
}
