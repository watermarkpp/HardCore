#!/usr/bin/env python3
"""Fix remaining 14 Temp paths for Deep Forest forest_clusters."""
import sys, os, json, zipfile
sys.stdout.reconfigure(encoding='utf-8')
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
CATALOG = REPO / "assets" / "data" / "assets" / "map_asset_catalog.json"

# Find the Deep Forest ZIP
source_root = Path(r"C:\Users\Administrator\Desktop\sucai\新增\树木")
zip_path = None
for z in source_root.glob("*.zip"):
    if "Deep_Forest" in z.name:
        zip_path = z
        break

if not zip_path:
    print("ERROR: Deep Forest ZIP not found")
    sys.exit(1)

print(f"Found ZIP: {zip_path.name}")

# Load catalog
with open(CATALOG, 'r', encoding='utf-8') as f:
    catalog = json.load(f)

# Fix remaining Temp paths
fixed_count = 0
for asset in catalog['assets']:
    src = asset.get('source_external_path', '')
    if 'Temp' in src or 'ADMINI~1' in src:
        filename = os.path.basename(src)
        # Remove _partN suffix if present
        base_name = filename
        if '_part' in filename:
            base_name = filename.split('_part')[0] + '.png'

        # Search in ZIP
        try:
            with zipfile.ZipFile(zip_path, 'r') as zf:
                for member in zf.infolist():
                    if os.path.basename(member.filename) == base_name:
                        # Found match
                        provenance = f"{zip_path}::{member.filename}"
                        asset['source_external_path'] = provenance
                        fixed_count += 1
                        print(f"  Fixed: {filename} -> {member.filename}")
                        break
        except Exception as e:
            print(f"  Error processing {filename}: {e}")

print(f"\nFixed {fixed_count} Temp paths")

# Save
with open(CATALOG, 'w', encoding='utf-8') as f:
    json.dump(catalog, f, ensure_ascii=False, indent=2)

print("Catalog saved")

# Verify no more Temp paths
temp_count = sum(1 for a in catalog['assets'] if 'Temp' in a.get('source_external_path', '') or 'ADMINI~1' in a.get('source_external_path', ''))
print(f"Remaining Temp paths: {temp_count}")
