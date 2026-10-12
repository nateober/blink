# Blink — fleet-native fork (project instructions)

**Read `handoff.md` first — it's the canonical, current record** (state, environment/credentials,
the release pipeline, code map, and how to resume cold). This file is the short pointer that loads
automatically; `handoff.md` has the detail.

## What this is
Nate's personal fork of [blinksh/blink](https://github.com/blinksh/blink) (GPL-3.0 iOS terminal),
made "fleet-native" for driving his Tailscale-meshed Macs from an iPhone. **TestFlight-only, never
App Store** (GPL code he doesn't own + App-Store-terms conflict + "Blink" trademark).

## Current state (2026-10-12)
- **Build 1120** (dictation SmartKey) is on TestFlight internal. `feat/voice-key` was merged into
  `raw` on 2026-10-12 (Nate uses the key daily), so `raw` is the baseline and holds everything
  shipped. `feat/tmux-key-config` (iPad tmux key + file-configurable sequence) is still unreleased.
- **Upstream draft PR:** the dictation key alone (no tmux key, no FleetCore) is offered to
  blinksh/blink as draft PR #2297 from branch `voice-key-upstream` (one commit on `upstream/raw`).
  Changes the maintainer asks for go on that branch, not on `raw`.
- Shipped: iCloud-folder mounts (linked into `~/<name>`), `Run Fleet Command` + `Run Fleet Script`
  App Intents + the `fleetexec` terminal twin, push + `notiflog` inbox, `$PATH` inclusion, the tmux
  menu SmartKey, and (1120) the dictation SmartKey (on-device speech, live strip, typed at the
  cursor). Live Activity app-side ships but is dormant until the widget target exists.

## Open items — these need NATE (surface them at the start of a fresh session)
1. **Add the Live Activity widget-extension target in Xcode** → `docs/LIVE-ACTIVITY-SETUP.md`. Until
   then the lock-screen / Dynamic Island indicator can't render.
2. **Finish the dictation key's device checklist** (MANUAL-TESTS § Feature E: bare shell, vim,
   hold versus tap), and decide whether `feat/tmux-key-config` ships.
3. **On-device acceptance** (sim can't cover these): iCloud-folder linking into `~`, `addpath` →
   `$PATH` membership, `Run Fleet Script`, real-APNs push. Checklist: `MANUAL-TESTS.md`.

## Working here
```bash
git checkout raw                              # baseline; branch new work off it
swift test --package-path tools/FleetCore     # 51 tests = pure-logic verification path
# build for sim: xcodebuild ... -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' ENABLE_DEBUG_DYLIB=NO
#   (keep code signing ON: CODE_SIGNING_ALLOWED=NO drops the app-group entitlement → crash in Migrator at launch)
# ship a TestFlight build: scripts/release.sh  (detached, ~15 min; auto-bumps build #)
# add a new source file to the Xcode target: tools/add_to_target.py <file> <Target>
```
Pure logic lives in `tools/FleetCore` (unit-tested); app commands are `@_cdecl *_main` shims
registered in `Resources/blinkCommandsDictionary.plist`.

## Conventions
- **Commits:** Conventional Commits; **no AI co-author trailer, no "Claude" name, no "generated
  with" footer** (per Nate's global CLAUDE.md). Commit/push only when asked.
- `raw` is the buildable baseline — branch off it, don't commit straight to it.
- Don't claim a feature works until it's verified (FleetCore test, sim drive, or device); say what
  you didn't verify. Device/Xcode-only steps are Nate's.
