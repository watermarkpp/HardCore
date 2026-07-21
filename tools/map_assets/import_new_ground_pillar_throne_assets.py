"""Cut and import the transparent ground, pillar, and throne sprite sheets."""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import shutil
from collections import deque
from dataclasses import dataclass
from pathlib import Path

from PIL import Image, ImageChops, ImageFilter


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_SOURCE_ROOT = Path.home() / "Desktop" / "sucai" / "新增"
PALETTE_ROOT = ROOT / "assets/art/maps/_shared/user_palette"
CATALOG_PATH = (
    ROOT / "assets/data/assets/map_new_ground_pillar_throne_asset_catalog.json"
)
PACKAGE_ID = "mse_new_ground_pillar_throne_42_v1"
TILE_SIZE = [64, 32]
CROP_PADDING = 4
CLUSTER_JOIN_KERNEL = 15


@dataclass(frozen=True)
class SheetGroup:
    source_folder: str
    destination_parts: tuple[str, ...]
    file_prefix: str
    asset_prefix: str
    columns: int
    rows: int
    expected_sheets: int
    footprint: tuple[int, int]
    asset_type: str
    category: str
    object_class: str
    anchor_mode: str
    default_layer: str
    occlusion: bool


GROUPS = (
    SheetGroup(
        source_folder="地面",
        destination_parts=("地面", "新增石板地面"),
        file_prefix="stone_ground",
        asset_prefix="mse.new_ground.stone_platform",
        columns=3,
        rows=2,
        expected_sheets=2,
        footprint=(1, 1),
        asset_type="ground_brush",
        category="ground",
        object_class="ground",
        anchor_mode="tile_center",
        default_layer="ground_base",
        occlusion=False,
    ),
    SheetGroup(
        source_folder="立柱",
        destination_parts=("装饰物1", "立柱"),
        file_prefix="gothic_pillar",
        asset_prefix="mse.new_pillar",
        columns=4,
        rows=2,
        expected_sheets=3,
        footprint=(3, 3),
        asset_type="large_prop",
        category="decoration",
        object_class="decoration",
        anchor_mode="foot_tile",
        default_layer="object_base",
        occlusion=True,
    ),
    SheetGroup(
        source_folder="王座",
        destination_parts=("装饰物1", "王座"),
        file_prefix="gothic_throne",
        asset_prefix="mse.new_throne",
        columns=3,
        rows=2,
        expected_sheets=1,
        footprint=(6, 6),
        asset_type="large_prop",
        category="decoration",
        object_class="decoration",
        anchor_mode="foot_tile",
        default_layer="object_base",
        occlusion=True,
    ),
)


def sha256(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def discover_sheets(source_root: Path, group: SheetGroup) -> list[Path]:
    source_directory = source_root / group.source_folder
    if not source_directory.is_dir():
        raise SystemExit(f"missing source directory: {source_directory}")
    sheets = sorted(source_directory.glob("*.png"), key=lambda path: path.name.casefold())
    if len(sheets) != group.expected_sheets:
        raise SystemExit(
            f"{group.source_folder}: expected {group.expected_sheets} PNG sheets, "
            f"got {len(sheets)}"
        )
    return sheets


def validate_source(image: Image.Image, source_path: Path) -> Image.Image:
    rgba = image.convert("RGBA")
    alpha_min, alpha_max = rgba.getchannel("A").getextrema()
    if alpha_min != 0 or alpha_max != 255:
        raise ValueError(
            f"{source_path.name}: expected transparent and opaque pixels, "
            f"got alpha extrema {(alpha_min, alpha_max)}"
        )
    return rgba


def cut_grid_cell(
    source: Image.Image,
    columns: int,
    rows: int,
    column: int,
    row: int,
) -> tuple[Image.Image, list[int], list[int], int]:
    width, height = source.size
    cell_box = (
        column * width // columns,
        row * height // rows,
        (column + 1) * width // columns,
        (row + 1) * height // rows,
    )
    cell = source.crop(cell_box)
    cell, discarded_alpha_pixels = retain_primary_cluster(cell)
    alpha_box = cell.getchannel("A").getbbox()
    if alpha_box is None:
        raise ValueError(f"empty grid cell row={row + 1} column={column + 1}")
    cropped = cell.crop(alpha_box)
    output = Image.new(
        "RGBA",
        (cropped.width + CROP_PADDING * 2, cropped.height + CROP_PADDING * 2),
        (0, 0, 0, 0),
    )
    output.alpha_composite(cropped, (CROP_PADDING, CROP_PADDING))
    source_bounds = [
        cell_box[0] + alpha_box[0],
        cell_box[1] + alpha_box[1],
        cell_box[0] + alpha_box[2],
        cell_box[1] + alpha_box[3],
    ]
    visible_bounds = [
        CROP_PADDING,
        CROP_PADDING,
        output.width - CROP_PADDING,
        output.height - CROP_PADDING,
    ]
    return output, source_bounds, visible_bounds, discarded_alpha_pixels


def retain_primary_cluster(cell: Image.Image) -> tuple[Image.Image, int]:
    """Discard isolated spill from adjacent cells while retaining nearby rubble."""
    original_alpha = cell.getchannel("A")
    binary = original_alpha.point(lambda alpha: 255 if alpha > 0 else 0)
    joined = binary.filter(ImageFilter.MaxFilter(CLUSTER_JOIN_KERNEL))
    width, height = joined.size
    foreground = joined.tobytes()
    visited = bytearray(width * height)
    largest_component: list[int] = []

    for start, value in enumerate(foreground):
        if value == 0 or visited[start]:
            continue
        visited[start] = 1
        pending = deque([start])
        component: list[int] = []
        while pending:
            index = pending.popleft()
            component.append(index)
            x = index % width
            y = index // width
            for neighbor in (
                index - 1 if x > 0 else -1,
                index + 1 if x + 1 < width else -1,
                index - width if y > 0 else -1,
                index + width if y + 1 < height else -1,
            ):
                if (
                    neighbor >= 0
                    and foreground[neighbor] != 0
                    and not visited[neighbor]
                ):
                    visited[neighbor] = 1
                    pending.append(neighbor)
        if len(component) > len(largest_component):
            largest_component = component

    if not largest_component:
        raise ValueError("grid cell has no foreground cluster")
    keep_bytes = bytearray(width * height)
    for index in largest_component:
        keep_bytes[index] = 255
    keep_mask = Image.frombytes("L", (width, height), bytes(keep_bytes))
    filtered_alpha = ImageChops.multiply(original_alpha, keep_mask)
    original_count = sum(original_alpha.histogram()[1:])
    filtered_count = sum(filtered_alpha.histogram()[1:])
    cleaned = cell.copy()
    cleaned.putalpha(filtered_alpha)
    return cleaned, original_count - filtered_count


def png_payload(image: Image.Image) -> bytes:
    buffer = io.BytesIO()
    image.save(buffer, format="PNG", optimize=True)
    return buffer.getvalue()


def build_asset(
    *,
    group: SheetGroup,
    asset_index: int,
    sheet_index: int,
    row: int,
    column: int,
    source_path: Path,
    source_payload: bytes,
    output_path: Path,
    output_payload: bytes,
    output_size: tuple[int, int],
    source_bounds: list[int],
    visible_bounds: list[int],
    discarded_alpha_pixels: int,
) -> dict:
    width, height = output_size
    is_ground = group.asset_type == "ground_brush"
    anchor = (
        [width // 2, height // 2]
        if is_ground
        else [width // 2, max(0, visible_bounds[3] - 1)]
    )
    footprint = list(group.footprint)
    project_image = output_path.relative_to(ROOT).as_posix()
    asset = {
        "asset_id": f"{group.asset_prefix}.{asset_index:02d}",
        "display_name": (
            f"新增石板地面 {asset_index:02d}"
            if group.source_folder == "地面"
            else f"{group.source_folder} {asset_index:02d}"
        ),
        "asset_type": group.asset_type,
        "category": group.category,
        "object_class": group.object_class,
        "theme": "gothic_ruins",
        "image": project_image,
        "thumbnail": project_image,
        "canvas_size": [width, height],
        "image_size": [width, height],
        "visible_bounds_px": visible_bounds,
        "anchor_px": anchor,
        "placement_anchor_px": anchor,
        "anchor_tile": [0, 0],
        "anchor_mode": group.anchor_mode,
        "footprint_tiles": footprint,
        "visual_footprint_tiles": footprint,
        "occupancy_footprint_tiles": footprint,
        "base_footprint_tiles": footprint,
        "collision_footprint_tiles": [0, 0],
        "collision_cells": [],
        "placement_clearance_cells": [],
        "tile_size": TILE_SIZE,
        "approved_scale": 1.0,
        "logical_scale_level": 0,
        "scale_approved": True,
        "anchor_approved": True,
        "default_layer": group.default_layer,
        "default_object_role": "decoration",
        "collision_policy": "none",
        "collision_profile_id": "none_visual",
        "navigation_policy": "ignore",
        "manual_collision_expected": not is_ground,
        "map_collision_override": "default",
        "collision_authority": "ground_visual" if is_ground else "manual_by_user",
        "occlusion": group.occlusion,
        "content_layer": "personal_expansion",
        "placeable": True,
        "calibration_status": "placeable",
        "calibration_source": "transparent_sheet_grid_alpha_crop_v1",
        "palette_path": "/".join(group.destination_parts),
        "source_external_path": str(source_path),
        "source_sha256": sha256(source_payload),
        "output_sha256": sha256(output_payload),
        "thumbnail_source_sha256": sha256(output_payload),
        "processing": {
            "pipeline": "fixed_grid_alpha_bbox_crop_v1",
            "sheet_grid": [group.columns, group.rows],
            "sheet_index": sheet_index,
            "grid_row": row + 1,
            "grid_column": column + 1,
            "source_bounds_px": source_bounds,
            "padding_px": CROP_PADDING,
            "cluster_join_kernel_px": CLUSTER_JOIN_KERNEL,
            "discarded_alpha_pixels": discarded_alpha_pixels,
        },
        "tags": [
            "new_local_asset",
            "transparent_sheet_cut",
            group.source_folder,
            *group.destination_parts,
        ],
        "editable": True,
        "allows_edge_clipping": False,
        "semantic_role": "",
        "trigger_on_enter": False,
        "package_id": PACKAGE_ID,
        "source_group": group.source_folder,
        "source_sheet_index": sheet_index,
        "source_grid": [column + 1, row + 1],
        "projection": "orthographic_isometric_2_to_1",
    }
    if is_ground:
        asset.update(
            {
                "ground_brush_role": "base_tile",
                "terrain_type": "gothic_stone_platform",
                "paintable": True,
                "normalization": "runtime_alpha_bounds_to_64x32_diamond_mask",
                "diamond_inner_coverage": 1.0,
            }
        )
    return asset


def clear_generated_directory(destination: Path) -> None:
    destination.resolve().relative_to(PALETTE_ROOT.resolve())
    if destination.exists():
        shutil.rmtree(destination)
    destination.mkdir(parents=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-root", type=Path, default=DEFAULT_SOURCE_ROOT)
    args = parser.parse_args()
    source_root = args.source_root.resolve()

    catalog_assets: list[dict] = []
    source_count = 0
    group_counts: dict[str, int] = {}
    for group in GROUPS:
        sheets = discover_sheets(source_root, group)
        destination = PALETTE_ROOT.joinpath(*group.destination_parts)
        clear_generated_directory(destination)
        asset_index = 0
        for sheet_index, source_path in enumerate(sheets, start=1):
            source_payload = source_path.read_bytes()
            with Image.open(io.BytesIO(source_payload)) as source_image:
                source = validate_source(source_image, source_path)
                for row in range(group.rows):
                    for column in range(group.columns):
                        asset_index += 1
                        (
                            output,
                            source_bounds,
                            visible_bounds,
                            discarded_alpha_pixels,
                        ) = cut_grid_cell(
                            source,
                            group.columns,
                            group.rows,
                            column,
                            row,
                        )
                        output_path = (
                            destination
                            / f"{group.file_prefix}_{asset_index:02d}.png"
                        )
                        output_payload = png_payload(output)
                        output_path.write_bytes(output_payload)
                        catalog_assets.append(
                            build_asset(
                                group=group,
                                asset_index=asset_index,
                                sheet_index=sheet_index,
                                row=row,
                                column=column,
                                source_path=source_path,
                                source_payload=source_payload,
                                output_path=output_path,
                                output_payload=output_payload,
                                output_size=output.size,
                                source_bounds=source_bounds,
                                visible_bounds=visible_bounds,
                                discarded_alpha_pixels=discarded_alpha_pixels,
                            )
                        )
            source_count += 1
        group_counts[group.source_folder] = asset_index

    expected_counts = {"地面": 12, "立柱": 24, "王座": 6}
    if group_counts != expected_counts:
        raise SystemExit(f"unexpected asset counts: {group_counts}")
    asset_ids = [str(asset["asset_id"]) for asset in catalog_assets]
    if len(asset_ids) != len(set(asset_ids)):
        raise SystemExit("duplicate stable asset id")

    catalog = {
        "asset_schema_version": 2,
        "package_id": PACKAGE_ID,
        "package_version": 1,
        "source_root": str(source_root),
        "source_count": source_count,
        "asset_count": len(catalog_assets),
        "group_counts": group_counts,
        "classifications": {
            "地面": "地面/新增石板地面",
            "立柱": "装饰物1/立柱",
            "王座": "装饰物1/王座",
        },
        "cutting_policy": (
            "fixed_grid_primary_alpha_cluster_then_bbox_with_padding"
        ),
        "assets": catalog_assets,
    }
    CATALOG_PATH.write_text(
        json.dumps(catalog, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(
        "MSE_NEW_GROUND_PILLAR_THRONE_IMPORT_PASS "
        "sources=6 assets=42 ground=12 pillars=24 thrones=6"
    )


if __name__ == "__main__":
    main()
