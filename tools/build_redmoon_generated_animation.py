#!/usr/bin/env python3
"""Assemble native-alpha Red Moon Demon masters into runtime atlases.

The generated sheets are built from transparent ImageGen masters.  A master
sheet is not a layout contract: each cell can contain the same monster at a
different canvas position.  We therefore align a lower support-band anchor
from the retained main connected component before the common resize.  The
anchor is deliberately based on the base of the silhouette rather than the
whole-frame bounding-box centre, so attack mouth/tentacle changes do not move
the body.
"""

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
ALPHA_THRESHOLD = 12
SUPPORT_BAND_FRACTION = 0.12
MAX_ANCHOR_DEVIATION_PX = 1.5


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
    count, labels, stats, _ = cv2.connectedComponentsWithStats(
        (alpha >= ALPHA_THRESHOLD).astype(np.uint8), 8
    )
    if count <= 1:
        raise RuntimeError("empty generated frame")
    largest = 1 + int(np.argmax(stats[1:, cv2.CC_STAT_AREA]))
    body = cv2.dilate((labels == largest).astype(np.uint8), np.ones((3, 3), np.uint8), iterations=1)
    pixels[:, :, 3] = np.where(body != 0, alpha, 0)
    return Image.fromarray(pixels, "RGBA")


def support_anchor(frame: Image.Image) -> tuple[float, float]:
    """Return a robust lower-body (x, y) anchor in source pixels.

    The largest alpha-connected component is scanned across its lowest 12%
    of occupied rows.  Each row contributes its silhouette median x, then the
    medians are reduced again.  This rejects isolated alpha noise and keeps
    upper-body attack geometry from affecting the base anchor.
    """

    alpha = np.asarray(frame, dtype=np.uint8)[:, :, 3]
    count, labels, stats, _ = cv2.connectedComponentsWithStats(
        (alpha >= ALPHA_THRESHOLD).astype(np.uint8), 8
    )
    if count <= 1:
        raise RuntimeError("empty generated frame while finding support anchor")
    largest = 1 + int(np.argmax(stats[1:, cv2.CC_STAT_AREA]))
    body = labels == largest
    ys, _ = np.where(body)
    if ys.size == 0:
        raise RuntimeError("empty generated frame while finding support anchor")
    top = int(ys.min())
    bottom = int(ys.max())
    band_height = max(2, round((bottom - top + 1) * SUPPORT_BAND_FRACTION))
    band_start = max(top, bottom - band_height)
    row_centers: list[float] = []
    row_numbers: list[float] = []
    for y in range(band_start, bottom + 1):
        row_x = np.flatnonzero(body[y])
        if row_x.size:
            row_centers.append(float(np.median(row_x)))
            row_numbers.append(float(y))
    if not row_centers:
        raise RuntimeError("empty support band")
    return float(np.median(row_centers)), float(np.median(row_numbers))


def normalize_action(frames: list[Image.Image]) -> list[Image.Image]:
    frames = [retain_main_body(frame) for frame in frames]
    boxes = [frame.getchannel("A").getbbox() for frame in frames]
    if any(box is None for box in boxes):
        raise RuntimeError("empty frame after alpha validation")
    typed_boxes = [box for box in boxes if box is not None]
    anchors = [support_anchor(frame) for frame in frames]
    reference_anchor = (
        float(np.median([anchor[0] for anchor in anchors])),
        float(np.median([anchor[1] for anchor in anchors])),
    )
    shifts = [
        (
            round(reference_anchor[0] - anchor[0]),
            round(reference_anchor[1] - anchor[1]),
        )
        for anchor in anchors
    ]
    aligned_boxes = [
        (
            box[0] + shift[0],
            box[1] + shift[1],
            box[2] + shift[0],
            box[3] + shift[1],
        )
        for box, shift in zip(typed_boxes, shifts)
    ]
    left = min(box[0] for box in aligned_boxes)
    top = min(box[1] for box in aligned_boxes)
    right = max(box[2] for box in aligned_boxes)
    bottom = max(box[3] for box in aligned_boxes)
    source_width, source_height = right - left, bottom - top
    target_x, target_y, target_width, target_height = TARGET_BOX
    scale = min(target_width / source_width, target_height / source_height)
    width = max(1, round(source_width * scale))
    height = max(1, round(source_height * scale))
    paste_x = target_x + (target_width - width) // 2
    paste_y = target_y + target_height - height
    result: list[Image.Image] = []
    for frame, box, shift in zip(frames, typed_boxes, shifts):
        source = frame.crop(box)
        aligned = Image.new("RGBA", (source_width, source_height), (0, 0, 0, 0))
        aligned.alpha_composite(
            source,
            (
                box[0] + shift[0] - left,
                box[1] + shift[1] - top,
            ),
        )
        source = aligned.resize((width, height), Image.Resampling.LANCZOS)
        # Lanczos creates a narrow antialias fringe around the retained body.
        # Re-run the same component policy at runtime resolution so that tiny
        # resampling islands and source-background specks cannot enter the
        # final atlas.
        source = retain_main_body(source)
        cell = Image.new("RGBA", CELL, (0, 0, 0, 0))
        cell.alpha_composite(source, (paste_x, paste_y))
        result.append(cell)
    return result


def align_frames_to_shared_anchor(frames: list[Image.Image]) -> list[Image.Image]:
    """Re-align already normalized frames without changing their scale.

    Death midpoint blends can change which lower silhouette pixels survive the
    alpha threshold even when both source keyframes were aligned.  Replaying
    the support-anchor correction after interpolation keeps the collapse on a
    fixed base while preserving each frame's area and proportions.
    """

    anchors = [support_anchor(frame) for frame in frames]
    reference = (
        float(np.median([anchor[0] for anchor in anchors])),
        float(np.median([anchor[1] for anchor in anchors])),
    )
    shifts = [
        (
            round(reference[0] - anchor[0]),
            round(reference[1] - anchor[1]),
        )
        for anchor in anchors
    ]
    boxes = [frame.getchannel("A").getbbox() for frame in frames]
    if any(box is None for box in boxes):
        raise RuntimeError("empty normalized frame while aligning support anchor")
    typed_boxes = [box for box in boxes if box is not None]
    shifted_boxes = [
        (
            box[0] + shift[0],
            box[1] + shift[1],
            box[2] + shift[0],
            box[3] + shift[1],
        )
        for box, shift in zip(typed_boxes, shifts)
    ]

    def bounded_global_offset(axis: int, extent: int) -> int:
        low = -min(box[axis] for box in shifted_boxes)
        high = extent - max(box[axis + 2] for box in shifted_boxes)
        if low > high:
            raise RuntimeError("support-anchor correction would crop a frame")
        return low if low > 0 else high if high < 0 else 0

    global_x = bounded_global_offset(0, CELL[0])
    global_y = bounded_global_offset(1, CELL[1])
    result: list[Image.Image] = []
    for frame, shift in zip(frames, shifts):
        offset_x = shift[0] + global_x
        offset_y = shift[1] + global_y
        source_box = (
            max(0, -offset_x),
            max(0, -offset_y),
            min(CELL[0], CELL[0] - offset_x),
            min(CELL[1], CELL[1] - offset_y),
        )
        if source_box[0] >= source_box[2] or source_box[1] >= source_box[3]:
            raise RuntimeError("support-anchor correction removed a frame")
        shifted = Image.new("RGBA", CELL, (0, 0, 0, 0))
        shifted.alpha_composite(
            frame.crop(source_box),
            (max(0, offset_x), max(0, offset_y)),
        )
        result.append(shifted)
    return result


def expand_death(keyframes: list[Image.Image]) -> list[Image.Image]:
    if len(keyframes) != 10:
        raise RuntimeError(f"expected 10 death keyframes, got {len(keyframes)}")
    frames: list[Image.Image] = []
    for index, frame in enumerate(keyframes[:-1]):
        frames.extend((frame, Image.blend(frame, keyframes[index + 1], 0.5)))
    frames.extend((keyframes[-1], keyframes[-1].copy()))
    return align_frames_to_shared_anchor(frames)


def build_atlas(frames: list[Image.Image]) -> Image.Image:
    def quantize(current: list[Image.Image]) -> Image.Image:
        strip = Image.new(
            "RGBA", (CELL[0] * len(current), CELL[1]), (0, 0, 0, 0)
        )
        for index, frame in enumerate(current):
            strip.alpha_composite(frame, (CELL[0] * index, 0))
        atlas = Image.new(
            "RGBA", (strip.width, strip.height * DIRECTIONS), (0, 0, 0, 0)
        )
        for direction in range(DIRECTIONS):
            atlas.alpha_composite(strip, (0, direction * strip.height))
        return atlas.quantize(
            colors=255,
            method=Image.Quantize.FASTOCTREE,
            dither=Image.Dither.NONE,
        )

    # Palette quantization can discard a low-alpha support pixel in only one
    # frame.  Re-read the quantized first row and apply the same integer anchor
    # correction twice before the final palette write; this keeps the runtime
    # pixels, rather than only the pre-quantized RGBA intermediates, stable.
    aligned = list(frames)
    for _ in range(2):
        quantized = quantize(aligned).convert("RGBA")
        first_row = [
            quantized.crop((index * CELL[0], 0, (index + 1) * CELL[0], CELL[1]))
            for index in range(len(aligned))
        ]
        aligned = align_frames_to_shared_anchor(first_row)
    return quantize(aligned)


def verify(path: Path, frame_count: int) -> dict[str, object]:
    atlas = Image.open(path).convert("RGBA")
    expected = (CELL[0] * frame_count, CELL[1] * DIRECTIONS)
    if atlas.size != expected:
        raise RuntimeError(f"{path.name}: expected {expected}, got {atlas.size}")
    first_row = atlas.crop((0, 0, atlas.width, CELL[1])).tobytes()
    for direction in range(1, DIRECTIONS):
        row = atlas.crop((0, direction * CELL[1], atlas.width, (direction + 1) * CELL[1])).tobytes()
        if row != first_row:
            raise RuntimeError(f"{path.name}: direction row {direction} differs")
    frames: list[Image.Image] = []
    for index in range(frame_count):
        frame = atlas.crop((index * CELL[0], 0, (index + 1) * CELL[0], CELL[1]))
        bbox = frame.getchannel("A").getbbox()
        if bbox is None:
            raise RuntimeError(f"{path.name}: frame {index} is empty")
        if bbox[0] < 0 or bbox[1] < 0 or bbox[2] > CELL[0] or bbox[3] > CELL[1]:
            raise RuntimeError(f"{path.name}: frame {index} was cropped")
        alpha = np.asarray(frame, dtype=np.uint8)[:, :, 3]
        solid = (alpha >= ALPHA_THRESHOLD).astype(np.uint8)
        component_count, labels, stats, _ = cv2.connectedComponentsWithStats(solid, 8)
        if component_count <= 1:
            raise RuntimeError(f"{path.name}: frame {index} has no solid body")
        largest = 1 + int(np.argmax(stats[1:, cv2.CC_STAT_AREA]))
        body = labels == largest
        # Allow the two-pixel Lanczos edge fringe, but reject any detached
        # alpha-bearing background outside the main body.
        halo = cv2.dilate(body.astype(np.uint8), np.ones((5, 5), np.uint8), iterations=1)
        stray = (alpha > 0) & (halo == 0)
        if np.any(stray):
            raise RuntimeError(
                f"{path.name}: frame {index} contains background alpha outside body"
            )
        if any(alpha[y, x] != 0 for x, y in [(0, 0), (CELL[0] - 1, 0), (0, CELL[1] - 1), (CELL[0] - 1, CELL[1] - 1)]):
            raise RuntimeError(f"{path.name}: frame {index} corner alpha is nonzero")
        frames.append(frame)
    anchors = [support_anchor(frame) for frame in frames]
    reference = (
        float(np.median([anchor[0] for anchor in anchors])),
        float(np.median([anchor[1] for anchor in anchors])),
    )
    deviations = [
        [round(anchor[0] - reference[0], 3), round(anchor[1] - reference[1], 3)]
        for anchor in anchors
    ]
    max_abs = [
        round(max(abs(value[axis]) for value in deviations), 3)
        for axis in range(2)
    ]
    max_euclidean = round(
        max((dx * dx + dy * dy) ** 0.5 for dx, dy in deviations), 3
    )
    if max(max_abs) > MAX_ANCHOR_DEVIATION_PX:
        raise RuntimeError(
            f"{path.name}: support anchor drift {max_abs} exceeds "
            f"{MAX_ANCHOR_DEVIATION_PX}px"
        )
    return {
        "reference": [round(reference[0], 3), round(reference[1], 3)],
        "perFrame": deviations,
        "maxAbsDeviationPx": max_abs,
        "maxEuclideanDeviationPx": max_euclidean,
        "maxBackgroundAlphaOutsideBody": 0,
        "cornerAlpha": [0, 0, 0, 0],
    }

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
        verification = verify(path, expected_counts[action])
        report[action] = {
            "framesPerDirection": expected_counts[action],
            "dimensions": list(Image.open(path).size),
            "sha256": file_sha256(path),
            "supportAnchor": verification,
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
