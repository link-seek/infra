#!/usr/bin/env python3
# scripts/cf-edge-apply.py — linkseek.net.cn 边缘配置声明式对账。
# 用法：STATE_FILE=cf/linkseek-edge.json DRY_RUN=1|0 CF_TOKEN=xxx python3 scripts/cf-edge-apply.py
# 规矩：只动本文件声明的条目（rate limiting 按 description managed: 前缀认领；WAF 只翻已部署托管包的动作位）。
# fail-closed：任何一步不符预期即非零退出；dry-run 只打计划。
# API 形状严格抄 docs（Rulesets API）：拌 entrypoint 用 POST /rulesets/{id}/rules 单条增删改，
# 绝不用全量 PUT 替换（字段稍有出入就 404/丢规则）。
import json
import os
import sys
import urllib.parse
import urllib.request
import urllib.error

BASE = "https://api.cloudflare.com/client/v4"


def api(method, path, body=None):
    headers = {"Authorization": "Bearer " + os.environ["CF_TOKEN"]}
    data = None
    if body is not None:
        headers["Content-Type"] = "application/json"
        data = json.dumps(body).encode()
    req = urllib.request.Request(BASE + path, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            raw = resp.read()
            try:
                return resp.status, json.loads(raw or b"{}")
            except Exception:
                return resp.status, {"_raw": raw[:300]}
    except urllib.error.HTTPError as exc:
        raw = exc.read() or b""
        try:
            return exc.code, json.loads(raw)
        except Exception:
            return exc.code, {"_raw": raw[:300], "_note": "non-JSON body"}
    except Exception as exc:
        return 0, {"success": False, "errors": [{"message": str(exc)[:200]}]}


def ok(resp):
    st, r = resp
    return st in (200, 201) and isinstance(r, dict) and r.get("success", st == 200)


def fail(msg, resp=None):
    print("FAIL: %s" % msg)
    if resp is not None:
        st, r = resp
        print("  status=%s body=%s" % (st, json.dumps(r)[:400] if isinstance(r, dict) else r))
    return 1


def main():
    state_path = os.environ.get("STATE_FILE", "cf/linkseek-edge.json")
    dry = os.environ.get("DRY_RUN", "1").lower() in ("1", "true", "yes", "on")
    want = json.load(open(state_path))
    zone_name = os.environ.get("ZONE_OVERRIDE") or want["zone"]

    st, r = api("GET", "/zones?name=" + urllib.parse.quote(zone_name))
    zones = (r.get("result") or []) if isinstance(r, dict) else []
    if st != 200 or not zones:
        return fail("取 zone 失败", (st, r))
    zid = zones[0]["id"]
    print("zone=%s id=%s%s" % (zone_name, zid, " DRY-RUN" if dry else ""))

    # ---- 盘点：LIST 拿全量（entrypoint GET 行为存疑，不用它；per_page 上限 50，翻页取全） ----
    all_rs = []
    page = 1
    while True:
        st, r = api("GET", "/zones/%s/rulesets?per_page=50&page=%d" % (zid, page))
        if st != 200 or not isinstance(r, dict):
            return fail("列 rulesets 失败", (st, r))
        batch = r.get("result") or []
        all_rs.extend(batch)
        info = r.get("result_info") or {}
        total_pages = info.get("total_pages", 1) or 1
        if page >= total_pages or not batch or page >= 10:
            break
        page += 1
    by_phase = {}
    for rs in all_rs:
        if rs.get("kind") == "zone" and rs.get("phase"):
            by_phase.setdefault(rs["phase"], rs)
    # LIST 摘要的 rules 字段不可信（entrypoint 明细需按 ID 取全量；曾误报 rules=0 导致重复创建）
    for ph in ("http_ratelimit", "http_request_firewall_managed"):
        if ph in by_phase:
            rid = by_phase[ph].get("id")
            st0, r0 = api("GET", "/zones/%s/rulesets/%s" % (zid, rid))
            if st0 == 200 and isinstance(r0, dict) and isinstance((r0.get("result") or {}).get("rules"), list):
                by_phase[ph] = r0["result"]
            else:
                print("WARN: %s 全量拉取失败 status=%s，用 LIST 摘要继续" % (ph, st0))
    print("phases: " + ", ".join(sorted(by_phase)) + "（LIST 定位＋按 ID 取全量核对）")
    for ph, rs in sorted(by_phase.items()):
        print("  phase=%s id=%s rules=%d" % (ph, rs.get("id"), len(rs.get("rules") or [])))

    # ---- 限流：逐条对账（POST 新增 / PUT 改动 / DELETE 移除） ----
    ers = by_phase.get("http_ratelimit")
    live = {x.get("description"): x for x in (ers.get("rules") if ers else []) or [] if x.get("description")}
    want_rules = []
    for x in want.get("rate_limits") or []:
        want_rules.append({
            "description": "managed:" + x["name"],
            "expression": x["expression"],
            "action": x.get("action", "block"),
            "ratelimit": {
                "characteristics": ["cf.colo.id", "ip.src"],
                "period": int(x["period"]),
                "requests_per_period": int(x["requests_per_period"]),
                "mitigation_timeout": int(x.get("mitigation_timeout", 600)),
            },
        })
    want_names = set(x["description"] for x in want_rules)
    live_managed = {k: v for k, v in live.items() if k.startswith("managed:")}

    def _same_rl(old, new):
        if old.get("expression") != new.get("expression"):
            return False, ["expression"]
        if old.get("action") != new.get("action"):
            return False, ["action"]
        ooo = old.get("ratelimit") or {}
        nnn = new.get("ratelimit") or {}
        _diff = [k for k in ("characteristics", "period", "requests_per_period", "mitigation_timeout") if ooo.get(k) != nnn.get(k)]
        return (len(_diff) == 0), _diff

    ops = []
    for w in want_rules:
        cur = live_managed.get(w["description"])
        if not cur:
            ops.append(("create", w["description"], w))
            continue
        same, diff = _same_rl(cur, w)
        if not same:
            ops.append(("update", w["description"], cur, w))
    for k in live_managed:
        if k not in want_names:
            ops.append(("delete", k, live_managed[k].get("id")))
    if dry:
        print("ratelimit: dry-run cur=%s want=%s" % (sorted(live_managed), sorted(want_names)))
        for op in ops:
            print("  would-%s %s" % (op[0], op[1]))
    else:
        if not ers:
            if not want_rules:
                print("ratelimit: 无需 entrypoint（零规则）")
            else:
                st2, r2 = api("POST", "/zones/%s/rulesets" % zid, {
                    "name": "managed edge rate limiting", "kind": "zone",
                    "phase": "http_ratelimit", "rules": want_rules})
                if not ok((st2, r2)):
                    return fail("创建 http_ratelimit entrypoint 失败", (st2, r2))
                print("ratelimit: entrypoint 已创建")
        else:
            eid = ers["id"]
            for op in ops:
                if op[0] == "create":
                    st2, r2 = api("POST", "/zones/%s/rulesets/%s/rules" % (zid, eid), op[2])
                    if not ok((st2, r2)):
                        return fail("创建规则 %s 失败" % op[1], (st2, r2))
                    print("ratelimit: created %s" % op[1])
                elif op[0] == "update":
                    _, name, old, want = op
                    body = dict(old)
                    body.update({"description": want["description"], "expression": want["expression"], "action": want["action"], "ratelimit": want["ratelimit"], "enabled": True})
                    rid = old.get("id")
                    st2, r2 = api("PUT", "/zones/%s/rulesets/%s/rules/%s" % (zid, eid, rid), body)
                    if not ok((st2, r2)):
                        return fail("更新规则 %s 失败" % name, (st2, r2))
                    print("ratelimit: updated %s" % name)
                elif op[0] == "delete":
                    _, name, rid = op
                    st2, r2 = api("DELETE", "/zones/%s/rulesets/%s/rules/%s" % (zid, eid, rid))
                    if not ok((st2, r2)):
                        return fail("删除规则 %s 失败" % name, (st2, r2))
                    print("ratelimit: deleted %s" % name)
        print("ratelimit: OK")

    # ---- WAF 托管包：只翻已部署 bundle 的动作位（log/block），不动结构 ----
    waf = want.get("managed_waf") or {}
    if waf.get("enabled"):
        ers = by_phase.get("http_request_firewall_managed")
        if not ers:
            print("WAF: phase 缺失 —— dashboard 一键启用托管包后重跑 dry-run")
            return 0 if dry else 1
        managed = [x for x in (ers.get("rules") or []) if (x.get("action_parameters") or {}).get("id")]
        if not managed:
            print("WAF: phase 存在但无托管包引用 —— dashboard 一键启用托管包后重跑 dry-run")
            return 0 if dry else 1
        for m in managed:
            ap = m.get("action_parameters") or {}
            cur = (ap.get("overrides") or {}).get("action") or m.get("action")
            print("WAF: bundle=%s version=%s cur=%s want=%s" % (ap.get("id"), ap.get("version"), cur, waf["action"]))
        if dry:
            print("WAF: dry-run，仅展示不改动")
        else:
            eid = ers["id"]
            for m in managed:
                ap = dict(m.get("action_parameters") or {})
                ov = dict(ap.get("overrides") or {})
                if ov.get("action") == waf["action"]:
                    print("WAF: %s 已是 %s，跳过" % (ap.get("id"), waf["action"]))
                    continue
                ov["action"] = waf["action"]
                body = {"action": m.get("action", "execute"), "action_parameters": dict(ap, overrides=ov),
                        "expression": m.get("expression", "true"), "description": m.get("description", ""),
                        "enabled": m.get("enabled", True)}
                st2, r2 = api("PUT", "/zones/%s/rulesets/%s/rules/%s" % (zid, eid, m.get("id")), body)
                if not ok((st2, r2)):
                    return fail("WAF 切换 action 失败", (st2, r2))
                print("WAF: action -> %s OK" % waf["action"])
    print("DONE")
    return 0


if __name__ == "__main__":
    sys.exit(main())
