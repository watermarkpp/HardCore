"""Import the two user portal-gate images as a deterministic 2-asset pack.

Source directory: C:\\Users\\Administrator\\Desktop\\sucai\\装饰物1\\传送门
  - "ChatGPT Image 2026年9月16日 13_10_26 (1).png"  blue  -> bidirectional portal
  - "ChatGPT Image 2026年9月16日 13_10_26 (2).png"  red   -> one-way portal

Each source is a single-subject transparent RGBA image (1122x1402). The
importer crops the alpha bounding box (threshold 16), downscales the content
to 80 px height (= 2.5 vertical tiles at tile_size [64, 32], matching the
in-game ZonePortal placeholder scale the user approved), pastes it onto a
4 px padded canvas, and emits one catalog entry per image with the same field
set as the user_map_exit_pack_20260822_v1 pack. Footprint tiles are derived
from the final canvas; the user calibrates anchor/footprint/collision/occlusion
through the editor's 素材校准（Expansion覆盖）panel afterwards.

The importer owns only the exact portal-gate asset directory, the new
map_portal_gate_asset_catalog.json extension catalog and its import manifest;
it never touches map workspaces, runtime data, or the 20260822 pack.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any

import numpy as np
from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
SOURCE_DIR = Path(r"C:\Users\Administrator\Desktop\sucai\装饰物1\传送门")
OUTPUT_DIR = ROOT / "assets/art/maps/_shared/user_palette/decorations_1/map_entrances/portal_gates_20260916"
OUTPUT_RELPATH = "assets/art/maps/_shared/user_palette/decorations_1/map_entrances/portal_gates_20260916"
CATALOG_PATH = ROOT / "assets/data/assets/map_portal_gate_asset_catalog.json"
MANIFEST_PATH = ROOT / "assets/data/assets/map_portal_gate_asset_import_manifest_20260916.json"

PACKAGE_ID = "user_portal_gate_pack_20260916_v1"
PALETTE_PATH = "装饰物1/传送门"
PIPELINE = "single_image_alpha_bbox_crop_downscale_rgba_preserve_v1"
ALPHA_THRESHOLD = 16
PADDING_PX = 4
CONTENT_HEIGHT_PX = 80  # 2.5 vertical tiles at tile_size [64, 32]
TILE_SIZE = [64, 32]

SOURCES: list[dict[str, Any]] = [
    {
        "filename": "ChatGPT Image 2026年9月16日 13_10_26 (1).png",
        "output_name": "portal_gate_bidirectional_blue.png",
        "asset_id": "user.portal_gate.20260916.s01_r1_c1",
        "package_asset_id": "s01_r1_c1",
        "set_id": "S01",
        "display_name": "传送门 双向（蓝）20260916 S01",
        "portal_mode": "bidirectional",
        "portal_tag": "portal_bidirectional",
    },
    {
        "filename": "ChatGPT Image 2026年9月16日 13_10_26 (2).png",
        "output_name": "portal_gate_one_way_red.png",
        "asset_id": "user.portal_gate.20260916.s02_r1_c1",
        "package_asset_id": "s02_r1_c1",
        "set_id": "S02",
        "display_name": "传送门 单向（红）20260916 S02",
        "portal_mode": "one_way",
        "portal_tag": "portal_one_way",
    },
]


def sha256_bytes(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def alpha_bbox(rgba: np.ndarray) -> tuple[int, int, int, int]:
    mask = rgba[:, :, 3] > ALPHA_THRESHOLD
    rows = np.any(mask, axis=1)
    columns = np.any(mask, axis=0)
    if not rows.any() or not columns.any():
        raise ValueError("source image has no alpha content above threshold")
    top = int(np.argmax(rows))
    bottom = int(rgba.shape[0] - np.argmax(rows[::-1]))
    left = int(np.argmax(columns))
    right = int(rgba.shape[1] - np.argmax(columns[::-1]))
    return left, top, right, bottom


def process_source(source: dict[str, Any]) -> tuple[dict[str, Any], bytes]:
    source_path = SOURCE_DIR / str(source["filename"])
    raw = source_path.read_bytes()
    source_sha = sha256_bytes(raw)
    image = Image.open(source_path).convert("RGBA")
    source_canvas = [int(image.width), int(image.height)]
    pixels = np.asarray(image, dtype=np.uint8)
    left, top, right, bottom = alpha_bbox(pixels)
    crop = image.crop((left, top, right, bottom))
    crop_w, crop_h = crop.size
    content_h = CONTENT_HEIGHT_PX
    content_w = max(1, int(round(content_h * crop_w / crop_h)))
    resized = crop.resize((content_w, content_h), Image.LANCZOS)
    canvas_w = content_w + PADDING_PX * 2
    canvas_h = content_h + PADDING_PX * 2
    canvas = Image.new("RGBA", (canvas_w, canvas_h), (0, 0, 0, 0))
    canvas.paste(resized, (PADDING_PX, PADDING_PX))

    buffer = BytesIOByteSink()
    canvas.save(buffer.handle(), format="PNG", optimize=True)
    output_bytes = buffer.payload()
    output_sha = sha256_bytes(output_bytes)

    out_pixels = np.asarray(canvas, dtype=np.uint8)
    out_left, out_top, out_right, out_bottom = alpha_bbox(out_pixels)
    footprint = [
        int(-(-canvas_w // TILE_SIZE[0])),
        int(-(-canvas_h // TILE_SIZE[1])),
    ]
    anchor = [canvas_w // 2, canvas_h - PADDING_PX - 1]
    low_alpha = int(np.count_nonzero(
        (out_pixels[:, :, 3] > 0) & (out_pixels[:, :, 3] <= ALPHA_THRESHOLD)
    ))

    entry: dict[str, Any] = {
        "asset_id": source["asset_id"],
        "display_name": source["display_name"],
        "asset_type": "large_prop",
        "category": "map_entrance",
        "object_class": "map_entrance",
        "theme": "user_palette",
        "image": f"{OUTPUT_RELPATH}/{source['output_name']}",
        "thumbnail": f"{OUTPUT_RELPATH}/{source['output_name']}",
        "canvas_size": [canvas_w, canvas_h],
        "image_size": [canvas_w, canvas_h],
        "visible_bounds_px": [out_left, out_top, out_right, out_bottom],
        "selection_bounds_px": [out_left, out_top, out_right, out_bottom],
        "anchor_px": anchor,
        "placement_anchor_px": list(anchor),
        "door_anchor_px": None,
        "anchor_tile": [0, 0],
        "anchor_mode": "foot_tile",
        "footprint_tiles": footprint,
        "visual_footprint_tiles": list(footprint),
        "occupancy_footprint_tiles": list(footprint),
        "base_footprint_tiles": list(footprint),
        "collision_footprint_tiles": [0, 0],
        "collision_cells": [],
        "placement_clearance_cells": [],
        "tile_size": list(TILE_SIZE),
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
        "occlusion": True,
        "content_layer": "personal_expansion",
        "placeable": True,
        "overlap_policy": "placeable",
        "calibration_status": "pending_manual_review",
        "calibration_source": "pending_manual_geometry_v1",
        "geometry_pending_manual": True,
        "palette_path": PALETTE_PATH,
        "source_external_path": str(source_path),
        "source_sha256": source_sha,
        "source_canvas": source_canvas,
        "source_grid": [1, 1],
        "source_cell_bounds_px": [left, top, right, bottom],
        "source_bounds_px": [left, top, right, bottom],
        "source_alpha_bbox_px": [left, top, right, bottom],
        "output_sha256": output_sha,
        "thumbnail_source_sha256": output_sha,
        "processing": {
            "pipeline": PIPELINE,
            "grid": [1, 1],
            "alpha_threshold": ALPHA_THRESHOLD,
            "padding_px": PADDING_PX,
            "source_bounds_px": [left, top, right, bottom],
            "source_alpha_bbox_px": [left, top, right, bottom],
            "content_resize_target_height_px": CONTENT_HEIGHT_PX,
            "content_resized_size_px": [content_w, content_h],
            "resample": "lanczos",
            "rgba_pixels_preserved": True,
            "background_purification": {},
            "low_alpha_pixels": low_alpha,
            "cell_edge_alpha_pixels": 0,
        },
        "tags": [
            "new_local_asset",
            "map_exit",
            "map_entrance",
            "pending_manual_review",
            "portal_gate",
            str(source["portal_tag"]),
        ],
        "editable": True,
        "allows_edge_clipping": True,
        "trigger_on_enter": True,
        "package_id": PACKAGE_ID,
        "package_asset_id": source["package_asset_id"],
        "set_id": source["set_id"],
        "placement_kind": "manual_pending",
        "logical_direction": "unknown_pending",
        "screen_position": "manual_pending",
        "view": "front_oblique",
        "opening_visible": None,
        "requires_runtime_rotation": False,
        "allow_flip": False,
        "source_sheet": str(source["filename"]),
        "projection": "orthographic_isometric_2_to_1",
        "portal_mode": source["portal_mode"],
    }
    return entry, output_bytes


class BytesIOByteSink:
    """Minimal in-memory sink so canvas.save can serialise the PNG bytes."""

    def __init__(self) -> None:
        import io

        self._buffer = io.BytesIO()

    def handle(self) -> io.BytesIO:
        return self._buffer

    def payload(self) -> bytes:
        return self._buffer.getvalue()


def build_expected() -> tuple[dict[str, Any], dict[str, bytes], dict[str, str]]:
    assets: list[dict[str, Any]] = []
    outputs: dict[str, bytes] = {}
    source_hashes: dict[str, str] = {}
    for source in SOURCES:
        entry, output_bytes = process_source(source)
        assets.append(entry)
        outputs[str(entry["image"])] = output_bytes
        source_hashes[str(source["filename"])] = str(entry["source_sha256"])
    assets.sort(key=lambda item: str(item["asset_id"]))
    catalog = {
        "asset_schema_version": 2,
        "package_id": PACKAGE_ID,
        "package_version": 1,
        "source_archive": str(SOURCE_DIR),
        "asset_count": len(assets),
        "classification": PALETTE_PATH,
        "default_collision_policy": "none",
        "assets": assets,
    }
    manifest = {
        "package_id": PACKAGE_ID,
        "pipeline": PIPELINE,
        "alpha_threshold": ALPHA_THRESHOLD,
        "padding_px": PADDING_PX,
        "content_resize_target_height_px": CONTENT_HEIGHT_PX,
        "tile_size": list(TILE_SIZE),
        "sources": [
            {
                "filename": str(source["filename"]),
                "source_sha256": source_hashes[str(source["filename"])],
                "asset_id": str(source["asset_id"]),
                "output": f"{OUTPUT_RELPATH}/{source['output_name']}",
                "portal_mode": str(source["portal_mode"]),
            }
            for source in SOURCES
        ],
        "assets": [
            {
                "asset_id": str(entry["asset_id"]),
                "image": str(entry["image"]),
                "output_sha256": str(entry["output_sha256"]),
                "canvas_size": list(entry["canvas_size"]),
                "footprint_tiles": list(entry["footprint_tiles"]),
                "anchor_px": list(entry["anchor_px"]),
            }
            for entry in assets
        ],
    }
    return (
        {"catalog": catalog, "manifest": manifest},
        outputs,
        source_hashes,
    )


def write_json(path: Path, payload: dict[str, Any]) -> None:
    text = json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=False)
    path.write_text(text + "\n", encoding="utf-8")


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def replace_files(
    expected: dict[str, Any], outputs: dict[str, bytes]
) -> dict[str, int]:
    counters = {"png_written": 0, "catalog_written": 0, "manifest_written": 0}
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    for relpath, payload in outputs.items():
        target = ROOT / relpath
        if not target.exists() or target.read_bytes() != payload:
            target.write_bytes(payload)
            counters["png_written"] += 1
    if (not CATALOG_PATH.exists()) or read_json(CATALOG_PATH) != expected["catalog"]:
        write_json(CATALOG_PATH, expected["catalog"])
        counters["catalog_written"] += 1
    if (not MANIFEST_PATH.exists()) or read_json(MANIFEST_PATH) != expected["manifest"]:
        write_json(MANIFEST_PATH, expected["manifest"])
        counters["manifest_written"] += 1
    return counters


def check(
    expected: dict[str, Any], outputs: dict[str, bytes]
) -> None:
    problems: list[str] = []
    for relpath, payload in outputs.items():
        target = ROOT / relpath
        if not target.exists():
            problems.append(f"missing_output:{relpath}")
        elif target.read_bytes() != payload:
            problems.append(f"output_mismatch:{relpath}")
    if not CATALOG_PATH.exists():
        problems.append("missing_catalog")
    elif read_json(CATALOG_PATH) != expected["catalog"]:
        problems.append("catalog_mismatch")
    if not MANIFEST_PATH.exists():
        problems.append("missing_manifest")
    elif read_json(MANIFEST_PATH) != expected["manifest"]:
        problems.append("manifest_mismatch")
    catalog_assets = expected["catalog"]["assets"]
    if len(catalog_assets) != 2 or len(
        {asset["asset_id"] for asset in catalog_assets}
    ) != 2:
        problems.append("asset_count_invalid")
    ids = [str(asset["asset_id"]) for asset in catalog_assets]
    if any(not asset_id.startswith("user.portal_gate.20260916.") for asset_id in ids):
        problems.append("asset_id_prefix_invalid")
    if problems:
        raise ValueError("; ".join(problems))
    print(
        "PORTAL_GATE_ASSET_IMPORT_CHECK_PASS assets=2 "
        f"outputs={len(outputs)} pipeline={PIPELINE} "
        f"content_height_px={CONTENT_HEIGHT_PX} padding={PADDING_PX}"
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true")
    mode.add_argument("--write", action="store_true")
    args = parser.parse_args()
    try:
        expected, outputs, _hashes = build_expected()
        if args.write:
            print("PORTAL_GATE_ASSET_IMPORT_WRITE", replace_files(expected, outputs))
        check(expected, outputs)
        return 0
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"PORTAL_GATE_ASSET_IMPORT_FAIL {exc}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
