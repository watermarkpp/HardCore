#!/usr/bin/env python3
"""Build the canonical eight-direction Black Iron Helmet source sheet.

The user-approved front/side concept contains nine panels with one duplicate
and incorrect labels.  Only the visual panels are consumed here.  The accepted
rear N/NE/NW sheet supplies the three away-facing directions.
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
SOURCE_ROOT = ROOT / "dev_art_sources/reference/generated/black_iron_helmet"
FRONT_SIDE_SOURCE = SOURCE_ROOT / "front_side_direction_concept.png"
REAR_SOURCE = SOURCE_ROOT / "rear_n_ne_nw_transparent.png"
OUTPUT_ROOT = SOURCE_ROOT / "canonical_directions"
MANIFEST = OUTPUT_ROOT / "manifest.json"
SHEET = OUTPUT_ROOT / "black_iron_helmet_8_directions.png"
DIRECTIONS = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
# Visual panel indexes in the supplied nine-panel concept.  Labels in that
# source are deliberately ignored: panel 4 is the symmetric front view.
FRONT_SIDE_PANEL_INDEX = {"E": 2, "SE": 3, "S": 4, "SW": 6, "W": 7}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def largest_central_component(mask: np.ndarray) -> np.ndarray:
    count, labels, stats, centroids = cv2.connectedComponentsWithStats(mask, 8)
    if count <= 1:
        raise ValueError("No foreground component found")
    height, width = mask.shape
    candidates: list[tuple[float, int]] = []
    for label in range(1, count):
        area = int(stats[label, cv2.CC_STAT_AREA])
        cx, cy = centroids[label]
        centre_distance = abs(cx - width * 0.5) / width + abs(cy - height * 0.52) / height
        candidates.append((area * max(0.1, 1.0 - centre_distance), label))
    selected = max(candidates)[1]
    return np.where(labels == selected, 255, 0).astype(np.uint8)


def extract_concept_panel(source: Image.Image, panel_index: int) -> Image.Image:
    panel_width = source.width / 9.0
    left = int(round(panel_index * panel_width))
    right = int(round((panel_index + 1) * panel_width))
    # The helmet occupies this band; the incorrect text labels sit below it.
    panel = source.crop((left, 390, right, 585)).convert("RGB")
    rgb = np.asarray(panel)
    bgr = cv2.cvtColor(rgb, cv2.COLOR_RGB2BGR)
    mask = np.full(bgr.shape[:2], cv2.GC_BGD, dtype=np.uint8)
    rectangle = (10, 5, bgr.shape[1] - 20, bgr.shape[0] - 15)
    background_model = np.zeros((1, 65), np.float64)
    foreground_model = np.zeros((1, 65), np.float64)
    cv2.grabCut(bgr, mask, rectangle, background_model, foreground_model, 8, cv2.GC_INIT_WITH_RECT)
    foreground = np.where((mask == cv2.GC_FGD) | (mask == cv2.GC_PR_FGD), 255, 0).astype(np.uint8)
    foreground = cv2.morphologyEx(foreground, cv2.MORPH_CLOSE, np.ones((3, 3), np.uint8), iterations=1)
    foreground = largest_central_component(foreground)
    # Fill enclosed face/shell holes while retaining the outer silhouette.
    contours, _ = cv2.findContours(foreground, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    filled = np.zeros_like(foreground)
    cv2.drawContours(filled, contours, -1, 255, thickness=cv2.FILLED)
    # The dark visor in the side/diagonal concepts may be classified as the
    # grey background when it opens into a silhouette concavity.  Close only
    # small internal gaps and paint newly restored visor pixels dark; otherwise
    # the underlying unhelmeted face leaks through in Godot.
    closed = cv2.morphologyEx(filled, cv2.MORPH_CLOSE, np.ones((7, 11), np.uint8), iterations=1)
    restored_visors = (closed > 0) & (filled == 0)
    rgb = rgb.copy()
    rgb[restored_visors] = np.array([8, 9, 11], dtype=np.uint8)
    filled = closed
    rgba = np.dstack((rgb, filled))
    result = Image.fromarray(rgba, "RGBA")
    box = result.getchannel("A").getbbox()
    if not box:
        raise ValueError(f"Concept panel {panel_index} became empty")
    return result.crop(box)


def extract_rear_panels(source: Image.Image) -> dict[str, Image.Image]:
    result: dict[str, Image.Image] = {}
    third = source.width // 3
    for panel_index, direction in enumerate(("N", "NE", "NW")):
        left = panel_index * third
        right = source.width if panel_index == 2 else (panel_index + 1) * third
        panel = source.crop((left, 0, right, source.height)).convert("RGBA")
        box = panel.getchannel("A").getbbox()
        if not box:
            raise ValueError(f"Rear panel {direction} is empty")
        result[direction] = panel.crop(box)
    return result


def main() -> None:
    for required in (FRONT_SIDE_SOURCE, REAR_SOURCE):
        if not required.exists():
            raise FileNotFoundError(required)
    OUTPUT_ROOT.mkdir(parents=True, exist_ok=True)
    front_source = Image.open(FRONT_SIDE_SOURCE).convert("RGB")
    rear = extract_rear_panels(Image.open(REAR_SOURCE))
    variants: dict[str, Image.Image] = dict(rear)
    for direction, panel_index in FRONT_SIDE_PANEL_INDEX.items():
        panel = extract_concept_panel(front_source, panel_index)
        # Runtime body comparison confirms that visual panel 7 must be
        # mirrored for the W row; source labels are not trusted.
        if direction == "W":
            panel = panel.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
        variants[direction] = panel

    records: list[dict] = []
    tile_size = (220, 250)
    sheet = Image.new("RGBA", (tile_size[0] * 8, tile_size[1]), (255, 0, 255, 255))
    draw = ImageDraw.Draw(sheet)
    for index, direction in enumerate(DIRECTIONS):
        image = variants[direction]
        target = OUTPUT_ROOT / f"{index}_{direction.lower()}.png"
        image.save(target)
        scale = min(180 / image.width, 190 / image.height)
        preview = image.resize((max(1, round(image.width * scale)), max(1, round(image.height * scale))), Image.Resampling.NEAREST)
        x = index * tile_size[0] + (tile_size[0] - preview.width) // 2
        y = 20 + (195 - preview.height) // 2
        sheet.alpha_composite(preview, (x, y))
        draw.text((index * tile_size[0] + 8, 222), direction, fill=(0, 0, 0, 255))
        records.append(
            {
                "direction": direction,
                "path": target.relative_to(ROOT).as_posix(),
                "size": list(image.size),
                "sha256": sha256(target),
                "source": "rear-approved" if direction in {"N", "NE", "NW"} else "front-side-approved-concept",
                "sourcePanel": FRONT_SIDE_PANEL_INDEX.get(direction),
                "horizontalFlipApplied": direction == "W",
            }
        )
    sheet.save(SHEET)
    payload = {
        "schemaVersion": 1,
        "item": "黑铁头盔",
        "directionOrder": DIRECTIONS,
        "frontSideSource": FRONT_SIDE_SOURCE.relative_to(ROOT).as_posix(),
        "frontSideSourceSha256": sha256(FRONT_SIDE_SOURCE),
        "rearSource": REAR_SOURCE.relative_to(ROOT).as_posix(),
        "rearSourceSha256": sha256(REAR_SOURCE),
        "policy": "All eight runtime appearance directions come from the newly generated user-approved visual family; source labels are ignored.",
        "records": records,
    }
    MANIFEST.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"BLACK_IRON_CANONICAL_DIRECTIONS_PASS sheet={SHEET.relative_to(ROOT).as_posix()}")


if __name__ == "__main__":
    main()
