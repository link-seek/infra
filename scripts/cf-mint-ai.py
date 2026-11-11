#!/usr/bin/env python3
"""Workers AI child-token minter for kamal-deliver.
Verbatim port of the Workers AI deploy mint block in scripts/deliver-remote-core.sh
(old line untouched; single home for kamal line). Env in: CF_PARENT_TOKEN_SANITIZED,
CF_ACCOUNT_ID. Stdout: ::add-mask:: lines + CF_MINTED_VALUE=<token>.
"""
import json
import os
import sys
import urllib.error
import urllib.request
from datetime import datetime, timedelta, timezone
BASE = "https://api.cloudflare.com/client/v4"
TOKEN = os.environ["CF_PARENT_TOKEN_SANITIZED"]
ACCOUNT_ID = os.environ["CF_ACCOUNT_ID"]
print("::add-mask::%s" % TOKEN)
def call(method, path, body=None):
    headers = {"Authorization": "Bearer " + TOKEN}
    data = None
    if body is not None:
        headers["Content-Type"] = "application/json"
        data = json.dumps(body).encode()
    req = urllib.request.Request(BASE + path, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return resp.status, json.loads(resp.read() or b"{}")
    except urllib.error.HTTPError as exc:
        try:
            return exc.code, json.loads(exc.read() or b"{}")
        except Exception:
            return exc.code, {}
st, r = call("GET", "/accounts/%s/tokens/permission_groups?per_page=100" % ACCOUNT_ID)
groups = r.get("result") if isinstance(r.get("result"), list) else []
by_name = {str(g.get("name", "")).lower(): str(g.get("id") or "") for g in groups}
read_id = by_name.get("workers ai read", "")
write_id = by_name.get("workers ai write", "")
if not read_id or not write_id:
    print("FAIL: Workers AI Read/Write group 不在 permission_groups 里", file=sys.stderr)
    raise SystemExit(1)
expires = (datetime.now(timezone.utc) + timedelta(days=90)).strftime("%Y-%m-%dT%H:%M:%SZ")
st, r = call("POST", "/accounts/%s/tokens" % ACCOUNT_ID, {
    "name": "cf-ai-deploy-%s" % datetime.now(timezone.utc).strftime("%Y%m%d"),
    "policies": [{"effect": "allow",
                  "resources": {("com.cloudflare.api.account.%s" % ACCOUNT_ID): "*"},
                  "permission_groups": [{"id": read_id}, {"id": write_id}]}],
    "expires_on": expires,
})
if not r.get("success"):
    print("FAIL: Workers AI 现签 status=%s" % st, file=sys.stderr)
    raise SystemExit(1)
value = str((r.get("result") or {}).get("value") or "")
if not value:
    print("FAIL: Workers AI 现签无值", file=sys.stderr)
    raise SystemExit(1)
print("::add-mask::%s" % value)
print("CF_MINTED_VALUE=%s" % value)
