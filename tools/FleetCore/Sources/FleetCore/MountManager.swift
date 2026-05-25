import Foundation

/// Pure path logic for mounting picked folders into Blink's home namespace.
///
/// The actual symlink-into-`~` action lives in the Blink app layer (it uses
/// `BlinkPaths`/`Local` and security-scoped access). These helpers are the
/// UIKit-free, unit-tested core: where a mount lands and what PATH fragment it
/// contributes.
public enum MountManager {
  /// Filesystem location a named mount is exposed at, e.g. `~/mnt/<name>`.
  public static func mountPoint(home: String, name: String) -> String {
    "\(home)/mnt/\(sanitized(name: name))"
  }

  /// PATH entry contributed by a mount that opted into `addToPath` (its `bin/`).
  public static func pathFragment(home: String, name: String) -> String {
    mountPoint(home: home, name: name) + "/bin"
  }

  /// Make a user-supplied mount name safe as a single path component:
  /// strip path separators and parent refs, collapse to a dash, trim, fall back to "mount".
  public static func sanitized(name: String) -> String {
    var s = name.trimmingCharacters(in: .whitespacesAndNewlines)
    // drop leading parent-dir refs like "../"
    while s.hasPrefix("../") { s.removeFirst(3) }
    if s == ".." { s = "" }
    s = s.replacingOccurrences(of: "/", with: "-")
         .replacingOccurrences(of: "\\", with: "-")
    s = s.trimmingCharacters(in: .whitespacesAndNewlines)
    return s.isEmpty ? "mount" : s
  }
}
