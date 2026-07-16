from __future__ import annotations

import argparse
import json
import math
from collections import deque
from pathlib import Path
from typing import Any

from PIL import Image


def _components(mask: list[bytearray], width: int, height: int) -> list[dict[str, Any]]:
    visited = [bytearray(width) for _ in range(height)]
    result: list[dict[str, Any]] = []
    for start_y in range(height):
        for start_x in range(width):
            if not mask[start_y][start_x] or visited[start_y][start_x]:
                continue
            queue = deque([(start_x, start_y)])
            visited[start_y][start_x] = 1
            area = 0
            sum_x = 0
            sum_y = 0
            min_x = max_x = start_x
            min_y = max_y = start_y
            touches_border = False
            while queue:
                x, y = queue.popleft()
                area += 1
                sum_x += x
                sum_y += y
                min_x = min(min_x, x)
                max_x = max(max_x, x)
                min_y = min(min_y, y)
                max_y = max(max_y, y)
                touches_border = touches_border or x == 0 or y == 0 or x == width - 1 or y == height - 1
                for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                    if 0 <= nx < width and 0 <= ny < height and mask[ny][nx] and not visited[ny][nx]:
                        visited[ny][nx] = 1
                        queue.append((nx, ny))
            box_width = max_x - min_x + 1
            box_height = max_y - min_y + 1
            radius = min(box_width, box_height) * 0.5
            circle_area = math.pi * radius * radius if radius > 0 else 1.0
            aspect_score = min(box_width, box_height) / max(box_width, box_height)
            fill_score = min(1.0, area / circle_area)
            result.append(
                {
                    "area": area,
                    "touchesBorder": touches_border,
                    "bbox": [min_x, min_y, box_width, box_height],
                    "center": [sum_x / area, sum_y / area],
                    "radius": radius,
                    "aspectScore": aspect_score,
                    "circleFillScore": fill_score,
                    "circleScore": aspect_score * fill_score,
                }
            )
    return result


def analyze_alpha_holes(path: Path, alpha_threshold: int = 12, max_scan_edge: int = 512) -> dict[str, Any]:
    original = Image.open(path).convert("RGBA")
    scale = min(1.0, max_scan_edge / max(original.size))
    scan = original if scale == 1.0 else original.resize(
        (max(1, round(original.width * scale)), max(1, round(original.height * scale))),
        Image.Resampling.NEAREST,
    )
    alpha = scan.getchannel("A")
    pixels = alpha.load()
    mask = [bytearray(1 if pixels[x, y] <= alpha_threshold else 0 for x in range(scan.width)) for y in range(scan.height)]
    components = _components(mask, scan.width, scan.height)
    enclosed = [component for component in components if not component["touchesBorder"]]
    enclosed.sort(key=lambda component: component["area"], reverse=True)
    inverse_scale = 1.0 / scale
    normalized: list[dict[str, Any]] = []
    for component in enclosed:
        item = dict(component)
        item["bbox"] = [round(value * inverse_scale, 3) for value in component["bbox"]]
        item["center"] = [round(value * inverse_scale, 3) for value in component["center"]]
        item["radius"] = round(component["radius"] * inverse_scale, 3)
        item["area"] = round(component["area"] * inverse_scale * inverse_scale)
        normalized.append(item)
    return {
        "path": path.as_posix(),
        "size": [original.width, original.height],
        "alphaThreshold": alpha_threshold,
        "scanScale": scale,
        "enclosedTransparentRegions": normalized,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Measure enclosed transparent regions in UI frame PNGs.")
    parser.add_argument("images", nargs="+", type=Path)
    parser.add_argument("--out", type=Path)
    args = parser.parse_args()
    payload = {"frames": [analyze_alpha_holes(path) for path in args.images]}
    encoded = json.dumps(payload, ensure_ascii=False, indent=2)
    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(encoded, encoding="utf-8")
        print(f"UI_FRAME_GEOMETRY={args.out}")
    else:
        print(encoded)


if __name__ == "__main__":
    main()
