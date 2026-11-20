#!/usr/bin/env python3
"""门禁：cluster 镜像只认 SWR（k8s/edge/clusters），白名单逐条审批（edge/registries/foreign-allowlist.yaml）。
CI runner 侧除外（断圈：不断 runners 公网源）。stale 白名单（仓里已无引用）同样红。"""
import re, sys, pathlib
try:
    import yaml
    _allow = yaml.safe_load(open('edge/registries/foreign-allowlist.yaml')) or []
except Exception as e:
    print('ALLOWLIST-UNREADABLE: %s' % e)
    sys.exit(1)
allowed = {(a['path'], a['image']) for a in _allow}
seen = set()
fail = False
img_re = re.compile(r'^\s*(?:-\s+)?image:\s*["\']?([^\s"\']+)')
ext_re = re.compile(
    r'(^\s*(?:-\s+)?image:\s*["\']?|^\s*FROM\s+|docker\s+(?:pull|run)\b.*?\s)'
    r'(docker\.io|ghcr\.io|quay\.io|gcr\.io|registry\.k8s\.io|k8s\.gcr\.io|mcr\.microsoft\.com)[/:]')
SKIP = {'edge/registries/foreign-allowlist.yaml'}
for base in ['k8s', 'edge', 'clusters']:
    for p in sorted(pathlib.Path(base).rglob('*')):
        if not p.is_file() or p.suffix not in ('.yaml', '.yml', ''):
            continue
        if str(p) in SKIP:
            continue
        try:
            lines = p.read_text(errors='replace').splitlines()
        except OSError:
            continue
        for n, line in enumerate(lines, 1):
            m = img_re.match(line)
            if m:
                img = m.group(1)
                key = (str(p), img)
                if img.startswith('swr.'):
                    continue
                if key in allowed:
                    seen.add(key)
                    continue
                print(f'VIOLATION {p}:{n} -> {img}')
                fail = True
            elif ext_re.search(line):
                print(f'VIOLATION {p}:{n}: {line.strip()[:160]}')
                fail = True
for key in sorted(allowed - seen):
    print(f'STALE-ALLOWLIST {key[0]} :: {key[1]}')
    fail = True
# 空文件守卫
for p in list(pathlib.Path('edge').rglob('Caddyfile')) + list(pathlib.Path('edge').rglob('*.caddy')):
    try:
        if p.stat().st_size == 0:
            print(f'VIOLATION {p} is empty')
            fail = True
    except OSError:
        pass
print('POLICY-OK' if not fail else 'FAIL: 镜像必须走 SWR（白名单除外）')
sys.exit(1 if fail else 0)
