#!/usr/bin/env python3
"""blink-fleet: the host side of Blink's agent loop. Standard library only, so a hook
costs a few milliseconds.

Installed under several names (symlinks made by install-agent-loop.sh):

  blink-agent-hook   Claude Code hook (stdin: the hook's JSON). Records what the agent in
                     this tmux session is doing and pushes the phone when it needs input.
  blink-attach HEX   Attach to (or create) the tmux session whose name is HEX-encoded.
                     What a tap on a push runs: `mosh <host> -- blink-attach <hex>`.
  blink-sessions     One line per tmux session, tab-separated:
                     name, windows, attached, activity epoch, state, host, pane title.
  blink-push ...     Send one push from this host's key (other hosts relay through it).
  blink-decide ID allow|deny
                     Answer the permission request a push carried. What the Approve and
                     Deny buttons on that push run.

State lives in ~/.blink-notify/:
  config.json   {"key_id","team_id","p8","topic"} on the host that holds the APNs key,
                or {"relay": "<ssh host>"} on the others
  token         the phone's APNs device token (Blink publishes it)
  state/<hex>   "<state>\t<epoch>\t<message>" for each tmux session with an agent
  requests/<hex>   the permission request a session is waiting on: {"id","summary","at"}
  decisions/<id>   "allow" or "deny", written by blink-decide and read once by the hook
"""
import fcntl
import json
import os
import re
import secrets
import subprocess
import sys
import time
from pathlib import Path

HOME = Path(os.environ.get("BLINK_NOTIFY_HOME", str(Path.home() / ".blink-notify")))
STATE = HOME / "state"
REQUESTS = HOME / "requests"
DECISIONS = HOME / "decisions"
# How long the hook holds a permission request open for an answer from the phone. The
# prompt in the terminal works as usual the whole time; whichever answers first wins.
DECISION_WAIT_SECS = 540
DECISION_POLL_SECS = 0.4
LOG = HOME / "hook.log"
# Someone typing in the session this recently is looking at it; no push needed.
WATCHING_SECS = 20
# A state file older than this is a session whose agent went away without saying so.
STALE_SECS = 3 * 86400
# After a remote start, how long to wait for the phone to publish the new activity's token.
START_GRACE_SECS = 120
# Every start by push wakes the app on the phone, and an agent's turn is often a few seconds.
# So an activity starts only once agents have been running this long (one that needs input
# starts at once), and ends only after this long with nothing running.
START_DELAY_SECS = 45
END_DELAY_SECS = 120

NEEDS_INPUT, DONE, RUNNING = "needs_input", "done", "running"


# ---- pure decisions (unit-tested) --------------------------------------------------

def state_for(event):
    """The session state a hook event means, None for events that change nothing,
    "" for the session ending."""
    name = event.get("hook_event_name", "")
    if name == "UserPromptSubmit":
        return RUNNING
    if name == "Stop":
        return DONE
    if name == "SessionEnd":
        return ""
    if name == "Notification":
        kind = event.get("notification_type", "")
        message = (event.get("message") or "").lower()
        if kind in ("permission_prompt", "elicitation_dialog"):
            return NEEDS_INPUT
        if kind == "idle_prompt":
            return DONE
        if not kind:
            if "permission" in message or "approval" in message:
                return NEEDS_INPUT
            if "waiting for your input" in message:
                return DONE
    return None


def asks_permission(event):
    """True for the notification that reports a permission prompt. Only that one may carry a
    request to answer: a question the agent asks is also "needs input", and an earlier
    request answered in the terminal can still be on file then."""
    if event.get("hook_event_name") != "Notification":
        return False
    kind = event.get("notification_type", "")
    if kind:
        return kind == "permission_prompt"
    return "permission" in (event.get("message") or "").lower()


def push_for(new, previous, watching):
    """What to send the phone for a state change: "alert", "quiet" or None.

    Needing input rings. Finishing lands quietly in Notification Center and the inbox.
    Nothing is sent to someone who is typing in the session, or twice for the same state.
    """
    if watching or new == previous:
        return None
    if new == NEEDS_INPUT:
        return "alert"
    if new == DONE and previous in (RUNNING, NEEDS_INPUT):
        return "quiet"
    return None


def hexname(session):
    return session.encode().hex()


def unhex(text):
    try:
        name = bytes.fromhex(text).decode()
    except ValueError:
        return None
    if not name or len(name) > 64 or any(ord(c) < 32 or ord(c) == 127 for c in name):
        return None
    return name


def is_agent_title(title):
    if not title:
        return False
    first = ord(title[0])
    return first == 0x2733 or 0x2800 <= first <= 0x28FF


def task_from_title(title):
    if not is_agent_title(title):
        return ""
    i = 0
    while i < len(title) and not title[i].isalnum():
        i += 1
    return title[i:]


def push_text(kind, session, task, message):
    """(title, body) for the banner."""
    if kind == "alert":
        return f"{session} needs you", (message or task or "Claude is waiting on you")[:180]
    return f"{session} finished", (task or message or "")[:180]


def permission_summary(event):
    """One line saying what the agent wants to do, for the push that asks."""
    tool = str(event.get("tool_name") or "a tool")
    args = event.get("tool_input") if isinstance(event.get("tool_input"), dict) else {}
    detail = ""
    for key in ("command", "file_path", "notebook_path", "url", "pattern", "query"):
        if isinstance(args.get(key), str) and args[key].strip():
            detail = " ".join(args[key].split())
            break
    text = f"{tool}: {detail}" if detail else tool
    return text if len(text) <= 160 else text[:159] + "\u2026"


REMOTE_URL = re.compile(r"https://claude\.ai/code/session_[A-Za-z0-9_-]{1,80}")


def remote_url(lines):
    """The Remote Control address of a Claude Code session, from its transcript's lines:
    the last one the session announced, or "" when Remote Control is not on."""
    found = ""
    for line in lines:
        if '"bridge_status"' not in line:
            continue
        match = REMOTE_URL.search(line)
        if match:
            found = match.group(0)
    return found


def is_request_id(text):
    return len(text) == 16 and all(c in "0123456789abcdef" for c in text)


def decision_output(decision):
    """What a PermissionRequest hook prints to answer the prompt."""
    answer = {"behavior": "allow"} if decision == "allow" else {
        "behavior": "deny", "message": "Denied from the phone."}
    return {"hookSpecificOutput": {"hookEventName": "PermissionRequest", "decision": answer}}


def summarize(states, now):
    """(status, detail) for the lock-screen activity from {session: (state, epoch)},
    or None when nothing is running or waiting."""
    live = {s: v for s, v in states.items() if now - v[1] < 12 * 3600}
    waiting = sorted(s for s, v in live.items() if v[0] == NEEDS_INPUT)
    running = sorted(s for s, v in live.items() if v[0] == RUNNING)
    if waiting:
        more = f" +{len(waiting) - 1}" if len(waiting) > 1 else ""
        detail = f"{waiting[0]}{more}"
        if running:
            detail += f" · {len(running)} running"
        return "needs input", detail
    if running:
        more = f" +{len(running) - 1}" if len(running) > 1 else ""
        return "running", f"{running[0]}{more}"
    return None


# ---- tmux and files ----------------------------------------------------------------

def tmux(*args):
    try:
        out = subprocess.run(["tmux", *args], capture_output=True, text=True, timeout=5)
    except (OSError, subprocess.TimeoutExpired):
        return ""
    return out.stdout.rstrip("\n") if out.returncode == 0 else ""


def read_state(session):
    try:
        parts = (STATE / hexname(session)).read_text().rstrip("\n").split("\t", 2)
        return parts[0], int(parts[1]), parts[2] if len(parts) > 2 else ""
    except (OSError, ValueError, IndexError):
        return "", 0, ""


def write_state(session, state, message=""):
    STATE.mkdir(parents=True, exist_ok=True)
    path = STATE / hexname(session)
    if not state:
        path.unlink(missing_ok=True)
        return
    tmp = path.with_suffix(".tmp")
    tmp.write_text(f"{state}\t{int(time.time())}\t{message.replace(chr(10), ' ')[:200]}\n")
    tmp.replace(path)


def all_states():
    out = {}
    if not STATE.is_dir():
        return out
    for path in STATE.iterdir():
        name = unhex(path.name)
        if name is None:
            continue
        try:
            parts = path.read_text().split("\t")
            out[name] = (parts[0], int(parts[1]))
        except (OSError, ValueError, IndexError):
            continue
    return out


def read_request(session):
    try:
        data = json.loads((REQUESTS / hexname(session)).read_text())
    except (OSError, ValueError):
        return None
    return data if isinstance(data, dict) and is_request_id(str(data.get("id", ""))) else None


def write_request(session, request):
    REQUESTS.mkdir(parents=True, exist_ok=True)
    path = REQUESTS / hexname(session)
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(request))
    tmp.replace(path)


def clear_request(session, only_id=None):
    current = read_request(session)
    if current is None or (only_id and current["id"] != only_id):
        return
    (REQUESTS / hexname(session)).unlink(missing_ok=True)
    (DECISIONS / current["id"]).unlink(missing_ok=True)


def take_decision(request_id):
    """The answer blink-decide left for this request, once."""
    path = DECISIONS / request_id
    try:
        text = path.read_text().strip()
    except OSError:
        return None
    path.unlink(missing_ok=True)
    return text if text in ("allow", "deny") else None


def someone_watching(session):
    now = time.time()
    for line in tmux("list-clients", "-t", f"={session}", "-F", "#{client_activity}").splitlines():
        try:
            if now - int(line) < WATCHING_SECS:
                return True
        except ValueError:
            pass
    return False


def config():
    try:
        return json.loads((HOME / "config.json").read_text())
    except (OSError, ValueError):
        return {}


def log(text):
    try:
        HOME.mkdir(parents=True, exist_ok=True)
        if LOG.exists() and LOG.stat().st_size > 200_000:
            LOG.write_text("")
        with LOG.open("a") as f:
            f.write(time.strftime("%Y-%m-%d %H:%M:%S ") + text + "\n")
    except OSError:
        pass


def detach(argv):
    """Run without holding up the agent; output goes to the hook log."""
    try:
        HOME.mkdir(parents=True, exist_ok=True)
        with LOG.open("a") as f:
            subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=f, stderr=f,
                             start_new_session=True)
    except OSError as e:
        log(f"could not start {argv[0]}: {e}")


def push_argv(kind, host, session, title, body, request="", url=""):
    """argv for `blink-push`, every free-text field hex-encoded so it survives ssh."""
    argv = [kind, host, hexname(session), title.encode().hex(), body.encode().hex()]
    if request or url:
        argv.append(request or "-")
    if url:
        argv.append(url.encode().hex())
    return argv


def transcript_remote_url(path):
    if not path:
        return ""
    try:
        with open(path, errors="replace") as f:
            return remote_url(f)
    except OSError:
        return ""


def send_push(kind, host, session, title, body, request="", url=""):
    cfg = config()
    args = push_argv(kind, host, session, title, body, request, url)
    here = str(Path(__file__).resolve())
    if cfg.get("p8"):
        detach([sys.executable, here, "push", *args])
    elif cfg.get("relay"):
        detach(["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=5",
                "-o", "ServerAliveInterval=5", "-o", "ServerAliveCountMax=2",
                cfg["relay"], "blink-push", *args])
    else:
        log("no key and no relay in config.json; push not sent")


# ---- commands ----------------------------------------------------------------------

def wait_for_decision(session, request_id, sleep=time.sleep, clock=time.time):
    """Holds a permission request open until the phone answers it, something else in the
    session replaces or clears it, or the wait runs out. Returns "allow", "deny" or None."""
    deadline = clock() + DECISION_WAIT_SECS
    while clock() < deadline:
        current = read_request(session)
        if current is None or current["id"] != request_id:
            return None  # answered in the terminal, or a newer request took its place
        decision = take_decision(request_id)
        if decision:
            clear_request(session, request_id)
            return decision
        sleep(DECISION_POLL_SECS)
    clear_request(session, request_id)
    return None


def cmd_permission(event, session):
    """A permission prompt just opened. Leave a request the push can name, then wait for
    the phone's answer; printing nothing leaves the prompt to the terminal."""
    request_id = secrets.token_hex(8)
    write_request(session, {"id": request_id, "summary": permission_summary(event),
                            "at": int(time.time())})
    decision = wait_for_decision(session, request_id)
    if decision:
        log(f"PermissionRequest {session}: {decision} from the phone")
        print(json.dumps(decision_output(decision)))
    return 0


def cmd_hook():
    try:
        event = json.load(sys.stdin)
    except ValueError:
        return 0
    pane = os.environ.get("TMUX_PANE")
    if not pane or not os.environ.get("TMUX"):
        return 0  # not in tmux: nothing to name, nothing to return to
    is_permission = event.get("hook_event_name") == "PermissionRequest"
    new = state_for(event)
    if new is None and not is_permission:
        return 0
    info = tmux("display-message", "-p", "-t", pane, "#{session_name}\t#{pane_title}")
    session, _, title = info.partition("\t")
    if not session:
        return 0
    if is_permission:
        return cmd_permission(event, session)
    previous, _, _ = read_state(session)
    message = event.get("message") or ""
    write_state(session, new, message)
    request = read_request(session) if asks_permission(event) else None
    if new != NEEDS_INPUT:
        clear_request(session)  # the turn moved on; an open request is answered or moot
    kind = push_for(new, previous, someone_watching(session)) if new else None
    host = tmux("display-message", "-p", "#{host_short}") or os.uname().nodename.split(".")[0]
    if kind:
        title_text, body = push_text(kind, session, task_from_title(title), message)
        if request and kind == "alert":
            body = request.get("summary") or body
        alert = kind == "alert"
        send_push(kind, host, session, title_text, body,
                  request["id"] if request and alert else "",
                  transcript_remote_url(event.get("transcript_path")) if alert else "")
    log(f"{event.get('hook_event_name')} {session}: {previous or '-'} -> {new or 'ended'}"
        + (f" push={kind}" if kind else ""))
    if new != previous:
        cfg = config()
        here = str(Path(__file__).resolve())
        if cfg.get("p8"):
            detach([sys.executable, here, "activity"])
        elif cfg.get("relay"):
            pass  # the relay host's own sessions drive the lock-screen activity
    return 0


def cmd_attach(argv):
    name = unhex(argv[0]) if argv else None
    if name is None:
        print("blink-attach: not a session name", file=sys.stderr)
        return 2
    os.execvp("tmux", ["tmux", "new-session", "-A", "-s", name])


def cmd_sessions():
    fmt = "#{session_name}\t#{session_windows}\t#{session_attached}\t#{session_activity}\t#{pane_title}"
    now = time.time()
    host = tmux("display-message", "-p", "#{host_short}") or os.uname().nodename.split(".")[0]
    for line in tmux("list-sessions", "-F", fmt).splitlines():
        parts = line.split("\t", 4)
        if len(parts) < 5:
            continue
        name, windows, attached, activity, title = parts
        state, at, _ = read_state(name)
        if not is_agent_title(title) or now - at > STALE_SECS:
            state = ""
        print("\t".join([name, windows, attached, activity, state or "-", host, title]))
    return 0


def notify_argv(cfg, token, extra):
    here = Path(__file__).resolve().parent / "blink_notify.py"
    return [str(here), "--token", token, "--key-id", cfg["key_id"], "--team-id", cfg["team_id"],
            "--p8", os.path.expanduser(cfg["p8"]), "--topic", cfg.get("topic", "com.obercode.blink"),
            *extra]


def read_token(name):
    try:
        token = (HOME / name).read_text().strip()
    except OSError:
        return ""
    return token if token and all(c in "0123456789abcdefABCDEF" for c in token) else ""


def cmd_decide(argv):
    if len(argv) != 2 or not is_request_id(argv[0]) or argv[1] not in ("allow", "deny"):
        print("usage: blink-decide REQUESTID allow|deny", file=sys.stderr)
        return 2
    request_id, decision = argv
    waiting = False
    if REQUESTS.is_dir():
        for path in REQUESTS.iterdir():
            name = unhex(path.name)
            current = read_request(name) if name else None
            if current and current["id"] == request_id:
                waiting = True
    if not waiting:
        print("expired")  # answered already, or the agent moved on
        return 3
    DECISIONS.mkdir(parents=True, exist_ok=True)
    tmp = DECISIONS / (request_id + ".tmp")
    tmp.write_text(decision)
    tmp.replace(DECISIONS / request_id)
    print("ok")
    return 0


def cmd_push(argv):
    if len(argv) not in (5, 6, 7) or argv[0] not in ("alert", "quiet"):
        print("usage: blink-push alert|quiet HOST SESSIONHEX TITLEHEX BODYHEX [REQUESTID|-] [URLHEX]",
              file=sys.stderr)
        return 2
    kind, host, session_hex, title_hex, body_hex = argv[:5]
    request = argv[5] if len(argv) >= 6 and argv[5] != "-" else ""
    if request and not is_request_id(request):
        return 2
    url = ""
    if len(argv) == 7:
        try:
            url = bytes.fromhex(argv[6]).decode()
        except ValueError:
            return 2
        if not REMOTE_URL.fullmatch(url):
            return 2
    session = unhex(session_hex)
    try:
        title, body = bytes.fromhex(title_hex).decode(), bytes.fromhex(body_hex).decode()
    except ValueError:
        return 2
    if session is None or not host.replace("-", "").replace(".", "").isalnum():
        return 2
    cfg, token = config(), read_token("token")
    if not cfg.get("p8") or not token:
        log("push not sent: this host has no key or no device token")
        return 1
    extra = ["--title", title, "--body", body, "--host", host, "--session", session,
             "--kind", "needs_input" if kind == "alert" else "done",
             "--collapse-id", f"{host}.{session_hex}"[:64]]
    if kind == "quiet":
        extra.append("--quiet")
    if request:
        extra += ["--request", request]
    if url:
        extra += ["--claude-url", url]
    return run_notify(notify_argv(cfg, token, extra))


def plan_activity(summary, shown, has_token, has_start, marker_age, waited):
    """What to do about the lock-screen activity: "none", "end", "update", "start", or
    "wait-start" / "wait-end" (look again after the delay; `waited` says that was done)."""
    if summary is None:
        if not shown:
            return "none"
        return "end" if waited else "wait-end"
    if f"{summary[0]}\t{summary[1]}" == shown:
        return "none"
    if has_token and shown:
        return "update"
    if shown and marker_age < START_GRACE_SECS:
        return "none"  # started a moment ago; the phone hasn't published the new token yet
    if not has_start:
        return "none"  # the phone hasn't offered a way to start one (older iOS, or turned off)
    if summary[0] == "running" and not waited:
        return "wait-start"
    return "start"


def cmd_activity(sleep=time.sleep):
    """Bring the lock-screen activity in line with what the agents are doing."""
    cfg = config()
    if not cfg.get("p8"):
        return 0
    HOME.mkdir(parents=True, exist_ok=True)
    lock = (HOME / "activity.lock").open("w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        return 0  # another run is already settling it and will see the newest states
    marker = HOME / "activity-shown"
    waited = False
    for _ in range(8):
        summary = summarize(all_states(), time.time())
        token = read_token("activity-token")
        shown = marker.read_text().strip() if marker.exists() else ""
        age = time.time() - marker.stat().st_mtime if marker.exists() else 0
        plan = plan_activity(summary, shown, bool(token), bool(read_token("activity-start-token")),
                             age, waited)
        if plan == "none":
            return 0
        if plan == "wait-start":
            sleep(START_DELAY_SECS)
            waited = True
            continue
        if plan == "wait-end":
            sleep(END_DELAY_SECS)
            waited = True
            continue
        waited = False
        if plan == "end":
            if token:
                run_notify(notify_argv(cfg, token, ["--live-activity-event", "end"]))
            marker.unlink(missing_ok=True)
            (HOME / "activity-token").unlink(missing_ok=True)
            continue
        status, detail = summary
        la = ["--la-status", status, "--la-detail", detail]
        if plan == "update":
            rc = run_notify(notify_argv(cfg, token, ["--live-activity-event", "update", *la]))
            if rc != 0:
                # The activity that token belonged to is gone; start a fresh one next time.
                marker.unlink(missing_ok=True)
                (HOME / "activity-token").unlink(missing_ok=True)
                return rc
        else:
            host = os.uname().nodename.split(".")[0].lower()
            (HOME / "activity-token").unlink(missing_ok=True)
            rc = run_notify(notify_argv(cfg, read_token("activity-start-token"),
                                        ["--live-activity-event", "start",
                                         "--host", host, "--session", "agents", *la]))
            if rc != 0:
                return rc
        marker.write_text(f"{status}\t{detail}")
    return 0


def run_notify(argv):
    """Runs blink_notify from the home directory: `uv run` in an agent's project directory
    would pick up that project's Python requirement and refuse to start."""
    return subprocess.run(argv, timeout=60, cwd=str(Path.home())).returncode


def main():
    name = Path(sys.argv[0]).name
    argv = sys.argv[1:]
    if name.startswith("blink_fleet") and argv:
        name, argv = "blink-" + argv[0], argv[1:]
    if name == "blink-agent-hook" or name == "blink-hook":
        return cmd_hook()
    if name == "blink-attach":
        return cmd_attach(argv)
    if name == "blink-sessions":
        return cmd_sessions()
    if name == "blink-push":
        return cmd_push(argv)
    if name == "blink-decide":
        return cmd_decide(argv)
    if name == "blink-activity":
        return cmd_activity()
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
