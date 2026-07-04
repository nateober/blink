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
    // The device token is half the secret needed to push to this device — don't log it in
    // full to the unified log (readable via Console / sysdiagnose). Prefix only, Debug only.
    #if DEBUG
    NSLog("[blink-notify] APNs device token (prefix): %@…", String(hex.prefix(8)))
    #endif
    publishBestEffort(hex: hex)
  }

  /// The last token this device registered (for display in settings/UI).
  @objc public func currentToken() -> String? { tokenStore.load() }

  /// Publish the token to ~/.blink-notify/token on a configured host (alias
  /// "push-notify" preferred, else "ada"). No-op if neither is configured.
  private func publishBestEffort(hex: String) {
    let candidates = ["push-notify", "ada"]
    guard let alias = candidates.first(where: { BKHosts.withHost($0) != nil }) else { return }
    // Defense in depth: hex is built from raw token bytes (always [0-9a-f]), but guard
    // locally so the value interpolated into the remote shell command can't ever inject.
    guard !hex.isEmpty, hex.allSatisfy(\.isHexDigit) else { return }
    let cmd = "mkdir -p ~/.blink-notify && printf '%s' '\(hex)' > ~/.blink-notify/token"
    Task {
      do {
        // Resolve + authenticate like `ssh <alias>` (agent + default keys + keyboard-interactive),
        // trusting the host key on first use for the owner's own fleet.
        _ = try await HeadlessSSHRunner.run(alias: alias, command: cmd, acceptUnknownHostKeys: true)
        NSLog("[blink-notify] published APNs token via '%@'", alias)
      } catch {
        NSLog("[blink-notify] token publish to '%@' failed: %@", alias, error.localizedDescription)
      }
    }
  }
}
