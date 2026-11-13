import Foundation

// Pure rules for keeping a mosh tab alive: telling from what mosh prints that its server
// is gone, and choosing the command that brings the tab back.

/// Watches what a mosh client prints. A mosh client cannot rejoin its server without the
/// state it had, and the client itself only says "Last contact …" forever when the server
/// is gone (host rebooted, server timed out). While it has no contact it prints a blue
/// banner on the first row and then rewrites the seconds once a second (every third second
/// after a minute); with contact and nothing happening it prints nothing. So a banner that
/// keeps ticking is a client with no server.
public struct MoshLiveness {
  /// How long the banner has to keep ticking before the server counts as gone. mosh shows
  /// it only after about 9 s without contact, so this is on top of that.
  public static let bannerSeconds: TimeInterval = 12
  /// Banner updates further apart than this are separate outages (or the app was frozen).
  public static let bannerGap: TimeInterval = 5
  /// Bytes of ordinary output that show a new client has heard from its server at least
  /// once (its own start-up sequence is under 100).
  public static let contactBytes = 200

  static let attributes = Array("\u{1b}[0;1;37;44m".utf8)
  static let lead = Array("mosh: ".utf8)
  static let firstRow = Array("\u{1b}[1;".utf8)

  /// False for a new client until its server has answered. A client that never had contact
  /// (UDP blocked on this network) gains nothing from being started again.
  public private(set) var hadContact: Bool
  private var plainBytes = 0
  private var lossStart: TimeInterval?
  private var lastBanner: TimeInterval?

  /// - Parameter restored: the client was restored from a saved state, so it had contact
  ///   in its earlier life.
  public init(restored: Bool) {
    hadContact = restored
  }

  public enum Kind: Equatable {
    /// The banner drawn in full ("mosh: Last contact 9 seconds ago. …").
    case banner
    /// The banner's counter being rewritten.
    case tick
    case other
  }

  public static func kind(of chunk: [UInt8]) -> Kind {
    guard let at = index(of: attributes, in: chunk) else { return .other }
    if contains(chunk, lead) { return .banner }
    // A rewrite moves to the first row and sets the banner's colours; the terminal layer
    // puts a hide-cursor in front and a cursor restore behind.
    if chunk.count <= 120, contains(Array(chunk[..<at]), firstRow) { return .tick }
    return .other
  }

  /// - Parameters:
  ///   - chunk: one read of the client's output, or its first few kilobytes.
  ///   - length: the full size of the read when `chunk` is only its start.
  public mutating func saw(_ chunk: [UInt8], length: Int? = nil, at now: TimeInterval) {
    let kind = Self.kind(of: chunk)
    if kind == .other {
      plainBytes += length ?? chunk.count
      if plainBytes >= Self.contactBytes { hadContact = true }
      return
    }
    // A tick only counts as part of an outage a full banner started.
    if let last = lastBanner, now - last <= Self.bannerGap, lossStart != nil {
      lastBanner = now
    } else if kind == .banner {
      lossStart = now
      lastBanner = now
    } else {
      lossStart = nil
      lastBanner = nil
    }
  }

  /// True when the banner has been up and ticking long enough. The caller still checks
  /// that the host answers before acting: offline looks the same from here.
  public func looksDead(at now: TimeInterval) -> Bool {
    guard hadContact, let start = lossStart, let last = lastBanner else { return false }
    return now - last <= Self.bannerGap && now - start >= Self.bannerSeconds
  }

  private static func contains(_ haystack: [UInt8], _ needle: [UInt8]) -> Bool {
    index(of: needle, in: haystack) != nil
  }

  private static func index(of needle: [UInt8], in haystack: [UInt8]) -> Int? {
    guard haystack.count >= needle.count else { return nil }
    for i in 0...(haystack.count - needle.count) where haystack[i] == needle[0] {
      if haystack[i..<(i + needle.count)].elementsEqual(needle) { return i }
    }
    return nil
  }
}

/// The command that brings a mosh tab back after its connection is lost for good.
public enum MoshReconnect {
  /// Auto-reconnects closer together than this are refused: something else is wrong.
  public static let minInterval: TimeInterval = 60

  /// - Parameters:
  ///   - original: the mosh command the tab was started with.
  ///   - session: the tmux session the tab was last showing (from its window title), if any.
  /// A plain `mosh host` would land wherever the host's login puts it, so it is pointed at
  /// the session; a `blink-attach` command is pointed at the session the tab moved to.
  /// Anything else the user wrote after `--` is run again as it was.
  public static func command(original: String, session: String?) -> String {
    let command = original.trimmingCharacters(in: .whitespaces)
    guard let session, command.hasPrefix("mosh "), AgentRoute.isSessionName(session) else { return command }

    if let range = command.range(of: " -- ") {
      let remote = command[range.upperBound...].split(separator: " ").map(String.init)
      if remote.count == 2, remote[0] == "blink-attach" {
        return command[..<range.upperBound] + "blink-attach " + VoiceInsert.hex(session)
      }
      // The ending this function adds itself: follow the tab to another session.
      if remote.count == 5, Array(remote[0..<4]) == attach, isPlainName(session) {
        return command[..<range.upperBound] + (attach + [session]).joined(separator: " ")
      }
      return command
    }
    guard isPlainName(session) else { return command }
    return command + " -- " + (attach + [session]).joined(separator: " ")
  }

  static let attach = ["tmux", "new-session", "-A", "-s"]

  /// A session name that needs no quoting on its way through Blink, mosh and the host's shell.
  static func isPlainName(_ s: String) -> Bool {
    !s.hasPrefix("-") && s.range(of: #"^[A-Za-z0-9_.@+-]{1,64}$"#, options: .regularExpression) != nil
  }

  public static func allows(lastReconnect: TimeInterval?, now: TimeInterval) -> Bool {
    guard let lastReconnect else { return true }
    return now - lastReconnect >= minInterval
  }
}
