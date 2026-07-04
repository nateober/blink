# Live Activity — one-time Xcode setup

All the code is written. To light up the lock-screen / Dynamic Island indicator, add a
Widget Extension target in Xcode once (the part that's fragile to fabricate by hand), then
add two existing files to it. ~5 minutes.

## 1. Add the widget-extension target
Xcode → **File → New → Target… → Widget Extension**.
- Product name: **BlinkWidgets**
- **Uncheck** "Include Configuration App Intent"; **check** "Include Live Activity".
- Embed in the **Blink** app target when prompted. Set the bundle id to
  `com.obercode.blink.BlinkWidgets` and signing to your team (684GQ6L3D9).
- Deployment target iOS 16.1+ (Live Activities need 16.1; Dynamic Island 16.1 too).

Xcode generates a starter `BlinkWidgets.swift` / `*Bundle.swift` + `*LiveActivity.swift`.
**Delete the generated `*LiveActivity.swift` and the generated bundle's body** — we replace them.

## 2. Add the prepared files to the BlinkWidgets target
In the Project navigator, add these (File → Add Files, or drag), with **target membership =
BlinkWidgets**:
- `BlinkWidgets/BlinkWidgetsBundle.swift`  (the `@main WidgetBundle` — replaces the generated one)
- `BlinkWidgets/FleetActivityWidget.swift` (the lock-screen + Dynamic Island UI)
- `Blink/Fleet/FleetActivityAttributes.swift` — **add to the BlinkWidgets target too** (it's
  already in the app target; just tick BlinkWidgets in the File Inspector → Target Membership).
  Do NOT duplicate the file; share the one copy.

If Xcode left its own `@main` struct, delete it so `BlinkWidgetsBundle` is the only `@main`.

## 3. Build + ship
`scripts/release.sh` already archives the whole app; the embedded extension goes along. The
release script auto-bumps the build number for both. Confirm the symbol guard still holds.

## What already works once the target exists
- **Terminal:** `liveactivity start ada claude running "claude -p summarizing"` →
  `liveactivity update "needs input" "waiting on you"` → `liveactivity end`.
- **Remote (APNs):** the app captures each activity's push token and publishes it to
  `~/.blink-notify/activity-token` on `ada`/`push-notify`. Update it from the fleet:
  `blink_notify.py --token $(cat ~/.blink-notify/activity-token) --live-activity-event update \
     --la-status "needs input" --la-detail "on ada" --key-id … --team-id … --p8 …`
  (`--live-activity-event end` to dismiss.)

## Notes / likely device-tuning
- `content-state` JSON keys must match `FleetActivityAttributes.ContentState`
  (`status`, `detail`, `updatedAt`). `updatedAt` is sent as epoch seconds; if ActivityKit's
  decoder rejects it on device, switch the Swift field to a `String` ISO timestamp (one-line).
- Push-to-START (begin an activity remotely with no app interaction) needs iOS 17.2+ and the
  push-to-start token; not wired — we start locally and update/end via push, which covers the
  `claude -p` flow (you kick it off, the fleet updates the indicator).
- Live Activities can't be exercised on the simulator reliably; this is device acceptance.
