//////////////////////////////////////////////////////////////////////////////////
//
// B L I N K  —  fleet-native fork
//
// NotificationInbox: records every received push so its text survives the tap (iOS
// clears the banner once the app opens, losing the content). Bridges the ObjC
// AppDelegate notification callbacks to FleetCore's NotificationLog, and backs the
// `notiflog` terminal command.
//
// Blink is free software under the GNU GPL v3; see <http://www.github.com/blinksh/blink>.
//
//////////////////////////////////////////////////////////////////////////////////

import Foundation
import BlinkConfig

@objc public final class NotificationInbox: NSObject {
  @objc public static let shared = NotificationInbox()
  private let log: NotificationLog

  private override init() {
    let url = URL(fileURLWithPath: BlinkPaths.blink()).appendingPathComponent("notifications.plist")
    self.log = NotificationLog(storeURL: url)
    super.init()
  }

  /// Called from AppDelegate on notification receipt/tap. Pulls title/body and the
  /// `blink` routing dict ({kind,host,session}) out of the APNs userInfo and persists it.
  @objc public func record(title: String?, body: String?, userInfo: [AnyHashable: Any]) {
    let blink = userInfo["blink"] as? [String: Any]
    let title = title ?? ""
    let body = body ?? ""
    let host = blink?["host"] as? String
    // The same push can surface via more than one callback (foreground willPresent, a tap,
    // and a content-available background wake). Collapse the immediate duplicate — keyed on
    // host too, so two different hosts with identical text aren't merged.
    if let last = log.recent(limit: 1).first,
       last.title == title, last.body == body, last.host == host,
       Date().timeIntervalSince(last.receivedAt) < 10 {
      return
    }
    log.append(NotificationRecord(
      receivedAt: Date(),
      title: title,
      body: body,
      kind: blink?["kind"] as? String,
      host: host,
      session: blink?["session"] as? String
    ))
  }

  /// Background/content-available path: the raw APNs userInfo has the alert nested under
  /// `aps.alert`. Dig it out, then record (deduped) like the foreground path.
  @objc public func recordRemote(userInfo: [AnyHashable: Any]) {
    let aps = userInfo["aps"] as? [String: Any]
    let alert = aps?["alert"] as? [String: Any]
    record(title: alert?["title"] as? String, body: alert?["body"] as? String, userInfo: userInfo)
  }

  func recent(limit: Int = 50) -> [NotificationRecord] { log.recent(limit: limit) }
  func clear() { log.clear() }
}
