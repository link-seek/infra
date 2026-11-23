#!/usr/bin/env python3
"""若 SWR 上的 latest artifact 比 infra pin 新，则开一个 draft PR 更新 pin。

只做“提议”，不合并：合并仍需人工（branch protection required approval）。
"""
import json
import os
import re
import subprocess
import sys
import urllib.parse
import urllib.request

FILE = "clusters/k3s/git-docker-images.yaml"


def sh(*args, **kw):
    return subprocess.run(args, check=True, text=True, capture_output=True, **kw).stdout.strip()


def latest_digest(url: str) -> str:
    host, repo = url.split("/", 1)
    q = urllib.parse.urlencode({"scope": f"repository:{repo}:pull", "service": "dockyard"})
    with urllib.request.urlopen(f"https://{host}/swr/auth/v2/registry/auth/?{q}", timeout=30) as r:
        tok = json.load(r)["token"]
    req = urllib.request.Request(
        f"https://{host}/v2/{repo}/manifests/latest",
        headers={"Authorization": f"Bearer {tok}", "Accept": "application/vnd.oci.image.manifest.v1+json"},
    )
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.headers["Docker-Content-Digest"]


def main() -> int:
    text = open(FILE, encoding="utf-8").read()
    url = re.search(r"url:\s*oci://(\S+)", text).group(1)
    cur = re.search(r"digest:\s*(sha256:[0-9a-f]{64})", text).group(1)
    new = latest_digest(url)
    if new == cur:
        print("up to date:", cur)
        return 0

    short = new.split(":", 1)[1][:12]
    branch = f"chore/release-{short}"
    existing = sh("gh", "pr", "list", "--head", branch, "--state", "open", "--json", "number")
    if json.loads(existing):
        print("PR already open for", branch)
        return 0

    sh("git", "config", "user.name", "release-bot")
    sh("git", "config", "user.email", "release-bot@users.noreply.github.com")
    sh("git", "checkout", "-b", branch)
    updated = re.sub(r"digest:\s*sha256:[0-9a-f]{64}", f"digest: {new}", text, count=1)
    updated = re.sub(r"# release: .*", f"# release: auto-{short}", updated, count=1)
    open(FILE, "w", encoding="utf-8").write(updated)
    sh("git", "commit", "-am", f"chore(release): bump docker-images artifact to {new}")
    sh("git", "push", "-u", "origin", branch)
    sh(
        "gh", "pr", "create", "--draft", "--base", "main", "--head", branch,
        "--title", f"chore(release): bump artifact {short}",
        "--body",
        f"自动提议：把 `docker-images` artifact 从 `{cur}` 升到 `{new}`。\n\n"
        "合并前请确认 docker-images 的变更内容；合并后 Flux 5 分钟内对账。\n"
        "回滚：把 digest 改回上一条。",
    )
    print("opened PR for", branch)
    return 0


if __name__ == "__main__":
    sys.exit(main())
