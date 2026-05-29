# Fleet-side push: blink-notify

`blink_notify.py` sends an agent-attention push to the Blink iOS app via APNs. Run it
on a fleet host (Ada/Vera/Max) from your `claude -p` wrapper when the agent needs input.

## One-time setup (🔒 human-gated — needs Nate)

1. **Generate an APNs auth key (.p8)** at App Store Connect → Users and Access →
   Integrations → Keys (or developer.apple.com → Account → Keys): "+", enable
   **Apple Push Notifications service (APNs)**, download the `.p8` (one-time).
   Note the **Key ID** (10 chars) and your **Issuer/Team ID**.
2. Store it: `op-add` the .p8 into 1Password, and place a copy at
   `~/.appstoreconnect/apns/AuthKey_<KEYID>.p8` (chmod 600).
3. **Enable the Push Notifications capability** on App ID `com.obercode.blink`
   (Certificates, Identifiers & Profiles → Identifiers). The app archive re-adds the
   `aps-environment` entitlement automatically once this is on.

## Device token

The Blink app (PushRegistrar) registers for remote notifications and writes its APNs
token to `~/.blink-notify/token` on the configured host. `blink_notify.py` reads that.

## Send

```bash
TOKEN=$(cat ~/.blink-notify/token)
scripts/fleet/blink_notify.py \
  --token "$TOKEN" --title "Claude needs you" --body "approve edit?" \
  --kind needs_input --host ada \
  --key-id <KEYID> --team-id 9ff16463-2c73-4e60-8bf9-273267673229 \
  --topic com.obercode.blink \
  --p8 ~/.appstoreconnect/apns/AuthKey_<KEYID>.p8
```

- `--sandbox` targets the APNs sandbox host (use for development/`aps-environment=development` builds; TestFlight/App Store builds use production — the default).
- `--dry-run` prints the payload without sending (used by tests).

## Wire into `claude -p`

In your wrapper, when Claude pauses for input, call `blink_notify.py` with
`--kind needs_input`; on completion call it with `--kind done`. Keep `--kind progress`
for periodic Live Activity updates.

## Simulator verification (no device/APNs needed)

Push *handling* is verified on the iOS Simulator with the same payload shape:

```bash
echo '{"aps":{"alert":{"title":"Claude needs you","body":"approve edit?"},"sound":"default"},"blink":{"kind":"needs_input","host":"ada"}}' > /tmp/p.json
xcrun simctl push booted com.obercode.blink /tmp/p.json
```
