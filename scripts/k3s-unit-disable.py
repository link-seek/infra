#!/usr/bin/env python3
"""k3s systemd unit 内 --disable<comp> 吃掉（单行/多行换行两种写法），幂等。"""
import sys, re
u, m, act = sys.argv[1], sys.argv[2], sys.argv[3]  # act: remove|add
lines = open(u).read().split("\n")
if act == "remove":
    out, skip = [], False
    for ln in lines:
        if skip:
            skip = False
            if re.sub(r"[\\'\"\s]", "", ln) == m:
                continue
            out.append(ln)
            continue
        if re.search(r"--disable\s*=\s*" + m + r"\b", ln) or re.search(r"--disable\s+" + m + r"\b", ln):
            continue
        if re.search(r"--disable['\"]?\s*\\?\s*$", ln):
            skip = True
            continue
        out.append(ln)
    open(u, "w").write("\n".join(out))
    print("unit disable removed: %s" % m)
elif act == "add":
    txt = "\n".join(lines)
    assert m not in txt, "already present"
    for i, ln in enumerate(lines):
        if ln.strip().startswith("ExecStart="):
            lines.insert(i + 1, "    '--disable=%s' \\" % m)
            break
    open(u, "w").write("\n".join(lines))
    print("unit disable added: %s" % m)
