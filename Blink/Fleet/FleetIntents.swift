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
  case runFailed(String)
  var localizedStringResource: LocalizedStringResource {
    switch self {
    case .unknownHost(let h): return "No Blink host named “\(h)”. Add it in Blink (config → Hosts) first."
    case .noOutput: return "The command produced no output."
    // Surface the real underlying error — App Intents shows "unspecified error" for
    // any thrown error that isn't CustomLocalizedStringResourceConvertible.
    case .runFailed(let m): return "SSH failed: \(m)"
    }
  }
}

@available(iOS 16.0, *)
struct RunFleetCommandIntent: AppIntent {
  static var title: LocalizedStringResource = "Run Fleet Command"
  // Kept so existing shortcuts keep working; new ones use the general actions in BlinkIntents.swift.
  static var isDiscoverable: Bool = false
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
    .result(value: try await HostActionRunner.run(host: host, command: command, what: "command", trustNewHostKey: true))
  }
}

@available(iOS 16.0, *)
enum FleetInterpreter: String, AppEnum {
  case bash, sh, zsh, python3

  static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Interpreter")
  static var caseDisplayRepresentations: [FleetInterpreter: DisplayRepresentation] = [
    .bash: "bash", .sh: "sh", .zsh: "zsh", .python3: "python3"
  ]
}

@available(iOS 16.0, *)
struct RunFleetScriptIntent: AppIntent {
  static var title: LocalizedStringResource = "Run Fleet Script"
  // Kept so existing shortcuts keep working; new ones use the general actions in BlinkIntents.swift.
  static var isDiscoverable: Bool = false
  static var description = IntentDescription(
    "Run a multi-line bash/python script on a configured Blink host over SSH and return its output."
  )
  static var openAppWhenRun: Bool = false

  @Parameter(title: "Host", description: "A host configured in Blink (e.g. ada).")
  var host: String

  @Parameter(title: "Interpreter", description: "Interpreter to run the script with.", default: .bash)
  var interpreter: FleetInterpreter

  @Parameter(title: "Script", description: "The script to run.",
             inputOptions: String.IntentInputOptions(multiline: true))
  var script: String

  static var parameterSummary: some ParameterSummary {
    Summary("Run a \(\.$interpreter) script on \(\.$host)")
  }

  @MainActor
  func perform() async throws -> some IntentResult & ReturnsValue<String> {
    // The script is base64-encoded into a single-line pipeline (see FleetScript) so any
    // content runs verbatim with no escaping/injection.
    let command = FleetScript.command(script: script, interpreter: interpreter.rawValue)
    return .result(value: try await HostActionRunner.run(host: host, command: command, what: "script", trustNewHostKey: true))
  }
}

@available(iOS 16.0, *)
struct BlinkFleetShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: RunCommandOnHostIntent(),
      phrases: [
        "Run a command on a host with \(.applicationName)",
        "Run a command with \(.applicationName)"
      ],
      shortTitle: "Run Command on Host",
      systemImageName: "terminal"
    )
    AppShortcut(
      intent: RunScriptOnHostIntent(),
      phrases: [
        "Run a script on a host with \(.applicationName)",
        "Run a script with \(.applicationName)"
      ],
      shortTitle: "Run Script on Host",
      systemImageName: "scroll"
    )
    AppShortcut(
      intent: OpenTerminalSessionIntent(),
      phrases: [
        "Open a session with \(.applicationName)",
        "Open a terminal with \(.applicationName)"
      ],
      shortTitle: "Open Terminal Session",
      systemImageName: "macwindow"
    )
  }
}
