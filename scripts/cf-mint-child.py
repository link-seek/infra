#!/usr/bin/env python3
"""CF child-token minter for kamal-deliver.
Verbatim port of the CF deploy mint block in scripts/deliver-remote-core.sh
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
st, r = call("GET", "/accounts/%s/tokens/permission_groups?per_page=50" % ACCOUNT_ID)
groups = r.get("result") if isinstance(r.get("result"), list) else []
by_name = {str(g.get("name", "")).lower(): g for g in groups}
by_id = {str(g.get("id") or ""): g for g in groups}
def gid(name, fallbacks=()):
    for cand in [name] + list(fallbacks):
        g = by_name.get(cand)
        if g and g.get("id"):
            return str(g["id"])
    return ""
dns_id = gid("dns read", ["c8fed203ed3043cba015a93ad1616f1f"])
zone_id = gid("zone read", ["82e64a83756745bbbb1c9c2701bf816b"])
if not dns_id or not zone_id:
    print("FAIL: 读权限组缺失", file=sys.stderr)
    raise SystemExit(1)
# 写权限（容器 wrangler/DNS/Workers 自助，owner 已批）：别名全试，缺一即 fail-closed。
# 注意：Cloudflare 组名以列表返回为准，下面的候选只是常见写法。
WRITE_ALIASES = {
    "zone edit": ["zone edit", "zone write"],
    "dns edit": ["dns edit", "dns write"],
    "workers edit": ["workers scripts edit", "workers scripts write", "workers edit", "workers write"],
    "pages edit": ["pages edit", "pages write"],
}
write_ids = []
for want, aliases in WRITE_ALIASES.items():
    got = ""
    for a in aliases:
        if by_name.get(a) and by_name[a].get("id"):
            got = str(by_name[a]["id"])
            break
    if not got:
        print("FAIL: 写权限组缺失（要 %s，试过 %s）；现有组名前 10：%s" % (
            want, aliases, sorted(by_name.keys())[:10]), file=sys.stderr)
        raise SystemExit(1)
    write_ids.append(got)
# policy 按 scope 分流（#149 同款）：zone 级组走 zone 通配，account 级组走账号资源；
# 混一起 Cloudflare 回 400。
def scope_of(gid_):
    g = by_id.get(gid_, {})
    return [str(s) for s in (g.get("scopes") or [])]
zone_gids, acct_gids = [], []
for gid_ in [dns_id, zone_id] + write_ids:
    if any("account.zone" in s for s in scope_of(gid_)):
        zone_gids.append(gid_)
    else:
        acct_gids.append(gid_)
policies = []
if zone_gids:
    policies.append({"effect": "allow",
                     "resources": {("com.cloudflare.api.account.%s" % ACCOUNT_ID): {"com.cloudflare.api.account.zone.*": "*"}},
                     "permission_groups": [{"id": i} for i in zone_gids]})
if acct_gids:
    policies.append({"effect": "allow",
                     "resources": {("com.cloudflare.api.account.%s" % ACCOUNT_ID): "*"},
                     "permission_groups": [{"id": i} for i in acct_gids]})
if not policies:
    print("FAIL: 无可用 policy", file=sys.stderr)
    raise SystemExit(1)
expires = (datetime.now(timezone.utc) + timedelta(days=90)).strftime("%Y-%m-%dT%H:%M:%SZ")
st, r = call("POST", "/accounts/%s/tokens" % ACCOUNT_ID, {
    "name": "cf-deploy-%s" % datetime.now(timezone.utc).strftime("%Y%m%d"),
    "policies": policies,
    "expires_on": expires,
})
if not r.get("success"):
    print("FAIL: CF 现签 status=%s" % st, file=sys.stderr)
    raise SystemExit(1)
value = str((r.get("result") or {}).get("value") or "")
if not value:
    print("FAIL: CF 现签无值", file=sys.stderr)
    raise SystemExit(1)
print("::add-mask::%s" % value)
print("CF_MINTED_VALUE=%s" % value)
