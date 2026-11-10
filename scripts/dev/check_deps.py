import os
import subprocess
import glob

fw_dir = os.path.expanduser("/home/builder/work/fw")
lineage_dir = os.path.expanduser("/home/builder/lineage")

blobs_to_add = [
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
    "vendor/lib64/qcrilNrSecureMode.so"
]

def get_dt_needed(filepath):
    try:
        out = subprocess.check_output(["readelf", "-d", filepath], stderr=subprocess.DEVNULL).decode('utf-8')
        deps = []
        for line in out.splitlines():
            if "(NEEDED)" in line and "[" in line:
                dep = line.split("[")[1].split("]")[0]
                deps.append(dep)
        return deps
    except Exception as e:
        return []

all_deps = set()
for b in blobs_to_add:
    p = os.path.join(fw_dir, b)
    if os.path.exists(p):
        deps = get_dt_needed(p)
        for d in deps:
            all_deps.add(d)

print("Dependencies of the 20 new blobs:")
for d in sorted(all_deps):
    print("  ", d)
