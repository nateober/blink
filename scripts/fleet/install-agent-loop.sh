#!/usr/bin/env bash
# Install the host side of Blink's agent loop on this Mac: the Claude Code hook that
# records what each agent is doing and pushes the phone, `blink-attach` (what a tap on a
# push runs) and `blink-sessions` (what the session switcher reads).
#
#   install-agent-loop.sh --key-id KID --team-id TEAM --p8 PATH   the host holding the APNs key
#   install-agent-loop.sh --relay SSH_HOST                        any other host
#   install-agent-loop.sh                                         refresh the scripts only
#
# Safe to run again. ~/.claude/settings.json is backed up before the hooks are merged in.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
home="$HOME/.blink-notify"
bin="$HOME/.local/bin"
key_id="" team_id="" p8="" relay=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --key-id) key_id="$2"; shift 2 ;;
    --team-id) team_id="$2"; shift 2 ;;
    --p8) p8="$2"; shift 2 ;;
    --relay) relay="$2"; shift 2 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

mkdir -p "$home/bin" "$home/state" "$bin"
chmod 700 "$home"
install -m 755 "$here/blink_fleet.py" "$home/bin/blink_fleet.py"
install -m 755 "$here/blink_notify.py" "$home/bin/blink_notify.py"
for name in blink-agent-hook blink-attach blink-sessions blink-push blink-activity; do
  ln -sf "$home/bin/blink_fleet.py" "$bin/$name"
done

# `mosh <host> -- blink-attach ...` and `ssh <host> blink-sessions` run without an interactive
# shell, so ~/.local/bin has to be on the PATH zsh gives every shell.
if ! zsh -c 'command -v blink-attach' >/dev/null 2>&1; then
  {
    echo ''
    echo '# >>> blink agent loop: ~/.local/bin for non-interactive shells >>>'
    echo 'export PATH="$HOME/.local/bin:$PATH"'
    echo '# <<< blink agent loop <<<'
  } >> "$HOME/.zshenv"
  echo "PATH: added ~/.local/bin to ~/.zshenv"
fi

# A mosh-server whose client never comes back (the app was deleted, or the tab reconnected
# with a new server) otherwise runs until the host restarts. Three days is longer than a
# phone stays away with a tab it still means to use, and a tab that comes back later
# reconnects into the same tmux session by itself (docs/bugs.md, 2026-11-13).
if [ -z "$(zsh -c 'echo ${MOSH_SERVER_NETWORK_TMOUT-}' 2>/dev/null)" ]; then
  {
    echo ''
    echo '# >>> mosh-server idle timeout >>>'
    echo '# mosh-server exits after 3 days without hearing from its client.'
    echo 'export MOSH_SERVER_NETWORK_TMOUT=259200'
    echo '# <<< mosh-server idle timeout <<<'
  } >> "$HOME/.zshenv"
  echo "mosh: servers now exit after 3 days without a client (~/.zshenv)"
fi

python3 - "$home/config.json" "$key_id" "$team_id" "$p8" "$relay" <<'PY'
import json, os, sys
path, key_id, team_id, p8, relay = sys.argv[1:6]
try:
    cfg = json.load(open(path))
except (OSError, ValueError):
    cfg = {}
if key_id and team_id and p8:
    cfg = {"key_id": key_id, "team_id": team_id, "p8": p8, "topic": cfg.get("topic", "com.obercode.blink")}
elif relay:
    cfg = {"relay": relay}
with open(path, "w") as f:
    json.dump(cfg, f, indent=2)
    f.write("\n")
os.chmod(path, 0o600)
print("config:", "key" if cfg.get("p8") else f"relay via {cfg['relay']}" if cfg.get("relay") else "EMPTY (no pushes until --relay or a key is given)")
PY

python3 - "$HOME/.claude/settings.json" "$bin/blink-agent-hook" <<'PY'
import json, os, shutil, sys, time
path, hook = sys.argv[1:3]
try:
    settings = json.load(open(path))
except OSError:
    settings = {}
hooks = settings.setdefault("hooks", {})
changed = False
for event in ("Notification", "Stop", "UserPromptSubmit", "SessionEnd"):
    groups = hooks.setdefault(event, [])
    if any("blink-agent-hook" in h.get("command", "") for g in groups for h in g.get("hooks", [])):
        continue
    groups.append({"hooks": [{"type": "command", "command": hook, "timeout": 10}]})
    changed = True
if changed:
    if os.path.exists(path):
        shutil.copy2(path, f"{path}.bak-{time.strftime('%Y%m%d-%H%M%S')}")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(settings, f, indent=2)
        f.write("\n")
    os.replace(tmp, path)
print("claude hooks:", "added" if changed else "already present")
PY

# Window titles carry host, session and the program in front, so Blink can tell which tab
# is attached to what. `tm` applies the same on every attach; this covers the live server.
if tmux list-sessions >/dev/null 2>&1; then
  tmux set -g set-titles on
  tmux set -g set-titles-string '#h › #S › #{pane_current_command} › #T'
  echo "tmux titles: on"
fi
echo "installed in $home"
