import Foundation

/// In-band remote exit-status protocol. The vendored SSH framework does not expose
/// `ssh_channel_get_exit_status` (its `Stream.channel` is internal, and upstream
/// `ssh.swift` never reads the remote exit status either), so a headless exec wraps
/// its command to print a sentinel trailer carrying `$?`, which `parse` strips back
/// off the captured stdout. Pure + deterministic so it is unit-tested Mac-native.
public enum ExitTrailer {
  static let prefix = "__BLINK_EXIT_"
  static let suffix = "__"

  /// Wrap a user command so its exit status is emitted on its own trailing line.
  /// Works in POSIX sh / bash / zsh (Nate's fleet shells).
  public static func wrap(_ command: String) -> String {
    "{ \(command)\n; } ; printf '\\n\(prefix)%d\(suffix)\\n' \"$?\""
  }

  public struct Result: Equatable {
    public let output: String
    public let exitCode: Int32?
  }

  /// Split the trailing `__BLINK_EXIT_<n>__` line off captured stdout.
  /// Returns the cleaned output and the parsed code (nil if no valid trailer present).
  public static func parse(_ raw: String) -> Result {
    let lines = raw.split(separator: "\n", omittingEmptySubsequences: false)
    guard let last = lines.last(where: { !$0.isEmpty }),
          last.hasPrefix(prefix), last.hasSuffix(suffix) else {
      return Result(output: raw, exitCode: nil)
    }
    let inner = last.dropFirst(prefix.count).dropLast(suffix.count)
    guard let code = Int32(inner) else { return Result(output: raw, exitCode: nil) }
    // Drop the marker line plus exactly one separator newline before it.
    if let range = raw.range(of: "\n" + last) {
      return Result(output: String(raw[raw.startIndex..<range.lowerBound]), exitCode: code)
    }
    if let range = raw.range(of: String(last)) {
      return Result(output: String(raw[raw.startIndex..<range.lowerBound]), exitCode: code)
    }
    return Result(output: raw, exitCode: code)
  }
}
