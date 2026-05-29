# Fleet-native Blink Hardening Implementation Plan

> **For agentic workers:** Steps use checkbox (`- [ ]`) syntax for tracking. TDD throughout: pure logic lands in FleetCore with `swift test` first, then wires into the app targets.

**Goal:** Fix the three correctness bugs in the fleet-native features (false-success SSH results, dropped stderr, no deadline, leaked security scopes, silent mount-name collisions), validate the UI on the simulator, and ship a new TestFlight build.

**Architecture:** Pure, deterministic logic (`ExitTrailer.parse`, `MountManager.uniqueName`) lives in the `FleetCore` SPM package and is unit-tested Mac-native. The app-layer Swift (`HeadlessSSHRunner`, `FleetIntents`, `mounts.swift`) consumes that logic and is verified by build + simulator drive. The vendored `SSH/` framework is NOT modified — exit status comes from an in-band command trailer, stderr from the framework's existing public `read_err`.

**Tech Stack:** Swift, Combine, SwiftPM (FleetCore), AppIntents, ios_system, XcodeBuildMCP/simctl, `scripts/release.sh`.

---

### Task 1: `ExitTrailer` pure parse logic (FleetCore)

**Files:**
- Create: `tools/FleetCore/Sources/FleetCore/ExitTrailer.swift`
- Test: `tools/FleetCore/Tests/FleetCoreTests/ExitTrailerTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import FleetCore

final class ExitTrailerTests: XCTestCase {
  func testWrapAppendsTrailer() {
    XCTAssertEqual(ExitTrailer.wrap("uptime"),
                   "{ uptime\n; } ; printf '\\n__BLINK_EXIT_%d__\\n' \"$?\"")
  }
  func testParseSuccess() {
    let raw = "hello\n__BLINK_EXIT_0__\n"
    let r = ExitTrailer.parse(raw)
    XCTAssertEqual(r.output, "hello")
    XCTAssertEqual(r.exitCode, 0)
  }
  func testParseFailureCode() {
    let r = ExitTrailer.parse("boom\n__BLINK_EXIT_3__\n")
    XCTAssertEqual(r.output, "boom")
    XCTAssertEqual(r.exitCode, 3)
  }
  func testParseMultilineOutputPreserved() {
    let r = ExitTrailer.parse("a\nb\nc\n__BLINK_EXIT_0__\n")
    XCTAssertEqual(r.output, "a\nb\nc")
    XCTAssertEqual(r.exitCode, 0)
  }
  func testParseNegativeCode() {
    let r = ExitTrailer.parse("x\n__BLINK_EXIT_-1__\n")
    XCTAssertEqual(r.exitCode, -1)
  }
  func testParseMissingMarkerReturnsNilCode() {
    let r = ExitTrailer.parse("no marker here")
    XCTAssertEqual(r.output, "no marker here")
    XCTAssertNil(r.exitCode)
  }
  func testParseEmptyOutputWithMarker() {
    let r = ExitTrailer.parse("__BLINK_EXIT_0__\n")
    XCTAssertEqual(r.output, "")
    XCTAssertEqual(r.exitCode, 0)
  }
}
```

- [ ] **Step 2: Run, confirm fail**

Run: `swift test --package-path tools/FleetCore --filter ExitTrailerTests`
Expected: FAIL — `ExitTrailer` undefined.

- [ ] **Step 3: Implement**

```swift
import Foundation

/// In-band remote exit-status protocol. The SSH framework does not expose
/// `ssh_channel_get_exit_status` (Stream.channel is internal), so a headless exec
/// wraps its command to print a sentinel trailer carrying `$?`, which `parse` strips
/// back off the captured stdout. Pure + deterministic so it is unit-tested Mac-native.
public enum ExitTrailer {
  static let prefix = "__BLINK_EXIT_"
  static let suffix = "__"

  /// Wrap a user command so its exit status is emitted on its own trailing line.
  public static func wrap(_ command: String) -> String {
    "{ \(command)\n; } ; printf '\\n\(prefix)%d\(suffix)\\n' \"$?\""
  }

  public struct Result: Equatable {
    public let output: String
    public let exitCode: Int32?
  }

  /// Split the trailing `__BLINK_EXIT_<n>__` line off captured stdout.
  /// Returns the cleaned output and the parsed code (nil if no valid trailer).
  public static func parse(_ raw: String) -> Result {
    let lines = raw.split(separator: "\n", omittingEmptySubsequences: false)
    guard let last = lines.last(where: { !$0.isEmpty }),
          last.hasPrefix(prefix), last.hasSuffix(suffix) else {
      return Result(output: raw, exitCode: nil)
    }
    let inner = last.dropFirst(prefix.count).dropLast(suffix.count)
    guard let code = Int32(inner) else { return Result(output: raw, exitCode: nil) }
    // Drop the marker line and exactly one separator newline before it.
    if let range = raw.range(of: "\n" + last) {
      return Result(output: String(raw[raw.startIndex..<range.lowerBound]), exitCode: code)
    }
    if let range = raw.range(of: String(last)) {
      return Result(output: String(raw[raw.startIndex..<range.lowerBound]), exitCode: code)
    }
    return Result(output: raw, exitCode: code)
  }
}
```

- [ ] **Step 4: Run, confirm pass**

Run: `swift test --package-path tools/FleetCore --filter ExitTrailerTests`
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
git add tools/FleetCore/Sources/FleetCore/ExitTrailer.swift tools/FleetCore/Tests/FleetCoreTests/ExitTrailerTests.swift
git commit -m "feat(fleet): ExitTrailer — in-band remote exit-status parse (TDD)"
```

---

### Task 2: `MountManager.uniqueName` collision helper (FleetCore)

**Files:**
- Modify: `tools/FleetCore/Sources/FleetCore/MountManager.swift`
- Test: `tools/FleetCore/Tests/FleetCoreTests/MountManagerTests.swift` (append)

- [ ] **Step 1: Write the failing tests** (append to `MountManagerTests`)

```swift
  func testUniqueNameNoCollision() {
    XCTAssertEqual(MountManager.uniqueName(base: "Docs", existing: ["Other"]), "Docs")
  }
  func testUniqueNameOneCollision() {
    XCTAssertEqual(MountManager.uniqueName(base: "Docs", existing: ["Docs"]), "Docs-2")
  }
  func testUniqueNameChain() {
    XCTAssertEqual(MountManager.uniqueName(base: "Docs", existing: ["Docs", "Docs-2", "Docs-3"]), "Docs-4")
  }
```

- [ ] **Step 2: Run, confirm fail**

Run: `swift test --package-path tools/FleetCore --filter MountManagerTests`
Expected: FAIL — `uniqueName` undefined.

- [ ] **Step 3: Implement** (add to `enum MountManager`)

```swift
  /// Return `base` if free, else the lowest `base-N` (N≥2) not in `existing`.
  /// Callers pass the already-sanitized base name.
  public static func uniqueName(base: String, existing: [String]) -> String {
    let set = Set(existing)
    if !set.contains(base) { return base }
    var n = 2
    while set.contains("\(base)-\(n)") { n += 1 }
    return "\(base)-\(n)"
  }
```

- [ ] **Step 4: Run, confirm pass**

Run: `swift test --package-path tools/FleetCore`
Expected: PASS (all FleetCore tests green).

- [ ] **Step 5: Commit**

```bash
git add tools/FleetCore/Sources/FleetCore/MountManager.swift tools/FleetCore/Tests/FleetCoreTests/MountManagerTests.swift
git commit -m "feat(fleet): MountManager.uniqueName — disambiguate mount-name collisions (TDD)"
```

---

### Task 3: Rewrite `HeadlessSSHRunner` — stderr + exit code + deadline

**Files:**
- Modify: `Blink/Fleet/HeadlessSSHRunner.swift`

Both `ExitTrailer.swift` and `MountManager.swift` are already in the `BlinkConfig` target (FleetCore sources are dual-added). `HeadlessSSHRunner` imports `BlinkConfig`, so `ExitTrailer` is in scope.

- [ ] **Step 1: Replace the result type and `run` body**

Replace the `HeadlessSSHResult` struct and the `run(...)` function with:

```swift
public struct HeadlessSSHResult: Sendable {
  public let stdout: String
  public let stderr: String
  public let exitCode: Int32?   // nil = could not be determined
  public var exitOK: Bool { (exitCode ?? 0) == 0 }
}
```

```swift
  public static func run(
    host: String,
    user: String,
    port: String = "22",
    command: String,
    privateKey: String? = nil,
    password: String? = nil,
    connectionTimeout: Int = 30,
    overallTimeout: TimeInterval = 30,
    acceptUnknownHostKeys: Bool = false
  ) async throws -> HeadlessSSHResult {
    var authMethods: [AuthMethod] = []
    if let pk = privateKey, !pk.isEmpty { authMethods.append(AuthPublicKey(privateKey: pk)) }
    if let pw = password, !pw.isEmpty { authMethods.append(AuthPassword(with: pw)) }
    guard !authMethods.isEmpty else { throw HeadlessSSHError.noAuth }

    let config = SSHClientConfig(
      user: user,
      port: port,
      authMethods: authMethods,
      verifyHostCallback: { _ in
        Just(acceptUnknownHostKeys ? InteractiveResponse.affirmative : InteractiveResponse.negative)
          .setFailureType(to: Error.self).eraseToAnyPublisher()
      },
      connectionTimeout: connectionTimeout,
      sshDirectory: BlinkPaths.ssh()
    )

    // Wrap so the remote shell emits its $? as a trailing sentinel line we can parse.
    let wrapped = ExitTrailer.wrap(command)

    return try await withThrowingTaskGroup(of: HeadlessSSHResult.self) { group in
      group.addTask {
        try await runOnce(host: host, config: config, wrappedCommand: wrapped)
      }
      group.addTask {
        try await Task.sleep(nanoseconds: UInt64(overallTimeout * 1_000_000_000))
        throw HeadlessSSHError.ssh("timed out after \(Int(overallTimeout))s")
      }
      defer { group.cancelAll() }
      guard let first = try await group.next() else {
        throw HeadlessSSHError.ssh("no result")
      }
      return first
    }
  }

  private static func runOnce(
    host: String,
    config: SSHClientConfig,
    wrappedCommand: String
  ) async throws -> HeadlessSSHResult {
    var cancellable: AnyCancellable?
    var outData = Data()
    var errData = Data()
    var resumed = false

    return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<HeadlessSSHResult, Error>) in
      cancellable = SSHClient.dial(host, with: config)
        .flatMap { client in client.requestExec(command: wrappedCommand) }
        .flatMap { stream in
          // Read stdout and stderr to EOF; the channel completes when both drain.
          Publishers.Zip(
            stream.read(max: Int(SSIZE_MAX)),
            stream.read_err(max: Int(SSIZE_MAX))
          )
        }
        .sink(
          receiveCompletion: { completion in
            guard !resumed else { return }
            resumed = true
            switch completion {
            case .failure(let error):
              cont.resume(throwing: HeadlessSSHError.ssh(error.localizedDescription))
            case .finished:
              let parsed = ExitTrailer.parse(String(decoding: outData, as: UTF8.self))
              let err = String(decoding: errData, as: UTF8.self)
              cont.resume(returning: HeadlessSSHResult(
                stdout: parsed.output, stderr: err, exitCode: parsed.exitCode))
            }
            _ = cancellable
          },
          receiveValue: { (out: DispatchData, err: DispatchData) in
            outData.append(contentsOf: out)
            errData.append(contentsOf: err)
          }
        )
    }
  }
```

- [ ] **Step 2: Compile-verify (sim build)**

Run: build for simulator (Task 6 command). Expected: `HeadlessSSHRunner.swift` compiles. If `Publishers.Zip` value tuple destructuring fails, fall back to two sequential reads (stdout then stderr) — both still complete at EOF.

- [ ] **Step 3: Commit**

```bash
git add Blink/Fleet/HeadlessSSHRunner.swift
git commit -m "fix(fleet): HeadlessSSHRunner captures stderr + real exit code + deadline"
```

---

### Task 4: `FleetIntents` surfaces failures

**Files:**
- Modify: `Blink/Fleet/FleetIntents.swift:68-83`

- [ ] **Step 1: Replace the `do/catch` result handling**

```swift
    do {
      let result = try await HeadlessSSHRunner.run(
        host: hostName, user: user, command: command,
        privateKey: pem, password: password,
        acceptUnknownHostKeys: true
      )
      if let code = result.exitCode, code != 0 {
        let detail = result.stderr.isEmpty ? result.stdout : result.stderr
        throw FleetIntentError.runFailed(
          "command exited \(code)" + (detail.isEmpty ? "" : ": \(detail.trimmingCharacters(in: .whitespacesAndNewlines))"))
      }
      return .result(value: result.stdout.isEmpty ? "(no output)" : result.stdout)
    } catch let e as FleetIntentError {
      throw e
    } catch {
      throw FleetIntentError.runFailed((error as? LocalizedError)?.errorDescription ?? "\(error)")
    }
```

- [ ] **Step 2: Compile-verify (sim build).** Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add Blink/Fleet/FleetIntents.swift
git commit -m "fix(fleet): App Intent surfaces non-zero exit + stderr to Shortcuts"
```

---

### Task 5: `mounts.swift` — scope lifecycle + collision-safe naming

**Files:**
- Modify: `Blink/Commands/mounts.swift`

- [ ] **Step 1: Add a single-slot scope holder** (after the `markStore()` helper, ~line 29)

```swift
/// Holds the one security-scoped URL the terminal is currently "inside", so a new
/// pickFolder/jump releases the previous scope instead of leaking it for the session.
private enum ScopeHolder {
  private static let lock = NSLock()
  private static var current: URL?
  static func enter(_ url: URL) {
    lock.lock(); defer { lock.unlock() }
    if let prev = current, prev != url { prev.stopAccessingSecurityScopedResource() }
    _ = url.startAccessingSecurityScopedResource()
    current = url
  }
}
```

- [ ] **Step 2: Use the holder + `uniqueName` in `pickFolder_main`**

Replace the body of `pickFolder_main`'s `do {}` block with:

```swift
  do {
    let data = try url.bookmarkData(options: bookmarkCreateOptions, includingResourceValuesForKeys: nil, relativeTo: nil)
    let store = markStore()
    let base = MountManager.sanitized(name: url.lastPathComponent)
    // Refresh in place if this exact path is already marked; else pick a unique name.
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
```

Also remove the now-redundant `_ = u.startAccessingSecurityScopedResource()` from `FolderPicker.documentPicker(_:didPickDocumentsAt:)` — the scope is taken by `ScopeHolder.enter`. Keep capturing `picked = u`.

- [ ] **Step 3: Use the holder in `jump_main`**

Replace the `do {}` block of `jump_main` with:

```swift
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
```

- [ ] **Step 4: Compile-verify (sim build).** Expected: PASS. Symbol guard unaffected (no new `*_main`).

- [ ] **Step 5: Commit**

```bash
git add Blink/Commands/mounts.swift
git commit -m "fix(mounts): release prior security scope; collision-safe mount names"
```

---

### Task 6: Build, install, and validate on the simulator

**Files:** none (verification).

- [ ] **Step 1: Confirm session defaults / build for sim**

Use XcodeBuildMCP: `session_show_defaults`; if unset, set project `Blink.xcodeproj`, scheme `Blink`, simulator `iPhone 17` (OS 26.5). Then `build_sim`.
Expected: BUILD SUCCEEDED.

- [ ] **Step 2: Boot + install + launch**

`boot_sim` (iPhone 17) → `install_app_sim` → `launch_app_sim` (bundle `com.obercode.blink`).
Expected: app launches to the terminal.

- [ ] **Step 3: Drive the mount commands**

Via ios-simulator UI tools: tap the terminal, `ui_type "showmarks\n"` → screenshot, Read PNG, confirm empty-state line. Then `ui_type "pickFolder\n"` → screenshot, confirm the Files document picker appears (the device-only path now exercised). Cancel.
Expected: `showmarks` prints the empty-state hint; `pickFolder` presents the picker.

- [ ] **Step 4: Verify App Intent registration + push**

`simctl push booted com.obercode.blink <payload.json>` with a sample alert; screenshot to confirm banner. (App Intent end-to-end needs the Shortcuts app — confirm the intent compiles + is registered; full Siri run is device acceptance.)
Expected: push banner renders.

- [ ] **Step 5: Record findings** in `MANUAL-TESTS.md` (what was validated on sim vs. still device-only). Commit.

```bash
git add MANUAL-TESTS.md
git commit -m "docs: simulator validation of mount picker + push (2026-05-29)"
```

---

### Task 7: Commit orphaned PushRegistrar fix + deploy

**Files:**
- Already-modified working tree: `Blink/Fleet/PushRegistrar.swift`

- [ ] **Step 1: Commit the PushRegistrar fix** (separate from this pass's edits — it predates them)

```bash
git add Blink/Fleet/PushRegistrar.swift
git commit -m "fix(push): honor stored password + trust-on-first-use when publishing token"
```

- [ ] **Step 2: Full FleetCore test sweep**

Run: `swift test --package-path tools/FleetCore`
Expected: all green (12 prior + 7 ExitTrailer + 3 uniqueName).

- [ ] **Step 3: Cut a TestFlight build**

Run: `scripts/release.sh` (detached per its docs; poll the log). Symbol guard must report ≥22 `_main`.
Expected: `Attached build <N>` in the log; new build in the internal group.

- [ ] **Step 4: Record the build number** in `handoff.md` / `MANUAL-TESTS.md` and commit.

```bash
git add handoff.md MANUAL-TESTS.md
git commit -m "docs: record build <N> (stderr/exit-code/scope hardening)"
```

---

## Self-Review

**Spec coverage:** Fix A (exit code/stderr/deadline) → Tasks 1,3,4. Fix B (scope + collisions) → Tasks 2,5. Fix C (PushRegistrar) → Task 7. Testing strategy → Tasks 1,2 (pure), 6 (sim UI), 7 (deploy). UI intent validation → Task 6. All spec sections covered.

**Placeholder scan:** No TBD/TODO; every code step shows complete code; commands have expected output.

**Type consistency:** `HeadlessSSHResult` gains `stderr`/`exitCode: Int32?`/`exitOK` (Task 3), consumed in Task 4. `ExitTrailer.wrap`/`.parse`/`.Result` (Task 1) consumed in Task 3. `MountManager.uniqueName(base:existing:)` (Task 2) consumed in Task 5. `ScopeHolder.enter` (Task 5 Step 1) consumed in Steps 2–3. Consistent.

**Known risk:** `Publishers.Zip` of the two reads — if the value tuple doesn't destructure cleanly in this Combine version, Task 3 Step 2 notes the sequential-read fallback.
