#!/usr/bin/env python3
"""Fix SHA256 values for new batch assets."""
import sys, os, json, hashlib, zipfile
sys.stdout.reconfigure(encoding='utf-8')
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
CATALOG = REPO / "assets" / "data" / "assets" / "map_asset_catalog.json"
REPORT_DIR = REPO / "docs" / "mafa_scene_editor"

# Load new batch IDs
with open(REPORT_DIR / "new_batch_asset_ids.json", 'r', encoding='utf-8') as f:
    new_batch_ids = set(json.load(f))

# Load catalog
with open(CATALOG, 'r', encoding='utf-8') as f:
    catalog = json.load(f)

def sha256_file(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(8192), b''):
            h.update(chunk)
    return h.hexdigest()

def sha256_bytes(data):
    return hashlib.sha256(data).hexdigest()

def sha256_zip_member(zip_path, member_path):
    with zipfile.ZipFile(zip_path, 'r') as zf:
        with zf.open(member_path) as m:
            return sha256_bytes(m.read())

# Fix SHA256 for new batch assets
fixed_source = 0
fixed_output = 0
fixed_thumbnail = 0

for asset in catalog['assets']:
    if asset['asset_id'] not in new_batch_ids:
        continue

    src = asset.get('source_external_path', '')
    img_path = REPO / asset.get('image', '')

    # Calculate output SHA256 (from final PNG)
    if img_path.exists():
        output_sha = sha256_file(img_path)
        if asset.get('output_sha256', '') != output_sha:
            asset['output_sha256'] = output_sha
            fixed_output += 1

        # thumbnail_source_sha256 = output_sha if thumbnail == image
        if asset.get('thumbnail', '') == asset.get('image', ''):
            if asset.get('thumbnail_source_sha256', '') != output_sha:
                asset['thumbnail_source_sha256'] = output_sha
                fixed_thumbnail += 1

    # Calculate source SHA256
    if '::' in src:
        # ZIP source
        parts = src.split('::', 1)
        zip_path, member_path = parts
        if os.path.exists(zip_path):
            try:
                source_sha = sha256_zip_member(zip_path, member_path)
                if asset.get('source_sha256', '') != source_sha:
                    asset['source_sha256'] = source_sha
                    fixed_source += 1
            except Exception as e:
                print(f"  Warning: Could not read ZIP member {member_path}: {e}")
    elif os.path.exists(src):
        # Direct file source
        source_sha = sha256_file(src)
        if asset.get('source_sha256', '') != source_sha:
            asset['source_sha256'] = source_sha
            fixed_source += 1

print(f"Fixed source_sha256: {fixed_source}")
print(f"Fixed output_sha256: {fixed_output}")
print(f"Fixed thumbnail_source_sha256: {fixed_thumbnail}")

# Save
with open(CATALOG, 'w', encoding='utf-8') as f:
    json.dump(catalog, f, ensure_ascii=False, indent=2)

print("Catalog saved")
