#!/usr/bin/env python3
"""#317 item10：两仓 `k8s/<name>` 不得同名（部署清单真相源唯一）。

对比 infra 本地 `k8s/*` 与 `link-seek/docker-images` 的 `k8s/*`；出现同名目录即 red。
（注：存储分层/备份、NFS export 收敛已按决策移出治理案，归 NFS/存储单列，不在本检查内。）
"""
import json
import os
import pathlib
import subprocess
import sys
import urllib.request

REMOTE = "link-seek/docker-images"


def gh_token():
    tok = (os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN") or "").strip()
    if tok:
        return tok
    return subprocess.check_output(["gh", "auth", "token"], text=True).strip()


def remote_dirs():
    req = urllib.request.Request(
        f"https://api.github.com/repos/{REMOTE}/contents/k8s",
        headers={"Authorization": "Bearer " + gh_token(),
                 "Accept": "application/vnd.github+json"},
    )
    with urllib.request.urlopen(req, timeout=30) as r:
        return {e["name"] for e in json.load(r) if e.get("type") == "dir"}


def main() -> int:
    local = {p.name for p in pathlib.Path("k8s").iterdir()
             if p.is_dir() and not p.name.startswith("_")}
    try:
        remote = remote_dirs()
    except Exception as e:  # noqa: BLE001
        print(f"FAIL: 读取 {REMOTE}/k8s 失败: {e}")
        return 1
    dup = sorted(local & remote)
    print("infra k8s:", sorted(local))
    print("docker-images k8s:", sorted(remote))
    if dup:
        print("DUPLICATE k8s dirs (must live in exactly one repo):", dup)
        return 1
    print("K8S-DEDUP-OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
