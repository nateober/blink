//////////////////////////////////////////////////////////////////////////////////
//
// B L I N K  —  fleet-native fork
//
// AgentSessions: the app-side glue for agents running in tmux on the fleet. Which Blink
// host entry reaches a host a push names, what tmux session each tab was last attached
// to, and whether an agent push deserves a banner. The decisions themselves are in
// FleetCore/AgentRules.swift.
//
// Blink is free software under the GNU GPL v3; see <http://www.github.com/blinksh/blink>.
//
//////////////////////////////////////////////////////////////////////////////////

import Foundation
import UIKit
import UserNotifications
import BlinkConfig

enum FleetHosts {
  /// The host entry that reaches the machine tmux calls `host` (its short hostname): an
  /// entry with that name, or one whose address starts with it (`ada` for `ada.ober`).
  static func alias(for host: String) -> String? {
    let wanted = host.lowercased()
    let hosts = BKHosts.allHosts() ?? []
    if let exact = hosts.first(where: { ($0.host ?? "").lowercased() == wanted }) {
      return exact.host
    }
    return hosts.first(where: {
      let name = ($0.hostName ?? "").lowercased()
      return name == wanted || name.hasPrefix(wanted + ".")
    })?.host
  }

  /// Every host entry's name, for the session switcher.
  static func aliases() -> [String] {
    (BKHosts.allHosts() ?? []).compactMap { $0.host }.filter { !$0.isEmpty }
  }
}

/// Remembers the tmux title each tab last showed, so a tab that hasn't been loaded since
/// the app launched can still be matched to its session.
enum AgentTabTitles {
  private static let key = "AgentTabTitles"
  private static let limit = 60

  static func title(for tab: UUID, live: String?) -> String? {
    guard let live, !live.isEmpty else {
      return (UserDefaults.standard.dictionary(forKey: key) as? [String: String])?[tab.uuidString]
    }
    var stored = (UserDefaults.standard.dictionary(forKey: key) as? [String: String]) ?? [:]
    if TmuxTitle.parse(live) != nil {
      if stored[tab.uuidString] != live {
        if stored.count >= limit { stored.removeAll() }
        stored[tab.uuidString] = live
        UserDefaults.standard.set(stored, forKey: key)
      }
    } else if stored[tab.uuidString] != nil {
      // The tab left tmux; what it was attached to before no longer holds.
      stored[tab.uuidString] = nil
      UserDefaults.standard.set(stored, forKey: key)
    }
    return live
  }
}

@objc final class AgentPush: NSObject {
  /// False for an agent push that shouldn't interrupt while Blink is in front: one about the
  /// session on screen, or one that only says an agent finished.
  @objc(showsBannerFor:) static func showsBanner(for userInfo: [AnyHashable: Any]) -> Bool {
    guard let blink = userInfo["blink"] as? [String: Any] else { return true }
    if (blink["kind"] as? String) == BlinkPush.Meta.Kind.done.rawValue { return false }
    let front = UIApplication.shared.connectedScenes
      .first(where: { $0.activationState == .foregroundActive })
      .flatMap { $0.delegate as? SceneDelegate }?
      .spaceController.frontTabTitle()
    return AgentRoute.showsBanner(
      host: blink["host"] as? String,
      session: blink["session"] as? String,
      frontTitle: front,
      appActive: UIApplication.shared.applicationState == .active)
  }
}

/// Answering an agent's permission prompt from its push (FleetCore/PermissionReply).
@objc final class AgentReply: NSObject {
  /// Gives pushes that carry a permission request their Approve and Deny buttons. Both ask
  /// for the phone to be unlocked first, and neither brings the app to the front.
  @objc static func registerCategory() {
    let approve = UNNotificationAction(
      identifier: PermissionReply.approveAction, title: "Approve", options: [.authenticationRequired])
    let deny = UNNotificationAction(
      identifier: PermissionReply.denyAction, title: "Deny", options: [.authenticationRequired, .destructive])
    // Opening another app needs this one in front for a moment.
    let open = UNNotificationAction(
      identifier: PermissionReply.openAction, title: "Open in Claude", options: [.foreground])
    let ours = [
      PermissionReply.category: [approve, deny],
      PermissionReply.remoteCategory: [approve, deny, open],
      PermissionReply.openOnlyCategory: [open],
    ]
    let center = UNUserNotificationCenter.current()
    center.getNotificationCategories { existing in
      var all = existing.filter { ours[$0.identifier] == nil }
      for (identifier, actions) in ours {
        all.insert(UNNotificationCategory(
          identifier: identifier, actions: actions, intentIdentifiers: [], options: []))
      }
      center.setNotificationCategories(all)
    }
  }

  /// Runs the answer on the host the push named, or opens the session in the Claude app.
  /// False when the response is not one of our buttons (a plain tap), and `completion` is
  /// then the caller's to call.
  @objc(handleAction:userInfo:completion:)
  static func handle(action: String, userInfo: [AnyHashable: Any], completion: @escaping () -> Void) -> Bool {
    guard let blink = userInfo["blink"] as? [String: Any] else { return false }
    if let address = PermissionReply.remoteURL(action: action, address: blink["claude"] as? String),
       let url = URL(string: address) {
      // Open in Claude: the session's page in the Claude app (Remote Control).
      DispatchQueue.main.async {
        UIApplication.shared.open(url, options: [:]) { _ in completion() }
      }
      return true
    }
    guard let host = blink["host"] as? String,
          let command = PermissionReply.command(action: action, request: blink["request"] as? String)
    else { return false }
    let session = (blink["session"] as? String) ?? host
    let request = (blink["request"] as? String) ?? ""

    var task = UIBackgroundTaskIdentifier.invalid
    let end = {
      if task != .invalid {
        UIApplication.shared.endBackgroundTask(task)
        task = .invalid
      }
    }
    task = UIApplication.shared.beginBackgroundTask(withName: "agent-reply") { end() }

    Task {
      var outcome = PermissionReply.Outcome.failed("no host entry reaches \(host)")
      if let alias = FleetHosts.alias(for: host) {
        do {
          let result = try await HeadlessSSHRunner.run(alias: alias, command: command, overallTimeout: 20)
          outcome = PermissionReply.outcome(stdout: result.stdout, exitCode: result.exitCode, stderr: result.stderr)
        } catch {
          outcome = .failed((error as? LocalizedError)?.errorDescription ?? "\(error)")
        }
      }
      if let notice = PermissionReply.failureNotice(session: session, action: action, outcome: outcome) {
        // Say so, and make the notice a way back to the session.
        let content = UNMutableNotificationContent()
        content.title = notice.title
        content.body = notice.body
        content.sound = .default
        content.userInfo = ["blink": ["kind": "needs_input", "host": host, "session": session]]
        try? await UNUserNotificationCenter.current().add(
          UNNotificationRequest(identifier: "agent-reply-\(request)", content: content, trigger: nil))
      }
      await MainActor.run {
        completion()
        end()
      }
    }
    return true
  }
}

enum AgentSettings {
  private static let composeKey = "AgentsComposeDictation"
  private static let hostsKey = "AgentsSessionHosts"

  /// Dictation opens the compose area in Prompt mode when a coding agent is in front.
  static var composeDictation: Bool {
    get { UserDefaults.standard.object(forKey: composeKey) as? Bool ?? true }
    set { UserDefaults.standard.set(newValue, forKey: composeKey) }
  }

  /// Host entries that answered the session switcher last time. Empty means ask them all.
  static var sessionHosts: [String] {
    get { UserDefaults.standard.stringArray(forKey: hostsKey) ?? [] }
    set { UserDefaults.standard.set(newValue, forKey: hostsKey) }
  }
}
