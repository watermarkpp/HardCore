#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
R3: Restore authoritative geometry from source package meta.

Priority:
  1. Source ZIP per-asset meta (Deep Forest, Carpets)
  2. Manual overrides (cages from visual inspection)
  3. Mark as unresolved (no authoritative data)

bottom_contact algorithm MUST NOT overwrite authoritative footprint_tiles.
"""

from __future__ import annotations

import json
import shutil
import subprocess
import zipfile
from pathlib import Path, PurePosixPath

REPO = Path(__file__).resolve().parents[2]
CATALOG_PATH = REPO / "assets" / "data" / "assets" / "map_asset_catalog.json"
SOURCE_ROOT = Path(r"C:\Users\Administrator\Desktop\sucai\新增")
OVERRIDES_PATH = REPO / "docs" / "mafa_scene_editor" / "manual_footprint_overrides.json"
UNRESOLVED_PATH = REPO / "docs" / "mafa_scene_editor" / "new_decor_geometry_unresolved.json"
BACKUP_DIR = REPO / "docs" / "mafa_scene_editor" / "backups" / "r3_authoritative_geometry"

PRE_IMPORT_BASE = "cf4ceb344d7a612104347917c1e32ef0392eeff6"
IMPORT_COMMIT = "c4d260866935132b95a4a2498fe322acf7050e17"
CATALOG_REL = "assets/data/assets/map_asset_catalog.json"


def read_json(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")


def load_catalog_at(commit):
    raw = subprocess.check_output(
        ["git", "show", f"{commit}:{CATALOG_REL}"],
        cwd=str(REPO),
    )
    return json.loads(raw.decode("utf-8"))


def new_batch_ids():
    pre = load_catalog_at(PRE_IMPORT_BASE)
    imp = load_catalog_at(IMPORT_COMMIT)
    pre_ids = {str(a.get("asset_id", "")) for a in pre.get("assets", [])}
    imp_ids = {str(a.get("asset_id", "")) for a in imp.get("assets", [])}
    return imp_ids - pre_ids


def read_meta_from_zip(zip_path, png_member):
    """Try to find meta/{stem}.json for a given PNG member in a ZIP."""
    try:
        with zipfile.ZipFile(zip_path) as zf:
            all_members = zf.namelist()
            parts = PurePosixPath(png_member).parts
            pkg_root = ""
            for i, part in enumerate(parts):
                if part == "transparent_assets":
                    pkg_root = "/".join(parts[:i])
                    break
            if not pkg_root:
                return None
            stem = PurePosixPath(png_member).stem
            # Try exact path
            meta_path = f"{pkg_root}/meta/{stem}.json"
            try:
                return json.loads(zf.read(meta_path).decode("utf-8"))
            except (KeyError, json.JSONDecodeError):
                pass
            # Fallback: search
            for m in all_members:
                if m.endswith(f"/meta/{stem}.json"):
                    try:
                        return json.loads(zf.read(m).decode("utf-8"))
                    except (json.JSONDecodeError):
                        continue
    except (zipfile.BadZipFile, OSError):
        pass
    return None


def build_source_meta_index():
    """Build index: source_external_path -> meta dict."""
    index = {}
    if not SOURCE_ROOT.exists():
        return index
    for zip_path in sorted(SOURCE_ROOT.rglob("*.zip")):
        try:
            with zipfile.ZipFile(zip_path) as zf:
                all_members = zf.namelist()
                png_members = [m for m in all_members if "transparent_assets/" in m and m.endswith(".png")]
                for member in png_members:
                    meta = read_meta_from_zip(zip_path, member)
                    if meta is not None:
                        provenance = f"{zip_path}::{member}"
                        index[provenance] = meta
                        # Also index by stem
                        stem = PurePosixPath(member).stem
                        index[f"stem:{stem}"] = meta
        except (zipfile.BadZipFile, OSError):
            continue
    return index


def main():
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()

    catalog = read_json(CATALOG_PATH)
    assets = catalog.get("assets", [])
    batch_ids = new_batch_ids()

    # Build source meta index
    source_index = build_source_meta_index()

    # Load manual overrides
    overrides = {}
    if OVERRIDES_PATH.exists():
        ov_data = read_json(OVERRIDES_PATH)
        for ov in ov_data.get("overrides", []):
            overrides[ov["asset_id"]] = ov

    authoritative_count = 0
    manual_override_count = 0
    unresolved_count = 0
    footprint_changed = 0
    unresolved_entries = []

    # Phase 0: Apply manual overrides (regardless of batch_ids)
    for asset in assets:
        asset_id = str(asset.get("asset_id", ""))
        if asset_id in overrides:
            ov = overrides[asset_id]
            new_fp = list(ov["footprint_tiles"])
            old_fp = list(asset.get("footprint_tiles", [1, 1]))
            asset["footprint_tiles"] = new_fp
            asset["visual_footprint_tiles"] = list(new_fp)
            asset["occupancy_footprint_tiles"] = list(new_fp)
            asset["base_footprint_tiles"] = list(new_fp)
            asset["geometry_authority"] = "manual_override"
            asset["footprint_calibration_source"] = "manual_visual_calibration"
            manual_override_count += 1
            if old_fp != new_fp:
                footprint_changed += 1

    for asset in assets:
        asset_id = str(asset.get("asset_id", ""))
        if asset_id not in batch_ids:
            continue
        # Skip if already handled by manual override
        if asset.get("geometry_authority") == "manual_override":
            continue

        source_path = str(asset.get("source_external_path", ""))
        old_fp = list(asset.get("footprint_tiles", [1, 1]))

        # Priority 1: Source meta
        source_meta = source_index.get(source_path)
        if source_meta is None:
            # Try stem match
            if "::" in source_path:
                member_part = source_path.split("::", 1)[-1]
                stem = PurePosixPath(member_part).stem
            else:
                stem = Path(source_path).stem
            source_meta = source_index.get(f"stem:{stem}")

        if source_meta is not None and "footprint_tiles" in source_meta:
            # AUTHORITATIVE: apply source meta
            fp = source_meta["footprint_tiles"]
            new_fp = [max(1, int(fp[0])), max(1, int(fp[1]))]

            asset["footprint_tiles"] = new_fp
            asset["visual_footprint_tiles"] = list(new_fp)
            asset["occupancy_footprint_tiles"] = list(new_fp)
            asset["base_footprint_tiles"] = list(new_fp)
            asset["geometry_authority"] = "source_meta"
            asset["footprint_calibration_source"] = "source_package_meta"

            # Also apply anchor if available
            if "anchor" in source_meta:
                anchor = source_meta["anchor"]
                asset["anchor_px"] = [int(anchor[0]), int(anchor[1])]
                asset["placement_anchor_px"] = [int(anchor[0]), int(anchor[1])]

            # Apply occlusion
            if "occlusion" in source_meta:
                asset["occlusion"] = bool(source_meta["occlusion"])

            # Apply other fields
            for key in ["default_layer", "scene_intent", "axis"]:
                if key in source_meta:
                    asset[key] = source_meta[key]

            authoritative_count += 1
            if old_fp != new_fp:
                footprint_changed += 1
            continue

        # Priority 2: Manual override
        if asset_id in overrides:
            ov = overrides[asset_id]
            new_fp = list(ov["footprint_tiles"])
            asset["footprint_tiles"] = new_fp
            asset["visual_footprint_tiles"] = list(new_fp)
            asset["occupancy_footprint_tiles"] = list(new_fp)
            asset["base_footprint_tiles"] = list(new_fp)
            asset["geometry_authority"] = "manual_override"
            asset["footprint_calibration_source"] = "manual_visual_calibration"
            manual_override_count += 1
            if old_fp != new_fp:
                footprint_changed += 1
            continue

        # Priority 3: Unresolved
        asset["geometry_authority"] = "fallback_unresolved"
        unresolved_count += 1
        unresolved_entries.append({
            "asset_id": asset_id,
            "display_name": str(asset.get("display_name", "")),
            "category": str(asset.get("palette_path", "")),
            "image": str(asset.get("image", "")),
            "current_footprint": asset.get("footprint_tiles"),
            "source_external_path": source_path,
        })

    print(f"AUTHORITATIVE_META_FOUND={authoritative_count}")
    print(f"MANUAL_OVERRIDES={manual_override_count}")
    print(f"UNRESOLVED_GEOMETRY={unresolved_count}")
    print(f"FOOTPRINT_CHANGED={footprint_changed}")

    if not args.apply:
        print("DRY_RUN_OK")
        print("Use --apply to write changes.")
        # Write unresolved report even in dry-run
        write_json(UNRESOLVED_PATH, {
            "count": unresolved_count,
            "entries": unresolved_entries,
        })
        print(f"WROTE_UNRESOLVED={UNRESOLVED_PATH}")
        return

    # Backup
    BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    backup = BACKUP_DIR / "map_asset_catalog.before.json"
    if not backup.exists():
        shutil.copy2(CATALOG_PATH, backup)

    write_json(CATALOG_PATH, catalog)
    write_json(UNRESOLVED_PATH, {
        "count": unresolved_count,
        "entries": unresolved_entries,
    })

    print(f"WROTE_CATALOG={CATALOG_PATH}")
    print(f"WROTE_UNRESOLVED={UNRESOLVED_PATH}")
    print("AUTHORITATIVE_GEOMETRY_APPLY_OK")


if __name__ == "__main__":
    main()
