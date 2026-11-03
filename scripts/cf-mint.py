#!/usr/bin/env python3
# scripts/cf-mint.py — 用 CF_PARENT_TOKEN 现签一把 2h 短 token（fail-closed）。
# 用法：CF_PARENT_TOKEN=... CF_TOKEN_NAME=... CF_TOKEN_TTL_HOURS=2 \
#       CF_PERM_GROUPS="zone read,zone rulesets read" CF_ZONE_NAME=linkseek.net.cn \
#       python3 scripts/cf-mint.py
# 输出：CF_MINTED_VALUE=<token>（调用方负责 ::add-mask:: + 写入 GITHUB_ENV）。
# 失败：打印 FAIL + 非零退出，不吐 secret。
import json
import os
import sys
import urllib.parse
import urllib.request
import urllib.error
from datetime import datetime, timedelta, timezone

BASE = "https://api.cloudflare.com/client/v4"


def call(token, method, path, body=None):
    headers = {"Authorization": "Bearer " + token}
    data = None
    if body is not None:
        headers["Content-Type"] = "application/json"
        data = json.dumps(body).encode()
    req = urllib.request.Request(BASE + path, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return resp.status, json.load(resp or b"{}")
    except urllib.error.HTTPError as exc:
        try:
            return exc.code, json.load(exc.read() or b"{}")
        except Exception:
            return exc.code, {}
    except Exception as exc:
        return 0, {"success": False, "errors": [{"message": str(exc)[:200]}]}


def main():
    parent = os.environ.get("CF_PARENT_TOKEN", "").strip()
    if not parent:
        print("FAIL: CF_PARENT_TOKEN 为空")
        return 1
    zone_name = os.environ.get("CF_ZONE_NAME", "linkseek.net.cn")
    st, r = call(parent, "GET", "/zones?name=" + urllib.parse.quote(zone_name))
    if not (isinstance(r, dict) and r.get("success") and r.get("result")):
        print("FAIL: 取 zone/account 失败 status=%s body=%s" % (st, json.dumps(r)[:200] if isinstance(r, dict) else "?"))
        return 1
    zones = r["result"]
    print("ZONE %s id=%s" % (zone_name, zones[0]["id"]))
    account_id = (zones[0].get("account") or {}).get("id")
    if not account_id:
        print("FAIL: zone 无 account")
        return 1
    st, r = call(parent, "GET", "/accounts/%s/tokens/permission_groups?per_page=100" % account_id)
    groups = r.get("result") if isinstance(r, dict) and isinstance(r.get("result"), list) else []
    by_name = {}
    for g in groups:
        by_name.setdefault(str(g.get("name", "")).lower(), g)
        by_name.setdefault(str(g.get("name", "")).lower().replace(" ", "_"), g)
    wanted = [x.strip().lower() for x in os.environ.get("CF_PERM_GROUPS", "").split(",") if x.strip()]
    zone_ids = []
    for w in wanted:
        cand = [w, w.replace(" ", "_"), w.replace("_", " ")]
        g = next((by_name[c] for c in cand if c in by_name), None)
        if not g:
            print("FAIL: permission group 不存在: %s" % w)
            print("AVAILABLE-ALL: %s" % sorted(by_name))
            return 1
        zone_ids.append(str(g["id"]))
    policies = [{
        "effect": "allow",
        "resources": {"com.cloudflare.api.account.%s" % account_id: {"com.cloudflare.api.account.zone.*": "*"}},
        "permission_groups": [{"id": i} for i in zone_ids],
    }]
    expires = (datetime.now(timezone.utc) + timedelta(hours=int(os.environ.get("CF_TOKEN_TTL_HOURS", "2")))).strftime("%Y-%m-%dT%H:%M:%SZ")
    st, r = call(parent, "POST", "/accounts/%s/tokens" % account_id, {
        "name": os.environ.get("CF_TOKEN_NAME", "cf-edge"),
        "expires_on": expires,
        "policies": policies,
    })
    if not (isinstance(r, dict) and r.get("success")):
        print("FAIL: CF 现签失败 status=%s errors=%s" % (st, json.dumps((r or {}).get("errors"))[:300] if isinstance(r, dict) else "?"))
        return 1
    value = str((r.get("result") or {}).get("value") or "")
    if not value:
        print("FAIL: CF 现签无值")
        return 1
    print("CF_MINTED_VALUE=%s" % value)
    return 0


if __name__ == "__main__":
    sys.exit(main())
