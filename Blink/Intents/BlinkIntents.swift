////////////////////////////////////////////////////////////////////////////////
//
// B L I N K
//
// Copyright (C) 2016-2019 Blink Mobile Shell Project
//
// This file is part of Blink.
//
// Blink is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Blink is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with Blink. If not, see <http://www.gnu.org/licenses/>.
//
// In addition, Blink is also subject to certain additional terms under
// GNU GPL version 3 section 7.
//
// You should have received a copy of these additional terms immediately
// following the terms and conditions of the GNU General Public License
// which accompanied the Blink Source Code. If not, see
// <http://www.github.com/blinksh/blink>.
//
////////////////////////////////////////////////////////////////////////////////


import AppIntents
import BlinkConfig
import Foundation
import UIKit

// General Shortcuts actions: run a command or script on a saved host and get the output
// back, or open a terminal session in the app. The older "Run Fleet ..." actions stay so
// shortcuts built with them keep working; they share the code here.

// MARK: - Host picker

@available(iOS 16.0, *)
struct BlinkHostEntity: AppEntity {
  static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Blink Host")
  static var defaultQuery = BlinkHostQuery()

  /// The host's name in Blink (what you type after `ssh`).
  let id: String
  let hostName: String

  var displayRepresentation: DisplayRepresentation {
    hostName.isEmpty || hostName == id
      ? DisplayRepresentation(title: "\(id)")
      : DisplayRepresentation(title: "\(id)", subtitle: "\(hostName)")
  }

  static func all() -> [BlinkHostEntity] {
    return (BKHosts.allHosts() ?? [])
      .compactMap { host -> BlinkHostEntity? in
        guard let name = host.host, !name.isEmpty else { return nil }
        return BlinkHostEntity(id: name, hostName: host.hostName ?? "")
      }
      .sorted { $0.id.localizedCaseInsensitiveCompare($1.id) == .orderedAscending }
  }
}

@available(iOS 16.0, *)
struct BlinkHostQuery: EntityStringQuery {
  func entities(for identifiers: [String]) async throws -> [BlinkHostEntity] {
    let all = BlinkHostEntity.all()
    // A host typed by hand, or removed since the shortcut was made, still resolves by name
    // so the action can report it clearly when it runs.
    return identifiers.map { id in all.first { $0.id == id } ?? BlinkHostEntity(id: id, hostName: "") }
  }

  func entities(matching string: String) async throws -> [BlinkHostEntity] {
    BlinkHostEntity.all().filter {
      $0.id.localizedCaseInsensitiveContains(string) || $0.hostName.localizedCaseInsensitiveContains(string)
    }
  }

  func suggestedEntities() async throws -> [BlinkHostEntity] {
    BlinkHostEntity.all()
  }
}

// MARK: - Shared runner

@available(iOS 16.0, *)
enum HostActionRunner {
  /// Runs `command` on a saved host the way `ssh <host> <command>` would, and returns what it
  /// printed. A non-zero exit is an error (with the command's own error text), not empty output.
  static func run(host: String, command: String, what: String, trustNewHostKey: Bool) async throws -> String {
    guard BKHosts.withHost(host) != nil else {
      throw FleetIntentError.unknownHost(host)
    }
    do {
      let result = try await HeadlessSSHRunner.run(
        alias: host, command: command, acceptUnknownHostKeys: trustNewHostKey
      )
      if let code = result.exitCode, code != 0 {
        let detail = result.stderr.isEmpty ? result.stdout : result.stderr
        let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        throw FleetIntentError.runFailed("\(what) exited \(code)" + (trimmed.isEmpty ? "" : ": \(trimmed)"))
      }
      return result.stdout.isEmpty ? "(no output)" : result.stdout
    } catch let e as FleetIntentError {
      throw e
    } catch {
      // App Intents shows "unspecified error" unless the error describes itself.
      throw FleetIntentError.runFailed((error as? LocalizedError)?.errorDescription ?? "\(error)")
    }
  }
}

// MARK: - Run a command

@available(iOS 16.0, *)
struct RunCommandOnHostIntent: AppIntent {
  static var title: LocalizedStringResource = "Run Command on Host"
  static var description = IntentDescription(
    "Run a command on a host saved in Blink, over SSH, and return what it prints.",
    categoryName: "Hosts"
  )
  static var openAppWhenRun: Bool = false

  @Parameter(title: "Host")
  var host: BlinkHostEntity

  @Parameter(title: "Command")
  var command: String

  @Parameter(title: "Trust New Host Key",
             description: "Accept a host's key the first time it is seen. A key that has changed is always refused.",
             default: true)
  var trustNewHostKey: Bool

  static var parameterSummary: some ParameterSummary {
    Summary("Run \(\.$command) on \(\.$host)") {
      \.$trustNewHostKey
    }
  }

  @MainActor
  func perform() async throws -> some IntentResult & ReturnsValue<String> {
    .result(value: try await HostActionRunner.run(
      host: host.id, command: command, what: "command", trustNewHostKey: trustNewHostKey))
  }
}

// MARK: - Run a script

@available(iOS 16.0, *)
struct RunScriptOnHostIntent: AppIntent {
  static var title: LocalizedStringResource = "Run Script on Host"
  static var description = IntentDescription(
    "Run a script of several lines on a host saved in Blink, over SSH, and return what it prints.",
    categoryName: "Hosts"
  )
  static var openAppWhenRun: Bool = false

  @Parameter(title: "Host")
  var host: BlinkHostEntity

  @Parameter(title: "Interpreter", default: .bash)
  var interpreter: FleetInterpreter

  @Parameter(title: "Script", inputOptions: String.IntentInputOptions(multiline: true))
  var script: String

  @Parameter(title: "Trust New Host Key",
             description: "Accept a host's key the first time it is seen. A key that has changed is always refused.",
             default: true)
  var trustNewHostKey: Bool

  static var parameterSummary: some ParameterSummary {
    Summary("Run a \(\.$interpreter) script on \(\.$host)") {
      \.$script
      \.$trustNewHostKey
    }
  }

  @MainActor
  func perform() async throws -> some IntentResult & ReturnsValue<String> {
    // Encoded into one line (see FleetScript) so the script runs as written, with no quoting.
    let command = FleetScript.command(script: script, interpreter: interpreter.rawValue)
    return .result(value: try await HostActionRunner.run(
      host: host.id, command: command, what: "script", trustNewHostKey: trustNewHostKey))
  }
}

// MARK: - Open a session

@available(iOS 16.0, *)
enum SessionConnection: String, AppEnum {
  case ssh, mosh

  static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Connection")
  static var caseDisplayRepresentations: [SessionConnection: DisplayRepresentation] = [
    .ssh: "SSH", .mosh: "Mosh"
  ]
}

@available(iOS 16.0, *)
enum OpenSessionError: Error, CustomLocalizedStringResourceConvertible {
  case nothingToOpen
  case invalid(String)
  case appNotReady

  var localizedStringResource: LocalizedStringResource {
    switch self {
    case .nothingToOpen: return "Give the action a host, a command, or the name of a session to go back to."
    case .invalid(let why): return "Blink can't open that session: \(why)."
    case .appNotReady: return "Blink didn't finish opening. Try again."
    }
  }
}

@available(iOS 16.0, *)
struct OpenTerminalSessionIntent: AppIntent {
  static var title: LocalizedStringResource = "Open Terminal Session"
  static var description = IntentDescription(
    "Open Blink in a new terminal session: connect to a saved host, run a command, or both. Give the session a name and the action goes back to it next time instead of opening another.",
    categoryName: "Sessions"
  )
  static var openAppWhenRun: Bool = true

  @Parameter(title: "Host")
  var host: BlinkHostEntity?

  @Parameter(title: "Connection", default: .ssh)
  var connection: SessionConnection

  @Parameter(title: "Command", description: "Runs on the host, or in Blink's own shell when there is no host.")
  var command: String?

  @Parameter(title: "Session Name", description: "Letters, digits, dot, dash and underscore. A session opened under a name is reused while it stays open.")
  var sessionName: String?

  static var parameterSummary: some ParameterSummary {
    Summary("Open a session on \(\.$host)") {
      \.$connection
      \.$command
      \.$sessionName
    }
  }

  @MainActor
  func perform() async throws -> some IntentResult {
    // The same rules as blinkshell:// links, by building the link this action stands for.
    var components = URLComponents()
    components.scheme = "blinkshell"
    var items: [URLQueryItem] = []
    let cmd = (command ?? "").trimmingCharacters(in: .whitespaces)
    let name = (sessionName ?? "").trimmingCharacters(in: .whitespaces)
    if let host {
      components.host = "host"
      components.path = "/" + host.id
      if connection == .mosh { items.append(URLQueryItem(name: "mosh", value: "1")) }
    } else if !cmd.isEmpty {
      components.host = "run"
    } else if !name.isEmpty {
      components.host = "focus"
    } else {
      throw OpenSessionError.nothingToOpen
    }
    if !cmd.isEmpty { items.append(URLQueryItem(name: "cmd", value: cmd)) }
    if !name.isEmpty { items.append(URLQueryItem(name: "id", value: name)) }
    components.queryItems = items.isEmpty ? nil : items

    guard let url = components.url else { throw OpenSessionError.invalid("the host or name has characters a link can't carry") }
    let link: SessionLink
    switch SessionLink.parse(url) {
    case .success(let parsed): link = parsed
    case .failure(.badCommand): throw OpenSessionError.invalid("the command has a line break or is too long")
    case .failure(.badHost): throw OpenSessionError.invalid("the host name is not a plain host name")
    case .failure(.badID): throw OpenSessionError.invalid("the session name may only use letters, digits, dot, dash and underscore")
    case .failure: throw OpenSessionError.invalid("there is nothing to open")
    }

    // The app may still be launching: wait for a window to be on screen.
    for _ in 0..<40 {
      if let scene = UIApplication.shared.connectedScenes.activeAppScene(),
         let delegate = scene.delegate as? SceneDelegate {
        // A shortcut is something the user built and chose to run, so it needs no link key.
        delegate.spaceController.openSession(for: link)
        return .result()
      }
      try await Task.sleep(nanoseconds: 100_000_000)
    }
    throw OpenSessionError.appNotReady
  }
}
