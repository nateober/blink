# Manual / On-Device Acceptance — fleet-native Blink

The Ralph loop certifies compile + sign + archive + unit tests + reviews only.
Everything below requires Nate on a real device (and, for push, the fleet).
Each item names the TestFlight build it first shipped in.

## Feature A — Mountable iCloud/Files folders
- [ ] `pickFolder` opens the iOS folder picker; choosing an iCloud folder mounts it at `~/mnt/<name>`.
- [ ] Mounted folder survives an app relaunch (bookmark persisted).
- [ ] `showmarks` / `jump <mark>` / `renamemark` / `deletemark` behave. (`cd ~<mark>` shell-tilde deferred; use `jump`.)
- [ ] Blink's own iCloud folder ("Blink For Personal") appears in iCloud Drive on a Mac (NSUbiquitousContainers fix).
- (PATH-inclusion feature deferred — see plan Task 1.7.)

## Feature B — App Intents / Shortcuts
- [ ] "Run on Ada" (or similar) Shortcut/Siri phrase appears after install.
- [ ] The Shortcut runs `claude -p "..."` on a fleet host and returns text output.

## Feature C — Push notifications
- [ ] 🔒 APNs auth key (.p8) generated in the portal and stored via op-add.
- [ ] 🔒 Push capability enabled on App ID `com.obercode.blink` (if not auto-added during signing).
- [ ] Blink registers and publishes its APNs token to `~/.blink-notify/token` on the configured host.
- [ ] `blink_notify.py` sends a push that arrives on the device.
- [ ] Live Activity renders for a long-running `claude -p` session.
- [ ] 🔒 `blink_notify` wired into the `claude -p` wrapper on "needs input".

## Build numbers
- (recorded by the loop at each phase milestone)
