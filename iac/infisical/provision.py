#!/usr/bin/env python3
"""Infisical 声明式 provisioning（幂等，Phase A）。

按同目录 apps.json 的声明，确保每个应用的：
  Infisical 项目存在 → 机器身份 <slug>-operator 存在 → 项目授权 → k8s Secret <ns>/<ua.name>(clientId/clientSecret) 存在。
默认 dry-run（只打印计划）；加 --apply 才真正变更。**只补缺，不动已存在的 ua secret（绝不轮换现有凭据）。**

运行环境：能访问 Infisical 服务且具备 `k3s kubectl` 的节点（CI 里通过 ssh 到控制节点执行）。
可用环境变量 INFISICAL_API 覆盖 API 地址（默认自动从 Service ClusterIP 发现）。
"""
import base64, json, os, sys, subprocess, urllib.request, urllib.error

APPLY = "--apply" in sys.argv
HERE = os.path.dirname(os.path.abspath(__file__))
SPEC = json.load(open(os.path.join(HERE, "apps.json"), encoding="utf-8"))


def kubectl(args, stdin=None):
    return subprocess.run(["k3s", "kubectl"] + args, input=stdin,
                          capture_output=True, text=True)


def _resolve_api():
    if os.environ.get("INFISICAL_API"):
        return os.environ["INFISICAL_API"]
    r = kubectl(["-n", "infisical", "get", "svc", "infisical",
                 "-o", "jsonpath={.spec.clusterIP}"])
    ip = (r.stdout or "").strip()
    return "http://%s:8080" % ip if ip else "http://10.43.153.59:8080"


API = _resolve_api()


def admin_token():
    r = kubectl(["-n", "infisical", "get", "secret", "infisical-admin",
                 "-o", "jsonpath={.data.token}"])
    if r.returncode != 0:
        sys.exit("FAIL: 读不到 infisical-admin token: " + r.stderr[:200])
    return base64.b64decode(r.stdout).decode().strip()


TOK = admin_token()


def api(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(API + path, data=data, method=method,
                                 headers={"Authorization": "Bearer " + TOK,
                                          "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read() or b"{}")
        except Exception:
            return e.code, {}
    except Exception as e:
        return 0, {"error": str(e)[:200]}


def list_projects():
    st, r = api("GET", "/api/v1/workspace")
    return {w.get("slug"): w for w in (r.get("workspaces") or [])}


def org_id(projects):
    for w in projects.values():
        if w.get("orgId"):
            return w["orgId"]
    return os.environ.get("INFISICAL_ORG_ID", "")


def list_identities(org):
    st, r = api("GET", "/api/v1/identities?orgId=%s" % org)
    out = {}
    for i in (r.get("identities") or []):
        ident = i.get("identity") or {}
        if ident.get("name"):
            out[ident["name"]] = ident
    return out


def project_member_ids(pid):
    st, r = api("GET", "/api/v2/workspace/%s/identity-memberships" % pid)
    return [m.get("identity", {}).get("id") for m in (r.get("identityMemberships") or [])]


def secret_exists(ns, name):
    return kubectl(["-n", ns, "get", "secret", name, "-o", "name"]).returncode == 0


def create_secret(ns, name, cid, csec):
    man = (f"apiVersion: v1\nkind: Secret\nmetadata:\n  name: {name}\n  namespace: {ns}\n"
           f"type: Opaque\nstringData:\n  clientId: {json.dumps(cid)}\n  clientSecret: {json.dumps(csec)}\n")
    return kubectl(["apply", "-f", "-"], stdin=man)


def main():
    print("== Infisical provisioning  mode=%s  api=%s ==" % ("APPLY" if APPLY else "DRY-RUN", API))
    projects = list_projects()
    org = org_id(projects)
    identities = list_identities(org) if org else {}
    print("org=%s  projects=%d  identities=%d" % (org, len(projects), len(identities)))
    changed = 0

    for app in SPEC:
        slug = app["slug"]; ident_name = app["identity"]; role = app.get("role", "viewer")
        ua = app["ua"]; ns = ua["namespace"]; sec = ua["name"]
        print("\n-- %s (identity=%s, ua=%s/%s)" % (slug, ident_name, ns, sec))

        # 1) 项目
        proj = projects.get(slug)
        if not proj:
            print("   project: MISSING -> %s" % ("CREATE" if APPLY else "would create"))
            if APPLY:
                st, r = api("POST", "/api/v1/projects", {"projectName": slug})
                proj = r.get("project")
                if not proj:
                    print("   !! create project failed: %s %s" % (st, r)); continue
                if proj.get("slug") != slug:
                    api("PATCH", "/api/v1/projects/%s" % proj["id"], {"slug": slug})
                    proj["slug"] = slug
                changed += 1
        else:
            print("   project: OK (%s)" % proj.get("id"))

        # 2) 身份
        ident = identities.get(ident_name)
        if not ident:
            print("   identity: MISSING -> %s" % ("CREATE" if APPLY else "would create"))
            if APPLY and org:
                st, r = api("POST", "/api/v1/identities",
                            {"name": ident_name, "organizationId": org, "role": "no-access"})
                ident = r.get("identity")
                if not ident:
                    print("   !! create identity failed: %s %s" % (st, r)); continue
                changed += 1
        else:
            print("   identity: OK (%s)" % ident.get("id"))

        # 3) 项目授权
        if proj and ident:
            members = project_member_ids(proj["id"])
            if ident["id"] not in members:
                print("   membership: MISSING -> %s" % ("GRANT " + role if APPLY else "would grant " + role))
                if APPLY:
                    st, r = api("POST", "/api/v2/workspace/%s/identity-memberships/%s" % (proj["id"], ident["id"]),
                                {"role": role})
                    print("     grant http=%s" % st); changed += 1
            else:
                print("   membership: OK")

        # 4) k8s ua secret（只缺才建，绝不覆盖已有）
        if secret_exists(ns, sec):
            print("   ua-secret %s/%s: OK (skip, 不改动)" % (ns, sec))
            continue
        print("   ua-secret %s/%s: MISSING -> %s" % (ns, sec, "CREATE(新身份凭据)" if APPLY else "would create"))
        if not APPLY:
            continue
        if not ident:
            print("   !! 无身份，跳过建 ua-secret"); continue
        # 确保 UA 已挂 + 取 clientId + 生成 clientSecret
        api("POST", "/api/v1/auth/universal-auth/identities/%s" % ident["id"])
        st, cfg = api("GET", "/api/v1/auth/universal-auth/identities/%s" % ident["id"])
        cid = ((cfg.get("identityUniversalAuth") or {}).get("clientId")) if isinstance(cfg, dict) else None
        st, cs = api("POST", "/api/v1/auth/universal-auth/identities/%s/client-secrets" % ident["id"], {})
        csec = cs.get("clientSecret") if isinstance(cs, dict) else None
        if not (cid and csec):
            print("   !! 取 UA 凭据失败 cid=%s csec=%s" % (bool(cid), bool(csec))); continue
        r = create_secret(ns, sec, cid, csec)
        print("   create secret rc=%s %s" % (r.returncode, r.stderr[:120] if r.returncode else "ok"))
        changed += 1

    print("\n== done, changed=%d (mode=%s) ==" % (changed, "APPLY" if APPLY else "DRY-RUN"))


if __name__ == "__main__":
    main()
