# Blink fork — handoff for the next session

**Last updated:** 2026-05-29 · **Branch:** `feat/fleet-native` · **PR:** nateober/blink#1 (open vs `raw`, not merged)

This is Nate's personal fork of [blinksh/blink](https://github.com/blinksh/blink) (iOS terminal),
published to **TestFlight for personal use** under bundle id **`com.obercode.blink`** ("Blink For Personal").
The goal: a "fleet-native" Blink with three features that fit Nate's habits (Mac fleet + `ssh <host> claude -p`,
heavy travel, all-iCloud config). Built almost entirely autonomously via a Ralph loop.

## TL;DR current state
- 3 features built, reviewed, hardened, shipped to TestFlight: **mountable iCloud folders, App Intents/Shortcuts, push notifications.**
- Latest build: **1108** live in the TestFlight internal group. (History: …1106 hardening; 1107 runloop fix; **1108 — 2026-05-29 SSH auth fix (agent + default keys + keyboard-interactive)**.)
- **1108 — the `SSHError error 3` after the runloop fix:** once 1107 made the dial actually run, the Shortcut/`fleetexec` reached SSH but failed auth. Cause: HeadlessSSHRunner hand-rolled `AuthPublicKey(hostKey)+AuthPassword`, but Blink moved to a **pure-agent** model (`SSHConfigProvider`): auth goes through an `SSHAgent` loaded with the host's signers **or the default signers**, plus **keyboard-interactive**. Hosts using a default key (none bound to the host) or keyboard-interactive password were never tried headlessly. Fix: `HeadlessSSHRunner.run(alias:command:)` now builds the connection via `BKConfig` + agent + `host.sshClientConfig` — the SAME path as `ssh <alias>` — answering keyboard-interactive with the stored password. Also surfaces `SSHError.description` (it's not a LocalizedError, so `localizedDescription` gave the useless "error 3"). All 3 callers pass the alias now. **Sim-verified** (readable errors, fast, no crash); real-key success is on-device only — `fleetexec ada uptime` is the quickest device check.
- **1107 — THE Shortcut "unknown error" root cause (finally):** `HeadlessSSHRunner` ran the SSH pipeline on the Swift-concurrency pool, which never spins a RunLoop. But Blink's SSH framework only progresses while the RunLoop captured at `SSHClient.init` is *running* (`.subscribe(on: rloop)`); the interactive `ssh` command works because it spins it (`ssh.swift` `awaitRunLoop` → `CFRunLoopRun`). So the headless dial **hung**, and iOS killed the App Intent with its generic "unknown error". (1106's legible-error/timeout never even fired — the watchdog killed the process first.) **Fix:** dial on a dedicated `Thread` that drives its run loop until completion. **Sim-verified** via the new `fleetexec` command: a dial to a reachable sshd with a bad password now fails in <3s with a real SSH error instead of hanging 30s. New terminal command **`fleetexec <host> <cmd>`** is the shell twin of the App Intent (same BKHosts/HeadlessSSHRunner path) for on-device debugging. Spec: `docs/superpowers/specs/2026-05-29-fleet-reachability-design.md` covers reachability (Tailscale); the runloop diagnosis is in commit `03f52670`.
- **1106 hardening (spec+plan in `docs/superpowers/{specs,plans}/2026-05-29-fleet-native-hardening*`):**
  - `HeadlessSSHRunner` now captures **stderr** + the **real remote exit code** (in-band `__BLINK_EXIT_<n>__` trailer parsed by pure `FleetCore/ExitTrailer`, since the SSH framework never exposed exit status) + enforces a **30s overall deadline**. The App Intent throws `runFailed("command exited N: <stderr>")` on non-zero exit instead of a false success.
  - `mounts.swift`: single-slot `ScopeHolder` **releases the prior security scope** on jump/pickFolder (was leaking); **collision-safe mount names** via `MountManager.uniqueName` (was silently clobbering).
  - PushRegistrar token-publish honors stored password + trust-on-first-use (was orphaned in the tree).
  - FleetCore: **22 tests green** (added ExitTrailer ×7, uniqueName ×3). Sim-validated via the ios-tester agent: showmarks/pickFolder/push all correct.
- **On-device acceptance is still the main open work** (see "Open threads"). Everything is compile/sign/archive/unit-test + sim verified; real-device + real-APNs + Shortcut-over-LAN remain.

## Environment & access (verify, don't trust — things drift)
- **Build host:** Ada (this Mac mini). Xcode 26.5, iOS 26.5 SDK + iPhone 17 simulator. `xcode-select -p` → `/Applications/Xcode.app/...`.
- **Repo:** `~/code/blink`. origin = `git@github.com:nateober/blink` (fork), upstream = `blinksh/blink`. Default branch is `raw` (not main/master).
- **Apple Developer:** Team ID `684GQ6L3D9`, Issuer/Developer ID `9ff16463-2c73-4e60-8bf9-273267673229`, Apple ID nateober@gmail.com. Canonical details in the wiki: `~/Documents/Wiki/work/apple-developer.md` ([[apple-developer]]).
- **Credentials in 1Password** (vault "Ada - Claude Usage", via `op`):
  - `App Store Connect API - Team Key` — Key ID `S3MYBGRBL4` (Admin role; the App-Manager key `HY65N982F5` was revoked). .p8 at `~/.appstoreconnect/private_keys/AuthKey_S3MYBGRBL4.p8`.
  - `Apple APNs Auth Key - Blink Push` — Key ID `AG8A58DXW9`. .p8 at `~/.appstoreconnect/apns/AuthKey_AG8A58DXW9.p8`. Topic `com.obercode.blink`.
- **ASC app:** Apple ID `6771422199`. **Internal TestFlight group** id `cb615610-fe31-4df9-83d7-46588611e0d2` ("Nate (Internal)"), Nate is a tester.

## The build pipeline — `scripts/release.sh` (READ THIS before building)
One command: archives → symbol-guards → uploads → waits for ASC processing → attaches to the internal group, auto-bumping the build number from the ASC max. Critical hard-won flags it encodes:
- **`STRIP_STYLE=non-global` + `DEAD_CODE_STRIPPING=NO` + `BLINK_OTHER_LDFLAGS=-Wl,-export_dynamic`** — Blink dispatches built-in commands via `dlsym(RTLD_MAIN_ONLY, "<cmd>_main")`. The default `strip -all` deletes those symbols (only referenced by dlsym string), breaking EVERY built-in command at runtime (`config: command not found`). These flags keep them. **Symbol guard:** after archive, `xcrun dyld_info -exports .../Blink.app/Blink | grep -cE '_main$'` must be ≥ 22 (currently 28 = 22 base + 6 new mount commands).
- **`/usr/bin` ahead of PATH** for export — Homebrew `rsync 3.4.x` breaks Xcode's IPA packaging ("Copy failed"); Apple's openrsync works.
- Auth via the ASC API key (`-authenticationKey*`) so signing + upload are unattended.
- **release.sh runs detached via `nohup ... &`** in practice (long: ~15 min incl. ASC processing). To know when it's done, poll the log or run a background `until grep -qE "Attached build|FAILED" /tmp/release_*.log; do sleep 20; done`.

## Adding files to the Xcode project — `tools/add_to_target.py`
The high-level `mod-pbxproj add_file()` **crashes** on this SPM-heavy project (build files without `fileRef`). The helper uses the low-level object API instead. **Quirks:** NOT idempotent (its dup-check doesn't match) — always run on a clean pbxproj and add each file exactly once; verify with `grep -c "<File>.swift in Sources"` (expect 2 = build-file def + phase ref). It also cosmetically strips comment labels from `PBXFileSystemSynchronizedBuildFileExceptionSet` (Xcode 16 synced-folders); harmless. Always compile-verify after.

## Testing iOS here — what works / what doesn't (each gotcha cost a build cycle)
- **Pure logic → `FleetCore` SPM package** (`tools/FleetCore`): `swift test` runs Mac-native in ~0.01s, no sim/xcframeworks. The SAME .swift files are added to the `BlinkConfig` framework target for the app. 12 tests green. THIS is the fast verification path.
- **Sim builds work** (xcframeworks have sim slices): `-destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'`.
- **`simctl` is the verification toolkit:** boot / install / launch / **push** (`simctl push booted com.obercode.blink payload.json`) / `io screenshot` (then Read the PNG to verify visually) / openurl / privacy. Push delivery + the notification-permission prompt were verified this way.
- **Mac Catalyst native tests FAIL** — vendored xcframeworks (openssl/OpenSSH/vim/...) have **no Catalyst slices**.
- **The sim can't read host `/tmp`** (separate filesystem) but **shares host localhost** (sim → 127.0.0.1 reaches Ada's sshd).
- **`BlinkTests` target is pre-broken upstream** (`SessionParamsTests` references removed `MCPParams` members; `BKSessionParamsSnapshotting` missing) → it won't compile, blocking `-only-testing` runs. Not our bug.
- **App Intents mask errors:** a thrown error that isn't `CustomLocalizedStringResourceConvertible` shows as "unspecified error" in Shortcuts. Always wrap.
- **No UI automation wired** — taps/typing on the sim need `idb` or XCUITest (NOT installed). This blocked autonomous testing of the picker + Shortcut. See "ios-tester agent" below.

## The three features
### A. Mountable iCloud/Files folders
Commands `pickFolder` / `bookmark` / `showmarks` / `jump` / `renamemark` / `deletemark` (model: chdir into a security-scoped folder, NOT `~/mnt` symlinks). Code: `Blink/Commands/mounts.swift` (the `@_cdecl *_main` shims) + `tools/FleetCore/Sources/FleetCore/{BookmarkStore,MountManager}.swift` (tested core). Registered in `Resources/blinkCommandsDictionary.plist`. `Info.plist` `NSUbiquitousContainers` repointed to `iCloud.com.obercode.blink` so the app's iCloud folder is Finder-visible on Macs. `cd ~<mark>` shell-tilde syntax NOT implemented (use `jump`). PATH-inclusion for mounted `bin/` DEFERRED (YAGNI).

### B. App Intents / Shortcuts — "Run `<cmd>` on `<host>`"
`Blink/Fleet/FleetIntents.swift` (`RunFleetCommandIntent`, `BlinkFleetShortcuts`) + `Blink/Fleet/HeadlessSSHRunner.swift` (one-shot SSH exec on `SSHClient.dial → requestExec → Stream.read`, Combine→async). Resolves user/host/key from `BKHosts.withHost` + `BKPubKey.loadPrivateKey`, AND the stored password (`h.password`). Host-key: strict (reject unknown) by default, but the intent passes `acceptUnknownHostKeys: true` (trust-on-first-use for owner's own fleet). In-app App Intent (no extension target). **Compile-verified only — never run on device successfully yet (see open threads).**

### C. Push notifications
`Blink/Fleet/PushRegistrar.swift` (@objc; register + capture APNs token + persist via `APNSTokenStore` + best-effort SSH-publish token to `~/.blink-notify/token` on host alias "push-notify"/"ada") hooked into `Blink/AppDelegate.m` (didFinishLaunching + didRegister callbacks). Payload models + token store in `tools/FleetCore/Sources/FleetCore/PushModels.swift`. Fleet sender: `scripts/fleet/blink_notify.py` (+ README, 4 pytest green). `aps-environment` entitlement present + in signed builds; Push capability auto-provisioned on the App ID. **Live Activity DEFERRED** (needs a widget-extension target). Push *delivery+handling* verified on sim via `simctl push`; real APNs end-to-end needs a device token (only appears once the app runs on Nate's iPhone).

## Open threads (what's actually left)
1. **Device acceptance (Nate-only):** install 1105, test the Shortcut (the "unspecified error" should now show the real cause), the folder picker, and `ssh <alias>` in the terminal.
2. **The Shortcut bug:** Nate hit "unspecified error" on a host he created IN the fork. 1105 surfaces the real error + does trust-on-first-use. If it still fails, the surfaced "SSH failed: …" message tells us the cause (auth / unreachable / etc.). **Reachability caveat:** fleet hosts are LAN IPs (e.g. ada = 192.168.86.21) — the Shortcut/SSH only works when the phone is on the home LAN or WireGuard, NOT cellular. This may be the real cause.
3. **Saved-hosts question:** Nate asked "why no way to load saved hosts via a command?" Answer: `ssh <alias>` / `mosh <alias>` use saved Host config. Pending: confirm `ssh <alias>` resolves saved hosts in the fork (should — it's core Blink). If not, separate bug.
4. **Push end-to-end:** APNs key is in place. Need the device token (install 1105 → allow notifications → token publishes to `~/.blink-notify/token` on ada, or read it from the `[blink-notify] APNs device token: …` log line). Then `scripts/fleet/blink_notify.py` fires a test push.
5. **PR #1:** review/merge decision is Nate's (left unmerged pending device tests).
6. **ios-tester agent (proposed, not built):** Nate asked about a reusable iPhone-testing agent. Recommendation: build `~/.claude/agents/ios-tester.md` encoding this file's "Testing iOS here" section, AND install `idb` (Meta's iOS Debug Bridge) for real UI automation (tap/type/swipe) — the missing primitive that blocked autonomous picker/Shortcut testing. Awaiting Nate's go.
7. **Deferred by design (YAGNI):** mount PATH-inclusion; Live Activity (widget extension).
8. **iCloud container separation:** this fork (`iCloud.com.obercode.blink`) is SEPARATE from official Blink (`sh.blink.blinkshell`) — hosts/keys/snippets do NOT carry over. Nate confirmed he created hosts IN the fork, so this isn't the current blocker, but remember it.
9. **Entitlements oddity:** Xcode auto-management left empty `keychain-access-groups <array/>`, `associated-domains <array/>`, `user-fonts <array/>`. Host passwords use `accessGroup:nil` (default group) so they work, but the empty keychain-access-groups could affect the FileProvider extension's credential sharing. Not confirmed broken; watch for it.

## Process artifacts
- **Spec:** `docs/superpowers/specs/2026-05-25-fleet-native-blink-design.md`
- **Plan (with all task statuses + recon findings):** `docs/superpowers/plans/2026-05-25-fleet-native-blink.md`
- **Manual/on-device acceptance checklist:** `MANUAL-TESTS.md`
- **Live web build-log (Nate watches this):** `~/loop-log/index.html` (generator `~/loop-log/gen.py`, `gen.py add --iter N --phase ... --title ... --body ... [--build N] [--image f.png]`; auto-refreshes every 20s). 17 passes recorded.
- This was driven by the **ralph-loop** plugin (`/ralph-loop`, cancel with `/cancel-ralph`). It was cancelled at iteration 21.

## How to resume cold
```bash
cd ~/code/blink && git checkout feat/fleet-native && git log --oneline -8
swift test --package-path tools/FleetCore        # 12 tests green = core healthy
cat MANUAL-TESTS.md                               # what needs device testing
# to cut a new build: scripts/release.sh  (see flags above; ~15 min)
# to verify a fix on sim: build for sim → simctl install/launch/push → simctl io screenshot → Read the png
```
Conventions: Conventional Commits, no AI trailer (per Nate's global CLAUDE.md). Commit/push only when asked. Branch off `raw`, never commit straight to it for shared work (this fork's `raw` is the buildable baseline).
