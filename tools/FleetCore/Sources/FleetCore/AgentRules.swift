import Foundation

// Pure rules for working with coding agents in tmux on the fleet: what a tmux window
// title says about the pane in front, where a tap on an "agent needs you" push lands,
// what a finished dictation does there, and how the session switcher reads a host's
// session list.

/// The window title tmux reports when `set-titles` is on with `TmuxTitle.format`.
/// `tm` sets that format on every fleet host, so the app can tell which host and session
/// a tab is attached to and what program is in front, without asking the host.
public struct TmuxTitle: Equatable {
  public static let separator = " › "
  /// The value for tmux's `set-titles-string`.
  public static let format = "#h › #S › #{pane_current_command} › #T"

  public let host: String
  public let session: String
  /// The foreground program in the active pane (`zsh`, `vim`, a version number for Claude Code).
  public let command: String
  /// The title the pane's own program set. May itself contain the separator.
  public let paneTitle: String

  public static func parse(_ title: String?) -> TmuxTitle? {
    guard let title else { return nil }
    let parts = title.components(separatedBy: separator)
    guard parts.count >= 4, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
    return TmuxTitle(
      host: parts[0],
      session: parts[1],
      command: parts[2],
      paneTitle: parts[3...].joined(separator: separator))
  }

  /// Programs that take a prompt, by name.
  static let agentCommands: Set<String> = ["claude", "codex", "gemini", "aider", "opencode", "amp"]

  /// True when a coding agent is in front. Claude Code shows up as its version number
  /// (`2.1.322`) with a title that starts with a star or a spinner frame.
  public var isAgent: Bool {
    if Self.agentCommands.contains(command.lowercased()) { return true }
    guard let first = paneTitle.unicodeScalars.first else { return false }
    let marked = first.value == 0x2733 || (0x2800...0x28FF).contains(first.value)
    let versionLike = command.range(of: #"^\d+\.\d+\.\d+"#, options: .regularExpression) != nil
    return marked && (versionLike || command.lowercased() == "node")
  }

  /// A short label for lists and the tab strip: the session, and the agent's task if any.
  public var label: String {
    let task = paneTitle.drop(while: { !$0.isLetter && !$0.isNumber })
    return task.isEmpty || !isAgent ? session : "\(session): \(task)"
  }
}

/// Where a tap on an agent push goes.
public enum AgentRoute: Equatable {
  /// A tab is already attached to that session: go to it.
  case focus(index: Int)
  /// No tab has it: open one with this command.
  case open(command: String)
  /// The push names a host Blink has no entry for, or a session name that can't be real.
  case ignore

  public static let maxSessionLength = 64

  public static func isSessionName(_ s: String) -> Bool {
    !s.isEmpty && s.count <= maxSessionLength
      && s.rangeOfCharacter(from: .controlCharacters) == nil
      && s.rangeOfCharacter(from: .newlines) == nil
  }

  /// The command that attaches to a session on a host. The session name travels as hex so
  /// no quoting has to survive Blink's shell, mosh and the remote shell; `blink-attach` on
  /// the host decodes it.
  public static func attachCommand(alias: String, session: String) -> String {
    "mosh \(alias) -- blink-attach \(VoiceInsert.hex(session))"
  }

  /// - Parameters:
  ///   - host: the host the push names (tmux's `#h`).
  ///   - alias: the Blink host entry that reaches it, nil when there is none.
  ///   - titles: the window title of each open tab, in tab order.
  public static func decide(host: String, session: String, alias: String?, titles: [String?]) -> AgentRoute {
    guard isSessionName(session), !host.isEmpty else { return .ignore }
    for (index, raw) in titles.enumerated() {
      guard let title = TmuxTitle.parse(raw) else { continue }
      if title.session == session && title.host.caseInsensitiveCompare(host) == .orderedSame {
        return .focus(index: index)
      }
    }
    guard let alias, SessionLink.isToken(alias, maxLength: 253), !alias.hasPrefix("-") else { return .ignore }
    return .open(command: attachCommand(alias: alias, session: session))
  }

  /// A push banner for the session already on screen says nothing new.
  public static func showsBanner(host: String?, session: String?, frontTitle: String?, appActive: Bool) -> Bool {
    guard appActive, let host, let session, let front = TmuxTitle.parse(frontTitle) else { return true }
    return !(front.session == session && front.host.caseInsensitiveCompare(host) == .orderedSame)
  }
}

/// What the dictation key does with finished words.
public enum DictationTarget: Equatable {
  /// Type them at the cursor (shell, vim, anything else).
  case type
  /// Put them in the compose area in Prompt mode, to edit and send to the agent.
  case compose

  public static func choose(title: String?, promptModeForAgents: Bool) -> DictationTarget {
    guard promptModeForAgents, let parsed = TmuxTitle.parse(title), parsed.isAgent else { return .type }
    return .compose
  }
}

/// One tmux session on a host, as `blink-sessions` prints it: tab-separated
/// `name, windows, attached clients, last activity (epoch), state, host, pane title`.
public struct FleetSession: Equatable {
  public enum State: String, Equatable {
    case needsInput = "needs_input"
    case done
    case running
    case none = "-"

    /// Lower sorts first in the switcher.
    var rank: Int {
      switch self {
      case .needsInput: return 0
      case .done: return 1
      case .running: return 2
      case .none: return 3
      }
    }
  }

  /// The Blink host entry the list came from.
  public let alias: String
  /// What the host calls itself (tmux's `#h`), which is what window titles and pushes carry.
  public let host: String
  public let name: String
  public let windows: Int
  public let attached: Int
  public let activity: Date
  public let state: State
  public let title: String

  public static func parse(alias: String, output: String) -> [FleetSession] {
    output.split(whereSeparator: \.isNewline).compactMap { line in
      let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
      guard f.count >= 7, AgentRoute.isSessionName(f[0]), !f[5].isEmpty else { return nil }
      return FleetSession(
        alias: alias,
        host: f[5],
        name: f[0],
        windows: Int(f[1]) ?? 1,
        attached: Int(f[2]) ?? 0,
        activity: Date(timeIntervalSince1970: TimeInterval(f[3]) ?? 0),
        state: State(rawValue: f[4]) ?? .none,
        title: f[6...].joined(separator: "\t"))
    }
  }

  /// The command the switcher runs on each host. The PATH covers a host whose
  /// non-interactive shell doesn't set one up.
  public static let listCommand =
    "PATH=\"$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH\" blink-sessions"

  /// Sessions waiting on the user first, then finished, then by most recent activity.
  public static func sorted(_ sessions: [FleetSession]) -> [FleetSession] {
    sessions.sorted {
      if $0.state.rank != $1.state.rank { return $0.state.rank < $1.state.rank }
      if $0.activity != $1.activity { return $0.activity > $1.activity }
      return ($0.alias, $0.name) < ($1.alias, $1.name)
    }
  }

  /// The agent's task without its marker, or empty when the pane isn't an agent's.
  public var task: String {
    guard let first = title.unicodeScalars.first,
          first.value == 0x2733 || (0x2800...0x28FF).contains(first.value) else { return "" }
    return String(title.drop(while: { !$0.isLetter && !$0.isNumber }))
  }

  public func age(now: Date) -> String {
    let s = max(0, Int(now.timeIntervalSince(activity)))
    if s < 60 { return "now" }
    if s < 3600 { return "\(s / 60)m" }
    if s < 86400 { return "\(s / 3600)h" }
    return "\(s / 86400)d"
  }
}

/// Sending a clipboard image to a host so an agent there can look at it: the file lands in
/// `~/Scratch/blink-paste/` and its path is typed at the cursor.
public enum PasteUpload {
  public static let directory = "Scratch/blink-paste"
  /// Files older than this are cleared out of the directory on each upload.
  public static let keepDays = 7
  /// Longest side sent, in pixels. A phone screenshot is larger than an agent needs.
  public static let maxSide: Double = 2000
  /// Base64 characters per command, well inside what a remote shell accepts on one line.
  public static let chunkSize = 180_000

  public static func fileName(at date: Date, timeZone: TimeZone = .current) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = timeZone
    f.dateFormat = "yyyyMMdd-HHmmss"
    return "blink-\(f.string(from: date)).jpg"
  }

  public static func scaledSize(width: Double, height: Double) -> (width: Double, height: Double) {
    let longest = max(width, height)
    guard longest > maxSide, longest > 0 else { return (width, height) }
    let k = maxSide / longest
    return ((width * k).rounded(), (height * k).rounded())
  }

  /// The commands that write the image on the host, in order. The last one prints the
  /// file's full path. `fileName` must come from `fileName(at:)`.
  public static func commands(base64: String, fileName: String) -> [String] {
    let dir = "\"$HOME/\(directory)\""
    let part = "\(dir)/\(fileName).b64"
    let begin = "mkdir -p \(dir) && find \(dir) -type f -mtime +\(keepDays) -delete; : > \(part)"
    let finish = "base64 --decode < \(part) > \(dir)/\(fileName) && rm -f \(part) && printf %s \(dir)/\(fileName)"

    var chunks: [String] = []
    var rest = Substring(base64)
    while !rest.isEmpty {
      chunks.append(String(rest.prefix(chunkSize)))
      rest = rest.dropFirst(chunkSize)
    }
    var out = chunks.map { "printf %s '\($0)' >> \(part)" }
    guard !out.isEmpty else { return [] }
    out[0] = begin + " && " + out[0]
    out[out.count - 1] += " && " + finish
    return out
  }

  /// What gets typed once the upload is done: the path the host printed and a space, or nil
  /// when the answer isn't the path we asked for.
  public static func typedText(stdout: String, fileName: String) -> String? {
    let path = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    guard path.hasPrefix("/"), path.hasSuffix("/\(directory)/\(fileName)"),
          path.rangeOfCharacter(from: .controlCharacters) == nil,
          !path.contains(" "), !path.contains("'"), !path.contains("\"")
    else { return nil }
    return path + " "
  }
}
