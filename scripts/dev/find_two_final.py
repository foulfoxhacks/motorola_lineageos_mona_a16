import os
import subprocess

fw_dir = os.path.expanduser("/home/builder/work/fw")

targets = [
    "libATFWD",
    "vendor.qti.hardware.radio.internal.deviceinfo"
]

found = {}
for root, dirs, files in os.walk(fw_dir):
    for f in files:
        for t in targets:
            if t in f:
                rel = os.path.relpath(os.path.join(root, f), fw_dir)
                found.setdefault(t, []).append(rel)

for t in targets:
    res = found.get(t, ["NOT FOUND"])
    print(f"{t}: {res}")

def check_deps(relpath):
    p = os.path.join(fw_dir, relpath)
    out = subprocess.check_output(["readelf", "-d", p]).decode('utf-8')
    needed = [l.split("[")[1].split("]")[0] for l in out.splitlines() if "(NEEDED)" in l and "[" in l]
    print(f"Dependencies of {relpath}: {needed}")

for t, paths in found.items():
    for p in paths:
        if p.endswith(".so"):
            check_deps(p)
