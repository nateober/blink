#!/bin/bash
# Pre-release look at a simulator build on one iPhone and one iPad (docs/bugs.md, 2026-11-18:
# the iPad key row was missing for months because nothing was ever run on an iPad).
#
#   tools/sim-devices.sh <Blink.app> <shot-prefix>
#
# For each device: boots it if needed, installs and launches the app with the on-screen
# keyboard, checks the app is still running after 12 s (a crash at launch fails the run) and
# writes <shot-prefix>-iphone.png and <shot-prefix>-ipad.png. Devices this script booted are
# shut down again.
#
# Pass: exit 0, and in BOTH screenshots the prompt is drawn and the row of keys (esc, ctrl,
# tab, tmux menu, mic, arrows) sits above the keyboard. The key row lives in the keyboard's
# process and is not in the accessibility tree, so that part is read off the screenshot.
#
# Devices: IPHONE and IPAD (names or udids), default "iPhone 17" and "iPad (A16)".
set -u
APP=${1:?path to Blink.app}
OUT=${2:?screenshot prefix}
BUNDLE=${BUNDLE:-com.obercode.blink}
nap() { perl -e "select(undef,undef,undef,$1)"; }
udid() {
  case $1 in
  ????????-????-????-????-????????????) echo "$1" ;;
  *) xcrun simctl list devices available | grep -F "$1 (" | head -1 | awk -F '[()]' '{print $(NF-3)}' ;;
  esac
}
# The on-screen keyboard only shows when the simulator has no hardware keyboard connected.
defaults write com.apple.iphonesimulator ConnectHardwareKeyboard -bool false
rc=0
for pair in "iphone:${IPHONE:-iPhone 17}" "ipad:${IPAD:-iPad (A16)}"; do
  kind=${pair%%:*}
  dev=$(udid "${pair#*:}")
  if [ -z "$dev" ]; then echo "$kind: no such simulator (${pair#*:})"; rc=1; continue; fi
  booted_here=0
  if ! xcrun simctl list devices booted | grep -q "$dev"; then
    xcrun simctl boot "$dev" && booted_here=1
  fi
  xcrun simctl bootstatus "$dev" >/dev/null 2>&1
  xcrun simctl terminate "$dev" "$BUNDLE" >/dev/null 2>&1
  if xcrun simctl install "$dev" "$APP" && pid=$(xcrun simctl launch "$dev" "$BUNDLE" | awk '{print $NF}'); then
    nap 12
    xcrun simctl io "$dev" screenshot "$OUT-$kind.png" >/dev/null 2>&1
    if kill -0 "$pid" 2>/dev/null; then
      echo "$kind: running (pid $pid), screenshot $OUT-$kind.png"
    else
      echo "$kind: Blink exited within 12 s of launch"; rc=1
    fi
  else
    echo "$kind: install or launch failed"; rc=1
  fi
  [ "$booted_here" = 1 ] && xcrun simctl shutdown "$dev"
done
exit $rc
