//////////////////////////////////////////////////////////////////////////////////
//
// B L I N K  —  fleet-native fork
//
// App Intents / Shortcuts: run a command on a configured Blink host over SSH and
// return its output — without opening the terminal. Fits Nate's `ssh <host> claude -p`
// habit: a Shortcut/Siri phrase fires the command and hands back the result. Host
// user/hostname/key are resolved from Blink's existing host config (BKHosts/BKPubKey),
// which syncs via iCloud, so only `host` + `command` are needed.
//
// Blink is free software under the GNU GPL v3; see <http://www.github.com/blinksh/blink>.
//
//////////////////////////////////////////////////////////////////////////////////

import AppIntents
import Foundation
import BlinkConfig

@available(iOS 16.0, *)
enum FleetIntentError: Error, CustomLocalizedStringResourceConvertible {
  case unknownHost(String)
  case noOutput
  var localizedStringResource: LocalizedStringResource {
    switch self {
    case .unknownHost(let h): return "No Blink host named “\(h)”. Add it in Blink (config → Hosts) first."
    case .noOutput: return "The command produced no output."
    }
  }
}

@available(iOS 16.0, *)
struct RunFleetCommandIntent: AppIntent {
  static var title: LocalizedStringResource = "Run Fleet Command"
  static var description = IntentDescription(
    "Run a command on a configured Blink host over SSH and return its output."
  )
  // Runs the SSH work in-process (needs the app), not in a lightweight extension.
  static var openAppWhenRun: Bool = false

  @Parameter(title: "Host", description: "A host configured in Blink (e.g. ada).")
  var host: String

  @Parameter(title: "Command", description: "The command to run on the host.")
  var command: String

  static var parameterSummary: some ParameterSummary {
    Summary("Run \(\.$command) on \(\.$host)")
  }

  @MainActor
  func perform() async throws -> some IntentResult & ReturnsValue<String> {
    guard let h = BKHosts.withHost(host) else {
      throw FleetIntentError.unknownHost(host)
    }
    let user = (h.user?.isEmpty == false) ? h.user! : NSUserName()
    let hostName = (h.hostName?.isEmpty == false) ? h.hostName! : host
    var pem: String? = nil
    if let keyName = h.key, let card = BKPubKey.withID(keyName) {
      pem = card.loadPrivateKey()
    }
    // Also honor the host's stored password (keychain via passwordRef) — a host may
    // use password auth, key auth, or both. HeadlessSSHRunner tries whatever is given.
    let password = h.password
    let result = try await HeadlessSSHRunner.run(
      host: hostName, user: user, command: command, privateKey: pem, password: password
    )
    return .result(value: result.stdout)
  }
}

@available(iOS 16.0, *)
struct BlinkFleetShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: RunFleetCommandIntent(),
      phrases: [
        "Run a command on a host with \(.applicationName)",
        "Ask my fleet with \(.applicationName)"
      ],
      shortTitle: "Run Fleet Command",
      systemImageName: "terminal"
    )
  }
}
