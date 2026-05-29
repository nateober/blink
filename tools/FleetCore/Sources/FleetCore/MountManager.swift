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

  /// Return `base` if free, else the lowest `base-N` (N≥2) not in `existing`.
  /// Callers pass the already-sanitized base name.
  public static func uniqueName(base: String, existing: [String]) -> String {
    let set = Set(existing)
    if !set.contains(base) { return base }
    var n = 2
    while set.contains("\(base)-\(n)") { n += 1 }
    return "\(base)-\(n)"
  }
}
