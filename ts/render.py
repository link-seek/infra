#!/usr/bin/env python3
"""render.py — ts 声明式配置的纯逻辑部分（无网络，全部走文件/stdin，便于本地测）。

子命令：
  render <tmpl> <hostname>   渲染 daemon 模板，authKey 只从 env TS_AUTH_KEY 取（永不走 argv/日志）
  check-devices <devices.yaml>  从 stdin 读在线设备 JSON（ts-acl-apply verify 的 /tmp/dev.json 格式），
                                与 devices.yaml static 段核对 hostname/tags/routes，漂移即 exit 1
"""
import json
import os
import sys


def cmd_render(tmpl, hostname):
    key = os.environ.get("TS_AUTH_KEY", "").strip()
    if not key:
        sys.exit("render: TS_AUTH_KEY 为空（authKey 永不进仓，只走 env 现填）")
    if not hostname:
        sys.exit("render: hostname 为空")
    s = open(tmpl, encoding="utf-8").read()
    if "__TS_AUTHKEY__" not in s or "__TS_HOSTNAME__" not in s:
        sys.exit("render: 模板缺占位符 __TS_AUTHKEY__ / __TS_HOSTNAME__")
    out = s.replace("__TS_AUTHKEY__", key).replace("__TS_HOSTNAME__", hostname)
    cfg = json.loads(out)  # 非法 JSON 即红
    assert cfg.get("version") == "alpha0", "version 必须为 alpha0"
    assert cfg.get("authKey") == key and cfg.get("hostname") == hostname
    print(out, end="" if out.endswith("\n") else "\n")


def load_yaml_min(path):
    """极简 YAML 子集解析（只够读 devices.yaml 的 static/ci_conventions 结构，避免依赖 pyyaml）。"""
    import re
    text = open(path, encoding="utf-8").read()
    # 去掉整行注释
    text = re.sub(r"(?m)^\s*#.*$", "", text)
    ci, static = {}, []
    cur = None
    in_static = False
    for line in text.splitlines():
        if re.match(r"^ci_conventions:\s*$", line):
            in_static = False
            continue
        if re.match(r"^static:\s*$", line):
            in_static = True
            continue
        if re.match(r"^[a-z_]+:\s*$", line):
            in_static = False
            continue
        m = re.match(r"^\s{2}([a-z_]+):\s*(.+?)\s*$", line)
        if m and not in_static:
            k, v = m.group(1), m.group(2)
            try:
                ci[k] = json.loads(v)
            except Exception:
                ci[k] = v.strip('"')
            continue
        m = re.match(r"^\s*-\s*hostname:\s*(\S+)\s*$", line)
        if m:
            cur = {"hostname": m.group(1)}
            static.append(cur)
            continue
        m = re.match(r"^\s{4}([a-z_]+):\s*(.+?)\s*$", line)
        if m and cur is not None and in_static:
            k, v = m.group(1), m.group(2)
            try:
                cur[k] = json.loads(v)
            except Exception:
                cur[k] = v.strip('"')
    return ci, static


def cmd_check_devices(devices_yaml):
    ci, static = load_yaml_min(devices_yaml)
    live = json.load(sys.stdin).get("devices") or []
    by_host = {d.get("hostname"): d for d in live if isinstance(d, dict)}
    fail = 0
    for want in static:
        h = want["hostname"]
        got = by_host.get(h)
        if got is None:
            print(f"MISSING: {h} 控制台无此设备")
            fail = 1
            continue
        tags = sorted(got.get("tags") or [])
        routes = sorted(got.get("enabledRoutes") or [])
        ok = sorted(want.get("tags") or []) == tags and sorted(want.get("routes") or []) == routes
        mark = "OK " if ok else "DRIFT"
        if not ok:
            fail = 1
        print(f"{mark}: {h} tags={tags} routes={routes}"
              + ("" if ok else f"（期望 tags={sorted(want.get('tags') or [])} routes={sorted(want.get('routes') or [])}）")
              + (" [unverified]" if not want.get("verified") else ""))
    print("DEVICES-OK" if fail == 0 else "DEVICES-DRIFT")
    sys.exit(fail)


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    cmd = sys.argv[1]
    if cmd == "render":
        if len(sys.argv) != 4:
            sys.exit("用法: render.py render <tmpl> <hostname>  # TS_AUTH_KEY 走 env")
        cmd_render(sys.argv[2], sys.argv[3])
    elif cmd == "check-devices":
        if len(sys.argv) != 3:
            sys.exit("用法: render.py check-devices <devices.yaml>  # 设备 JSON 走 stdin")
        cmd_check_devices(sys.argv[2])
    else:
        sys.exit(f"未知子命令: {cmd}\n{__doc__}")


if __name__ == "__main__":
    main()
