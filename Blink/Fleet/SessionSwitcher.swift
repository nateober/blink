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
    Task {
      var found: [FleetSession] = []
      var answered: [String] = []
      await withTaskGroup(of: (String, [FleetSession]?).self) { group in
        for alias in hosts {
          group.addTask {
            guard let result = try? await HeadlessSSHRunner.run(
              alias: alias, command: FleetSession.listCommand, overallTimeout: 12),
              result.exitOK
            else { return (alias, nil) }
            return (alias, FleetSession.parse(alias: alias, output: result.stdout))
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
