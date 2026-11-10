import os
import subprocess

fw_dir = os.path.expanduser("/home/builder/work/fw")
extra = [
    "vendor/lib64/vendor.qti.hardware.data.iwlandata-V2-ndk.so",
    "vendor/lib64/vendor.qti.hardware.data.connectionaidl-V1-ndk.so"
]

for e in extra:
    p = os.path.join(fw_dir, e)
    out = subprocess.check_output(["readelf", "-d", p]).decode('utf-8')
    needed = [l.split("[")[1].split("]")[0] for l in out.splitlines() if "(NEEDED)" in l and "[" in l]
    print(f"{e} depends on: {needed}")
