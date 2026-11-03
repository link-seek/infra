#!/usr/bin/env python3
# scripts/cf-edge-apply.py — linkseek.net.cn 边缘配置声明式对账（WAF/限流/Bot）。
# 用法：STATE_FILE=cf/linkseek-edge.json DRY_RUN=1|0 CF_TOKEN=... python3 scripts/cf-edge-apply.py
# 规矩：只动本文件声明的条目（rate limit 以 description managed: 开头认领；WAF 只动已部署的托管 bundle）。
# fail-closed：任何一步不符预期即 exit 非零；dry-run 只打印计划。
import json
import os
import sys
import urllib.parse
import urllib.request
import urllib.error


BASE = "https://api.cloudflare.com/client/v4"


def api(method, path, body=None):
    token = os.environ["CF_TOKEN"]
    headers = {"Authorization": "Bearer " + token}
    data = None
    if body is not None:
        headers["Content-Type"] = "application/json"
        data = json.dumps(body).encode()
    req = urllib.request.Request(BASE + path, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return resp.status, json.load(resp)
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.load(e)
        except Exception:
            return e.code, {}


def ok(resp):
    st, r = resp
    return st in (200, 201) and isinstance(r, dict) and r.get("success", st == 200)


def main():
    state_path = os.environ.get("STATE_FILE", "cf/linkseek-edge.json")
    dry = os.environ.get("DRY_RUN", "1").lower() in ("1", "true", "yes", "on")
    want = json.load(open(state_path))
    zone_name = os.environ.get("ZONE_OVERRIDE") or want["zone"]

    st, r = api("GET", "/zones?name=" + urllib.parse.quote(zone_name))
    zones = (r.get("result") or []) if isinstance(r, dict) else []
    if st != 200 or not zones:
        print(f"FAIL: 取 zone 失败 status={st} body={json.dumps(r)[:200]}")
        return 1
    zid = zones[0]["id"]
    acct = (zones[0].get("account") or {}).get("id", "")
    print(f"zone={zone_name} id={zid} acct={acct}" + (" DRY-RUN" if dry else ""))
    if dry and os.environ.get("CF_DISCOVER", ""):
        st0, r0 = api("GET", f"/accounts/{acct}/rulesets?per_page=100")
        items = (r0.get("result") or []) if isinstance(r0, dict) else []
        print(f"DISCOVER account-rulesets total={len(items)} status={st0}")
        for it in items:
            print(f"DISCOVER id={it.get('id')} kind={it.get('kind')} phase={it.get('phase')} name={it.get('name')}")

    phases = {}
    for ph in ("http_request_firewall_managed", "http_ratelimit"):
        st0, r0 = api("GET", f"/zones/{zid}/rulesets/phases/{ph}/entrypoint")
        ok0 = st0 == 200 and isinstance(r0, dict) and bool(r0.get("result"))
        print(f"phase {ph}: status={st0} ok={ok0}")
        if ok0:
            phases[ph] = r0["result"]
    print("phases: " + ", ".join(sorted(phases)) + "（entrypoint 直读，404 表示该 phase 未建）")

    # ---- WAF 托管包：只调已部署 bundle 的执行动作（log/block），不动结构 ----
    waf = want.get("managed_waf") or {}
    if waf.get("enabled"):
        ers = phases.get("http_request_firewall_managed")
        if not ers:
            if waf.get("ruleset_id"):
                print("WAF: phase 缺失但 state 已 pin ruleset_id —— 本版暂不自动首装，请 dashboard 点一次后重跑")
            else:
                print("WAF: 未部署托管包 —— dashboard 一键启用后，dry-run 会打印其 ID 供 pin 回 state")
            return 1
        # entrypoint GET 已是完整定义（含 rules），直接用；写回也用它（LIST 摘要缺字段，回写会丢规则）
        full = ers
        if not isinstance(full.get("rules"), list):
            print("FAIL: WAF phase 详情无 rules")
            return 1
        ers_rules = full["rules"]
        full_rules = [dict(x) for x in ers_rules]
        # entrypoint 内可能有多条；只看引用托管包的 execute 规则
        managed = [x for x in ers_rules if (x.get("action_parameters") or {}).get("id")]
        if not managed and waf.get("ruleset_id"):
            print("WAF: phase 存在但无托管包引用 —— 请检查 dashboard")
            return 1
        print(f"WAF: phase 规则数={len(ers_rules)}")
        for m in managed:
            ap = m.get("action_parameters") or {}
            cur = ((ap.get("overrides") or {}).get("action")) or m.get("action")
            print(f"WAF: bundle={ap.get('id')} version={ap.get('version')} cur={cur} want={waf['action']}")
        if dry:
            print("WAF: dry-run，仅展示不改动")
        else:
            # read-modify-write：只翻 overrides.action（或 rule action），其余原样写回
            new_rules = []
            for x in full_rules:
                ap = dict(x.get("action_parameters") or {})
                if ap.get("id"):
                    ov = dict(ap.get("overrides") or {})
                    ov["action"] = waf["action"]
                    ap["overrides"] = ov
                    x = dict(x)
                    x["action_parameters"] = ap
                new_rules.append(x)
            st2, r2 = api("PUT", f"/zones/{zid}/rulesets/{ers['id']}", {"rules": new_rules})
            if not ok((st2, r2)):
                print(f"FAIL: WAF 更新 status={st2} {json.dumps(r2)[:300]}")
                return 1
            print(f"WAF: action -> {waf['action']} OK")

    # ---- 限流：按 description managed: 前缀认领，全量对账 ----
    want_rl = []
    for rl in want.get("rate_limits") or []:
        want_rl.append({
            "description": "managed:" + rl["name"],
            "expression": rl["expression"],
            "action": rl.get("action", "block"),
            "ratelimit": {
                "characteristics": ["ip.src"],
                "period": int(rl["period"]),
                "requests_per_period": int(rl["requests_per_period"]),
                "mitigation_timeout": int(rl.get("mitigation_timeout", 600)),
                "counting_expression": "",
            },
        })
    ers = phases.get("http_ratelimit")
    live_rules = list((ers or {}).get("rules") or [])
    keep = [x for x in live_rules if not str(x.get("description", "")).startswith("managed:")]
    new_rules = keep + want_rl
    if dry:
        cur = sorted(x.get("description", "") for x in live_rules if str(x.get("description", "")).startswith("managed:"))
        new = sorted(x["description"] for x in want_rl)
        print(f"ratelimit: dry-run cur={cur} want={new} (keep others={len(keep)})")
    else:
        if ers:
            st2, r2 = api("PUT", f"/zones/{zid}/rulesets/{ers['id']}", {"rules": new_rules})
            verb = "update"
        else:
            st2, r2 = api("POST", f"/zones/{zid}/rulesets", {
                "name": "managed edge rate limits",
                "description": "cf/linkseek-edge.json 对账",
                "kind": "zone", "phase": "http_ratelimit", "rules": new_rules})
            verb = "create"
        if not ok((st2, r2)):
            print(f"FAIL: ratelimit {verb} status={st2} {json.dumps(r2)[:400]}")
            return 1
        print(f"ratelimit: {verb} OK ({len(want_rl)} 条)")

    # ---- Bot 开关 ----
    want_bot = bool(want.get("bot_fight_mode", False))
    st3, r3 = api("GET", f"/zones/{zid}/settings/bot_fight_mode")
    cur_bot = (r3.get("result") or {}).get("value") == "on" if isinstance(r3, dict) else None
    print(f"bot_fight_mode: cur={cur_bot} want={want_bot}")
    if cur_bot is not None and cur_bot != want_bot and not dry:
        st4, r4 = api("PATCH", f"/zones/{zid}/settings/bot_fight_mode", {"value": "on" if want_bot else "off"})
        if not ok((st4, r4)):
            print(f"FAIL: bot_fight_mode status={st4}")
            return 1
        print("bot_fight_mode: updated")
    return 0


if __name__ == "__main__":
    sys.exit(main())
