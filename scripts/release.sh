#!/usr/bin/env bash
#
# release.sh — archive + upload the personal-fork Blink build to TestFlight.
#
# Encodes the hard-won build incantation for Xcode 26 / personal signing:
#   - STRIP_STYLE=non-global + DEAD_CODE_STRIPPING=NO  → keep the dlsym-dispatched
#     command symbols (config_main, ssh_main, …); the default `strip -all` deletes
#     them and breaks every built-in command at runtime.
#   - -Wl,-export_dynamic (via BLINK_OTHER_LDFLAGS in developer_setup.xcconfig)
#     publishes those globals in the export trie so dlsym(RTLD_MAIN_ONLY) resolves.
#   - /usr/bin ahead of PATH so Apple's openrsync is used; Homebrew rsync 3.4.x
#     breaks Xcode's IPA packaging ("Copy failed").
#   - ASC API key auth so signing + upload run unattended.
#
# Build numbers must be unique & increasing per upload. We derive the next one
# from the current ASC max, so re-runs never collide.
#
# Usage: scripts/release.sh [build_number]
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

KEY_ID="S3MYBGRBL4"
ISSUER_ID="9ff16463-2c73-4e60-8bf9-273267673229"
KEY_PATH="$HOME/.appstoreconnect/private_keys/AuthKey_${KEY_ID}.p8"
TEAM_ID="684GQ6L3D9"
APP_ID="6771422199"
GROUP_ID="cb615610-fe31-4df9-83d7-46588611e0d2"   # "Nate (Internal)"

# Next build number: one past the current ASC max (or arg override).
BUILD_NUM="${1:-}"
if [[ -z "$BUILD_NUM" ]]; then
  BUILD_NUM="$(uv run --quiet --with PyJWT --with cryptography --with requests --python 3.12 python - <<PY
import sys; sys.path.insert(0, "$REPO/scripts")
from asc_api import call
out = call("GET", "/v1/apps/$APP_ID/builds?limit=200&fields[builds]=version")
nums = [int(b["attributes"]["version"]) for b in out.get("data", []) if b["attributes"]["version"].isdigit()]
print((max(nums) + 1) if nums else 1100)
PY
)"
fi
echo ">> Building build number $BUILD_NUM"

rm -rf build/Blink.xcarchive build/export build/archive.log build/export.log

echo ">> Archiving…"
xcodebuild archive \
  -project Blink.xcodeproj \
  -scheme Blink \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath build/Blink.xcarchive \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$KEY_PATH" \
  -authenticationKeyID "$KEY_ID" \
  -authenticationKeyIssuerID "$ISSUER_ID" \
  CODE_SIGN_STYLE=Automatic \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CURRENT_PROJECT_VERSION="$BUILD_NUM" \
  DEAD_CODE_STRIPPING=NO \
  STRIP_STYLE=non-global \
  BLINK_OTHER_LDFLAGS="-Wl,-export_dynamic" \
  > build/archive.log 2>&1
echo ">> Archive done."

# Sanity: confirm the command symbols survived into the export trie.
APP_BIN=build/Blink.xcarchive/Products/Applications/Blink.app/Blink
N=$(xcrun dyld_info -exports "$APP_BIN" 2>/dev/null | grep -cE "_main$" || true)
echo ">> Exported *_main symbols: $N"
if ! xcrun dyld_info -exports "$APP_BIN" 2>/dev/null | grep -q "_config_main"; then
  echo "!! config_main missing from export trie — aborting (commands would break)." >&2
  exit 1
fi

echo ">> Exporting + uploading to TestFlight…"
PATH=/usr/bin:/bin:/usr/sbin:/sbin:$PATH xcodebuild -exportArchive \
  -archivePath build/Blink.xcarchive \
  -exportPath build/export \
  -exportOptionsPlist ExportOptions.plist \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$KEY_PATH" \
  -authenticationKeyID "$KEY_ID" \
  -authenticationKeyIssuerID "$ISSUER_ID" \
  > build/export.log 2>&1
grep -qE "EXPORT SUCCEEDED" build/export.log && echo ">> Upload succeeded (build $BUILD_NUM)."

echo ">> Waiting for ASC processing, then attaching to internal group…"
uv run --quiet --with PyJWT --with cryptography --with requests --python 3.12 python - "$BUILD_NUM" <<PY
import sys, time
sys.path.insert(0, "$REPO/scripts")
from asc_api import call
want = sys.argv[1]; deadline = time.time() + 2400
while time.time() < deadline:
    out = call("GET", "/v1/apps/$APP_ID/builds?limit=20&fields[builds]=version,processingState")
    m = next((b for b in out.get("data", []) if b["attributes"]["version"] == want), None)
    if m and m["attributes"]["processingState"] == "VALID":
        call("POST", "/v1/betaGroups/$GROUP_ID/relationships/builds", json={"data":[{"type":"builds","id":m["id"]}]})
        print(f">> Attached build {want} to internal group. Live in TestFlight.")
        break
    print(f"   build {want}: {(m or {}).get('attributes',{}).get('processingState','not visible')}…", flush=True)
    time.sleep(120)
else:
    print(">> Timed out waiting for processing; attach manually later.", file=sys.stderr)
PY
