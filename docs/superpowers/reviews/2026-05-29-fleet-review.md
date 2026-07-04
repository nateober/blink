# Fleet-native review — 2026-05-29 (build 1110)

Three parallel review passes (correctness, concurrency/resources, security) over the fleet surface:
`FleetCore/*`, `Blink/Fleet/*`, `Blink/Commands/{mounts,fleetexec,notiflog}.swift`, `AppDelegate.m`,
`scripts/fleet/blink_notify.py`. Dispositions below; all "fixed" items are in build 1110.

## Fixed
- **[CORRECTNESS HIGH] `ExitTrailer.parse`** split on the FIRST marker occurrence (dropped output
  when a marker-looking line repeats) and rejected a CRLF `\r` on the marker line (→ nil code →
  silent false success in the App Intent). Rewrote to scan from the end for the LAST marker via
  `components(separatedBy:.newlines)` + whitespace trim. +4 regression tests.
- **[SECURITY HIGH] Host-key callback** auto-accepted CHANGED keys, not just first-use unknowns,
  and silently overwrote the pin. Now case-aware: pin `.unknown`/`.notFound` on first use only;
  ALWAYS reject `.changed`. Pin-on-first-use-then-strict, no UI needed.
- **[SECURITY MED] APNs device token** was NSLog'd in full → now Debug-only, prefix-only. Added a
  `hex.allSatisfy(\.isHexDigit)` guard before interpolating it into the remote shell command.
- **[CORRECTNESS MED] `fleetexec`** re-joined tokenized argv with plain spaces, corrupting
  `claude -p "two words"`. Now POSIX-quotes each token. Also restored the friendly "No Blink host"
  pre-check that the alias rewrite had dropped (was falling through to a raw socket error).
- **[CONCURRENCY MED] `ScopeHolder`** double-started the security scope on same-URL re-entry
  (refcount climb); now always balances the prior scope first.
- **[LOW] `NotificationLog.recent()`** sorted by insertion order → now by `receivedAt`. Inbox dedupe
  key now includes `host`. Documented the single-thread invariant in `HeadlessSSHRunner` + added a
  `CFRunLoopWakeUp` after `Stop` as belt-and-suspenders.

## Reviewed clean / accepted as-is
- `runOnce` continuation resumes exactly once on all four paths (success / remote failure / deadline
  / synchronous-dial-failure) — confirmed no double-resume, no permanent hang.
- `PushModels`, `FolderPicker` semaphore handling, `fleetexec` semaphore `defer`-signal,
  `NotificationLog` locking, `NotificationInbox` crash-safety against malformed payloads,
  `blink_notify.py` TLS/JWT/no-injection — all clean.
- `SSHClientConfig` non-Sendable capture warning — benign (thread-confined, never mutated).

## Known limitations (documented, not bugs)
- `ExitTrailer.wrap` assumes a single foreground command (no trailing here-doc / `&`).
- Background notification capture wakes a suspended/backgrounded app, NOT a force-quit one (iOS
  doesn't deliver background pushes to terminated apps); those are still captured on tap.
- Passphrase-protected keys can't be unlocked headlessly — the auth error now says so.
