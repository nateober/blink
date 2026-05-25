#!/usr/bin/env -S uv run --quiet --with PyJWT --with cryptography --with requests --
"""
App Store Connect API helper for the personal-use Blink fork.

Auth: ECDSA P-256 JWT signed with the .p8 private key, valid for 20 min.

Usage:
  asc_api.py whoami
  asc_api.py list-apps
  asc_api.py list-bundle-ids
  asc_api.py register-bundle-id <bundle-id> <name>
  asc_api.py create-app <bundle-id> <name> <sku> <primary-lang>
"""
import json
import os
import sys
import time
import jwt
import requests

KEY_PATH = os.path.expanduser("~/.appstoreconnect/private_keys/AuthKey_S3MYBGRBL4.p8")
KEY_ID = "S3MYBGRBL4"
ISSUER_ID = "9ff16463-2c73-4e60-8bf9-273267673229"
BASE = "https://api.appstoreconnect.apple.com"


def token() -> str:
    with open(KEY_PATH, "rb") as f:
        private_key = f.read()
    now = int(time.time())
    return jwt.encode(
        {
            "iss": ISSUER_ID,
            "iat": now,
            "exp": now + 20 * 60,
            "aud": "appstoreconnect-v1",
        },
        private_key,
        algorithm="ES256",
        headers={"kid": KEY_ID, "typ": "JWT"},
    )


def call(method: str, path: str, **kwargs) -> dict:
    r = requests.request(
        method,
        f"{BASE}{path}",
        headers={
            "Authorization": f"Bearer {token()}",
            "Content-Type": "application/json",
        },
        **kwargs,
    )
    if not r.ok:
        print(f"HTTP {r.status_code}: {r.text}", file=sys.stderr)
        sys.exit(1)
    return r.json() if r.text else {}


def cmd_whoami():
    print(json.dumps(call("GET", "/v1/users?limit=5"), indent=2))


def cmd_list_apps():
    data = call("GET", "/v1/apps?limit=200")
    for app in data.get("data", []):
        a = app["attributes"]
        print(f"{app['id']}  {a.get('bundleId'):40s}  {a.get('name')}")


def cmd_list_bundle_ids():
    data = call("GET", "/v1/bundleIds?limit=200")
    for b in data.get("data", []):
        a = b["attributes"]
        print(f"{b['id']}  {a.get('identifier'):40s}  {a.get('name')}")


def cmd_register_bundle_id(identifier: str, name: str):
    body = {
        "data": {
            "type": "bundleIds",
            "attributes": {
                "identifier": identifier,
                "name": name,
                "platform": "IOS",
            },
        }
    }
    out = call("POST", "/v1/bundleIds", json=body)
    print(json.dumps(out, indent=2))


def cmd_create_app(bundle_id: str, name: str, sku: str, primary_language: str):
    # Step 1: look up the bundleId resource id (it must already be registered)
    bids = call("GET", f"/v1/bundleIds?filter[identifier]={bundle_id}")
    if not bids.get("data"):
        print(f"Bundle ID {bundle_id} is not registered yet — run register-bundle-id first.", file=sys.stderr)
        sys.exit(1)
    bid_resource_id = bids["data"][0]["id"]

    body = {
        "data": {
            "type": "apps",
            "attributes": {
                "bundleId": bundle_id,
                "name": name,
                "primaryLocale": primary_language,
                "sku": sku,
            },
            "relationships": {
                "bundleId": {
                    "data": {"type": "bundleIds", "id": bid_resource_id}
                }
            },
        }
    }
    out = call("POST", "/v1/apps", json=body)
    print(json.dumps(out, indent=2))


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    cmd, *args = sys.argv[1:]
    fn = {
        "whoami": cmd_whoami,
        "list-apps": cmd_list_apps,
        "list-bundle-ids": cmd_list_bundle_ids,
        "register-bundle-id": cmd_register_bundle_id,
        "create-app": cmd_create_app,
    }.get(cmd)
    if not fn:
        print(__doc__)
        sys.exit(1)
    fn(*args)


if __name__ == "__main__":
    main()
