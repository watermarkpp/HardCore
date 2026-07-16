from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Any

import cv2
import numpy as np


def analyze_frame(path: Path, alpha_threshold: int = 12) -> dict[str, Any]:
    encoded = np.fromfile(path, dtype=np.uint8)
    image = cv2.imdecode(encoded, cv2.IMREAD_UNCHANGED)
    if image is None or image.ndim != 3 or image.shape[2] != 4:
        raise RuntimeError(f"frame is not a readable RGBA image: {path}")
    alpha = image[:, :, 3]
    transparent = np.where(alpha <= alpha_threshold, 1, 0).astype(np.uint8)
    count, labels, stats, centroids = cv2.connectedComponentsWithStats(transparent, connectivity=4)
    height, width = transparent.shape
    regions: list[dict[str, Any]] = []
    for label in range(1, count):
        x, y, box_width, box_height, area = [int(value) for value in stats[label]]
        touches_border = x == 0 or y == 0 or x + box_width >= width or y + box_height >= height
        if touches_border:
            continue
        component = np.where(labels == label, 255, 0).astype(np.uint8)
        distance = cv2.distanceTransform(component, cv2.DIST_L2, cv2.DIST_MASK_PRECISE)
        _, radius, _, center = cv2.minMaxLoc(distance)
        contours, _ = cv2.findContours(component, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
        perimeter = sum(cv2.arcLength(contour, True) for contour in contours)
        circularity = (4.0 * math.pi * area / (perimeter * perimeter)) if perimeter > 0 else 0.0
        aspect_score = min(box_width, box_height) / max(box_width, box_height)
        regions.append(
            {
                "area": area,
                "bbox": [x, y, box_width, box_height],
                "centroid": [round(float(centroids[label][0]), 4), round(float(centroids[label][1]), 4)],
                "inscribedCircle": {
                    "center": [int(center[0]), int(center[1])],
                    "radius": round(float(radius), 4),
                },
                "aspectScore": round(aspect_score, 6),
                "contourCircularity": round(circularity, 6),
                "selectionScore": round(circularity * aspect_score * math.sqrt(area), 6),
            }
        )
    regions.sort(key=lambda item: item["area"], reverse=True)
    return {
        "path": path.as_posix(),
        "size": [width, height],
        "alphaThreshold": alpha_threshold,
        "engine": "OpenCV connectedComponentsWithStats + DIST_L2 precise distanceTransform",
        "enclosedTransparentRegions": regions,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="OpenCV alpha-hole geometry analysis for game UI frames.")
    parser.add_argument("images", nargs="+", type=Path)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--alpha-threshold", type=int, default=12)
    args = parser.parse_args()
    payload = {"frames": [analyze_frame(path, args.alpha_threshold) for path in args.images]}
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"UI_FRAME_GEOMETRY_OPENCV={args.out}")


if __name__ == "__main__":
    main()
