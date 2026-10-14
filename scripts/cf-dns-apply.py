#!/usr/bin/env python3
"""Cloudflare DNS 对账：按 dns/records.json 声明收敛。

规则：
- state=present：不存在则创建；存在但 content/ttl/proxied 不一致则更新。
- state=absent：存在则删除，删前必须 content 完全一致，否则中止该条。
- 未在文件里声明的记录一律不动（不剪枝）。
- 只打记录名和动作，不打 token。

环境变量：CF_TOKEN（必填）、RECORDS_FILE（默认 dns/records.json）、
DRY_RUN=1 时只打印计划不执行。
"""
import json
import os
import sys
import urllib.request

API = "https://api.cloudflare.com/client/v4"


def api(method, path, body=None):
    token = os.environ["CF_TOKEN"]
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(API + path, data=data, method=method, headers={
        "Authorization": "Bearer " + token,
        "Content-Type": "application/json",
    })
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            return json.load(r)
    except Exception as e:  # noqa: BLE001 - 对账脚本：API 错误直接打印原文
        print("API-ERROR " + method + " " + path + " :: " + str(e)[:200])
        raise SystemExit(1)


def main():
    dry = os.environ.get("DRY_RUN", "") == "1"
    with open(os.environ.get("RECORDS_FILE", "dns/records.json"), encoding="utf-8") as f:
        want = json.load(f)
    zone_name = want["zone"]
    zr = api("GET", "/zones?name=" + zone_name)
    if not zr.get("success") or not zr.get("result"):
        print("ZONE-NOT-FOUND " + zone_name)
        raise SystemExit(1)
    zid = zr["result"][0]["id"]
    print("zone=" + zone_name + " id=" + zid + (" DRY-RUN" if dry else ""))

    got = api("GET", "/zones/" + zid + "/dns_records?per_page=100")
    live = {(r["name"], r["type"]): r for r in got.get("result", [])}

    changed = 0
    # 两遍：先删（absent），再建/改。Cloudflare 同名只容一种类型，
    # 若先建 A 会因旧 CNAME 未删报 400。
    ordered = sorted(want["records"], key=lambda r: 0 if r.get("state") == "absent" else 1)
    for rec in ordered:
        key = (rec["name"], rec["type"])
        state = rec.get("state", "present")
        cur = live.get(key)
        if state == "absent":
            if cur is None:
                print("already-absent " + rec["name"] + " " + rec["type"])
                continue
            if cur["content"] != rec.get("content"):
                print("REFUSE-DELETE content-mismatch " + rec["name"]
                      + " live=" + cur["content"][:40])
                raise SystemExit(1)
            print(("would-delete " if dry else "delete ") + cur["id"] + " " + rec["name"])
            if not dry:
                api("DELETE", "/zones/" + zid + "/dns_records/" + cur["id"])
            changed += 1
            continue
        body = {"type": rec["type"], "name": rec["name"],
                "content": rec["content"], "ttl": rec.get("ttl", 600),
                "proxied": rec.get("proxied", False)}
        if cur is None:
            print(("would-create " if dry else "create ") + rec["name"] + " " + rec["type"]
                  + " -> " + rec["content"])
            if not dry:
                api("POST", "/zones/" + zid + "/dns_records", body)
            changed += 1
        elif (cur["content"] != body["content"] or cur.get("ttl") != body["ttl"]
                or cur.get("proxied") != body["proxied"]):
            print(("would-update " if dry else "update ") + cur["id"] + " " + rec["name"]
                  + " " + cur["content"][:40] + " -> " + body["content"])
            if not dry:
                api("PUT", "/zones/" + zid + "/dns_records/" + cur["id"], body)
            changed += 1
        else:
            print("in-sync " + rec["name"] + " " + rec["type"])
    print("done changed=" + str(changed))


main()
