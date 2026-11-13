import json, subprocess, sys, pathlib

HERE = pathlib.Path(__file__).parent

def run(args):
    return subprocess.run([sys.executable, str(HERE / "blink_notify.py"), *args],
                          capture_output=True, text=True)

def test_builds_needs_input_payload():
    r = run(["--token", "abc", "--title", "T", "--body", "B",
             "--kind", "needs_input", "--host", "ada", "--dry-run"])
    assert r.returncode == 0, r.stderr
    payload = json.loads(r.stdout)
    assert payload["aps"]["alert"]["title"] == "T"
    assert payload["aps"]["alert"]["body"] == "B"
    assert payload["blink"]["kind"] == "needs_input"
    assert payload["blink"]["host"] == "ada"

def test_default_kind_is_needs_input():
    r = run(["--token", "abc", "--title", "T", "--dry-run"])
    assert r.returncode == 0, r.stderr
    assert json.loads(r.stdout)["blink"]["kind"] == "needs_input"

def test_requires_token():
    r = run(["--title", "T", "--body", "B", "--dry-run"])
    assert r.returncode != 0

def test_session_included_when_given():
    r = run(["--token", "t", "--title", "T", "--session", "s9", "--dry-run"])
    assert json.loads(r.stdout)["blink"]["session"] == "s9"

def test_payload_sets_content_available_for_background_wake():
    r = run(["--token", "abc", "--title", "T", "--dry-run"])
    assert json.loads(r.stdout)["aps"]["content-available"] == 1

def test_live_activity_update_payload():
    r = run(["--token", "abc", "--live-activity-event", "update",
             "--la-status", "needs input", "--la-detail", "on ada", "--dry-run"])
    assert r.returncode == 0, r.stderr
    aps = json.loads(r.stdout)["aps"]
    assert aps["event"] == "update"
    assert aps["content-state"]["status"] == "needs input"
    assert aps["content-state"]["detail"] == "on ada"


def test_a_permission_request_gets_buttons():
    r = run(["--token", "ab12", "--title", "t", "--body", "Bash: ls", "--host", "ada",
             "--session", "work", "--request", "00112233aabbccdd", "--dry-run"])
    assert r.returncode == 0, r.stderr
    payload = json.loads(r.stdout)
    assert payload["aps"]["category"] == "AGENT_PERMISSION"
    assert payload["blink"]["request"] == "00112233aabbccdd"


def test_buttons_follow_what_the_push_carries():
    url = "https://claude.ai/code/session_01abc"
    base = ["--token", "ab12", "--title", "t", "--host", "ada", "--session", "work", "--dry-run"]
    both = json.loads(run(base + ["--request", "00112233aabbccdd", "--claude-url", url]).stdout)
    assert both["aps"]["category"] == "AGENT_PERMISSION_REMOTE" and both["blink"]["claude"] == url
    only_url = json.loads(run(base + ["--claude-url", url]).stdout)
    assert only_url["aps"]["category"] == "AGENT_REMOTE" and "request" not in only_url["blink"]
    plain = json.loads(run(base).stdout)
    assert "category" not in plain["aps"] and plain["aps"]["sound"] == "default"
    quiet = json.loads(run(base + ["--quiet", "--claude-url", url]).stdout)
    assert "category" not in quiet["aps"]
