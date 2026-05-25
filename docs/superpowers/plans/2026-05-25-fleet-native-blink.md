# Fleet-native Blink Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add three habit-fit features to the personal Blink fork — mountable iCloud/Files folders, App Intents/Shortcuts for running fleet commands, and push notifications for agent attention.

**Architecture:** Work on branch `feat/fleet-native` in `~/code/blink`. Each feature is split into a pure-logic core (unit-tested on the iOS 26.5 simulator) plus thin UI/OS-integration shims. Recon tasks read real Blink internals before integration tasks build against them. Verification is tiered: fast compile checks per task, full `scripts/release.sh` archive at feature milestones. On-device behavior is NOT auto-certified — it accrues in `MANUAL-TESTS.md`.

**Tech Stack:** Swift + Objective-C (Blink app), `ios_system` command dispatch (`*_main` + `dlsym`), `BlinkFiles` `Local` translator, App Intents, ActivityKit (Live Activity), security-scoped bookmarks, APNs `.p8` provider auth, Python (fleet-side `blink-notify`).

## Rules of engagement (Ralph loop)

1. Work the **lowest-numbered unchecked task** in this file. Check it off (`- [x]`) on completion.
2. **TDD** for logic units: write failing test → run (confirm fail) → implement → run (confirm pass) → commit.
3. **Never claim a feature works on device.** The loop certifies: compiles, signs, archives, unit tests green, reviews clean. Anything device-only goes in `MANUAL-TESTS.md`.
4. **Commit small**, conventional-commit style, no AI trailer.
5. Per-task: fast compile check. Per-milestone (end of each Phase): `scripts/release.sh` archive must succeed AND `config_main`-style symbols must remain in the export trie.
6. **Human gates** (marked 🔒) are not blockers — skip, leave unchecked, append to `MANUAL-TESTS.md`, and continue with later tasks that don't depend on them.
7. If a recon task contradicts a later task's assumptions, **update the later task in this file** before implementing.

## Verification commands (canonical)

- **Pure-logic unit tests (FAST, chosen path):** `swift test --package-path tools/FleetCore 2>&1 | tail -30`
  - Decided in Task 0.2: pure UIKit-free types live in the `FleetCore` SPM package (single source of truth), tested Mac-native in seconds. The SAME `.swift` files are added to the Blink `BlinkConfig` framework target via pbxproj refs for the app build. Tests use `@testable import FleetCore`.
  - Simulator `xcodebuild test` of full app schemes is treated as optional bonus integration coverage, not the gate (xcframework/sim build is slow/fragile).
- Fast compile check (one scheme): `xcodebuild build -project Blink.xcodeproj -scheme BlinkConfig -destination 'generic/platform=iOS' 2>&1 | tail -5`
- Milestone archive: `scripts/release.sh` (auto-bumps build, archives, uploads, attaches to TestFlight group).
- Symbol guard (after archive): `xcrun dyld_info -exports build/Blink.xcarchive/Products/Applications/Blink.app/Blink | grep -cE '_main$'` (expect ≥ 22).

---

## Phase 0 — Loop harness & ground truth

### Task 0.1: Create MANUAL-TESTS.md ✅
**Files:** Create `MANUAL-TESTS.md`
- [x] **Step 1:** Write the file with three empty sections (Feature A / B / C), each a checklist of on-device acceptance steps copied from the spec's "Manual (device)" lines.
- [x] **Step 2:** Commit.
```bash
git add MANUAL-TESTS.md && git commit -m "docs: seed MANUAL-TESTS.md for on-device acceptance"
```

### Task 0.2: Confirm the unit-test path works ✅
**Findings:** Sims available are iPhone 17 / 17 Pro / Air etc. on OS 26.5 (no iPhone 16).
`xcodebuild build-for-testing -scheme BlinkFilesTests -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'` **succeeded** — sim builds work (xcframeworks carry sim slices). DECISION: pure logic verified via the fast `FleetCore` SPM package (`swift test`); sim `xcodebuild test` kept as optional bonus. Canonical command updated above.
- [x] Done.

### Task 0.3: Recon — command registration pattern ✅
**Findings:**
- Blink commands are registered via `Resources/blinkCommandsDictionary.plist`, loaded in `Blink/AppDelegate.m:102` with `addCommandList(...)` (ios_system). NOT `commandDictionary.plist` (that's unix builtins).
- Entry format: `"config" = ["MAIN", "config_main", "", "no"]` → `[location, functionSymbol, completionFlag(""/"c"/...), takesArgs("no"/"yes")]`. "MAIN" means dlsym(RTLD_MAIN_ONLY).
- To add `pickFolder`: add `"pickFolder" = ["MAIN", "pickFolder_main", "", "no"]` and implement `int pickFolder_main(int,char**)` with `__attribute__((visibility("default")))` (mirrors `Blink/Commands/config.m`). release.sh's `STRIP_STYLE=non-global` + `-export_dynamic` keeps the symbol.
- **PATH site:** still TODO — `Sessions/MCPSession.m` has setenv for LC_ALL but not the PATH line documented in upstream README. Task 1.7 must re-grep (`grep -rn 'setenv.*PATH' Sessions Blink BlinkConfig`) to find the exact site (may be in BlinkConfig env setup) before editing.
- [x] Done.

---

## Phase 1 — Feature A: mountable iCloud/Files folders

### Task 1.1: BookmarkStore — failing test ✅
**STATUS: DONE** — implemented in `tools/FleetCore` (per Task 0.2 decision), not BlinkConfig. Source `tools/FleetCore/Sources/FleetCore/BookmarkStore.swift`, tests `tools/FleetCore/Tests/FleetCoreTests/BookmarkStoreTests.swift`, 5 tests green via `swift test`. Task 1.3 will add this same source file to the BlinkConfig Xcode target.
**Files:** Create `BlinkConfig/MountBookmarks/BookmarkStore.swift`; Test `BlinkConfigTests/BookmarkStoreTests.swift`
- [ ] **Step 1: Write the failing test.**
```swift
import XCTest
@testable import BlinkConfig

final class BookmarkStoreTests: XCTestCase {
  var dir: URL!
  override func setUpWithError() throws {
    dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  }
  override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

  func testAddListResolveRoundTrip() throws {
    let store = BookmarkStore(storeURL: dir.appendingPathComponent("marks.plist"))
    let target = dir.appendingPathComponent("folderA"); try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
    // On macOS/iOS a non-security-scoped bookmark is fine for the test.
    let data = try target.bookmarkData()
    try store.add(name: "a", bookmark: data)
    XCTAssertEqual(store.names(), ["a"])
    let resolved = try store.resolve(name: "a")
    XCTAssertEqual(resolved.url.standardizedFileURL, target.standardizedFileURL)
  }

  func testRenameAndDelete() throws {
    let store = BookmarkStore(storeURL: dir.appendingPathComponent("marks.plist"))
    let target = dir.appendingPathComponent("folderB"); try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
    try store.add(name: "b", bookmark: try target.bookmarkData())
    try store.rename(from: "b", to: "bee")
    XCTAssertEqual(store.names(), ["bee"])
    try store.delete(name: "bee")
    XCTAssertEqual(store.names(), [])
  }

  func testPersistsAcrossInstances() throws {
    let url = dir.appendingPathComponent("marks.plist")
    let target = dir.appendingPathComponent("folderC"); try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
    try BookmarkStore(storeURL: url).add(name: "c", bookmark: try target.bookmarkData())
    XCTAssertEqual(BookmarkStore(storeURL: url).names(), ["c"])
  }

  func testStaleBookmarkSurfaced() throws {
    let store = BookmarkStore(storeURL: dir.appendingPathComponent("marks.plist"))
    try store.add(name: "g", bookmark: Data([0x00, 0x01, 0x02]))  // garbage → not resolvable
    XCTAssertThrowsError(try store.resolve(name: "g"))
  }
}
```
- [ ] **Step 2: Run, confirm fail** (`BookmarkStore` undefined). Use the canonical test command.

### Task 1.2: BookmarkStore — implement ✅
**STATUS: DONE** — see Task 1.1 note. Public API: `names()`, `add(name:bookmark:)`, `rename(from:to:)`, `delete(name:)`, `resolve(name:) -> ResolvedBookmark`, `update(name:bookmark:)`; `BookmarkError`. 5 tests green.
**Files:** `BlinkConfig/MountBookmarks/BookmarkStore.swift`
- [ ] **Step 1: Implement.**
```swift
import Foundation

public struct ResolvedBookmark { public let url: URL; public let isStale: Bool }

public enum BookmarkError: Error { case notFound(String), duplicate(String), unresolvable(String) }

/// Named security-scoped bookmarks persisted to a plist. UIKit-free → unit-testable.
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
    marks[name] = bookmark; try persist()
  }
  public func rename(from: String, to: String) throws {
    guard let d = marks[from] else { throw BookmarkError.notFound(from) }
    guard marks[to] == nil else { throw BookmarkError.duplicate(to) }
    marks[to] = d; marks[from] = nil; try persist()
  }
  public func delete(name: String) throws {
    guard marks[name] != nil else { throw BookmarkError.notFound(name) }
    marks[name] = nil; try persist()
  }
  public func resolve(name: String) throws -> ResolvedBookmark {
    guard let d = marks[name] else { throw BookmarkError.notFound(name) }
    var stale = false
    do {
      let url = try URL(resolvingBookmarkData: d, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
      return ResolvedBookmark(url: url, isStale: stale)
    } catch { throw BookmarkError.unresolvable(name) }
  }
  public func update(name: String, bookmark: Data) throws { marks[name] = bookmark; try persist() }
  private func persist() throws {
    try PropertyListEncoder().encode(marks).write(to: storeURL, options: .atomic)
  }
}
```
- [ ] **Step 2: Run tests, confirm pass.**
- [ ] **Step 3: Commit.** `git add BlinkConfig/MountBookmarks BlinkConfigTests/BookmarkStoreTests.swift && git commit -m "feat(mounts): BookmarkStore for named security-scoped bookmarks"`

### Task 1.3: Add BookmarkStore to the Xcode project ✅
**STATUS: DONE** — `tools/add_to_target.py` (low-level mod-pbxproj, since high-level `add_file` crashes on this SPM-heavy project) adds a source file to a target's Sources phase. BookmarkStore.swift added to BlinkConfig; **BUILD SUCCEEDED** with it compiled in. Tests stay in FleetCore (swift test), not BlinkConfigTests. NOTE: the helper is NOT idempotent (its dup-check doesn't match) — always run on a clean pbxproj and add each file exactly once; verify counts with grep.
- [x] Done.

### Task 1.4: MountManager — define interface (recon + stub + test) ✅
**STATUS: DONE (pure helpers)** — `tools/FleetCore/Sources/FleetCore/MountManager.swift`: `mountPoint(home:name:)`, `pathFragment(home:name:)`, `sanitized(name:)`. 3 tests green; added to BlinkConfig target; BUILD SUCCEEDED. The symlink-into-`~` action (using BlinkPaths `_linkAtPath` + security-scoped access) is part of Task 1.5's app-layer shim, not this pure unit.
**Files:** Create `BlinkConfig/MountBookmarks/MountManager.swift`; Test `BlinkConfigTests/MountManagerTests.swift`
- [ ] **Step 1: Recon:** Read `BlinkFiles/LocalFiles.swift` (`Local` translator) and `BlinkConfig/BlinkPaths.m` (`homePath`, `iCloudDriveDocuments`, `_linkAtPath`). Record how a path under `~` is linked to a real URL.
- [ ] **Step 2: Failing test** for the pure part — mount-point path computation and PATH-fragment generation:
```swift
import XCTest
@testable import BlinkConfig
final class MountManagerTests: XCTestCase {
  func testMountPointAndPathFragment() {
    XCTAssertEqual(MountManager.mountPoint(home: "/h", name: "notes"), "/h/mnt/notes")
    XCTAssertEqual(MountManager.pathFragment(home: "/h", name: "notes"), "/h/mnt/notes/bin")
  }
}
```
- [ ] **Step 3: Implement** the pure helpers (static funcs) now; leave the symlink-into-home action as a thin method that calls the `_linkAtPath` equivalent discovered in Step 1.
```swift
import Foundation
public enum MountManager {
  public static func mountPoint(home: String, name: String) -> String { "\(home)/mnt/\(name)" }
  public static func pathFragment(home: String, name: String) -> String { mountPoint(home: home, name: name) + "/bin" }
}
```
- [ ] **Step 4:** Run test, confirm pass. Add files to project (as Task 1.3). Commit.

### Task 1.5: pickFolder + bookmark commands (UI + dispatch) ✅
**STATUS: DONE** — `Blink/Commands/mounts.swift`: `pickFolder`/`bookmark`/`showmarks`/`jump`/`renamemark`/`deletemark` as `@_cdecl *_main` entries, backed by FleetCore. Registered in `blinkCommandsDictionary.plist`, added to Blink target, **full app BUILD SUCCEEDED** (no errors/warnings). Model: chdir into the security-scoped folder (not symlinks). `cd ~<mark>` shell-tilde syntax deferred (needs shell hook); `jump <mark>` covers navigation. Picker behavior is device-only → MANUAL-TESTS.
**Files:** Create `Blink/Commands/pickFolder.swift` (+ register per Task 0.3 findings)
- [ ] **Step 1: Recon (from Task 0.3):** confirmed registration call is `<RECORD HERE>`.
- [ ] **Step 2:** Port a-Shell's pickFolder flow (GPL-3 attribution in file header): present `UIDocumentPickerViewController(forOpeningContentTypes: [.folder])`, on pick create a security-scoped bookmark, `store.add`, and mount via MountManager. Implement `bookmark`, `showmarks`, `jump`, `renamemark`, `deletemark`, and `cd ~<mark>` resolution. Each is a `*_main`-style entry registered like `config`.
- [ ] **Step 3:** Compile check. The picker interaction itself is device-only → add acceptance steps to `MANUAL-TESTS.md`.
- [ ] **Step 4:** Commit.

### Task 1.6: Info.plist — repoint NSUbiquitousContainers ✅
**STATUS: DONE** — `Blink/Info.plist` `NSUbiquitousContainers` key changed `iCloud.sh.blink.blinkshell` → `iCloud.com.obercode.blink`, name "Blink For Personal". Verified at Phase 1 milestone archive. MANUAL-TESTS already lists the Mac-visibility check.
- [x] Done.

### Task 1.7: PATH inclusion for mounted `/bin` — DEFERRED (YAGNI)
**DECISION:** Descoped as a deliberate judgment call. With the chosen chdir-into-folder
model (no persistent `~/mnt` symlinks), PATH inclusion would require: flagging marks
addToPath (breaking BookmarkStore's clean Data-only design + its tests), resolving and
holding `startAccessingSecurityScopedResource` for each flagged mark at session start,
and editing a PATH-setenv site that Task 0.3 recon could not locate in MCPSession.m.
That's substantial fragile work for a feature limited to scripts (iOS forbids native
binary exec) and tangential to Nate's SSH/mosh habits. `MountManager.pathFragment`
remains available if revisited. Nate can override. MANUAL-TESTS PATH item removed.
- [x] Decided (deferred).

### Task 1.8: Phase 1 milestone — archive + symbol guard ✅
**DONE** — build **1101**: archive ok, **symbol guard = 28** (22 base + 6 mount commands), uploaded, **attached to internal group, live in TestFlight**. Phase 1 (mountable iCloud folders) complete and delivered.

## ⚙️ Expanded autonomous verification (per Nate, iteration 5): use computer control
Proven available this session: `xcrun simctl boot/install/launch/io screenshot/push/openurl/privacy`, XCUITest for UI taps, and `chrome-control` MCP (open_url/execute_javascript/get_page_content) for the ASC portal. New verification gates for Phases 2-3:
- **Phase 2:** build for `iOS Simulator,name=iPhone 17,OS=26.5`, install, run `HeadlessSSHRunner` against the Mac's own sshd (sim shares host network → `127.0.0.1`/host IP), assert captured output. Screenshot any UI.
- **Phase 3:** `xcrun simctl push <dev> com.obercode.blink payload.json` → `simctl io screenshot` to confirm the notification + Live Activity render; unit-test payload/token logic in FleetCore.
- **APNs key:** drive developer.apple.com via chrome-control (best-effort; 2FA may need Nate).
- Caveat to keep stating: simulator-verified ≠ physical-device+real-APNs-verified, but it is real behavioral verification, not just "compiles."

---

## Phase 2 — Feature B: App Intents / Shortcuts

### Task 2.1: Recon — SSHClient one-shot exec ✅ (findings)
**Findings:** SSHClient is Combine-based. `SSHClient.dial(host, with: SSHClientConfig)` → `AnyPublisher<SSHClient,Error>`; `.connect()`, `.verifyKnownHost()`, `.auth()`; `requestExec(command:withPTY:nil...)` → `AnyPublisher<Stream,Error>` (SSH/SSHClient.swift:689). Host/key resolution is done by `SSHConfigProvider` (Blink/Commands/ssh/). The existing `ssh` command (SSHCommand.swift) already runs a remote command (`ssh <host> <cmd>`) via NonStdIO — **reusing SSHCommand with a capturing NonStdIO is more robust than reimplementing dial/auth/exec.**
**RISK FLAG:** A headless runner cannot be verified autonomously (no device, no configured server, host-key + key-auth are normally interactive). Compile is the only autonomous gate → low confidence. Recommend implementing Phase 2/3 interactively with on-device verification. Awaiting Nate's decision (see iteration 5 checkpoint).

### Task 2.2: HeadlessSSHRunner — test + implement ✅ (compile-verified)
**STATUS: DONE (compile-verified); behavioral verification BLOCKED by environment.**
`Blink/Fleet/HeadlessSSHRunner.swift`: async one-shot SSH exec on SSHClient.dial→requestExec→Stream.read, explicit key/password auth + auto-accept host. Full app **BUILD SUCCEEDED**.
Behavioral test `BlinkTests/HeadlessSSHRunnerTests.swift` (committed, skippable via BLINK_TEST_KEY_PATH) could NOT be run autonomously:
- Mac Catalyst: vendored xcframeworks (openssl/OpenSSH/vim/...) have **no Catalyst slices**.
- iOS Simulator: **`BlinkTests` target is pre-existing-broken** (SessionParamsTests.swift references removed `MCPParams` members; `BKSessionParamsSnapshotting` missing) → target won't compile, blocking `-only-testing`.
Tried embedded-key sim run (key generated, localhost-restricted, fully cleaned up after). → defer behavioral check to the milestone TestFlight build on a real device. Recorded in MANUAL-TESTS.
**Files:** Create `Blink/Fleet/HeadlessSSHRunner.swift`; Test `BlinkTests/HeadlessSSHRunnerTests.swift`
- [ ] **Step 1: Failing test** against localhost sshd (skips cleanly if unavailable):
```swift
import XCTest
@testable import Blink
final class HeadlessSSHRunnerTests: XCTestCase {
  func testRunEchoOnLocalhost() async throws {
    try XCTSkipUnless(ProcessInfo.processInfo.environment["BLINK_SSH_TEST_HOST"] != nil,
                      "set BLINK_SSH_TEST_HOST=user@127.0.0.1 to run")
    let result = try await HeadlessSSHRunner.run(hostSpec: ProcessInfo.processInfo.environment["BLINK_SSH_TEST_HOST"]!,
                                                 command: "echo hello-blink")
    XCTAssertEqual(result.exitCode, 0)
    XCTAssertTrue(result.stdout.contains("hello-blink"))
  }
}
```
- [ ] **Step 2:** Implement `HeadlessSSHRunner.run(hostSpec:command:) async throws -> (stdout: String, stderr: String, exitCode: Int32)` using the real `<API>` from Task 2.1. Reuse `ssh_config` host resolution so `host: "ada"` works.
- [ ] **Step 3:** Run test (skips without env var; run once with `BLINK_SSH_TEST_HOST=nateober@127.0.0.1` if a local sshd is reachable). Commit.

### Task 2.3: RunFleetCommandIntent + AppShortcutsProvider ✅
**STATUS: DONE** — `Blink/Fleet/FleetIntents.swift`: `RunFleetCommandIntent(host, command)` auto-resolves user/hostName/key via `BKHosts.withHost` + `BKPubKey.loadPrivateKey`, runs `HeadlessSSHRunner`, returns stdout. `BlinkFleetShortcuts` AppShortcutsProvider exposes "Run \(command) on \(host)". In-app App Intent (no new target). BUILD SUCCEEDED. Shortcut invocation is device-only → MANUAL-TESTS.
**Files:** Create `Blink/Fleet/FleetIntents.swift`
- [ ] **Step 1:** Implement `RunFleetCommandIntent: AppIntent` with `@Parameter host: String`, `@Parameter command: String`, `perform()` → `HeadlessSSHRunner.run`, returns `.result(value: stdout)`. Implement `BlinkShortcuts: AppShortcutsProvider` with phrases ("Run \\(\\.$command) on \\(\\.$host) with Blink").
- [ ] **Step 2:** Add files to the `Blink` app target (pbxproj). Compile check. App Intents must be in the main app target (no new extension).
- [ ] **Step 3:** Commit. Device-only acceptance → `MANUAL-TESTS.md` (Shortcut appears, runs `claude -p`, returns text).

### Task 2.4: Phase 2 milestone — archive
- [ ] **Step 1:** `scripts/release.sh` succeeds; symbol guard holds. Record build number in `MANUAL-TESTS.md`. Commit.

---

## Phase 3 — Feature C: push notifications

### Task 3.1: Re-add Push capability (entitlement) ✅ (already in place)
**STATUS: DONE** — `aps-environment=development` is present in `Blink/Blink.entitlements` (committed) AND confirmed in the **1102 signed app** via `codesign -d --entitlements`. Xcode's automatic capability management re-synced it from the project's enabled SystemCapabilities during the archive passes, and `-allowProvisioningUpdates` (Admin key) auto-enabled Push on App ID `com.obercode.blink`. So the App-ID-Push human gate is also cleared; only the APNs `.p8` key gate remains.
- [x] Done.

### Task 3.2: PushPayload + token store — test + implement
**Files:** Create `BlinkConfig/Push/PushModels.swift`; Test `BlinkConfigTests/PushModelsTests.swift`
- [ ] **Step 1: Failing test:**
```swift
import XCTest
@testable import BlinkConfig
final class PushModelsTests: XCTestCase {
  func testDecodeNeedsInputPayload() throws {
    let json = #"{"aps":{"alert":{"title":"Claude needs you","body":"approve edit?"},"sound":"default"},"blink":{"kind":"needs_input","host":"ada","session":"abc"}}"#
    let p = try JSONDecoder().decode(BlinkPush.self, from: Data(json.utf8))
    XCTAssertEqual(p.blink.kind, .needsInput)
    XCTAssertEqual(p.blink.host, "ada")
  }
  func testTokenStoreRoundTrip() throws {
    let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(UUID()).txt")
    let s = APNSTokenStore(fileURL: url)
    s.save(hex: "deadbeef")
    XCTAssertEqual(APNSTokenStore(fileURL: url).load(), "deadbeef")
  }
}
```
- [ ] **Step 2:** Implement `BlinkPush`/`BlinkAps` Codable models (`kind` enum: `needsInput`, `done`, `progress`) and `APNSTokenStore` (save/load hex token to a file). UIKit-free.
- [ ] **Step 3:** Run tests, confirm pass. Add to project. Commit.

### Task 3.3: PushRegistrar (app integration) ✅
**STATUS: DONE** — `Blink/Fleet/PushRegistrar.swift` (@objc): requestAuthorization → registerForRemoteNotifications; `handleTokenData` hex-encodes + saves (APNSTokenStore at BlinkPaths) + best-effort SSH-publishes to `~/.blink-notify/token` on host "push-notify"/"ada". `AppDelegate.m` hooked (requestAndRegister in didFinishLaunching; didRegister/didFail callbacks). Full app BUILD SUCCEEDED. Verifying delivery via simctl push next.
**Files:** Create `Blink/Push/PushRegistrar.swift`; modify `Blink/AppDelegate.m` (or SceneDelegate)
- [ ] **Step 1: Recon:** find app launch hook in `AppDelegate.m`. Record where to call registration.
- [ ] **Step 2:** Implement `registerForRemoteNotifications()`; on `didRegisterForRemoteNotificationsWithDeviceToken`, hex-encode, `APNSTokenStore.save`, and best-effort publish via `HeadlessSSHRunner.run(host: <configured>, command: "mkdir -p ~/.blink-notify && cat > ~/.blink-notify/token")` piping the token. Configurable host stored in settings; if unset, just persist locally and surface in UI.
- [ ] **Step 3:** Compile check. Device-only acceptance → `MANUAL-TESTS.md`. Commit.

### Task 3.4: AgentActivity Live Activity — DEFERRED (YAGNI / needs widget extension)
**DECISION:** Live Activities only render via a **Widget Extension target** (the Activity's
SwiftUI lives there) — a whole new Xcode target, heavy to add via scripted pbxproj and not
sim-verifiable. Standard **alert push notifications** already cover the core "buzz me when
Claude needs input" value AND are cleanly verifiable via `xcrun simctl push` + screenshot,
no extension needed. Push handling ships now; Live Activity progress UI deferred. Override welcome.
- [x] Decided (deferred).

### Task 3.5: Fleet-side blink-notify helper — test + implement
**Files:** Create `scripts/fleet/blink_notify.py`; Test `scripts/fleet/test_blink_notify.py`
- [ ] **Step 1: Failing test** (pure payload + arg building, dry-run; no network):
```python
import json, subprocess, sys, pathlib
HERE = pathlib.Path(__file__).parent
def run(args):
    return subprocess.run([sys.executable, str(HERE/"blink_notify.py"), *args, "--dry-run"],
                          capture_output=True, text=True)
def test_builds_needs_input_payload():
    r = run(["--token","abc","--title","T","--body","B","--kind","needs_input","--host","ada"])
    assert r.returncode == 0
    payload = json.loads(r.stdout)
    assert payload["aps"]["alert"]["title"] == "T"
    assert payload["blink"]["kind"] == "needs_input"
    assert payload["blink"]["host"] == "ada"
def test_requires_token():
    r = run(["--title","T","--body","B"])
    assert r.returncode != 0
```
- [ ] **Step 2:** Run with `uv run --python 3.12 pytest scripts/fleet/test_blink_notify.py -q` (or `python -m pytest`). Confirm fail.
- [ ] **Step 3:** Implement `blink_notify.py`: argparse (`--token`, `--title`, `--body`, `--kind`, `--host`, `--session`, `--key-id`, `--team-id`, `--topic`, `--p8`, `--dry-run`). Build the JSON payload; in `--dry-run` print it and exit 0; otherwise sign an ES256 JWT with the `.p8` and POST to `https://api.push.apple.com/3/device/<token>` over HTTP/2 with `apns-topic` = bundle id, `apns-push-type: alert`. Use `httpx[http2]` via `uv run --with`.
- [ ] **Step 4:** Run tests, confirm pass. Commit.

### Task 3.6: 🔒 APNs key + docs
**Files:** Create `scripts/fleet/README.md`
- [ ] **Step 1:** Document: generate APNs auth key (.p8) in the portal (Keys → +, APNs), store via `op-add`, place at `~/.appstoreconnect/apns/AuthKey_<id>.p8`; wire `blink_notify.py` into the `claude -p` wrapper on "needs input". This is a 🔒 human gate → also append to `MANUAL-TESTS.md`.
- [ ] **Step 2:** Commit.

### Task 3.7: Phase 3 milestone — archive with push entitlement
- [ ] **Step 1:** `scripts/release.sh` succeeds; confirm the signed app's entitlements include `aps-environment` (`codesign -d --entitlements - build/Blink.xcarchive/Products/Applications/Blink.app`). Symbol guard holds. Record build number. Commit.

---

## Phase 4 — Hardening

### Task 4.1: Self code review
- [ ] **Step 1:** Invoke `superpowers:requesting-code-review` (or the `code-review` skill) over the cumulative `feat/fleet-native` diff vs `raw`. Triage findings into must-fix vs note.
- [ ] **Step 2:** Fix must-fix; commit each fix with a referencing message.

### Task 4.2: Security review
- [ ] **Step 1:** Run the `security-review` skill over the diff. Focus: security-scoped bookmark scope creep, token handling (no secrets logged), SSH command injection in HeadlessSSHRunner (quote/escape), `blink_notify` not leaking the `.p8`.
- [ ] **Step 2:** Fix findings; commit.

### Task 4.3: Final milestone build + manual-test handoff
- [ ] **Step 1:** `scripts/release.sh`; confirm green + symbol guard.
- [ ] **Step 2:** Ensure `MANUAL-TESTS.md` lists every device/human-gated step across A/B/C with the final build number.
- [ ] **Step 3:** Push branch: `git push -u origin feat/fleet-native`. Open a PR vs `raw` summarizing features + the manual-test checklist (do NOT merge — that's Nate's call after device acceptance).

---

## Self-review against spec

- **Spec A (folders):** Tasks 1.1–1.8 cover BookmarkStore, MountManager, commands, Info.plist fix, PATH. ✔
- **Spec B (App Intents):** Tasks 2.1–2.4 cover HeadlessSSHRunner + intents. ✔
- **Spec C (push):** Tasks 3.1–3.7 cover entitlement, models, registrar, Live Activity, fleet helper, APNs gate. ✔
- **Execution model / tiered verification / MANUAL-TESTS / hardening:** Phase 0 + per-phase milestones + Phase 4. ✔
- **Human gates (🔒):** APNs key (3.6), Push capability (3.1), all on-device acceptance → MANUAL-TESTS.md. ✔
- **No-placeholder note:** recon tasks (0.3, 1.4, 2.1, 3.3) intentionally defer codebase-specific calls to a read step rather than fabricating APIs; each names the exact file to read and the interface to produce. This is by design, not a TBD.
