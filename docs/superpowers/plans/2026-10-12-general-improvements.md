# Blink general improvements: plan (2026-10-12)

Ten items from upstream's issue list that match how the fork is used. Nate's instruction: do all
of them and take them through to TestFlight (internal) without stopping for approval. Nothing is
posted upstream.

## How each item runs

1. Branch off `raw` (`imp/<slug>`), implement, unit-test pure logic (FleetCore `swift test`, or
   Node for terminal JavaScript).
2. Build for the iPhone 17 Pro simulator (signing on, `ENABLE_DEBUG_DYLIB=NO`) and drive the
   feature there; screenshot what is visual.
3. Merge into `raw`. Items that only a device can confirm go on the checklist in `MANUAL-TESTS.md`.
4. Release in batches with `scripts/release.sh`; record build numbers in `handoff.md`.

## Order (most certain first)

| # | Issue | Item | Approach | Certainty |
|---|---|---|---|---|
| 1 | #2231 | Prompt-mode Snips | `.prompt` marker in the Snip's file name; editor, new-Snip screen and send path honour it | high |
| 2 | #1118 | Easier link opening | JavaScript finds links on screen (plain and OSC 8); "open latest link" SmartKey and key-bindable command; Cmd-click on a link opens it | medium-high |
| 3 | #2278 | Copy truncates long selection | Select All copies the whole buffer, not only rows in the page | medium (cause not reproduced yet) |
| 4 | #2232 | ⏺ misaligned in Claude Code | No bundled font has U+23FA so it falls back to a wide emoji glyph; give such symbols a fixed one-cell box or a fallback font | high on cause |
| 5 | #752 | Follow system light/dark | Optional dark theme on a style; applied live when the appearance changes | medium-high |
| 6 | #2290 | Links that open a session | `blinkshell://run` and `blinkshell://host/<alias>` with optional `id` to refocus; off by default, secret key or a confirm prompt | high on design |
| 7 | #2253 | Shortcuts actions | Generic names for the two fleet actions (old ones kept), host picker, new "Open Terminal Session" action sharing item 6's code | medium |
| 8 | #1037 | Sessions bar | Optional tab strip at the top with live titles; tap to switch | medium (layout modes) |
| 9 | #2294 | mosh loses lines after app switch | Don't report keyboard-driven size changes to the session while the scene is inactive | low-medium (hypothesis) |
| 10 | #2267 | iPad scroll hang | Not reproduced by anyone. Harden the scroll path (divide-by-zero guard, no echo of programmatic scrolls, coalesce calls) and say plainly it is unproven | low |

## Batches

- Build A: items 1 to 4. Build B: items 5 to 7. Build C: items 8 to 10.

## Progress

- 2026-10-12: all ten coded on `imp/general`, one commit per item or pair; FleetCore 79 tests,
  link finder 10 checks. Simulator run 1 (items 1 to 4): Snips, symbol alignment, menu Select All
  and whole-buffer copy passed; it caught the link finder reading rows wrongly and Cmd-A typing
  an "a", both fixed. Snips can't open in the simulator at all (a path problem that predates this
  work), so they were checked on a throwaway simulator.
- Batches collapsed into one build since everything landed the same day.
