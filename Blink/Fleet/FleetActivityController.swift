//////////////////////////////////////////////////////////////////////////////////
//
// B L I N K  —  fleet-native fork
//
// FleetActivityController: app-side start / update / end of the fleet Live Activity, and
// capture of its ActivityKit push-update token (published to the fleet host alongside the
// device token, so a remote `claude -p` can drive the lock-screen indicator over APNs).
// The lock-screen + Dynamic Island UI lives in the widget extension (see the SETUP doc);
// this controller works once that extension exists. Availability-gated to iOS 16.1+.
//
// Blink is free software under the GNU GPL v3; see <http://www.github.com/blinksh/blink>.
//
//////////////////////////////////////////////////////////////////////////////////

import Foundation
import ActivityKit
import BlinkConfig

@available(iOS 16.1, *)
public enum FleetActivityError: Error, LocalizedError {
  case disabled
  case noActive
  public var errorDescription: String? {
    switch self {
    case .disabled: return "Live Activities are turned off (Settings → Blink → enable, or Face ID/Notifications)."
    case .noActive: return "No active fleet Live Activity to update/end."
    }
  }
}

@available(iOS 16.1, *)
public final class FleetActivityController {
  public static let shared = FleetActivityController()
  private var current: Activity<FleetActivityAttributes>?
  private var tokenTask: Task<Void, Never>?

  public var isRunning: Bool { current != nil }

  private var observing = false
  private var startTokenTask: Task<Void, Never>?
  private var adoptTask: Task<Void, Never>?

  /// Called once at launch. Publishes the token a fleet host needs to start the activity by
  /// push (iOS 17.2+), and picks up an activity started that way so its update token gets
  /// published too. iOS wakes the app in the background for both.
  public func startObserving() {
    guard !observing else { return }
    observing = true
    if #available(iOS 17.2, *) {
      startTokenTask = Task { [weak self] in
        for await tokenData in Activity<FleetActivityAttributes>.pushToStartTokenUpdates {
          let hex = tokenData.map { String(format: "%02x", $0) }.joined()
          await self?.publish(hex, as: "activity-start-token")
        }
      }
    }
    adoptTask = Task { [weak self] in
      for await activity in Activity<FleetActivityAttributes>.activityUpdates {
        self?.adopt(activity)
      }
    }
  }

  /// Follow an activity this controller didn't start (a remote start, or one that outlived
  /// the last launch).
  private func adopt(_ activity: Activity<FleetActivityAttributes>) {
    guard activity.id != current?.id else { return }
    guard activity.activityState == .active || activity.activityState == .stale else { return }
    current = activity
    tokenTask?.cancel()
    tokenTask = Task { [weak self] in
      for await tokenData in activity.pushTokenUpdates {
        let hex = tokenData.map { String(format: "%02x", $0) }.joined()
        await self?.publishActivityToken(hex)
      }
    }
  }

  /// Start (replacing any current) a Live Activity for a fleet session, requesting a push token.
  public func start(host: String, label: String, status: String, detail: String) throws {
    guard ActivityAuthorizationInfo().areActivitiesEnabled else { throw FleetActivityError.disabled }
    end()  // one fleet activity at a time

    let attrs = FleetActivityAttributes(host: host, sessionLabel: label)
    let state = FleetActivityAttributes.ContentState(status: status, detail: detail, updatedAt: Date())
    let content = ActivityContent(state: state, staleDate: nil)
    let activity = try Activity.request(attributes: attrs, content: content, pushType: .token)
    current = activity

    // Capture the per-activity push token and publish it to the fleet so the host can
    // update this specific activity via APNs (apns-push-type: liveactivity).
    tokenTask = Task { [weak self] in
      for await tokenData in activity.pushTokenUpdates {
        let hex = tokenData.map { String(format: "%02x", $0) }.joined()
        await self?.publishActivityToken(hex)
        _ = self
      }
    }
  }

  public func update(status: String, detail: String) async throws {
    guard let activity = current else { throw FleetActivityError.noActive }
    let state = FleetActivityAttributes.ContentState(status: status, detail: detail, updatedAt: Date())
    await activity.update(ActivityContent(state: state, staleDate: nil))
  }

  public func end() {
    tokenTask?.cancel(); tokenTask = nil
    guard let activity = current else { return }
    current = nil
    Task { await activity.end(nil, dismissalPolicy: .immediate) }
  }

  /// Best-effort publish of the activity push token to ~/.blink-notify/activity-token on the
  /// fleet host (mirrors PushRegistrar's device-token publish). Guarded to valid hex.
  private func publishActivityToken(_ hex: String) async {
    await publish(hex, as: "activity-token")
  }

  /// Writes a token to ~/.blink-notify/<name> on the fleet host. `name` is one of ours, and
  /// the token is checked to be hex, so nothing in the command comes from outside.
  private func publish(_ hex: String, as name: String) async {
    guard !hex.isEmpty, hex.allSatisfy(\.isHexDigit) else { return }
    guard ["activity-token", "activity-start-token"].contains(name) else { return }
    let alias = ["push-notify", "ada"].first { BKHostsExists($0) }
    guard let alias else { return }
    let cmd = "mkdir -p ~/.blink-notify && printf '%s' '\(hex)' > ~/.blink-notify/\(name)"
    _ = try? await HeadlessSSHRunner.run(alias: alias, command: cmd, acceptUnknownHostKeys: true)
  }
}

/// What AppDelegate (Objective-C) calls at launch.
@objc public final class FleetActivityBridge: NSObject {
  @objc public static func startObserving() {
    if #available(iOS 16.1, *) {
      FleetActivityController.shared.startObserving()
    }
  }
}

/// Tiny indirection so this file doesn't import the BKHosts header directly (kept Swift-only).
@available(iOS 16.1, *)
private func BKHostsExists(_ alias: String) -> Bool { BKHosts.withHost(alias) != nil }
