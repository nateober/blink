//////////////////////////////////////////////////////////////////////////////////
//
// B L I N K  —  fleet-native fork
//
// SessionSwitcher: every tmux session on the fleet hosts in one list, the ones with an
// agent waiting on you first. Each host is asked with `blink-sessions` over SSH; parsing
// and ordering are in FleetCore/AgentRules.swift.
//
// Blink is free software under the GNU GPL v3; see <http://www.github.com/blinksh/blink>.
//
//////////////////////////////////////////////////////////////////////////////////

import Foundation
import SwiftUI

/// True the first time it is asked, false after: lets two racing tasks resume one continuation.
private final class OnceFlag: @unchecked Sendable {
  private let lock = NSLock()
  private var claimed = false
  func claim() -> Bool {
    lock.lock(); defer { lock.unlock() }
    if claimed { return false }
    claimed = true
    return true
  }
}

@MainActor
final class SessionSwitcherModel: ObservableObject {
  @Published var sessions: [FleetSession] = []
  @Published var loading = false
  /// Hosts asked that did not answer with a session list.
  @Published var silent: [String] = []
  @Published var asked: [String] = []

  let openTabs: Set<String>

  init(openTabs: Set<String>) {
    self.openTabs = openTabs
  }

  nonisolated static func key(host: String, session: String) -> String {
    host.lowercased() + "\t" + session
  }

  /// One host's sessions, or nil when it doesn't answer. A host that accepts the connection
  /// and then says nothing must not hold the list up, so the wait is bounded here as well as
  /// inside the SSH run.
  nonisolated private static func ask(_ alias: String) async -> [FleetSession]? {
    await withCheckedContinuation { (done: CheckedContinuation<[FleetSession]?, Never>) in
      let once = OnceFlag()
      let work = Task {
        let result = try? await HeadlessSSHRunner.run(
          alias: alias, command: FleetSession.listCommand, overallTimeout: 12)
        let list = result.flatMap { $0.exitOK ? FleetSession.parse(alias: alias, output: $0.stdout) : nil }
        if once.claim() { done.resume(returning: list) }
      }
      Task {
        try? await Task.sleep(nanoseconds: 15_000_000_000)
        if once.claim() {
          work.cancel()
          done.resume(returning: nil)
        }
      }
    }
  }

  func isOpen(_ session: FleetSession) -> Bool {
    openTabs.contains(Self.key(host: session.host, session: session.name))
  }

  /// Asks the hosts that answered before, or every host entry when none are known or
  /// `everyHost` is set.
  func load(everyHost: Bool = false) {
    guard !loading else { return }
    let known = AgentSettings.sessionHosts
    let scanAll = everyHost || known.isEmpty
    let hosts = scanAll ? FleetHosts.aliases() : known
    asked = hosts
    loading = true
    #if targetEnvironment(simulator)
    // Simulator runs have no host entries; a file of `blink-sessions` output stands in.
    if let path = ProcessInfo.processInfo.environment["BLINK_FIXTURE_SESSIONS"],
       let output = try? String(contentsOfFile: path, encoding: .utf8) {
      sessions = FleetSession.sorted(FleetSession.parse(alias: "ada", output: output))
      asked = ["ada"]
      loading = false
      return
    }
    #endif
    Task {
      var found: [FleetSession] = []
      var answered: [String] = []
      await withTaskGroup(of: (String, [FleetSession]?).self) { group in
        for alias in hosts {
          group.addTask {
            (alias, await Self.ask(alias))
          }
        }
        for await (alias, list) in group {
          guard let list else { continue }
          answered.append(alias)
          found.append(contentsOf: list)
        }
      }
      self.sessions = FleetSession.sorted(found)
      self.silent = hosts.filter { !answered.contains($0) }.sorted()
      self.loading = false
      if scanAll, !answered.isEmpty {
        AgentSettings.sessionHosts = answered.sorted()
      }
    }
  }
}

struct SessionSwitcherView: View {
  @ObservedObject var model: SessionSwitcherModel
  let onPick: (FleetSession) -> Void
  let onClose: () -> Void

  var body: some View {
    NavigationView {
      List {
        if model.sessions.isEmpty {
          if model.loading {
            HStack(spacing: 10) {
              ProgressView()
              Text("Asking \(model.asked.count) \(model.asked.count == 1 ? "host" : "hosts")")
                .foregroundColor(.secondary)
            }
          } else {
            Text("No tmux sessions found. A host is listed once the agent loop is installed on it (scripts/fleet/install-agent-loop.sh).")
              .foregroundColor(.secondary)
          }
        }
        ForEach(Array(model.sessions.enumerated()), id: \.offset) { _, session in
          Button {
            onPick(session)
          } label: {
            SessionRow(session: session, open: model.isOpen(session))
          }
          .buttonStyle(.plain)
        }
        if !model.loading {
          Section {
            Button("Ask every host again") { model.load(everyHost: true) }
          } footer: {
            if !model.silent.isEmpty {
              Text("No answer from \(model.silent.joined(separator: ", ")).")
            }
          }
        }
      }
      .listStyle(.insetGrouped)
      .navigationTitle("Sessions")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Close", action: onClose)
        }
        ToolbarItem(placement: .primaryAction) {
          if model.loading {
            ProgressView()
          } else {
            Button {
              model.load()
            } label: {
              Image(systemName: "arrow.clockwise")
            }
            .accessibilityLabel("Refresh")
          }
        }
      }
    }
    .navigationViewStyle(.stack)
  }
}

private struct SessionRow: View {
  let session: FleetSession
  let open: Bool

  private var mark: (symbol: String, color: Color, label: String) {
    switch session.state {
    case .needsInput: return ("exclamationmark.circle.fill", .orange, "Needs input")
    case .done: return ("checkmark.circle.fill", .green, "Finished")
    case .running: return ("circle.dotted", .blue, "Running")
    case .none: return ("terminal", .secondary, "")
    }
  }

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      Image(systemName: mark.symbol)
        .foregroundColor(mark.color)
        .frame(width: 22)
        .accessibilityLabel(mark.label)
      VStack(alignment: .leading, spacing: 2) {
        Text(session.name)
          .font(.body.weight(.semibold))
          .lineLimit(1)
        if !session.task.isEmpty {
          Text(session.task)
            .font(.subheadline)
            .foregroundColor(.secondary)
            .lineLimit(2)
        }
        Text(detail)
          .font(.caption)
          .foregroundColor(.secondary)
      }
      Spacer(minLength: 0)
      if open {
        Image(systemName: "rectangle.on.rectangle")
          .font(.caption)
          .foregroundColor(.secondary)
          .accessibilityLabel("Open in a tab")
      }
    }
    .contentShape(Rectangle())
    .padding(.vertical, 2)
  }

  private var detail: String {
    var parts = [session.alias, session.age(now: Date())]
    if !mark.label.isEmpty { parts.insert(mark.label, at: 0) }
    return parts.joined(separator: " · ")
  }
}
