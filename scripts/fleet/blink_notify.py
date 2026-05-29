#!/usr/bin/env -S uv run --quiet --with PyJWT --with cryptography --with httpx[http2] --python 3.12 --
"""blink-notify — send an agent-attention push to the Blink iOS app via APNs.

Meant to run on a fleet host (Ada/Vera/Max), invoked from a `claude -p` wrapper when
the agent needs input. Builds the BlinkPush payload (mirrors FleetCore's BlinkPush) and
delivers it to APNs over HTTP/2 using a provider .p8 auth key.

  blink_notify.py --token <hex> --title "Claude needs you" --body "approve edit?" \
                  --kind needs_input --host ada \
                  --key-id <KID> --team-id <ISSUER> --topic com.obercode.blink \
                  --p8 ~/.appstoreconnect/apns/AuthKey_<KID>.p8

--dry-run prints the payload JSON and exits (no deps needed) — used by tests.
"""
import argparse, json, sys, time

APNS_HOST = "https://api.push.apple.com"  # production; use api.sandbox.push.apple.com for dev builds

def build_payload(args):
    blink = {"kind": args.kind}
    if args.host: blink["host"] = args.host
    if args.session: blink["session"] = args.session
    alert = {"title": args.title}
    if args.body: alert["body"] = args.body
    return {"aps": {"alert": alert, "sound": "default"}, "blink": blink}

def send(args, payload):
    # Lazy imports so --dry-run needs no third-party deps.
    import jwt, httpx
    with open(args.p8) as f:
        key = f.read()
    token = jwt.encode(
        {"iss": args.team_id, "iat": int(time.time())},
        key, algorithm="ES256", headers={"kid": args.key_id},
    )
    url = f"{args.host_base}/3/device/{args.token}"
    headers = {
        "authorization": f"bearer {token}",
        "apns-topic": args.topic,
        "apns-push-type": "alert",
        "apns-priority": "10",
    }
    with httpx.Client(http2=True, timeout=15) as client:
        r = client.post(url, headers=headers, content=json.dumps(payload))
    print(f"APNs {r.status_code} {r.headers.get('apns-id','')} {r.text}".strip())
    return 0 if r.status_code == 200 else 1

def main():
    ap = argparse.ArgumentParser(prog="blink_notify")
    ap.add_argument("--token", required=True, help="APNs device token (hex)")
    ap.add_argument("--title", required=True)
    ap.add_argument("--body", default="")
    ap.add_argument("--kind", default="needs_input", choices=["needs_input", "done", "progress"])
    ap.add_argument("--host", default="")
    ap.add_argument("--session", default="")
    ap.add_argument("--key-id", dest="key_id", default="")
    ap.add_argument("--team-id", dest="team_id", default="")
    ap.add_argument("--topic", default="com.obercode.blink")
    ap.add_argument("--p8", default="")
    ap.add_argument("--sandbox", action="store_true", help="use APNs sandbox host")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()
    args.host_base = "https://api.sandbox.push.apple.com" if args.sandbox else APNS_HOST

    payload = build_payload(args)
    if args.dry_run:
        print(json.dumps(payload))
        return 0
    missing = [n for n in ("key_id", "team_id", "p8") if not getattr(args, n)]
    if missing:
        ap.error("send requires --key-id, --team-id, --p8 (or use --dry-run): missing " + ",".join(missing))
    return send(args, payload)

if __name__ == "__main__":
    sys.exit(main())
