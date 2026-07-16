#!/usr/bin/env python3
"""Measure real client Helmet.wil scale and death-pose parameters."""

from __future__ import annotations

import hashlib
import json
import math
import statistics
import sys
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
LIBRARY = ROOT / "dev_art_sources/external/mir2opensource_full/Data/Helmet.wil"
OUTPUT = ROOT / "outputs/resource_catalog/black_iron_helmet/client_helmet_parameter_baseline.json"
STRIDE = 600
APPEARANCES = 6
CELL = (192, 160)
DRAW_ORIGIN = (64, 80)
DIRECTIONS = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
ACTIONS = {
    "idle": {"start": 0, "frames": 4},
    "walk": {"start": 64, "frames": 6},
    "attack": {"start": 200, "frames": 6},
    "hit": {"start": 472, "frames": 3},
    "death": {"start": 536, "frames": 4},
}

sys.path.insert(0, str(ROOT / "tools/vendor"))
from extract_wil import decode_sprite, read_library  # noqa: E402


def percentile(values: list[int], fraction: float) -> float:
    ordered = sorted(values)
    position = (len(ordered) - 1) * fraction
    low = math.floor(position)
    high = math.ceil(position)
    if low == high:
        return float(ordered[low])
    return ordered[low] * (high - position) + ordered[high] * (position - low)


def frame_box(data: bytes, palette: list, offsets: list[int], index: int) -> tuple[int, int, int, int] | None:
    image, meta = decode_sprite(data, offsets[index], palette)
    cell = Image.new("RGBA", CELL, (0, 0, 0, 0))
    cell.alpha_composite(
        image.convert("RGBA"),
        (DRAW_ORIGIN[0] + int(meta["x"]), DRAW_ORIGIN[1] + int(meta["y"])),
    )
    return cell.getchannel("A").getbbox()


def size(box: tuple[int, int, int, int]) -> tuple[int, int]:
    return box[2] - box[0], box[3] - box[1]


def stats(values: list[tuple[int, int]]) -> dict:
    widths = [value[0] for value in values]
    heights = [value[1] for value in values]
    return {
        "count": len(values),
        "median": [statistics.median(widths), statistics.median(heights)],
        "p75": [percentile(widths, 0.75), percentile(heights, 0.75)],
        "min": [min(widths), min(heights)],
        "max": [max(widths), max(heights)],
    }


def main() -> None:
    data, palette, offsets, info = read_library(LIBRARY)
    if int(info["image_count"]) != STRIDE * APPEARANCES:
        raise AssertionError("Helmet.wil no longer matches six 600-frame appearances")
    action_values: dict[str, list[tuple[int, int]]] = {name: [] for name in ACTIONS}
    idle_by_direction: dict[str, list[tuple[int, int]]] = {direction: [] for direction in DIRECTIONS}
    death_final: list[tuple[int, int]] = []
    for appearance in range(APPEARANCES):
        for action_name, action in ACTIONS.items():
            for direction_index, direction in enumerate(DIRECTIONS):
                for frame in range(int(action["frames"])):
                    index = appearance * STRIDE + int(action["start"]) + direction_index * 8 + frame
                    box = frame_box(data, palette, offsets, index)
                    if box is None:
                        continue
                    frame_size = size(box)
                    action_values[action_name].append(frame_size)
                    if action_name == "idle":
                        idle_by_direction[direction].append(frame_size)
                    if action_name == "death" and frame == int(action["frames"]) - 1:
                        death_final.append(frame_size)
    direction_stats = {direction: stats(values) for direction, values in idle_by_direction.items()}
    runtime_envelopes = {
        direction: [max(1, round(value["p75"][0])), max(1, round(value["p75"][1]))]
        for direction, value in direction_stats.items()
    }
    payload = {
        "schemaVersion": 1,
        "source": LIBRARY.relative_to(ROOT).as_posix(),
        "sourceSha256": hashlib.sha256(LIBRARY.read_bytes()).hexdigest(),
        "imageCount": int(info["image_count"]),
        "appearanceStride": STRIDE,
        "appearanceCount": APPEARANCES,
        "sampleRule": "all six real Helmet.wil appearances; MIR2 action offsets and eight direction rows",
        "actions": {name: stats(values) for name, values in action_values.items()},
        "idleDirections": direction_stats,
        "directionRuntimeMaxSize": runtime_envelopes,
        "deathFinal": {
            **stats(death_final),
            "horizontalCount": sum(1 for width, height in death_final if width > height),
            "verticalOrSquareCount": sum(1 for width, height in death_final if width <= height),
            "canonicalSpriteRotate90Degrees": False,
            "reason": "Real client helmets use authored death frames; no uniform whole-sprite 90-degree rotation exists.",
        },
    }
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(
        "CLIENT_HELMET_PARAMETER_BASELINE_PASS "
        f"appearances={APPEARANCES} idle_samples={sum(len(v) for v in idle_by_direction.values())} "
        f"death_final_samples={len(death_final)}"
    )


if __name__ == "__main__":
    main()
