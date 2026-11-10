import os

# 1. Update sm6475-common/extract-files.py
common_file = os.path.expanduser("/home/builder/lineage/device/motorola/sm6475-common/extract-files.py")
with open(common_file, "r") as f:
    common_content = f.read()

# Replace rkp-V1 with rkp-V3
common_content = common_content.replace(
    ".add_needed('android.hardware.security.rkp-V1-ndk.so')",
    ".add_needed('android.hardware.security.rkp-V3-ndk.so')"
)

# Add fixup for libwfdmmsrc_proprietary if not present
if "libwfdmmsrc_proprietary" not in common_content:
    wfd_fixup = """    'vendor/lib64/libwfdmmsrc_proprietary.so': blob_fixup()
        .replace_needed('android.media.audio.common.types-V2-ndk.so', 'android.media.audio.common.types-V3-ndk.so'),
"""
    common_content = common_content.replace(
        "blob_fixups: blob_fixups_user_type = {",
        "blob_fixups: blob_fixups_user_type = {\n" + wfd_fixup
    )

with open(common_file, "w") as f:
    f.write(common_content)
print("Updated sm6475-common extract-files.py")

# 2. Update mona/extract-files.py
mona_file = os.path.expanduser("/home/builder/lineage/device/motorola/mona/extract-files.py")
with open(mona_file, "r") as f:
    mona_content = f.read()

# Update libcamximageformatutils or add allocator replacement
allocator_fixup = """    (
        'vendor/lib64/libcamximageformatutils.so',
        'vendor/lib64/vendor.qti.hardware.camera.postproc@1.0-service-impl.so',
    ): blob_fixup().replace_needed(
        'android.hardware.graphics.allocator-V1-ndk.so',
        'android.hardware.graphics.allocator-V2-ndk.so',
    ),"""

if "allocator-V1-ndk.so" not in mona_content:
    mona_content = mona_content.replace(
        "blob_fixups: blob_fixups_user_type = {",
        "blob_fixups: blob_fixups_user_type = {\n" + allocator_fixup
    )
    with open(mona_file, "w") as f:
        f.write(mona_content)
    print("Updated mona extract-files.py with allocator fixups")
else:
    print("allocator fixup already present in mona extract-files.py")
