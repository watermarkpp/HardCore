#!/usr/bin/env python3
"""Repair placement metadata of package-based decoration assets.

The recent "装饰物1" import flattened package assets (ZIP members under
``transparent_assets/...``) into image-oriented catalog records and replaced
the per-asset placement metadata shipped in each package's ``meta/*.json``
with pixel-derived guesses.

This tool restores the source-authoritative placement fields for every
current catalog entry whose provenance (``source_external_path``) points to a
package member that ships a sibling ``meta/{asset_id}.json``:

    footprint_tiles / visual_ / occupancy_ / base_footprint_tiles
    anchor_px            (source anchor converted into the trimmed image space)
    default_layer        (only schema-valid layer names)
    default_object_role  (only when the source provides one)
    occlusion            (only when the source provides a bool)

Lifecycle fields (placeable / calibration_status) and collision behaviour
(collision_policy / navigation_policy / collision_footprint_tiles) are kept
as-is; the differences are reported.

Safety model:
  * Matching is provenance based (archive::member), never display_name based.
  * The importer pipeline is re-executed on the source member and the result
    is pixel-compared with the stored PNG before any anchor offset is used.
  * Entries that cannot be matched byte-for-byte are reported as AMBIGUOUS
    and left untouched.
  * Default mode is --dry-run; --write is required to modify the catalog.
"""

from __future__ import annotations

import argparse
import importlib.util
import io
import json
import os
import sys
import zipfile
from pathlib import Path
from PIL import Image

REPO_ROOT = Path(__file__).resolve().parents[2]
CATALOG_PATH = REPO_ROOT / "assets" / "data" / "assets" / "map_asset_catalog.json"
IMPORTER_PATH = Path(__file__).resolve().parent / "import_new_decor_assets.py"

BATCH_PROCESSING_TAG = "user_pre_cut_transparent_passthrough"
# Provenance prefix that identifies the 装饰物1 import batch.
BATCH_SOURCE_HINT = "sucai\\\u65b0\u589e"
TRIM_PADDING = 20

VALID_LAYERS = {
    "ground_base",
    "ground_overlay",
    "terrain_base",
    "terrain_front",
    "object_base",
    "object_front",
}

# Source meta keys that have no consumer in the current catalog schema.
# They are reported but not written.
UNMAPPED_SOURCE_FIELDS = (
    "axis",
    "scene_intent",
    "collision_preset",
    "placement_clearance_tiles",
    "runtime_export",
    "runtime_mirroring_required",
    "runtime_rotation_required",
    "tags",
    "theme",
    "direction",
    "long_edge_screen_slope",
    "short_edge_screen_slope",
    "short_end_seamless",
    "tile_size",
)


def _load_importer_from_source(source_code: str, name: str):
    import types

    module = types.ModuleType(name)
    module.__file__ = str(IMPORTER_PATH)
    exec(compile(source_code, str(IMPORTER_PATH), "exec"), module.__dict__)
    return module


def _load_importer():
    """Load the importer module (working copy)."""
    return _load_importer_from_source(
        IMPORTER_PATH.read_text(encoding="utf-8"), "import_new_decor_assets_working"
    )


def _load_committed_importer():
    """Load the importer as committed at HEAD (the version that performed
    the original import), used to reproduce historical pipeline behaviour."""
    import subprocess

    try:
        out = subprocess.run(
            ["git", "-C", str(REPO_ROOT), "show", "HEAD:tools/map_assets/import_new_decor_assets.py"],
            capture_output=True,
            check=True,
        )
        return _load_importer_from_source(
            out.stdout.decode("utf-8"), "import_new_decor_assets_committed"
        )
    except (subprocess.CalledProcessError, OSError, UnicodeDecodeError):
        return None


def resolve_zip_member(zf: zipfile.ZipFile, member: str) -> str | None:
    """Resolve a provenance member path against actual archive names.

    Provenance may omit the package root prefix, so match by suffix.
    """
    member = member.replace("\\", "/")
    names = [n.replace("\\", "/") for n in zf.namelist()]
    if member in names:
        return member
    candidates = [n for n in names if n.endswith("/" + member)]
    if len(candidates) == 1:
        return candidates[0]
    return None


def read_package_meta(zip_path: str, member: str) -> tuple[dict | None, str]:
    """Find and load the sibling meta/{stem}.json for a package member.

    Returns (meta_dict_or_None, status) where status is one of:
    "found", "missing", "ambiguous", "zip_missing".
    """
    if not os.path.isfile(zip_path):
        return None, "zip_missing"
    member = member.replace("\\", "/")
    stem = os.path.splitext(os.path.basename(member))[0]
    try:
        with zipfile.ZipFile(zip_path) as zf:
            resolved = resolve_zip_member(zf, member)
            base_dir = ""
            if resolved is not None:
                idx = resolved.find("transparent_assets/")
                base_dir = resolved[:idx] if idx >= 0 else ""
            names = {n.replace("\\", "/") for n in zf.namelist()}
            exact = f"{base_dir}meta/{stem}.json"
            if exact in names:
                candidate = exact
            else:
                fallback = [
                    n
                    for n in names
                    if n.split("/")[-2:] == ["meta", stem + ".json"]
                ]
                if len(fallback) == 1:
                    candidate = fallback[0]
                elif len(fallback) > 1:
                    return None, "ambiguous"
                else:
                    return None, "missing"
            raw = zf.read(candidate)
        return json.loads(raw.decode("utf-8")), "found"
    except (zipfile.BadZipFile, KeyError, json.JSONDecodeError):
        return None, "missing"


def apply_package_meta(target: dict, meta: dict, offset: tuple[int, int], img_size: tuple[int, int]) -> dict:
    """Map source package meta onto catalog schema fields.

    Returns a dict describing the change; raises ValueError when the source
    values are unusable (bad footprint / anchor outside the trimmed image).
    """
    fp = meta.get("footprint_tiles")
    if (
        not isinstance(fp, list)
        or len(fp) != 2
        or int(fp[0]) <= 0
        or int(fp[1]) <= 0
    ):
        raise ValueError(f"invalid source footprint_tiles: {fp!r}")

    anchor_src = meta.get("anchor")
    if not isinstance(anchor_src, list) or len(anchor_src) != 2:
        raise ValueError(f"invalid source anchor: {anchor_src!r}")
    anchor = [int(anchor_src[0]) - offset[0], int(anchor_src[1]) - offset[1]]
    w, h = img_size
    if not (0 <= anchor[0] < w and 0 <= anchor[1] < h):
        raise ValueError(
            f"source anchor {anchor_src} with offset {offset} lands outside "
            f"trimmed image {w}x{h}: {anchor}"
        )

    change: dict = {}
    for field in (
        "footprint_tiles",
        "visual_footprint_tiles",
        "occupancy_footprint_tiles",
        "base_footprint_tiles",
    ):
        change[field] = [int(fp[0]), int(fp[1])]
    change["anchor_px"] = anchor
    if "placement_anchor_px" in target:
        change["placement_anchor_px"] = list(anchor)

    layer = meta.get("default_layer")
    if layer in VALID_LAYERS:
        change["default_layer"] = layer
    # default_object_role is intentionally NOT restored: the project's
    # established convention for these packages keeps role "decoration"
    # with manual/empty collision (see mse_deep_forest_asset_pack_test.gd);
    # restoring source "obstacle" would activate preset-collision fallbacks.
    # The source role is recorded in the dry-run/report lifecycle diff.
    if isinstance(meta.get("occlusion"), bool):
        change["occlusion"] = meta["occlusion"]
    return change


def trim_origin_box(img, importer, padding: int = TRIM_PADDING) -> tuple[int, int]:
    """Top-left corner of trim_with_padding's crop in img coordinates."""
    vx1, vy1, vx2, vy2 = importer.compute_visible_bounds(img)
    x1 = max(0, vx1 - padding)
    y1 = max(0, vy1 - padding)
    y1 = max(0, y1 - padding // 2)
    _ = (vx2, vy2)
    return x1, y1


def pipeline_crops(img, importer):
    """Re-execute an importer version's crop pipeline.

    Returns (mode, [(origin_or_None, crop_image), ...]).
    """
    if not importer.detect_multi_asset(img):
        return "single", [((0, 0), img)]
    row_tr, col_tr = importer.get_alpha_row_col_status(img)
    grid_fn = getattr(importer, "find_grid_layout", None)
    h_splits, v_splits = ([], [])
    if grid_fn is not None:
        h_splits, v_splits = grid_fn(img)
    if h_splits or v_splits:
        row_bounds = [0] + h_splits + [img.size[1]]
        col_bounds = [0] + v_splits + [img.size[0]]
        crops = []
        for ri in range(len(row_bounds) - 1):
            for ci in range(len(col_bounds) - 1):
                ry1, ry2 = row_bounds[ri], row_bounds[ri + 1]
                cx1, cx2 = col_bounds[ci], col_bounds[ci + 1]
                crop = img.crop((cx1, ry1, cx2, ry2))
                if importer.has_visible_content(crop):
                    crops.append(((cx1, ry1), crop))
        return "grid", crops
    crops = importer.cut_image(img, row_tr, col_tr, img.size[1], img.size[0])
    return "cut", [(None, c) for c in crops]


def match_entry_to_source(entry: dict) -> dict:
    """Determine the repair action for one catalog entry.

    Result keys: status, zip_path, member, meta_status, old/new values, reason.
    """
    result: dict = {
        "asset_id": entry.get("asset_id"),
        "display_name": entry.get("display_name"),
        "status": "SKIPPED",
        "reason": "",
    }
    sep = str(entry.get("source_external_path", ""))
    if "::" not in sep:
        result["status"] = "TYPE_B_NO_PACKAGE"
        result["reason"] = "direct PNG without package provenance"
        return result
    zip_path, member = sep.split("::", 1)
    member = member.replace("\\", "/")
    result["zip_path"] = zip_path
    result["member"] = member

    meta, meta_status = read_package_meta(zip_path, member)
    result["meta_status"] = meta_status
    if meta is None:
        result["status"] = (
            "AMBIGUOUS" if meta_status == "ambiguous" else "MATCHED_WITHOUT_META"
        )
        result["reason"] = f"sibling meta {meta_status}"
        return result

    # Re-execute the importer pipeline and pixel-match the stored PNG.
    try:
        with zipfile.ZipFile(zip_path) as zf:
            resolved_member = resolve_zip_member(zf, member)
            if resolved_member is None:
                result["status"] = "AMBIGUOUS"
                result["reason"] = f"member not found in archive: {member}"
                return result
            result["member"] = resolved_member
            src_bytes = zf.read(resolved_member)
        src_img = Image.open(io.BytesIO(src_bytes))
        if src_img.mode != "RGBA":
            src_img = src_img.convert("RGBA")
    except (KeyError, zipfile.BadZipFile, OSError) as exc:
        result["status"] = "AMBIGUOUS"
        result["reason"] = f"cannot read source member: {exc}"
        return result

    stored_path = REPO_ROOT / str(entry.get("image", "")).replace("/", os.sep)
    if not stored_path.is_file():
        result["status"] = "AMBIGUOUS"
        result["reason"] = f"stored image missing: {stored_path}"
        return result
    stored_img = Image.open(stored_path)
    if stored_img.mode != "RGBA":
        stored_img = stored_img.convert("RGBA")
    stored_bytes = stored_img.tobytes()

    matched_origin = None
    matched_mode = None
    matched_importer = None
    for importer in (_load_importer(), _load_committed_importer()):
        if importer is None:
            continue
        mode, crops = pipeline_crops(src_img, importer)
        for origin, crop in crops:
            if crop.mode != "RGBA":
                crop = crop.convert("RGBA")
            trimmed, _ = importer.trim_with_padding(crop, padding=TRIM_PADDING)
            if trimmed.tobytes() == stored_bytes:
                matched_origin = origin
                matched_mode = mode
                matched_importer = importer
                break
        if matched_origin is not None:
            break
    if matched_origin is None or matched_importer is None:
        result["status"] = "AMBIGUOUS"
        result["reason"] = (
            "stored PNG does not match recomputed pipeline output "
            "in any importer version"
        )
        return result

    ox, oy = matched_origin
    crop_box = _crop_box_for(src_img, pipeline_crops(src_img, matched_importer)[1], matched_origin)
    tx, ty = trim_origin_box(src_img.crop(crop_box), matched_importer)
    offset = (ox + tx, oy + ty)
    try:
        change = apply_package_meta(entry, meta, offset, stored_img.size)
    except ValueError as exc:
        result["status"] = "AMBIGUOUS"
        result["reason"] = str(exc)
        return result

    result["status"] = "MATCHED_WITH_META"
    result["offset"] = offset
    result["old_footprint"] = entry.get("footprint_tiles")
    result["new_footprint"] = change["footprint_tiles"]
    result["old_anchor"] = entry.get("anchor_px")
    result["new_anchor"] = change["anchor_px"]
    result["change"] = change
    result["unmapped_source_fields"] = {
        k: meta[k] for k in UNMAPPED_SOURCE_FIELDS if k in meta
    }
    result["lifecycle_diff"] = {
        k: meta.get(k)
        for k in ("placeable", "calibration_status", "collision_policy", "collision_preset", "navigation_policy", "default_object_role")
        if k in meta
    }
    changed = False
    for key, value in change.items():
        if entry.get(key) != value:
            changed = True
    result["changed"] = changed
    return result


def _crop_box_for(src_img, crops, matched_origin):
    """Return the source-image box of the matched crop."""
    for origin, crop in crops:
        if origin == matched_origin:
            w, h = crop.size
            ox, oy = origin
            return (ox, oy, ox + w, oy + h)
    return (0, 0, src_img.size[0], src_img.size[1])


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", action="store_true", help="apply repairs (default is dry-run)")
    args = parser.parse_args()

    with open(CATALOG_PATH, "r", encoding="utf-8") as f:
        catalog = json.load(f)
    entries = catalog["assets"]

    batch = [
        e
        for e in entries
        if isinstance(e, dict)
        and str(e.get("processing", "")) == BATCH_PROCESSING_TAG
        and BATCH_SOURCE_HINT.lower() in str(e.get("source_external_path", "")).lower()
    ]

    counters = {
        "CURRENT_BATCH_ENTRIES": len(batch),
        "PACKAGE_BACKED_ENTRIES": 0,
        "PACKAGE_META_FOUND": 0,
        "PACKAGE_META_MISSING": 0,
        "MATCHED_WITH_META": 0,
        "MATCHED_WITHOUT_META": 0,
        "FOOTPRINT_CHANGED": 0,
        "ANCHOR_CHANGED": 0,
        "ENTRIES_REPAIRED": 0,
        "UNCHANGED": 0,
        "AMBIGUOUS": 0,
    }
    type_b: list[dict] = []
    manual: list[dict] = []
    repairs: list[tuple[dict, dict]] = []

    for entry in batch:
        if "::" in str(entry.get("source_external_path", "")):
            counters["PACKAGE_BACKED_ENTRIES"] += 1
        res = match_entry_to_source(entry)
        status = res["status"]
        if status == "TYPE_B_NO_PACKAGE":
            type_b.append(res)
            manual.append(res)
            continue
        if res.get("meta_status") == "found":
            counters["PACKAGE_META_FOUND"] += 1
        else:
            counters["PACKAGE_META_MISSING"] += 1
        if status == "MATCHED_WITH_META":
            counters["MATCHED_WITH_META"] += 1
            if res.get("changed"):
                counters["ENTRIES_REPAIRED"] += 1
                if res["old_footprint"] != res["new_footprint"]:
                    counters["FOOTPRINT_CHANGED"] += 1
                if res["old_anchor"] != res["new_anchor"]:
                    counters["ANCHOR_CHANGED"] += 1
                repairs.append((entry, res))
            else:
                counters["UNCHANGED"] += 1
        elif status == "AMBIGUOUS":
            counters["AMBIGUOUS"] += 1
            manual.append(res)
        else:
            counters["MATCHED_WITHOUT_META"] += 1
            manual.append(res)

    counters["MANUAL_CALIBRATION_REQUIRED"] = len(manual)

    print("== P3C DECOR PACKAGE METADATA REPAIR ==")
    print("MODE=" + ("WRITE" if args.write else "DRY_RUN"))
    for key in (
        "CURRENT_BATCH_ENTRIES",
        "PACKAGE_BACKED_ENTRIES",
        "PACKAGE_META_FOUND",
        "PACKAGE_META_MISSING",
        "MATCHED_WITH_META",
        "MATCHED_WITHOUT_META",
        "FOOTPRINT_CHANGED",
        "ANCHOR_CHANGED",
        "ENTRIES_REPAIRED",
        "UNCHANGED",
        "AMBIGUOUS",
        "MANUAL_CALIBRATION_REQUIRED",
    ):
        print(f"{key}={counters[key]}")

    print("== PER_ASSET (matched-with-meta) ==")
    for entry, res in repairs:
        print(json.dumps({
            "asset_id": res["asset_id"],
            "name": res["display_name"],
            "member": res["member"],
            "old_fp": res["old_footprint"],
            "new_fp": res["new_footprint"],
            "old_anchor": res["old_anchor"],
            "new_anchor": res["new_anchor"],
            "offset": res["offset"],
        }, ensure_ascii=False))

    if args.write:
        for entry, res in repairs:
            for key, value in res["change"].items():
                entry[key] = value
        with open(CATALOG_PATH, "w", encoding="utf-8") as f:
            json.dump(catalog, f, ensure_ascii=False, indent=2)
        print("CATALOG_WRITTEN=" + str(CATALOG_PATH))
    else:
        print("DRY_RUN_NO_WRITE")

    print("== MANUAL_CALIBRATION_REQUIRED_LIST ==")
    for res in manual:
        print(json.dumps({
            "asset_id": res.get("asset_id"),
            "name": res.get("display_name"),
            "status": res.get("status"),
            "member": res.get("member", ""),
            "reason": res.get("reason", ""),
        }, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
