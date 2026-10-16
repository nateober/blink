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

import Security
import UIKit
import SwiftUI

/// Where the `blinkshell://` link settings live. Off until the user turns them on.
enum LinkActionsSettings {
  private static let enabledKey = "LinkActionsEnabled"
  private static let legacyKeyKey = "LinkActionsKey"
  private static let keychainService = "com.obercode.blink.link-actions"

  static var isEnabled: Bool {
    get { UserDefaults.standard.bool(forKey: enabledKey) }
    set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
  }

  /// The key links are signed with. Kept in this device's Keychain, never synced or shown.
  static var signingKey: Data? {
    // The old plain key lived in UserDefaults and was copied to the shared clipboard, so it
    // is dropped rather than carried over.
    if UserDefaults.standard.object(forKey: legacyKeyKey) != nil {
      UserDefaults.standard.removeObject(forKey: legacyKeyKey)
    }
    var query = baseQuery
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
    return item as? Data
  }

  /// The signing key, made on first use.
  static func signingKeyCreatingIfNeeded() -> Data? {
    if let key = signingKey { return key }
    return replaceSigningKey()
  }

  /// A new key. Every link signed with the old one stops running without asking.
  @discardableResult
  static func replaceSigningKey() -> Data? {
    SecItemDelete(baseQuery as CFDictionary)
    let key = SessionLinkPolicy.makeKey()
    var add = baseQuery
    add[kSecValueData as String] = key
    add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    return SecItemAdd(add as CFDictionary, nil) == errSecSuccess ? key : nil
  }

  private static var baseQuery: [String: Any] {
    [kSecClass as String: kSecClassGenericPassword,
     kSecAttrService as String: keychainService,
     kSecAttrAccount as String: "signing-key",
     kSecAttrSynchronizable as String: false]
  }
}

struct LinkActionsView: View {
  @State private var enabled = LinkActionsSettings.isEnabled
  @State private var linkToSign = ""
  @State private var signed = ""
  @State private var signError = ""
  @State private var confirmReplace = false

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
          TextField("blinkshell://host/myserver?id=work", text: $linkToSign)
            .font(.system(.body, design: .monospaced))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .onChange(of: linkToSign) { _ in signed = ""; signError = "" }
          Button("Sign and Copy") { sign() }
            .disabled(linkToSign.trimmingCharacters(in: .whitespaces).isEmpty)
          if !signed.isEmpty {
            Text(signed)
              .font(.system(.footnote, design: .monospaced))
              .textSelection(.enabled)
            Text("Copied.").foregroundColor(.secondary)
          }
          if !signError.isEmpty {
            Text(signError).foregroundColor(.red)
          }
        } header: {
          Text("Sign a Link")
        } footer: {
          Text("A signed link runs its command without asking. The signature covers the whole link, so it can't be changed to run anything else. Any other link shows the command first and waits for you. The key that signs links never leaves this device.")
        }

        Section {
          Button("Replace Signing Key", role: .destructive) { confirmReplace = true }
        } footer: {
          Text("Every link signed so far will ask before it runs.")
        }
        .confirmationDialog("Replace the signing key?", isPresented: $confirmReplace, titleVisibility: .visible) {
          Button("Replace Key", role: .destructive) {
            LinkActionsSettings.replaceSigningKey()
            signed = ""
          }
        }

        Section("Examples") {
          example("Connect to a host", "blinkshell://host/myserver")
          example("Run a command", "blinkshell://run?cmd=ssh%20-t%20myserver%20tmux%20attach")
          example("Open once, then return to it", "blinkshell://host/myserver?mosh=1&id=work")
          example("Go back to a session", "blinkshell://focus?id=work")
        }
      }
    }
    .listStyle(.grouped)
    .navigationTitle("Link Actions")
  }

  private func sign() {
    signed = ""
    signError = ""
    guard let url = URL(string: linkToSign.trimmingCharacters(in: .whitespaces)) else {
      signError = "That isn't a link."
      return
    }
    guard let key = LinkActionsSettings.signingKeyCreatingIfNeeded() else {
      signError = "Blink couldn't save a signing key."
      return
    }
    switch SessionLink.signedURL(url, key: key) {
    case .success(let result):
      signed = result.absoluteString
      // Only this device's clipboard: the link stays local until it is pasted somewhere.
      UIPasteboard.general.setItems([[UIPasteboard.typeAutomatic: signed]], options: [.localOnly: true])
    case .failure(.notASessionLink):
      signError = "Only blinkshell://run, host and focus links can be signed."
    case .failure(.missingCommand):
      signError = "A run link needs a cmd."
    case .failure(.badCommand):
      signError = "The command has a line break, a control or invisible character, or is too long."
    case .failure(.badHost):
      signError = "The host is not a plain host name."
    case .failure(.badID):
      signError = "The id may only use letters, digits, dot, dash and underscore."
    }
  }

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
