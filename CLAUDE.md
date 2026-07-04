# Blink — fleet-native fork (project instructions)

**Read `handoff.md` first — it's the canonical, current record** (state, environment/credentials,
the release pipeline, code map, and how to resume cold). This file is the short pointer that loads
automatically; `handoff.md` has the detail.

## What this is
Nate's personal fork of [blinksh/blink](https://github.com/blinksh/blink) (GPL-3.0 iOS terminal),
made "fleet-native" for driving his Tailscale-meshed Macs from an iPhone. **TestFlight-only, never
App Store** (GPL code he doesn't own + App-Store-terms conflict + "Blink" trademark).

## Current state (2026-05-30)
- **Build 1114** live in TestFlight internal. Branch **`feat/notification-inbox`**; **PR #1 merged**
  to `raw`, **PR #2 open** with all post-merge work.
- Shipped: iCloud-folder mounts (linked into `~/<name>`), `Run Fleet Command` + `Run Fleet Script`
  App Intents + the `fleetexec` terminal twin, push + `notiflog` inbox, `$PATH` inclusion. Live
  Activity app-side ships but is dormant until the widget target exists.

## Open items — these need NATE (surface them at the start of a fresh session)
1. **Add the Live Activity widget-extension target in Xcode** → `docs/LIVE-ACTIVITY-SETUP.md`. Until
   then the lock-screen / Dynamic Island indicator can't render.
2. **Merge PR #2** (`feat/notification-inbox` → `raw`) when satisfied.
3. **On-device acceptance** (sim can't cover these): iCloud-folder linking into `~`, `addpath` →
   `$PATH` membership, `Run Fleet Script`, real-APNs push. Checklist: `MANUAL-TESTS.md`.

## Working here
```bash
git checkout feat/notification-inbox          # ongoing branch (NOT feat/fleet-native)
swift test --package-path tools/FleetCore     # 42 tests = pure-logic verification path
# build for sim: XcodeBuildMCP build_sim (or -destination 'platform=iOS Simulator,name=iPhone 17')
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
