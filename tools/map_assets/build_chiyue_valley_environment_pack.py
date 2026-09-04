from __future__ import annotations

import hashlib
import json
import shutil
from collections import deque
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[2]
ART_ROOT = ROOT / "assets/art/maps/_shared/terrain/chiyue_valley"
SOURCE_ROOT = ART_ROOT / "source"
ROCK_ROOT = ART_ROOT / "ground_rocks"
FLOOR_ROOT = ART_ROOT / "floor"
DATA_ROOT = ROOT / "assets/data/assets"

GENERATED = Path(
    r"C:\Users\Administrator\.codex\generated_images\01a01ede-3674-7e13-9da2-95fcf6ab1745"
)

ROCK_SOURCES = [
    "exec-fe631dfa-b0ca-4f5f-ba77-1a4b848f3468.png",
    "exec-d21b74d5-be77-49dc-9a9d-5bfed1e5cd80.png",
    "exec-48a22952-42c7-49b1-85a0-833a29272f30.png",
    "exec-5bc71d32-9a3c-44c9-ae78-f5fa320d80cb.png",
    "exec-4c73911e-249e-4159-8640-511e2eb7b7ac.png",
    "exec-e874d106-888b-4769-bd92-cce9e014b548.png",
    "exec-19ebce97-8571-4578-a7c4-a6ca35024197.png",
    "exec-966c9b1c-56b9-49ca-8103-0421d9087174.png",
    "exec-2228e6ed-5cdf-46d9-bd5c-1f4958421057.png",
    "exec-8ddf4531-99ce-4f70-b80a-68a6b409ba06.png",
    "exec-2da6bd82-ad45-4484-9340-f7b7516458cd.png",
    "exec-8191cdf0-61e8-408a-a569-93cd04a2411d.png",
]

FLOOR_SOURCES = [
    "exec-da423b96-7d0e-471d-9880-6025be424151.png",
    "exec-ad386870-ff2c-43f3-b67d-b7f0b5e9ae22.png",
    "exec-501c9569-5454-44ea-916b-ff2009aed717.png",
    "exec-b188141c-c56a-4ee0-a35d-c78bc9d7558d.png",
    "exec-aff1b083-8430-47bc-b072-2a0124032bb4.png",
    "exec-0ddb366d-53d0-4a19-9243-debebe04c985.png",
]

# Maximum visible dimensions. These preserve intentional differences in silhouette
# while keeping the props practical beside a 64x32 map cell.
ROCK_TARGETS = [
    (152, 88),
    (112, 112),
    (88, 184),
    (144, 144),
    (152, 96),
    (160, 112),
    (136, 120),
    (168, 120),
    (176, 112),
    (176, 120),
    (112, 176),
    (192, 104),
]


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def repo_path(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def _border_connected_background(rgb: np.ndarray) -> np.ndarray:
    """Return only near-neutral bright pixels connected to the canvas border."""
    minimum = rgb.min(axis=2)
    maximum = rgb.max(axis=2)
    chroma = maximum.astype(np.int16) - minimum.astype(np.int16)
    candidate = (minimum >= 178) & (chroma <= 42)
    h, w = candidate.shape
    background = np.zeros((h, w), dtype=np.uint8)
    queue: deque[tuple[int, int]] = deque()

    def seed(y: int, x: int) -> None:
        if candidate[y, x] and background[y, x] == 0:
            background[y, x] = 1
            queue.append((y, x))

    for x in range(w):
        seed(0, x)
        seed(h - 1, x)
    for y in range(h):
        seed(y, 0)
        seed(y, w - 1)
    while queue:
        y, x = queue.popleft()
        for yy, xx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
            if 0 <= yy < h and 0 <= xx < w and candidate[yy, xx] and background[yy, xx] == 0:
                background[yy, xx] = 1
                queue.append((yy, xx))
    return background.astype(bool)


def _remove_small_foreground(mask: np.ndarray) -> np.ndarray:
    count, labels, stats, _ = cv2.connectedComponentsWithStats(mask.astype(np.uint8), 8)
    keep = np.zeros_like(mask, dtype=bool)
    for label in range(1, count):
        area = int(stats[label, cv2.CC_STAT_AREA])
        if area >= 1200:
            keep |= labels == label
    return keep


def extract_rock_rgba(source: Image.Image) -> tuple[Image.Image, str]:
    rgba = np.asarray(source.convert("RGBA"), dtype=np.uint8)
    source_alpha = rgba[:, :, 3]
    if int(source_alpha.min()) < 255:
        alpha = source_alpha.copy()
        method = "native_alpha_preserved"
    else:
        background = _border_connected_background(rgba[:, :, :3])
        foreground = _remove_small_foreground(~background)
        # Erode one source pixel, then feather the following three pixels.
        # At the final downscaled size this removes baked white/checker antialias
        # without taking a visible bite out of the rock silhouette.
        distance = cv2.distanceTransform(foreground.astype(np.uint8), cv2.DIST_L2, 5)
        alpha = np.clip((distance - 1.0) * 85.0, 0.0, 255.0).astype(np.uint8)
        method = "border_connected_neutral_key_distance_matte_v1"

    alpha[alpha < 4] = 0
    ys, xs = np.where(alpha > 0)
    if not len(xs):
        raise RuntimeError("background extraction produced an empty rock")
    x0, x1 = int(xs.min()), int(xs.max()) + 1
    y0, y1 = int(ys.min()), int(ys.max()) + 1
    out = rgba[y0:y1, x0:x1].copy()
    out[:, :, 3] = alpha[y0:y1, x0:x1]
    out[out[:, :, 3] == 0, :3] = 0
    return Image.fromarray(out, "RGBA"), method


def resize_rgba_premultiplied(image: Image.Image, maximum: tuple[int, int]) -> Image.Image:
    width, height = image.size
    scale = min(maximum[0] / width, maximum[1] / height)
    size = (max(1, round(width * scale)), max(1, round(height * scale)))
    arr = np.asarray(image.convert("RGBA"), dtype=np.float32) / 255.0
    alpha = arr[:, :, 3:4]
    premul = np.concatenate((arr[:, :, :3] * alpha, alpha), axis=2)
    resized = cv2.resize(premul, size, interpolation=cv2.INTER_AREA)
    out_alpha = resized[:, :, 3:4]
    out_rgb = np.divide(
        resized[:, :, :3],
        np.maximum(out_alpha, 1.0 / 255.0),
        out=np.zeros_like(resized[:, :, :3]),
        where=out_alpha > 0,
    )
    out = np.concatenate((out_rgb, out_alpha), axis=2)
    out = np.clip(out * 255.0 + 0.5, 0, 255).astype(np.uint8)
    out[out[:, :, 3] == 0, :3] = 0
    return Image.fromarray(out, "RGBA")


def pad(image: Image.Image, amount: int = 8) -> Image.Image:
    canvas = Image.new("RGBA", (image.width + amount * 2, image.height + amount * 2), (0, 0, 0, 0))
    canvas.alpha_composite(image, (amount, amount))
    return canvas


def alpha_bbox(image: Image.Image) -> tuple[int, int, int, int]:
    bbox = image.getchannel("A").getbbox()
    if bbox is None:
        raise RuntimeError("empty alpha")
    x0, y0, x1, y1 = bbox
    return x0, y0, x1 - x0, y1 - y0


def make_diamond(source: Image.Image) -> Image.Image:
    texture = source.convert("RGB").resize((256, 128), Image.Resampling.LANCZOS)
    mask = Image.new("L", (256, 128), 0)
    draw = ImageDraw.Draw(mask)
    draw.polygon([(128, 0), (255, 64), (128, 127), (0, 64)], fill=255)
    rgba = texture.convert("RGBA")
    rgba.putalpha(mask)
    rgba = resize_rgba_premultiplied(rgba, (64, 32))
    if rgba.size != (64, 32):
        rgba = rgba.resize((64, 32), Image.Resampling.LANCZOS)
    arr = np.asarray(rgba, dtype=np.uint8).copy()
    arr[arr[:, :, 3] == 0, :3] = 0
    return Image.fromarray(arr, "RGBA")


def common_collision() -> dict:
    return {
        "collision_policy": "none",
        "collision_profile_id": "none_visual",
        "collision_footprint_tiles": [0, 0],
        "collision_cells": [],
        "navigation_policy": "ignore",
    }


def build_rocks() -> tuple[list[dict], list[dict], list[Image.Image]]:
    assets: list[dict] = []
    provenance: list[dict] = []
    images: list[Image.Image] = []
    for index, (filename, target) in enumerate(zip(ROCK_SOURCES, ROCK_TARGETS), 1):
        external = GENERATED / filename
        if not external.is_file():
            raise FileNotFoundError(external)
        source_path = SOURCE_ROOT / f"chiyue_valley_ground_rock_{index:02d}_source.png"
        shutil.copy2(external, source_path)
        extracted, method = extract_rock_rgba(Image.open(source_path))
        output = pad(resize_rgba_premultiplied(extracted, target), 8)
        output_path = ROCK_ROOT / f"chiyue_valley_ground_rock_{index:02d}.png"
        output.save(output_path, optimize=True)
        x, y, w, h = alpha_bbox(output)
        asset_kind = "block" if index <= 6 else "pile"
        ordinal = index if index <= 6 else index - 6
        asset_id = f"chiyue_valley_ground_rock_{asset_kind}_{ordinal:02d}"
        palette_leaf = "岩石块" if asset_kind == "block" else "岩石堆"
        display_kind = "岩块" if asset_kind == "block" else "岩石堆"
        anchor = [x + w // 2, y + h]
        asset = {
            "asset_id": asset_id,
            "display_name": f"赤月地面{display_kind} {ordinal:02d}",
            "asset_type": "large_prop",
            "category": "object",
            "object_class": "decoration",
            "theme": "chiyue_valley",
            "image": repo_path(output_path),
            "thumbnail": repo_path(output_path),
            "canvas_size": list(output.size),
            "image_size": list(output.size),
            "logical_bounds_px": [0, 0, output.width, output.height],
            "visible_bounds_px": [x, y, w, h],
            "selection_bounds_px": [x, y, w, h],
            "anchor_px": anchor,
            "placement_anchor_px": anchor,
            "anchor_tile": [0, 0],
            "anchor_mode": "foot_tile",
            "footprint_tiles": [1, 1],
            "visual_footprint_tiles": [1, 1],
            "occupancy_footprint_tiles": [1, 1],
            "base_footprint_tiles": [1, 1],
            "tile_size": [64, 32],
            "approved_scale": 1.0,
            "logical_scale_level": 0,
            "default_layer": "object_base",
            "default_object_role": "decoration",
            "occlusion": False,
            "content_layer": "personal_expansion",
            "placeable": True,
            "allow_overlap": True,
            "overlap_policy": "always_allow",
            "calibration_status": "placeable",
            "geometry_pending_manual": True,
            "calibration_source": "pending_manual_geometry_v1",
            "manual_collision_expected": True,
            "collision_authority": "manual_by_user",
            "palette_path": f"洞穴与地下城/地面装饰/赤月峡谷/{palette_leaf}",
            "source_distribution": "openai_builtin_imagegen_user_approved_system",
            "source_path": repo_path(source_path),
            "source_sha256": sha256(source_path),
            "output_sha256": sha256(output_path),
            "thumbnail_source_sha256": sha256(output_path),
            "processing": method + "_premultiplied_downscale_tight_canvas_v1",
            "style_family_id": "chiyue_valley_rock_environment_u0",
            "wall_family_reference": "chiyue_valley_rock_wall_u0",
        }
        asset.update(common_collision())
        assets.append(asset)
        provenance.append(
            {
                "asset_id": asset_id,
                "external_source": str(external),
                "source_path": repo_path(source_path),
                "source_sha256": sha256(source_path),
                "output_path": repo_path(output_path),
                "output_sha256": sha256(output_path),
                "alpha_method": method,
                "visible_bounds_px": [x, y, w, h],
            }
        )
        images.append(output)
    return assets, provenance, images


def build_floors() -> tuple[list[dict], list[dict], list[Image.Image]]:
    assets: list[dict] = []
    provenance: list[dict] = []
    images: list[Image.Image] = []
    for index, filename in enumerate(FLOOR_SOURCES, 1):
        external = GENERATED / filename
        if not external.is_file():
            raise FileNotFoundError(external)
        source_path = SOURCE_ROOT / f"chiyue_valley_floor_{index:02d}_orthographic_source.png"
        shutil.copy2(external, source_path)
        output = make_diamond(Image.open(source_path))
        output_path = FLOOR_ROOT / f"chiyue_valley_floor_{index:02d}.png"
        output.save(output_path, optimize=True)
        asset_id = f"mse.ground.chiyue_valley_floor.{index:02d}"
        asset = {
            "asset_id": asset_id,
            "display_name": f"赤月峡谷地面 {index:02d}",
            "asset_type": "ground_brush",
            "category": "ground",
            "object_class": "ground",
            "theme": "chiyue_valley",
            "image": repo_path(output_path),
            "thumbnail": repo_path(output_path),
            "canvas_size": [64, 32],
            "image_size": [64, 32],
            "logical_bounds_px": [0, 0, 64, 32],
            "visible_bounds_px": [0, 0, 64, 32],
            "selection_bounds_px": [0, 0, 64, 32],
            "anchor_px": [32, 16],
            "placement_anchor_px": [32, 16],
            "anchor_tile": [0, 0],
            "anchor_mode": "tile_center",
            "footprint_tiles": [1, 1],
            "visual_footprint_tiles": [1, 1],
            "occupancy_footprint_tiles": [1, 1],
            "base_footprint_tiles": [1, 1],
            "tile_size": [64, 32],
            "approved_scale": 1.0,
            "logical_scale_level": 0,
            "default_layer": "ground_base",
            "default_object_role": "decoration",
            "occlusion": False,
            "content_layer": "personal_expansion",
            "placeable": True,
            "allow_overlap": True,
            "overlap_policy": "always_allow",
            "calibration_status": "placeable",
            "palette_path": "洞穴与地下城/地面/赤月峡谷地面",
            "source_distribution": "openai_builtin_imagegen_user_approved_system",
            "source_path": repo_path(source_path),
            "source_sha256": sha256(source_path),
            "output_sha256": sha256(output_path),
            "thumbnail_source_sha256": sha256(output_path),
            "processing": "orthographic_texture_to_canonical_64x32_isometric_diamond_v1",
            "ground_brush_role": "base_tile",
            "terrain_type": "chiyue_valley_wet_karst_rock",
            "variation_group_id": "mse.ground.chiyue_valley_floor.v1",
            "paintable": True,
            "normalization": "canonical_64x32_one_cell_diamond_v1",
            "diamond_inner_coverage": 1.0,
            "style_family_id": "chiyue_valley_rock_environment_u0",
            "wall_family_reference": "chiyue_valley_rock_wall_u0",
        }
        asset.update(common_collision())
        assets.append(asset)
        provenance.append(
            {
                "asset_id": asset_id,
                "external_source": str(external),
                "source_path": repo_path(source_path),
                "source_sha256": sha256(source_path),
                "output_path": repo_path(output_path),
                "output_sha256": sha256(output_path),
                "projection": "orthographic_square_to_isometric_64x32_diamond",
            }
        )
        images.append(output)
    return assets, provenance, images


def write_catalog(path: Path, package_id: str, classification: str, assets: list[dict]) -> None:
    payload = {
        "asset_schema_version": 2,
        "package_id": package_id,
        "package_version": 1,
        "asset_count": len(assets),
        "classification": classification,
        "projection": "orthographic_isometric_2_to_1",
        "style_family_id": "chiyue_valley_rock_environment_u0",
        "wall_family_reference": "chiyue_valley_rock_wall_u0",
        "source_distribution": "openai_builtin_imagegen_user_approved_system",
        "assets": assets,
    }
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def checker(size: tuple[int, int], cell: int = 12) -> Image.Image:
    image = Image.new("RGB", size, (238, 238, 238))
    draw = ImageDraw.Draw(image)
    for y in range(0, size[1], cell):
        for x in range(0, size[0], cell):
            if ((x // cell) + (y // cell)) % 2:
                draw.rectangle((x, y, x + cell - 1, y + cell - 1), fill=(200, 200, 200))
    return image


def contact_sheet(images: list[Image.Image], path: Path, backgrounds: list[tuple[int, int, int]]) -> None:
    cell_w, cell_h = 224, 208
    sheet = Image.new("RGB", (cell_w * len(backgrounds), cell_h * len(images)), (20, 22, 20))
    for row, image in enumerate(images):
        for col, color in enumerate(backgrounds):
            base = Image.new("RGB", (cell_w, cell_h), color)
            scale = min((cell_w - 20) / image.width, (cell_h - 20) / image.height, 1.0)
            preview = image.resize((max(1, round(image.width * scale)), max(1, round(image.height * scale))), Image.Resampling.LANCZOS)
            base.paste(preview, ((cell_w - preview.width) // 2, (cell_h - preview.height) // 2), preview)
            sheet.paste(base, (col * cell_w, row * cell_h))
    sheet.save(path, optimize=True)


def floor_contact_sheet(images: list[Image.Image], path: Path) -> None:
    cell_w, cell_h = 192, 96
    sheet = Image.new("RGB", (cell_w * 3, cell_h * 2), (18, 21, 19))
    grid = ImageDraw.Draw(sheet)
    for index, image in enumerate(images):
        col, row = index % 3, index // 3
        preview = image.resize((128, 64), Image.Resampling.NEAREST)
        x, y = col * cell_w + 32, row * cell_h + 16
        sheet.paste(preview, (x, y), preview)
        grid.text((col * cell_w + 8, row * cell_h + 8), f"{index + 1:02d}", fill=(230, 220, 180))
    sheet.save(path, optimize=True)


def main() -> None:
    for directory in (SOURCE_ROOT, ROCK_ROOT, FLOOR_ROOT, DATA_ROOT):
        directory.mkdir(parents=True, exist_ok=True)
    rocks, rock_provenance, rock_images = build_rocks()
    floors, floor_provenance, floor_images = build_floors()
    write_catalog(
        DATA_ROOT / "map_chiyue_valley_ground_asset_catalog.json",
        "mse_chiyue_valley_ground_rocks_12_v1",
        "洞穴与地下城/地面装饰/赤月峡谷",
        rocks,
    )
    write_catalog(
        DATA_ROOT / "map_chiyue_valley_floor_asset_catalog.json",
        "mse_chiyue_valley_floor_6_v1",
        "洞穴与地下城/地面/赤月峡谷地面",
        floors,
    )
    provenance = {
        "schema_version": 1,
        "style_family_id": "chiyue_valley_rock_environment_u0",
        "wall_family_reference": "chiyue_valley_rock_wall_u0",
        "material_contract": "hard_planar_wet_cave_rock",
        "image_generation_mode": "OpenAI built-in image_gen, one call per distinct asset source",
        "rejected_source": "exec-e71afdaf-c419-41ac-a724-b0839b5e2b6b.png (user-rejected diamond-shaped rock)",
        "transparent_edit_attempt": "built-in background-removal edits remained opaque and were rejected",
        "rock_assets": rock_provenance,
        "floor_assets": floor_provenance,
    }
    (SOURCE_ROOT / "chiyue_valley_environment_source_provenance.json").write_text(
        json.dumps(provenance, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    contact_sheet(
        rock_images,
        ART_ROOT / "chiyue_valley_ground_rocks_alpha_qa_contact_sheet.png",
        [(0, 0, 0), (255, 255, 255), (255, 0, 255)],
    )
    floor_contact_sheet(floor_images, ART_ROOT / "chiyue_valley_floor_contact_sheet.png")
    print(f"built rocks={len(rocks)} floors={len(floors)}")


if __name__ == "__main__":
    main()
