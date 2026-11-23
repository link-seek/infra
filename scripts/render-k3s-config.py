#!/usr/bin/env python3
"""渲染 k3s server 的 config.yaml（声明式）。

输入（单一真相）：
  - node/k3s-cluster.yaml  集群级 settings + api_server + cluster_init_node
  - node/node-config.yaml  每节点 node-ip / node-external-ip / flannel-iface
  - node/k3s-version       版本（本渲染器不写进 config.yaml，供安装/升级读取）

输出：每台 role=server 的 config.yaml（dict，token 不包含，由 apply 时从目标机就地保留）。

用法：
  python3 scripts/render-k3s-config.py --list
  python3 scripts/render-k3s-config.py --host mesh-hw-21            # 打印 YAML
  python3 scripts/render-k3s-config.py --host mesh-hw-21 --json     # 打印 JSON（apply 用）
"""
import argparse, json, sys, yaml

CLUSTER = "node/k3s-cluster.yaml"
NODECFG = "node/node-config.yaml"


def load():
    cluster = yaml.safe_load(open(CLUSTER))
    nodecfg = yaml.safe_load(open(NODECFG))
    try:
        version = open(cluster["version_file"]).read().strip()
    except Exception as e:
        sys.exit(f"FAIL: 读不到 version_file {cluster.get('version_file')}: {e}")
    if not version:
        sys.exit("FAIL: version_file 为空")
    return cluster, nodecfg, version


def render_host(cluster, nodecfg, host):
    if host.get("role", "server") != "server":
        sys.exit(f"FAIL: {host['name']} role={host.get('role')}，本渲染器只产出 server config.yaml")
    settings = dict(cluster.get("settings") or {})
    cfg = {}
    # 引导：首节点 cluster-init，其余 server 指向 api_server
    if host["name"] == cluster["cluster_init_node"]:
        cfg["cluster-init"] = True
    else:
        cfg["server"] = cluster["api_server"]
    # 节点身份
    cfg["flannel-iface"] = host.get("flannel_iface") or settings.get("flannel-iface", "tailscale0")
    cfg["node-ip"] = host["node_ip"]
    if host.get("node_external_ip"):
        cfg["node-external-ip"] = host["node_external_ip"]
    # 其余集群级 settings（不覆盖上面已设的）
    for k, v in settings.items():
        if k not in cfg:
            cfg[k] = v
    # 单节点覆盖（如实 codify 现网差异）
    cfg.update((cluster.get("overrides") or {}).get(host["name"], {}))
    return cfg


def servers(nodecfg):
    return [h for h in nodecfg["hosts"] if h.get("role", "server") == "server"]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--host")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()
    cluster, nodecfg, version = load()
    if a.list:
        for h in servers(nodecfg):
            init = " (cluster-init)" if h["name"] == cluster["cluster_init_node"] else ""
            print(f"{h['name']}\t{h['node_ip']}\tk3s={version}{init}")
        return
    if not a.host:
        sys.exit("FAIL: 需 --host 或 --list")
    host = next((h for h in servers(nodecfg) if h["name"] == a.host), None)
    if not host:
        sys.exit(f"FAIL: 找不到 server 节点 {a.host}")
    cfg = render_host(cluster, nodecfg, host)
    print(json.dumps(cfg, ensure_ascii=False, indent=2) if a.json else yaml.safe_dump(cfg, sort_keys=False, allow_unicode=True))


if __name__ == "__main__":
    main()
