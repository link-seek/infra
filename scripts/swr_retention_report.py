#!/usr/bin/env python3
"""SWR 版本保留报告（只读）：列出各仓库 tag 数，超过 keep 则 WARN。

不删除任何东西；删除请在 SWR 控制台配“镜像老化规则”，并先确认
infra pin 的 digest / manifest 里引用的 digest 不在清理范围内。
"""
import subprocess
import sys

import yaml

CFG = "ops/swr-retention.yaml"


def main() -> int:
    cfg = yaml.safe_load(open(CFG, encoding="utf-8"))
    reg = cfg["registry"]
    warn = 0
    print(f"{'REPO':<48}{'TAGS':>6}{'KEEP':>6}  STATE")
    for item in cfg["repos"]:
        name, keep = item["name"], int(item["keep"])
        try:
            out = subprocess.run(
                ["skopeo", "list-tags", f"docker://{reg}/{name}"],
                capture_output=True, text=True, timeout=60, check=True,
            ).stdout
            import json
            tags = json.loads(out).get("Tags") or []
        except Exception as e:  # noqa: BLE001
            print(f"{name:<48}{'ERR':>6}{keep:>6}  {str(e)[:60]}")
            warn += 1
            continue
        n = len(tags)
        state = "OK" if n <= keep else "WARN"
        if state == "WARN":
            warn += 1
            extra = sorted(tags)[:0]
        else:
            extra = []
        print(f"{name:<48}{n:>6}{keep:>6}  {state}")
        if extra:
            print("    candidates:", ", ".join(extra[:5]))
    print(f"\nSUMMARY: {warn} repo(s) over threshold or unreadable")
    return 0  # 报告不红；要门禁再看 --strict


if __name__ == "__main__":
    sys.exit(main())
