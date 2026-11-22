#!/usr/bin/env python3
"""安全清理"已合并 PR"对应的远端分支（squash 友好）。

规则（保守）：
- 跳过默认分支；跳过任何 open PR 的 head 分支。
- 仅删除：存在 merged PR，且分支当前 tip sha == 该 PR 合并时的 head sha。
  （tip 有额外提交的、或找不到 merged PR 的，一律保留，避免误删未收尾工作。）
用法：REPO=owner/name APPLY=1 python3 scripts/prune-merged-branches.py
"""
import os, json, subprocess

REPO = os.environ["REPO"]
APPLY = os.environ.get("APPLY", "0") == "1"
GH = os.environ.get("GH_BIN", "gh")

def api(path):
    r = subprocess.run([GH, "api", path], capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(r.stderr[:300])
    return json.loads(r.stdout or "null")

def pages(path):
    out, p = [], 1
    while True:
        sep = "&" if "?" in path else "?"
        d = api(f"{path}{sep}per_page=100&page={p}")
        if not d:
            break
        out += d
        if len(d) < 100:
            break
        p += 1
        if p > 80:
            break
    return out

def main():
    branches = [(b["name"], b["commit"]["sha"]) for b in pages(f"repos/{REPO}/branches")]
    default = api(f"repos/{REPO}")["default_branch"]
    merged = {}
    for pr in pages(f"repos/{REPO}/pulls?state=closed"):
        if pr.get("merged_at"):
            merged.setdefault(pr["head"]["ref"], set()).add(pr["head"]["sha"])
    openheads = {pr["head"]["ref"] for pr in pages(f"repos/{REPO}/pulls?state=open")}
    deletable = [n for n, s in branches
                 if n != default and n not in openheads and n in merged and s in merged[n]]
    print(f"repo={REPO} branches={len(branches)} default={default} deletable={len(deletable)} apply={APPLY}")
    if not APPLY:
        for n in deletable:
            print("would-delete", n)
        return
    ok, fail = 0, []
    for n in deletable:
        r = subprocess.run([GH, "api", "-X", "DELETE", f"repos/{REPO}/git/refs/heads/{n}"],
                           capture_output=True, text=True)
        err = (r.stderr or r.stdout)
        if r.returncode == 0 or "does not exist" in err:
            ok += 1
        else:
            fail.append((n, err.strip()[:120]))
    print(f"deleted={ok} failed={len(fail)}")
    for n, e in fail:
        print("FAIL", n, e)

if __name__ == "__main__":
    main()
