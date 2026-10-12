import Foundation

// Pure rules for `blinkshell://` session links: what a link asks for, and whether Blink
// runs it, asks first, or refuses.
//
//   blinkshell://run?cmd=<command>[&id=<token>][&key=<secret>]
//   blinkshell://host/<alias>[?cmd=<command>&mosh=1&id=<token>&key=<secret>]
//   blinkshell://focus?id=<token>
//
// `id` names the session: a later link with the same id goes back to it instead of opening
// another. A link is text anyone can put in a web page or a message, so nothing runs unless
// the user turned link actions on, and a command runs unasked only with the user's own key.
public struct SessionLink: Equatable {
  public enum Kind: Equatable { case run, host, focus }

  public let kind: Kind
  /// The line handed to Blink's shell. Empty for `focus`.
  public let command: String
  public let id: String?
  public let key: String?

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
    let key = value("key").flatMap { $0.isEmpty ? nil : $0 }
    let cmd = (value("cmd") ?? "").trimmingCharacters(in: .whitespaces)
    guard isSafeCommand(cmd) else { return .failure(.badCommand) }

    switch action {
    case "run":
      guard !cmd.isEmpty else { return .failure(.missingCommand) }
      return .success(SessionLink(kind: .run, command: cmd, id: id, key: key))
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
      return .success(SessionLink(kind: .host, command: command, id: id, key: key))
    default:
      guard id != nil else { return .failure(.badID) }
      return .success(SessionLink(kind: .focus, command: "", id: id, key: key))
    }
  }

  static func isToken(_ s: String, maxLength: Int, extra: String = "") -> Bool {
    guard !s.isEmpty, s.count <= maxLength else { return false }
    let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-" + extra)
    return s.unicodeScalars.allSatisfy { allowed.contains($0) }
  }

  static func isSafeCommand(_ s: String) -> Bool {
    s.count <= maxCommandLength
      && s.rangeOfCharacter(from: .controlCharacters) == nil
      && s.rangeOfCharacter(from: .newlines) == nil
  }
}

public enum SessionLinkPolicy {
  public enum Decision: Equatable {
    case refuse     // link actions are off
    case run        // go ahead without asking
    case confirm    // show the command and ask
  }

  /// Going back to a session the user already opened runs nothing, so it needs no key.
  /// A command runs unasked only when the link carries the user's key.
  public static func decide(link: SessionLink, sessionExists: Bool, enabled: Bool, userKey: String) -> Decision {
    guard enabled else { return .refuse }
    if link.kind == .focus || sessionExists { return .run }
    if !userKey.isEmpty, let key = link.key, key == userKey { return .run }
    return .confirm
  }

  /// A new random key for the settings screen.
  public static func makeKey() -> String {
    let letters = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
    return String((0..<16).map { _ in letters[Int.random(in: 0..<letters.count)] })
  }
}
