import Foundation

/// Builds the remote command that runs an arbitrary multi-line script under an interpreter,
/// for the "Run Fleet Script" App Intent. The script is base64-encoded and piped through
/// `base64 --decode` into the interpreter — so any content (quotes, newlines, shell
/// metacharacters, `$(...)`) is carried literally with zero escaping/injection risk, and the
/// whole thing stays a single-line pipeline that composes cleanly with ExitTrailer.wrap.
/// `base64 --decode` and stdin-reading interpreters (bash/sh/zsh/python3) work on the fleet's
/// macOS and Linux nodes alike (verified).
public enum FleetScript {
  public static func command(script: String, interpreter: String) -> String {
    let b64 = Data(script.utf8).base64EncodedString()
    return "printf %s '\(b64)' | base64 --decode | \(interpreter)"
  }
}
