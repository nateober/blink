# Fleet-native Blink — Design Spec

**Date:** 2026-05-25
**Author:** Ada (for Nate Ober)
**Repo:** `nateober/blink` fork, branch `feat/fleet-native`
**Status:** Approved (design), pending implementation plan

## Summary

Three enhancements to the personal Blink fork, built to fit Nate's actual habits
(a multi-machine Mac fleet driven by `ssh <host> claude -p`, heavy travel, an
all-iCloud config life):

- **A. Mountable iCloud/Files folders** — pick any Files/iCloud folder, persist it
  via security-scoped bookmarks, mount it in Blink's filesystem, optionally add to `$PATH`.
- **B. App Intents / Shortcuts** — run a command on a fleet host from Shortcuts/Siri
  and get the output back, without opening the terminal.
- **C. Push notifications for agent attention** — Blink can be pushed when a
  long-running remote `claude -p` needs input, with a Live Activity for progress.

Built in isolation on `feat/fleet-native`, executed by a Ralph loop with TDD on the
logic units. The loop certifies **compile + sign + archive + green unit tests +
clean review**. It explicitly does NOT certify on-device behavior; those are manual
acceptance steps captured in `MANUAL-TESTS.md`.

## Non-goals (YAGNI)

- Apple Watch targets (deferred; no watch app exists).
- A WebAssembly runtime / native binary execution (out of scope; iOS forbids exec of
  arbitrary Mach-O — `$PATH` additions run scripts only: sh/python/lua/built-ins).
- Bidirectional CloudKit sync daemon.
- Replacing Blink's existing host/key model — Feature A complements it via the
  existing `ssh_config` file path; it does not rewrite BKHosts.

## Constraints & ground truth (verified in code this session)

- Blink reads a real SSH config at `[blinkURL]/ssh_config` (`BlinkConfig/BlinkPaths.m:224`).
- `iCloudDriveDocuments` resolves the ubiquity container `iCloud.$(CLOUD_ID)/Documents`
  (`BlinkPaths.m:79-89`); `~/iCloud` is symlinked to it via `_linkAtPath`.
- `Info.plist`'s `NSUbiquitousContainers` key points at upstream `iCloud.sh.blink.blinkshell`,
  NOT our `iCloud.com.obercode.blink` — so our container is not Finder-visible on Macs yet.
- `BlinkFiles/LocalFiles.swift` provides a `Local` Translator — the mount backing.
- PATH is assembled in `MCPSession` via `setenv PATH=$PATH:~/Library/bin:~/Documents/bin`.
- Commands are dispatched via `dlsym(RTLD_MAIN_ONLY, "<cmd>_main")`; the build MUST keep
  these symbols (release.sh sets `STRIP_STYLE=non-global`, `DEAD_CODE_STRIPPING=NO`,
  `-Wl,-export_dynamic`). Any new built-in command must follow the same `*_main` pattern.
- a-Shell (github.com/holzschu/a-shell, GPL-3, same `ios_system` engine) already
  implements pickFolder/bookmarks — port with attribution, do not reinvent.

## Feature A — Mountable iCloud/Files folders

### Behavior
New built-in commands (mirroring a-Shell for muscle memory):
`pickFolder`, `bookmark`, `showmarks`, `jump <mark>`, `cd ~<mark>`, `renamemark`, `deletemark`.

`pickFolder` presents `UIDocumentPickerViewController` in folder mode; the chosen folder
is mounted at `~/mnt/<name>` and bookmarked. Bookmarks survive relaunch.

### Units
- **`BookmarkStore`** (new, Swift, in BlinkConfig): CRUD over named security-scoped
  bookmarks. Persists bookmark `Data` in the app-group container. Resolves on launch,
  calls `startAccessingSecurityScopedResource`, detects/refreshes stale bookmarks.
  *Pure-ish; unit-testable with temp dirs + synthetic bookmark data.*
- **`MountManager`** (new): maps resolved bookmark URLs to `~/mnt/<name>` using the
  existing `Local` translator; applies optional `addToPath` (append `<name>/bin`).
- **command shims** (`*_main`): thin Obj-C/Swift entry points dispatching to the above.
- **Info.plist fix**: repoint `NSUbiquitousContainers` to `$(CLOUD_ID)` (Finder-visible
  container → delivers the ssh_config-sync idea as a side effect).

### Verification
- Unit: BookmarkStore add/list/rename/delete/resolve/stale-handling.
- Build: archive clean; new `*_main` symbols present in export trie.
- Manual (device): `pickFolder` picks an iCloud folder; it appears at `~/mnt/<name>`;
  survives relaunch; PATH toggle runs a script from it.

## Feature B — App Intents / Shortcuts ("Ask the fleet")

### Behavior
In-app App Intents (no new target). `RunFleetCommandIntent(host, command)` runs the
command on the host over SSH headless and returns stdout as the intent result.
`AppShortcutsProvider` exposes phrases ("Run on Ada", "Ask the fleet").

### Units
- **`HeadlessSSHRunner`** (new, Swift, in SSH or a thin app-layer): given a Blink host
  (or user@host) + command, opens an SSH channel, runs one command, captures
  stdout/stderr/exit, tears down. No terminal UI. Reuses the existing `SSHClient`.
  *Unit-testable against localhost sshd.*
- **`RunFleetCommandIntent`** (AppIntent) + **`BlinkShortcuts`** (AppShortcutsProvider).

### Verification
- Unit: HeadlessSSHRunner against `127.0.0.1` sshd (run a known command, assert output/exit).
- Build: archive clean; App Intents metadata present.
- Manual (device): the Shortcut appears, runs `claude -p` on a host, returns text.

## Feature C — Push notifications for agent attention

### Behavior
Blink registers for remote notifications, publishes its APNs device token to a fleet
host, and renders incoming "needs input" pushes (+ a Live Activity for long runs). A
fleet-side helper sends the push when `claude -p` pauses for input.

### Units
- **app entitlement/capability**: re-add `aps-environment`; enable Push on the bundle ID
  (automatic via `-allowProvisioningUpdates` once the capability is on the App ID).
- **`PushRegistrar`** (new, Swift): registers, captures the APNs token, persists it,
  and publishes it via SSH to `~/.blink-notify/token` on a configured host.
  *Token-store + payload parsing unit-testable; APNs round-trip is not.*
- **`AgentActivity`** (ActivityKit Live Activity): progress/needs-input states.
- **fleet helper `blink-notify`** (Python, lives in `scripts/fleet/`): sends an APNs
  push via the `.p8` auth key + token; meant to be called from Nate's `claude -p`
  wrapper on "needs input". Not part of the iOS build; shipped in-repo + documented.

### Human gates (cannot be automated)
1. Generate the **APNs auth key (.p8)** in the developer portal → stored via `op-add`.
2. Confirm re-adding the Push capability (reverses the earlier iCloud-only choice).
3. On-device: receive a real push; verify Live Activity.

### Verification
- Unit: payload build + token store/serialize; `blink-notify` arg parsing + payload
  (dry-run mode, no real send).
- Build: archive clean WITH the push entitlement present in the signed app.
- Manual (device + fleet): end-to-end push round trip.

## Execution model

- Branch `feat/fleet-native` (in-place; rationale: dedicated fork clone, avoids
  re-downloading ~300 MB xcframeworks a worktree would require).
- Ralph loop: take next plan task → TDD (write failing test → implement → `xcodebuild
  test` on the iOS 26.5 simulator for logic units) → commit small. Per-iteration:
  fast compile check. Per-milestone: full `scripts/release.sh` archive.
- `MANUAL-TESTS.md` accumulates on-device acceptance steps as features land.
- Final hardening: `requesting-code-review` + `security-review` over the cumulative
  diff; fix findings; then a milestone TestFlight build for device acceptance.
- Human-gated items are explicit checkpoints, not blockers — the loop continues on
  everything else and parks them in `MANUAL-TESTS.md`.

## Definition of "loop-complete" vs "done"

- **Loop-complete** (autonomous): compiles, signs, archives; unit tests green; code
  review + security review clean. The loop may assert ONLY this.
- **Done** (requires Nate): on-device acceptance for A/B/C + APNs key + fleet wiring for C.

## Risks

- iOS UI/entitlement features can't be exercised headlessly → real risk of
  "compiles but misbehaves." Mitigation: maximize pure-logic units behind testable
  interfaces; keep UI shims thin; explicit manual acceptance list.
- App Intents discovery quirks across iOS versions → keep intents minimal, in-app.
- Stale security-scoped bookmarks (iCloud eviction) → BookmarkStore must detect and
  trigger re-download / re-pick gracefully.
- Heavy/slow archive cycle → tier verification (compile fast, archive at milestones).
