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
