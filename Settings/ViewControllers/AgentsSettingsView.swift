//////////////////////////////////////////////////////////////////////////////////
//
// B L I N K  —  fleet-native fork
//
// AgentsSettingsView: the switches for working with coding agents on the fleet.
//
// Blink is free software under the GNU GPL v3; see <http://www.github.com/blinksh/blink>.
//
//////////////////////////////////////////////////////////////////////////////////

import SwiftUI

struct AgentsSettingsView: View {
  @State private var compose = AgentSettings.composeDictation
  @State private var hosts = AgentSettings.sessionHosts

  var body: some View {
    List {
      Section {
        Toggle("Dictate into the compose area", isOn: $compose)
          .onChange(of: compose) { AgentSettings.composeDictation = $0 }
      } footer: {
        Text("With a coding agent in front, the dictation key puts your words in the compose area as a prompt to read over and send. Off, or anywhere else, they are typed at the cursor.")
      }

      Section {
        if hosts.isEmpty {
          Text("Every host is asked the next time Sessions opens.")
            .foregroundColor(.secondary)
        } else {
          ForEach(hosts, id: \.self) { Text($0) }
          Button("Forget these hosts", role: .destructive) {
            AgentSettings.sessionHosts = []
            hosts = []
          }
        }
      } header: {
        Text("Session switcher hosts")
      } footer: {
        Text("Sessions lists the tmux sessions on the hosts that answered last time. A host answers once scripts/fleet/install-agent-loop.sh has been run on it; that script also installs the hook that sends a push when an agent needs you.")
      }
    }
    .listStyle(.insetGrouped)
    .navigationTitle("Agents")
  }
}
