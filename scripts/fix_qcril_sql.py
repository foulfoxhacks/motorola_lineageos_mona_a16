import os

prop_file = os.path.expanduser("/home/builder/lineage/device/motorola/sm6475-common/proprietary-files.txt")
with open(prop_file, "r") as f:
    lines = f.readlines()

new_lines = []
for line in lines:
    # Skip any old unmatched qcril config/other lines
    if "proprietary_rildb_config_sql_files" in line or "proprietary_rildb_other_sql_files" in line:
        continue
    new_lines.append(line)

sql_entries = [
    "\n# QCRIL database sql files matching stock firmware\n",
    "vendor/etc/qcril_database/upgrade/config/0006.0_config.sql;FILEGROUP=proprietary_rildb_config_sql_files\n",
    "vendor/etc/qcril_database/upgrade/config/0007.0_config.sql;FILEGROUP=proprietary_rildb_config_sql_files\n",
    "vendor/etc/qcril_database/upgrade/config/0008.0_config.sql;FILEGROUP=proprietary_rildb_config_sql_files\n",
    "vendor/etc/qcril_database/upgrade/config/0009.0_config.sql;FILEGROUP=proprietary_rildb_config_sql_files\n",
    "vendor/etc/qcril_database/upgrade/config/0010.0_config.sql;FILEGROUP=proprietary_rildb_config_sql_files\n",
    "vendor/etc/qcril_database/upgrade/config/0011.0_config.sql;FILEGROUP=proprietary_rildb_config_sql_files\n",
    "vendor/etc/qcril_database/upgrade/config/0012.0_config.sql;FILEGROUP=proprietary_rildb_config_sql_files\n",
    "vendor/etc/qcril_database/upgrade/config/0013.0_config.sql;FILEGROUP=proprietary_rildb_config_sql_files\n",
    "vendor/etc/qcril_database/upgrade/config/0014.0_config.sql;FILEGROUP=proprietary_rildb_config_sql_files\n",
    "vendor/etc/qcril_database/upgrade/config/0015.0_config.sql;FILEGROUP=proprietary_rildb_config_sql_files\n",
    "vendor/etc/qcril_database/upgrade/other/0002_version_add_wps_config_qcrilnr.sql;FILEGROUP=proprietary_rildb_other_sql_files\n",
    "vendor/etc/qcril_database/upgrade/other/0003_version_update_wps_config_qcrilnr.sql;FILEGROUP=proprietary_rildb_other_sql_files\n",
    "vendor/etc/qcril_database/upgrade/other/0006_version_change_property_table_qcrilnr.sql;FILEGROUP=proprietary_rildb_other_sql_files\n",
    "vendor/etc/qcril_database/upgrade/other/0014_version_update_modules.sql;FILEGROUP=proprietary_rildb_other_sql_files\n",
    "vendor/etc/qcril_database/upgrade/other/0015_version_add_iccid_clir_pref_table.sql;FILEGROUP=proprietary_rildb_other_sql_files\n"
]

new_lines.extend(sql_entries)

with open(prop_file, "w") as f:
    f.writelines(new_lines)

print("Updated proprietary-files.txt with exact qcril SQL file names")
