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

/// POSIX single-quote a shell word (wrap in '…', escaping embedded single quotes).
private func shQuote(_ s: String) -> String {
  "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

@_cdecl("fleetexec_main")
public func fleetexec_main(argc: Int32, argv: Argv) -> Int32 {
  let args = argv.args(count: argc)
  guard args.count > 2 else {
    fputs("usage: fleetexec <host> <command...>\n", thread_stderr)
    return 1
  }
  let host = args[1]
  // argv has already been tokenized/dequoted by the shell, so re-joining with plain spaces
  // would corrupt a command like `claude -p "two words"` (the quoted token would split on the
  // remote side). Re-quote each token so word boundaries survive the round trip.
  let command = args[2...].map(shQuote).joined(separator: " ")

  let sema = DispatchSemaphore(value: 0)
  var outText = ""
  var errText = ""
  var exit: Int32 = 0
  var failure: String? = nil

  Task {
    defer { sema.signal() }
    // Friendly pre-check (mirrors the App Intent): a truly-unknown alias should say so, not
    // fall through to a raw "Socket error: No such file or directory" from the connect attempt.
    guard await MainActor.run(body: { BKHosts.withHost(host) != nil }) else {
      failure = "No Blink host named '\(host)'. Add it in Blink (config → Hosts) first."
      return
    }
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
