#!/usr/bin/env python3
"""Execute cleanup: remove canonical duplicates, fix Temp paths, fix SHA256."""
import sys, os, json, hashlib, zipfile
sys.stdout.reconfigure(encoding='utf-8')
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
CATALOG = REPO / "assets" / "data" / "assets" / "map_asset_catalog.json"
REPORT_DIR = REPO / "docs" / "mafa_scene_editor"

# Load IDs
with open(REPORT_DIR / "new_batch_asset_ids.json", 'r', encoding='utf-8') as f:
    new_batch_ids = set(json.load(f))

with open(REPORT_DIR / "canonical_duplicate_ids.json", 'r', encoding='utf-8') as f:
    canonical_dup_ids = set(json.load(f))

with open(REPORT_DIR / "unreferenced_duplicate_ids.json", 'r', encoding='utf-8') as f:
    unreferenced_dup_ids = set(json.load(f))

# Load current catalog
with open(CATALOG, 'r', encoding='utf-8') as f:
    catalog = json.load(f)

print(f"Total catalog assets before: {len(catalog['assets'])}")
print(f"New batch IDs: {len(new_batch_ids)}")
print(f"Canonical duplicates: {len(canonical_dup_ids)}")
print(f"Unreferenced duplicates: {len(unreferenced_dup_ids)}")

# Phase 1: Remove unreferenced canonical duplicates
removed_entries = []
kept_entries = []
for asset in catalog['assets']:
    if asset['asset_id'] in unreferenced_dup_ids:
        removed_entries.append(asset)
    else:
        kept_entries.append(asset)

catalog['assets'] = kept_entries
print(f"\nRemoved {len(removed_entries)} canonical duplicate entries")
print(f"Catalog assets after removal: {len(catalog['assets'])}")

# Phase 2: Fix Temp paths and SHA256 for remaining new batch entries
# Load extension catalogs to find correct ZIP provenance
extension_catalogs = {
    "map_exit_asset_catalog.json": "assets/data/assets/map_exit_asset_catalog.json",
    "map_deep_forest_asset_catalog.json": "assets/data/assets/map_deep_forest_asset_catalog.json",
    "map_ground_graffiti_asset_catalog.json": "assets/data/assets/map_ground_graffiti_asset_catalog.json",
    "map_new_carpet_asset_catalog.json": "assets/data/assets/map_new_carpet_asset_catalog.json",
    "map_new_ground_pillar_throne_asset_catalog.json": "assets/data/assets/map_new_ground_pillar_throne_asset_catalog.json",
}

# Build source path -> ZIP member mapping from extension catalogs
zip_member_map = {}
for cat_name, cat_path in extension_catalogs.items():
    full_path = REPO / cat_path
    if full_path.exists():
        with open(full_path, 'r', encoding='utf-8') as f:
            data = json.load(f)
        for asset in data.get('assets', []):
            src = asset.get('source_external_path', '')
            if src and '::' in src:
                # Extract ZIP path and member
                parts = src.split('::', 1)
                if len(parts) == 2:
                    zip_path, member_path = parts
                    zip_member_map[os.path.basename(member_path)] = src

# Fix remaining new batch entries
remaining_new_batch = [a for a in catalog['assets'] if a['asset_id'] in new_batch_ids]
print(f"\nRemaining new batch entries to fix: {len(remaining_new_batch)}")

temp_path_count = 0
sha_fixed_count = 0
provenance_fixed_count = 0

for asset in remaining_new_batch:
    src = asset.get('source_external_path', '')
    aid = asset['asset_id']

    # Check if Temp path
    is_temp = 'Temp' in src or 'ADMINI~1' in src

    if is_temp:
        temp_path_count += 1
        # Try to find correct provenance from extension catalogs
        filename = os.path.basename(src)
        correct_provenance = zip_member_map.get(filename)

        if correct_provenance:
            asset['source_external_path'] = correct_provenance
            provenance_fixed_count += 1
        else:
            # Try to find the ZIP file and member
            # Search in source directory
            source_root = REPO.parent.parent / "Desktop" / "sucai" / "新增"
            for zip_file in source_root.rglob("*.zip"):
                try:
                    with zipfile.ZipFile(zip_file, 'r') as zf:
                        for member in zf.infolist():
                            if os.path.basename(member.filename) == filename:
                                # Found it
                                provenance = f"{zip_file}::{member.filename}"
                                asset['source_external_path'] = provenance
                                provenance_fixed_count += 1
                                break
                except:
                    pass

    # Fix source_sha256 and output_sha256
    # For now, we'll mark that these need manual verification
    # since we don't have the original source files for all assets
    if asset.get('source_sha256', '') == asset.get('output_sha256', ''):
        # This might be correct for passthrough, but let's verify
        img_path = REPO / asset.get('image', '')
        if img_path.exists():
            with open(img_path, 'rb') as f:
                actual_sha = hashlib.sha256(f.read()).hexdigest()
            if asset.get('output_sha256', '') != actual_sha:
                asset['output_sha256'] = actual_sha
                asset['thumbnail_source_sha256'] = actual_sha
                sha_fixed_count += 1

print(f"\nTemp paths fixed: {provenance_fixed_count}/{temp_path_count}")
print(f"SHA256 fixed: {sha_fixed_count}")

# Save cleaned catalog
with open(CATALOG, 'w', encoding='utf-8') as f:
    json.dump(catalog, f, ensure_ascii=False, indent=2)

print(f"\nCleaned catalog saved")
print(f"Total catalog assets: {len(catalog['assets'])}")

# Generate cleanup report
report_lines = []
report_lines.append("# Decoration Import Cleanup Report")
report_lines.append("")
report_lines.append(f"PRE_IMPORT_BASE = cf4ceb344d7a612104347917c1e32ef0392eeff6")
report_lines.append(f"IMPORT_COMMIT = c4d260866935132b95a4a2498fe322acf7050e17")
report_lines.append(f"CLEANUP_BASE = e5fa93bbd9a20a95d9ea694322ddfde59ad0676f")
report_lines.append("")
report_lines.append(f"NEW_BATCH_ASSETS = {len(new_batch_ids)}")
report_lines.append("")
report_lines.append("## Cleanup Results")
report_lines.append(f"- Removed canonical duplicate entries: {len(removed_entries)}")
report_lines.append(f"- Temp paths fixed: {provenance_fixed_count}/{temp_path_count}")
report_lines.append(f"- SHA256 corrected: {sha_fixed_count}")
report_lines.append("")
report_lines.append("## Category Breakdown (After Cleanup)")
categories = {}
for a in catalog['assets']:
    if a['asset_id'] in new_batch_ids:
        pp = a.get('palette_path', '')
        categories[pp] = categories.get(pp, 0) + 1

for k, v in sorted(categories.items()):
    report_lines.append(f"- {k}: {v}")

report_lines.append("")
report_lines.append("## Remaining Issues")
report_lines.append(f"- Temp paths remaining: {temp_path_count - provenance_fixed_count}")
report_lines.append(f"- SHA256 unverified: {len(remaining_new_batch) - sha_fixed_count}")

cleanup_report_path = REPORT_DIR / "new_decor_asset_cleanup_report.md"
with open(cleanup_report_path, 'w', encoding='utf-8') as f:
    f.write('\n'.join(report_lines))

print(f"\nCleanup report written to: {cleanup_report_path}")
