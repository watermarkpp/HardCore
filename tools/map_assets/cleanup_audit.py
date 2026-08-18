#!/usr/bin/env python3
"""Phase 1: Identify exact NEW_BATCH_ASSET_IDS and generate overlap audit."""
import sys, os, json
sys.stdout.reconfigure(encoding='utf-8')
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
CATALOG = REPO / "assets" / "data" / "assets" / "map_asset_catalog.json"
REPORT_DIR = REPO / "docs" / "mafa_scene_editor"
REPORT_DIR.mkdir(parents=True, exist_ok=True)

PRE_IMPORT_BASE = "cf4ceb344d7a612104347917c1e32ef0392eeff6"
IMPORT_COMMIT = "c4d260866935132b95a4a2498fe322acf7050e17"

def load_catalog_at(commit):
    """Load catalog JSON at a specific commit."""
    import subprocess
    content = subprocess.check_output(
        ['git', 'show', f'{commit}:assets/data/assets/map_asset_catalog.json'],
        cwd=str(REPO)
    ).decode('utf-8')
    return json.loads(content)

# Load both versions
print("Loading PRE_IMPORT_BASE catalog...")
pre_catalog = load_catalog_at(PRE_IMPORT_BASE)
pre_ids = set(a['asset_id'] for a in pre_catalog['assets'])
print(f"  Pre-import assets: {len(pre_catalog['assets'])}")

print("Loading IMPORT_COMMIT catalog...")
imp_catalog = load_catalog_at(IMPORT_COMMIT)
imp_ids = set(a['asset_id'] for a in imp_catalog['assets'])
print(f"  Import-commit assets: {len(imp_catalog['assets'])}")

# Calculate NEW_BATCH_ASSET_IDS
new_batch_ids = imp_ids - pre_ids
print(f"\nNEW_BATCH_ASSET_IDS count: {len(new_batch_ids)}")

# Get the actual entries
new_batch_entries = [a for a in imp_catalog['assets'] if a['asset_id'] in new_batch_ids]

# Categorize
categories = {}
for e in new_batch_entries:
    pp = e.get('palette_path', '')
    categories[pp] = categories.get(pp, 0) + 1

print("\nCategory breakdown:")
for k, v in sorted(categories.items()):
    print(f"  {k}: {v}")

# Count PNGs
png_count = sum(1 for e in new_batch_entries if e.get('image', '').endswith('.png'))
print(f"\nTotal new PNG assets: {png_count}")

# Now read ALL catalogs that MapAssetCatalogService loads
print("\n=== Reading all effective catalogs ===")
catalog_service_path = REPO / "scripts" / "map_assets" / "map_asset_catalog_service.gd"
with open(catalog_service_path, 'r', encoding='utf-8') as f:
    service_code = f.read()

# Extract CATALOG_PATH and EXTENSION_CATALOG_PATHS
import re
cat_path_match = re.search(r'CATALOG_PATH\s*:=\s*"([^"]+)"', service_code)
ext_paths_match = re.search(r'EXTENSION_CATALOG_PATHS\s*:=\s*\[(.*?)\]', service_code, re.DOTALL)

all_catalog_paths = []
if cat_path_match:
    main_path = cat_path_match.group(1).replace('res://', str(REPO) + '/')
    all_catalog_paths.append(main_path)
    print(f"Main catalog: {main_path}")

if ext_paths_match:
    ext_text = ext_paths_match.group(1)
    ext_paths = re.findall(r'"([^"]+)"', ext_text)
    for ep in ext_paths:
        full_path = ep.replace('res://', str(REPO) + '/')
        all_catalog_paths.append(full_path)
        print(f"Extension: {full_path}")

# Load all catalogs and build effective index
effective_assets = []
for cp in all_catalog_paths:
    if os.path.exists(cp):
        with open(cp, 'r', encoding='utf-8') as f:
            data = json.load(f)
        assets = data.get('assets', [])
        effective_assets.extend(assets)
        print(f"  Loaded {len(assets)} assets from {os.path.basename(cp)}")
    else:
        print(f"  MISSING: {cp}")

print(f"\nTotal effective assets: {len(effective_assets)}")

# Check for overlaps between new batch and existing effective assets
effective_ids = set(a['asset_id'] for a in effective_assets)
effective_images = set(a.get('image', '') for a in effective_assets)
effective_sources = set(a.get('source_external_path', '') for a in effective_assets)

# Find duplicates
duplicate_by_id = []
duplicate_by_image = []
duplicate_by_source = []

for e in new_batch_entries:
    aid = e['asset_id']
    img = e.get('image', '')
    src = e.get('source_external_path', '')

    # Check if this asset_id exists in other catalogs (not main)
    other_cats = [cp for cp in all_catalog_paths[1:] if os.path.exists(cp)]
    for cp in other_cats:
        with open(cp, 'r', encoding='utf-8') as f:
            data = json.load(f)
        for other in data.get('assets', []):
            if other.get('asset_id') == aid:
                duplicate_by_id.append((e, cp, other))
            if other.get('image', '') == img and img:
                duplicate_by_image.append((e, cp, other))
            if other.get('source_external_path', '') == src and src:
                duplicate_by_source.append((e, cp, other))

print(f"\n=== Overlap Audit ===")
print(f"Duplicates by asset_id: {len(duplicate_by_id)}")
print(f"Duplicates by image path: {len(duplicate_by_image)}")
print(f"Duplicates by source path: {len(duplicate_by_source)}")

# Check for Temp paths in source_external_path
temp_paths = [e for e in new_batch_entries if 'Temp' in e.get('source_external_path', '') or 'ADMINI~1' in e.get('source_external_path', '')]
print(f"\nTemp source paths: {len(temp_paths)}")

# Generate audit report
report_lines = []
report_lines.append("# New Decoration Cleanup Audit")
report_lines.append("")
report_lines.append(f"PRE_IMPORT_BASE = {PRE_IMPORT_BASE}")
report_lines.append(f"IMPORT_COMMIT = {IMPORT_COMMIT}")
report_lines.append(f"CLEANUP_BASE = e5fa93bbd9a20a95d9ea694322ddfde59ad0676f")
report_lines.append("")
report_lines.append(f"NEW_BATCH_ASSETS = {len(new_batch_ids)}")
report_lines.append(f"NEW_BATCH_PNG_COUNT = {png_count}")
report_lines.append("")
report_lines.append("## Category Breakdown")
for k, v in sorted(categories.items()):
    report_lines.append(f"- {k}: {v}")
report_lines.append("")
report_lines.append("## Overlap Audit")
report_lines.append(f"- Duplicates by asset_id: {len(duplicate_by_id)}")
report_lines.append(f"- Duplicates by image path: {len(duplicate_by_image)}")
report_lines.append(f"- Duplicates by source path: {len(duplicate_by_source)}")
report_lines.append(f"- Temp source paths: {len(temp_paths)}")
report_lines.append("")

if duplicate_by_id:
    report_lines.append("### Duplicates by asset_id")
    for e, cp, other in duplicate_by_id[:10]:
        report_lines.append(f"- {e['asset_id']} in {os.path.basename(cp)}")

if temp_paths:
    report_lines.append("\n### Temp Source Paths (first 10)")
    for e in temp_paths[:10]:
        report_lines.append(f"- {e['asset_id']}: {e['source_external_path']}")

report_path = REPORT_DIR / "new_decor_cleanup_audit.md"
with open(report_path, 'w', encoding='utf-8') as f:
    f.write('\n'.join(report_lines))

print(f"\nAudit report written to: {report_path}")

# Save new batch IDs for next phase
ids_path = REPORT_DIR / "new_batch_asset_ids.json"
with open(ids_path, 'w', encoding='utf-8') as f:
    json.dump(list(new_batch_ids), f, ensure_ascii=False, indent=2)
print(f"New batch IDs saved to: {ids_path}")
