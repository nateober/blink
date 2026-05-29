//////////////////////////////////////////////////////////////////////////////////
//
// B L I N K  —  fleet-native fork
//
// PushRegistrar: register for remote (APNs) notifications, capture the device token,
// persist it, and best-effort publish it to ~/.blink-notify/token on a configured
// fleet host so the fleet-side blink_notify.py can target this device. Incoming
// "agent needs input" pushes are displayed by AppDelegate's existing
// UNUserNotificationCenterDelegate. Standard alert pushes (no Live Activity / widget
// extension — that's deferred).
//
// Blink is free software under the GNU GPL v3; see <http://www.github.com/blinksh/blink>.
//
//////////////////////////////////////////////////////////////////////////////////

import Foundation
import UIKit
import UserNotifications
import BlinkConfig

@objc public class PushRegistrar: NSObject {
  @objc public static let shared = PushRegistrar()

  private var tokenStore: APNSTokenStore {
    APNSTokenStore(fileURL: URL(fileURLWithPath: BlinkPaths.blink())
      .appendingPathComponent("apns_token.txt"))
  }

  /// Request notification authorization, then register for remote notifications.
  @objc public func requestAndRegister() {
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
      guard granted else { return }
      DispatchQueue.main.async {
        UIApplication.shared.registerForRemoteNotifications()
      }
    }
  }

  /// Called from AppDelegate's didRegisterForRemoteNotificationsWithDeviceToken.
  @objc public func handleTokenData(_ deviceToken: Data) {
    let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
    tokenStore.save(hex: hex)
    NSLog("[blink-notify] APNs device token: %@", hex)
    publishBestEffort(hex: hex)
  }

  /// The last token this device registered (for display in settings/UI).
  @objc public func currentToken() -> String? { tokenStore.load() }

  /// Publish the token to ~/.blink-notify/token on a configured host (alias
  /// "push-notify" preferred, else "ada"). No-op if neither is configured.
  private func publishBestEffort(hex: String) {
    let candidates = ["push-notify", "ada"]
    guard let alias = candidates.first(where: { BKHosts.withHost($0) != nil }),
          let h = BKHosts.withHost(alias) else { return }
    let user = (h.user?.isEmpty == false) ? h.user! : NSUserName()
    let hostName = (h.hostName?.isEmpty == false) ? h.hostName! : alias
    var pem: String? = nil
    if let keyName = h.key, let card = BKPubKey.withID(keyName) { pem = card.loadPrivateKey() }
    let pw = h.password
    let cmd = "mkdir -p ~/.blink-notify && printf '%s' '\(hex)' > ~/.blink-notify/token"
    Task {
      do {
        _ = try await HeadlessSSHRunner.run(
          host: hostName, user: user, command: cmd,
          privateKey: pem, password: pw,
          // Owner publishing to their own fleet host: honor a stored password (key-less
          // hosts authenticate this way) and trust on first use, mirroring the App Intent
          // path. The fork's known_hosts may not yet contain this host.
          acceptUnknownHostKeys: true
        )
        NSLog("[blink-notify] published APNs token to %@@%@", user, hostName)
      } catch {
        NSLog("[blink-notify] token publish to '%@' failed: %@", alias, error.localizedDescription)
      }
    }
  }
}
