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
HAIR_LIBRARY = ROOT / "dev_art_sources/external/mir2opensource_full/Data/Hair.wil"
OUTPUT = ROOT / "outputs/resource_catalog/black_iron_helmet/client_helmet_parameter_baseline.json"
STRIDE = 600
APPEARANCES = 6
HAIR_STRIDE = 2224
HAIR_APPEARANCE = 2
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


def frame_metrics(
    data: bytes,
    palette: list,
    offsets: list[int],
    index: int,
) -> tuple[tuple[int, int, int, int], int, tuple[float, float]] | None:
    image, meta = decode_sprite(data, offsets[index], palette)
    cell = Image.new("RGBA", CELL, (0, 0, 0, 0))
    cell.alpha_composite(
        image.convert("RGBA"),
        (DRAW_ORIGIN[0] + int(meta["x"]), DRAW_ORIGIN[1] + int(meta["y"])),
    )
    alpha = cell.getchannel("A")
    box = alpha.getbbox()
    if box is None:
        return None
    opaque_pixels = sum(alpha.histogram()[1:])
    weighted_x = 0.0
    weighted_y = 0.0
    total_alpha = 0.0
    for y in range(box[1], box[3]):
        for x in range(box[0], box[2]):
            weight = alpha.getpixel((x, y)) / 255.0
            if weight <= 0.0:
                continue
            weighted_x += x * weight
            weighted_y += y * weight
            total_alpha += weight
    if total_alpha <= 0.0:
        return None
    return box, opaque_pixels, (weighted_x / total_alpha, weighted_y / total_alpha)


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


def scalar_stats(values: list[int]) -> dict:
    return {
        "count": len(values),
        "median": statistics.median(values),
        "p75": percentile(values, 0.75),
        "min": min(values),
        "max": max(values),
    }


def head_proximal_samples(
    samples: list[dict],
    hair_centroid: tuple[float, float],
) -> tuple[list[dict], list[dict]]:
    """Reject a separated Helmet.wil pose cluster that is not at the actor head."""
    ranked = sorted(
        samples,
        key=lambda sample: math.dist(sample["centroid"], hair_centroid),
    )
    half = len(ranked) // 2
    if len(ranked) >= 6 and half >= 3:
        near_distance = math.dist(ranked[half - 1]["centroid"], hair_centroid)
        far_distance = math.dist(ranked[half]["centroid"], hair_centroid)
        if far_distance - near_distance >= 16.0 and far_distance >= near_distance * 2.5:
            return ranked[:half], ranked[half:]
    return samples, []


def main() -> None:
    data, palette, offsets, info = read_library(LIBRARY)
    hair_data, hair_palette, hair_offsets, hair_info = read_library(HAIR_LIBRARY)
    if int(info["image_count"]) != STRIDE * APPEARANCES:
        raise AssertionError("Helmet.wil no longer matches six 600-frame appearances")
    if int(hair_info["image_count"]) <= HAIR_APPEARANCE * HAIR_STRIDE + 599:
        raise AssertionError("Hair.wil does not contain the selected male-warrior anchor appearance")
    action_values: dict[str, list[tuple[int, int]]] = {name: [] for name in ACTIONS}
    action_opaque: dict[str, list[int]] = {name: [] for name in ACTIONS}
    idle_by_direction: dict[str, list[tuple[int, int]]] = {direction: [] for direction in DIRECTIONS}
    idle_opaque_by_direction: dict[str, list[int]] = {direction: [] for direction in DIRECTIONS}
    pose_samples: dict[tuple[str, int, int], list[dict]] = {}
    death_final: list[tuple[int, int]] = []
    death_final_opaque: list[int] = []
    for appearance in range(APPEARANCES):
        for action_name, action in ACTIONS.items():
            for direction_index, direction in enumerate(DIRECTIONS):
                for frame in range(int(action["frames"])):
                    index = appearance * STRIDE + int(action["start"]) + direction_index * 8 + frame
                    measured = frame_metrics(data, palette, offsets, index)
                    if measured is None:
                        continue
                    box, opaque_pixels, centroid = measured
                    frame_size = size(box)
                    action_values[action_name].append(frame_size)
                    action_opaque[action_name].append(opaque_pixels)
                    if action_name == "idle":
                        idle_by_direction[direction].append(frame_size)
                        idle_opaque_by_direction[direction].append(opaque_pixels)
                    pose_samples.setdefault((action_name, direction_index, frame), []).append(
                        {
                            "appearance": appearance,
                            "sourceIndex": index,
                            "bbox": list(box),
                            "centroid": [round(centroid[0], 4), round(centroid[1], 4)],
                        }
                    )
                    if action_name == "death" and frame == int(action["frames"]) - 1:
                        death_final.append(frame_size)
                        death_final_opaque.append(opaque_pixels)
    direction_stats = {
        direction: {**stats(values), "opaquePixels": scalar_stats(idle_opaque_by_direction[direction])}
        for direction, values in idle_by_direction.items()
    }
    runtime_max_envelopes = {
        direction: [max(1, round(value["p75"][0])), max(1, round(value["p75"][1]))]
        for direction, value in direction_stats.items()
    }
    runtime_target_sizes = {
        direction: [max(1, round(value["median"][0])), max(1, round(value["median"][1]))]
        for direction, value in direction_stats.items()
    }
    pose_anchors: dict[str, list[dict]] = {name: [] for name in ACTIONS}
    outlier_filtered_records = 0
    for (action_name, direction_index, frame), samples in sorted(
        pose_samples.items(), key=lambda item: (list(ACTIONS).index(item[0][0]), item[0][1], item[0][2])
    ):
        hair_index = (
            HAIR_APPEARANCE * HAIR_STRIDE
            + int(ACTIONS[action_name]["start"])
            + direction_index * 8
            + frame
        )
        hair_measured = frame_metrics(hair_data, hair_palette, hair_offsets, hair_index)
        if hair_measured is None:
            raise AssertionError(
                f"Hair anchor is empty: action={action_name} direction={direction_index} frame={frame}"
            )
        hair_box, _hair_opaque, hair_centroid = hair_measured
        selected_samples, outlier_samples = head_proximal_samples(samples, hair_centroid)
        if outlier_samples:
            outlier_filtered_records += 1
        pose_anchors[action_name].append(
            {
                "direction": DIRECTIONS[direction_index],
                "directionRow": direction_index,
                "frame": frame,
                "clientAppearanceCount": len(samples),
                "selectedAppearanceCount": len(selected_samples),
                "selectedAppearances": [sample["appearance"] for sample in selected_samples],
                "outlierAppearances": [sample["appearance"] for sample in outlier_samples],
                "hairAnchorSourceIndex": hair_index,
                "hairAnchorOpaqueBox": list(hair_box),
                "hairAnchorCentroid": [
                    round(hair_centroid[0], 4),
                    round(hair_centroid[1], 4),
                ],
                "centroidMedian": [
                    round(statistics.median(sample["centroid"][0] for sample in selected_samples), 4),
                    round(statistics.median(sample["centroid"][1] for sample in selected_samples), 4),
                ],
                "bboxMedian": [
                    round(statistics.median(sample["bbox"][0] for sample in selected_samples), 4),
                    round(statistics.median(sample["bbox"][1] for sample in selected_samples), 4),
                    round(statistics.median(sample["bbox"][2] for sample in selected_samples), 4),
                    round(statistics.median(sample["bbox"][3] for sample in selected_samples), 4),
                ],
                "samples": samples,
            }
        )
    payload = {
        "schemaVersion": 4,
        "source": LIBRARY.relative_to(ROOT).as_posix(),
        "sourceSha256": hashlib.sha256(LIBRARY.read_bytes()).hexdigest(),
        "hairAnchorSource": HAIR_LIBRARY.relative_to(ROOT).as_posix(),
        "hairAnchorSourceSha256": hashlib.sha256(HAIR_LIBRARY.read_bytes()).hexdigest(),
        "hairAnchorAppearance": HAIR_APPEARANCE,
        "hairAnchorStride": HAIR_STRIDE,
        "imageCount": int(info["image_count"]),
        "appearanceStride": STRIDE,
        "appearanceCount": APPEARANCES,
        "sampleRule": "all six real Helmet.wil appearances; MIR2 action offsets and eight direction rows",
        "actions": {
            name: {**stats(values), "opaquePixels": scalar_stats(action_opaque[name])}
            for name, values in action_values.items()
        },
        "idleDirections": direction_stats,
        "directionRuntimeMaxSize": runtime_max_envelopes,
        "directionRuntimeTargetSize": runtime_target_sizes,
        "directionRuntimeOpaquePixels": {
            direction: round(value["opaquePixels"]["median"])
            for direction, value in direction_stats.items()
        },
        "poseAnchorRule": "For every action/direction/frame, use the same-cell Hair.wil male-warrior head centroid to reject a separated non-head Helmet.wil cluster, then place the generated helmet at the median centroid of the remaining head-proximal samples.",
        "outlierFilteredPoseRecords": outlier_filtered_records,
        "poseAnchors": pose_anchors,
        "deathFinal": {
            **stats(death_final),
            "opaquePixels": scalar_stats(death_final_opaque),
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
