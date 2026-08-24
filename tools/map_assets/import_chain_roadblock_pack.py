"""Import the two transparent chain-fence sheets as one deterministic asset pack.

The source contract is deliberately narrow: both source files, their SHA-256
values, and their RGBA dimensions are fixed.  Alpha values >= 8 are projected
onto the x axis and must form exactly four wide contiguous runs per sheet.  A
run is cropped to its alpha>=8 bounding box, copied without changing any RGBA
pixel, and surrounded by four transparent pixels on every side.

``--check`` is read-only and regenerates the expected outputs in memory.
``--write`` writes only the eight owned PNGs and the independent extension
catalog; it never appends to the main catalog.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from io import BytesIO
from pathlib import Path
from typing import Any

import numpy as np
from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
CATALOG_PATH = ROOT / "assets/data/assets/map_chain_roadblock_asset_catalog.json"
OUTPUT_ROOT = ROOT / "assets/art/maps/_shared/user_palette/decorations_1/barricades/chain_fence_20260821"
PALETTE_PATH = "装饰物1/路障"
PACKAGE_ID = "mse_chain_roadblock_pack_20260822_v1"
PIPELINE = "alpha_x_run_bbox_rgba_preserve_v1"
ALPHA_THRESHOLD = 8
PADDING_PX = 4
TILE_SIZE = [64, 32]
FOOTPRINT_UNIT_PX = 64

SOURCE_SPECS: tuple[dict[str, Any], ...] = (
    {
        "path": Path(r"C:\Users\Administrator\Downloads\ChatGPT Image 2026年8月21日 23_52_30.png"),
        "sha256": "a42752c5ca3cd095eeef804b2509de792f467973bcf524b580bb1cd0b6018dc1",
        "stable_start": 1,
    },
    {
        "path": Path(r"C:\Users\Administrator\Downloads\ChatGPT Image 2026年8月22日 00_00_52.png"),
        "sha256": "0d84c91b295ca7a0566f1ce92d65c782412894431ef0aa4cffc155af8fdf8022",
        "stable_start": 5,
    },
)


def sha256_bytes(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def sha256_file(path: Path) -> str:
    return sha256_bytes(path.read_bytes())


def png_bytes(image: Image.Image) -> bytes:
    buffer = BytesIO()
    # Explicit encoder options make output bytes reproducible across runs.
    image.save(buffer, format="PNG", optimize=False, compress_level=9)
    return buffer.getvalue()


def read_source(spec: dict[str, Any]) -> tuple[Image.Image, str]:
    path = Path(spec["path"])
    if not path.is_file():
        raise ValueError(f"missing source: {path}")
    payload = path.read_bytes()
    actual_sha = sha256_bytes(payload)
    if actual_sha != str(spec["sha256"]):
        raise ValueError(
            f"source SHA mismatch: {path}\n"
            f"expected={spec['sha256']} actual={actual_sha}"
        )
    with Image.open(BytesIO(payload)) as opened:
        opened.load()
        if opened.mode != "RGBA":
            raise ValueError(f"{path}: expected RGBA, got {opened.mode}")
        image = opened.copy()
    expected_sizes = {
        SOURCE_SPECS[0]["sha256"]: (1774, 469),
        SOURCE_SPECS[1]["sha256"]: (1536, 554),
    }
    if tuple(image.size) != expected_sizes[str(spec["sha256"])]:
        raise ValueError(f"{path}: unexpected size {image.size}")
    return image, actual_sha


def alpha_x_runs(image: Image.Image) -> list[tuple[int, int]]:
    alpha = np.asarray(image.getchannel("A"), dtype=np.uint8)
    active = (alpha >= ALPHA_THRESHOLD).any(axis=0)
    runs: list[tuple[int, int]] = []
    start: int | None = None
    for index, enabled in enumerate(np.concatenate((active, np.asarray([False])))):
        if bool(enabled) and start is None:
            start = index
        elif not bool(enabled) and start is not None:
            runs.append((start, index))
            start = None
    if len(runs) != 4:
        raise ValueError(f"alpha x-run count={len(runs)}, expected=4: {runs}")
    if any(end - start < 32 for start, end in runs):
        raise ValueError(f"alpha x-run is not a large run: {runs}")
    return runs


def run_output(
    image: Image.Image,
    run: tuple[int, int],
) -> tuple[Image.Image, dict[str, Any]]:
    alpha = np.asarray(image.getchannel("A"), dtype=np.uint8)
    x_start, x_end = run
    local = alpha[:, x_start:x_end] >= ALPHA_THRESHOLD
    ys, local_xs = np.where(local)
    if len(local_xs) == 0:
        raise ValueError(f"empty alpha run: {run}")
    x1 = x_start + int(local_xs.min())
    x2 = x_start + int(local_xs.max()) + 1
    y1 = int(ys.min())
    y2 = int(ys.max()) + 1
    source_bounds = [x1, y1, x2 - x1, y2 - y1]
    cropped = image.crop((x1, y1, x2, y2))
    output = Image.new(
        "RGBA",
        (cropped.width + PADDING_PX * 2, cropped.height + PADDING_PX * 2),
        (0, 0, 0, 0),
    )
    output.paste(cropped, (PADDING_PX, PADDING_PX))
    visible_bounds = [PADDING_PX, PADDING_PX, cropped.width, cropped.height]
    threshold_alpha = np.asarray(output.getchannel("A"), dtype=np.uint8) >= ALPHA_THRESHOLD
    visible_mask = np.zeros_like(threshold_alpha)
    vx, vy, vw, vh = visible_bounds
    visible_mask[vy:vy + vh, vx:vx + vw] = True
    if bool(np.any(threshold_alpha & ~visible_mask)):
        raise ValueError(f"threshold alpha escaped crop: {run}")
    # The selected bbox is based on alpha>=8, while the crop itself retains
    # every original RGBA value inside that bbox, including low alpha edges.
    return output, {
        "source_x_run_bounds_px": [x1, x2 - 1],
        "source_bounds_px": source_bounds,
        "visible_bounds_px": visible_bounds,
        "visible_alpha_pixel_count": int(np.count_nonzero(threshold_alpha)),
        "output_size": list(output.size),
    }


def build_expected() -> tuple[dict[str, Any], dict[str, bytes]]:
    assets: list[dict[str, Any]] = []
    outputs: dict[str, bytes] = {}
    source_records: list[dict[str, Any]] = []
    for source_index, spec in enumerate(SOURCE_SPECS, start=1):
        source, source_sha = read_source(spec)
        runs = alpha_x_runs(source)
        source_records.append({
            "source_index": source_index,
            "source_external_path": str(spec["path"]),
            "source_sha256": source_sha,
            "source_canvas": list(source.size),
            "alpha_threshold": ALPHA_THRESHOLD,
            "x_run_count": len(runs),
            "x_run_bounds_px_inclusive": [[start, end - 1] for start, end in runs],
        })
        for local_index, run in enumerate(runs, start=1):
            output, geometry = run_output(source, run)
            stable_index = int(spec["stable_start"]) + local_index - 1
            image_rel = (
                Path("assets/art/maps/_shared/user_palette/decorations_1/barricades")
                / "chain_fence_20260821"
                / f"chain_fence_{stable_index:02d}.png"
            ).as_posix()
            output_payload = png_bytes(output)
            outputs[image_rel] = output_payload
            visible = geometry["visible_bounds_px"]
            visible_width, visible_height = int(visible[2]), int(visible[3])
            footprint = [
                (visible_width + FOOTPRINT_UNIT_PX - 1) // FOOTPRINT_UNIT_PX,
                (visible_height + FOOTPRINT_UNIT_PX - 1) // FOOTPRINT_UNIT_PX,
            ]
            anchor = [
                int(visible[0]) + visible_width // 2,
                int(visible[1]) + visible_height - 1,
            ]
            processing = {
                "pipeline": PIPELINE,
                "alpha_threshold": ALPHA_THRESHOLD,
                "padding_px": PADDING_PX,
                "source_canvas": list(source.size),
                "source_x_run_bounds_px_inclusive": geometry["source_x_run_bounds_px"],
                "source_bounds_px": geometry["source_bounds_px"],
                "rgba_pixels_preserved": True,
                "run_index": local_index,
                "run_count": len(runs),
                "output_mask_edge_touch": [],
            }
            assets.append({
                "asset_id": f"mse.roadblock.chain_fence.{stable_index:02d}",
                "display_name": f"铁链路障 {stable_index:02d}",
                "asset_type": "large_prop",
                "category": "obstacle",
                "object_class": "obstacle",
                "theme": "user_palette",
                "image": image_rel,
                "thumbnail": image_rel,
                "canvas_size": list(output.size),
                "image_size": list(output.size),
                "visible_bounds_px": visible,
                "selection_bounds_px": visible.copy(),
                "anchor_px": anchor,
                "placement_anchor_px": anchor.copy(),
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
                "default_object_role": "obstacle",
                "collision_policy": "none",
                "collision_profile_id": "none_visual",
                "navigation_policy": "ignore",
                "manual_collision_expected": True,
                "map_collision_override": "default",
                "collision_authority": "manual_by_user",
                "occlusion": True,
                "content_layer": "personal_expansion",
                "placeable": True,
                "calibration_status": "placeable",
                "calibration_source": "pending_manual_geometry_v1",
                "geometry_pending_manual": True,
                "palette_path": PALETTE_PATH,
                "source_external_path": str(spec["path"]),
                "source_sha256": source_sha,
                "source_canvas": list(source.size),
                "source_x_run_bounds_px_inclusive": geometry["source_x_run_bounds_px"],
                "source_bounds_px": geometry["source_bounds_px"],
                "output_sha256": sha256_bytes(output_payload),
                "thumbnail_source_sha256": sha256_bytes(output_payload),
                "processing": processing,
                "tags": [
                    "new_local_asset",
                    "chain_fence",
                    "roadblock",
                    PIPELINE,
                ],
                "editable": True,
                "allows_edge_clipping": True,
                "semantic_role": "",
                "trigger_on_enter": False,
                "package_id": PACKAGE_ID,
                "source_index": source_index,
                "source_run_index": local_index,
                "projection": "orthographic_isometric_2_to_1",
            })
    catalog = {
        "asset_schema_version": 2,
        "package_id": PACKAGE_ID,
        "package_version": 1,
        "classification": PALETTE_PATH,
        "palette_path": PALETTE_PATH,
        "source_count": len(SOURCE_SPECS),
        "asset_count": len(assets),
        "cutting_policy": PIPELINE,
        "alpha_threshold": ALPHA_THRESHOLD,
        "padding_px": PADDING_PX,
        "default_collision_policy": "none",
        "collision_authority": "manual_by_user",
        "sources": source_records,
        "assets": assets,
    }
    if len(assets) != 8 or len(outputs) != 8:
        raise AssertionError(f"expected 8 assets and outputs, got {len(assets)} / {len(outputs)}")
    return catalog, outputs


def read_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"JSON root must be an object: {path}")
    return value


def write_json(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")


def validate_existing(catalog: dict[str, Any], expected: dict[str, Any], outputs: dict[str, bytes]) -> list[str]:
    errors: list[str] = []
    actual_assets = catalog.get("assets", [])
    expected_assets = expected["assets"]
    if catalog.get("package_id") != PACKAGE_ID:
        errors.append("catalog.package_id_mismatch")
    if catalog.get("asset_count") != 8 or len(actual_assets) != 8:
        errors.append(f"catalog.asset_count={len(actual_assets)} expected=8")
    actual_by_id = {str(asset.get("asset_id", "")): asset for asset in actual_assets if isinstance(asset, dict)}
    if len(actual_by_id) != len(actual_assets):
        errors.append("catalog.duplicate_or_missing_id")
    for expected_asset in expected_assets:
        asset_id = str(expected_asset["asset_id"])
        actual = actual_by_id.get(asset_id)
        if actual is None:
            errors.append(f"catalog.missing:{asset_id}")
            continue
        for field in (
            "display_name", "category", "object_class", "image", "thumbnail",
            "visible_bounds_px", "selection_bounds_px", "anchor_px",
            "footprint_tiles", "visual_footprint_tiles", "occupancy_footprint_tiles",
            "base_footprint_tiles", "collision_footprint_tiles", "collision_policy",
            "collision_profile_id", "navigation_policy", "placeable", "calibration_status",
            "geometry_pending_manual", "palette_path", "source_sha256", "source_bounds_px",
            "output_sha256", "processing",
        ):
            if actual.get(field) != expected_asset.get(field):
                errors.append(f"catalog.field_mismatch:{asset_id}:{field}")
        image_path = ROOT / str(expected_asset["image"])
        if not image_path.is_file():
            errors.append(f"image.missing:{image_path}")
        elif image_path.read_bytes() != outputs[str(expected_asset["image"])]:
            errors.append(f"image.bytes_mismatch:{image_path}")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser()
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true")
    mode.add_argument("--write", action="store_true")
    args = parser.parse_args()
    try:
        expected, outputs = build_expected()
        existing = read_json(CATALOG_PATH) if CATALOG_PATH.is_file() else None
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"CHAIN_ROADBLOCK_IMPORT_FAIL {exc}")
        return 1
    if args.check:
        if existing is None:
            print(f"CHAIN_ROADBLOCK_CHECK_FAIL missing_catalog={CATALOG_PATH}")
            return 1
        errors = validate_existing(existing, expected, outputs)
        if errors:
            print("CHAIN_ROADBLOCK_CHECK_FAIL")
            print("\n".join(errors))
            return 1
        print("CHAIN_ROADBLOCK_CHECK_PASS assets=8 alpha_runs=8 rgba_preserved=true")
        return 0

    if existing is not None and existing.get("package_id") not in (None, PACKAGE_ID):
        print("CHAIN_ROADBLOCK_IMPORT_REFUSE existing_catalog_not_owned_or_deterministic")
        return 1
    for image_rel, payload in outputs.items():
        path = ROOT / image_rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(payload)
    write_json(CATALOG_PATH, expected)
    print(f"CHAIN_ROADBLOCK_WRITE_PASS assets=8 output_dir={OUTPUT_ROOT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
