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

- Pure-logic unit tests (simulator): `xcodebuild test -project Blink.xcodeproj -scheme BlinkConfig -destination 'platform=iOS Simulator,name=iPhone 16,OS=26.5' -only-testing:BlinkConfigTests/<TestName> 2>&1 | tail -30`
  - (Recon Task 0.2 confirms the exact scheme/destination that runs green; update this line if needed.)
- Fast compile check (one scheme): `xcodebuild build -project Blink.xcodeproj -scheme BlinkConfig -destination 'generic/platform=iOS' 2>&1 | tail -5`
- Milestone archive: `scripts/release.sh` (auto-bumps build, archives, uploads, attaches to TestFlight group).
- Symbol guard (after archive): `xcrun dyld_info -exports build/Blink.xcarchive/Products/Applications/Blink.app/Blink | grep -cE '_main$'` (expect ≥ 22).

---

## Phase 0 — Loop harness & ground truth

### Task 0.1: Create MANUAL-TESTS.md
**Files:** Create `MANUAL-TESTS.md`
- [ ] **Step 1:** Write the file with three empty sections (Feature A / B / C), each a checklist of on-device acceptance steps copied from the spec's "Manual (device)" lines.
- [ ] **Step 2:** Commit.
```bash
git add MANUAL-TESTS.md && git commit -m "docs: seed MANUAL-TESTS.md for on-device acceptance"
```

### Task 0.2: Confirm the simulator unit-test path works
**Files:** none (recon)
- [ ] **Step 1:** List simulators: `xcrun simctl list devices available | grep -i iphone`. Pick an available iPhone on OS 26.5.
- [ ] **Step 2:** Confirm a test scheme exists and runs: `xcodebuild test -project Blink.xcodeproj -scheme BlinkConfig -destination 'platform=iOS Simulator,name=<picked>,OS=26.5' 2>&1 | tail -40`. If `BlinkConfig` has no test target, identify which scheme maps to `BlinkConfigTests` via `xcodebuild -list`.
- [ ] **Step 3:** Record the working scheme + destination at the top of this file (edit the "Verification commands" block). Commit the edit.
- [ ] **Note:** If NO unit-test target runs green on the simulator after reasonable effort, append a blocker to `MANUAL-TESTS.md` and switch logic-unit verification to `swift test` in a standalone SPM package under `tools/` for the pure types (no UIKit). Do not give up silently.

### Task 0.3: Recon — command registration pattern
**Files:** none (recon); write findings into Task 1.5 below
- [ ] **Step 1:** Read `Blink/Commands/config.m` and find where `config` is registered (grep `replaceCommand`, `commandList`, `MCPSession`, `ios_system`). Identify the exact file + call that maps the string `"config"` → `config_main`.
- [ ] **Step 2:** Read `MCPSession.m` (PATH setup + command table). Record: (a) how a new built-in `*_main` is registered, (b) where PATH is assembled.
- [ ] **Step 3:** Update Task 1.5 and Task 1.7 with the real registration call + PATH file. Commit any plan edits.

---

## Phase 1 — Feature A: mountable iCloud/Files folders

### Task 1.1: BookmarkStore — failing test
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

### Task 1.2: BookmarkStore — implement
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

### Task 1.3: Add BookmarkStore + test file to the Xcode project
**Files:** Modify `Blink.xcodeproj/project.pbxproj`
- [ ] **Step 1:** Add `BookmarkStore.swift` to the `BlinkConfig` framework target and `BookmarkStoreTests.swift` to `BlinkConfigTests`. Prefer opening the project once in Xcode if pbxproj surgery is unreliable; otherwise add the file refs + build-file entries following the pattern of an existing BlinkConfig swift file.
- [ ] **Step 2:** Compile check (canonical fast build). Commit.

### Task 1.4: MountManager — define interface (recon + stub + test)
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

### Task 1.5: pickFolder + bookmark commands (UI + dispatch)
**Files:** Create `Blink/Commands/pickFolder.swift` (+ register per Task 0.3 findings)
- [ ] **Step 1: Recon (from Task 0.3):** confirmed registration call is `<RECORD HERE>`.
- [ ] **Step 2:** Port a-Shell's pickFolder flow (GPL-3 attribution in file header): present `UIDocumentPickerViewController(forOpeningContentTypes: [.folder])`, on pick create a security-scoped bookmark, `store.add`, and mount via MountManager. Implement `bookmark`, `showmarks`, `jump`, `renamemark`, `deletemark`, and `cd ~<mark>` resolution. Each is a `*_main`-style entry registered like `config`.
- [ ] **Step 3:** Compile check. The picker interaction itself is device-only → add acceptance steps to `MANUAL-TESTS.md`.
- [ ] **Step 4:** Commit.

### Task 1.6: Info.plist — repoint NSUbiquitousContainers
**Files:** Modify `Blink/Info.plist`
- [ ] **Step 1:** Change the `NSUbiquitousContainers` dict key from `iCloud.sh.blink.blinkshell` to `iCloud.com.obercode.blink` (keep `NSUbiquitousContainerIsDocumentScopePublic=true`, name "Blink For Personal", folder levels Any).
- [ ] **Step 2:** Compile check. Commit. Add to `MANUAL-TESTS.md`: "verify Blink folder appears in iCloud Drive on a Mac."

### Task 1.7: PATH inclusion for mounted `/bin`
**Files:** Modify the PATH-assembly site found in Task 0.3 (likely `MCPSession.m`)
- [ ] **Step 1:** After existing PATH setup, append each mounted folder's `bin` (those flagged `addToPath`) using `MountManager.pathFragment`. Read flags from BookmarkStore metadata (extend the plist value to `{bookmark, addToPath}` if needed — update Task 1.1/1.2 types and tests accordingly, then re-run).
- [ ] **Step 2:** Compile check. Commit.

### Task 1.8: Phase 1 milestone — archive + symbol guard
- [ ] **Step 1:** Run `scripts/release.sh`. Confirm EXPORT SUCCEEDED.
- [ ] **Step 2:** Symbol guard ≥ 22. If new commands added `*_main`, confirm they're present.
- [ ] **Step 3:** Append the new build number to `MANUAL-TESTS.md` Feature A section. Commit.

---

## Phase 2 — Feature B: App Intents / Shortcuts

### Task 2.1: Recon — SSHClient one-shot exec
**Files:** none (recon)
- [ ] **Step 1:** Read `SSH/SSHClient.swift`, `SSH/SSHClientConfig.swift`. Record the minimal API to: open a connection from a host config, run a single command, capture stdout/stderr/exit, close. Note how Blink resolves a host alias → config (the `ssh_config` reader).
- [ ] **Step 2:** Write the discovered interface into Task 2.2 (replace `<API>` placeholders with real calls). Commit plan edit.

### Task 2.2: HeadlessSSHRunner — test + implement
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

### Task 2.3: RunFleetCommandIntent + AppShortcutsProvider
**Files:** Create `Blink/Fleet/FleetIntents.swift`
- [ ] **Step 1:** Implement `RunFleetCommandIntent: AppIntent` with `@Parameter host: String`, `@Parameter command: String`, `perform()` → `HeadlessSSHRunner.run`, returns `.result(value: stdout)`. Implement `BlinkShortcuts: AppShortcutsProvider` with phrases ("Run \\(\\.$command) on \\(\\.$host) with Blink").
- [ ] **Step 2:** Add files to the `Blink` app target (pbxproj). Compile check. App Intents must be in the main app target (no new extension).
- [ ] **Step 3:** Commit. Device-only acceptance → `MANUAL-TESTS.md` (Shortcut appears, runs `claude -p`, returns text).

### Task 2.4: Phase 2 milestone — archive
- [ ] **Step 1:** `scripts/release.sh` succeeds; symbol guard holds. Record build number in `MANUAL-TESTS.md`. Commit.

---

## Phase 3 — Feature C: push notifications

### Task 3.1: 🔒 Re-add Push capability (entitlement)
**Files:** Modify `Blink/Blink.entitlements`
- [ ] **Step 1:** Add `aps-environment` = `development`. (Production string is set automatically for App Store/TestFlight distribution.)
- [ ] **Step 2:** Compile/sign check via archive. If signing fails because the App ID lacks the Push capability, `-allowProvisioningUpdates` with the Admin key should add it; if not, append a 🔒 note to `MANUAL-TESTS.md` ("enable Push on App ID in portal") and continue.
- [ ] **Step 3:** Commit.

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

### Task 3.3: PushRegistrar (app integration)
**Files:** Create `Blink/Push/PushRegistrar.swift`; modify `Blink/AppDelegate.m` (or SceneDelegate)
- [ ] **Step 1: Recon:** find app launch hook in `AppDelegate.m`. Record where to call registration.
- [ ] **Step 2:** Implement `registerForRemoteNotifications()`; on `didRegisterForRemoteNotificationsWithDeviceToken`, hex-encode, `APNSTokenStore.save`, and best-effort publish via `HeadlessSSHRunner.run(host: <configured>, command: "mkdir -p ~/.blink-notify && cat > ~/.blink-notify/token")` piping the token. Configurable host stored in settings; if unset, just persist locally and surface in UI.
- [ ] **Step 3:** Compile check. Device-only acceptance → `MANUAL-TESTS.md`. Commit.

### Task 3.4: AgentActivity Live Activity
**Files:** Create `Blink/Push/AgentActivity.swift`
- [ ] **Step 1:** Define `ActivityAttributes` (`host`, `session`) with `ContentState` (`status`, `detail`). Start/update/end helpers gated on `ActivityAuthorizationInfo().areActivitiesEnabled`.
- [ ] **Step 2:** Compile check. Live Activity render is device-only → `MANUAL-TESTS.md`. Commit.

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
