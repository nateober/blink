import Foundation

/// Pure `$PATH` string manipulation for mounting folders' executables/scripts onto the
/// shell search path. UIKit-free + unit-tested; the app layer resolves security-scoped
/// folder URLs, calls these to build the new PATH, and `setenv`s it.
public enum PathManager {
  private static let sep = ":"

  /// Prepend `dirs` (in order) to `path`, skipping any already present and any duplicates
  /// within `dirs`. Existing entries keep their position.
  public static func prepend(_ dirs: [String], to path: String) -> String {
    let existing = path.isEmpty ? [] : path.components(separatedBy: sep)
    var seen = Set(existing)
    var front: [String] = []
    for d in dirs where !d.isEmpty && !seen.contains(d) {
      seen.insert(d)
      front.append(d)
    }
    let all = front + existing
    return all.joined(separator: sep)
  }

  /// Remove `dir` from `path` (all occurrences).
  public static func remove(_ dir: String, from path: String) -> String {
    guard !path.isEmpty else { return "" }
    return path.components(separatedBy: sep).filter { $0 != dir }.joined(separator: sep)
  }
}
