# Manual / On-Device Acceptance — fleet-native Blink

The Ralph loop certifies compile + sign + archive + unit tests + reviews only.
Everything below requires Nate on a real device (and, for push, the fleet).
Each item names the TestFlight build it first shipped in.

## Feature A — Mountable iCloud/Files folders
- [x] `pickFolder` opens the iOS folder picker; choosing a folder stores a security-scoped
      bookmark and chdir's into it (prints `Mounted '<name>' -> <path>` / `(jump <name> ...)`;
      it does NOT symlink under `~/mnt`). Cancel prints `pickFolder: cancelled`.
      **Sim-verified 2026-05-25** (build 1105 source, iPhone 17 / iOS 26.5): happy path + cancel
      path both correct. Folder picked was a local "On My iPhone" folder — iCloud-folder
      navigation specifically still needs a device (sim isn't signed into iCloud).
- [x] Mounted folder survives an app relaunch (bookmark persisted). **Sim-verified 2026-05-25:**
      mark + path identical after `simctl terminate` + cold relaunch, no `(stale)` suffix.
      `mountmarks.plist` in `BlinkPaths.blink()` persists through the app data container.
- [x] `showmarks` / `jump <mark>` / `renamemark` / `deletemark` behave. (`cd ~<mark>` shell-tilde
      deferred; use `jump`.) **Sim-verified 2026-05-25:** `showmarks` lists mount + path; `jump`
      re-resolves the bookmark; `renamemark` rewrites the plist key (no dup); `deletemark` removes
      it; both edge cases (`renamemark` no-args usage, `deletemark` unknown-name error) correct.
- [ ] Blink's own iCloud folder ("Blink For Personal") appears in iCloud Drive on a Mac
      (NSUbiquitousContainers fix). Device/Mac-only — not testable on sim.
- (PATH-inclusion feature deferred — see plan Task 1.7.)

> **Sim build note:** Debug simulator builds need `ENABLE_DEBUG_DYLIB=NO` or every dlsym-dispatched
> built-in (`pickFolder`, `config`, `ssh`, ...) fails with `command not found`. Xcode 26 defaults it
> to YES, splitting the app into a stub + `Blink.debug.dylib` that `dlsym(RTLD_MAIN_ONLY,...)` can't
> see. Set in `developer_setup.xcconfig` (Debug-scoped); distinct from the Release strip flags.

## Feature B — App Intents / Shortcuts
- [ ] "Run on Ada" (or similar) Shortcut/Siri phrase appears after install.
- [ ] The Shortcut runs `claude -p "..."` on a fleet host and returns text output.
      **Hardened 2026-05-29 (build 1106):** the runner now captures stderr + the real remote
      exit code (via an in-band `__BLINK_EXIT_<n>__` trailer — see `FleetCore/ExitTrailer`) and
      enforces a 30s overall deadline. The App Intent throws `runFailed("command exited <n>: …")`
      on non-zero exit instead of returning a false success.
- [ ] **ROOT-CAUSE FIX 2026-05-29 (build 1107):** the Shortcut returned iOS's generic "unknown
      error". Cause: `HeadlessSSHRunner` ran the SSH pipeline on the Swift-concurrency pool, which
      never spins a RunLoop — but the SSH framework only makes progress while the RunLoop captured
      at `SSHClient.init` is running (interactive `ssh` spins it via `CFRunLoopRun`). So the dial
      hung and iOS killed the App Intent → "unknown error". Fixed: dial on a dedicated thread that
      spins its run loop (mirrors `ssh.swift awaitRunLoop`). **Sim-verified:** a dial to a reachable
      sshd with a bad password now fails in <3s with a real SSH error instead of hanging 30s.
      New terminal command **`fleetexec <host> <cmd>`** is the shell twin of the intent — use it to
      test the headless path directly on the phone: `fleetexec ada uptime`.
- [ ] HeadlessSSHRunner behavioral test: fix the pre-existing BlinkTests compile errors
      (SessionParamsTests / BKSessionParamsSnapshotting), then run
      `BLINK_TEST_KEY_PATH=<key> xcodebuild test -only-testing:BlinkTests/HeadlessSSHRunnerTests`
      on the iOS Simulator (sim reaches host sshd at 127.0.0.1). Compile-verified only so far.
      The exit-code/stderr parse logic IS covered by `swift test --package-path tools/FleetCore`
      (ExitTrailerTests, 7 cases, Mac-native).

## Feature C — Push notifications
- [ ] 🔒 APNs auth key (.p8) generated in the portal and stored via op-add.
- [ ] 🔒 Push capability enabled on App ID `com.obercode.blink` (if not auto-added during signing).
- [ ] Blink registers and publishes its APNs token to `~/.blink-notify/token` on the configured host.
- [ ] `blink_notify.py` sends a push that arrives on the device.
- [ ] Live Activity renders for a long-running `claude -p` session.
- [ ] 🔒 `blink_notify` wired into the `claude -p` wrapper on "needs input".

## Build numbers (TestFlight internal group)
- 1101 — Phase 1 (mountable iCloud folders)
- 1102 — Phase 2 (App Intents / Shortcuts)
- 1103 — Phase 3 (push notifications + security fix); all features
- 1104 — host-password fix in the App Intent
- 1105 — Shortcut error-surfacing + trust-on-first-use
- 1106 — hardening: SSH stderr + real exit code + 30s deadline; collision-safe mount names;
         security-scope release on jump/pickFolder; push token-publish honors password.
         **Sim-validated 2026-05-29** (ios-tester, iPhone 17 / iOS 26.5): `showmarks` empty-state
         correct; `pickFolder` presents the Files picker, cancel prints `pickFolder: cancelled`;
         `simctl push` banner renders. FleetCore: 22 tests green.
- 1107 — **root-cause fix for the Shortcut "unknown error":** HeadlessSSHRunner now drives a
         RunLoop on a dedicated thread (the headless SSH dial used to hang). Adds `fleetexec`
         terminal command. Sim-verified: dial fails fast with a real SSH error, no 30s hang.
- Test on the latest (1107). On-device: set the host's HostName to its Tailscale IP (e.g.
  ada → 100.64.0.3), then run the Shortcut / `fleetexec ada uptime` — should return output now.
