#!/usr/bin/env python3
"""契约校验：infra pin 的 artifact digest 必须存在于 SWR，且来自 **main 绿构建**。

#317 item6/8：
  1) 制品 digest 必须真实存在（regctl 匿名取）；
  2) 其 `org.opencontainers.image.revision` 必须是 `main@sha1:<40hex>`
     —— 即 flux-artifact 在 main push（绿）时推的正式制品，而非分支/临时构建。
"""
import json
import re
import subprocess
import sys

FILE = "clusters/k3s/git-docker-images.yaml"
REV_RE = re.compile(r"^main@sha1:[0-9a-f]{40}$")


def regctl(*args):
    return subprocess.run(["regctl", *args], capture_output=True, text=True, timeout=90)


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
    ref = f"{m.group(1)}@{digest}"

    r = regctl("manifest", "get", ref, "--format", "{{.GetDescriptor.Digest}}")
    got = (r.stdout or "").strip()
    print(f"pinned={digest}")
    print(f"remote={got or '(none)'}")
    if r.returncode != 0 or got != digest:
        err = (r.stderr or "").strip().splitlines()
        if err:
            print(err[-1][:200])
        print("FAIL: pinned digest not found in registry")
        return 1

    # 只认 main 绿构建：制品 annotations 里的 revision 必须是 main@sha1:<sha>
    r2 = regctl("manifest", "get", ref, "--format", "{{json .}}")
    if r2.returncode != 0:
        print("FAIL: 读取制品 manifest 失败（无法校验 revision）")
        return 1
    try:
        doc = json.loads(r2.stdout)
    except Exception as e:  # noqa: BLE001
        print(f"FAIL: manifest JSON 解析失败: {e}")
        return 1
    ann = doc.get("annotations") or doc.get("Annotations") or {}
    rev = ann.get("org.opencontainers.image.revision", "")
    if not REV_RE.match(rev):
        print(f"FAIL: 制品 revision 非 main 绿构建: '{rev}'（须 main@sha1:<40hex>）")
        return 1
    print(f"REVISION OK: {rev}")
    print("CONTRACT-OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
