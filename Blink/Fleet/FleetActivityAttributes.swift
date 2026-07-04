//////////////////////////////////////////////////////////////////////////////////
//
// B L I N K  —  fleet-native fork
//
// FleetActivityAttributes: the ActivityKit model shared between the app (which starts /
// updates / ends the Live Activity and captures its push token) and the widget extension
// (which renders the lock-screen + Dynamic Island UI). Add THIS FILE to BOTH the Blink app
// target and the new widget-extension target. See docs/LIVE-ACTIVITY-SETUP.md.
//
// Blink is free software under the GNU GPL v3; see <http://www.github.com/blinksh/blink>.
//
//////////////////////////////////////////////////////////////////////////////////

import Foundation
import ActivityKit

@available(iOS 16.1, *)
public struct FleetActivityAttributes: ActivityAttributes {
  /// The mutable part — pushed/updated as the fleet command progresses.
  public struct ContentState: Codable, Hashable {
    public var status: String   // "running" | "needs input" | "done" | "failed" | free text
    public var detail: String   // e.g. "claude -p" or the last line of output
    public var updatedAt: Date
    public init(status: String, detail: String, updatedAt: Date) {
      self.status = status
      self.detail = detail
      self.updatedAt = updatedAt
    }
  }

  /// The fixed part — set once at start.
  public var host: String         // e.g. "ada"
  public var sessionLabel: String // e.g. "claude" / a short session name
  public init(host: String, sessionLabel: String) {
    self.host = host
    self.sessionLabel = sessionLabel
  }
}
