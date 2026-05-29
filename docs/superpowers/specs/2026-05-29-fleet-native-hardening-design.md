# Fleet-native Blink — hardening + UI validation (design)

**Date:** 2026-05-29 · **Branch:** `feat/fleet-native` · **Author:** Ada (autonomous, per Nate's "do and fix all the things" directive)

Continuation of the fleet-native work (mountable folders, App Intents, push). The three
features compile/sign/unit-test and ship to TestFlight, but carry correctness bugs found in
review and have never been exercised on a running app. This pass fixes the bugs, validates the
UI on the simulator, and ships a new build. No approval gates — two-way-door work on a personal
TestFlight internal group.

## Intent (assumptions, since we're not pausing to ask)

These are my read of what Nate intended; each is a reversible default.

1. **App Intent / Shortcut = "run a command on a host, get the real result back."** "Real" means:
   if the remote command fails, the Shortcut surfaces *why* (stderr + non-zero exit), not a false
   success with empty output. This is the single biggest correctness gap.
2. **Mount commands = a-Shell-style working-folder bookmarks.** `pickFolder` mounts + cd's;
   `jump` returns; marks persist. Picking two folders with the same leaf name should not silently
   destroy the first mark.
3. **Security-scoped access should not leak.** Holding the *current* folder open is intended;
   accumulating every folder ever visited is not.
4. **Hung commands must fail cleanly,** not wedge the App Intent until iOS kills it (which shows
   the generic "unspecified error" we just removed).

## Fixes

### A. `HeadlessSSHRunner` — real exit status + stderr + deadline
- **Result shape:** `HeadlessSSHResult { stdout: String; stderr: String; exitCode: Int32? }`
  (`exitCode == nil` means "couldn't determine"). Drop the always-true `exitOK`.
- **stderr:** capture via the SSH framework's public `Stream.read_err(max:)`, zipped with the
  stdout read. Both complete at channel EOF.
- **Exit code (in-band trailer):** the SSH framework does not expose `ssh_channel_get_exit_status`
  (its `Stream.channel` is internal; even upstream `ssh.swift` never reads remote exit status).
  Rather than patch the vendored framework, wrap the command:
  `{ <command>; } ; printf '\n__BLINK_EXIT_%d__\n' "$?"`. A **pure FleetCore function**
  `ExitTrailer.parse(_:)` splits the trailer off the captured stdout and returns `(output, exitCode)`.
  Portable across bash/zsh, fully unit-testable with no device/sshd. Degrades to `exitCode == nil`
  if the marker is absent.
- **Deadline:** overall timeout (default 30s) via a racing `Task`; on expiry, cancel the Combine
  subscription and resume `.runFailed("timed out after Ns")`.
- **App Intent surfacing:** on `exitCode != 0`, throw `runFailed` with stderr (falling back to
  stdout) so Shortcuts shows the cause. On success, return stdout (or `(no output)`).

### B. `mounts.swift` — scope lifecycle + name collisions
- **Scope lifecycle:** track the currently-held security-scoped URL in a single holder; on a new
  `pickFolder`/`jump`, `stopAccessingSecurityScopedResource()` the previous one before starting the
  new. Deliberate single-folder hold, no unbounded accumulation.
- **Name collisions:** new pure FleetCore helper `BookmarkStore`-aware unique-naming —
  `MountManager.uniqueName(base:existing:)` appends `-2`, `-3`, … when the sanitized leaf name is
  already taken by a *different* folder. `pickFolder` uses it instead of silently `update`-ing.
  (Re-picking the *same* path still refreshes in place — match on resolved path.)

### C. Hygiene
- Commit the orphaned `PushRegistrar.swift` fix (password + trust-on-first-use, mirrors the
  committed App Intent fixes) as its own `fix(push):` unit.

## Testing strategy

- **Pure logic → FleetCore (`swift test`, Mac-native, fast):** `ExitTrailer.parse` (success, failure,
  multiline output, missing marker, negative code), `MountManager.uniqueName` (no collision, one
  collision, chain). This is where the exit-code/stderr correctness is locked.
- **Runner integration:** keep the localhost-sshd test but make the assertion meaningful (assert
  `exitCode == 0` for `true`, `== 3` for `sh -c 'exit 3'`, stderr captured for `echo x >&2`). Runs
  opportunistically against Ada's own sshd (localhost reachable from sim).
- **UI validation (simulator):** build → install → launch → drive the terminal via the
  ios-simulator UI tools: `showmarks` (empty state), `pickFolder` (picker appears), and verify the
  App Intent is registered. Screenshot each and read the PNG to confirm. Push via `simctl push`.
- **Deploy:** `scripts/release.sh` (symbol guard must hold ≥22 `_main`), attach to internal group.

## Out of scope (unchanged YAGNI)
Mount PATH-inclusion; Live Activity; `cd ~<mark>` tilde syntax; LAN reachability redesign (noted in
handoff as a separate product decision — flagged, not built here).
