import os

prop_file = os.path.expanduser("/home/builder/lineage/device/motorola/sm6475-common/proprietary-files.txt")
with open(prop_file, "r") as f:
    current = f.read()

blobs = [
    "vendor/lib64/libATFWD.so",
    "vendor/lib64/vendor.qti.hardware.radio.internal.deviceinfo-V1-ndk.so",
    "vendor/lib64/vendor.qti.hardware.radio.atfwd-V1-ndk.so"
]

to_add = [b for b in blobs if b not in current]
if to_add:
    with open(prop_file, "a") as f:
        f.write("\n# Added for ATFWD and radio internal deviceinfo\n" + "\n".join(to_add) + "\n")
    print(f"Added {len(to_add)} blobs to {prop_file}")
else:
    print("All blobs already in file.")
