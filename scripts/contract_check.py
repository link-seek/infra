#!/usr/bin/env python3
"""契约校验：infra pin 的 artifact digest 必须存在于 SWR（#317 Phase 1：委托 regctl，匿名）。

不再自研 registry token 流；regctl（regclient）匿名取 manifest 并比对 digest。
"""
import re
import subprocess
import sys

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
    ref = f"{m.group(1)}@{digest}"
    try:
        r = subprocess.run(
            ["regctl", "manifest", "get", ref, "--format", "{{.GetDescriptor.Digest}}"],
            capture_output=True, text=True, timeout=90,
        )
    except Exception as ex:  # noqa: BLE001
        print(f"FAIL: regctl exec: {ex}")
        return 1
    got = (r.stdout or "").strip()
    print(f"pinned={digest}")
    print(f"remote={got or '(none)'}")
    if r.returncode != 0 or got != digest:
        err = (r.stderr or "").strip().splitlines()
        if err:
            print(err[-1][:200])
        print("FAIL: pinned digest not found in registry")
        return 1
    print("CONTRACT-OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
