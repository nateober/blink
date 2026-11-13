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
    assert "content-available" not in quiet["aps"]  # a finished turn must not wake the app
    loud = notify(["--token", "ab12", "--title", "T"])
    assert loud["aps"]["sound"] == "default"
    assert loud["aps"]["content-available"] == 1
    start = notify(["--token", "ab12", "--live-activity-event", "start", "--host", "ada",
                    "--session", "agents", "--la-status", "running", "--la-detail", "blink"])
    assert start["aps"]["event"] == "start"
    assert start["aps"]["attributes-type"] == "FleetActivityAttributes"
    assert start["aps"]["attributes"] == {"host": "ada", "sessionLabel": "agents"}
    assert start["aps"]["alert"]["body"] == "blink"
    # Seconds since 2001, which is what ActivityKit's decoder expects for a Date.
    assert start["aps"]["content-state"]["updatedAt"] < 1_000_000_000


def test_activity_waits_before_starting_and_ending():
    run, ask = ("running", "a"), ("needs input", "a")
    plan = bf.plan_activity
    # A turn that has only just begun doesn't start one; after the wait it does.
    assert plan(run, "", False, True, 0, False) == "wait-start"
    assert plan(run, "", False, True, 0, True) == "start"
    # Waiting on the user starts at once.
    assert plan(ask, "", False, True, 0, False) == "start"
    # Nothing running: hold the one on screen for a while, then end it.
    assert plan(None, "running\ta", True, True, 500, False) == "wait-end"
    assert plan(None, "running\ta", True, True, 500, True) == "end"
    assert plan(None, "", False, True, 0, False) == "none"
    # The next turn began inside the wait: nothing is sent at all.
    assert plan(run, "running\ta", True, True, 500, True) == "none"
    assert plan(ask, "running\ta", True, True, 500, False) == "update"
    # Started a moment ago and the phone hasn't published the token yet.
    assert plan(ask, "running\ta", False, True, 30, False) == "none"
    assert plan(ask, "", False, False, 0, False) == "none"


def test_notify_does_not_run_inside_a_project():
    first = (pathlib.Path(bf.__file__).parent / "blink_notify.py").read_text().splitlines()[0]
    assert "--no-project" in first


# ---- answering a permission prompt from the phone ----------------------------------

def test_permission_summary_names_the_tool_and_what_it_touches():
    assert bf.permission_summary(ev("PermissionRequest", tool_name="Bash",
                                    tool_input={"command": "rm -rf\n  node_modules"})) == "Bash: rm -rf node_modules"
    assert bf.permission_summary(ev("PermissionRequest", tool_name="Edit",
                                    tool_input={"file_path": "/a/b.py", "old_string": "x"})) == "Edit: /a/b.py"
    assert bf.permission_summary(ev("PermissionRequest", tool_name="Agent", tool_input={})) == "Agent"
    long = bf.permission_summary(ev("PermissionRequest", tool_name="Bash", tool_input={"command": "x" * 400}))
    assert len(long) == 160 and long.endswith("…")


def test_decision_output_is_what_the_hook_contract_expects():
    allow = bf.decision_output("allow")["hookSpecificOutput"]
    assert allow["hookEventName"] == "PermissionRequest" and allow["decision"] == {"behavior": "allow"}
    assert bf.decision_output("deny")["hookSpecificOutput"]["decision"]["behavior"] == "deny"


def _home(tmp_path, monkeypatch):
    for name, sub in (("HOME", ""), ("STATE", "state"), ("REQUESTS", "requests"), ("DECISIONS", "decisions")):
        monkeypatch.setattr(bf, name, tmp_path / sub if sub else tmp_path)
    monkeypatch.setattr(bf, "LOG", tmp_path / "hook.log")


def test_a_decision_reaches_the_waiting_hook_once(tmp_path, monkeypatch, capsys):
    _home(tmp_path, monkeypatch)
    bf.write_request("work", {"id": "00112233aabbccdd", "summary": "Bash: ls", "at": 1})
    assert bf.cmd_decide(["00112233aabbccdd", "allow"]) == 0
    assert capsys.readouterr().out.strip() == "ok"
    assert bf.wait_for_decision("work", "00112233aabbccdd", sleep=lambda s: None) == "allow"
    assert bf.read_request("work") is None
    # the same answer a second time finds nothing waiting
    assert bf.cmd_decide(["00112233aabbccdd", "allow"]) == 3
    assert capsys.readouterr().out.strip() == "expired"


def test_the_wait_ends_when_the_request_is_cleared_or_replaced(tmp_path, monkeypatch):
    _home(tmp_path, monkeypatch)
    bf.write_request("work", {"id": "00112233aabbccdd", "summary": "", "at": 1})
    bf.clear_request("work")  # what Stop or the next prompt does
    assert bf.wait_for_decision("work", "00112233aabbccdd", sleep=lambda s: None) is None
    bf.write_request("work", {"id": "ffffffffffffffff", "summary": "", "at": 2})
    assert bf.wait_for_decision("work", "00112233aabbccdd", sleep=lambda s: None) is None
    assert bf.read_request("work")["id"] == "ffffffffffffffff"  # the newer one is left alone


def test_the_wait_gives_up_and_tidies(tmp_path, monkeypatch):
    _home(tmp_path, monkeypatch)
    bf.write_request("work", {"id": "00112233aabbccdd", "summary": "", "at": 1})
    now = [0.0]
    def tick(_):
        now[0] += 100
    assert bf.wait_for_decision("work", "00112233aabbccdd", sleep=tick, clock=lambda: now[0]) is None
    assert bf.read_request("work") is None


def test_decide_refuses_anything_but_a_request_id_and_a_verdict(tmp_path, monkeypatch):
    _home(tmp_path, monkeypatch)
    assert bf.cmd_decide(["../../etc/passwd", "allow"]) == 2
    assert bf.cmd_decide(["00112233aabbccdd", "maybe"]) == 2
    assert bf.cmd_decide(["00112233AABBCCDD", "allow"]) == 2
    assert not (tmp_path / "decisions").exists()


def test_a_push_carries_the_request_only_when_there_is_one():
    assert bf.push_argv("alert", "ada", "work", "t", "b") == ["alert", "ada", "776f726b", "74", "62"]
    assert bf.push_argv("alert", "ada", "work", "t", "b", "00112233aabbccdd")[-1] == "00112233aabbccdd"


def test_a_push_carries_the_remote_control_address_when_the_session_has_one():
    url = "https://claude.ai/code/session_01AbC-dEf_9"
    argv = bf.push_argv("alert", "ada", "work", "t", "b", "", url)
    assert argv[5] == "-" and bytes.fromhex(argv[6]).decode() == url
    argv = bf.push_argv("alert", "ada", "work", "t", "b", "00112233aabbccdd", url)
    assert argv[5] == "00112233aabbccdd" and len(argv) == 7


def test_remote_address_is_the_last_one_the_transcript_announced():
    lines = [
        '{"type":"user","content":"see https://claude.ai/code/session_notthisone"}',
        '{"type":"system","subtype":"bridge_status","content":"active at https://claude.ai/code/session_01old"}',
        '{"type":"system","subtype":"bridge_status","content":"active \\u00b7 https://claude.ai/code/session_01New-x_2?foo=1"}',
    ]
    assert bf.remote_url(lines) == "https://claude.ai/code/session_01New-x_2"
    assert bf.remote_url(lines[:1]) == ""
    assert bf.remote_url(['{"subtype":"bridge_status","content":"https://evil.example/code/session_1"}']) == ""


def test_push_refuses_an_address_that_is_not_a_claude_session(tmp_path, monkeypatch):
    _home(tmp_path, monkeypatch)
    bad = "https://evil.example/x".encode().hex()
    assert bf.cmd_push(["alert", "ada", "776f726b", "74", "62", "-", bad]) == 2
    assert bf.cmd_push(["alert", "ada", "776f726b", "74", "62", "-", "zz"]) == 2


def test_only_a_permission_prompt_may_carry_a_request():
    assert bf.asks_permission(ev("Notification", notification_type="permission_prompt"))
    assert bf.asks_permission(ev("Notification", message="Claude needs your permission to use Bash"))
    assert not bf.asks_permission(ev("Notification", notification_type="elicitation_dialog"))
    assert not bf.asks_permission(ev("Notification", notification_type="idle_prompt"))
    assert not bf.asks_permission(ev("Stop"))
