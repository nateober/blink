//////////////////////////////////////////////////////////////////////////////////
//
// B L I N K  —  fleet-native fork
//
// notiflog: list the fleet push notifications this device has received (most recent
// first), so the text survives tapping the banner. `notiflog clear` empties the log.
//
// Blink is free software under the GNU GPL v3; see <http://www.github.com/blinksh/blink>.
//
//////////////////////////////////////////////////////////////////////////////////

import Foundation
import BlinkConfig
import ios_system

@_cdecl("notiflog_main")
public func notiflog_main(argc: Int32, argv: Argv) -> Int32 {
  let args = argv.args(count: argc)
  if args.count > 1, args[1] == "clear" {
    NotificationInbox.shared.clear()
    fputs("Notification log cleared.\n", thread_stdout)
    return 0
  }

  let records = NotificationInbox.shared.recent(limit: 50)
  guard !records.isEmpty else {
    fputs("No notifications yet.\n", thread_stdout)
    return 0
  }

  let fmt = DateFormatter()
  fmt.dateFormat = "MMM d HH:mm"
  for r in records {
    let when = fmt.string(from: r.receivedAt)
    var tags = [String]()
    if let k = r.kind { tags.append(k) }
    if let h = r.host { tags.append(h) }
    let prefix = tags.isEmpty ? "" : "[\(tags.joined(separator: " "))] "
    fputs("\(when)  \(prefix)\(r.title)\n", thread_stdout)
    if !r.body.isEmpty {
      fputs("            \(r.body)\n", thread_stdout)
    }
  }
  return 0
}
