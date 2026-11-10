# scripts/dev — one-off bring-up probes

Throwaway diagnostics written while chasing missing blobs and AIDL/soong errors during the
first `lineage-24.0` build attempts. They are kept for reference only.

- They assume the source tree lives at `/home/builder/lineage` and the firmware dump at
  `/home/builder/work/fw`. Edit the paths before running them.
- They are read-only: they print whether a blob is listed in `proprietary-files.txt`, present
  in the firmware dump, or defined in the generated `Android.bp`, and they dump `readelf` NEEDED entries.
- Nothing in the documented workflow calls them.

If one turns out to be generally useful, promote it to `scripts/` with proper arguments.
