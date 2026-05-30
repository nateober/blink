//////////////////////////////////////////////////////////////////////////////////
//
// B L I N K  —  fleet-native fork
//
// liveactivity: start / update / end the fleet Live Activity from the terminal (the twin of
// the remote APNs path). Renders on the lock screen + Dynamic Island via the widget extension.
//
//   liveactivity start <host> <label> [status] [detail]
//   liveactivity update <status> [detail]
//   liveactivity end
//
// Blink is free software under the GNU GPL v3; see <http://www.github.com/blinksh/blink>.
//
//////////////////////////////////////////////////////////////////////////////////

import Foundation
import ios_system

@_cdecl("liveactivity_main")
public func liveactivity_main(argc: Int32, argv: Argv) -> Int32 {
  let args = argv.args(count: argc)
  func err(_ s: String) -> Int32 { fputs("liveactivity: \(s)\n", thread_stderr); return 1 }
  func out(_ s: String) { fputs(s + "\n", thread_stdout) }

  guard #available(iOS 16.1, *) else { return err("Live Activities need iOS 16.1+") }
  guard args.count > 1 else {
    return err("usage: liveactivity start <host> <label> [status] [detail] | update <status> [detail] | end")
  }

  let ctrl = FleetActivityController.shared
  let sema = DispatchSemaphore(value: 0)
  var failure: String?
  var message = ""

  switch args[1] {
  case "start":
    guard args.count > 3 else { return err("usage: liveactivity start <host> <label> [status] [detail]") }
    let host = args[2], label = args[3]
    let status = args.count > 4 ? args[4] : "running"
    let detail = args.count > 5 ? args[5...].joined(separator: " ") : label
    do {
      try ctrl.start(host: host, label: label, status: status, detail: detail)
      message = "Live Activity started for \(label)@\(host)."
    } catch { failure = (error as? LocalizedError)?.errorDescription ?? "\(error)" }
    sema.signal()

  case "update":
    guard args.count > 2 else { return err("usage: liveactivity update <status> [detail]") }
    let status = args[2]
    let detail = args.count > 3 ? args[3...].joined(separator: " ") : status
    Task {
      do { try await ctrl.update(status: status, detail: detail); message = "Updated." }
      catch { failure = (error as? LocalizedError)?.errorDescription ?? "\(error)" }
      sema.signal()
    }

  case "end":
    ctrl.end(); message = "Ended."; sema.signal()

  default:
    return err("unknown subcommand '\(args[1])' (start | update | end)")
  }

  sema.wait()
  if let failure { return err(failure) }
  out(message)
  return 0
}
