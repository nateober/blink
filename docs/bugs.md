# Bug ledger

One line per bug Nate reports: date, symptom in his words, root cause, the check that guards it.
If a symptom here comes back, mark it REGRESSED and do a root-cause pass before patching again.

| Date | Symptom | Root cause | Guard |
|------|---------|------------|-------|
| 2026-11-10 | "on restore there seems to be some frozen parts of the terminal" | Build 1121 (`eed7218c`) held size reports to the session while the scene was inactive, but the page still reflowed its grid for the keyboard hiding and returning. The session (mosh, tmux) kept drawing for the old layout, so output landed on the wrong rows, and since the size it finally heard was the one it already had, nothing repainted. Traced in code, not reproduced on a device. Fix: the page holds its grid while the scene is inactive (`term_holdResize`) and takes the settled size once, after activation. | `node tools/termjs-tests/resizehold.test.js`; `ResizeRules.settles` in FleetCore tests; device check MANUAL-TESTS Feature I |
