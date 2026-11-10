entries = [
    "vendor/lib64/libseclog.so",
    "vendor/lib64/vendor.qti.data.factoryservice-V1-ndk.so",
    "vendor/lib64/vendor.qti.hardware.dsp-V1-ndk.so",
    "vendor/lib64/qcrilIntermodulemsgs.so",
    "vendor/lib64/vendor.qti.hardware.qseecom-V1-ndk.so",
    "vendor/lib64/vendor.qti.qspmhal-V1-ndk.so",
    "vendor/lib64/libqspm-mem-utils-vendor.so"
]

target_file = "/home/builder/lineage/device/motorola/sm6475-common/proprietary-files.txt"

with open(target_file, "r") as f:
    content = f.read()

added = []
with open(target_file, "a") as f:
    f.write("\n# Added for A16/A17 AIDL & shared lib dependencies\n")
    for e in entries:
        if e not in content:
            f.write(e + "\n")
            added.append(e)

print(f"Added {len(added)} entries to {target_file}")
