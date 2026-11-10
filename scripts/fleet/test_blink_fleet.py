import importlib.util
import json
import os
import pathlib
import subprocess
import sys

HERE = pathlib.Path(__file__).parent
spec = importlib.util.spec_from_file_location("blink_fleet", HERE / "blink_fleet.py")
bf = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bf)


def ev(name, **kw):
    return {"hook_event_name": name, **kw}


def test_events_map_to_states():
    assert bf.state_for(ev("UserPromptSubmit")) == "running"
    assert bf.state_for(ev("Stop")) == "done"
    assert bf.state_for(ev("SessionEnd")) == ""
    assert bf.state_for(ev("Notification", notification_type="permission_prompt")) == "needs_input"
    assert bf.state_for(ev("Notification", notification_type="elicitation_dialog")) == "needs_input"
    assert bf.state_for(ev("Notification", notification_type="idle_prompt")) == "done"
    assert bf.state_for(ev("Notification", notification_type="auth_success")) is None
    assert bf.state_for(ev("PreToolUse")) is None


def test_older_notifications_without_a_type_are_read_from_the_message():
    assert bf.state_for(ev("Notification", message="Claude needs your permission to use Bash")) == "needs_input"
    assert bf.state_for(ev("Notification", message="Claude is waiting for your input")) == "done"
    assert bf.state_for(ev("Notification", message="something else")) is None


def test_needing_input_rings_and_finishing_is_quiet():
    assert bf.push_for("needs_input", "running", False) == "alert"
    assert bf.push_for("done", "running", False) == "quiet"
    assert bf.push_for("done", "needs_input", False) == "quiet"


def test_no_push_when_watching_or_nothing_changed():
    assert bf.push_for("needs_input", "running", True) is None
    assert bf.push_for("needs_input", "needs_input", False) is None
    assert bf.push_for("done", "done", False) is None      # idle_prompt after Stop
    assert bf.push_for("done", "", False) is None           # a stop with no prompt before it
    assert bf.push_for("running", "done", False) is None


def test_session_names_travel_as_hex():
    assert bf.hexname("neon starship") == "6e656f6e207374617273686970"
    assert bf.unhex("6e656f6e207374617273686970") == "neon starship"
    assert bf.unhex("zz") is None
    assert bf.unhex("") is None
    assert bf.unhex("610a62") is None            # a line break
    assert bf.unhex("61" * 65) is None


def test_agent_titles():
    assert bf.is_agent_title("✳ Blink refresh bugs")
    assert bf.is_agent_title("⠐ Working")
    assert not bf.is_agent_title("nateober@ada:~")
    assert bf.task_from_title("✳ Blink refresh bugs") == "Blink refresh bugs"
    assert bf.task_from_title("zsh") == ""


def test_push_text():
    assert bf.push_text("alert", "blink", "Fix bugs", "Claude needs your permission to use Bash") == (
        "blink needs you", "Claude needs your permission to use Bash")
    assert bf.push_text("quiet", "blink", "Fix bugs", "") == ("blink finished", "Fix bugs")


def test_lock_screen_summary():
    now = 1_000_000
    assert bf.summarize({}, now) is None
    assert bf.summarize({"a": ("done", now)}, now) is None
    assert bf.summarize({"a": ("running", now), "b": ("running", now)}, now) == ("running", "a +1")
    assert bf.summarize({"a": ("running", now), "b": ("needs_input", now)}, now) == ("needs input", "b · 1 running")
    assert bf.summarize({"a": ("running", now - 13 * 3600)}, now) is None


def run(name, args, home, stdin="", env=None):
    link = home / name
    if not link.exists():
        link.symlink_to(HERE / "blink_fleet.py")
    e = {**os.environ, "BLINK_NOTIFY_HOME": str(home), **(env or {})}
    e.pop("TMUX", None)
    e.pop("TMUX_PANE", None)
    e.update(env or {})
    return subprocess.run([sys.executable, str(link), *args], input=stdin,
                          capture_output=True, text=True, env=e)


def test_hook_outside_tmux_does_nothing(tmp_path):
    r = run("blink-agent-hook", [], tmp_path, stdin=json.dumps(ev("Stop")))
    assert r.returncode == 0
    assert not (tmp_path / "state").exists()


def test_hook_survives_bad_input(tmp_path):
    assert run("blink-agent-hook", [], tmp_path, stdin="not json").returncode == 0


def test_attach_refuses_a_bad_name(tmp_path):
    assert run("blink-attach", ["zz"], tmp_path).returncode == 2
    assert run("blink-attach", [], tmp_path).returncode == 2


def test_push_refuses_bad_arguments_and_missing_key(tmp_path):
    assert run("blink-push", ["alert", "ada"], tmp_path).returncode == 2
    assert run("blink-push", ["loud", "ada", "61", "61", "61"], tmp_path).returncode == 2
    assert run("blink-push", ["alert", "ada;rm", "61", "61", "61"], tmp_path).returncode == 2
    assert run("blink-push", ["alert", "ada", "61", "61", "61"], tmp_path).returncode == 1


def test_quiet_push_payload_and_remote_start():
    def notify(args):
        r = subprocess.run([sys.executable, str(HERE / "blink_notify.py"), *args, "--dry-run"],
                           capture_output=True, text=True)
        assert r.returncode == 0, r.stderr
        return json.loads(r.stdout)
    quiet = notify(["--token", "ab12", "--title", "T", "--quiet"])
    assert quiet["aps"]["interruption-level"] == "passive"
    assert "sound" not in quiet["aps"]
    loud = notify(["--token", "ab12", "--title", "T"])
    assert loud["aps"]["sound"] == "default"
    start = notify(["--token", "ab12", "--live-activity-event", "start", "--host", "ada",
                    "--session", "agents", "--la-status", "running", "--la-detail", "blink"])
    assert start["aps"]["event"] == "start"
    assert start["aps"]["attributes-type"] == "FleetActivityAttributes"
    assert start["aps"]["attributes"] == {"host": "ada", "sessionLabel": "agents"}
    assert start["aps"]["alert"]["body"] == "blink"
    # Seconds since 2001, which is what ActivityKit's decoder expects for a Date.
    assert start["aps"]["content-state"]["updatedAt"] < 1_000_000_000
