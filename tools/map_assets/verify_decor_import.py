#!/usr/bin/env python3
"""Verify the decoration asset import results against effective catalogs."""
import json
import os
import re
import sys
import zipfile
from pathlib import Path

sys.stdout.reconfigure(encoding='utf-8')

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import repair_new_decor_package_metadata as repair

# No hardcoded worktree
REPO = Path(__file__).resolve().parents[2]
CATALOG_SERVICE_PATH = REPO / "scripts" / "map_assets" / "map_asset_catalog_service.gd"
ASSET_BASE = REPO / "assets" / "art" / "maps" / "_shared" / "user_palette" / "decorations_1"

errors = []
warnings = []


def load_effective_catalogs():
    """Load all catalogs that MapAssetCatalogService loads."""
    catalogs = []

    if CATALOG_SERVICE_PATH.exists():
        with open(CATALOG_SERVICE_PATH, 'r', encoding='utf-8') as f:
            content = f.read()

        cat_match = re.search(r'CATALOG_PATH\s*:=\s*"([^"]+)"', content)
        if cat_match:
            main_path = cat_match.group(1).replace('res://', str(REPO) + '/')
            catalogs.append(main_path)

        ext_match = re.search(r'EXTENSION_CATALOG_PATHS\s*:=\s*\[(.*?)\]', content, re.DOTALL)
        if ext_match:
            ext_text = ext_match.group(1)
            ext_paths = re.findall(r'"([^"]+)"', ext_text)
            for ep in ext_paths:
                full_path = ep.replace('res://', str(REPO) + '/')
                catalogs.append(full_path)
    else:
        catalogs.append(str(REPO / "assets" / "data" / "assets" / "map_asset_catalog.json"))

    all_assets = []
    for cat_path in catalogs:
        if os.path.exists(cat_path):
            with open(cat_path, 'r', encoding='utf-8') as f:
                data = json.load(f)
            assets = data.get('assets', [])
            all_assets.extend(assets)
            print(f"  Loaded {len(assets)} assets from {os.path.basename(cat_path)}")
        else:
            print(f"  WARNING: Missing catalog: {cat_path}")

    return all_assets


def main():
    print("=== Effective Catalog Validation ===")

    # 1. Load all effective catalogs
    try:
        all_assets = load_effective_catalogs()
        print(f"\nTotal effective assets: {len(all_assets)}")
    except Exception as e:
        print(f"  FAIL: {e}")
        sys.exit(1)

    # 2. Check effective duplicate asset_ids
    print("\n=== Effective Asset ID Uniqueness ===")
    ids = [a['asset_id'] for a in all_assets]
    seen = set()
    dupes = []
    for aid in ids:
        if aid in seen:
            dupes.append(aid)
        seen.add(aid)
    if dupes:
        errors.append(f"Duplicate asset_ids: {len(set(dupes))}")
        print(f"  FAIL: {len(set(dupes))} duplicate IDs")
        for d in list(set(dupes))[:5]:
            print(f"    {d}")
    else:
        print(f"  PASS: No duplicate asset_ids")

    # 3. Check effective duplicate image paths
    print("\n=== Effective Image Path Uniqueness ===")
    img_paths = [a.get('image', '') for a in all_assets]
    path_seen = set()
    path_dupes = []
    for p in img_paths:
        if p in path_seen:
            path_dupes.append(p)
        path_seen.add(p)
    if path_dupes:
        errors.append(f"Duplicate image paths: {len(set(path_dupes))}")
        print(f"  FAIL: {len(set(path_dupes))} duplicate paths")
    else:
        print(f"  PASS: No duplicate image paths")

    # 4. Check all image paths exist
    print("\n=== Image Path Existence ===")
    missing_images = []
    for a in all_assets:
        img_path = REPO / a.get('image', '')
        if not img_path.exists():
            missing_images.append(a.get('image', ''))
    if missing_images:
        errors.append(f"Missing images: {len(missing_images)}")
        print(f"  FAIL: {len(missing_images)} missing images")
        for m in missing_images[:5]:
            print(f"    {m}")
    else:
        print(f"  PASS: All image paths exist")

    # 5. Check all thumbnail paths exist
    print("\n=== Thumbnail Path Existence ===")
    missing_thumbs = []
    for a in all_assets:
        thumb_path = REPO / a.get('thumbnail', a.get('image', ''))
        if not thumb_path.exists():
            missing_thumbs.append(a.get('thumbnail', a.get('image', '')))
    if missing_thumbs:
        errors.append(f"Missing thumbnails: {len(missing_thumbs)}")
        print(f"  FAIL: {len(missing_thumbs)} missing thumbnails")
    else:
        print(f"  PASS: All thumbnail paths exist")

    # 6. Check RGBA / Alpha
    print("\n=== Alpha Channel Validation ===")
    from PIL import Image
    no_alpha = []
    for a in all_assets:
        img_path = REPO / a.get('image', '')
        if img_path.exists():
            try:
                img = Image.open(img_path)
                if img.mode != 'RGBA':
                    no_alpha.append(a.get('image', ''))
            except Exception as e:
                errors.append(f"Cannot open {a.get('image', '')}: {e}")
    if no_alpha:
        warnings.append(f"Images without RGBA: {len(no_alpha)}")
        print(f"  WARN: {len(no_alpha)} images without RGBA")
    else:
        print(f"  PASS: All images have RGBA")

    # 7. Check source provenance (no Temp paths)
    print("\n=== Source Provenance Validation ===")
    temp_paths = []
    invalid_zip = []
    for a in all_assets:
        src = a.get('source_external_path', '')
        if 'Temp' in src or 'ADMINI~1' in src:
            temp_paths.append(src)
        elif '::' in src:
            # ZIP provenance: check archive exists and member exists
            parts = src.split('::', 1)
            if len(parts) == 2:
                zip_path, member_path = parts
                if not os.path.exists(zip_path):
                    invalid_zip.append(f"Archive missing: {zip_path}")
                else:
                    try:
                        with zipfile.ZipFile(zip_path, 'r') as zf:
                            # Provenance may omit the package root prefix;
                            # resolve by suffix like the importer/repair tools.
                            if repair.resolve_zip_member(zf, member_path) is None:
                                invalid_zip.append(f"Member missing: {member_path} in {zip_path}")
                    except Exception as e:
                        invalid_zip.append(f"ZIP error: {e}")

    if temp_paths:
        errors.append(f"Temp source paths: {len(temp_paths)}")
        print(f"  FAIL: {len(temp_paths)} Temp source paths")
        for t in temp_paths[:3]:
            print(f"    {t}")
    else:
        print(f"  PASS: No Temp source paths")

    if invalid_zip:
        errors.append(f"Invalid ZIP provenance: {len(invalid_zip)}")
        print(f"  FAIL: {len(invalid_zip)} invalid ZIP provenance")
    else:
        print(f"  PASS: All ZIP provenance valid")

    # 8. Check source/output SHA correctness
    print("\n=== SHA256 Validation ===")
    sha_mismatches = []
    for a in all_assets:
        img_path = REPO / a.get('image', '')
        if img_path.exists():
            import hashlib
            with open(img_path, 'rb') as f:
                actual_sha = hashlib.sha256(f.read()).hexdigest()

            output_sha = a.get('output_sha256', '')
            thumb_sha = a.get('thumbnail_source_sha256', '')

            if output_sha and output_sha != actual_sha:
                sha_mismatches.append(f"output_sha mismatch: {a.get('asset_id', '')}")
            if thumb_sha and thumb_sha != actual_sha and a.get('thumbnail', '') == a.get('image', ''):
                sha_mismatches.append(f"thumb_sha mismatch: {a.get('asset_id', '')}")

    if sha_mismatches:
        warnings.append(f"SHA mismatches: {len(sha_mismatches)}")
        print(f"  WARN: {len(sha_mismatches)} SHA mismatches")
    else:
        print(f"  PASS: All SHA256 verified")

    # 9. Check palette_path
    print("\n=== Palette Path Validation ===")
    invalid_palette = []
    for a in all_assets:
        pp = a.get('palette_path', '')
        if not pp:
            invalid_palette.append(a.get('asset_id', ''))
    if invalid_palette:
        errors.append(f"Missing palette_path: {len(invalid_palette)}")
        print(f"  FAIL: {len(invalid_palette)} missing palette_path")
    else:
        print(f"  PASS: All palette_path present")

    # 10. Check placeable
    print("\n=== Placeable Validation ===")
    non_placeable = []
    for a in all_assets:
        if a.get('palette_path', '').startswith('装饰物 1/') and not a.get('placeable', False):
            non_placeable.append(a.get('asset_id', ''))
    if non_placeable:
        warnings.append(f"Non-placeable decorations: {len(non_placeable)}")
        print(f"  WARN: {len(non_placeable)} non-placeable decorations")
    else:
        print(f"  PASS: All decorations placeable")

    # 11. Check map references resolve
    print("\n=== Map Reference Resolution ===")
    # Scan map_editor_workspace for asset_id references
    workspace = REPO / "map_editor_workspace"
    if workspace.exists():
        referenced_ids = set()
        for editor_json in workspace.rglob("*.editor.json"):
            if '_delivery_backups' in str(editor_json):
                continue
            try:
                with open(editor_json, 'r', encoding='utf-8') as f:
                    doc = json.load(f)
                layers = doc.get('layers', {})
                for layer_name, items in layers.items():
                    if isinstance(items, list):
                        for item in items:
                            if isinstance(item, dict):
                                aid = item.get('asset_id', '')
                                if aid:
                                    referenced_ids.add(aid)
            except:
                continue

        # Check if all referenced IDs exist in effective catalog
        effective_ids = set(a['asset_id'] for a in all_assets)
        unresolved = referenced_ids - effective_ids

        if unresolved:
            errors.append(f"Unresolved map references: {len(unresolved)}")
            print(f"  FAIL: {len(unresolved)} unresolved map references")
            for u in list(unresolved)[:5]:
                print(f"    {u}")
        else:
            print(f"  PASS: All map references resolve")
    else:
        print(f"  SKIP: No map_editor_workspace found")

    # 12. Placement metadata validation (P3C Test A/B/C)
    print("\n=== Placement Metadata Validation ===")
    from PIL import Image as _PILImage
    placement_errors = []
    decor_assets = [
        a for a in all_assets
        if str(a.get('palette_path', '')).startswith(('装饰物1/', '装饰物 1/'))
    ]
    for a in decor_assets:
        aid = a.get('asset_id', '')
        fp = a.get('footprint_tiles')
        if (
            not isinstance(fp, list)
            or len(fp) != 2
            or int(fp[0]) <= 0
            or int(fp[1]) <= 0
        ):
            placement_errors.append(f"{aid}: invalid footprint_tiles {fp!r}")
            continue
        anchor = a.get('anchor_px')
        img_path = REPO / str(a.get('image', ''))
        if isinstance(anchor, list) and len(anchor) == 2 and img_path.exists():
            try:
                with _PILImage.open(img_path) as img:
                    w, h = img.size
                if not (0 <= int(anchor[0]) < w and 0 <= int(anchor[1]) < h):
                    placement_errors.append(
                        f"{aid}: anchor_px {anchor} outside image {w}x{h}"
                    )
            except Exception as e:
                placement_errors.append(f"{aid}: cannot check anchor: {e}")
        else:
            placement_errors.append(f"{aid}: missing/invalid anchor_px {anchor!r}")
    if placement_errors:
        errors.append(f"Invalid placement metadata: {len(placement_errors)}")
        print(f"  FAIL: {len(placement_errors)} placement metadata problems")
        for p in placement_errors[:5]:
            print(f"    {p}")
    else:
        print(f"  PASS: {len(decor_assets)} decoration assets have valid footprint/anchor")

    # 13. Package metadata consistency (P3C §25)
    # For every batch entry whose package ships meta/{asset_id}.json, the
    # catalog must carry the source-authoritative footprint/anchor values.
    print("\n=== Package Metadata Consistency ===")
    drift = []
    checked = 0
    by_id = {a.get('asset_id'): a for a in all_assets}
    for a in all_assets:
        if str(a.get('processing', '')) != repair.BATCH_PROCESSING_TAG:
            continue
        if repair.BATCH_SOURCE_HINT.lower() not in str(a.get('source_external_path', '')).lower():
            continue
        res = repair.match_entry_to_source(a)
        if res.get('status') == 'MATCHED_WITH_META':
            checked += 1
            if res.get('changed'):
                drift.append(
                    f"{res['asset_id']} ({res['display_name']}): "
                    f"catalog fp={res.get('old_footprint')} anchor={res.get('old_anchor')} "
                    f"source fp={res.get('new_footprint')} anchor={res.get('new_anchor')}"
                )
    if drift:
        errors.append(f"Package metadata drift: {len(drift)}")
        print(f"  FAIL: {len(drift)} entries drifted from package meta")
        for dline in drift[:5]:
            print(f"    {dline}")
    else:
        print(f"  PASS: {checked} package-backed entries match source meta")

    # 14. Directional footprint regression (P3C §26)
    print("\n=== Directional Footprint Regression ===")
    directional_fixtures = {
        'user.05707157c169287e': ('DF_FL_01', [4, 2]),
        'user.c77774e4a922cfdf': ('DF_FL_02', [2, 4]),
        'user.ec47d69519e0d37c': ('DF_FL_03', [4, 2]),
        'user.fb739cc59ddca306': ('DF_FL_04', [2, 4]),
    }
    directional_errors = []
    for aid, (name, expected_fp) in directional_fixtures.items():
        entry = by_id.get(aid)
        if entry is None:
            directional_errors.append(f"{name}: asset {aid} missing from catalog")
        elif entry.get('footprint_tiles') != expected_fp:
            directional_errors.append(
                f"{name}: footprint {entry.get('footprint_tiles')} != {expected_fp}"
            )
    if directional_errors:
        errors.append(f"Directional footprint regression: {len(directional_errors)}")
        print(f"  FAIL: {len(directional_errors)} directional footprints wrong")
        for dline in directional_errors:
            print(f"    {dline}")
    else:
        print("  PASS: fallen-tree directional footprints preserved")

    # 15. Non-uniform tree footprint regression (P3C §27)
    print("\n=== Non-Uniform Tree Footprint Regression ===")
    tree_fixtures = {
        'user.41dca73743ca7b03': ('DF_ST_01', [3, 3]),
        'user.94895c67f33c404b': ('DF_ST_05', [1, 1]),
        'user.9fa5ec2bbe080598': ('DF_ST_08', [1, 1]),
        'user.ecd243cdec91d662': ('DF_ST_10', [3, 3]),
    }
    tree_errors = []
    observed_fps = set()
    for aid, (name, expected_fp) in tree_fixtures.items():
        entry = by_id.get(aid)
        if entry is None:
            tree_errors.append(f"{name}: asset {aid} missing from catalog")
            continue
        fp = entry.get('footprint_tiles')
        observed_fps.add(tuple(fp) if isinstance(fp, list) else fp)
        if fp != expected_fp:
            tree_errors.append(f"{name}: footprint {fp} != {expected_fp}")
    if len(observed_fps) < 2:
        tree_errors.append(
            f"all checked single trees share one footprint {observed_fps}; "
            "uniform tree footprints indicate importer damage"
        )
    if tree_errors:
        errors.append(f"Non-uniform tree regression: {len(tree_errors)}")
        print(f"  FAIL: {len(tree_errors)} tree footprint problems")
        for tline in tree_errors:
            print(f"    {tline}")
    else:
        print("  PASS: single-tree footprints remain non-uniform and source-accurate")

    # 16. Source-anchor preservation regression (P3C §28)
    print("\n=== Anchor Preservation Regression ===")
    # Expected catalog anchors = source meta anchor converted by the trim
    # offset (source DF_ST_01 [96,224] - [0,19]; DF_FL_01 [160,160] - [4,0]).
    anchor_fixtures = {
        'user.41dca73743ca7b03': ('DF_ST_01', [96, 205]),
        'user.05707157c169287e': ('DF_FL_01', [156, 160]),
    }
    anchor_errors = []
    for aid, (name, expected_anchor) in anchor_fixtures.items():
        entry = by_id.get(aid)
        if entry is None:
            anchor_errors.append(f"{name}: asset {aid} missing from catalog")
        elif entry.get('anchor_px') != expected_anchor:
            anchor_errors.append(
                f"{name}: anchor {entry.get('anchor_px')} != {expected_anchor}"
            )
    if anchor_errors:
        errors.append(f"Anchor preservation regression: {len(anchor_errors)}")
        print(f"  FAIL: {len(anchor_errors)} anchor problems")
        for aline in anchor_errors:
            print(f"    {aline}")
    else:
        print("  PASS: source-derived anchors preserved")

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

    return 0 if not errors else 1


if __name__ == '__main__':
    sys.exit(main())
