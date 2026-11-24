#!/usr/bin/env python3
"""清理 ci-* 临时 tag：每个仓库只保留最近的 N 个（默认 3）。

ci-* 是 bake 的一次性产物，永远不被部署；版本 tag 由 SWR 老化规则管理。
默认 dry-run，--apply 才删除。
"""
import argparse
import json
import subprocess
import sys

import yaml

CFG = "ops/swr-retention.yaml"
REG = "swr.cn-north-9.myhuaweicloud.com"


def list_tags(repo: str):
    out = subprocess.run(
        ["skopeo", "list-tags", f"docker://{REG}/{repo}"],
        capture_output=True, text=True, timeout=60, check=True,
    ).stdout
    return [t for t in json.loads(out).get("Tags") or [] if t]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--keep", type=int, default=3)
    ap.add_argument("--apply", action="store_true")
    args = ap.parse_args()
    cfg = yaml.safe_load(open(CFG, encoding="utf-8"))
    total = 0
    for item in cfg["repos"]:
        repo = item["name"]
        try:
            tags = list_tags(repo)
        except Exception as e:  # noqa: BLE001
            print(f"{repo}: LIST-FAIL {str(e)[:80]}")
            continue
        ci = sorted(t for t in tags if t.startswith("ci-"))
        doomed = ci[:-args.keep] if len(ci) > args.keep else []
        print(f"{repo}: ci={len(ci)} keep={args.keep} -> delete={len(doomed)}")
        for tag in doomed:
            if not args.apply:
                continue
            r = subprocess.run(
                ["skopeo", "delete", f"docker://{REG}/{repo}:{tag}"],
                capture_output=True, text=True, timeout=60,
            )
            if r.returncode == 0:
                total += 1
                print(f"  deleted {tag}")
            else:
                print(f"  FAIL {tag}: {r.stderr.strip()[:120]}")
    print(f"{'DELETED' if args.apply else 'DRY-RUN'} ci tags: {total}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
