import os

extract_file = os.path.expanduser("/home/builder/lineage/device/motorola/mona/extract-files.py")
with open(extract_file, "r") as f:
    content = f.read()

target = "blob_fixups: blob_fixups_user_type = {"
addition = """blob_fixups: blob_fixups_user_type = {
    'vendor/bin/hw/android.hardware.biometrics.fingerprint@2.1-goodixservice': blob_fixup()
        .replace_needed('android.hardware.biometrics.common-V3-ndk.so', 'android.hardware.biometrics.common-V4-ndk.so')
        .replace_needed('android.hardware.biometrics.fingerprint-V3-ndk.so', 'android.hardware.biometrics.fingerprint-V4-ndk.so'),"""

if "android.hardware.biometrics.fingerprint@2.1-goodixservice" not in content:
    content = content.replace(target, addition, 1)
    with open(extract_file, "w") as f:
        f.write(content)
    print("Added goodixservice blob fixups to mona extract-files.py")
else:
    print("goodixservice fixup already present")
