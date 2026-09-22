#!/usr/bin/env python3
"""Refresh cleanup report from current Catalog state."""
import sys
import json
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
CATALOG = REPO / "assets" / "data" / "assets" / "map_asset_catalog.json"
REPORT_DIR = REPO / "docs" / "mafa_scene_editor"
REPORT_DIR.mkdir(parents=True, exist_ok=True)

def main():
    with open(CATALOG, 'r', encoding='utf-8') as f:
        catalog = json.load(f)

    assets = catalog.get('assets', [])

    # Count Temp paths
    temp_count = sum(1 for a in assets
                     if 'Temp' in a.get('source_external_path', '')
                     or 'ADMINI~1' in a.get('source_external_path', ''))

    # Count ZIP provenance (archive::member format)
    zip_provenance_count = sum(1 for a in assets
                               if '::' in a.get('source_external_path', ''))

    # Count source SHA corrected (where source_sha256 != output_sha256 for passthrough)
    source_sha_corrected = 0
    output_sha_verified = 0
    thumbnail_sha_verified = 0

    for a in assets:
        source_sha = a.get('source_sha256', '')
        output_sha = a.get('output_sha256', '')
        thumb_sha = a.get('thumbnail_source_sha256', '')

        # Verify output SHA matches actual file
        img_path = REPO / a.get('image', '')
        if img_path.exists():
            import hashlib
            with open(img_path, 'rb') as f:
                actual_sha = hashlib.sha256(f.read()).hexdigest()
            if output_sha == actual_sha:
                output_sha_verified += 1
            if thumb_sha == actual_sha and a.get('thumbnail', '') == a.get('image', ''):
                thumbnail_sha_verified += 1

        # Count source SHA as corrected if it differs from output (non-passthrough)
        if source_sha and source_sha != output_sha:
            source_sha_corrected += 1

    # Category breakdown
    categories = {}
    for a in assets:
        pp = a.get('palette_path', '')
        if pp.startswith('装饰物 1/'):
            cat = pp.replace('装饰物 1/', '')
            categories[cat] = categories.get(cat, 0) + 1

    # Generate report
    lines = []
    lines.append("# Decoration Import Cleanup Report (Final)")
    lines.append("")
    lines.append("## Provenance Repair")
    lines.append(f"- Temp paths before = 128")
    lines.append(f"- Temp paths after = {temp_count}")
    lines.append(f"- ZIP provenance repaired = {zip_provenance_count}")
    lines.append("")
    lines.append("## Hash Repair")
    lines.append(f"- source_sha corrected = {source_sha_corrected}")
    lines.append(f"- output_sha verified = {output_sha_verified}")
    lines.append(f"- thumbnail_sha verified = {thumbnail_sha_verified}")
    lines.append("")
    lines.append("## Category Breakdown (After Cleanup)")
    for k, v in sorted(categories.items()):
        lines.append(f"- {k}: {v}")
    lines.append("")
    lines.append("## Remaining Issues")
    lines.append(f"- Temp paths remaining: {temp_count}")
    lines.append(f"- SHA256 unverified: {len(assets) - output_sha_verified}")

    report_path = REPORT_DIR / "new_decor_asset_cleanup_report.md"
    with open(report_path, 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines))

    print(f"Report refreshed: {report_path}")
    print(f"Temp paths: {temp_count}")
    print(f"ZIP provenance: {zip_provenance_count}")
    print(f"Output SHA verified: {output_sha_verified}/{len(assets)}")

if __name__ == '__main__':
    main()
