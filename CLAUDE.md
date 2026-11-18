# Blink — fleet-native fork (project instructions)

**Read `handoff.md` first — it's the canonical, current record** (state, environment/credentials,
the release pipeline, code map, and how to resume cold). This file is the short pointer that loads
automatically; `handoff.md` has the detail.

## What this is
Nate's personal fork of [blinksh/blink](https://github.com/blinksh/blink) (GPL-3.0 iOS terminal),
made "fleet-native" for driving his Tailscale-meshed Macs from an iPhone. **TestFlight-only, never
App Store** (GPL code he doesn't own + App-Store-terms conflict + "Blink" trademark).

## Current state (2026-11-13)
- **The agent loop** is the newest work (plan and prior art:
  `docs/superpowers/plans/2026-11-10-agent-loop.md`): a Claude Code hook on the hosts pushes the
  phone when an agent needs input and a tap goes to that tmux session; Sessions (a switcher
  across hosts); Paste Image; dictation into the compose area when an agent is in front; the
  Live Activity, now with its widget target and started by push; and the terminal page reloading
  after iOS kills it. Host side: `scripts/fleet/install-agent-loop.sh` (installed on Ada and
  Jarvis; Max still needs it). `tm` sets the tmux window title the app reads.
- **Build 1127** (2026-11-12) fixes tabs coming back blank or not taking typing after iOS kills
  the terminal page, and cuts the background wakes suspected of getting the app killed (see
  `docs/bugs.md`; the crashes are not root-caused). Check: `tools/sim-page-kill.sh`.
- **Build 1128** (2026-11-13): a mosh tab restored after the app was killed runs its command
  again instead of sitting on "mosh: Last contact", and the terminal page reports its real size
  when it starts (it used to say 43 columns, then 65, and tmux drew for both). Check: `tools/sim-mosh-restore.sh`.
- **Build 1129** (2026-11-13): a mosh tab whose server is gone (host restarted, server timed
  out) notices within about 25 s and connects again into the tmux session it was showing
  (`MoshWatch`, `FleetCore/MoshRules.swift`); hosts end mosh-servers after 3 days without a
  client (`MOSH_SERVER_NETWORK_TMOUT` in `~/.zshenv`). Check: `tools/sim-mosh-restore.sh dead`.
- **Build 1130** (2026-11-13): Approve, Deny and Open in Claude on the push for a permission
  prompt (`PermissionRequest` hook, `blink-decide`); the app sends iOS's reports about itself
  (exits, crashes) to `~/Scratch/blink-diag/`, read with `blink-diag`; upstream's
  synchronized-output patch. Hosts: Claude Code fullscreen renderer and Remote Control at
  startup on Ada and Jarvis, tmux 3.8 installed (Ada's running server is 3.6a until restarted).
  Research and sources: `docs/research/2026-11-13-phone-experience.md`.
- **Build 1131** (2026-11-18): the key row above the on-screen keyboard is back on iPad (it had
  been missing since upstream's September 2025 keyboard refactor; `docs/bugs.md`).
- **Build 1132** (2026-11-18): tmux menu and mic keys on the iPad key row, upstream's
  trackpad drag clean-up (`822e7777`), the optional floating D-pad from upstream PR 2291 (off
  by default). Pre-release look at both device classes: `tools/sim-devices.sh`.
- **Build 1125** fixed frozen rows and stale frames after an app switch. Bugs Nate reports go in
  `docs/bugs.md`.
- `raw` is the baseline and holds everything shipped (pushed to GitHub 2026-11-18).
- **Upstream draft PR:** the dictation key alone is offered to blinksh/blink as draft PR #2297
  from branch `voice-key-upstream`. Changes the maintainer asks for go on that branch, not `raw`.

## Open items — these need NATE (surface them at the start of a fresh session)
0. **Restart Ada's tmux server** when no session matters (`tmux kill-server` ends them all):
   until then it runs 3.6a and the flicker fix from 3.8 is not in effect. And build 1130 on the
   phone: MANUAL-TESTS Features R, S, T.
0. **Builds 1127 to 1129 on the phone**: does coming back still give a blank or dead tab, does
   the app still get killed (if so, the phone's crash or jetsam log comes first, `docs/bugs.md`),
   does a killed mosh tab reconnect (MANUAL-TESTS Feature P), and does a tab left for days or
   across a host restart come back by itself (Feature Q)?
1. **Device checks for the agent loop** (MANUAL-TESTS Features J to O): none of the push, SSH or
   microphone paths can be confirmed in the simulator.
2. **Install the host side on Max** when it is online:
   `scripts/fleet/install-agent-loop.sh --relay ada.ober`.
3. **Build 1125's leave-and-return check** (Feature I), the dictation key's checklist (Feature E),
   and builds 1131 and 1132 on the iPad (Features U, V).

## Working here
```bash
git checkout raw                              # baseline; branch new work off it
swift test --package-path tools/FleetCore     # 136 tests = pure-logic verification path
uv run --with pytest pytest scripts/fleet -q   # host-side scripts (hook, push, session list)
for t in tools/termjs-tests/*.test.js; do node "$t"; done   # terminal page
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
