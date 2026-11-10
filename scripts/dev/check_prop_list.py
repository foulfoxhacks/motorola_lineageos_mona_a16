import os

prop_file = os.path.expanduser("/home/builder/lineage/device/motorola/sm6475-common/proprietary-files.txt")
with open(prop_file, "r") as f:
    prop_text = f.read()

fw_dir = os.path.expanduser("/home/builder/work/fw")

check_list = [
    "libqcrilNrFramework.so",
    "libqcrilNrLogger.so",
    "libqcrilNrQtiMutex.so",
    "libqmi_common_so.so",
    "libril-db.so",
    "qcrilInterfaces.so",
    "qcrilNrQmiModule.so",
    "qtiril-utils.so",
    "qtiwakelock.so",
    "vendor.qti.hardware.radio.lpa-V1-ndk.so",
    "vendor.qti.hardware.radio.uim-V1-ndk.so",
    "vendor.qti.hardware.radio.uim_remote_client-V1-ndk.so",
    "vendor.qti.hardware.radio.uim_remote_server-V1-ndk.so",
]

for item in check_list:
    in_prop = item in prop_text
    found_fw = []
    for root, dirs, files in os.walk(fw_dir):
        if item in files:
            found_fw.append(os.path.relpath(os.path.join(root, item), fw_dir))
    print(f"{item}: in_prop={in_prop}, in_fw={found_fw}")
