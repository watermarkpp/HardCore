#!/usr/bin/env python3
"""Build a mutually edge-compatible 64x32 isometric floor-tile set.

The source images are large chroma-magenta isometric diamonds.  Each source is
unprojected into square ground coordinates, color-normalized, made periodic,
and blended to one shared periodic edge field before being projected back to
the editor's canonical 64x32 diamond.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont


MASTER_SIZE = 512
SUPERSAMPLE_SIZE = (256, 128)
OUTPUT_SIZE = (64, 32)
EDGE_BLEND_FRACTION = 0.22
SOURCE_INSET_FRACTION = 0.045
WALL_TARGET_MEAN = np.asarray([91.7, 95.7, 73.7], dtype=np.float32)
WALL_TARGET_STD = np.asarray([14.0, 15.0, 11.0], dtype=np.float32)
REJECTED_SOURCE_INDICES = {4}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def bilinear_sample(rgb: np.ndarray, x: np.ndarray, y: np.ndarray) -> np.ndarray:
    height, width, _ = rgb.shape
    x = np.clip(x, 0.0, width - 1.001)
    y = np.clip(y, 0.0, height - 1.001)
    x0 = np.floor(x).astype(np.int32)
    y0 = np.floor(y).astype(np.int32)
    x1 = np.minimum(x0 + 1, width - 1)
    y1 = np.minimum(y0 + 1, height - 1)
    fx = (x - x0)[..., None]
    fy = (y - y0)[..., None]
    top = rgb[y0, x0] * (1.0 - fx) + rgb[y0, x1] * fx
    bottom = rgb[y1, x0] * (1.0 - fx) + rgb[y1, x1] * fx
    return top * (1.0 - fy) + bottom * fy


def foreground_mask(rgb: np.ndarray) -> np.ndarray:
    red = rgb[..., 0]
    green = rgb[..., 1]
    blue = rgb[..., 2]
    chroma_magenta = (
        (red > 170.0)
        & (blue > 150.0)
        & (green < 125.0)
        & (((red + blue) * 0.5 - green) > 85.0)
    )
    return ~chroma_magenta


def diamond_corners(mask: np.ndarray) -> dict[str, tuple[float, float]]:
    ys, xs = np.nonzero(mask)
    if xs.size < 1000:
        raise ValueError("source diamond foreground is missing")
    min_x, max_x = int(xs.min()), int(xs.max())
    min_y, max_y = int(ys.min()), int(ys.max())
    vertical_band = max(2, (max_y - min_y) // 200)
    horizontal_band = max(2, (max_x - min_x) // 200)

    def median_point(selector: np.ndarray) -> tuple[float, float]:
        chosen_y, chosen_x = np.nonzero(selector)
        return float(np.median(chosen_x)), float(np.median(chosen_y))

    top = median_point(mask & (np.indices(mask.shape)[0] <= min_y + vertical_band))
    bottom = median_point(mask & (np.indices(mask.shape)[0] >= max_y - vertical_band))
    left = median_point(mask & (np.indices(mask.shape)[1] <= min_x + horizontal_band))
    right = median_point(mask & (np.indices(mask.shape)[1] >= max_x - horizontal_band))
    return {"top": top, "right": right, "bottom": bottom, "left": left}


def unproject_source(path: Path) -> tuple[np.ndarray, dict[str, tuple[float, float]]]:
    source = np.asarray(Image.open(path).convert("RGB"), dtype=np.float32)
    corners = diamond_corners(foreground_mask(source))
    grid = (np.arange(MASTER_SIZE, dtype=np.float32) + 0.5) / MASTER_SIZE
    u, v = np.meshgrid(grid, grid)
    u = SOURCE_INSET_FRACTION + u * (1.0 - SOURCE_INSET_FRACTION * 2.0)
    v = SOURCE_INSET_FRACTION + v * (1.0 - SOURCE_INSET_FRACTION * 2.0)
    top = np.asarray(corners["top"], dtype=np.float32)
    right = np.asarray(corners["right"], dtype=np.float32)
    bottom = np.asarray(corners["bottom"], dtype=np.float32)
    left = np.asarray(corners["left"], dtype=np.float32)
    points = (
        ((1.0 - u) * (1.0 - v))[..., None] * top
        + (u * (1.0 - v))[..., None] * right
        + (u * v)[..., None] * bottom
        + ((1.0 - u) * v)[..., None] * left
    )
    return bilinear_sample(source, points[..., 0], points[..., 1]), corners


def periodic_component(channel: np.ndarray) -> np.ndarray:
    height, width = channel.shape
    boundary = np.zeros_like(channel, dtype=np.float64)
    row_delta = channel[-1, :].astype(np.float64) - channel[0, :].astype(np.float64)
    boundary[0, :] += row_delta
    boundary[-1, :] -= row_delta
    column_delta = channel[:, -1].astype(np.float64) - channel[:, 0].astype(np.float64)
    boundary[:, 0] += column_delta
    boundary[:, -1] -= column_delta
    yy = np.arange(height, dtype=np.float64)[:, None]
    xx = np.arange(width, dtype=np.float64)[None, :]
    denominator = (
        2.0 * np.cos(2.0 * np.pi * xx / width)
        + 2.0 * np.cos(2.0 * np.pi * yy / height)
        - 4.0
    )
    denominator[0, 0] = 1.0
    smooth_frequency = np.fft.fft2(boundary) / denominator
    smooth_frequency[0, 0] = 0.0
    smooth = np.fft.ifft2(smooth_frequency).real
    periodic = channel.astype(np.float64) - smooth
    periodic[:, -1] = periodic[:, 0]
    periodic[-1, :] = periodic[0, :]
    return periodic.astype(np.float32)


def make_periodic(rgb: np.ndarray) -> np.ndarray:
    periodic = np.stack([periodic_component(rgb[..., index]) for index in range(3)], axis=2)
    return np.clip(periodic, 0.0, 255.0)


def normalize_color(rgb: np.ndarray) -> np.ndarray:
    source_mean = rgb.reshape(-1, 3).mean(axis=0)
    source_std = np.maximum(rgb.reshape(-1, 3).std(axis=0), 1.0)
    normalized = (rgb - source_mean) * np.clip(WALL_TARGET_STD / source_std, 0.55, 1.1) + WALL_TARGET_MEAN
    return np.clip(normalized, 0.0, 255.0)


def edge_weight(size: int) -> np.ndarray:
    coordinates = np.linspace(0.0, 1.0, size, dtype=np.float32)
    distance = np.minimum(coordinates, 1.0 - coordinates)
    t = np.clip(distance / EDGE_BLEND_FRACTION, 0.0, 1.0)
    smooth = t * t * (3.0 - 2.0 * t)
    return np.minimum(smooth[:, None], smooth[None, :])[..., None]


def apply_quiet_mortar_edge(rgb: np.ndarray) -> np.ndarray:
    coordinates = np.linspace(0.0, 1.0, rgb.shape[0], dtype=np.float32)
    distance = np.minimum(coordinates, 1.0 - coordinates)
    edge_distance = np.minimum(distance[:, None], distance[None, :])
    t = np.clip(edge_distance / 0.032, 0.0, 1.0)
    smooth = t * t * (3.0 - 2.0 * t)
    factor = 0.70 + 0.30 * smooth
    return rgb * factor[..., None]


def project_diamond(square: np.ndarray) -> Image.Image:
    width, height = SUPERSAMPLE_SIZE
    y, x = np.indices((height, width), dtype=np.float32)
    normalized_x = (x + 0.5 - width * 0.5) / (width * 0.5)
    normalized_y = (y + 0.5) / (height * 0.5)
    u = (normalized_x + normalized_y) * 0.5
    v = (normalized_y - normalized_x) * 0.5
    inside = (u >= 0.0) & (u < 1.0) & (v >= 0.0) & (v < 1.0)
    sampled = bilinear_sample(square, (u % 1.0) * MASTER_SIZE, (v % 1.0) * MASTER_SIZE)
    rgba = np.zeros((height, width, 4), dtype=np.uint8)
    rgba[..., :3] = np.clip(sampled, 0.0, 255.0).astype(np.uint8)
    rgba[..., 3] = np.where(inside, 255, 0).astype(np.uint8)
    high_resolution = Image.fromarray(rgba, "RGBA")
    return high_resolution.resize(OUTPUT_SIZE, Image.Resampling.LANCZOS)


def composite_over(image: Image.Image, background: tuple[int, int, int]) -> Image.Image:
    canvas = Image.new("RGBA", image.size, (*background, 255))
    canvas.alpha_composite(image)
    return canvas.convert("RGB")


def make_contact_sheet(tiles: list[tuple[int, Image.Image]], output_path: Path) -> None:
    scale = 6
    cell_width, cell_height = 64 * scale + 32, 32 * scale + 54
    sheet = Image.new("RGB", (cell_width * 3, cell_height * 2), (18, 21, 20))
    draw = ImageDraw.Draw(sheet)
    font = ImageFont.load_default()
    for slot, (source_index, tile) in enumerate(tiles):
        enlarged = tile.resize((64 * scale, 32 * scale), Image.Resampling.NEAREST)
        x = (slot % 3) * cell_width + 16
        y = (slot // 3) * cell_height + 14
        checker = Image.new("RGB", enlarged.size, (33, 37, 34))
        checker.paste((44, 48, 43), (0, enlarged.height // 2, enlarged.width, enlarged.height))
        sheet.paste(checker, (x, y))
        sheet.paste(enlarged, (x, y), enlarged)
        draw.text((x, y + enlarged.height + 12), f"GOTHIC OLIVE FLOOR {source_index:02d}", fill=(205, 208, 190), font=font)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(output_path)


def make_mixed_preview(tiles: list[tuple[int, Image.Image]], output_path: Path) -> None:
    count = 10
    scale = 4
    base_width = (count + count) * 32 + 64
    base_height = (count + count) * 16 + 32
    canvas = Image.new("RGBA", (base_width, base_height), (18, 21, 20, 255))
    rng = np.random.default_rng(176)
    for diagonal in range(count * 2 - 1):
        for tile_y in range(count):
            tile_x = diagonal - tile_y
            if tile_x < 0 or tile_x >= count:
                continue
            left = count * 32 + (tile_x - tile_y) * 32
            top = 8 + (tile_x + tile_y) * 16
            tile = tiles[int(rng.integers(0, len(tiles)))][1]
            canvas.alpha_composite(tile, (left, top))
    output_path.parent.mkdir(parents=True, exist_ok=True)
    canvas.resize((base_width * scale, base_height * scale), Image.Resampling.NEAREST).convert("RGB").save(output_path)


def edge_compatibility_metric(squares: list[np.ndarray]) -> dict[str, float]:
    maximum = 0.0
    mean = 0.0
    comparisons = 0
    for first in squares:
        for second in squares:
            for edge_a, edge_b in ((first[:, -1], second[:, 0]), (first[-1, :], second[0, :])):
                delta = np.abs(edge_a - edge_b)
                maximum = max(maximum, float(delta.max()))
                mean += float(delta.mean())
                comparisons += 1
    return {"maximum_channel_delta": round(maximum, 4), "mean_channel_delta": round(mean / comparisons, 4)}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--preview-dir", type=Path, required=True)
    parser.add_argument("sources", nargs=6, type=Path)
    args = parser.parse_args()

    unprojected: list[tuple[int, np.ndarray]] = []
    source_records: list[dict[str, object]] = []
    for source_index, source in enumerate(args.sources, start=1):
        if source_index in REJECTED_SOURCE_INDICES:
            continue
        square, corners = unproject_source(source)
        unprojected.append((source_index, square))
        source_records.append({"source_index": source_index, "path": str(source), "sha256": sha256(source), "corners": corners})

    periodic = [(index, make_periodic(normalize_color(square))) for index, square in unprojected]
    shared_edge = np.mean(np.stack([square for _, square in periodic], axis=0), axis=0)
    shared_edge = make_periodic(shared_edge)
    weight = edge_weight(MASTER_SIZE)
    compatible = [
        (index, apply_quiet_mortar_edge(shared_edge * (1.0 - weight) + square * weight))
        for index, square in periodic
    ]

    args.output_dir.mkdir(parents=True, exist_ok=True)
    tiles: list[tuple[int, Image.Image]] = []
    output_records: list[dict[str, object]] = []
    for index, square in compatible:
        tile = project_diamond(square)
        output_path = args.output_dir / f"gothic_olive_floor_{index:02d}.png"
        tile.save(output_path)
        tiles.append((index, tile))
        output_records.append({"path": str(output_path), "sha256": sha256(output_path), "size": list(tile.size)})

    contact_path = args.preview_dir / "gothic_olive_floor_tiles_contact.png"
    mixed_path = args.preview_dir / "gothic_olive_floor_tiles_mixed_10x10.png"
    make_contact_sheet(tiles, contact_path)
    make_mixed_preview(tiles, mixed_path)
    report = {
        "pipeline": "chroma_diamond_unproject_periodic_shared_edge_project_v1",
        "rejected_source_indices": sorted(REJECTED_SOURCE_INDICES),
        "output_size": list(OUTPUT_SIZE),
        "mutual_edge_compatibility": edge_compatibility_metric([square for _, square in compatible]),
        "sources": source_records,
        "outputs": output_records,
        "previews": [str(contact_path), str(mixed_path)],
    }
    report_path = args.preview_dir / "gothic_olive_floor_tiles_build_report.json"
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
