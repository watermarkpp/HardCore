#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Scan source ZIPs under C:\\Users\\Administrator\\Desktop\\sucai\\新增
and extract per-asset authoritative metadata.

Priority:
  1. Per-asset meta/{asset_id}.json inside source ZIP
  2. manifest.json metadata
  3. Existing project manual calibration / override

Forbidden:
  - Deriving footprint from PNG height/width
  - Deriving footprint from bottom-contact alpha ratio
"""

from __future__ import annotations

import json
import zipfile
from pathlib import Path, PurePosixPath
from typing import Optional

REPO = Path(__file__).resolve().parents[2]
SOURCE_ROOT = Path(r"C:\Users\Administrator\Desktop\sucai\新增")
CATALOG_PATH = REPO / "assets" / "data" / "assets" / "map_asset_catalog.json"
REPORT_PATH = REPO / "docs" / "mafa_scene_editor" / "new_decor_source_metadata_report.json"


def read_json_from_zip(zf: zipfile.ZipFile, member: str) -> Optional[dict]:
    try:
        return json.loads(zf.read(member).decode("utf-8"))
    except (KeyError, json.JSONDecodeError, UnicodeDecodeError):
        return None


def find_meta_for_member(
    zf: zipfile.ZipFile,
    png_member: str,
    all_members: list[str],
) -> Optional[dict]:
    """
    Given a PNG member path like:
      PackDir/transparent_assets/single_trees/DF_ST_01.png
    Find the corresponding meta:
      PackDir/meta/DF_ST_01.json
    """
    parts = PurePosixPath(png_member).parts

    # Find the package root (everything before transparent_assets/)
    pkg_root = ""
    for i, part in enumerate(parts):
        if part == "transparent_assets":
            pkg_root = "/".join(parts[:i])
            break

    if not pkg_root:
        return None

    # Get the asset stem from the PNG filename
    stem = PurePosixPath(png_member).stem

    # Try exact meta path
    meta_path = f"{pkg_root}/meta/{stem}.json"
    meta = read_json_from_zip(zf, meta_path)
    if meta is not None:
        return meta

    # Fallback: search any */meta/{stem}.json
    for member in all_members:
        if member.endswith(f"/meta/{stem}.json"):
            meta = read_json_from_zip(zf, member)
            if meta is not None:
                return meta

    return None


def scan_zip(zip_path: Path) -> dict:
    """
    Scan a single ZIP and return:
    {
      "zip_path": str,
      "has_manifest": bool,
      "manifest": dict | None,
      "meta_count": int,
      "assets": {
        "transparent_assets/category/file.png": {
          "meta": dict | None,
          "meta_path": str | None,
        }
      }
    }
    """
    result = {
        "zip_path": str(zip_path),
        "has_manifest": False,
        "manifest": None,
        "meta_count": 0,
        "assets": {},
    }

    try:
        with zipfile.ZipFile(zip_path) as zf:
            all_members = zf.namelist()

            # Check for manifest
            for member in all_members:
                if member.endswith("/manifest.json") or member == "manifest.json":
                    result["manifest"] = read_json_from_zip(zf, member)
                    result["has_manifest"] = result["manifest"] is not None
                    break

            # Find all meta files
            meta_files = [m for m in all_members if "/meta/" in m and m.endswith(".json")]
            result["meta_count"] = len(meta_files)

            # Find all transparent_assets PNGs
            for member in all_members:
                if "transparent_assets/" in member and member.endswith(".png"):
                    meta = find_meta_for_member(zf, member, all_members)
                    result["assets"][member] = {
                        "meta": meta,
                        "meta_path": None,
                    }
                    if meta is not None:
                        # Find which meta path was used
                        stem = PurePosixPath(member).stem
                        for m in meta_files:
                            if m.endswith(f"/meta/{stem}.json"):
                                result["assets"][member]["meta_path"] = m
                                break

    except (zipfile.BadZipFile, OSError) as exc:
        result["error"] = str(exc)

    return result


def extract_authoritative_fields(meta: dict) -> dict:
    """Extract the fields we care about from a source meta JSON."""
    result = {}
    for key in [
        "footprint_tiles",
        "anchor",
        "canvas_size",
        "visible_bounds_px",
        "occlusion",
        "default_layer",
        "default_object_role",
        "axis",
        "scene_intent",
        "collision_policy",
        "collision_preset",
        "navigation_policy",
        "placement_clearance_tiles",
        "sort_baseline_tile_offset",
        "sort_baseline_offset_px",
        "content_layer",
        "calibration_status",
        "placeable",
        "tags",
    ]:
        if key in meta:
            result[key] = meta[key]
    return result


def build_source_to_catalog_mapping() -> list[dict]:
    """
    For each current catalog entry from the new batch,
    try to find its source meta in the ZIPs.
    """
    catalog = json.loads(CATALOG_PATH.read_text(encoding="utf-8"))
    assets = catalog.get("assets", [])

    # Get new batch IDs
    pre_commit = "cf4ceb344d7a612104347917c1e32ef0392eeff6"
    import_commit = "c4d260866935132b95a4a2498fe322acf7050e17"

    import subprocess
    pre_raw = subprocess.check_output(
        ["git", "show", f"{pre_commit}:assets/data/assets/map_asset_catalog.json"],
        cwd=str(REPO),
    )
    imp_raw = subprocess.check_output(
        ["git", "show", f"{import_commit}:assets/data/assets/map_asset_catalog.json"],
        cwd=str(REPO),
    )
    pre_ids = {
        str(a.get("asset_id", ""))
        for a in json.loads(pre_raw.decode("utf-8")).get("assets", [])
    }
    imp_ids = {
        str(a.get("asset_id", ""))
        for a in json.loads(imp_raw.decode("utf-8")).get("assets", [])
    }
    batch_ids = imp_ids - pre_ids

    # Scan all ZIPs
    zip_results = {}
    if SOURCE_ROOT.exists():
        for zip_path in sorted(SOURCE_ROOT.rglob("*.zip")):
            scan = scan_zip(zip_path)
            zip_results[str(zip_path)] = scan

    # Build mapping: source_external_path -> source meta
    source_meta_index = {}
    for zip_str, scan in zip_results.items():
        for member, info in scan["assets"].items():
            if info["meta"] is not None:
                # Index by the provenance pattern: zip_path::member
                provenance = f"{zip_str}::{member}"
                source_meta_index[provenance] = info["meta"]
                # Also index by just the member stem for fuzzy matching
                stem = PurePosixPath(member).stem
                source_meta_index[f"stem:{stem}"] = info["meta"]

    # Match catalog entries to source meta
    mappings = []
    for asset in assets:
        asset_id = str(asset.get("asset_id", ""))
        if asset_id not in batch_ids:
            continue

        source_path = str(asset.get("source_external_path", ""))
        display_name = str(asset.get("display_name", ""))

        source_meta = None
        match_method = None

        # Try exact provenance match
        if source_path in source_meta_index:
            source_meta = source_meta_index[source_path]
            match_method = "exact_provenance"
        else:
            # Try stem match
            # Extract stem from source path
            if "::" in source_path:
                member_part = source_path.split("::", 1)[-1]
                stem = PurePosixPath(member_part).stem
                key = f"stem:{stem}"
                if key in source_meta_index:
                    source_meta = source_meta_index[key]
                    match_method = "stem_match"
            elif "/" in source_path or "\\" in source_path:
                stem = Path(source_path).stem
                key = f"stem:{stem}"
                if key in source_meta_index:
                    source_meta = source_meta_index[key]
                    match_method = "stem_match"

        entry = {
            "asset_id": asset_id,
            "display_name": display_name,
            "category": str(asset.get("palette_path", "")),
            "source_external_path": source_path,
            "current_footprint_tiles": asset.get("footprint_tiles"),
            "current_anchor_px": asset.get("anchor_px"),
            "current_occlusion": asset.get("occlusion"),
            "source_meta_found": source_meta is not None,
            "match_method": match_method,
        }

        if source_meta is not None:
            entry["authoritative"] = extract_authoritative_fields(source_meta)
        else:
            entry["authoritative"] = None

        mappings.append(entry)

    return mappings, zip_results


def main():
    mappings, zip_results = build_source_to_catalog_mapping()

    # Summary
    total = len(mappings)
    with_meta = sum(1 for m in mappings if m["source_meta_found"])
    without_meta = total - with_meta

    # Per-ZIP summary
    zip_summary = {}
    for zip_str, scan in zip_results.items():
        zip_name = Path(zip_str).name
        total_pngs = len(scan["assets"])
        with_metas = sum(
            1 for info in scan["assets"].values()
            if info["meta"] is not None
        )
        zip_summary[zip_name] = {
            "total_pngs": total_pngs,
            "with_meta": with_metas,
            "has_manifest": scan["has_manifest"],
            "meta_file_count": scan["meta_count"],
        }

    report = {
        "summary": {
            "total_batch_assets": total,
            "with_source_meta": with_meta,
            "without_source_meta": without_meta,
        },
        "zip_summary": zip_summary,
        "mappings": mappings,
    }

    REPORT_PATH.parent.mkdir(parents=True, exist_ok=True)
    REPORT_PATH.write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )

    print(f"TOTAL_BATCH_ASSETS={total}")
    print(f"WITH_SOURCE_META={with_meta}")
    print(f"WITHOUT_SOURCE_META={without_meta}")
    print(f"ZIPS_SCANNED={len(zip_results)}")
    for name, info in zip_summary.items():
        print(f"  {name}: pngs={info['total_pngs']} meta={info['with_meta']}/{info['total_pngs']} manifest={info['has_manifest']}")
    print(f"WROTE_REPORT={REPORT_PATH}")


if __name__ == "__main__":
    main()
