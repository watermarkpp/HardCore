# -*- coding: utf-8 -*-
"""Measure slot wells (dark enclosed interiors) in candidate chassis art.

Outputs a JSON with per-image: size, alpha stats, background alpha, and the
enclosed dark components classified as orbs / item slots / xp bar.
Run: python tools/measure_chassis_candidates_20260914.py
"""
from __future__ import annotations

import json
import sys
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
INPUT_DIR = ROOT / "outputs" / "chassis_design_20260914"
FILES = {
    "dragon": INPUT_DIR / "candidate_1_dragon.png",
    "lion": INPUT_DIR / "candidate_2_lion.png",
    "winged_lion": INPUT_DIR / "candidate_3_winged_lion.png",
    "demon": INPUT_DIR / "candidate_4_demon.webp",
}
DARK_THRESHOLD = 26  # luminance below this counts as "well interior"


def luminance(arr: np.ndarray) -> np.ndarray:
    rgb = arr[:, :, :3].astype(np.float32)
    return 0.2126 * rgb[:, :, 0] + 0.7152 * rgb[:, :, 1] + 0.0722 * rgb[:, :, 2]


def label_components(mask: np.ndarray) -> list[dict]:
    visited = np.zeros_like(mask, dtype=bool)
    height, width = mask.shape
    components: list[dict] = []
    for sy, sx in zip(*np.nonzero(mask)):
        if visited[sy, sx]:
            continue
        queue = deque([(sy, sx)])
        visited[sy, sx] = True
        pixels = []
        while queue:
            y, x = queue.popleft()
            pixels.append((y, x))
            for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
                if 0 <= ny < height and 0 <= nx < width and mask[ny, nx] and not visited[ny, nx]:
                    visited[ny, nx] = True
                    queue.append((ny, nx))
        ys = np.array([p[0] for p in pixels], dtype=np.float64)
        xs = np.array([p[1] for p in pixels], dtype=np.float64)
        min_x, max_x = int(xs.min()), int(xs.max())
        min_y, max_y = int(ys.min()), int(ys.max())
        box_w, box_h = max_x - min_x + 1, max_y - min_y + 1
        area = len(pixels)
        touches_border = min_x == 0 or min_y == 0 or max_x == width - 1 or max_y == height - 1
        fill = area / float(box_w * box_h)
        aspect = min(box_w, box_h) / float(max(box_w, box_h))
        components.append(
            {
                "area": area,
                "touches_border": touches_border,
                "bbox": [min_x, min_y, box_w, box_h],
                "center": [float(xs.mean()), float(ys.mean())],
                "fill_ratio": round(fill, 4),
                "aspect_ratio": round(aspect, 4),
            }
        )
    return components


def background_connected_dark(arr: np.ndarray) -> bool:
    """True if the border-connected dark region covers >8% of image."""
    lum = luminance(arr)
    dark = lum < DARK_THRESHOLD
    height, width = dark.shape
    visited = np.zeros_like(dark, dtype=bool)
    queue = deque()
    for x in range(width):
        for y in (0, height - 1):
            if dark[y, x] and not visited[y, x]:
                visited[y, x] = True
                queue.append((y, x))
    for y in range(height):
        for x in (0, width - 1):
            if dark[y, x] and not visited[y, x]:
                visited[y, x] = True
                queue.append((y, x))
    count = 0
    while queue:
        y, x = queue.popleft()
        count += 1
        for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
            if 0 <= ny < height and 0 <= nx < width and dark[ny, nx] and not visited[ny, nx]:
                visited[ny, nx] = True
                queue.append((ny, nx))
    return count / float(width * height) > 0.08, count / float(width * height)


def analyze(name: str, path: Path) -> dict:
    img = Image.open(path).convert("RGBA")
    arr = np.array(img)
    alpha = arr[:, :, 3]
    lum = luminance(arr)
    dark = lum < DARK_THRESHOLD
    components = label_components(dark)
    enclosed = [c for c in components if not c["touches_border"]]
    enclosed.sort(key=lambda c: c["area"], reverse=True)
    bg_dark, bg_ratio = background_connected_dark(arr)
    report = {
        "name": name,
        "file": path.name,
        "size": [img.width, img.height],
        "alpha_min": int(alpha.min()),
        "alpha_max": int(alpha.max()),
        "alpha_transparent_pixels": int((alpha < 8).sum()),
        "corner_rgba": [
            arr[0, 0].tolist(),
            arr[0, -1].tolist(),
            arr[-1, 0].tolist(),
            arr[-1, -1].tolist(),
        ],
        "border_dark_background_ratio": round(bg_ratio, 4),
        "enclosed_dark_components_top": enclosed[:12],
    }
    return report


def main() -> int:
    reports = []
    for name, path in FILES.items():
        if name == "demon" and path.suffix == ".webp":
            png_path = path.with_suffix(".png")
            Image.open(path).convert("RGBA").save(png_path)
            path = png_path
        reports.append(analyze(name, path))
    out = INPUT_DIR / "candidate_geometry_probe.json"
    out.write_text(json.dumps(reports, indent=2, ensure_ascii=False), encoding="utf-8")
    for report in reports:
        print(
            f"{report['name']}: {report['size'][0]}x{report['size'][1]} "
            f"alpha[{report['alpha_min']}..{report['alpha_max']}] "
            f"transparent_px={report['alpha_transparent_pixels']} "
            f"border_dark_ratio={report['border_dark_background_ratio']}"
        )
        for comp in report["enclosed_dark_components_top"]:
            bbox = comp["bbox"]
            print(
                f"  comp area={comp['area']} bbox={bbox} center={tuple(round(v, 1) for v in comp['center'])} "
                f"fill={comp['fill_ratio']} aspect={comp['aspect_ratio']}"
            )
    print(f"saved: {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
