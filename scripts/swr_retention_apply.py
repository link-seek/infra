#!/usr/bin/env python3
"""把 ops/swr-retention.yaml 的保留策略写到 SWR（CreateRetention/UpdateRetention）。

默认 dry-run；--apply 才真正写。规则类型 tag_rule（保留版本数），
可用 tag_selectors 保护 latest/stable/指定 tag。
"""
import argparse
import datetime
import hashlib
import hmac
import json
import os
import sys
import urllib.error
import urllib.request

import yaml

CFG = "ops/swr-retention.yaml"
HOST = "swr-api.cn-north-9.myhuaweicloud.com"
DEFAULT_PROTECT = ["latest", "stable"]


def sign(method, path, body=b""):
    ak = os.environ["PROD_HCLOUD_AK"].strip()
    sk = os.environ["PROD_HCLOUD_SK"].strip()
    now = datetime.datetime.now(datetime.UTC).strftime("%Y%m%dT%H%M%SZ")
    ph = hashlib.sha256(body).hexdigest()
    ch = f"host:{HOST}\nx-sdk-date:{now}\n"
    sh = "host;x-sdk-date"
    cr = f"{method}\n{path}/\n\n{ch}\n{sh}\n{ph}"
    sts = f"SDK-HMAC-SHA256\n{now}\n{hashlib.sha256(cr.encode()).hexdigest()}"
    sig = hmac.new(sk.encode(), sts.encode(), hashlib.sha256).hexdigest()
    return {
        "Host": HOST,
        "X-Sdk-Date": now,
        "Content-Type": "application/json",
        "Authorization": f"SDK-HMAC-SHA256 Access={ak}, SignedHeaders={sh}, Signature={sig}",
    }


def call(method, path, payload=None):
    body = json.dumps(payload).encode() if payload is not None else b""
    req = urllib.request.Request(
        "https://" + HOST + path, data=body or None, method=method, headers=sign(method, path, body)
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            raw = r.read()
            return r.status, (json.loads(raw) if raw else None)
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", "replace")[:300]


def desired(keep, protect):
    return {
        "algorithm": "or",
        "rules": [
            {
                "template": "tag_rule",
                "params": {"num": str(int(keep))},
                "tag_selectors": [{"kind": "label", "pattern": p} for p in protect],
            }
        ],
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    args = ap.parse_args()
    cfg = yaml.safe_load(open(CFG, encoding="utf-8"))
    for item in cfg["repos"]:
        name = item["name"]
        ns, repo = name.split("/", 1)
        protect = DEFAULT_PROTECT + list(item.get("protect") or [])
        body = desired(item["keep"], protect)
        base = f"/v2/manage/namespaces/{ns}/repos/{repo}/retentions"
        code, data = call("GET", base)
        if code != 200:
            print(f"{name}: LIST HTTP {code} {data}")
            continue
        rules = data if isinstance(data, list) else (data or {}).get("retentions") or []
        rid = rules[0].get("id") if rules else None
        action = "update" if rid else "create"
        print(f"{name}: keep={item['keep']} protect={protect} -> {action}")
        if not args.apply:
            continue
        if rid:
            code, data = call("PATCH", f"{base}/{rid}", body)
            if code not in (200, 201):
                # 已有规则模板不同（如 date_rule）无法修改，删掉重建
                dcode, ddata = call("DELETE", f"{base}/{rid}")
                print(f"  delete old rule: HTTP {dcode} {'' if dcode in (200, 204) else ddata}")
                code, data = call("POST", base, body)
        else:
            code, data = call("POST", base, body)
        print(f"  {action}: HTTP {code} {'' if code in (200, 201) else data}")
    print("APPLIED" if args.apply else "DRY-RUN (use --apply)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
