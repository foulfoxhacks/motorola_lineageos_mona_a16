import os

prop_file = os.path.expanduser("/home/builder/lineage/device/motorola/sm6475-common/proprietary-files.txt")
with open(prop_file, "r") as f:
    prop_text = f.read()

fw_dir = os.path.expanduser("/home/builder/work/fw")

check_list = [
    "libqmi_cci.so",
    "libqmi.so",
    "libmdmdetect.so",
    "libqmi_client_qmux.so",
    "libqmi_client_helper.so",
    "libqmiservices.so",
    "vendor.qti.hardware.radio.atfwd-V1-ndk.so",
]

for item in check_list:
    in_prop = item in prop_text
    found_fw = []
    for root, dirs, files in os.walk(fw_dir):
        if item in files:
            found_fw.append(os.path.relpath(os.path.join(root, item), fw_dir))
    print(f"{item}: in_prop={in_prop}, in_fw={found_fw}")
