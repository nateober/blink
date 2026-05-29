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
  ///
  /// Scans from the END for the LAST marker line, so it is robust to: output that itself
  /// contains a marker-looking line (the real trailer is last), CRLF / trailing whitespace
  /// on the marker line, and trailing blank lines after it. A wrong answer here would hand
  /// a bogus/zero exit code to the App Intent and mask a remote failure as success.
  public static func parse(_ raw: String) -> Result {
    // components(separatedBy:.newlines) normalizes \n / \r\n / \r so a CRLF transport
    // doesn't leave a stray \r on the marker line.
    let lines = raw.components(separatedBy: .newlines)
    var i = lines.count - 1
    while i >= 0 {
      let line = lines[i].trimmingCharacters(in: .whitespaces)
      if line.hasPrefix(prefix), line.hasSuffix(suffix),
         let code = Int32(line.dropFirst(prefix.count).dropLast(suffix.count)) {
        return Result(output: lines[0..<i].joined(separator: "\n"), exitCode: code)
      }
      i -= 1
    }
    return Result(output: raw, exitCode: nil)
  }
}
