#!/usr/bin/env python3
# scripts/k3s-team-probe.py — tailnet 入口探针主体，跑在 .69（常驻节点，全量 netmap）。
# 背景：ephemeral runner（tag:user）看不见 tag:k8s 的 operator 代理设备（netmap 按 grant 裁剪），
# 而 .69 能看见（实测同簇：opencode-team/ha-a/ha-b 均在列）。探针主体必须跑在看得见的地方。
# 调用：echo <b64> | base64 -d | python3 - <namespace>
# 输出：IP=<tailnet ip|空> / HTTP=<200|ERR:xxx> 两行，调用方判。
#  regeneration：本文件即正本，workflow 内 `base64 -w0` 现场编码，不手写 b64。
import json
import subprocess
import sys
import urllib.request

NS = sys.argv[1] if len(sys.argv) > 1 else "opencode-team"
HOST_WANT = {"opencode-team": "opencode-team"}.get(NS, NS)

out = subprocess.run(["tailscale", "status", "--json"], capture_output=True, text=True)
try:
    peers = json.loads(out.stdout).get("Peer") or {}
except Exception:
    peers = {}
ip = next(
    (
        p["TailscaleIPs"][0]
        for p in peers.values()
        if HOST_WANT in str(p.get("DNSName", ""))
        or HOST_WANT in str(p.get("HostName", ""))
    ),
    "",
)
print("IP=" + ip)
code = ""
if ip:
    try:
        code = str(urllib.request.urlopen("http://%s:4097/" % ip, timeout=15).getcode())
    except Exception as e:
        code = "ERR:" + type(e).__name__
print("HTTP=" + code)
