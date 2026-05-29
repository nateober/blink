# Fleet command reachability — off-LAN design

**Date:** 2026-05-29 · **Branch:** `feat/fleet-native` · **Author:** Ada

## Problem

The App Intent / Shortcut ("Run `<cmd>` on `<host>`") and the push-token publish run over SSH via
`HeadlessSSHRunner`, which dials the host's configured address directly. Nate's fleet hosts are LAN
addresses (`ada = 192.168.86.21`, `jarvis = 192.168.86.20`, …). So the Shortcut works on home WiFi
or an active WireGuard tunnel and **fails on cellular** — which, for a travel-heavy user, is exactly
when the feature is wanted. This is the most likely cause of the original "unspecified error"
(build ≤1105 masked it; 1106 now reports "SSH failed: …" / "timed out", making the failure legible
but not fixed).

## Recon (what already exists)

- `SSH/SSHClientConfig.swift` already carries `proxyJump: String?` and `proxyCommand: String?`.
- `SSH/SSHClient.swift:163` already applies `proxyJump` natively via libssh `SSH_OPTIONS_PROXYJUMP`
  on `dial` — no extra tunnel plumbing needed for the headless path.
- `BKHosts` already persists per-host `proxyJump` and `proxyCmd` (`BlinkConfig/BKHosts.h:72-73`),
  editable in the existing host UI and synced via iCloud.
- **Gap:** `RunFleetCommandIntent` (`FleetIntents.swift`) and `PushRegistrar` resolve only
  user/host/key/password and call `HeadlessSSHRunner.run(...)` with **no proxy**. `HeadlessSSHRunner`
  doesn't accept a proxy argument at all. So even a host configured with `ProxyJump` is dialed
  directly by the Shortcut. The wiring is 90% present and simply not connected.

This splits the fix cleanly into an **app layer** (in our control, small, testable) and a
**network layer** (infra, Nate's call).

## App layer — honor the host's proxy + fail legibly

> **Superseded (see "Network layer" below):** the recon found the fleet — including the iPhone — is
> already on a Tailscale/Headscale mesh, so this whole app-layer plumbing is YAGNI and **not being
> built**. Kept here only to record the option that was evaluated. The 1106 legible-error change
> already shipped and stands.

1. **Plumb proxy through `HeadlessSSHRunner.run`.** Add `proxyJump: String? = nil` (and
   `proxyCommand: String? = nil` for completeness) parameters, pass them into `SSHClientConfig`.
   ProxyJump is the supported headless mechanism (libssh native); ProxyCommand on iOS uses Blink's
   internal stdio-tunnel reimplementation and is **out of scope** for the headless path — if a host
   has only `proxyCmd` set, we log that it's unsupported headless and dial direct.
2. **Read the host's proxy in the callers.** `RunFleetCommandIntent` and `PushRegistrar` pass
   `h.proxyJump` into the runner. Zero new UI — Nate configures `ProxyJump` on a host the normal way.
3. **Reachability is already handled** by 1106's connect timeout + overall deadline + legible error.
   Optionally tighten the message: if the dial fails fast on a private (RFC-1918) host address and no
   proxy is set, append a hint: `"(host is a LAN address and not reachable — on the home network or
   WireGuard?)"`. Pure string logic → unit-testable in FleetCore (`Reachability.isPrivateHost`).

That's the entirety of what code can do. It makes "configure `ada` with `ProxyJump <public-bastion>`
and the Shortcut works from anywhere" true — *provided the bastion can reach the LAN host*, which is
the network layer.

## Network layer — already solved (Tailscale/Headscale)

**Recon update (2026-05-29):** the entire fleet is already on a self-hosted Headscale tailnet
(MagicDNS suffix `ober`, Headscale's default `100.64.0.0/10` CGNAT range), **and the iPhone is a
member and online.** `tailscale status` on Ada:

| Host | Tailscale IP | MagicDNS |
|---|---|---|
| jarvis | `100.64.0.1` | `jarvis.ober` |
| lightsail | `100.64.0.2` | `lightsail.ober` |
| **ada** | `100.64.0.3` | `ada.ober` |
| homeassistant | `100.64.0.4` | `homeassistant.ober` |
| pihole | `100.64.0.5` | `pihole.ober` |
| **iphone** | `100.64.0.6` | `iphone.ober` (online) |
| max | `100.64.0.7` / `100.64.0.8` | `max.ober` |

This collapses the decision. The phone can already reach every fleet host from anywhere (cellular
included) over Tailscale's NAT-traversal + DERP relays — no WireGuard peering, no Lightsail bastion,
**and no app code change.** The earlier WireGuard / ProxyJump options are moot. The "app layer"
section above (ProxyJump plumbing, reachability hint) is therefore **YAGNI and dropped** — Tailscale
removes the need for it. (Keep the 1106 legible-error change; that stands on its own.)

**The entire fix is one configuration step:** set each Blink host's `hostName` to its Tailscale
address. Prefer the **literal `100.64.0.x` IP** over the MagicDNS name — the IP always routes through
the Tailscale `utun` regardless of whether iOS is using Tailscale's DNS resolver, whereas `ada.ober`
resolution depends on "Use Tailscale DNS / MagicDNS" being on. (If MagicDNS is on, names work too and
read better.)

## Action (Nate, ~5 min, no build)

In Blink → Settings → Hosts, set `HostName` for the fleet aliases to their Tailscale IPs:

- `ada` → `100.64.0.3`
- `jarvis` → `100.64.0.1`
- `max` → `100.64.0.7` (or `100.64.0.8` if that is the active mini)
- `lightsail` → `100.64.0.2`

Leave user/key/password as-is. Then the Shortcut and `ssh <alias>` work on cellular. Verify by
toggling the phone to cellular (WiFi off) and running the "Run Fleet Command" Shortcut against `ada`
with e.g. `uptime` — 1106 will report a clear error if anything is still wrong.

## Out of scope
WireGuard peering and the Lightsail-bastion path (obsoleted by Tailscale); ProxyJump plumbing in the
headless runner (YAGNI given Tailscale); any new host-config UI.
