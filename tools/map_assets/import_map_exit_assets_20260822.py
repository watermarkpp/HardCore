"""Import the eight user map-exit sheets as a deterministic 64-asset pack.

The source directory contains eight 1672x941 RGBA sheets. Each sheet's eight
major alpha components are assigned by centroid to the logical 4x2 slots, so
subjects crossing a grid line remain whole and neighboring subjects cannot be
copied into the output. Each result gets four transparent pixels of padding.
The importer owns only
the exact map-entrance asset directory and explicitly listed catalog records;
it never touches map workspaces or runtime data.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
from io import BytesIO
from pathlib import Path
from typing import Any

import numpy as np
from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = Path(r"C:\Users\Administrator\Desktop\sucai\新增\地图出入口")
ASSET_ROOT = ROOT / "assets/art/maps/_shared/user_palette/decorations_1/map_entrances"
OUTPUT_ROOT = ASSET_ROOT / "new_20260822"
MAP_ENTRANCE_REL = "assets/art/maps/_shared/user_palette/decorations_1/map_entrances"
MAP_ASSET_CATALOG = ROOT / "assets/data/assets/map_asset_catalog.json"
MAP_EXIT_CATALOG = ROOT / "assets/data/assets/map_exit_asset_catalog.json"
DIRECT_CATALOG = ROOT / "assets/data/assets/map_direct_folder_asset_catalog.json"
REPAIR_MANIFEST = ROOT / "assets/data/assets/decoration_alpha_edge_repair_manifest.json"
OVERRIDES = ROOT / "assets/data/expansions/personal_expansion_001/map_asset_overrides.json"
REVIEWS = ROOT / "assets/data/expansions/personal_expansion_001/map_asset_footprint_review_state.json"
IMPORT_MANIFEST = ROOT / "assets/data/assets/map_exit_asset_import_manifest_20260822.json"

PACKAGE_ID = "user_map_exit_pack_20260822_v1"
PALETTE_PATH = "装饰物1/地图出入口"
PIPELINE = "alpha_component_centroid_assignment_rgba_preserve_v2"
ALPHA_THRESHOLD = 16
PADDING_PX = 4
GRID_ROWS = 2
GRID_COLUMNS = 4
CANVAS_SIZE = (1672, 941)
X_EDGES = [0, 418, 836, 1254, 1672]
Y_EDGES = [0, 470, 941]
TILE_SIZE = [64, 32]

SOURCE_SHA256 = {
    1: "0845b5c2ba3376628c225d47eadc254fd2567e8cce4a935c2152b1059b10a3fd",
    2: "81979f27044e9526fc7e81eac0cca2d7ba4a0dde2589d4acfa6bf7f974580f62",
    3: "aa04618fd4ce6f3c8dfd4be33ee6a12b503b02aac44ea0b3f9f60855a81bdae9",
    4: "c9ab3bd0a19cdc6e568854c2798a53adda8e5f132d722e7a1d12be5ff573213a",
    5: "9680613e2a75eb45e3e055c01690866fc2b3ba010518e94ef58c82ae49a478c7",
    6: "195ed7ab84861f736e3dd9f938218bab89d0ecaf71c8aa510e3a787e901e1fac",
    7: "d840095d7c77f9f4e1e1e76c9ff6a68b5292f7978fa8d65a08f30e030beb7775",
    8: "910b8a5ff3ecb422c63294d82543d1abd5229bf45e6dbeb05e7f6bdc3ae66e43",
}

_OLD_ROOT_FILENAMES = tuple(f"{number}.png" for number in range(53, 61))
_OLD_KINDS = (
    "edge_west_far_open",
    "edge_north_far_open",
    "edge_east_near_back",
    "edge_south_near_back",
    "corner_north_open",
    "corner_east_inner_side_open",
    "corner_south_back",
    "corner_west_inner_side_open",
)
_OLD_FIXED_FOLDERS = (
    ("deep_forest", "deep_forest"),
    ("desert_caves", "desert_cave"),
    ("shrines", "shrine"),
    ("temples", "temple"),
)
_OLD_FIXED_ITEMS = tuple(
    (folder, set_id, f"{prefix}_{set_id}_{kind}.png")
    for folder, prefix in _OLD_FIXED_FOLDERS
    for set_id in ("a", "b")
    for kind in _OLD_KINDS
)
OLD_MAP_IMAGE_PATHS = {f"{MAP_ENTRANCE_REL}/{name}" for name in _OLD_ROOT_FILENAMES}
OLD_MAP_IMAGE_PATHS.update(
    f"{MAP_ENTRANCE_REL}/{name}" for _folder, _set_id, name in _OLD_FIXED_ITEMS
)
OLD_MAP_IMAGE_PATHS.update(
    f"{MAP_ENTRANCE_REL}/mse_fixed_64/{folder}/{set_id}/{name}"
    for folder, set_id, name in _OLD_FIXED_ITEMS
)
OLD_DIRECT_IMAGE_PATHS = {f"{MAP_ENTRANCE_REL}/{name}" for name in _OLD_ROOT_FILENAMES}


def sha256(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def read_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"expected object JSON: {path}")
    return value


def write_json(path: Path, value: dict[str, Any]) -> None:
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def normalize_image_path(value: Any) -> str:
    return str(value).replace("\\", "/")


def source_paths() -> list[Path]:
    indexed: list[tuple[int, Path]] = []
    for path in SOURCE_ROOT.glob("*.png"):
        match = re.search(r"\((\d+)\)\.png$", path.name)
        if match is None:
            raise ValueError(f"source file lacks stable sheet index: {path.name}")
        indexed.append((int(match.group(1)), path))
    indexed.sort(key=lambda item: item[0])
    indices = [index for index, _path in indexed]
    if indices != list(range(1, 9)):
        raise ValueError(f"expected source indices 1..8, got {indices}")
    return [path for _index, path in indexed]


def load_sources() -> list[tuple[Path, Image.Image, str]]:
    loaded: list[tuple[Path, Image.Image, str]] = []
    for index, path in enumerate(source_paths(), 1):
        payload = path.read_bytes()
        digest = sha256(payload)
        if digest != SOURCE_SHA256[index]:
            raise ValueError(f"source SHA mismatch {index}: {digest} != {SOURCE_SHA256[index]}")
        with Image.open(BytesIO(payload)) as opened:
            opened.load()
            if opened.mode != "RGBA" or tuple(opened.size) != CANVAS_SIZE:
                raise ValueError(
                    f"source {index}: expected RGBA {CANVAS_SIZE}, got {opened.mode} {opened.size}"
                )
            loaded.append((path, opened.copy(), digest))
    return loaded


def connected_components(mask: np.ndarray) -> list[list[tuple[int, int]]]:
    """Return 8-connected true components using only NumPy/Python."""
    height, width = mask.shape
    visited = np.zeros(mask.shape, dtype=bool)
    components: list[list[tuple[int, int]]] = []
    for raw_y, raw_x in zip(*np.where(mask)):
        y, x = int(raw_y), int(raw_x)
        if visited[y, x]:
            continue
        visited[y, x] = True
        stack = [(y, x)]
        component: list[tuple[int, int]] = []
        while stack:
            cy, cx = stack.pop()
            component.append((cy, cx))
            for ny in range(max(0, cy - 1), min(height, cy + 2)):
                for nx in range(max(0, cx - 1), min(width, cx + 2)):
                    if mask[ny, nx] and not visited[ny, nx]:
                        visited[ny, nx] = True
                        stack.append((ny, nx))
        components.append(component)
    return components


def purify_sheet1_bottom_band(cell: np.ndarray, source_index: int, row: int) -> dict[str, int]:
    """Remove the proven sheet-1 row-2 opaque light background band.

    Pixel profiling shows the opaque band begins below local y=330 and spans
    the cell.  Subject-base pixels in that region always have a dark core.
    Preserve the core plus a six-pixel anti-alias/highlight halo, and clear the
    remaining lower-region pixels.  This follows the subject silhouette rather
    than applying a rectangular crop through the rocks, fire, or floor.
    """
    stats = {
        "band_cleared_pixels": 0,
        "protected_subject_pixels": 0,
        "detached_lower_components": 0,
        "detached_lower_pixels": 0,
    }
    if source_index != 1 or row != 2:
        return stats

    rgb = cell[:, :, :3].astype(np.int16)
    alpha = cell[:, :, 3]
    yy = np.arange(cell.shape[0], dtype=np.int16)[:, None]
    lower_region = yy >= 330
    dark_core = (alpha >= ALPHA_THRESHOLD) & (rgb.mean(axis=2) < 150.0)
    protected = dark_core.copy()
    radius = 6
    padded = np.pad(dark_core, radius, mode="constant", constant_values=False)
    for dy in range(2 * radius + 1):
        for dx in range(2 * radius + 1):
            protected |= padded[dy : dy + cell.shape[0], dx : dx + cell.shape[1]]
    background = (alpha > 0) & lower_region & ~protected
    stats["band_cleared_pixels"] = int(np.count_nonzero(background))
    stats["protected_subject_pixels"] = int(np.count_nonzero((alpha > 0) & lower_region & protected))
    cell[background] = 0
    # Clear isolated lower fragments left by the source's colored band edge.
    # Real subjects are connected above y=330; these fragments are not.
    for component in connected_components(cell[:, :, 3] > 0):
        if min(y for y, _x in component) < 330:
            continue
        stats["detached_lower_components"] += 1
        stats["detached_lower_pixels"] += len(component)
        for y, x in component:
            cell[y, x] = 0
    return stats


def png_bytes(image: Image.Image) -> bytes:
    stream = BytesIO()
    image.save(stream, format="PNG", optimize=False, compress_level=9)
    return stream.getvalue()


def dilate(mask: np.ndarray, radius: int) -> np.ndarray:
    padded = np.pad(mask, radius, mode="constant", constant_values=False)
    result = np.zeros(mask.shape, dtype=bool)
    for dy in range(2 * radius + 1):
        for dx in range(2 * radius + 1):
            result |= padded[dy : dy + mask.shape[0], dx : dx + mask.shape[1]]
    return result


def split_sheet_components(
    source: Image.Image,
    source_index: int,
) -> dict[tuple[int, int], tuple[Image.Image, dict[str, Any]]]:
    """Assign each full-sheet alpha component to one logical 4x2 slot."""
    rgba = np.asarray(source, dtype=np.uint8).copy()
    purification_by_slot: dict[tuple[int, int], dict[str, int]] = {}
    if source_index == 1:
        for column in range(1, GRID_COLUMNS + 1):
            x0, x1 = X_EDGES[column - 1], X_EDGES[column]
            y0, y1 = Y_EDGES[1], Y_EDGES[2]
            cell = rgba[y0:y1, x0:x1].copy()
            purification_by_slot[(2, column)] = purify_sheet1_bottom_band(cell, source_index, 2)
            rgba[y0:y1, x0:x1] = cell

    alpha = rgba[:, :, 3]
    major = [component for component in connected_components(alpha >= ALPHA_THRESHOLD) if len(component) >= 2_000]
    if len(major) != 8:
        sizes = sorted((len(component) for component in major), reverse=True)
        raise ValueError(f"source {source_index}: expected 8 major alpha components, got {len(major)} {sizes}")

    result: dict[tuple[int, int], tuple[Image.Image, dict[str, Any]]] = {}
    for component in major:
        component_y = np.fromiter((point[0] for point in component), dtype=np.int32)
        component_x = np.fromiter((point[1] for point in component), dtype=np.int32)
        centroid_x = float(component_x.mean())
        centroid_y = float(component_y.mean())
        column = min(GRID_COLUMNS, int(centroid_x * GRID_COLUMNS / CANVAS_SIZE[0]) + 1)
        row = min(GRID_ROWS, int(centroid_y * GRID_ROWS / CANVAS_SIZE[1]) + 1)
        slot = (row, column)
        if slot in result:
            raise ValueError(f"source {source_index}: duplicate component assignment for slot {slot}")

        core = np.zeros(alpha.shape, dtype=bool)
        core[component_y, component_x] = True
        keep = (alpha > 0) & dilate(core, 2)
        ys_used, xs_used = np.where(keep)
        bx0, bx1 = int(xs_used.min()), int(xs_used.max()) + 1
        by0, by1 = int(ys_used.min()), int(ys_used.max()) + 1
        cropped = rgba[by0:by1, bx0:bx1].copy()
        cropped_keep = keep[by0:by1, bx0:bx1]
        cropped[~cropped_keep] = 0
        output_array = np.zeros(
            (by1 - by0 + 2 * PADDING_PX, bx1 - bx0 + 2 * PADDING_PX, 4), dtype=np.uint8
        )
        output_array[
            PADDING_PX : PADDING_PX + by1 - by0,
            PADDING_PX : PADDING_PX + bx1 - bx0,
        ] = cropped
        output = Image.fromarray(output_array, mode="RGBA")

        x0, x1 = X_EDGES[column - 1], X_EDGES[column]
        y0, y1 = Y_EDGES[row - 1], Y_EDGES[row]
        outside_cell = core.copy()
        outside_cell[y0:y1, x0:x1] = False
        result[slot] = (
            output,
            {
                "cell_bounds_px": [x0, y0, x1 - x0, y1 - y0],
                "cell_row": row,
                "cell_column": column,
                "cell_alpha_bbox_px": [bx0 - x0, by0 - y0, bx1 - bx0, by1 - by0],
                "source_bounds_px": [bx0, by0, bx1 - bx0, by1 - by0],
                "visible_bounds_px": [PADDING_PX, PADDING_PX, bx1 - bx0, by1 - by0],
                "output_size": list(output.size),
                "alpha_pixels": len(component),
                "low_alpha_pixels": int(np.count_nonzero(keep & (alpha < ALPHA_THRESHOLD))),
                "cell_edge_alpha_pixels": int(np.count_nonzero(outside_cell)),
                "component_centroid_px": [round(centroid_x, 3), round(centroid_y, 3)],
                "component_assignment": "full_sheet_alpha8_centroid_to_4x2",
                "background_purification": purification_by_slot.get(slot, {}),
            },
        )

    expected_slots = {(row, column) for row in range(1, 3) for column in range(1, 5)}
    if set(result) != expected_slots:
        raise ValueError(f"source {source_index}: component slots {sorted(result)} != {sorted(expected_slots)}")
    return result


def make_asset(
    source_path: Path,
    source_digest: str,
    source_index: int,
    row: int,
    column: int,
    image_rel: str,
    image: Image.Image,
    geometry: dict[str, Any],
    output_digest: str,
) -> dict[str, Any]:
    width, height = image.size
    visible = geometry["visible_bounds_px"]
    visible_width, visible_height = int(visible[2]), int(visible[3])
    footprint = [
        (visible_width + TILE_SIZE[0] - 1) // TILE_SIZE[0],
        (visible_height + TILE_SIZE[1] - 1) // TILE_SIZE[1],
    ]
    anchor = [visible[0] + visible_width // 2, visible[1] + visible_height - 1]
    return {
        "asset_id": f"user.map_exit.20260822.s{source_index:02d}_r{row}_c{column}",
        "display_name": f"地图出入口 新 20260822 S{source_index:02d} R{row} C{column}",
        "asset_type": "large_prop",
        "category": "map_entrance",
        "object_class": "map_entrance",
        "theme": "user_palette",
        "image": image_rel,
        "thumbnail": image_rel,
        "canvas_size": [width, height],
        "image_size": [width, height],
        "visible_bounds_px": visible,
        "selection_bounds_px": visible.copy(),
        "anchor_px": anchor,
        "placement_anchor_px": anchor.copy(),
        "door_anchor_px": None,
        "anchor_tile": [0, 0],
        "anchor_mode": "foot_tile",
        "footprint_tiles": footprint.copy(),
        "visual_footprint_tiles": footprint.copy(),
        "occupancy_footprint_tiles": footprint.copy(),
        "base_footprint_tiles": footprint.copy(),
        "collision_footprint_tiles": [0, 0],
        "collision_cells": [],
        "placement_clearance_cells": [],
        "tile_size": TILE_SIZE.copy(),
        "approved_scale": 1.0,
        "logical_scale_level": 0,
        "scale_approved": False,
        "anchor_approved": False,
        "default_layer": "object_base",
        "default_object_role": "terrain",
        "semantic_role": "map_portal",
        "collision_policy": "none",
        "collision_profile_id": "none_visual",
        "navigation_policy": "ignore",
        "manual_collision_expected": False,
        "map_collision_override": "default",
        "collision_authority": "manual_by_user",
        "occlusion": False,
        "content_layer": "personal_expansion",
        "placeable": True,
        "overlap_policy": "placeable",
        "calibration_status": "pending_manual_review",
        "calibration_source": "pending_manual_geometry_v1",
        "geometry_pending_manual": True,
        "palette_path": PALETTE_PATH,
        "source_external_path": str(source_path),
        "source_sha256": source_digest,
        "source_canvas": list(CANVAS_SIZE),
        "source_grid": [row, column],
        "source_cell_bounds_px": geometry["cell_bounds_px"],
        "source_bounds_px": geometry["source_bounds_px"],
        "source_alpha_bbox_px": geometry["cell_alpha_bbox_px"],
        "output_sha256": output_digest,
        "thumbnail_source_sha256": output_digest,
        "processing": {
            "pipeline": PIPELINE,
            "grid": [GRID_ROWS, GRID_COLUMNS],
            "cell_boundaries_x": X_EDGES.copy(),
            "cell_boundaries_y": Y_EDGES.copy(),
            "alpha_threshold": ALPHA_THRESHOLD,
            "padding_px": PADDING_PX,
            "cell_alpha_bbox_px": geometry["cell_alpha_bbox_px"],
            "source_bounds_px": geometry["source_bounds_px"],
            "rgba_pixels_preserved": True,
            "component_assignment": geometry["component_assignment"],
            "component_centroid_px": geometry["component_centroid_px"],
            "background_purification": geometry["background_purification"],
            "low_alpha_pixels": geometry["low_alpha_pixels"],
            "cell_edge_alpha_pixels": geometry["cell_edge_alpha_pixels"],
        },
        "tags": ["new_local_asset", "map_exit", "map_entrance", "pending_manual_review"],
        "editable": True,
        "allows_edge_clipping": True,
        "trigger_on_enter": True,
        "package_id": PACKAGE_ID,
        "package_asset_id": f"s{source_index:02d}_r{row}_c{column}",
        "set_id": f"S{source_index:02d}",
        "placement_kind": "manual_pending",
        "logical_direction": "unknown_pending",
        "screen_position": "manual_pending",
        "view": "front_oblique",
        "opening_visible": None,
        "requires_runtime_rotation": False,
        "allow_flip": False,
        "source_sheet": source_path.name,
        "projection": "orthographic_isometric_2_to_1",
    }


def build_expected() -> tuple[dict[str, Any], dict[str, bytes]]:
    assets: list[dict[str, Any]] = []
    outputs: dict[str, bytes] = {}
    source_records: list[dict[str, Any]] = []
    for source_index, (source_path, source, source_digest) in enumerate(load_sources(), 1):
        components = split_sheet_components(source, source_index)
        source_records.append(
            {
                "source_index": source_index,
                "source_external_path": str(source_path),
                "source_sha256": source_digest,
                "source_canvas": list(CANVAS_SIZE),
                "grid": [GRID_ROWS, GRID_COLUMNS],
                "cell_boundaries_x": X_EDGES.copy(),
                "cell_boundaries_y": Y_EDGES.copy(),
                "alpha_threshold": ALPHA_THRESHOLD,
                "padding_px": PADDING_PX,
                "major_component_count": len(components),
                "component_assignment": "full_sheet_alpha8_centroid_to_4x2",
            }
        )
        for row in range(1, GRID_ROWS + 1):
            for column in range(1, GRID_COLUMNS + 1):
                image_name = f"map_exit_s{source_index:02d}_r{row}_c{column}.png"
                image_rel = (OUTPUT_ROOT.relative_to(ROOT) / image_name).as_posix()
                image, geometry = components[(row, column)]
                payload = png_bytes(image)
                output_digest = sha256(payload)
                outputs[image_rel] = payload
                assets.append(
                    make_asset(
                        source_path,
                        source_digest,
                        source_index,
                        row,
                        column,
                        image_rel,
                        image,
                        geometry,
                        output_digest,
                    )
                )
    if len(assets) != 64 or len({asset["asset_id"] for asset in assets}) != 64:
        raise ValueError(f"expected 64 distinct assets, got {len(assets)}")
    catalog = {
        "asset_schema_version": 2,
        "package_id": PACKAGE_ID,
        "package_version": 1,
        "source_archive": str(SOURCE_ROOT),
        "asset_count": 64,
        "classification": PALETTE_PATH,
        "default_collision_policy": "none",
        "assets": assets,
    }
    manifest = {
        "schema_version": 1,
        "manifest_id": "map_exit_asset_import_20260822_v1",
        "package_id": PACKAGE_ID,
        "palette_path": PALETTE_PATH,
        "source_count": 8,
        "asset_count": 64,
        "grid": {
            "rows": GRID_ROWS,
            "columns": GRID_COLUMNS,
            "x": X_EDGES.copy(),
            "y": Y_EDGES.copy(),
            "alpha_threshold": ALPHA_THRESHOLD,
            "padding_px": PADDING_PX,
        },
        "sources": source_records,
        "assets": [
            {
                "asset_id": asset["asset_id"],
                "image": asset["image"],
                "source_sha256": asset["source_sha256"],
                "output_sha256": asset["output_sha256"],
                "source_grid": asset["source_grid"],
                "source_cell_bounds_px": asset["source_cell_bounds_px"],
                "source_bounds_px": asset["source_bounds_px"],
                "source_alpha_bbox_px": asset["source_alpha_bbox_px"],
                "canvas_size": asset["canvas_size"],
                "visible_bounds_px": asset["visible_bounds_px"],
                "processing": asset["processing"],
            }
            for asset in assets
        ],
        "qa": {
            "distinct_assets": True,
            "nonempty_alpha_assets": True,
            "single_cell_source_mapping": True,
            "rgba_source_preserved_for_retained_pixels": True,
            "manual_review_only": True,
        },
    }
    return {"catalog": catalog, "manifest": manifest}, outputs


def pending_review(asset: dict[str, Any]) -> dict[str, Any]:
    return {
        "anchor_px": asset["anchor_px"],
        "display_name": asset["display_name"],
        "footprint_tiles": asset["footprint_tiles"],
        "image": asset["image"],
        "output_sha256": asset["output_sha256"],
        "palette_path": PALETTE_PATH,
        "source_sha256": asset["source_sha256"],
        "status": "pending_manual_review",
        "calibration_status": "pending_manual_review",
        "manual_collision_expected": False,
    }


def remove_records_by_paths(catalog: dict[str, Any], paths: set[str]) -> tuple[dict[str, Any], set[str]]:
    assets = catalog.get("assets", [])
    if not isinstance(assets, list):
        raise ValueError("catalog assets must be a list")
    removed_ids: set[str] = set()
    kept: list[Any] = []
    for asset in assets:
        if isinstance(asset, dict) and normalize_image_path(asset.get("image", "")) in paths:
            removed_ids.add(str(asset.get("asset_id", "")))
        else:
            kept.append(asset)
    catalog["assets"] = kept
    return catalog, removed_ids


def collect_old_ids() -> dict[str, Any]:
    main = read_json(MAP_ASSET_CATALOG)
    exit_catalog = read_json(MAP_EXIT_CATALOG)
    direct = read_json(DIRECT_CATALOG)
    overrides = read_json(OVERRIDES)
    reviews = read_json(REVIEWS)
    old_main = [
        asset
        for asset in main.get("assets", [])
        if isinstance(asset, dict)
        and normalize_image_path(asset.get("image", "")) in OLD_MAP_IMAGE_PATHS
    ]
    old_exit = [
        asset
        for asset in exit_catalog.get("assets", [])
        if isinstance(asset, dict)
        and str(asset.get("asset_id", "")).startswith("mse.map_exit.")
        and normalize_image_path(asset.get("image", "")) in OLD_MAP_IMAGE_PATHS
    ]
    old_direct = [
        asset
        for asset in direct.get("assets", [])
        if isinstance(asset, dict)
        and normalize_image_path(asset.get("image", "")) in OLD_DIRECT_IMAGE_PATHS
    ]
    if len(old_main) not in (0, 8, 72):
        raise ValueError(f"expected exact old main map-entrance count 0, 8, or 72, got {len(old_main)}")
    if len(old_exit) not in (0, 64):
        raise ValueError(f"expected exact old map-exit count 0 or 64, got {len(old_exit)}")
    if len(old_direct) not in (0, 8):
        raise ValueError(f"expected exact old direct map-entrance count 0 or 8, got {len(old_direct)}")
    old_main_ids = {str(asset.get("asset_id", "")) for asset in old_main}
    old_exit_ids = {str(asset.get("asset_id", "")) for asset in old_exit}
    old_direct_ids = {str(asset.get("asset_id", "")) for asset in old_direct}
    return {
        "main": main,
        "exit": exit_catalog,
        "direct": direct,
        "overrides": overrides,
        "reviews": reviews,
        "old_main_ids": old_main_ids,
        "old_exit_ids": old_exit_ids,
        "old_direct_ids": old_direct_ids,
        "old_ids": old_main_ids | old_exit_ids,
    }


def prune_repair_manifest(manifest: dict[str, Any]) -> tuple[dict[str, Any], int]:
    assets = manifest.get("assets", [])
    if not isinstance(assets, list):
        raise ValueError("repair manifest assets must be a list")
    kept: list[Any] = []
    removed = 0
    for asset in assets:
        if isinstance(asset, dict) and normalize_image_path(asset.get("image", "")) in OLD_MAP_IMAGE_PATHS:
            removed += 1
        else:
            kept.append(asset)
    manifest["assets"] = kept
    manifest["asset_count"] = len(kept)
    manifest["repaired_png_count"] = len(kept)
    manifest["catalog_reference_count"] = sum(
        len(asset.get("catalog_records", [])) for asset in kept if isinstance(asset, dict)
    )
    manifest["changed_visible_edge_pixels"] = sum(
        int(asset.get("changed_visible_edge_pixels", 0)) for asset in kept if isinstance(asset, dict)
    )
    if isinstance(manifest.get("group_counts"), dict):
        manifest["group_counts"]["map_entrances"] = 0
    return manifest, removed


def clear_exact_asset_directory() -> dict[str, int]:
    resolved = ASSET_ROOT.resolve()
    expected = (ROOT / MAP_ENTRANCE_REL).resolve()
    if resolved != expected or resolved.name != "map_entrances":
        raise ValueError(f"refusing delete outside exact map_entrances directory: {resolved}")
    if not ASSET_ROOT.exists() or ASSET_ROOT.is_symlink():
        raise ValueError(f"missing or symlinked target directory: {ASSET_ROOT}")
    files = [path for path in ASSET_ROOT.rglob("*") if path.is_file()]
    outside_output = [path for path in files if OUTPUT_ROOT not in path.parents]
    unexpected = [path for path in outside_output if path.suffix.lower() not in {".png", ".import"}]
    if unexpected:
        raise ValueError(f"unexpected non-PNG/import target contents: {unexpected[:3]}")
    old_png = sum(path.suffix.lower() == ".png" for path in outside_output)
    old_import = sum(path.suffix.lower() == ".import" for path in outside_output)
    if old_png not in (0, 136) or old_import not in (0, 72):
        raise ValueError(f"unexpected old target counts png={old_png} import={old_import}")
    for child in list(ASSET_ROOT.iterdir()):
        if child.is_symlink():
            raise ValueError(f"refusing to delete symlink in target: {child}")
        if child.is_dir():
            shutil.rmtree(child)
        else:
            child.unlink()
    OUTPUT_ROOT.mkdir(parents=True, exist_ok=True)
    return {"old_png": old_png, "old_import": old_import}


def replace_files(expected: dict[str, Any], outputs: dict[str, bytes]) -> dict[str, int]:
    state = collect_old_ids()
    new_assets = expected["catalog"]["assets"]
    new_ids = {str(asset["asset_id"]) for asset in new_assets}
    state["main"], _ = remove_records_by_paths(state["main"], OLD_MAP_IMAGE_PATHS)
    state["direct"], _ = remove_records_by_paths(state["direct"], OLD_DIRECT_IMAGE_PATHS)
    managed_ids = set(state["old_ids"]) | new_ids

    override_map = state["overrides"].get("overrides", {})
    if not isinstance(override_map, dict):
        raise ValueError("overrides must be an object")
    review_items = state["reviews"].get("items", {})
    if not isinstance(review_items, dict):
        raise ValueError("review items must be an object")
    calibrated_new_ids = {
        asset_id
        for asset_id in new_ids
        if asset_id in override_map
        or (
            isinstance(review_items.get(asset_id), dict)
            and str(review_items[asset_id].get("status", "pending_manual_review"))
            not in {"", "pending", "pending_manual_review"}
        )
    }
    if calibrated_new_ids:
        sample = sorted(calibrated_new_ids)[:3]
        raise ValueError(
            "refusing --write because manual calibration already exists for new IDs: "
            f"{sample}"
        )
    state["overrides"]["overrides"] = {
        key: value for key, value in override_map.items() if str(key) not in managed_ids
    }
    state["reviews"]["items"] = {
        key: value for key, value in review_items.items() if str(key) not in managed_ids
    }
    state["reviews"]["items"].update(
        {str(asset["asset_id"]): pending_review(asset) for asset in new_assets}
    )

    repair, removed_repair = prune_repair_manifest(read_json(REPAIR_MANIFEST))
    physical = clear_exact_asset_directory()
    for image_rel, payload in outputs.items():
        path = ROOT / image_rel
        if OUTPUT_ROOT not in path.parents:
            raise ValueError(f"output escaped new_20260822: {path}")
        path.write_bytes(payload)

    write_json(MAP_ASSET_CATALOG, state["main"])
    write_json(DIRECT_CATALOG, state["direct"])
    write_json(MAP_EXIT_CATALOG, expected["catalog"])
    write_json(OVERRIDES, state["overrides"])
    write_json(REVIEWS, state["reviews"])
    write_json(REPAIR_MANIFEST, repair)
    write_json(IMPORT_MANIFEST, expected["manifest"])
    return {
        "old_main": len(state["old_main_ids"]),
        "old_exit": len(state["old_exit_ids"]),
        "old_direct": len(state["old_direct_ids"]),
        "old_repair": removed_repair,
        "old_png": physical["old_png"],
        "old_import": physical["old_import"],
        "new_assets": len(new_assets),
    }


def check(expected: dict[str, Any], outputs: dict[str, bytes]) -> None:
    catalog = read_json(MAP_EXIT_CATALOG)
    assets = catalog.get("assets", [])
    if str(catalog.get("package_id", "")) != PACKAGE_ID or len(assets) != 64:
        raise ValueError("map_exit catalog package/count mismatch")
    expected_by_id = {str(asset["asset_id"]): asset for asset in expected["catalog"]["assets"]}
    if {str(asset.get("asset_id")) for asset in assets} != set(expected_by_id):
        raise ValueError("map_exit catalog IDs differ from deterministic source mapping")
    for asset in assets:
        asset_id = str(asset["asset_id"])
        if asset != expected_by_id[asset_id]:
            raise ValueError(f"catalog record differs from deterministic expected record: {asset_id}")
        path = ROOT / str(asset["image"])
        payload = path.read_bytes() if path.is_file() else b""
        if not path.is_file() or sha256(payload) != str(asset["output_sha256"]):
            raise ValueError(f"output missing/hash mismatch: {asset_id}")
        with Image.open(BytesIO(payload)) as image:
            image.load()
            if image.mode != "RGBA":
                raise ValueError(f"output is not RGBA: {asset_id}")
            alpha = np.asarray(image.getchannel("A"), dtype=np.uint8)
            if not np.any(alpha >= ALPHA_THRESHOLD):
                raise ValueError(f"output has no alpha>=16 pixels: {asset_id}")
            visible = asset["visible_bounds_px"]
            outside = alpha >= ALPHA_THRESHOLD
            outside[
                visible[1] : visible[1] + visible[3],
                visible[0] : visible[0] + visible[2],
            ] = False
            if np.any(outside):
                raise ValueError(f"output alpha bbox exceeds declared bounds: {asset_id}")
    if not IMPORT_MANIFEST.is_file():
        raise ValueError("missing import manifest")
    print(
        f"MAP_EXIT_ASSET_IMPORT_CHECK_PASS assets=64 outputs={len(outputs)} "
        f"x={X_EDGES} y={Y_EDGES} threshold={ALPHA_THRESHOLD} padding={PADDING_PX}"
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true")
    mode.add_argument("--write", action="store_true")
    args = parser.parse_args()
    try:
        expected, outputs = build_expected()
        if args.write:
            print("MAP_EXIT_ASSET_IMPORT_WRITE", replace_files(expected, outputs))
        check(expected, outputs)
        return 0
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"MAP_EXIT_ASSET_IMPORT_FAIL {exc}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
