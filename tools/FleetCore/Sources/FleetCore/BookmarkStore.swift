import Foundation

public struct ResolvedBookmark {
  public let url: URL
  public let isStale: Bool
}

public enum BookmarkError: Error, Equatable {
  case notFound(String)
  case duplicate(String)
  case unresolvable(String)
}

/// Named security-scoped bookmarks persisted to a plist.
///
/// UIKit-free so it can be unit-tested Mac-native via `swift test`. The Blink app
/// adds this same source file to the `BlinkConfig` framework target and creates the
/// bookmarks with `.withSecurityScope` options; this type only stores/resolves the
/// opaque bookmark `Data`, so it is agnostic to how the bookmark was created.
public final class BookmarkStore {
  private let storeURL: URL
  private var marks: [String: Data]

  public init(storeURL: URL) {
    self.storeURL = storeURL
    self.marks = (try? Data(contentsOf: storeURL)).flatMap {
      try? PropertyListDecoder().decode([String: Data].self, from: $0)
    } ?? [:]
  }

  public func names() -> [String] { marks.keys.sorted() }

  public func add(name: String, bookmark: Data) throws {
    guard marks[name] == nil else { throw BookmarkError.duplicate(name) }
    marks[name] = bookmark
    try persist()
  }

  public func rename(from: String, to: String) throws {
    guard let data = marks[from] else { throw BookmarkError.notFound(from) }
    guard marks[to] == nil else { throw BookmarkError.duplicate(to) }
    marks[to] = data
    marks[from] = nil
    try persist()
  }

  public func delete(name: String) throws {
    guard marks[name] != nil else { throw BookmarkError.notFound(name) }
    marks[name] = nil
    try persist()
  }

  /// Resolve a stored bookmark to a URL. Throws `.unresolvable` for stale/garbage data.
  /// Callers on iOS must `startAccessingSecurityScopedResource()` on the returned URL.
  public func resolve(name: String) throws -> ResolvedBookmark {
    guard let data = marks[name] else { throw BookmarkError.notFound(name) }
    var stale = false
    do {
      let url = try URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
      return ResolvedBookmark(url: url, isStale: stale)
    } catch {
      throw BookmarkError.unresolvable(name)
    }
  }

  /// Replace the bookmark data for an existing (or new) name — used to refresh stale bookmarks.
  public func update(name: String, bookmark: Data) throws {
    marks[name] = bookmark
    try persist()
  }

  private func persist() throws {
    let data = try PropertyListEncoder().encode(marks)
    try data.write(to: storeURL, options: .atomic)
  }
}
