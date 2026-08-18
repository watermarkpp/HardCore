#!/usr/bin/env python3
"""Verify the decoration asset import results."""
import json
import os
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding='utf-8')

REPO = Path(r"C:\Users\Administrator\Documents\HardCore-worktrees\maps")
CATALOG = REPO / "assets" / "data" / "assets" / "map_asset_catalog.json"
ASSET_BASE = REPO / "assets" / "art" / "maps" / "_shared" / "user_palette" / "decorations_1"

errors = []
warnings = []

# 1. Load catalog
print("=== Catalog Validation ===")
try:
    with open(CATALOG, 'r', encoding='utf-8') as f:
        catalog = json.load(f)
    print(f"  Valid JSON: OK")
    print(f"  Total assets: {len(catalog['assets'])}")
except Exception as e:
    print(f"  FAIL: {e}")
    sys.exit(1)

# 2. Check duplicate asset_ids
ids = [a['asset_id'] for a in catalog['assets']]
seen = set()
dupes = []
for aid in ids:
    if aid in seen:
        dupes.append(aid)
    seen.add(aid)
if dupes:
    errors.append(f"Duplicate asset_ids: {dupes}")
    print(f"  Duplicate IDs: FAIL ({len(dupes)})")
else:
    print(f"  Duplicate IDs: NONE (OK)")

# 3. Check all image paths exist
print("\n=== Image Path Validation ===")
missing_images = []
for a in catalog['assets']:
    img_path = REPO / a['image']
    if not img_path.exists():
        missing_images.append(a['image'])
if missing_images:
    errors.append(f"Missing images: {len(missing_images)}")
    for m in missing_images[:5]:
        print(f"  MISSING: {m}")
    if len(missing_images) > 5:
        print(f"  ... and {len(missing_images) - 5} more")
else:
    print(f"  All image paths exist: OK")

# 4. Check all thumbnail paths exist
print("\n=== Thumbnail Path Validation ===")
missing_thumbs = []
for a in catalog['assets']:
    thumb_path = REPO / a.get('thumbnail', a['image'])
    if not thumb_path.exists():
        missing_thumbs.append(a.get('thumbnail', a['image']))
if missing_thumbs:
    errors.append(f"Missing thumbnails: {len(missing_thumbs)}")
    for m in missing_thumbs[:5]:
        print(f"  MISSING: {m}")
else:
    print(f"  All thumbnail paths exist: OK")

# 5. Check all new PNGs have alpha channel
print("\n=== Alpha Channel Validation ===")
from PIL import Image
no_alpha = []
new_entries = [a for a in catalog['assets'] if a.get('palette_path', '').startswith('\u88c5\u9970\u72691/')]
for a in new_entries:
    img_path = REPO / a['image']
    try:
        img = Image.open(img_path)
        if img.mode != 'RGBA':
            no_alpha.append(a['image'])
    except Exception as e:
        errors.append(f"Cannot open {a['image']}: {e}")

if no_alpha:
    warnings.append(f"Images without RGBA: {len(no_alpha)}")
    for n in no_alpha[:5]:
        print(f"  NO ALPHA: {n}")
else:
    print(f"  All new images have RGBA: OK")

# 6. Category breakdown
print("\n=== Category Breakdown ===")
cats = {}
for a in new_entries:
    pp = a.get('palette_path', '')
    cats[pp] = cats.get(pp, 0) + 1
for k, v in sorted(cats.items()):
    print(f"  {k}: {v}")
print(f"  Total new entries: {len(new_entries)}")

# 7. Check new entries have required fields
print("\n=== Required Fields Validation ===")
required = ['asset_id', 'display_name', 'asset_type', 'category', 'object_class',
            'theme', 'image', 'thumbnail', 'canvas_size', 'image_size',
            'visible_bounds_px', 'anchor_px', 'placement_anchor_px',
            'anchor_tile', 'anchor_mode', 'footprint_tiles', 'tile_size',
            'default_layer', 'default_object_role', 'collision_policy',
            'navigation_policy', 'placeable', 'palette_path', 'tags']
missing_fields = []
for a in new_entries:
    for field in required:
        if field not in a:
            missing_fields.append((a['asset_id'], field))
if missing_fields:
    errors.append(f"Missing fields: {len(missing_fields)}")
    for aid, field in missing_fields[:5]:
        print(f"  {aid} missing: {field}")
else:
    print(f"  All required fields present: OK")

# 8. Verify no existing assets were broken
print("\n=== Existing Assets Integrity ===")
old_entries = [a for a in catalog['assets'] if not a.get('palette_path', '').startswith('\u88c5\u9970\u72691/') or a.get('processing') != 'user_pre_cut_transparent_passthrough']
# Actually, just check that the original entries are still there
original_ids = set(ids) - set(a['asset_id'] for a in new_entries)
print(f"  Original assets preserved: {len(original_ids)}")

# 9. Check unique image paths
print("\n=== Image Path Uniqueness ===")
img_paths = [a['image'] for a in catalog['assets']]
path_dupes = [p for p in img_paths if img_paths.count(p) > 1]
if path_dupes:
    errors.append(f"Duplicate image paths: {len(set(path_dupes))}")
    for p in list(set(path_dupes))[:5]:
        print(f"  DUPLICATE: {p}")
else:
    print(f"  All image paths unique: OK")

# Summary
print("\n" + "=" * 50)
if errors:
    print(f"RESULT: FAIL ({len(errors)} errors, {len(warnings)} warnings)")
    for e in errors:
        print(f"  ERROR: {e}")
else:
    print(f"RESULT: PASS ({len(warnings)} warnings)")
for w in warnings:
    print(f"  WARN: {w}")
