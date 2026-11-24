#!/usr/bin/env python3
"""若 SWR 上最新的**不可变 tag**（vYYYY.MM.DD-<sha7>，且制品 revision 为 main 绿构建）比 infra pin 新，
则开 draft PR。

#317 item6/8：不再读可变 `latest`；只认 `flux-artifact` 在 main push（绿）推的不可变 tag
（只有绿构建才 push；工作流强制 tag→digest 不可变；annotations.revision=main@sha1:<sha>）。
"""
import json
import re
import subprocess
import sys
import urllib.parse
import urllib.request

FILE = "clusters/k3s/git-docker-images.yaml"
TAG_RE = re.compile(r"^v\d{4}\.\d{2}\.\d{2}-[0-9a-f]{7}$")
REV_RE = re.compile(r"^main@sha1:[0-9a-f]{40}$")


def sh(*args):
    return subprocess.run(args, check=True, text=True, capture_output=True).stdout.strip()


def token(host, repo):
    q = urllib.parse.urlencode({"scope": f"repository:{repo}:pull", "service": "dockyard"})
    with urllib.request.urlopen(f"https://{host}/swr/auth/v2/registry/auth/?{q}", timeout=30) as r:
        return json.load(r)["token"]


def fetch(host, repo, path, tok, accept):
    req = urllib.request.Request(
        f"https://{host}/v2/{repo}/{path}",
        headers={"Authorization": f"Bearer {tok}", "Accept": accept},
    )
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.headers.get("Docker-Content-Digest"), r.read()


def newest_official(host, repo, tok, tags):
    """从新到旧找第一个 revision 为 main@sha1 的不可变 tag。"""
    for t in reversed(tags[-40:]):
        dig, body = fetch(host, repo, f"manifests/{t}", tok,
                          "application/vnd.oci.image.manifest.v1+json")
        try:
            ann = json.loads(body).get("annotations") or {}
        except Exception:  # noqa: BLE001
            ann = {}
        rev = ann.get("org.opencontainers.image.revision", "")
        if dig and REV_RE.match(rev):
            return t, dig, rev
        print(f"skip {t}: revision='{rev}' 非 main 绿构建")
    return None, None, None


def main() -> int:
    text = open(FILE, encoding="utf-8").read()
    url = re.search(r"url:\s*oci://(\S+)", text).group(1)
    cur = re.search(r"digest:\s*(sha256:[0-9a-f]{64})", text).group(1)
    host, repo = url.split("/", 1)

    tok = token(host, repo)
    _, body = fetch(host, repo, "tags/list", tok, "application/json")
    tags = sorted(t for t in (json.loads(body).get("tags") or []) if TAG_RE.match(t))
    if not tags:
        print("FAIL: no immutable v* tags found")
        return 1

    newest, new, rev = newest_official(host, repo, tok, tags)
    if not newest:
        print("FAIL: no main-green immutable artifact found")
        return 1
    print(f"newest official: {newest} ({rev}) -> {new}")
    if new == cur:
        print("up to date:", cur)
        return 0

    branch = f"chore/release-{newest}"
    existing = json.loads(sh("gh", "pr", "list", "--head", branch, "--state", "open", "--json", "number") or "[]")
    if existing:
        print("PR already open for", branch)
        return 0

    sh("git", "config", "user.name", "release-bot")
    sh("git", "config", "user.email", "release-bot@users.noreply.github.com")
    sh("git", "checkout", "-b", branch)
    updated = re.sub(r"digest:\s*sha256:[0-9a-f]{64}", f"digest: {new}", text, count=1)
    updated = re.sub(r"# release: .*", f"# release: {newest}", updated, count=1)
    open(FILE, "w", encoding="utf-8").write(updated)
    sh("git", "commit", "-am", f"chore(release): bump docker-images artifact to {newest}")
    sh("git", "push", "-u", "origin", branch)
    sh("gh", "pr", "create", "--draft", "--base", "main", "--head", branch,
       "--title", f"chore(release): bump artifact {newest}",
       "--body",
       f"自动提议：docker-images 制品按**不可变 tag** `{newest}` 升到 `{new}`（旧 `{cur}`）。\n\n"
       f"- revision: `{rev}`（main 绿构建才 push）\n"
       "- 只认不可变 tag，不用可变 `latest`；合并后 Flux 5 分钟内对账。")
    print("opened PR for", branch)
    return 0


if __name__ == "__main__":
    sys.exit(main())
