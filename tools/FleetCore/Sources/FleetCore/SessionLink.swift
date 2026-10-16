import Foundation
import CryptoKit

// Pure rules for `blinkshell://` session links: what a link asks for, and whether Blink
// runs it, asks first, or refuses.
//
//   blinkshell://run?cmd=<command>[&id=<token>][&sig=<signature>]
//   blinkshell://host/<alias>[?cmd=<command>&mosh=1&id=<token>&sig=<signature>]
//   blinkshell://focus?id=<token>
//
// `id` names the session: a later link with the same id goes back to it instead of opening
// another. A link is text anyone can put in a web page or a message, so nothing runs unless
// the user turned link actions on, and a command runs unasked only when the link carries a
// signature made on this device with the user's key. The signature covers the whole link, so
// a link that leaks can only ever run its own command.
public struct SessionLink: Equatable {
  public enum Kind: Equatable { case run, host, focus }

  public let kind: Kind
  /// The line handed to Blink's shell. Empty for `focus`.
  public let command: String
  public let id: String?
  public let sig: String?

  public enum ParseError: Error, Equatable {
    case notASessionLink        // another scheme, or a blinkshell link this parser doesn't own
    case missingCommand
    case badCommand             // control characters, a line break, or too long
    case badHost
    case badID
  }

  public static let maxCommandLength = 2000

  public static func parse(_ url: URL) -> Result<SessionLink, ParseError> {
    guard url.scheme?.lowercased() == "blinkshell",
          let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
          let action = components.host?.lowercased(),
          ["run", "host", "focus"].contains(action)
    else { return .failure(.notASessionLink) }

    func value(_ name: String) -> String? {
      components.queryItems?.first(where: { $0.name == name })?.value
    }

    var id: String? = nil
    if let raw = value("id"), !raw.isEmpty {
      guard isToken(raw, maxLength: 64) else { return .failure(.badID) }
      id = raw
    }
    let sig = value("sig").flatMap { $0.isEmpty ? nil : $0 }
    let cmd = (value("cmd") ?? "").trimmingCharacters(in: .whitespaces)
    guard isSafeCommand(cmd) else { return .failure(.badCommand) }

    switch action {
    case "run":
      guard !cmd.isEmpty else { return .failure(.missingCommand) }
      return .success(SessionLink(kind: .run, command: cmd, id: id, sig: sig))
    case "host":
      let alias = String(components.path.drop(while: { $0 == "/" }))
      guard isToken(alias, maxLength: 253, extra: "@"), !alias.hasPrefix("-"), !alias.hasPrefix(".") else {
        return .failure(.badHost)
      }
      let mosh = ["1", "true", "yes"].contains((value("mosh") ?? "").lowercased())
      let command: String
      switch (mosh, cmd.isEmpty) {
      case (false, true): command = "ssh \(alias)"
      case (false, false): command = "ssh -t \(alias) \(cmd)"
      case (true, true): command = "mosh \(alias)"
      case (true, false): command = "mosh \(alias) -- \(cmd)"
      }
      return .success(SessionLink(kind: .host, command: command, id: id, sig: sig))
    default:
      guard id != nil else { return .failure(.badID) }
      return .success(SessionLink(kind: .focus, command: "", id: id, sig: sig))
    }
  }

  static func isToken(_ s: String, maxLength: Int, extra: String = "") -> Bool {
    guard !s.isEmpty, s.count <= maxLength else { return false }
    let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-" + extra)
    return s.unicodeScalars.allSatisfy { allowed.contains($0) }
  }

  /// Hangul fillers and the braille blank draw as nothing but are not format characters.
  private static let blankLetters: Set<UInt32> = [0x115F, 0x1160, 0x3164, 0xFFA0, 0x2800]

  static func isSafeCommand(_ s: String) -> Bool {
    s.count <= maxCommandLength
      && s.rangeOfCharacter(from: .controlCharacters) == nil
      && s.rangeOfCharacter(from: .newlines) == nil
      && !s.unicodeScalars.contains {
        $0.properties.generalCategory == .format || blankLetters.contains($0.value)
      }
  }

  /// True when spacing could push part of the command out of view in the confirmation:
  /// a run of three or more spaces, or any space other than a plain one.
  public static func hidesText(_ s: String) -> Bool {
    var run = 0
    for scalar in s.unicodeScalars {
      guard scalar.properties.isWhitespace else { run = 0; continue }
      if scalar != " " { return true }
      run += 1
      if run >= 3 { return true }
    }
    return false
  }

  /// What the signature covers: the action, the full command (host, mosh and cmd for a host
  /// link) and the id.
  private var signedText: String {
    "\(kind)\n\(command)\n\(id ?? "")"
  }

  public func signature(key: Data) -> String {
    let mac = HMAC<SHA256>.authenticationCode(for: Data(signedText.utf8), using: SymmetricKey(data: key))
    return Data(mac).prefix(16).map { String(format: "%02x", $0) }.joined()
  }

  public func isSigned(with key: Data) -> Bool {
    guard let sig, !key.isEmpty else { return false }
    // Compare every byte so the time taken says nothing about how much matched.
    let expected = Array(signature(key: key).utf8), given = Array(sig.lowercased().utf8)
    guard expected.count == given.count else { return false }
    return zip(expected, given).reduce(0) { $0 | ($1.0 ^ $1.1) } == 0
  }

  /// The same link with this device's signature added, replacing any old `key` or `sig`.
  public static func signedURL(_ url: URL, key: Data) -> Result<URL, ParseError> {
    guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
      return .failure(.notASessionLink)
    }
    components.queryItems = components.queryItems?.filter { $0.name != "key" && $0.name != "sig" }
    if components.queryItems?.isEmpty == true { components.queryItems = nil }
    guard let unsigned = components.url else { return .failure(.notASessionLink) }
    switch parse(unsigned) {
    case .failure(let error):
      return .failure(error)
    case .success(let link):
      components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "sig", value: link.signature(key: key))]
      guard let signed = components.url else { return .failure(.notASessionLink) }
      return .success(signed)
    }
  }
}

public enum SessionLinkPolicy {
  public enum Decision: Equatable {
    case refuse           // link actions are off
    case refuseUnreadable // unsigned, and spacing could hide part of the command
    case run              // go ahead without asking
    case confirm          // show the command and ask
  }

  /// Going back to a session the user already opened runs nothing, so it needs no signature.
  /// A command runs unasked only when the link is signed with the user's key.
  public static func decide(link: SessionLink, sessionExists: Bool, enabled: Bool, signingKey: Data?) -> Decision {
    guard enabled else { return .refuse }
    if link.kind == .focus || sessionExists { return .run }
    if let signingKey, link.isSigned(with: signingKey) { return .run }
    if SessionLink.hidesText(link.command) { return .refuseUnreadable }
    return .confirm
  }

  /// A new random signing key. It stays on the device; only signed links leave it.
  public static func makeKey() -> Data {
    var rng = SystemRandomNumberGenerator()
    return Data((0..<32).map { _ in UInt8.random(in: .min ... .max, using: &rng) })
  }
}
