//////////////////////////////////////////////////////////////////////////////////
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

import SwiftUI

/// Where the `blinkshell://` link settings live. Off until the user turns them on.
enum LinkActionsSettings {
  private static let enabledKey = "LinkActionsEnabled"
  private static let userKeyKey = "LinkActionsKey"

  static var isEnabled: Bool {
    get { UserDefaults.standard.bool(forKey: enabledKey) }
    set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
  }

  static var userKey: String {
    get { UserDefaults.standard.string(forKey: userKeyKey) ?? "" }
    set { UserDefaults.standard.set(newValue, forKey: userKeyKey) }
  }
}

struct LinkActionsView: View {
  @State private var enabled = LinkActionsSettings.isEnabled
  @State private var key = LinkActionsSettings.userKey

  var body: some View {
    List {
      Section {
        Toggle("Allow links to open sessions", isOn: $enabled)
          .onChange(of: enabled) { LinkActionsSettings.isEnabled = $0 }
      } footer: {
        Text("Links that start with blinkshell:// can open a session, connect to a host, or go back to a session they opened earlier. They do nothing while this is off.")
      }

      if enabled {
        Section {
          HStack {
            Text(key.isEmpty ? "No key" : key)
              .font(.system(.body, design: .monospaced))
              .foregroundColor(key.isEmpty ? .secondary : .primary)
              .textSelection(.enabled)
            Spacer()
            if !key.isEmpty {
              Button {
                UIPasteboard.general.string = key
              } label: {
                Image(systemName: "doc.on.doc")
              }
              .buttonStyle(.borderless)
            }
          }
          Button(key.isEmpty ? "Create Key" : "Replace Key") {
            key = SessionLinkPolicy.makeKey()
            LinkActionsSettings.userKey = key
          }
          if !key.isEmpty {
            Button("Remove Key", role: .destructive) {
              key = ""
              LinkActionsSettings.userKey = ""
            }
          }
        } header: {
          Text("Your Key")
        } footer: {
          Text("A link that carries your key runs its command without asking. Any other link shows the command first and waits for you. Put the key only in links you write yourself.")
        }

        Section("Examples") {
          example("Connect to a host", "blinkshell://host/myserver")
          example("Run a command", "blinkshell://run?cmd=ssh%20-t%20myserver%20tmux%20attach" + keySuffix)
          example("Open once, then return to it", "blinkshell://host/myserver?mosh=1&id=work" + keySuffix)
          example("Go back to a session", "blinkshell://focus?id=work")
        }
      }
    }
    .listStyle(.grouped)
    .navigationTitle("Link Actions")
  }

  private var keySuffix: String { key.isEmpty ? "" : "&key=\(key)" }

  private func example(_ title: String, _ link: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
      Text(link)
        .font(.system(.footnote, design: .monospaced))
        .foregroundColor(.secondary)
        .textSelection(.enabled)
    }
  }
}
