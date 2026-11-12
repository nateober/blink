#!/bin/bash
# Scripted check for the "blank or unresponsive on return" bugs (docs/bugs.md, 2026-11-12).
# Kills the terminal page's process in a booted simulator running Blink, the way iOS does
# to a backgrounded app, and takes a screenshot to compare.
#
#   tools/sim-page-kill.sh fg <shot>          kill it with Blink in front
#   tools/sim-page-kill.sh bg <shot> [secs]   send Blink to the background, wait, kill, return
#   tools/sim-page-kill.sh type <text> <shot> type a line and press Return (hardware keyboard on)
#
# Pass after each: the prompt or tmux screen is back, typing reaches the session, the Blink
# pid is unchanged, and for `bg` no page process exists while Blink is in the background.
# Use secs >= 330 to cover sessions the app has suspended.
set -u
S=${SIM:-$(xcrun simctl list devices booted | awk -F '[()]' '/Booted/{print $2; exit}')}
BUNDLE=${BUNDLE:-com.obercode.blink}
pages() { ps -axo pid,command | grep "WebKit.WebContent" | grep CoreSimulator | grep -v grep | awk '{print $1}'; }
nap() { perl -e "select(undef,undef,undef,$1)"; }
shot() { xcrun simctl io "$S" screenshot "$1.png" >/dev/null 2>&1; }
case ${1:-} in
fg)
  for p in $(pages); do kill -9 "$p"; done
  nap 4; echo "page process now: $(pages | tr '\n' ' ')"; shot "$2" ;;
bg)
  xcrun simctl launch "$S" com.apple.Preferences >/dev/null
  end=$(( $(date +%s) + ${3:-3} )); until [ "$(date +%s)" -ge "$end" ]; do nap 1; done
  for p in $(pages); do kill -9 "$p"; done
  nap 8; echo "page processes while in background: [$(pages | tr '\n' ' ')] (want none)"
  xcrun simctl launch "$S" "$BUNDLE" >/dev/null
  nap 5; echo "page process after return: $(pages | tr '\n' ' ')"; shot "$2" ;;
type)
  timeout 20 idb ui text --udid "$S" "$2"
  osascript -e 'tell application "Simulator" to activate' -e 'tell application "System Events" to key code 36'
  nap 2; shot "$3" ;;
*) sed -n 2,13p "$0"; exit 2 ;;
esac
echo "Blink pid: $(pgrep -x Blink)"
