import re

bp_file = "/home/builder/lineage/vendor/motorola/sm6475-common/Android.bp"
targets = [
    "libseclog",
    "vendor.qti.data.factoryservice-V1-ndk",
    "vendor.qti.hardware.dsp-V1-ndk",
    "qcrilIntermodulemsgs",
    "vendor.qti.hardware.qseecom-V1-ndk",
    "vendor.qti.qspmhal-V1-ndk",
    "libqspm-mem-utils-vendor"
]

with open(bp_file, "r") as f:
    content = f.read()

for t in targets:
    # check for name: "t"
    m = re.search(r'name:\s*"' + re.escape(t) + r'"', content)
    print(f"{'DEFINED' if m else 'NOT DEFINED'}: {t}")
