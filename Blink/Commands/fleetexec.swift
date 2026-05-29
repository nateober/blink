//////////////////////////////////////////////////////////////////////////////////
//
// B L I N K  —  fleet-native fork
//
// fleetexec: terminal twin of the "Run Fleet Command" App Intent. Resolves a saved
// Blink host (BKHosts/BKPubKey, same as the Shortcut) and runs one command on it via
// HeadlessSSHRunner — no PTY, no interactive session — printing stdout/stderr and
// exiting with the remote exit code. Lets the headless SSH path be exercised and
// debugged from the terminal (the App Intent can't be driven from a shell).
//
// Usage: fleetexec <host> <command...>
//
// Blink is free software under the GNU GPL v3; see <http://www.github.com/blinksh/blink>.
//
//////////////////////////////////////////////////////////////////////////////////

import Foundation
import BlinkConfig
import ios_system

@_cdecl("fleetexec_main")
public func fleetexec_main(argc: Int32, argv: Argv) -> Int32 {
  let args = argv.args(count: argc)
  guard args.count > 2 else {
    fputs("usage: fleetexec <host> <command...>\n", thread_stderr)
    return 1
  }
  let host = args[1]
  let command = args[2...].joined(separator: " ")

  let sema = DispatchSemaphore(value: 0)
  var outText = ""
  var errText = ""
  var exit: Int32 = 0
  var failure: String? = nil

  Task {
    defer { sema.signal() }
    do {
      // Same resolution + auth as the App Intent and the interactive `ssh <alias>`.
      let r = try await HeadlessSSHRunner.run(alias: host, command: command, acceptUnknownHostKeys: true)
      outText = r.stdout
      errText = r.stderr
      exit = r.exitCode ?? 0
    } catch {
      failure = (error as? LocalizedError)?.errorDescription ?? "\(error)"
    }
  }
  sema.wait()

  if let f = failure {
    fputs("fleetexec: \(f)\n", thread_stderr)
    return 1
  }
  if !outText.isEmpty {
    fputs(outText.hasSuffix("\n") ? outText : outText + "\n", thread_stdout)
  }
  if !errText.isEmpty {
    fputs(errText.hasSuffix("\n") ? errText : errText + "\n", thread_stderr)
  }
  return exit
}
