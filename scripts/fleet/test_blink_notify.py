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
