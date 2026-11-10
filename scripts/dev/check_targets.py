import sys

targets = [
    "libseclog.so",
    "vendor.qti.data.factoryservice-V1-ndk.so",
    "vendor.qti.hardware.dsp-V1-ndk.so",
    "qcrilIntermodulemsgs.so",
    "vendor.qti.hardware.qseecom-V1-ndk.so",
    "vendor.qti.qspmhal-V1-ndk.so",
    "libqspm-mem-utils-vendor.so"
]

files_to_check = [
    "/home/builder/lineage/device/motorola/sm6475-common/proprietary-files.txt",
    "/home/builder/lineage/device/motorola/mona/proprietary-files.txt"
]

for filepath in files_to_check:
    print(f"=== Checking {filepath} ===")
    try:
        with open(filepath, "r") as f:
            lines = f.readlines()
        for t in targets:
            matches = [l.strip() for l in lines if t in l]
            if matches:
                print(f"FOUND {t}: {matches}")
            else:
                print(f"MISSING {t}")
    except Exception as e:
        print(f"Error reading {filepath}: {e}")
