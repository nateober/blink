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

/// SSHError is not a LocalizedError, so its `localizedDescription` is the useless
/// "operation couldn't be completed (SSH.SSHError error N.)". Reach for its real
/// `.description` ("Could not authenticate. Tried …", "Connection Error: …") instead.
private func describeSSH(_ error: Error) -> String {
  if let e = error as? SSHError { return e.description }
  if let e = error as? LocalizedError, let d = e.errorDescription { return d }
  return "\(error)"
}

public enum HeadlessSSHRunner {
  /// Run `command` on the saved Blink host `alias` over SSH and return captured output.
  ///
  /// Resolves and authenticates the SAME way the interactive `ssh <alias>` command does —
  /// via `BKConfig` + an `SSHAgent` loaded with the host's signers (or the DEFAULT signers
  /// when the host binds no explicit key), plus keyboard-interactive answered with the host's
  /// stored password. Hand-rolling `AuthPublicKey(hostKey)+AuthPassword` (the old approach) is
  /// why the App Intent failed with `authFailed` where the terminal worked: Blink moved to a
  /// pure-agent model (see SSHConfigProvider), and most hosts authenticate via a default key
  /// or keyboard-interactive, neither of which the narrow path tried.
  public static func run(
    alias: String,
    command: String,
    overallTimeout: TimeInterval = 30,
    acceptUnknownHostKeys: Bool = true
  ) async throws -> HeadlessSSHResult {
    let bkConfig = try BKConfig()
    let host = try bkConfig.bkSSHHost(alias)
    let hostName = host.hostName ?? alias

    // Build the agent exactly like SSHConfigProvider.agent(for:): host signers, else defaults.
    let logger = PassthroughSubject<String, Never>()
    let agent = SSHAgent()
    let consts: [SSHAgentConstraint] = [SSHConstraintTrustedConnectionOnly()]
    let signers = bkConfig.signer(forHost: host) ?? bkConfig.defaultSigners()
    signers.forEach { (signer, name) in agent.loadKey(signer, aka: name, constraints: consts) }
    if let defaultAgent = SSHDefaultAgent.instance { agent.linkTo(agent: defaultAgent) }

    // Headless: answer any keyboard/password-interactive prompt with the stored host password
    // (the terminal would read it from the TTY; there is none here).
    let pw = host.password
    let answer: AuthKeyboardInteractive.RequestAnswersCb = { prompt in
      Just(prompt.userPrompts.map { _ in pw ?? "" })
        .setFailureType(to: Error.self).eraseToAnyPublisher()
    }
    var authMethods: [AuthMethod] = [AuthAgent(agent)]
    if let pw = pw, !pw.isEmpty { authMethods.append(AuthPassword(with: pw)) }
    authMethods.append(AuthKeyboardInteractive(requestAnswers: answer, wrongRetriesAllowed: 1))

    // Owner running against their own fleet: trust on first use (host may not be in known_hosts).
    let verify: SSHClientConfig.RequestVerifyHostCallback? = { _ in
      Just(acceptUnknownHostKeys ? InteractiveResponse.affirmative : InteractiveResponse.negative)
        .setFailureType(to: Error.self).eraseToAnyPublisher()
    }

    let config = host.sshClientConfig(
      authMethods: authMethods, verifyHostCallback: verify, agent: agent, logger: logger)

    // Wrap so the remote shell emits its $? as a trailing sentinel line we can parse —
    // the SSH framework does not expose the channel exit status (see ExitTrailer).
    let wrapped = ExitTrailer.wrap(command)

    return try await runOnce(
      host: hostName, config: config, wrappedCommand: wrapped, overallTimeout: overallTimeout)
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
                finish { cont.resume(throwing: HeadlessSSHError.ssh(describeSSH(error))) }
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
