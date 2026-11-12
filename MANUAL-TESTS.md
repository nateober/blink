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

## Feature D — Notification inbox (build 1109)
- [x] Received pushes are persisted and listable with the `notiflog` command (tapping a banner
      no longer loses the text). `notiflog clear` empties it. **Sim-verified 2026-05-29:** two
      `simctl push`es → `notiflog` lists both newest-first with `[kind host]` tags, title + body;
      `clear` → "No notifications yet." Recorded on both foreground-present and tap.
      Store: `FleetCore/NotificationLog` (6 tests); receipt hook in `AppDelegate.m` via the
      `@objc NotificationInbox` shim. **On-device:** send yourself a push, tap it, run `notiflog`.
      (Known gap: a push delivered while the app is fully killed is recorded only when tapped.)

## Feature C — Push notifications
- [ ] 🔒 APNs auth key (.p8) generated in the portal and stored via op-add.
- [ ] 🔒 Push capability enabled on App ID `com.obercode.blink` (if not auto-added during signing).
- [ ] Blink registers and publishes its APNs token to `~/.blink-notify/token` on the configured host.
- [ ] `blink_notify.py` sends a push that arrives on the device.
- [ ] Live Activity renders for a long-running `claude -p` session.
- [ ] 🔒 `blink_notify` wired into the `claude -p` wrapper on "needs input".

## Feature E — Dictation SmartKey (build 1120)
- [ ] The mic key renders in the SmartKeys bar (right of the tmux hamburger) in portrait and
      landscape without crowding the bar.
- [ ] First press asks for Microphone, then Speech Recognition; the strip then says to tap again
      (that press records nothing — by design, the alerts cancel the press).
- [ ] Tap: strip shows `Listening 0:0n`, the red dot and a moving level bar; partial words appear
      while speaking; tap again → the words are typed at the cursor, no Return sent.
- [ ] Hold ≥ 0.35 s and release: same, stops on release.
- [ ] In a tmux session running Claude Code: dictate a prompt, press Return, it runs.
- [ ] Curly apostrophes / unicode from the recognizer arrive intact (e.g. "don't").
- [ ] iOS 26 first run: if the SpeechAnalyzer model isn't installed, the first dictation uses the
      older recognizer and the model downloads for next time (check a second dictation later).
- [ ] Backgrounding mid-dictation (swipe up) ends it with what was heard; an incoming call too.
- [ ] Deny Speech in Settings → the strip explains and the mic stays shut.

## Feature F — General improvements (build after 1120)
Simulator-checked where it can be; these need the phone or iPad.
- [ ] **Prompt Snips:** new Snip → mode button next to Create → Prompt; it saves, reopens in Prompt
      mode, and sending it types the text and presses Return. (Snips can't open in the simulator.)
- [ ] **Links:** with a link on screen, Quick Actions → link icon opens it; with several, a list
      (newest first). Inside tmux, a link wrapped across two rows opens whole.
- [ ] **Cmd-click a link** on iPad with a keyboard/trackpad opens it; Cmd-click elsewhere still
      starts a mouse drag.
- [ ] **Select All:** selection menu → Select All → Copy gives the whole scrollback. Cmd-A on a
      hardware keyboard does the same.
- [ ] **⏺ in Claude Code:** the dot is a plain dot and the text after it lines up with the rows
      below. Check with your own font too.
- [ ] **Dark Mode theme:** Appearance → style → Dark Mode Theme; flip Control Center's Dark Mode and
      open terminals follow, including the margins.
- [ ] **Session links:** Settings → Link Actions → on, sign `blinkshell://host/ada?mosh=1&id=ada`.
      From Notes, tap the signed link → connects; tap again → returns to it. An unsigned link
      shows the command and asks (signed links replaced the `key=` links in Feature H).
- [ ] **Shortcuts:** "Open Terminal Session" with a host opens Blink connected; "Run Command on
      Host" returns output; an old "Run Fleet Command" shortcut still runs.
- [ ] **Sessions bar:** Settings → Display → Sessions Bar. Tabs show live titles (Claude Code's
      session names), tap switches, first terminal row is not covered, in Cover/Fit/Fill and landscape.
- [ ] **mosh after app switch (#2294):** mosh in, keyboard up, run a slow counter, switch apps and
      back: no lines lost. This fix is a hypothesis; if lines still vanish, say so.
- [ ] **Scrolling under output (#2267):** scroll up while an agent streams output: the view stays
      put and keeps responding. The reported iPad hang was never reproduced, so this is hardening.

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
- 1108 — **auth fix:** the Shortcut/`fleetexec` reached SSH but failed (`SSHError error 3`).
         Cause: headless auth hand-rolled key+password, but Blink uses a pure-agent model
         (agent + default keys + keyboard-interactive). HeadlessSSHRunner now resolves+auths via
         `BKConfig` + agent exactly like `ssh <alias>`. Also surfaces SSHError's real description.
         Sim-verified: readable errors, fast, no crash (real-key success is on-device only).
- Test on the latest (1108). On-device: host HostName already set to Tailscale IP (ada →
  100.64.0.3). Run `fleetexec ada uptime` in the terminal (fastest) or the Shortcut — should
  return output now. If it still errors, the message is now a readable SSH reason — capture it.
- 1120 — dictation SmartKey (branch `feat/voice-key`, off `raw`; not merged). Sim-verified key +
         permission flow + listening strip; transcription/insertion = device.

## Feature G: Copy All and Settings quick actions (build 1122)

- [ ] Double-tap the Command SmartKey: the bar shows Snippets, Copy All, Settings, New, Close, then More.
- [ ] In an ssh or mosh session with scrollback, Copy All: note "Copied N lines"; paste elsewhere has the whole buffer, scrollback included.
- [ ] Settings opens settings over a live remote session; closing it returns to the session still connected.

## Feature H: review fixes (build after 1122)

- [ ] **Fleet on bash hosts:** a Shortcut "Run Command on Host" against lightsail (bash) returns
      the output; `false` reports "command exited 1", not success.
- [ ] **Scripts that read stdin:** "Run Script on Host" with `cat` on one line and `echo after` on
      the next prints `after` and finishes at once instead of after 30 s.
- [ ] **Locked phone:** lock the phone, ask Siri to run a Blink command: it asks you to unlock first.
- [ ] **App lock:** with Settings → Auto Lock on and the app locked, tap a session link: nothing
      happens until Face ID; after unlocking the session opens (or the confirmation appears).
- [ ] **Signed links:** Settings → Link Actions → Sign a Link. The signed link runs without asking;
      edit any character of its cmd and it asks. Old `key=` links now ask. Replace Signing Key makes
      every earlier signed link ask.
- [ ] **Confirmation:** an unsigned link shows the command in monospace and Return cancels. A link
      with a run of spaces in its command is refused with a note.
- [ ] **Dictation and the lock button:** start dictating, lock the phone mid-sentence, unlock:
      the words are typed into the tab you started in.
- [ ] **Scrolled up under a prompt theme:** scroll up in a shell whose prompt queries the terminal
      (or run vim): the view stays where you put it until you type.

## Feature I: grid held while the app is not active (build after 1122)

- [ ] **Frozen rows after an app switch (the reported bug):** in mosh + tmux, hide and show the
      keyboard once, start something that keeps printing, switch to another app for a few
      seconds and come back. Every row is current, the bottom band included, with no `Ctrl-b r`.
- [ ] **Still resizes:** after coming back, hide the keyboard: the terminal grows to fill the
      screen and tmux redraws its status line at the new bottom. Rotate the phone: same.
- [ ] **Control Centre:** pull it down over a live session and dismiss it: nothing moves, and
      typing works at once.
- [ ] **App lock:** with Auto Lock on, come back through Face ID: the terminal fits the screen
      within a second of unlocking.
- [ ] **Local shell prompt:** in the `blink>` shell, fill the screen (`env`), hide the keyboard,
      show it again: no lines disappear and the prompt stays under the last line of output.
- [ ] **No stale frame on return (build 1125):** in mosh + tmux with the keyboard up, switch away
      and back: the tmux status line and current rows are there from the first moment, with no
      flash of older rows.

## Feature J: agent pushes and the tap (build after 1125)

Host side is installed on Ada (holds the key) and Jarvis (relays through Ada); Max needs
`scripts/fleet/install-agent-loop.sh --relay ada.ober` when it is next online. Claude Code
sessions started before the install don't have the hooks; restart one to test.

- [ ] **Needs input rings:** in a Claude Code session in tmux, ask for something that needs a
      permission, then leave Blink. A push arrives titled "<session> needs you".
- [ ] **The tap lands:** tap it. Blink opens on the tab attached to that tmux session. With no
      tab attached, a new tab opens and attaches (`mosh <host> -- blink-attach ...`).
- [ ] **Finishing is quiet:** let a turn finish while away. No sound or banner; one entry per
      session in Notification Center, and in `notiflog`.
- [ ] **Not while watching:** with the session on screen, a permission prompt shows no banner.
- [ ] **Window titles:** tab titles read `ada › main › zsh › ...` (set by `tm`).

## Feature K: Paste Image

- [ ] Copy a screenshot, open the quick actions (double-tap Command), tap Paste Image in a tmux
      tab on a fleet host: "Sending image to ada", then a path under `~/Scratch/blink-paste/`
      appears at the cursor and Claude Code reads the image.
- [ ] With an image and no text on the clipboard, the edit menu's Paste does the same.
- [ ] In the local `blink>` shell it says it needs a tmux session on a fleet host.

## Feature L: dictation into an agent

- [ ] With Claude Code in front, dictate: the compose area opens in Prompt mode holding the
      words; send it and it reaches the prompt.
- [ ] At a shell prompt, or in vim, dictation still types at the cursor.
- [ ] Settings > Agents > "Dictate into the compose area" off: words are typed everywhere.

## Feature M: Sessions

- [ ] Quick actions > Sessions lists the tmux sessions on Ada and Jarvis; ones needing input are
      first, then finished, then running, then plain shells.
- [ ] Tapping a session with a tab goes to that tab; one without opens a new tab attached to it.
- [ ] Settings > Agents lists the hosts that answered; "Forget these hosts" rescans next time.

## Feature N: Live Activity

- [ ] First run asks "Allow Live Activities from Blink?"; allow it.
- [ ] `liveactivity start ada agents running test` in the local shell shows it on the lock screen
      and in the Dynamic Island; `liveactivity end` removes it.
- [ ] **By push:** after Blink has been opened once on this build, `ls ~/.blink-notify/` on Ada
      shows `activity-start-token`. Start a Claude Code turn on Ada: the activity appears with
      "running"; a permission prompt turns it to "needs input"; it ends when nothing is running.
- [ ] Tapping the activity opens Blink on Sessions.

## Feature O: terminal comes back after its page is killed

- [ ] Leave Blink in the background long enough (or under memory pressure) that the terminal
      would have come back blank: it reloads and the session redraws within a few seconds.
- [ ] Build 1127: after that, typing reaches the session without tapping or switching tabs,
      and a local `blink>` tab shows its prompt again.
- [ ] Build 1127: over a day of agents running on Ada, Blink is not killed in the background
      (coming back does not start the app over). If it is, send the log named in
      `docs/bugs.md` (2026-11-12).

