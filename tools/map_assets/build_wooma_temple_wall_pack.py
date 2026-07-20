#!/usr/bin/env python3
"""Build the Wooma Temple wall family from reviewed generated source sheets.

The source sheets live under outputs/wooma_temple_generated and are intentionally
not versioned. The generated, transparent, calibrated wall modules and their
catalog records are versioned project assets.
"""

from __future__ import annotations

import copy
import hashlib
import json
from pathlib import Path
import shutil

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[2]
SOURCE_DIR = ROOT / "outputs" / "wooma_temple_generated"
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

SOURCE_REFERENCE = (
    r"C:\Users\Administrator\Desktop\sucai\新增\立柱"
    r"\ChatGPT Image 2026年7月19日 22_29_59.png"
)
FAMILY_ID = "wooma_temple_gothic_stone_u0"
SOCKET_ID = "wooma_temple_gothic_stone_socket_u0"
SOURCE_FAMILY_ID = "orc_tomb_rough_stone_u0"
SOURCE_PREFIX = "orc_tomb_wall_"
TARGET_PREFIX = "wooma_temple_wall_"

STRAIGHT_BOXES = [
    (76, 220, 419, 658),
    (517, 221, 858, 662),
    (975, 222, 1249, 625),
    (1379, 223, 1679, 640),
]
ADAPTER_BOXES = [
    (52, 222, 413, 652),
    (483, 222, 845, 655),
    (914, 235, 1282, 667),
    (1362, 235, 1725, 667),
]
PILLAR_BOXES = [
    (40, 298, 211, 617),
    (265, 297, 431, 616),
    (485, 298, 650, 617),
    (700, 298, 865, 616),
    (920, 299, 1083, 618),
    (1135, 299, 1298, 617),
    (1351, 299, 1515, 618),
    (1568, 302, 1733, 618),
]

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
        raise RuntimeError("source crop has no visible pixels")
    return rgba.crop(box)


def crop_sheet(sheet: Image.Image, box: tuple[int, int, int, int]) -> Image.Image:
    return alpha_trim(sheet.crop(box))


def fit_on_canvas(
    image: Image.Image,
    canvas_size: tuple[int, int],
    target_size: tuple[int, int],
    *,
    center_x: int,
    bottom_y: int,
) -> Image.Image:
    source = alpha_trim(image)
    ratio = min(target_size[0] / source.width, target_size[1] / source.height)
    size = (
        max(1, int(round(source.width * ratio))),
        max(1, int(round(source.height * ratio))),
    )
    resized = source.resize(size, RESAMPLE)
    canvas = Image.new("RGBA", canvas_size, (0, 0, 0, 0))
    left = int(round(center_x - resized.width / 2))
    top = bottom_y - resized.height
    canvas.alpha_composite(resized, (left, top))
    return canvas


def stretch_on_canvas(
    image: Image.Image,
    canvas_size: tuple[int, int],
    target_size: tuple[int, int],
    *,
    center_x: int,
    bottom_y: int,
) -> Image.Image:
    source = alpha_trim(image)
    resized = source.resize(target_size, RESAMPLE)
    canvas = Image.new("RGBA", canvas_size, (0, 0, 0, 0))
    left = int(round(center_x - resized.width / 2))
    top = bottom_y - resized.height
    canvas.alpha_composite(resized, (left, top))
    return canvas


def mirror(image: Image.Image) -> Image.Image:
    return image.transpose(Image.Transpose.FLIP_LEFT_RIGHT)


def composite(images: list[Image.Image], size: tuple[int, int]) -> Image.Image:
    result = Image.new("RGBA", size, (0, 0, 0, 0))
    for image in images:
        result.alpha_composite(image)
    return result


def place_anchored(
    source: Image.Image,
    source_anchor: tuple[int, int],
    target_size: tuple[int, int],
    target_anchor: tuple[int, int],
) -> Image.Image:
    result = Image.new("RGBA", target_size, (0, 0, 0, 0))
    position = (
        target_anchor[0] - source_anchor[0],
        target_anchor[1] - source_anchor[1],
    )
    result.alpha_composite(source, position)
    return result


def save_png(image: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, format="PNG", optimize=True)


def res_path(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def display_name(module: dict) -> str:
    topology = str(module["topology"])
    axis = str(module.get("axis") or "")
    length = int(module.get("length_tiles", 1))
    variant = int(module.get("variant", 1))
    names = {
        "straight": "直墙",
        "inner_corner": "内转角",
        "outer_corner": "外转角",
        "end_cap": "墙体端头",
        "door_adapter": "门洞墙",
        "broken_adapter": "破损墙",
        "seam_cover": "接缝立柱",
    }
    axis_name = {"iso_x": "X向", "iso_y": "Y向"}.get(axis, "")
    suffix = f" {length}格" if topology in {"straight", "door_adapter", "broken_adapter"} else ""
    return f"沃玛寺庙{names[topology]} {axis_name}{suffix} 变体{variant}".replace("  ", " ")


def normalized_continuous_wall() -> Image.Image:
    with Image.open(SOURCE_DIR / "continuous_wall_alpha_v4.png") as opened:
        return alpha_trim(opened.convert("RGBA"))


def normalized_adapters() -> list[Image.Image]:
    with Image.open(SOURCE_DIR / "adapter_sheet_alpha.png") as opened:
        sheet = opened.convert("RGBA")
    result: list[Image.Image] = []
    for box in ADAPTER_BOXES:
        result.append(crop_sheet(sheet, box))
    return result


def normalized_pillars() -> list[Image.Image]:
    with Image.open(SOURCE_DIR / "pillar_sheet_alpha.png") as opened:
        sheet = opened.convert("RGBA")
    result: list[Image.Image] = []
    for box in PILLAR_BOXES:
        result.append(crop_sheet(sheet, box))
    return result


def continuous_wall_window(
    source: Image.Image,
    length: int,
    variant_seed: int,
) -> Image.Image:
    source = alpha_trim(source)
    fraction = min(1.0, max(0.25, length / 4.0))
    window_width = max(1, int(round(source.width * fraction)))
    available = max(0, source.width - window_width)
    variant_ratio = (variant_seed % 3) / 2.0 if available > 0 else 0.0
    left = int(round(available * variant_ratio))
    return alpha_trim(source.crop((left, 0, left + window_width, source.height)))


def split_continuous_parts(
    artwork: Image.Image,
    length: int,
    axis: str,
) -> list[Image.Image]:
    if length <= 1:
        return [artwork.copy()]
    alpha_box = artwork.getchannel("A").getbbox()
    if alpha_box is None:
        raise RuntimeError("continuous wall artwork has no visible pixels")
    left, _top, right, _bottom = alpha_box
    width = max(1, right - left)
    parts = [
        Image.new("RGBA", artwork.size, (0, 0, 0, 0))
        for _index in range(length)
    ]
    for x in range(left, right):
        normalized = min(length - 1, int((x - left) * length / width))
        index = normalized if axis == "iso_x" else length - 1 - normalized
        column = artwork.crop((x, 0, x + 1, artwork.height))
        parts[index].alpha_composite(column, (x, 0))
    return parts


def _alpha_baseline_y(image: Image.Image, x: int, radius: int = 3) -> int:
    alpha = image.getchannel("A")
    values: list[int] = []
    for sample_x in range(max(0, x - radius), min(image.width, x + radius + 1)):
        visible = [
            y
            for y in range(image.height)
            if alpha.getpixel((sample_x, y)) > 32
        ]
        if visible:
            values.append(max(visible))
    if not values:
        raise RuntimeError(f"no visible seam pixels near x={x}")
    values.sort()
    return values[len(values) // 2]


def _alpha_top_y(image: Image.Image, x: int, radius: int = 1) -> int:
    alpha = image.getchannel("A")
    values: list[int] = []
    for sample_x in range(max(0, x - radius), min(image.width, x + radius + 1)):
        visible = [
            y
            for y in range(image.height)
            if alpha.getpixel((sample_x, y)) > 32
        ]
        if visible:
            values.append(min(visible))
    if not values:
        raise RuntimeError(f"no visible top pixels near x={x}")
    values.sort()
    return values[len(values) // 2]


def align_wall_seams(
    artwork: Image.Image,
    start_seam: tuple[int, int],
    end_seam: tuple[int, int],
) -> Image.Image:
    start_x, target_start_y = start_seam
    end_x, target_end_y = end_seam
    measured_start_y = _alpha_baseline_y(artwork, start_x)
    measured_end_y = _alpha_baseline_y(artwork, end_x)
    span = max(1, end_x - start_x)
    result = Image.new("RGBA", artwork.size, (0, 0, 0, 0))
    for x in range(artwork.width):
        ratio = (x - start_x) / span
        measured_y = measured_start_y + (measured_end_y - measured_start_y) * ratio
        target_y = target_start_y + (target_end_y - target_start_y) * ratio
        shift = int(round(target_y - measured_y))
        column = artwork.crop((x, 0, x + 1, artwork.height))
        result.alpha_composite(column, (x, shift))
    return result


def paint_isometric_cap_joints(
    artwork: Image.Image,
    length: int,
) -> Image.Image:
    """Lock coping joints to the opposite 2:1 isometric map axis."""
    overlay = Image.new("RGBA", artwork.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    for tile_index in range(length + 1):
        seam_x = 32 + 32 * tile_index
        back_x = min(artwork.width - 1, seam_x + 4)
        front_x = max(0, seam_x - 5)
        back_y = _alpha_top_y(artwork, back_x) + 1
        front_y = back_y + 5
        draw.line(
            [(back_x, back_y), (front_x, front_y)],
            fill=(58, 54, 45, 210),
            width=1,
        )
        draw.line(
            [(back_x, back_y - 1), (front_x, front_y - 1)],
            fill=(206, 201, 174, 105),
            width=1,
        )
    clipped_alpha = Image.composite(
        overlay.getchannel("A"),
        Image.new("L", artwork.size, 0),
        artwork.getchannel("A"),
    )
    overlay.putalpha(clipped_alpha)
    result = artwork.copy()
    result.alpha_composite(overlay)
    return result


def straight_art(
    module: dict,
    continuous_wall: Image.Image,
    variant_seed: int,
) -> tuple[Image.Image, list[Image.Image]]:
    axis = str(module["axis"])
    length = int(module["length_tiles"])
    size = tuple(int(value) for value in module["canvas_size"])
    # Preserve the proven orc-tomb module geometry inherited by this family.
    # The previous Wooma-only normalization compressed 48 px of elevation and
    # clipped the side overhang, turning a temple wall into a low fence.
    visual_size = (32 * length + 40, 128 + 16 * length)
    source = continuous_wall_window(continuous_wall, length, variant_seed)
    artwork = stretch_on_canvas(
        source,
        size,
        visual_size,
        center_x=size[0] // 2,
        bottom_y=size[1],
    )
    start_seam = tuple(int(value) for value in module["start_seam_px"])
    end_seam = tuple(int(value) for value in module["end_seam_px"])
    artwork = align_wall_seams(
        artwork,
        (32, start_seam[1]),
        (32 + 32 * length, end_seam[1]),
    )
    artwork = paint_isometric_cap_joints(artwork, length)
    if axis == "iso_y":
        artwork = mirror(artwork)
    return artwork, split_continuous_parts(artwork, length, axis)


def corner_art(
    module: dict,
    pillars: list[Image.Image],
) -> Image.Image:
    size = tuple(int(value) for value in module["canvas_size"])
    anchor = tuple(int(value) for value in module["anchor"])
    asset_id = str(module["asset_id"])
    # At a 64x32 isometric tile ratio, advancing one half-cell sideways changes
    # screen Y by eight pixels, not sixteen. The back (+,+) and front (-,-)
    # corners therefore need equal and opposite 8 px depth compensation; the
    # two side corners remain on the neutral seam baseline.
    depth_compensation = (
        8
        if "_se_" in asset_id
        else -8
        if "_nw_" in asset_id
        else 0
    )
    lateral_compensation = (
        16
        if "_ne_" in asset_id
        else -16
        if "_sw_" in asset_id
        else 0
    )
    # A closed loop already brings both straight-wall sockets to the corner
    # tile. The corner artwork must therefore only cover that seam. Building a
    # second pair of wall faces here double-renders the joint and creates the
    # visibly detached V/< /> shapes that this pack previously produced.
    #
    # Keep all four directional corner IDs for topology lookup, but render one
    # clean, symmetric pillar at each corner. This is the same calibrated seam
    # pillar used elsewhere in the family, so its base overlaps both adjoining
    # wall feet without inventing another wall plane.
    return stretch_on_canvas(
        pillars[0],
        size,
        (72, 154),
        center_x=anchor[0] + lateral_compensation,
        bottom_y=anchor[1] + 38 + depth_compensation,
    )


def pillar_art(module: dict, pillars: list[Image.Image], variant_seed: int) -> Image.Image:
    size = tuple(int(value) for value in module["canvas_size"])
    anchor = tuple(int(value) for value in module["anchor"])
    topology = str(module["topology"])
    target_size = (72, 148) if topology == "end_cap" else (58, 96)
    bottom_y = size[1] if topology == "end_cap" else anchor[1] + 8
    return stretch_on_canvas(
        pillars[variant_seed % len(pillars)],
        size,
        target_size,
        center_x=anchor[0],
        bottom_y=bottom_y,
    )


def adapter_art(module: dict, adapters: list[Image.Image]) -> Image.Image:
    topology = str(module["topology"])
    axis = str(module["axis"])
    source_index = {
        ("door_adapter", 1): 0,
        ("door_adapter", 2): 1,
        ("broken_adapter", 1): 2,
        ("broken_adapter", 2): 3,
    }[(topology, int(module.get("variant", 1)))]
    source = adapters[source_index]
    length = int(module.get("length_tiles", 3))
    size = tuple(int(value) for value in module["canvas_size"])
    artwork = stretch_on_canvas(
        source,
        size,
        (32 * length + 40, 128 + 16 * length),
        center_x=size[0] // 2,
        bottom_y=size[1],
    )
    if axis == "iso_y":
        artwork = mirror(artwork)
    return artwork


def build_module(
    source_module: dict,
    continuous_wall: Image.Image,
    adapters: list[Image.Image],
    pillars: list[Image.Image],
) -> tuple[dict, dict]:
    module = copy.deepcopy(source_module)
    asset_id = str(module["asset_id"]).replace(SOURCE_PREFIX, TARGET_PREFIX, 1)
    module["asset_id"] = asset_id
    module["display_name"] = display_name(module)
    module["category"] = "dungeon_wall"
    module["theme"] = "wooma_temple"
    module["wall_family_id"] = FAMILY_ID
    module["socket_profile_id"] = SOCKET_ID
    module["content_layer"] = "personal_expansion"
    module["collision_cells"] = []
    module["placement_clearance_cells"] = []
    module["collision_policy"] = "none"
    module["navigation_policy"] = "ignore"
    module["manual_collision_expected"] = True
    module["collision_authority"] = "manual_by_user"
    module["collision_profile_id"] = "none_visual"
    module["calibration_status"] = "placeable"
    module["placeable"] = True
    module["repeat_group"] = str(module.get("repeat_group", "")).replace(
        "orc_tomb_", "wooma_temple_", 1
    )
    for connector in module.get("connectors", []):
        connector["socket_profile_id"] = SOCKET_ID

    topology = str(module["topology"])
    variant_seed = max(0, int(module.get("variant", 1)) - 1)
    if topology == "straight":
        artwork, parts = straight_art(module, continuous_wall, variant_seed)
    elif topology in {"inner_corner", "outer_corner"}:
        artwork = corner_art(module, pillars)
        parts = [artwork]
    elif topology in {"door_adapter", "broken_adapter"}:
        artwork = adapter_art(module, adapters)
        parts = [artwork]
        module["render_mode"] = "single_part"
    elif topology in {"end_cap", "seam_cover"}:
        artwork = pillar_art(module, pillars, variant_seed)
        parts = [artwork]
    else:
        raise RuntimeError(f"unsupported topology: {topology}")

    asset_dir = ART_ROOT / asset_id
    if asset_dir.exists():
        shutil.rmtree(asset_dir)
    asset_dir.mkdir(parents=True)
    composite_path = asset_dir / "composite.png"
    save_png(artwork, composite_path)

    render_parts: list[dict] = []
    for index, part_image in enumerate(parts):
        part_path = asset_dir / f"part_{index:02d}_base.png"
        save_png(part_image, part_path)
        if topology == "straight":
            tile_offset = [index, 0] if module["axis"] == "iso_x" else [0, index]
        elif topology in {"door_adapter", "broken_adapter"}:
            tile_offset = [1, 0] if module["axis"] == "iso_x" else [0, 1]
        else:
            tile_offset = [0, 0]
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
    module["render_parts"] = render_parts

    size = list(artwork.size)
    digest = sha256(composite_path)
    asset = {
        **copy.deepcopy(module),
        "category": "wall_module",
        "object_class": "wall",
        "image": res_path(composite_path),
        "thumbnail": res_path(composite_path),
        "image_size": size,
        "visible_bounds_px": [0, 0, size[0], size[1]],
        "anchor_px": list(module["anchor"]),
        "placement_anchor_px": list(module["anchor"]),
        "anchor_tile": [0, 0],
        "anchor_mode": "foot_tile",
        "visual_footprint_tiles": list(module["footprint_tiles"]),
        "occupancy_footprint_tiles": list(module["footprint_tiles"]),
        "base_footprint_tiles": list(module["footprint_tiles"]),
        "collision_footprint_tiles": [0, 0],
        "tile_size": [64, 32],
        "approved_scale": 1.0,
        "logical_scale_level": 0,
        "scale_approved": True,
        "anchor_approved": True,
        "default_object_role": "terrain",
        "palette_path": (
            "洞穴与地下城/墙体模块/沃玛寺庙墙体/"
            f"{topology}/{module.get('axis') or '通用'}"
        ),
        "source_external_path": SOURCE_REFERENCE,
        "source_sha256": digest,
        "output_sha256": digest,
        "thumbnail_source_sha256": digest,
        "processing": "codex_imagegen_chroma_key_crop_grid_calibration",
        "generation_source_ids": [
            "call_cyNH4ptmEJLuV8B1ng02tFGb",
            "call_xsfjESoCTQVCnquzeXlIB5Rj",
            "call_bGEyuBMpAVbjI6KDM5QBFjkp",
            "call_8raUM7XLx5zAr6dA5fOpgLsh",
            "call_Y9TZ7EPiCWQgV026MYpIRyNL",
            "call_yV5OeDNzIezU9yrVumYXQqEu",
            "call_QwTKuxDXelxir3RMaDjAzlXe",
        ],
        "tags": [
            "cave_dungeon",
            "wooma_temple",
            "wall_module",
            FAMILY_ID,
            topology,
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
            "display_name": "沃玛寺庙哥特旧石墙 U0",
            "theme": "wooma_temple",
            "material": "gothic_gray_green_stone",
            "socket_profile_id": SOCKET_ID,
            "tile_size": [64, 32],
            "wall_height_px": 96,
            "side_pad_px": 16,
            "allowed_lengths": [1, 2, 3, 4],
            "primary_lengths": [4, 3],
            "repair_lengths": [2, 1],
            "default_blocked_side": "outside",
            "seam_guard_px": 16,
            "seam_overlap_px": 2,
            "seam_cover_asset_ids": [
                f"{TARGET_PREFIX}seam_cover_{index:02d}" for index in range(1, 7)
            ],
            "palette_id": "wooma_temple_gothic_stone_u0",
            "content_layer": "personal_expansion",
            "collision_authority": "manual_by_user",
            "enabled": True,
        }
    )
    write_json(FAMILY_CATALOG, catalog)


def main() -> None:
    required = [
        SOURCE_DIR / "continuous_wall_alpha_v4.png",
        SOURCE_DIR / "adapter_sheet_alpha.png",
        SOURCE_DIR / "pillar_sheet_alpha.png",
    ]
    missing = [str(path) for path in required if not path.is_file()]
    if missing:
        raise RuntimeError(f"missing reviewed source sheets: {missing}")

    module_catalog = read_json(MODULE_CATALOG)
    source_modules = [
        module
        for module in module_catalog.get("modules", [])
        if module.get("wall_family_id") == SOURCE_FAMILY_ID
    ]
    if len(source_modules) != 42:
        raise RuntimeError(f"expected 42 source modules, found {len(source_modules)}")

    continuous_wall = normalized_continuous_wall()
    adapters = normalized_adapters()
    pillars = normalized_pillars()

    modules: list[dict] = []
    assets: list[dict] = []
    for source_module in source_modules:
        module, asset = build_module(
            source_module,
            continuous_wall,
            adapters,
            pillars,
        )
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
            "display_name": "沃玛寺庙墙体素材包",
            "source_policy": "codex_imagegen_reviewed_chroma_key_calibrated",
            "wall_family_ids": [FAMILY_ID],
            "collision_authority": "manual_by_user",
            "assets": assets,
        },
    )
    print(
        f"WOOMA_TEMPLE_WALL_BUILD_OK modules={len(modules)} "
        f"assets={len(assets)} root={ART_ROOT}"
    )


if __name__ == "__main__":
    main()
