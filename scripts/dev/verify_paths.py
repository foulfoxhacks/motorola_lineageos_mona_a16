import os

paths = [
    "vendor/lib64/libseclog.so",
    "vendor/lib64/vendor.qti.data.factoryservice-V1-ndk.so",
    "vendor/lib64/vendor.qti.hardware.dsp-V1-ndk.so",
    "vendor/lib64/qcrilIntermodulemsgs.so",
    "vendor/lib64/vendor.qti.hardware.qseecom-V1-ndk.so",
    "vendor/lib64/vendor.qti.qspmhal-V1-ndk.so",
    "vendor/lib64/libqspm-mem-utils-vendor.so"
]

fw_root = "/home/builder/work/fw"
for p in paths:
    full = os.path.join(fw_root, p)
    print(f"{'EXISTS' if os.path.exists(full) else 'MISSING'}: {p} ({os.path.getsize(full) if os.path.exists(full) else 0} bytes)")
