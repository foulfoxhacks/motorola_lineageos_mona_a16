import os

fw_dir = os.path.expanduser("/home/builder/work/fw")
needed = [
    "vendor.qti.hardware.data.iwlandata-V2-ndk",
    "vendor.qti.hardware.data.connectionaidl-V1-ndk",
    "vendor.qti.hardware.radio.ims-V16-ndk",
    "vendor.qti.hardware.radio.qtiradio-V16-ndk",
    "vendor.qti.hardware.radio.am-V1-ndk",
    "vendor.qti.hardware.radio.qcrilhook-V1-ndk",
    "qcrilNr_aidl_common",
    "qcrilNr_aidl_IRadioConfig",
    "qcrilNr_aidl_IRadioMessaging",
    "qcrilNr_aidl_IRadioModem",
    "qcrilNr_aidl_IRadioNetwork",
    "qcrilNr_aidl_IRadioSim",
    "qcrilNr_aidl_IRadioVoice",
    "qcrilNr_aidl_UimRemoteServer",
    "qcrilNr_aidl_UimRemoteClient",
    "qcrilNr_aidl_UimLpaService",
    "qcrilNr_aidl_UimService",
    "qcrilNr_aidl_IRadioSap",
    "qcrilNr_aidl_SecureElementService",
    "qcrilNrSecureMode"
]

found = {}
for root, dirs, files in os.walk(fw_dir):
    for f in files:
        for n in needed:
            if n in f:
                rel = os.path.relpath(os.path.join(root, f), fw_dir)
                found.setdefault(n, []).append(rel)

for n in needed:
    res = found.get(n, "NOT FOUND")
    print(f"{n}: {res}")
