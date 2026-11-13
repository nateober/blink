# What would make driving agents from the phone better (research, 2026-11-13)

Standard-depth pass: four search legs, one of them looking for reasons the current setup is
the wrong approach, then direct checks of the sources that changed a decision. Recheck by
2027-02 (tool behaviour moves fast).

## Prior art

- Established practice: Claude Code has a fullscreen renderer (`/tui fullscreen`, setting
  `tui`, or `CLAUDE_CODE_NO_FLICKER=1`) that draws on the alternate screen and "eliminates
  flicker"; the conversation then lives in Claude Code, not in tmux scrollback (PgUp/PgDn,
  the wheel, `Ctrl+o` for the transcript). Its docs also say tmux through the 3.6 series has
  no synchronized output, "so under those versions you may see more flicker during redraws".
  (https://code.claude.com/docs/en/fullscreen, https://code.claude.com/docs/en/terminal-config,
  read 2026-11-13)
- tmux 3.7 added synchronized output for applications ("Add support for applications to use
  synchronized output mode (DECSET 2026) to prevent screen tearing during rapid updates") and
  3.8 fixes "flicker with alternate screen applications".
  (https://raw.githubusercontent.com/tmux/tmux/master/CHANGES, read 2026-11-13)
- Remote Control drives a session running on your own machine from the Claude app; the docs
  recommend running it inside tmux. Setting `remoteControlAtStartup` turns it on for every
  interactive session. (https://code.claude.com/docs/en/remote-control, read 2026-11-13)
- A `PermissionRequest` hook can answer a permission prompt with allow or deny.
  (https://code.claude.com/docs/en/hooks, read 2026-11-13). Checked here on Claude Code
  2.1.323: the prompt in the terminal is shown and usable while the hook is still running, a
  late answer from the hook resolves it, and answering in the terminal does not wait for the
  hook. The hook does not run in auto mode when no prompt is shown.
- Upstream Blink PR #2287 (open since 2026-08-12) adds DEC mode 2026 to the terminal page and
  stops rows shifting by a pixel as they redraw. Upstream is 151 commits past our fork point
  (2026-04-13), including a rewrite of session suspend and resume and a new report of bottom
  rows hidden after an app switch (#2310, 2026-11-11).
- Other iOS terminals for agents sell approve/deny from the notification (Moshi, Moshline)
  and paste-image-as-path (Secure ShellFish, Termius). Termius moved to a libghostty renderer
  in 8.0.3 (2026-10-15). These come from vendor pages and changelogs, not independent tests.

## We assumed X; the evidence says Y

- We assumed the redraw artifacts in tmux were the app's to fix. The evidence says part of
  them start on the host: Ada ran tmux 3.6a with none of the renderer settings.
- We assumed a hook that waits for the phone would block the prompt in the terminal. It
  does not (checked, above), so answering from the push costs nothing at the keyboard.
- We assumed synchronized output in the app would help mosh tabs. mosh keeps its own screen
  state and does not pass the mode through, so on mosh the gain from #2287 is the pixel-shift
  fix only (inference from how mosh works, not measured).

## Where we depart and why

- The whole upstream merge is not taken: their suspend/resume rewrite overlaps builds 1127 to
  1129, which have not been checked on the phone yet, and #2310 is unresolved. Taken: #2287
  and the mouse-mode reset when an ssh session ends (`700a24c5`, ssh only; the same reset
  for mosh was left out because a resumed mosh session was not shown to turn the mode back on).
- Eternal Terminal and a renderer swap are not pursued (maintainer's position that Tailscale
  covers the first; the second is a rewrite).
