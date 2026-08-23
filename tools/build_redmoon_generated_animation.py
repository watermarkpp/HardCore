#!/usr/bin/env python3
"""Assemble native-alpha Red Moon Demon masters into runtime atlases."""

from __future__ import annotations

import argparse
import hashlib
import json
from dataclasses import dataclass
from pathlib import Path

import cv2
import numpy as np
from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
CELL = (288, 208)
TARGET_BOX = (23, 8, 245, 165)
DIRECTIONS = 8
OUTPUT_DIR = ROOT / "assets/art/monsters/client_complete/appearance_131_race_34"


@dataclass(frozen=True)
class Sheet:
    filename: str
    columns: int
    rows: int


SHEETS = {
    "idle": Sheet("redmoon_idle_native_alpha_2x2.png", 2, 2),
    "attack": Sheet("redmoon_attack_native_alpha_3x2.png", 3, 2),
    "hit": Sheet("redmoon_hit_native_alpha_2x1.png", 2, 1),
    "death": Sheet("redmoon_death_native_alpha_5x2.png", 5, 2),
}


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest().upper()


def split_sheet(path: Path, columns: int, rows: int) -> list[Image.Image]:
    sheet = Image.open(path).convert("RGBA")
    if sheet.getchannel("A").getextrema()[0] != 0:
        raise RuntimeError(f"{path.name} has no transparent pixels")
    frames: list[Image.Image] = []
    for row in range(rows):
        top = round(row * sheet.height / rows)
        bottom = round((row + 1) * sheet.height / rows)
        for column in range(columns):
            left = round(column * sheet.width / columns)
            right = round((column + 1) * sheet.width / columns)
            frames.append(sheet.crop((left, top, right, bottom)))
    return frames


def retain_main_body(frame: Image.Image) -> Image.Image:
    pixels = np.asarray(frame, dtype=np.uint8).copy()
    alpha = pixels[:, :, 3]
    count, labels, stats, _ = cv2.connectedComponentsWithStats((alpha >= 12).astype(np.uint8), 8)
    if count <= 1:
        raise RuntimeError("empty generated frame")
    largest = 1 + int(np.argmax(stats[1:, cv2.CC_STAT_AREA]))
    body = cv2.dilate((labels == largest).astype(np.uint8), np.ones((3, 3), np.uint8), iterations=1)
    pixels[:, :, 3] = np.where(body != 0, alpha, 0)
    return Image.fromarray(pixels, "RGBA")


def normalize_action(frames: list[Image.Image]) -> list[Image.Image]:
    frames = [retain_main_body(frame) for frame in frames]
    boxes = [frame.getchannel("A").getbbox() for frame in frames]
    if any(box is None for box in boxes):
        raise RuntimeError("empty frame after alpha validation")
    typed_boxes = [box for box in boxes if box is not None]
    left = min(box[0] for box in typed_boxes)
    top = min(box[1] for box in typed_boxes)
    right = max(box[2] for box in typed_boxes)
    bottom = max(box[3] for box in typed_boxes)
    source_width, source_height = right - left, bottom - top
    target_x, target_y, target_width, target_height = TARGET_BOX
    scale = min(target_width / source_width, target_height / source_height)
    width = max(1, round(source_width * scale))
    height = max(1, round(source_height * scale))
    paste_x = target_x + (target_width - width) // 2
    paste_y = target_y + target_height - height
    result: list[Image.Image] = []
    for frame in frames:
        source = frame.crop((left, top, right, bottom)).resize((width, height), Image.Resampling.LANCZOS)
        cell = Image.new("RGBA", CELL, (0, 0, 0, 0))
        cell.alpha_composite(source, (paste_x, paste_y))
        result.append(cell)
    return result


def expand_death(keyframes: list[Image.Image]) -> list[Image.Image]:
    if len(keyframes) != 10:
        raise RuntimeError(f"expected 10 death keyframes, got {len(keyframes)}")
    frames: list[Image.Image] = []
    for index, frame in enumerate(keyframes[:-1]):
        frames.extend((frame, Image.blend(frame, keyframes[index + 1], 0.5)))
    frames.extend((keyframes[-1], keyframes[-1].copy()))
    return frames


def build_atlas(frames: list[Image.Image]) -> Image.Image:
    strip = Image.new("RGBA", (CELL[0] * len(frames), CELL[1]), (0, 0, 0, 0))
    for index, frame in enumerate(frames):
        strip.alpha_composite(frame, (CELL[0] * index, 0))
    atlas = Image.new("RGBA", (strip.width, strip.height * DIRECTIONS), (0, 0, 0, 0))
    for direction in range(DIRECTIONS):
        atlas.alpha_composite(strip, (0, direction * strip.height))
    return atlas.quantize(colors=255, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.NONE)


def verify(path: Path, frame_count: int) -> None:
    atlas = Image.open(path).convert("RGBA")
    expected = (CELL[0] * frame_count, CELL[1] * DIRECTIONS)
    if atlas.size != expected:
        raise RuntimeError(f"{path.name}: expected {expected}, got {atlas.size}")
    first_row = atlas.crop((0, 0, atlas.width, CELL[1])).tobytes()
    for direction in range(1, DIRECTIONS):
        row = atlas.crop((0, direction * CELL[1], atlas.width, (direction + 1) * CELL[1])).tobytes()
        if row != first_row:
            raise RuntimeError(f"{path.name}: direction row {direction} differs")
    for index in range(frame_count):
        frame = atlas.crop((index * CELL[0], 0, (index + 1) * CELL[0], CELL[1]))
        if frame.getchannel("A").getbbox() is None:
            raise RuntimeError(f"{path.name}: frame {index} is empty")


def build(master_dir: Path, output_dir: Path) -> dict[str, dict[str, object]]:
    masters = {
        action: normalize_action(split_sheet(master_dir / spec.filename, spec.columns, spec.rows))
        for action, spec in SHEETS.items()
    }
    actions = {
        "idle": masters["idle"],
        "walk": masters["idle"],
        "attack": masters["attack"],
        "hit": masters["hit"],
        "death": expand_death(masters["death"]),
    }
    expected_counts = {"idle": 4, "walk": 4, "attack": 6, "hit": 2, "death": 20}
    output_dir.mkdir(parents=True, exist_ok=True)
    report: dict[str, dict[str, object]] = {}
    for action, frames in actions.items():
        if len(frames) != expected_counts[action]:
            raise RuntimeError(f"{action}: wrong frame count")
        path = output_dir / f"appearance_131_race_34_{action}.png"
        build_atlas(frames).save(path, format="PNG", optimize=False)
        verify(path, expected_counts[action])
        report[action] = {
            "framesPerDirection": expected_counts[action],
            "dimensions": list(Image.open(path).size),
            "sha256": file_sha256(path),
        }
    if report["idle"]["sha256"] != report["walk"]["sha256"]:
        raise RuntimeError("idle and walk must be byte-identical")
    return report


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--master-dir", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, default=OUTPUT_DIR)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    master_dir = args.master_dir.resolve()
    payload = {
        "monsterId": 180,
        "appearanceProfileId": "appearance.赤月恶魔_13293a7f7aa2e17b",
        "generationAuthority": "explicit_user_replacement_request_2026-08-23",
        "backgroundPolicy": "native_alpha_only",
        "cellSize": list(CELL),
        "footAnchor": [85, 142],
        "directions": DIRECTIONS,
        "actions": build(master_dir, args.output_dir.resolve()),
        "masterSources": {
            spec.filename: file_sha256(master_dir / spec.filename) for spec in SHEETS.values()
        },
    }
    text = json.dumps(payload, ensure_ascii=False, indent=2) + "\n"
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(text, encoding="utf-8")
    print(text, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
