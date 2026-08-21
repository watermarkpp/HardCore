"""Explicit-grid recut/import for the 2026-08-21 tree and roadblock sheets.

The source sheets are intentionally described in a checked-in manifest.  This
tool never runs the generic transparent-gap detector or keeps a rectangular
cell crop.  It keeps only the alpha-connected component selected by the
declared nominal cell; a component shared by two nominal cells is split by
nearest per-cell centroid seeds.  Every output is rebuilt from a masked tight
bounds plus transparent padding.  ``--write`` is the only mutating mode;
``--check`` is safe to run after import or in CI.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from io import BytesIO
from pathlib import Path
from typing import Any

import cv2
import numpy as np
from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
MANIFEST = Path(__file__).with_name("tree_roadblock_slice_manifest.json")
CATALOG = ROOT / "assets/data/assets/map_asset_catalog.json"
DEEP_FOREST_CATALOG = ROOT / "assets/data/assets/map_deep_forest_asset_catalog.json"
REVIEW_STATE = ROOT / "assets/data/expansions/personal_expansion_001/map_asset_footprint_review_state.json"
OVERRIDES = ROOT / "assets/data/expansions/personal_expansion_001/map_asset_overrides.json"
ASSET_ROOT = ROOT / "assets/art/maps/_shared/user_palette/decorations_1"
TREE_PREFIX = "装饰物1/树木"
ROADBLOCK_PREFIX = "装饰物1/路障"
GENERATED_TAG = "tree_roadblock_explicit_grid_v1"
SEGMENTATION_TAG = "connected_components_dominant_cell_v2"


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, value: dict[str, Any]) -> None:
    # Keep repository JSON LF-normalized even on Windows (the catalogs are
    # large, so an accidental CRLF conversion would obscure the real diff).
    with path.open("w", encoding="utf-8", newline="\n") as handle:
        handle.write(json.dumps(value, ensure_ascii=False, indent=2) + "\n")


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def sha256_text(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def encoded_png_sha(image: Image.Image) -> str:
    buffer = BytesIO()
    image.save(buffer, "PNG")
    return sha256_bytes(buffer.getvalue())


def grid_bounds(length: int, count: int) -> list[int]:
    # Integer half-up rounding keeps every pixel in exactly one cell.
    return [(length * i * 2 + count) // (count * 2) for i in range(count + 1)]


def _component_segments(
    sheet: Image.Image,
    rows: int,
    cols: int,
    threshold: int,
    min_component_area: int,
    padding: int,
    expected_components: int,
) -> list[dict[str, Any]]:
    """Return one masked output per nominal cell.

    The nominal grid is used only to identify a component, never as an output
    crop.  This is important for sheets whose objects touch or slightly cross
    the artist's grid guides.  Roadblocks contain two labels spanning two
    nominal cells; those labels are deterministically partitioned by the
    centroid of their pixels inside each nominal cell.
    """
    rgba = np.asarray(sheet.convert("RGBA"), dtype=np.uint8)
    alpha = rgba[:, :, 3]
    height, width = alpha.shape
    xs = grid_bounds(width, cols)
    ys = grid_bounds(height, rows)
    binary = (alpha > threshold).astype(np.uint8)
    count, labels, stats, _centroids = cv2.connectedComponentsWithStats(binary, 8)
    valid_labels = [
        label
        for label in range(1, count)
        if int(stats[label, cv2.CC_STAT_AREA]) >= min_component_area
    ]
    if len(valid_labels) != expected_components:
        raise ValueError(
            f"{sheet.filename or 'sheet'} connected components={len(valid_labels)}, "
            f"expected={expected_components} at alpha>{threshold} area>={min_component_area}"
        )
    valid_set = set(valid_labels)

    dominant_labels: list[int] = []
    dominant_counts: list[int] = []
    for row in range(rows):
        for col in range(cols):
            cell_labels = labels[ys[row]:ys[row + 1], xs[col]:xs[col + 1]]
            counts = np.bincount(cell_labels.reshape(-1), minlength=count)
            label = max(valid_labels, key=lambda candidate: (int(counts[candidate]), -candidate))
            pixels = int(counts[label])
            if pixels <= 0:
                raise ValueError(f"empty dominant component at row={row + 1} col={col + 1}")
            dominant_labels.append(int(label))
            dominant_counts.append(pixels)

    grouped: dict[int, list[int]] = {}
    for cell_index, label in enumerate(dominant_labels):
        grouped.setdefault(label, []).append(cell_index)
    if set(grouped) != valid_set:
        missing = sorted(valid_set - set(grouped))
        raise ValueError(f"unassigned connected components: {missing}")

    target_masks: list[np.ndarray] = []
    for cell_index, label in enumerate(dominant_labels):
        cells_for_label = grouped[label]
        component_mask = labels == label
        if len(cells_for_label) == 1:
            target_masks.append(component_mask)
            continue

        # A merged label is split only within that label.  Seeds are the
        # per-cell centroids requested by the source-grid contract, so no
        # foreground pixel from an unrelated component can enter this mask.
        seeds: list[tuple[float, float]] = []
        for seed_cell in cells_for_label:
            seed_row, seed_col = divmod(seed_cell, cols)
            within_cell = component_mask.copy()
            within_cell[:ys[seed_row], :] = False
            within_cell[ys[seed_row + 1]:, :] = False
            within_cell[:, :xs[seed_col]] = False
            within_cell[:, xs[seed_col + 1]:] = False
            seed_y, seed_x = np.where(within_cell)
            if len(seed_x) == 0:
                raise ValueError(
                    f"duplicate component {label} has no seed pixels in cell "
                    f"row={seed_row + 1} col={seed_col + 1}"
                )
            seeds.append((float(seed_x.mean()), float(seed_y.mean())))
        component_y, component_x = np.where(component_mask)
        coordinates = np.column_stack((component_x, component_y)).astype(np.float64)
        seed_array = np.asarray(seeds, dtype=np.float64)
        distance = ((coordinates[:, None, :] - seed_array[None, :, :]) ** 2).sum(axis=2)
        assignment = np.argmin(distance, axis=1)
        seed_position = cells_for_label.index(cell_index)
        target = np.zeros_like(component_mask)
        selected = assignment == seed_position
        target[component_y[selected], component_x[selected]] = True
        # A thin bridge can leave a few detached fringe islands on the wrong
        # side of the nearest-seed boundary.  Keep the source component's
        # meaningful islands and discard only sub-components below the same
        # area floor used for source connected-component filtering.
        sub_count, sub_labels, sub_stats, _sub_centroids = cv2.connectedComponentsWithStats(target.astype(np.uint8), 8)
        for sub_label in range(1, sub_count):
            if int(sub_stats[sub_label, cv2.CC_STAT_AREA]) < min_component_area:
                target[sub_labels == sub_label] = False
        target_masks.append(target)

    results: list[dict[str, Any]] = []
    for cell_index, target_mask in enumerate(target_masks):
        row, col = divmod(cell_index, cols)
        target_y, target_x = np.where(target_mask)
        if len(target_x) == 0:
            raise ValueError(f"empty segmented target row={row + 1} col={col + 1}")
        x1, x2 = int(target_x.min()), int(target_x.max()) + 1
        y1, y2 = int(target_y.min()), int(target_y.max()) + 1
        target_crop = rgba[y1:y2, x1:x2].copy()
        crop_mask = target_mask[y1:y2, x1:x2]
        target_crop[:, :, :3][~crop_mask] = 0
        target_crop[:, :, 3] = np.where(crop_mask, target_crop[:, :, 3], 0)
        canvas = np.zeros((y2 - y1 + 2 * padding, x2 - x1 + 2 * padding, 4), dtype=np.uint8)
        canvas[padding:padding + y2 - y1, padding:padding + x2 - x1] = target_crop
        output = Image.fromarray(canvas, mode="RGBA")
        cell_box = (xs[col], ys[row], xs[col + 1], ys[row + 1])
        source_edge_touch: list[str] = []
        if x1 <= cell_box[0]:
            source_edge_touch.append("left")
        if y1 <= cell_box[1]:
            source_edge_touch.append("top")
        if x2 >= cell_box[2]:
            source_edge_touch.append("right")
        if y2 >= cell_box[3]:
            source_edge_touch.append("bottom")
        results.append({
            "output": output,
            "visible": (padding, padding, x2 - x1, y2 - y1),
            "cell_box": cell_box,
            "grid_edge_touch": source_edge_touch,
            "output_mask_edge_touch": [],
            "component_label": dominant_labels[cell_index],
            "component_count": len(valid_labels),
            "component_area": int(stats[dominant_labels[cell_index], cv2.CC_STAT_AREA]),
            "dominant_cell_pixels": dominant_counts[cell_index],
            "duplicate_component_cells": [
                {"row": index // cols + 1, "col": index % cols + 1}
                for index in grouped[dominant_labels[cell_index]]
            ],
            "segmentation_method": SEGMENTATION_TAG if len(grouped[dominant_labels[cell_index]]) == 1 else SEGMENTATION_TAG + "_nearest_seed",
        })
    return results


def initial_geometry(output: Image.Image, visible: tuple[int, int, int, int], blocking: bool) -> dict[str, Any]:
    # These are deliberately temporary defaults for the manual footprint
    # calibrator.  They are not review-state or override writes.
    w, h = output.size
    vx, vy, vw, vh = visible
    anchor = [max(0, min(w - 1, vx + vw // 2)), max(0, min(h - 1, vy + vh))]
    footprint = [1, 1]
    return {
        "canvas_size": [w, h],
        "image_size": [w, h],
        "visible_bounds_px": [vx, vy, vw, vh],
        "ground_contact_bounds_px": [vx, max(0, vy + vh - 8), vw, min(8, vh)],
        "anchor_px": anchor,
        "placement_anchor_px": anchor.copy(),
        "anchor_tile": [0, 0],
        "anchor_mode": "foot_tile",
        "footprint_tiles": footprint.copy(),
        "visual_footprint_tiles": footprint.copy(),
        "occupancy_footprint_tiles": footprint.copy(),
        "base_footprint_tiles": footprint.copy(),
        "collision_footprint_tiles": footprint.copy() if blocking else [0, 0],
        "tile_size": [64, 32],
        "grounding_policy_id": "manual_pending_explicit_grid_v1",
        "grounding_calibration_method": "pending_manual_review",
        "footprint_calibration_source": "pending_manual_footprint_review",
    }


def make_entry(sheet: dict[str, Any], source: Path, source_rel: str, source_sha: str, row: int, col: int, output: Image.Image, visible: tuple[int, int, int, int], cell_box: tuple[int, int, int, int], edge_touch: list[str], image_rel: str) -> dict[str, Any]:
    kind = str(sheet["kind"])
    category = str(sheet["source_category"])
    blocking = kind == "roadblock" or category in {"树", "倒木", "树墩"}
    ground = category in {"草", "蘑菇"}
    id_seed = f"{GENERATED_TAG}|{source_rel}|{source_sha}|r{row + 1:02d}c{col + 1:02d}"
    asset_id = "user." + sha256_text(id_seed)[:16]
    stem = f"{('roadblock' if kind == 'roadblock' else 'tree')}_new_20260821_s{int(sheet.get('sheet_index', 0)):02d}_r{row + 1:02d}_c{col + 1:02d}"
    palette_path = f"{ROADBLOCK_PREFIX}/新增" if kind == "roadblock" else f"{TREE_PREFIX}/新增/{category}"
    geometry = initial_geometry(output, visible, blocking)
    output_sha = encoded_png_sha(output)
    entry: dict[str, Any] = {
        "asset_id": asset_id,
        "display_name": f"新增{'路障' if kind == 'roadblock' else '树木'}20260821_{category}_s{int(sheet.get('sheet_index', 0)):02d}_r{row + 1:02d}_c{col + 1:02d}",
        "asset_type": "large_prop",
        "category": "obstacle" if kind == "roadblock" else "tree",
        "object_class": "obstacle" if kind == "roadblock" else "tree",
        "theme": "user_palette",
        "image": image_rel,
        "thumbnail": image_rel,
    }
    entry.update(geometry)
    entry.update({
        "approved_scale": 1.0,
        "logical_scale_level": 0,
        "scale_approved": False,
        "anchor_approved": False,
        "default_layer": "ground_overlay" if ground else "object_base",
        "default_object_role": "decoration" if ground else "obstacle",
        "collision_policy": "none" if ground else "solid_footprint",
        "collision_profile_id": "none_visual" if ground else "solid_logical_footprint",
        "navigation_policy": "ignore" if ground else "block_player_and_monster",
        "occlusion": not ground,
        "content_layer": "personal_expansion",
        "placeable": True,
        "calibration_status": "placeable",
        "calibration_source": "pending_manual_footprint_review",
        "geometry_pending_manual": True,
        "palette_path": palette_path,
        "source_external_path": str(source),
        "source_sheet_relative_path": source_rel,
        "source_sheet_sha256": source_sha,
        "source_cell": {"row": row + 1, "col": col + 1, "rows": int(sheet["rows"]), "cols": int(sheet["cols"])},
        "source_cell_bounds_px": [cell_box[0], cell_box[1], cell_box[2] - cell_box[0], cell_box[3] - cell_box[1]],
        "grid_edge_touch": edge_touch,
        "source_sha256": source_sha,
        "output_sha256": output_sha,
        "thumbnail_source_sha256": output_sha,
        "processing": GENERATED_TAG,
        "tags": ["user_source", "装饰物1", "树木" if kind == "tree" else "路障", category, GENERATED_TAG],
        "editable": True,
        "allows_edge_clipping": False,
        "semantic_role": "",
        "trigger_on_enter": False,
    })
    return entry


def load_entries(manifest: dict[str, Any]) -> tuple[list[dict[str, Any]], dict[str, Image.Image]]:
    entries: list[dict[str, Any]] = []
    images: dict[str, Image.Image] = {}
    for index, raw in enumerate(manifest["sheets"], start=1):
        sheet = dict(raw)
        sheet["sheet_index"] = index
        source = Path(manifest["source_roots"][sheet["kind"]]) / str(sheet["relative_path"])
        if not source.exists():
            raise FileNotFoundError(source)
        image = Image.open(source).convert("RGBA")
        expected = int(sheet["rows"]) * int(sheet["cols"])
        expected_components = int(sheet.get("expected_components", expected))
        source_sha = sha256_file(source)
        sheet_start = len(entries)
        segments = _component_segments(
            image,
            int(sheet["rows"]),
            int(sheet["cols"]),
            int(manifest["alpha_threshold"]),
            int(manifest["min_component_area"]),
            int(manifest["padding_px"]),
            expected_components,
        )
        for row in range(int(sheet["rows"])):
            for col in range(int(sheet["cols"])):
                segment = segments[row * int(sheet["cols"]) + col]
                output = segment["output"]
                visible = segment["visible"]
                cell_box = segment["cell_box"]
                edge_touch = segment["grid_edge_touch"]
                if output.mode != "RGBA" or output.getchannel("A").getbbox() is None:
                    raise ValueError(f"empty output: {source} r{row + 1} c{col + 1}")
                output_subdir = Path("barricades/新增") if sheet["kind"] == "roadblock" else Path("trees/新增") / Path(sheet["source_category"])
                image_rel = (Path("assets/art/maps/_shared/user_palette/decorations_1") / output_subdir / f"{('roadblock' if sheet['kind'] == 'roadblock' else 'tree')}_new_20260821_s{index:02d}_r{row + 1:02d}_c{col + 1:02d}.png").as_posix()
                entry = make_entry(sheet, source, str(sheet["relative_path"]), source_sha, row, col, output, visible, cell_box, edge_touch, image_rel)
                entry.update({key: value for key, value in segment.items() if key not in {"output", "visible", "cell_box", "grid_edge_touch"}})
                entries.append(entry)
                images[image_rel] = output
        if len(entries) - sheet_start != expected:
            raise AssertionError(f"sheet produced {len(entries) - sheet_start} cells, expected {expected}: {source}")
    return entries, images


def catalog_entries() -> tuple[dict[str, Any], list[dict[str, Any]]]:
    catalog = read_json(CATALOG)
    return catalog, list(catalog.get("assets", []))


def validate_entries(catalog: dict[str, Any], deep_forest_catalog: dict[str, Any], generated: list[dict[str, Any]], images: dict[str, Image.Image]) -> list[str]:
    errors: list[str] = []
    all_assets = list(catalog.get("assets", []))
    ids = [str(a.get("asset_id", "")) for a in all_assets]
    paths = [str(a.get("image", "")) for a in all_assets]
    if len(ids) != len(set(ids)):
        errors.append("duplicate asset_id in main catalog")
    if len(paths) != len(set(paths)):
        errors.append("duplicate image in main catalog")
    trees = [a for a in generated if str(a.get("palette_path", "")).startswith(TREE_PREFIX + "/新增/")]
    roadblocks = [a for a in generated if str(a.get("palette_path", "")).startswith(ROADBLOCK_PREFIX + "/新增")]
    if len(trees) != 128:
        errors.append(f"expected 128 generated tree assets, got {len(trees)}")
    if len(roadblocks) != 16:
        errors.append(f"expected 16 generated roadblock assets, got {len(roadblocks)}")
    for asset in generated:
        image_rel = str(asset.get("image", ""))
        if image_rel not in images:
            errors.append(f"missing generated image object: {image_rel}")
            continue
        image = images[image_rel]
        alpha = image.getchannel("A")
        if image.mode != "RGBA" or alpha.getbbox() is None:
            errors.append(f"invalid transparent output: {image_rel}")
        alpha_values = list(alpha.getdata())
        if min(alpha_values) != 0 or max(alpha_values) <= 0:
            errors.append(f"invalid alpha range (must include 0 and >0): {image_rel}")
        cell_bounds = asset.get("source_cell_bounds_px", [])
        if len(cell_bounds) != 4 or min(int(v) for v in cell_bounds) < 0:
            errors.append(f"invalid source cell bounds: {image_rel}")
        edge_touch = asset.get("grid_edge_touch", [])
        if not isinstance(edge_touch, list) or any(v not in ["left", "top", "right", "bottom"] for v in edge_touch):
            errors.append(f"invalid grid edge risk record: {image_rel}")
        if asset.get("output_mask_edge_touch", ["invalid"]) != []:
            errors.append(f"segmented mask touches output edge: {image_rel}")
        if not str(asset.get("segmentation_method", "")).startswith(SEGMENTATION_TAG):
            errors.append(f"wrong segmentation method: {image_rel}")
        output_path = ROOT / image_rel
        if output_path.is_file() and sha256_file(output_path) != str(asset.get("output_sha256", "")):
            errors.append(f"output hash mismatch: {image_rel}")
        if str(asset.get("source_sha256", "")) != str(asset.get("source_sheet_sha256", "")):
            errors.append(f"source hash mismatch: {asset.get('asset_id')}")
        if not bool(asset.get("geometry_pending_manual", False)) or bool(asset.get("anchor_approved", True)) or bool(asset.get("scale_approved", True)):
            errors.append(f"geometry not pending manual review: {asset.get('asset_id')}")
    old_tree = [a for a in all_assets if str(a.get("palette_path", "")).startswith(TREE_PREFIX) and not str(a.get("palette_path", "")).startswith(TREE_PREFIX + "/新增/")]
    old_tree.extend(a for a in deep_forest_catalog.get("assets", []) if str(a.get("palette_path", "")).startswith(TREE_PREFIX))
    if any(bool(a.get("placeable", True)) for a in old_tree):
        errors.append("old tree asset remains placeable")
    overrides = read_json(OVERRIDES).get("overrides", {})
    for asset in old_tree:
        change = overrides.get(str(asset.get("asset_id", "")), {})
        effective_placeable = change.get("placeable", asset.get("placeable", False))
        if bool(effective_placeable):
            errors.append(f"old tree effective asset remains placeable: {asset.get('asset_id')}")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", type=Path, default=MANIFEST)
    parser.add_argument("--write", action="store_true", help="write PNGs and catalog")
    parser.add_argument("--check", action="store_true", help="validate existing generated outputs/catalog")
    args = parser.parse_args()
    manifest = read_json(args.manifest)
    generated, images = load_entries(manifest)
    catalog, before_assets = catalog_entries()
    deep_forest_catalog = read_json(DEEP_FOREST_CATALOG)
    existing_by_id = {str(a.get("asset_id")): a for a in before_assets}
    existing_by_image = {str(a.get("image")): a for a in before_assets}
    if args.write:
        desired_ids = {str(entry["asset_id"]) for entry in generated}
        protected_ids: set[str] = set()
        for protected_path in (REVIEW_STATE, OVERRIDES):
            if protected_path.exists():
                protected = read_json(protected_path)
                items = protected.get("items", protected.get("overrides", {}))
                if isinstance(items, dict):
                    protected_ids.update(str(key) for key in items)
        for entry in generated:
            old = existing_by_id.get(str(entry["asset_id"])) or existing_by_image.get(str(entry["image"]))
            if old is not None and old != entry:
                if str(old.get("processing", "")) != GENERATED_TAG or str(entry["asset_id"]) in protected_ids:
                    raise SystemExit(f"refusing to replace existing generated/calibrated entry: {entry['asset_id']}")
                old_path = ROOT / str(old.get("image", ""))
                allowed_roots = [(ASSET_ROOT / "trees" / "新增").resolve(), (ASSET_ROOT / "barricades" / "新增").resolve()]
                if not any(old_path.resolve().is_relative_to(root) for root in allowed_roots):
                    raise SystemExit(f"refusing to remove non-generated output: {old_path}")
                if old_path.exists():
                    old_path.unlink()
                catalog["assets"].remove(old)
                existing_by_id.pop(str(old.get("asset_id")), None)
                existing_by_image.pop(str(old.get("image")), None)
        # Hide all existing tree entries without deleting their IDs or files.
        hidden = 0
        for source_catalog in (catalog, deep_forest_catalog):
            for asset in source_catalog["assets"]:
                palette = str(asset.get("palette_path", ""))
                if palette.startswith(TREE_PREFIX) and not palette.startswith(TREE_PREFIX + "/新增/") and bool(asset.get("placeable", False)):
                    asset["placeable"] = False
                    hidden += 1
        override_payload = read_json(OVERRIDES)
        overrides = override_payload.get("overrides", {})
        old_tree_ids = [
            str(asset.get("asset_id", ""))
            for source_catalog in (catalog, deep_forest_catalog)
            for asset in source_catalog.get("assets", [])
            if str(asset.get("palette_path", "")).startswith(TREE_PREFIX)
            and not str(asset.get("palette_path", "")).startswith(TREE_PREFIX + "/新增/")
        ]
        if len(old_tree_ids) != 118:
            raise SystemExit(f"expected 118 old tree IDs before override delete, got {len(old_tree_ids)}")
        for asset_id in old_tree_ids:
            change = overrides.get(asset_id)
            if not isinstance(change, dict):
                raise SystemExit(f"missing old tree override: {asset_id}")
            change["placeable"] = False
            overrides[asset_id] = change
        override_payload["overrides"] = overrides
        for image_rel, image in images.items():
            path = ROOT / image_rel
            path.parent.mkdir(parents=True, exist_ok=True)
            if path.exists():
                existing = Image.open(path).convert("RGBA")
                if existing.size != image.size or existing.tobytes() != image.tobytes():
                    if str(path.resolve()).startswith(str((ASSET_ROOT / "trees" / "新增").resolve())) or str(path.resolve()).startswith(str((ASSET_ROOT / "barricades" / "新增").resolve())):
                        path.unlink()
                    else:
                        raise SystemExit(f"refusing to overwrite existing output: {path}")
                else:
                    continue
            image.save(path, "PNG")
        existing_ids = {str(a.get("asset_id")) for a in catalog["assets"]}
        existing_images = {str(a.get("image")) for a in catalog["assets"]}
        for entry in generated:
            if entry["asset_id"] not in existing_ids and entry["image"] not in existing_images:
                catalog["assets"].append(entry)
                existing_ids.add(entry["asset_id"])
                existing_images.add(entry["image"])
        write_json(CATALOG, catalog)
        write_json(DEEP_FOREST_CATALOG, deep_forest_catalog)
        write_json(OVERRIDES, override_payload)
        _print_sheet_report(generated)
        print(f"wrote generated={len(generated)} hidden_old_trees={hidden}")
        return 0
    if not args.check:
        parser.error("choose --write or --check")
    actual_generated = [a for a in catalog.get("assets", []) if str(a.get("processing", "")) == GENERATED_TAG]
    missing_images = {str(a.get("image")): a for a in actual_generated if not (ROOT / str(a.get("image", ""))).exists()}
    if missing_images:
        print("missing generated PNGs:", sorted(missing_images))
        return 1
    errors = validate_entries(catalog, deep_forest_catalog, actual_generated, {str(a.get("image")): Image.open(ROOT / str(a.get("image"))).convert("RGBA") for a in actual_generated})
    if errors:
        print("\n".join(errors))
        return 1
    _print_sheet_report(actual_generated)
    print("PASS generated_tree=128 generated_roadblock=16 old_tree_placeable=0")
    return 0


def _print_sheet_report(entries: list[dict[str, Any]]) -> None:
    grouped: dict[str, list[dict[str, Any]]] = {}
    for entry in entries:
        grouped.setdefault(str(entry.get("source_sheet_relative_path", "")), []).append(entry)
    for source, items in grouped.items():
        component_counts = sorted({int(item.get("component_count", 0)) for item in items})
        duplicate_cells = sum(1 for item in items if len(item.get("duplicate_component_cells", [])) > 1)
        edge_risk = sum(1 for item in items if item.get("grid_edge_touch"))
        output_edge = sum(1 for item in items if item.get("output_mask_edge_touch"))
        print(
            f"sheet={source} objects={len(items)} components={component_counts} "
            f"duplicate_seed_cells={duplicate_cells} source_edge_touch={edge_risk} "
            f"output_edge_touch={output_edge}"
        )


if __name__ == "__main__":
    raise SystemExit(main())
