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
  public let exitOK: Bool
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

    var cancellable: AnyCancellable?
    var collected = Data()
    var resumed = false

    return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<HeadlessSSHResult, Error>) in
      cancellable = SSHClient.dial(host, with: config)
        .flatMap { client in client.requestExec(command: command) }
        .flatMap { stream in stream.read(max: Int(SSIZE_MAX)) }
        .sink(
          receiveCompletion: { completion in
            guard !resumed else { return }
            resumed = true
            switch completion {
            case .failure(let error):
              cont.resume(throwing: HeadlessSSHError.ssh(error.localizedDescription))
            case .finished:
              let out = String(decoding: collected, as: UTF8.self)
              cont.resume(returning: HeadlessSSHResult(stdout: out, exitOK: true))
            }
            _ = cancellable  // retain until completion
          },
          receiveValue: { (data: DispatchData) in
            collected.append(contentsOf: data)
          }
        )
    }
  }
}
