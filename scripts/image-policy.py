#!/usr/bin/env python3
"""门禁：cluster 镜像只认 SWR（k8s/edge/clusters）。CI runner 侧除外（断圈：不断 runners 公网源）。"""
import re, sys, pathlib
fail = False
img_re = re.compile(r'^\s*(?:-\s+)?image:\s*["\']?([^\s"\']+)')
ext_re = re.compile(
    r'(^\s*(?:-\s+)?image:\s*["\']?|^\s*FROM\s+|docker\s+(?:pull|run)\b.*?\s)'
    r'(docker\.io|ghcr\.io|quay\.io|gcr\.io|registry\.k8s\.io|k8s\.gcr\.io|mcr\.microsoft\.com)[/:]')
for p in list(pathlib.Path('edge').rglob('Caddyfile')) + list(pathlib.Path('edge').rglob('*.caddy')):
    try:
        sz = p.stat().st_size
    except OSError:
        continue
    if sz == 0:
        print(f'VIOLATION {p} is empty')
        fail = True
for base in ['k8s', 'edge', 'clusters']:
    for p in sorted(pathlib.Path(base).rglob('*')):
        if not p.is_file() or p.suffix not in ('.yaml', '.yml', ''):
            continue
        try:
            lines = p.read_text(errors='replace').splitlines()
        except OSError:
            continue
        for n, line in enumerate(lines, 1):
            m = img_re.match(line)
            if m and not m.group(1).startswith('swr.'):
                print(f'VIOLATION {p}:{n} -> {m.group(1)}')
                fail = True
            elif ext_re.search(line):
                print(f'VIOLATION {p}:{n}: {line.strip()[:160]}')
                fail = True
print('POLICY-OK' if not fail else 'FAIL: 镜像必须走 SWR')
sys.exit(1 if fail else 0)
