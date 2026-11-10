# Agent loop on the iPhone: plan and record (2026-11-10)

Nate asked what would make the fork better on the iPhone, then said to do all of it. Six
items, built and taken to TestFlight in one pass.

## Prior art

- Established practice: the iOS terminals built for coding agents lead with telling you when
  an agent needs you. Moshi lists a Live Activity with Approve/Deny and a Watch companion;
  TerminaLLM pushes only when an agent is waiting. (App Store listing for Moshi,
  https://apps.apple.com/us/app/6757859949; https://mwm.ai/apps/terminallm/6760659975; both read 2026-11-10.
  The comparison article that ranks them is Moshi's own, and nothing independent tests them.)
- Claude Code's `Notification` hook carries `notification_type`: `permission_prompt`,
  `idle_prompt`, `elicitation_dialog`, `auth_success`. `idle_prompt` is a 60-second timer, not
  a state, and `Stop` fires after every turn. (Community references and issue reports, e.g.
  https://github.com/anthropics/claude-code/issues/32634 and https://github.com/anthropics/claude-code/issues/9575; no official schema came back in the search, so the
  hook also reads the message text when the type is missing.)
- A Live Activity can be started by push from iOS 17.2 with a push-to-start token, needs
  token-based APNs auth and an alert in the payload, and content-state is decoded with a
  plain `JSONDecoder` (so a `Date` is seconds since 2001). (WWDC23 session 10185 notes,
  https://wwdcnotes.com/documentation/wwdc23-10185-update-live-activities-with-push-notifications/; vendor docs from OneSignal, Airship, Customer.io.)
- Pasting an image into Claude Code over SSH doesn't work on its own, because the remote side
  reads its own clipboard. The working pattern is: get the file onto the host, give the agent
  the path. cmux does this on drag. (https://cmux.com/blog/cmux-ssh; https://github.com/AlexZeitler/claude-ssh-image-skill.)
- A WKWebView whose content process dies goes blank; the usual recovery is to reload from
  `webViewWebContentProcessDidTerminate`, and the callback is not guaranteed to fire. (Cordova
  and Firefox iOS trackers; older material, nothing recent from Apple turned up.)
- Where we depart: needing input rings and finishing is quiet, because the evidence says
  finish events are too frequent to ring on. No Approve/Deny on the lock screen and no Watch
  app: a tap takes you to the session instead. Dictation uses no model at all; the tmux title
  says whether an agent is in front.
- What we assumed and what the evidence said: we assumed `idle_prompt` was a usable "needs
  you" signal; reports say it is a timer that also fires after ordinary turns, so it is
  treated as "finished", never as "needs input".

## What was built

| # | Item | Where |
|---|------|-------|
| 1 | Agent push names a tmux session; a tap goes to that tab or opens it | `scripts/fleet/blink_fleet.py` (hook, `blink-attach`, `blink-push`), `install-agent-loop.sh`, `FleetCore/AgentRules.swift`, `Blink/Fleet/AgentSessions.swift`, `AppDelegate.m`, `SceneDelegate.swift` |
| 2 | Live Activity: widget target, started and updated by push | `tools/add_widget_target.py`, `BlinkWidgets/`, `FleetActivityController.swift`, `blink_notify.py --live-activity-event start` |
| 3 | Paste Image: clipboard image to `~/Scratch/blink-paste/` on the host, path typed at the cursor | `FleetCore` `PasteUpload`, `Blink/Fleet/ImagePaste.swift`, quick action and the Paste menu item |
| 4 | Dictation opens the compose area in Prompt mode when an agent is in front | `DictationTarget`, `SpaceController._deliverDictation`, Snips scratch |
| 5 | Sessions: every tmux session across hosts, waiting ones first | `Blink/Fleet/SessionSwitcher.swift`, `blink-sessions`, quick action, `blinkshell://sessions` |
| 6 | Terminal page reloads and repaints after its process is killed | `TermView.m`, `TermDevice.m`, `TermController.deviceDidRecover` |

The thread that ties 1, 3, 4 and 5 together is the window title. `tm` now sets
`set-titles-string` to `#h › #S › #{pane_current_command} › #T`, so every tab says which host
and session it is attached to and what is in front.

## Decisions made without asking (all reversible)

- Finished pushes are passive notifications (Notification Center, no sound, no banner), one
  per session (`apns-collapse-id`), rather than background-only pushes iOS may drop.
- No push when someone typed in that tmux session in the last 20 seconds, and no banner for
  the session on screen.
- Quick actions order on the phone: Sessions, Snips, Paste Image, Copy All, New tab; Settings,
  Close tab and Links moved behind More.
- Other hosts relay pushes through Ada over SSH, so the APNs key stays on one machine.
- The 0.6 s settle after returning to the app and the flick-during-output scroll position were
  left alone: build 1125's fix for the return path is not confirmed on the phone yet, and
  changing the same code now would blur what fixed or broke what.

## Not verified here

Real-device behaviour of everything that needs APNs, SSH keys or the microphone: the tap from
a real push, the Live Activity started by push, the image upload over SSH, and dictation into
the compose area (Snips don't open in the simulator). Checklist: MANUAL-TESTS, Features J to O.
