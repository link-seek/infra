#!/usr/bin/env python3
"""契约校验：infra pin 的 artifact digest 必须存在于 SWR（匿名 token 流程）。"""
import json
import re
import sys
import urllib.parse
import urllib.request

FILE = "clusters/k3s/git-docker-images.yaml"


def main() -> int:
    text = open(FILE, encoding="utf-8").read()
    m = re.search(r"url:\s*oci://(\S+)", text)
    d = re.search(r"digest:\s*(sha256:[0-9a-f]{64})", text)
    if not m:
        print("FAIL: no oci url")
        return 1
    if not d:
        print("FAIL: no digest pinned (ref.digest required)")
        return 1
    digest = d.group(1)
    host, repo = m.group(1).split("/", 1)

    q = urllib.parse.urlencode({"scope": f"repository:{repo}:pull", "service": "dockyard"})
    with urllib.request.urlopen(f"https://{host}/swr/auth/v2/registry/auth/?{q}", timeout=30) as r:
        token = json.load(r)["token"]

    req = urllib.request.Request(
        f"https://{host}/v2/{repo}/manifests/{digest}",
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/vnd.oci.image.manifest.v1+json",
        },
    )
    with urllib.request.urlopen(req, timeout=30) as r:
        got = r.headers.get("Docker-Content-Digest")

    print(f"pinned={digest}")
    print(f"remote={got}")
    if got != digest:
        print("FAIL: pinned digest not found in registry")
        return 1
    print("CONTRACT-OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
