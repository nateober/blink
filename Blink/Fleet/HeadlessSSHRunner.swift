//////////////////////////////////////////////////////////////////////////////////
//
// B L I N K  —  fleet-native fork
//
// HeadlessSSHRunner: run a single command on a host over SSH (no PTY) and capture
// stdout, with no terminal/TermDevice. Built directly on the SSH framework's
// SSHClient.dial → requestExec → Stream.read pipeline (Combine), bridged to async.
// Auth is explicit (private key and/or password); host key is auto-accepted (these
// are Nate's own fleet hosts). Used by RunFleetCommandIntent (App Intents / Shortcuts).
//
// Blink is free software under the GNU GPL v3; see <http://www.github.com/blinksh/blink>.
//
//////////////////////////////////////////////////////////////////////////////////

import Foundation
import Combine
import SSH
import BlinkConfig

public struct HeadlessSSHResult: Sendable {
  public let stdout: String
  public let stderr: String
  public let exitCode: Int32?   // nil = could not be determined
  public var exitOK: Bool { (exitCode ?? 0) == 0 }
}

public enum HeadlessSSHError: Error, LocalizedError {
  case noAuth
  case ssh(String)
  public var errorDescription: String? {
    switch self {
    case .noAuth: return "No SSH credentials provided (need a private key or password)."
    case .ssh(let m): return m
    }
  }
}

public enum HeadlessSSHRunner {
  /// Run `command` on `user@host:port` over SSH and return captured stdout.
  /// - Auth: `privateKey` (PEM string) and/or `password`. At least one required.
  /// - Host-key verification is auto-accepted (personal fleet).
  public static func run(
    host: String,
    user: String,
    port: String = "22",
    command: String,
    privateKey: String? = nil,
    password: String? = nil,
    connectionTimeout: Int = 30,
    overallTimeout: TimeInterval = 30,
    acceptUnknownHostKeys: Bool = false
  ) async throws -> HeadlessSSHResult {
    var authMethods: [AuthMethod] = []
    if let pk = privateKey, !pk.isEmpty { authMethods.append(AuthPublicKey(privateKey: pk)) }
    if let pw = password, !pw.isEmpty { authMethods.append(AuthPassword(with: pw)) }
    guard !authMethods.isEmpty else { throw HeadlessSSHError.noAuth }

    let config = SSHClientConfig(
      user: user,
      port: port,
      authMethods: authMethods,
      // Fail closed: hosts already in Blink's known_hosts pass without hitting this
      // callback; unknown/changed keys are REJECTED (not blindly accepted) unless the
      // caller explicitly opts in. Matters on untrusted networks (hotel/airport WiFi).
      verifyHostCallback: { _ in
        Just(acceptUnknownHostKeys ? InteractiveResponse.affirmative : InteractiveResponse.negative)
          .setFailureType(to: Error.self).eraseToAnyPublisher()
      },
      connectionTimeout: connectionTimeout,
      sshDirectory: BlinkPaths.ssh()
    )

    // Wrap so the remote shell emits its $? as a trailing sentinel line we can parse —
    // the SSH framework does not expose the channel exit status (see ExitTrailer).
    let wrapped = ExitTrailer.wrap(command)

    return try await runOnce(
      host: host, config: config, wrappedCommand: wrapped, overallTimeout: overallTimeout)
  }

  private static func runOnce(
    host: String,
    config: SSHClientConfig,
    wrappedCommand: String,
    overallTimeout: TimeInterval
  ) async throws -> HeadlessSSHResult {
    // CRITICAL: Blink's SSH framework schedules all I/O on the RunLoop captured at
    // SSHClient.init (`self.rloop = RunLoop.current`, via `.subscribe(on: rloop)`), and
    // only makes progress while that run loop is *running*. The interactive `ssh` command
    // works because it spins its thread's run loop (ssh.swift `awaitRunLoop` → CFRunLoopRun).
    // Run on the Swift-concurrency pool — which never spins a run loop — and the connection
    // simply hangs (App Intent then dies with a generic "unknown error"). So we dial on a
    // dedicated Thread and drive its run loop until the pipeline completes, mirroring the
    // interactive path. The deadline timer doubles as the keep-alive source and the timeout.
    return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<HeadlessSSHResult, Error>) in
      let thread = Thread {
        var cancellable: AnyCancellable?
        var outData = Data()
        var errData = Data()
        var finished = false
        let cf = CFRunLoopGetCurrent()

        func finish(_ resume: () -> Void) {
          if finished { return }
          finished = true
          resume()
          cancellable?.cancel()
          CFRunLoopStop(cf)
        }

        cancellable = SSHClient.dial(host, with: config)
          .flatMap { client in client.requestExec(command: wrappedCommand) }
          .flatMap { (stream: SSH.Stream) in
            // Read stdout and stderr to EOF; the channel completes when both drain.
            Publishers.Zip(
              stream.read(max: Int(SSIZE_MAX)),
              stream.read_err(max: Int(SSIZE_MAX))
            )
          }
          .sink(
            receiveCompletion: { completion in
              switch completion {
              case .failure(let error):
                finish { cont.resume(throwing: HeadlessSSHError.ssh(error.localizedDescription)) }
              case .finished:
                let parsed = ExitTrailer.parse(String(decoding: outData, as: UTF8.self))
                let err = String(decoding: errData, as: UTF8.self)
                finish {
                  cont.resume(returning: HeadlessSSHResult(
                    stdout: parsed.output, stderr: err, exitCode: parsed.exitCode))
                }
              }
            },
            receiveValue: { (out: DispatchData, err: DispatchData) in
              outData.append(contentsOf: out)
              errData.append(contentsOf: err)
            }
          )

        // If dial failed synchronously, the continuation already resumed — don't run the loop.
        if !finished {
          let deadline = Timer(timeInterval: overallTimeout, repeats: false) { _ in
            finish { cont.resume(throwing: HeadlessSSHError.ssh("timed out after \(Int(overallTimeout))s")) }
          }
          RunLoop.current.add(deadline, forMode: .default)
          CFRunLoopRun()
          deadline.invalidate()
        }
        cancellable?.cancel()
      }
      thread.name = "blink.fleet.ssh"
      thread.stackSize = 2 << 20
      thread.start()
    }
  }
}
