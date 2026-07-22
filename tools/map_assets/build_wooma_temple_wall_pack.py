#!/usr/bin/env python3
"""Build the pillar-free Wooma Temple wall family on the native 64x32 grid.

The reviewed sources are deliberately flat orthographic textures.  This tool
projects them directly onto exact 2:1 isometric planes; it never repairs or
skews a previously generated isometric wall.  Corners use two straight modules
on the same tile, so this family has no corner pillar or corner bitmap.
"""

from __future__ import annotations

import copy
import hashlib
import json
from pathlib import Path
import shutil

from PIL import Image, ImageEnhance


ROOT = Path(__file__).resolve().parents[2]
SOURCE_DIR = ROOT / "outputs" / "wooma_temple_regenerated"
SOURCE_EXTERNAL_PATH = "outputs/wooma_temple_regenerated"
FRONT_SOURCE = SOURCE_DIR / "wooma_wall_front_bay_alpha.png"
CAP_SOURCE = SOURCE_DIR / "wooma_wall_capstone_alpha.png"
ART_ROOT = (
    ROOT
    / "assets"
    / "art"
    / "maps"
    / "_shared"
    / "walls"
    / "wooma_temple"
    / "wooma_temple_gothic_stone_u0"
)
MODULE_CATALOG = ROOT / "assets" / "data" / "assets" / "wall_module_catalog.json"
FAMILY_CATALOG = ROOT / "assets" / "data" / "assets" / "wall_family_catalog.json"
ASSET_CATALOG = (
    ROOT
    / "assets"
    / "data"
    / "assets"
    / "map_wooma_temple_wall_asset_catalog.json"
)

FAMILY_ID = "wooma_temple_gothic_stone_u0"
SOCKET_ID = "wooma_temple_gothic_stone_socket_u0"
VISUAL_PROFILE_ID = "wooma_temple_native_2to1_wall_v3"
PROJECTION_CONTRACT_ID = "isometric_cell_64x32_exact_v1"
PLACEMENT_CONTRACT_ID = "wall_foot_on_cell_edge_64x32_v1"
SOURCE_FAMILY_ID = "orc_tomb_rough_stone_u0"
SOURCE_PREFIX = "orc_tomb_wall_"
TARGET_PREFIX = "wooma_temple_wall_"
GRID_TILE = (64, 32)
FACE_SIZE = (32, 160)
SEGMENT_SIZE = (96, 224)
ANCHOR_Y = 184
RESAMPLE = Image.Resampling.LANCZOS


def read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(value, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def alpha_trim(image: Image.Image) -> Image.Image:
    rgba = image.convert("RGBA")
    box = rgba.getchannel("A").getbbox()
    if box is None:
        raise RuntimeError("source image has no visible pixels")
    return rgba.crop(box)


def save_png(image: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, format="PNG", optimize=True)


def res_path(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def display_name(module: dict) -> str:
    axis_name = "X向" if module["axis"] == "iso_x" else "Y向"
    return (
        f"标准哥特直墙 {axis_name} "
        f"{int(module['length_tiles'])}格 变体{int(module.get('variant', 1))}"
    )


def _load_reviewed_source(path: Path) -> Image.Image:
    with Image.open(path) as opened:
        return alpha_trim(opened.convert("RGBA"))


def _variant_texture(source: Image.Image, variant: int) -> Image.Image:
    """Keep variants subtle while preserving exactly the same geometry."""
    factors = (1.0, 0.94, 1.06)
    factor = factors[(max(1, variant) - 1) % len(factors)]
    return ImageEnhance.Brightness(source).enhance(factor)


def _project_capstone(source: Image.Image, variant: int) -> Image.Image:
    """Map a square top texture to an exact 64x32 isometric diamond."""
    square = _variant_texture(source, variant).resize((64, 64), RESAMPLE)
    projected = square.transform(
        (64, 32),
        Image.Transform.AFFINE,
        (1.0, 2.0, -32.0, -1.0, 2.0, 32.0),
        resample=Image.Resampling.BICUBIC,
    )
    # Affine sampling can leave a soft one-pixel rectangle around the diamond.
    mask = Image.new("L", (64, 32), 0)
    pixels = mask.load()
    for y in range(32):
        for x in range(64):
            if abs(x - 32) * 0.5 + abs(y - 16) <= 16.0:
                pixels[x, y] = 255
    projected.putalpha(Image.composite(projected.getchannel("A"), mask, mask))
    return projected


def _project_facade(source: Image.Image, variant: int) -> Image.Image:
    """Map a flat 32x160 bay onto a face whose axis slope is exactly +0.5."""
    face = _variant_texture(source, variant).resize(FACE_SIZE, RESAMPLE)
    projected = Image.new("RGBA", (32, 176), (0, 0, 0, 0))
    for x in range(32):
        shift = x // 2
        projected.alpha_composite(face.crop((x, 0, x + 1, 160)), (x, shift))
    return projected


def native_segment(
    front_source: Image.Image,
    cap_source: Image.Image,
    variant: int,
) -> Image.Image:
    """Create one canonical wall cell with exact matching top/face seams."""
    segment = Image.new("RGBA", SEGMENT_SIZE, (0, 0, 0, 0))
    # The face top is (32,24)->(64,40), exactly the cap's front-left edge.
    segment.alpha_composite(_project_facade(front_source, variant), (32, 24))
    segment.alpha_composite(_project_capstone(cap_source, variant), (32, 8))
    return segment


def split_continuous_parts(
    artwork: Image.Image,
    length: int,
    axis: str,
) -> list[Image.Image]:
    if length <= 1:
        return [artwork.copy()]
    alpha_box = artwork.getchannel("A").getbbox()
    if alpha_box is None:
        raise RuntimeError("wall artwork has no visible pixels")
    left, _top, right, _bottom = alpha_box
    width = max(1, right - left)
    parts = [
        Image.new("RGBA", artwork.size, (0, 0, 0, 0))
        for _index in range(length)
    ]
    for x in range(left, right):
        index = min(length - 1, int((x - left) * length / width))
        if axis == "iso_y":
            index = length - 1 - index
        parts[index].alpha_composite(
            artwork.crop((x, 0, x + 1, artwork.height)),
            (x, 0),
        )
    return parts


def _apply_native_geometry(module: dict) -> None:
    length = int(module["length_tiles"])
    axis = str(module["axis"])
    canvas_width = 32 * length + 64
    canvas_height = 208 + 16 * length
    # Wall instances are positioned at a cell centre by the editor.  The
    # visible foot must therefore use one complete diamond edge, never the
    # centre diagonal.  These anchors produce:
    #   iso_x: (-32, 0) -> (0, 16)
    #   iso_y: ( 32, 0) -> (0, 16)
    # relative to that cell centre.
    anchor_x = 64 if axis == "iso_x" else canvas_width - 64
    module["canvas_size"] = [canvas_width, canvas_height]
    module["anchor"] = [anchor_x, ANCHOR_Y]
    seam_start_y = ANCHOR_Y
    if axis == "iso_x":
        module["start_seam_px"] = [32, seam_start_y]
        module["end_seam_px"] = [
            32 + 32 * length,
            seam_start_y + 16 * length,
        ]
    else:
        module["start_seam_px"] = [canvas_width - 32, seam_start_y]
        module["end_seam_px"] = [
            canvas_width - 32 - 32 * length,
            seam_start_y + 16 * length,
        ]


def straight_art(
    module: dict,
    front_source: Image.Image,
    cap_source: Image.Image,
) -> tuple[Image.Image, list[Image.Image]]:
    length = int(module["length_tiles"])
    axis = str(module["axis"])
    size = tuple(int(value) for value in module["canvas_size"])
    segment = native_segment(
        front_source,
        cap_source,
        int(module.get("variant", 1)),
    )
    artwork = Image.new("RGBA", size, (0, 0, 0, 0))
    for tile_index in range(length):
        artwork.alpha_composite(segment, (32 * tile_index, 16 * tile_index))
    if axis == "iso_y":
        artwork = artwork.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
    return artwork, split_continuous_parts(artwork, length, axis)


def build_module(
    source_module: dict,
    front_source: Image.Image,
    cap_source: Image.Image,
) -> tuple[dict, dict]:
    module = copy.deepcopy(source_module)
    asset_id = str(module["asset_id"]).replace(SOURCE_PREFIX, TARGET_PREFIX, 1)
    module.update(
        {
            "asset_id": asset_id,
            "display_name": display_name(module),
            "category": "dungeon_wall",
            "theme": "wooma_temple",
            "wall_family_id": FAMILY_ID,
            "socket_profile_id": SOCKET_ID,
            "content_layer": "personal_expansion",
            "collision_cells": [],
            "placement_clearance_cells": [],
            "collision_policy": "none",
            "navigation_policy": "ignore",
            "manual_collision_expected": True,
            "collision_authority": "manual_by_user",
            "collision_profile_id": "none_visual",
            "map_collision_override": "disabled",
            "calibration_status": "placeable",
            "placeable": True,
            "repeat_group": str(module.get("repeat_group", "")).replace(
                "orc_tomb_", "wooma_temple_", 1
            ),
            "visual_profile_id": VISUAL_PROFILE_ID,
            "native_projection_contract_id": PROJECTION_CONTRACT_ID,
            "placement_contract_id": PLACEMENT_CONTRACT_ID,
            "corner_join_mode": "straight_overlap",
            "contains_corner_pillar": False,
            "wall_cap_thickness_tiles": 1,
            "wall_cap_projection_px": [32, 16],
        }
    )
    _apply_native_geometry(module)
    for connector in module.get("connectors", []):
        connector["socket_profile_id"] = SOCKET_ID

    artwork, parts = straight_art(module, front_source, cap_source)
    asset_dir = ART_ROOT / asset_id
    asset_dir.mkdir(parents=True, exist_ok=True)
    composite_path = asset_dir / f"composite_{VISUAL_PROFILE_ID}.png"
    save_png(artwork, composite_path)

    render_parts: list[dict] = []
    for index, part_image in enumerate(parts):
        part_path = asset_dir / f"part_{index:02d}_{VISUAL_PROFILE_ID}_base.png"
        save_png(part_image, part_path)
        tile_offset = (
            [index, 0] if module["axis"] == "iso_x" else [0, index]
        )
        render_parts.append(
            {
                "part_id": f"p{index:02d}",
                "tile_offset": tile_offset,
                "base_image": res_path(part_path),
                "front_image": "",
                "shadow_image": "",
                "anchor": list(module["anchor"]),
                "sort_tile_offset": tile_offset,
                "draw_order_index": index,
            }
        )
    module["render_mode"] = "single_part" if len(parts) == 1 else "segmented"
    module["render_parts"] = render_parts

    alpha_bounds = artwork.getchannel("A").getbbox()
    if alpha_bounds is None:
        raise RuntimeError(f"{asset_id} has no visible pixels")
    visible_bounds = [
        alpha_bounds[0],
        alpha_bounds[1],
        alpha_bounds[2] - alpha_bounds[0],
        alpha_bounds[3] - alpha_bounds[1],
    ]
    digest = sha256(composite_path)
    asset = {
        **copy.deepcopy(module),
        "category": "wall_module",
        "object_class": "wall",
        "image": res_path(composite_path),
        "thumbnail": res_path(composite_path),
        "image_size": list(artwork.size),
        "visible_bounds_px": visible_bounds,
        "selection_bounds_px": visible_bounds,
        "anchor_px": list(module["anchor"]),
        "placement_anchor_px": list(module["anchor"]),
        "anchor_tile": [0, 0],
        "anchor_mode": "foot_tile",
        "placement_preview_mode": "image_and_footprint",
        "visual_footprint_tiles": list(module["footprint_tiles"]),
        "occupancy_footprint_tiles": list(module["footprint_tiles"]),
        "base_footprint_tiles": list(module["footprint_tiles"]),
        "collision_footprint_tiles": [0, 0],
        "tile_size": list(GRID_TILE),
        "approved_scale": 1.0,
        "logical_scale_level": 0,
        "scale_approved": True,
        "anchor_approved": True,
        "default_object_role": "terrain",
        "palette_path": (
            "洞穴与地下城/墙体模块/沃玛寺庙墙体/"
            f"直墙/{module['axis']}"
        ),
        "source_external_path": SOURCE_EXTERNAL_PATH,
        "source_sha256": hashlib.sha256(
            (sha256(FRONT_SOURCE) + sha256(CAP_SOURCE)).encode("utf-8")
        ).hexdigest(),
        "output_sha256": digest,
        "thumbnail_source_sha256": digest,
        "processing": "native_flat_texture_to_exact_64x32_isometric_planes",
        "generation_source_ids": [
            "call_7z8NxnZ8imcRKyhEds3sTwzU",
            "call_HTxU8temh6Nr84TzLrrnTClr",
        ],
        "tags": [
            "cave_dungeon",
            "wooma_temple",
            "wall_module",
            FAMILY_ID,
            "straight",
            "straight_overlap_corner",
            "manual_collision",
        ],
        "editable": True,
        "runtime_export": True,
    }
    return module, asset


def update_family_catalog() -> None:
    catalog = read_json(FAMILY_CATALOG)
    catalog["wall_families"] = [
        family
        for family in catalog.get("wall_families", [])
        if family.get("wall_family_id") != FAMILY_ID
    ]
    catalog["wall_families"].append(
        {
            "wall_family_id": FAMILY_ID,
            "display_name": "标准灰绿色哥特寺庙墙 U0",
            "theme": "wooma_temple",
            "material": "gothic_gray_green_stone",
            "socket_profile_id": SOCKET_ID,
            "tile_size": list(GRID_TILE),
            "wall_height_px": FACE_SIZE[1],
            "side_pad_px": 16,
            "allowed_lengths": [1, 2, 3, 4],
            "primary_lengths": [4, 3],
            "repair_lengths": [2, 1],
            "default_blocked_side": "outside",
            "seam_guard_px": 16,
            "seam_overlap_px": 0,
            "seam_cover_asset_ids": [],
            "corner_join_mode": "straight_overlap",
            "corner_asset_ids": [],
            "native_projection_contract_id": PROJECTION_CONTRACT_ID,
            "placement_contract_id": PLACEMENT_CONTRACT_ID,
            "contains_corner_pillars": False,
            "palette_id": FAMILY_ID,
            "content_layer": "personal_expansion",
            "collision_authority": "manual_by_user",
            "palette_role": "standard_reusable_temple_wall",
            "intended_uses": ["zuma_temple", "other_temple_maps"],
            "enabled": True,
        }
    )
    write_json(FAMILY_CATALOG, catalog)


def main() -> None:
    missing = [
        str(path)
        for path in (FRONT_SOURCE, CAP_SOURCE)
        if not path.is_file()
    ]
    if missing:
        raise RuntimeError(f"missing reviewed flat source textures: {missing}")

    module_catalog = read_json(MODULE_CATALOG)
    source_modules = [
        module
        for module in module_catalog.get("modules", [])
        if (
            module.get("wall_family_id") == SOURCE_FAMILY_ID
            and module.get("topology") == "straight"
        )
    ]
    if len(source_modules) != 16:
        raise RuntimeError(f"expected 16 straight source modules, found {len(source_modules)}")

    front_source = _load_reviewed_source(FRONT_SOURCE)
    cap_source = _load_reviewed_source(CAP_SOURCE)
    if ART_ROOT.exists():
        shutil.rmtree(ART_ROOT)
    ART_ROOT.mkdir(parents=True)

    modules: list[dict] = []
    assets: list[dict] = []
    for source_module in source_modules:
        module, asset = build_module(source_module, front_source, cap_source)
        modules.append(module)
        assets.append(asset)

    module_catalog["modules"] = [
        module
        for module in module_catalog.get("modules", [])
        if module.get("wall_family_id") != FAMILY_ID
    ] + modules
    write_json(MODULE_CATALOG, module_catalog)
    update_family_catalog()
    write_json(
        ASSET_CATALOG,
        {
            "asset_schema_version": 2,
            "catalog_id": "wooma_temple_wall_pack",
            "display_name": "标准灰绿色哥特寺庙直墙素材包",
            "source_policy": "imagegen_flat_sources_native_2to1_projection",
            "native_projection_contract_id": PROJECTION_CONTRACT_ID,
            "placement_contract_id": PLACEMENT_CONTRACT_ID,
            "corner_join_mode": "straight_overlap",
            "wall_family_ids": [FAMILY_ID],
            "collision_authority": "manual_by_user",
            "palette_role": "standard_reusable_temple_wall",
            "assets": assets,
        },
    )
    print(
        f"WOOMA_TEMPLE_WALL_BUILD_OK modules={len(modules)} "
        f"assets={len(assets)} corners=0 pillars=0 root={ART_ROOT}"
    )


if __name__ == "__main__":
    main()
