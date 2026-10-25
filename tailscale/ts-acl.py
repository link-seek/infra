#!/usr/bin/env python3
"""ts-acl.py — ACL 下发工具的纯逻辑部分（无网络，全部走 stdin/文件，便于本地测）。

子命令：
  norm <file>               打印规范化 JSON（容忍整行 // 注释与尾逗号），用于比对
  device-id <hostname>      从 stdin 的设备 JSON 里取唯一匹配的 id
  devices-table             从 stdin 的设备 JSON 里打印 hostname/ip/tags/online
  tags-json <csv>           打印 {"tags": [...]}
  change-summary <a> <b>    打印 grants/ssh/tests 数量变化与 tagOwners
"""
import json
import re
import sys


def load_lenient(path_or_text, is_text=False):
    s = path_or_text if is_text else open(path_or_text, encoding="utf-8").read()
    try:
        return json.loads(s)
    except json.JSONDecodeError:
        s = re.sub(r"^\s*//.*$", "", s, flags=re.M)   # 整行注释
        s = re.sub(r"^\s*#.*$", "", s, flags=re.M)    # 整行 # 注释（HuJSON 也吃）
        s = re.sub(r",(\s*[}\]])", r"\1", s)          # 尾逗号
        return json.loads(s)


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    cmd = sys.argv[1]

    if cmd == "norm":
        print(json.dumps(load_lenient(sys.argv[2]), sort_keys=True, indent=1))

    elif cmd == "device-id":
        host = sys.argv[2]
        devs = json.load(sys.stdin).get("devices", [])
        hit = [d for d in devs if d.get("hostname") == host]
        if len(hit) != 1:
            sys.exit(f"device-id: hostname={host} 匹配到 {len(hit)} 台（要求唯一）")
        print(hit[0]["id"])

    elif cmd == "devices-table":
        for d in json.load(sys.stdin).get("devices", []):
            print(
                "%-24s %-20s tags=%-24s online=%s"
                % (
                    d.get("hostname", "?"),
                    ",".join(d.get("addresses") or []) or "-",
                    ",".join(d.get("tags") or []) or "-",
                    bool(d.get("connectedToControl")),
                )
            )

    elif cmd == "tags-json":
        tags = [t.strip() for t in sys.argv[2].split(",") if t.strip()]
        print(json.dumps({"tags": tags}))

    elif cmd == "change-summary":
        a = load_lenient(sys.argv[2])
        b = load_lenient(sys.argv[3])
        for k in ("grants", "ssh", "tests"):
            print("%s: %d -> %d" % (k, len(a.get(k, [])), len(b.get(k, []))))
        print("tagOwners:", sorted(b.get("tagOwners", {})))

    else:
        sys.exit(f"未知子命令: {cmd}\n{__doc__}")


if __name__ == "__main__":
    main()
