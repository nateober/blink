//////////////////////////////////////////////////////////////////////////////////
//
// B L I N K
//
// Mountable iCloud/Files folders for Blink (fleet-native fork).
//
// Commands: pickFolder / bookmark / showmarks / jump / renamemark / deletemark, plus
// addpath / rmpath / showpath. Folders are linked into the shell HOME (~/<name>) via Blink's
// native BookmarkedLocationsManager, which symlinks them AND registers their paths with
// ios_system's allowed-paths sandbox (ios_setAllowedPaths) — without that registration a
// security-scoped folder is picked but NOT navigable (cd/ls blocked outside the mini-root).
// Name logic is the pure FleetCore MountManager/PathManager (unit-tested). Device-only — see
// MANUAL-TESTS.md.
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

private let locations = BookmarkedLocationsManager.default

/// Path of `~/<name>` (the symlink BookmarkedLocationsManager creates).
private func homeChild(_ name: String) -> String {
  BlinkPaths.homeURL().appendingPathComponent(name).path
}

private func locationNames() -> [String] {
  ((try? locations.getLocations()) ?? []).map { $0.name }
}

#if targetEnvironment(macCatalyst)
private let bookmarkCreateOptions: URL.BookmarkCreationOptions = [.withSecurityScope]
#else
private let bookmarkCreateOptions: URL.BookmarkCreationOptions = []
#endif

/// Link `url` into ~ via BookmarkedLocationsManager (reusing the existing link if this exact
/// path is already linked), refresh the session's allowed paths so it's immediately usable,
/// and return the chosen ~ name.
private func linkIntoHome(_ url: URL, desired: String, session: MCPSession?) throws -> String {
  if let existing = (try? locations.getLocations())?.first(where: { $0.url?.path == url.path }) {
    session?.updateAllowedPaths()
    return existing.name
  }
  var name = MountManager.uniqueName(base: MountManager.sanitized(name: desired), existing: locationNames())
  // Avoid colliding with anything already sitting at ~/<name> on disk.
  while FileManager.default.fileExists(atPath: homeChild(name)) {
    name = MountManager.uniqueName(base: name, existing: locationNames() + [name])
  }
  _ = try locations.addLocation(name: name, location: url)
  session?.updateAllowedPaths()
  return name
}

/// Presents the folder picker and returns the chosen URL, blocking the command thread.
private final class FolderPicker: NSObject, UIDocumentPickerDelegate {
  private let sema = DispatchSemaphore(value: 0)
  private var picked: URL?
  private var strongSelf: FolderPicker?

  func present(from session: MCPSession) -> URL? {
    DispatchQueue.main.async {
      guard let root = session.device?.view?.window?.rootViewController else { self.sema.signal(); return }
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
    if let u = urls.first { picked = u }
    sema.signal()
  }
  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { sema.signal() }
}

private func currentSession() -> MCPSession? {
  guard let ctx = thread_context else { return nil }
  return Unmanaged<MCPSession>.fromOpaque(ctx).takeUnretainedValue()
}

// MARK: - Mount commands

@_cdecl("pickFolder_main")
public func pickFolder_main(argc: Int32, argv: Argv) -> Int32 {
  guard let session = currentSession() else { mErr("pickFolder: no session"); return 1 }
  guard let url = FolderPicker().present(from: session) else { mOut("pickFolder: cancelled"); return 0 }
  // Start access before reading the URL (iCloud folders are unreachable otherwise) and nudge
  // iCloud to materialize the folder.
  _ = url.startAccessingSecurityScopedResource()
  try? FileManager.default.startDownloadingUbiquitousItem(at: url)
  do {
    let name = try linkIntoHome(url, desired: url.lastPathComponent, session: session)
    FileManager.default.changeCurrentDirectoryPath(homeChild(name))
    mOut("Linked to ~/\(name)  ->  \(url.path)")
    mOut("(cd ~/\(name) any time · deletemark \(name) to remove)")
    return 0
  } catch { mErr("pickFolder: \(error.localizedDescription)"); return 1 }
}

@_cdecl("bookmark_main")
public func bookmark_main(argc: Int32, argv: Argv) -> Int32 {
  guard let session = currentSession() else { mErr("bookmark: no session"); return 1 }
  let args = argv.args(count: argc)
  let cwd = FileManager.default.currentDirectoryPath
  let desired = args.count > 1 ? args[1] : URL(fileURLWithPath: cwd).lastPathComponent
  do {
    let name = try linkIntoHome(URL(fileURLWithPath: cwd), desired: desired, session: session)
    mOut("Bookmarked ~/\(name)  ->  \(cwd)")
    return 0
  } catch { mErr("bookmark: \(error.localizedDescription)"); return 1 }
}

@_cdecl("showmarks_main")
public func showmarks_main(argc: Int32, argv: Argv) -> Int32 {
  let locs = (try? locations.getLocations()) ?? []
  if locs.isEmpty { mOut("No bookmarks. Use pickFolder or bookmark <name>."); return 0 }
  for loc in locs {
    let target = loc.url?.path ?? "(unresolvable)"
    mOut("~/\(loc.name)\t\(target)\(loc.isStale ? "  (stale)" : "")")
  }
  return 0
}

@_cdecl("jump_main")
public func jump_main(argc: Int32, argv: Argv) -> Int32 {
  let args = argv.args(count: argc)
  guard args.count > 1 else { mErr("usage: jump <mark>  (see showmarks)"); return 1 }
  let name = args[1]
  guard locationNames().contains(name) else { mErr("jump: no such bookmark '\(name)'"); return 1 }
  let dir = homeChild(name)
  if FileManager.default.changeCurrentDirectoryPath(dir) { mOut(dir); return 0 }
  mErr("jump: cannot enter ~/\(name) (folder unavailable?)"); return 1
}

@_cdecl("renamemark_main")
public func renamemark_main(argc: Int32, argv: Argv) -> Int32 {
  guard let session = currentSession() else { mErr("renamemark: no session"); return 1 }
  let args = argv.args(count: argc)
  guard args.count > 2 else { mErr("usage: renamemark <old> <new>"); return 1 }
  let old = args[1]
  guard let loc = (try? locations.getLocations())?.first(where: { $0.name == old }), let url = loc.url else {
    mErr("renamemark: no such bookmark '\(old)'"); return 1
  }
  do {
    let newName = MountManager.sanitized(name: args[2])
    try locations.removeLocation(name: old)
    _ = try linkIntoHome(url, desired: newName, session: session)
    mOut("Renamed.")
    return 0
  } catch { mErr("renamemark: \(error.localizedDescription)"); return 1 }
}

@_cdecl("deletemark_main")
public func deletemark_main(argc: Int32, argv: Argv) -> Int32 {
  guard let session = currentSession() else { mErr("deletemark: no session"); return 1 }
  let args = argv.args(count: argc)
  guard args.count > 1 else { mErr("usage: deletemark <mark>"); return 1 }
  let name = args[1]
  guard locationNames().contains(name) else { mErr("deletemark: no such bookmark '\(name)'"); return 1 }
  do {
    try locations.removeLocation(name: name)
    PathNames.remove(name)            // also drop it from PATH if it was there
    applyPathMarks(session: session)
    session.updateAllowedPaths()
    mOut("Deleted '\(name)'.")
    return 0
  } catch { mErr("deletemark: \(error.localizedDescription)"); return 1 }
}

// MARK: - PATH inclusion (addpath / rmpath / showpath)
//
// A folder is first linked into ~ (so it is navigable + sandbox-allowed), then ~/<name> is
// prepended to $PATH. PATH membership is a list of location names persisted to pathnames.plist
// and re-applied at launch (FleetPath.apply). iOS can't exec native binaries — serves
// ios_system-runnable scripts.

private enum PathNames {
  private static let url = URL(fileURLWithPath: BlinkPaths.blink()).appendingPathComponent("pathnames.plist")
  static func load() -> [String] {
    (try? Data(contentsOf: url)).flatMap { try? PropertyListDecoder().decode([String].self, from: $0) } ?? []
  }
  static func add(_ name: String) { var n = load(); if !n.contains(name) { n.append(name); save(n) } }
  static func remove(_ name: String) { save(load().filter { $0 != name }) }
  private static func save(_ names: [String]) {
    if let data = try? PropertyListEncoder().encode(names) { try? data.write(to: url, options: .atomic) }
  }
}

private enum PathState { static let lock = NSLock(); static var base: String? }

private func currentPATH() -> String {
  guard let p = getenv("PATH") else { return "" }
  return String(cString: p)
}

/// Rebuild $PATH = (~/<name> for each PATH-marked location) prepended to the captured base.
private func applyPathMarks(session: MCPSession?) {
  PathState.lock.lock(); defer { PathState.lock.unlock() }
  let current = currentPATH()
  if PathState.base == nil { PathState.base = current }
  let base = PathState.base ?? current
  let dirs = PathNames.load().filter { locationNames().contains($0) }.map { homeChild($0) }
  setenv("PATH", PathManager.prepend(dirs, to: base), 1)
  session?.updateAllowedPaths()
}

/// ObjC-callable: re-apply persisted PATH folders at launch.
@objc public final class FleetPath: NSObject {
  @objc public static func apply() { applyPathMarks(session: nil) }
}

@_cdecl("addpath_main")
public func addpath_main(argc: Int32, argv: Argv) -> Int32 {
  guard let session = currentSession() else { mErr("addpath: no session"); return 1 }
  guard let url = FolderPicker().present(from: session) else { mOut("addpath: cancelled"); return 0 }
  _ = url.startAccessingSecurityScopedResource()
  try? FileManager.default.startDownloadingUbiquitousItem(at: url)
  do {
    let name = try linkIntoHome(url, desired: url.lastPathComponent, session: session)
    PathNames.add(name)
    applyPathMarks(session: session)
    mOut("Added ~/\(name) to PATH  ->  \(url.path)")
    mOut("(rmpath \(name) to remove · showpath to list)")
    return 0
  } catch { mErr("addpath: \(error.localizedDescription)"); return 1 }
}

@_cdecl("rmpath_main")
public func rmpath_main(argc: Int32, argv: Argv) -> Int32 {
  guard let session = currentSession() else { mErr("rmpath: no session"); return 1 }
  let args = argv.args(count: argc)
  guard args.count > 1 else { mErr("usage: rmpath <name>  (see showpath)"); return 1 }
  guard PathNames.load().contains(args[1]) else { mErr("rmpath: not on PATH: '\(args[1])'"); return 1 }
  PathNames.remove(args[1])
  applyPathMarks(session: session)
  mOut("Removed '\(args[1])' from PATH (still linked at ~/\(args[1]); deletemark to unlink).")
  return 0
}

@_cdecl("showpath_main")
public func showpath_main(argc: Int32, argv: Argv) -> Int32 {
  let names = PathNames.load().filter { locationNames().contains($0) }
  if names.isEmpty { mOut("No folders on PATH. Use addpath to pick one.") }
  else { mOut("On PATH:"); for n in names { mOut("  ~/\(n)\t\(homeChild(n))") } }
  mOut("PATH=\(currentPATH())")
  return 0
}
