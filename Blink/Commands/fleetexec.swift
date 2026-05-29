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
    // Resolve host config the same way RunFleetCommandIntent does.
    guard let h = await MainActor.run(body: { BKHosts.withHost(host) }) else {
      failure = "No Blink host named '\(host)'. Add it in Blink (config → Hosts) first."
      return
    }
    let user = (h.user?.isEmpty == false) ? h.user! : NSUserName()
    let hostName = (h.hostName?.isEmpty == false) ? h.hostName! : host
    var pem: String? = nil
    if let keyName = h.key, let card = await MainActor.run(body: { BKPubKey.withID(keyName) }) {
      pem = card.loadPrivateKey()
    }
    let password = h.password
    do {
      let r = try await HeadlessSSHRunner.run(
        host: hostName, user: user, command: command,
        privateKey: pem, password: password,
        acceptUnknownHostKeys: true
      )
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
