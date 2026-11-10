import os

prop_file = os.path.expanduser("/home/builder/lineage/device/motorola/sm6475-common/proprietary-files.txt")
with open(prop_file, "r") as f:
    current = f.read()

blobs = [
    "vendor/lib64/vendor.qti.hardware.data.iwlandata-V2-ndk.so",
    "vendor/lib64/vendor.qti.hardware.data.connectionaidl-V1-ndk.so",
    "vendor/lib64/vendor.qti.hardware.radio.ims-V16-ndk.so",
    "vendor/lib64/vendor.qti.hardware.radio.qtiradio-V16-ndk.so",
    "vendor/lib64/vendor.qti.hardware.radio.am-V1-ndk.so",
    "vendor/lib64/vendor.qti.hardware.radio.qcrilhook-V1-ndk.so",
    "vendor/lib64/qcrilNr_aidl_common.so",
    "vendor/lib64/qcrilNr_aidl_IRadioConfig.so",
    "vendor/lib64/qcrilNr_aidl_IRadioMessaging.so",
    "vendor/lib64/qcrilNr_aidl_IRadioModem.so",
    "vendor/lib64/qcrilNr_aidl_IRadioNetwork.so",
    "vendor/lib64/qcrilNr_aidl_IRadioSim.so",
    "vendor/lib64/qcrilNr_aidl_IRadioVoice.so",
    "vendor/lib64/qcrilNr_aidl_UimRemoteServer.so",
    "vendor/lib64/qcrilNr_aidl_UimRemoteClient.so",
    "vendor/lib64/qcrilNr_aidl_UimLpaService.so",
    "vendor/lib64/qcrilNr_aidl_UimService.so",
    "vendor/lib64/qcrilNr_aidl_IRadioSap.so",
    "vendor/lib64/qcrilNr_aidl_SecureElementService.so",
    "vendor/lib64/qcrilNrSecureMode.so",
    "vendor/lib64/vendor.qti.hardware.radio.lpa-V1-ndk.so",
    "vendor/lib64/vendor.qti.hardware.radio.uim-V1-ndk.so",
    "vendor/lib64/vendor.qti.hardware.radio.uim_remote_client-V1-ndk.so",
    "vendor/lib64/vendor.qti.hardware.radio.uim_remote_server-V1-ndk.so"
]

to_add = [b for b in blobs if b not in current]
if to_add:
    with open(prop_file, "a") as f:
        f.write("\n# Added for qcrilNr and radio AIDL support\n" + "\n".join(to_add) + "\n")
    print(f"Added {len(to_add)} blobs to {prop_file}")
else:
    print("All blobs already in file.")
