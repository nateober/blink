import Foundation

/// Builds the remote command that runs an arbitrary multi-line script under an interpreter,
/// for the "Run Fleet Script" App Intent. The script is base64-encoded and decoded into the
/// interpreter's `-c` argument — so any content (quotes, newlines, shell metacharacters,
/// `$(...)`) is carried literally with zero escaping/injection risk, and the whole thing stays
/// one line that composes cleanly with ExitTrailer.wrap. It is an argument rather than stdin
/// so a line that reads stdin (`cat`, `claude -p`) can't swallow the lines after it.
/// `base64 --decode` and `-c` (bash/sh/zsh/python3) work on the fleet's macOS and Linux nodes.
public enum FleetScript {
  public static func command(script: String, interpreter: String) -> String {
    let b64 = Data(script.utf8).base64EncodedString()
    return "\(interpreter) -c \"$(printf %s '\(b64)' | base64 --decode)\""
  }
}
