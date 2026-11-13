#!/bin/bash
# Scripted check for "a mosh tab restored after the app is killed never reconnects"
# (docs/bugs.md, 2026-11-13).
#
# Needs a booted simulator running Blink with ONE tab connected by a real mosh command (ssh
# bootstrap, not `mosh -k`), attached to a throwaway tmux server, e.g.
#     mosh simtest -- tmux -L blinkrepro new -A -s repro
# where `simtest` is a host in the simulator's ~/.ssh/config that reaches this Mac with a key
# held in the simulator's Blink (Settings > Keys). After connecting, send Blink to the
# background and bring it back once, or the simulator forgets the tab on relaunch.
#
#   tools/sim-mosh-restore.sh kill <shot>         kill -9 Blink mid-session, relaunch
#   tools/sim-mosh-restore.sh resumed <shot>      background 335 s (sessions get suspended),
#                                                 return, kill -9, relaunch
#   tools/sim-mosh-restore.sh suspended <shot>    background 335 s, kill -9 while suspended,
#                                                 relaunch
#
# Pass: the screenshot shows the tmux session again (not `blink>`, not "mosh: Last contact"
# or "Nothing received"). For kill and resumed the "tmux clients" count goes up by one
# (a new connection); for suspended it stays the same (the saved connection was picked up).
# "sizes tmux saw" lists what a new connection attached at; it must not include 43 columns.
#
# Every relaunch that reconnects leaves the old mosh-server on the host. Afterwards kill the
# ones this test started BY PID (never by name: the user's live sessions are mosh-servers
# too) and `tmux -L blinkrepro kill-server`.
set -u
S=${SIM:-$(xcrun simctl list devices booted | awk -F '[()]' '/Booted/{print $2; exit}')}
BUNDLE=${BUNDLE:-com.obercode.blink}
SOCK=${SOCK:-blinkrepro}
T=${TMPDIR:-/tmp}/$SOCK.sizes
nap() { perl -e "select(undef,undef,undef,$1)"; }
clients() { tmux -L "$SOCK" list-clients 2>/dev/null | wc -l | tr -d ' '; }
away() { xcrun simctl launch "$S" com.apple.Preferences >/dev/null; nap "${1:-335}"; }
back() { xcrun simctl launch "$S" "$BUNDLE" >/dev/null; nap "${1:-15}"; }
# Log every size the tmux window takes from here on.
watch_sizes() {
  : > "$T"
  tmux -L "$SOCK" set-hook -g client-resized "run-shell 'echo #{client_width}x#{client_height} >> $T'"
  tmux -L "$SOCK" set-hook -g client-attached "run-shell 'echo #{client_width}x#{client_height} >> $T'"
}
echo "tmux clients before: $(clients)"
watch_sizes
case ${1:-} in
kill)      kill -9 "$(pgrep -x Blink)"; nap 2; back ;;
resumed)   away; back 8; kill -9 "$(pgrep -x Blink)"; nap 2; back ;;
suspended) away; kill -9 "$(pgrep -x Blink)"; nap 2; back ;;
*) sed -n 2,25p "$0"; exit 2 ;;
esac
xcrun simctl io "$S" screenshot "$2.png" >/dev/null 2>&1
echo "tmux clients after: $(clients)"
echo "sizes tmux saw: $(sort -u "$T" | tr '\n' ' ')"
tmux -L "$SOCK" set-hook -gu client-resized; tmux -L "$SOCK" set-hook -gu client-attached
