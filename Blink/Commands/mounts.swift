//////////////////////////////////////////////////////////////////////////////////
//
// B L I N K
//
// Mountable iCloud/Files folders for Blink (fleet-native fork).
//
// Command surface modeled on a-Shell (github.com/holzschu/a-shell, GPL-3): pickFolder,
// bookmark, showmarks, jump, renamemark, deletemark. Pure storage/path logic lives in
// FleetCore (`BookmarkStore`, `MountManager`), compiled into BlinkConfig and unit-tested
// via `swift test`. This file is the thin app-layer shim: the folder picker UI and the
// `chdir` into a security-scoped folder. Device-only behavior — see MANUAL-TESTS.md.
//
// Blink is free software under the GNU GPL v3; see <http://www.github.com/blinksh/blink>.
//
//////////////////////////////////////////////////////////////////////////////////

import Foundation
import UIKit
import UniformTypeIdentifiers
import BlinkConfig
import ios_system

private func mOut(_ s: String) { fputs(s + "\n", thread_stdout) }
private func mErr(_ s: String) { fputs(s + "\n", thread_stderr) }

private func markStore() -> BookmarkStore {
  let url = URL(fileURLWithPath: BlinkPaths.blink()).appendingPathComponent("mountmarks.plist")
  return BookmarkStore(storeURL: url)
}

/// Holds the one security-scoped URL the terminal is currently "inside", so a new
/// pickFolder/jump releases the previous scope instead of leaking it for the session.
private enum ScopeHolder {
  private static let lock = NSLock()
  private static var current: URL?
  static func enter(_ url: URL) {
    lock.lock(); defer { lock.unlock() }
    // Always release the previous scope before starting a new one — even when re-entering
    // the SAME url, since startAccessingSecurityScopedResource is refcounted and would
    // otherwise climb without a matching stop.
    current?.stopAccessingSecurityScopedResource()
    _ = url.startAccessingSecurityScopedResource()
    current = url
  }
}

#if targetEnvironment(macCatalyst)
private let bookmarkCreateOptions: URL.BookmarkCreationOptions = [.withSecurityScope]
private let bookmarkResolveOptions: URL.BookmarkResolutionOptions = [.withSecurityScope]
#else
private let bookmarkCreateOptions: URL.BookmarkCreationOptions = []
private let bookmarkResolveOptions: URL.BookmarkResolutionOptions = []
#endif

/// Presents the folder picker and returns the chosen URL (security access already started),
/// blocking the calling command thread until the user picks or cancels.
private final class FolderPicker: NSObject, UIDocumentPickerDelegate {
  private let sema = DispatchSemaphore(value: 0)
  private var picked: URL?
  private var strongSelf: FolderPicker?

  func present(from session: MCPSession) -> URL? {
    DispatchQueue.main.async {
      guard let root = session.device?.view?.window?.rootViewController else {
        self.sema.signal(); return
      }
      self.strongSelf = self
      let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
      picker.delegate = self
      picker.allowsMultipleSelection = false
      var presenter = root
      while let p = presenter.presentedViewController { presenter = p }
      presenter.present(picker, animated: true)
    }
    sema.wait()
    strongSelf = nil
    return picked
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    // Scope is taken (and the prior one released) by ScopeHolder.enter in pickFolder_main.
    if let u = urls.first { picked = u }
    sema.signal()
  }
  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    sema.signal()
  }
}

private func currentSession() -> MCPSession? {
  guard let ctx = thread_context else { return nil }
  return Unmanaged<MCPSession>.fromOpaque(ctx).takeUnretainedValue()
}

// MARK: - Commands

@_cdecl("pickFolder_main")
public func pickFolder_main(argc: Int32, argv: Argv) -> Int32 {
  guard let session = currentSession() else { mErr("pickFolder: no session"); return 1 }
  guard let url = FolderPicker().present(from: session) else {
    mOut("pickFolder: cancelled"); return 0
  }
  do {
    let data = try url.bookmarkData(options: bookmarkCreateOptions, includingResourceValuesForKeys: nil, relativeTo: nil)
    let store = markStore()
    let base = MountManager.sanitized(name: url.lastPathComponent)
    // Refresh in place if this exact path is already marked; else pick a unique name so a
    // second folder with the same leaf name doesn't silently clobber the first's bookmark.
    let existingForPath = store.names().first { (try? store.resolve(name: $0))?.url.path == url.path }
    let name = existingForPath ?? MountManager.uniqueName(base: base, existing: store.names())
    if store.names().contains(name) { try store.update(name: name, bookmark: data) }
    else { try store.add(name: name, bookmark: data) }
    ScopeHolder.enter(url)
    FileManager.default.changeCurrentDirectoryPath(url.path)
    mOut("Mounted '\(name)' -> \(url.path)")
    mOut("(jump \(name) to return here)")
    return 0
  } catch {
    mErr("pickFolder: \(error.localizedDescription)"); return 1
  }
}

@_cdecl("bookmark_main")
public func bookmark_main(argc: Int32, argv: Argv) -> Int32 {
  let args = argv.args(count: argc)
  let cwd = FileManager.default.currentDirectoryPath
  let name = MountManager.sanitized(name: args.count > 1 ? args[1] : URL(fileURLWithPath: cwd).lastPathComponent)
  do {
    let data = try URL(fileURLWithPath: cwd).bookmarkData(options: bookmarkCreateOptions, includingResourceValuesForKeys: nil, relativeTo: nil)
    let store = markStore()
    if store.names().contains(name) { try store.update(name: name, bookmark: data) }
    else { try store.add(name: name, bookmark: data) }
    mOut("Bookmarked '\(name)' -> \(cwd)")
    return 0
  } catch { mErr("bookmark: \(error.localizedDescription)"); return 1 }
}

@_cdecl("showmarks_main")
public func showmarks_main(argc: Int32, argv: Argv) -> Int32 {
  let store = markStore()
  let names = store.names()
  if names.isEmpty { mOut("No bookmarks. Use pickFolder or bookmark <name>."); return 0 }
  for name in names {
    if let r = try? store.resolve(name: name) {
      mOut("\(name)\t\(r.url.path)\(r.isStale ? "  (stale)" : "")")
    } else {
      mOut("\(name)\t(unresolvable)")
    }
  }
  return 0
}

@_cdecl("jump_main")
public func jump_main(argc: Int32, argv: Argv) -> Int32 {
  let args = argv.args(count: argc)
  guard args.count > 1 else { mErr("usage: jump <mark>"); return 1 }
  let name = args[1]
  let store = markStore()
  do {
    let r = try store.resolve(name: name)
    ScopeHolder.enter(r.url)
    if FileManager.default.changeCurrentDirectoryPath(r.url.path) {
      mOut(r.url.path)
      return 0
    } else {
      mErr("jump: cannot enter \(r.url.path)"); return 1
    }
  } catch { mErr("jump: no such bookmark '\(name)'"); return 1 }
}

@_cdecl("renamemark_main")
public func renamemark_main(argc: Int32, argv: Argv) -> Int32 {
  let args = argv.args(count: argc)
  guard args.count > 2 else { mErr("usage: renamemark <old> <new>"); return 1 }
  do { try markStore().rename(from: args[1], to: MountManager.sanitized(name: args[2])); mOut("Renamed."); return 0 }
  catch { mErr("renamemark: \(error)"); return 1 }
}

@_cdecl("deletemark_main")
public func deletemark_main(argc: Int32, argv: Argv) -> Int32 {
  let args = argv.args(count: argc)
  guard args.count > 1 else { mErr("usage: deletemark <mark>"); return 1 }
  do { try markStore().delete(name: args[1]); mOut("Deleted '\(args[1])'."); return 0 }
  catch { mErr("deletemark: no such bookmark '\(args[1])'"); return 1 }
}

// MARK: - PATH inclusion (addpath / rmpath / showpath)
//
// Folders the user opts onto $PATH so their scripts/commands resolve by name. Persisted as
// security-scoped bookmarks (separate from mount marks) and re-applied at launch via
// FleetPath.apply. iOS can't exec native binaries — this serves ios_system-runnable scripts.

private func pathMarkStore() -> BookmarkStore {
  let url = URL(fileURLWithPath: BlinkPaths.blink()).appendingPathComponent("pathmarks.plist")
  return BookmarkStore(storeURL: url)
}

/// Holds the original $PATH (captured once) so PATH can be recomputed from a clean base when
/// folders are added/removed, and tracks which scopes we've already opened (refcount hygiene).
private enum PathState {
  static let lock = NSLock()
  static var base: String?
  static var openedScopes = Set<String>()
}

private func currentPATH() -> String {
  guard let p = getenv("PATH") else { return "" }
  return String(cString: p)
}

/// Resolve all path-marked folders, hold security-scoped access, best-effort materialize iCloud
/// contents, and rebuild $PATH = (resolved dirs) prepended to the captured base PATH.
@discardableResult
private func applyPathMarks() -> [String] {
  PathState.lock.lock(); defer { PathState.lock.unlock() }
  let current = currentPATH()
  if PathState.base == nil { PathState.base = current }
  let base = PathState.base ?? current

  let store = pathMarkStore()
  var dirs: [String] = []
  for name in store.names() {
    guard let r = try? store.resolve(name: name) else { continue }
    if !PathState.openedScopes.contains(r.url.path) {
      if r.url.startAccessingSecurityScopedResource() { PathState.openedScopes.insert(r.url.path) }
    }
    // Pull the folder down from iCloud so its scripts are materialized (no-op if not ubiquitous).
    try? FileManager.default.startDownloadingUbiquitousItem(at: r.url)
    dirs.append(r.url.path)
  }
  setenv("PATH", PathManager.prepend(dirs, to: base), 1)
  return dirs
}

/// ObjC-callable entry point so AppDelegate can re-apply persisted PATH folders at launch.
@objc public final class FleetPath: NSObject {
  @objc public static func apply() { applyPathMarks() }
}

@_cdecl("addpath_main")
public func addpath_main(argc: Int32, argv: Argv) -> Int32 {
  guard let session = currentSession() else { mErr("addpath: no session"); return 1 }
  guard let url = FolderPicker().present(from: session) else { mOut("addpath: cancelled"); return 0 }
  do {
    let data = try url.bookmarkData(options: bookmarkCreateOptions, includingResourceValuesForKeys: nil, relativeTo: nil)
    let store = pathMarkStore()
    let base = MountManager.sanitized(name: url.lastPathComponent)
    let existingForPath = store.names().first { (try? store.resolve(name: $0))?.url.path == url.path }
    let name = existingForPath ?? MountManager.uniqueName(base: base, existing: store.names())
    if store.names().contains(name) { try store.update(name: name, bookmark: data) }
    else { try store.add(name: name, bookmark: data) }
    applyPathMarks()
    mOut("Added '\(name)' to PATH -> \(url.path)")
    mOut("(rmpath \(name) to remove; showpath to list)")
    return 0
  } catch { mErr("addpath: \(error.localizedDescription)"); return 1 }
}

@_cdecl("rmpath_main")
public func rmpath_main(argc: Int32, argv: Argv) -> Int32 {
  let args = argv.args(count: argc)
  guard args.count > 1 else { mErr("usage: rmpath <name>  (see showpath)"); return 1 }
  do {
    try pathMarkStore().delete(name: args[1])
    applyPathMarks()
    mOut("Removed '\(args[1])' from PATH.")
    return 0
  } catch { mErr("rmpath: not on PATH: '\(args[1])'"); return 1 }
}

@_cdecl("showpath_main")
public func showpath_main(argc: Int32, argv: Argv) -> Int32 {
  let store = pathMarkStore()
  let names = store.names()
  if names.isEmpty {
    mOut("No folders on PATH. Use addpath to pick one.")
  } else {
    mOut("On PATH:")
    for name in names {
      if let r = try? store.resolve(name: name) {
        mOut("  \(name)\t\(r.url.path)\(r.isStale ? "  (stale)" : "")")
      } else {
        mOut("  \(name)\t(unresolvable)")
      }
    }
  }
  mOut("PATH=\(currentPATH())")
  return 0
}
