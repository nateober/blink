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

## Network layer — the actual path (Nate's decision)

Three ways to make a LAN host reachable from the phone off-LAN. App-layer change above is a no-op
without one of these.

| Option | How | Pros | Cons |
|---|---|---|---|
| **A. Always-on WireGuard on iPhone** (recommended) | Phone joins the WG net (10.6.0.x); Blink hosts use WG IPs (`ada = 10.6.0.6`). No proxy needed. | Cleanest; all hosts reachable + encrypted; reuses existing WG; no app change strictly required (just use WG IPs as hostNames). | WG client must be up (battery, captive portals); the fleet WG must actually peer the phone and route to each host — the `[[machine-identity]]` memory notes the tunnel is "up but unpeered." Infra gap to close + verify. |
| **B. ProxyJump through public Lightsail** | Set `ProxyJump lightsail` on each fleet host; Lightsail is public (`ssh lightsail` works). Uses the app-layer change above. | No phone-side VPN; works on locked-down cellular; per-host opt-in. | Lightsail must itself reach the home LAN host → Lightsail must join the WG mesh or hold a reverse tunnel from home. So B still needs a mesh; it just moves the always-on endpoint from the phone to Lightsail. Extra hop/latency. |
| **C. Tailscale (or similar) mesh** | Install Tailscale on the fleet + phone; use MagicDNS names. | NAT-traversal "just works"; no manual peering; reachable anywhere. | New dependency/daemon across the fleet; duplicates the existing WG investment. |

**Recommendation:** **A**, with **B as the resilient add-on**. Put the iPhone on the WG mesh and
point Blink hosts at WG IPs — that alone fixes the Shortcut with no app change. Then layer the
app-layer proxy plumbing so that hosts *also* carrying `ProxyJump lightsail` keep working if WG is
down or blocked (Lightsail joins the mesh as the bastion). A is the primary path; B is the fallback;
the app-layer change is what makes B possible and is worth doing regardless.

## Phased plan (app layer is implementable + testable here; network is infra)

- **Phase 1 (code, here):** plumb `proxyJump` through `HeadlessSSHRunner` + both callers;
  add `Reachability.isPrivateHost` + hint string (TDD in FleetCore); build + sim-validate; ship in
  the next TestFlight build.
- **Phase 2 (infra, Nate):** verify/repair the WG mesh — peer the iPhone, confirm it routes to
  10.6.0.x LAN hosts (`sudo wg show` on Ada; the memory flags it unpeered). Set Blink host
  `hostName` to WG IPs (or add WG-IP host variants). This is the change that actually fixes cellular.
- **Phase 3 (infra, optional):** add Lightsail to the WG mesh as a public bastion; set
  `ProxyJump lightsail` on fleet hosts as the WG-down fallback. Validated by Phase 1's plumbing.

## Out of scope
ProxyCommand over the headless path (Blink's iOS stdio-tunnel reimplementation — interactive only);
any new host-config UI (reuse the existing ProxyJump field); changing the interactive `ssh` path
(already supports proxy).
