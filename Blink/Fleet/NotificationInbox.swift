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
    // Foreground arrival (willPresent) and a subsequent tap (didReceiveResponse) can both
    // fire for the same push — collapse the immediate duplicate.
    if let last = log.recent(limit: 1).first,
       last.title == title, last.body == body,
       Date().timeIntervalSince(last.receivedAt) < 5 {
      return
    }
    log.append(NotificationRecord(
      receivedAt: Date(),
      title: title,
      body: body,
      kind: blink?["kind"] as? String,
      host: blink?["host"] as? String,
      session: blink?["session"] as? String
    ))
  }

  func recent(limit: Int = 50) -> [NotificationRecord] { log.recent(limit: limit) }
  func clear() { log.clear() }
}
