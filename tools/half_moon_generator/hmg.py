"""Deterministic CPU authoring for HardCore's six-frame wide_hit sheet.

This module is a development tool. It never loads into the game runtime.
"""

from __future__ import annotations

import copy
import hashlib
import json
import math
import re
from functools import lru_cache
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parents[2]
CELL = (240, 224)
FRAMES = 6
DIRECTIONS = ("S", "SW", "W", "NW", "N", "NE", "E", "SE")
# ArtSpec.mir2_client_direction_row for the logical order above.
DIRECTION_ROWS = (4, 5, 6, 7, 0, 1, 2, 3)
FRAME_ENVELOPE = (0.13, 0.55, 1.0, 1.08, 0.63, 0.21)
TEMPORAL_ENVELOPE = (0.70, 0.70, 0.75, 0.85, 1.0, 0.52)
# Angular limits are signed around the facing axis. Negative is the actor's
# right side. The final tuple is radius scale, screen rise, and angular bounds.
TEMPORAL_SWEEP = (
    (0.58, -34, -60, 0),
    (0.62, -25, -60, 0),
    (0.68, -13, -60, 12),
    (0.84, -4, -60, 35),
    (1.00, 0, -60, 60),
    (0.78, -3, -15, 60),
)
FORMAL = ROOT / "assets/art/characters/warrior/effects/wide_hit.png"
ORIGINAL_SOURCE = Path(__file__).with_name("source") / "wide_hit_original.png"
ORIGINAL_BASE_SHA256 = "aa0b29f13d5c9a196c5f2372ad47fefa75f8b328684d4b8689a70f279c26276c"
ORIGINAL_WORK_ID = "HM_ORIGINAL_WORK"
ORIGINAL_CLEANUP = {"haze_cleanup": 1.0, "body_brightness": 1.22,
                    "core_gain": .22, "edge_detail": .9}
APPROVED_PARAMETERS = {"haze_cleanup": 1.5, "body_brightness": 1.0,
                       "core_gain": 0.0, "edge_detail": 0.0}
APPROVED_ATLAS_SHA256 = "ef9196c3eaa7c9dcb9a01a831d87a4679e6b6d76e5309b7e3526ad236d70cea4"
PROJECT_DIR = ROOT / "dev_art_sources/vfx/half_moon_generator"
PROJECT_PATH = PROJECT_DIR / "half_moon_project.json"
OUTPUT_DIR = ROOT / "outputs/half_moon_generator"
SW_REFERENCE_DIR = PROJECT_DIR / "references/sw"
SW_REFERENCE_SHA256 = (
    "7f235bcb9e4ca6c05c4edba2f7d68f9c6daf85797c8732677b459169dce192a2",
    "921ea9f3c0fbd346602150e4e1c24658b1eb4f802607fee985d6cab6f02c4d5b",
    "f465bdce343ac2c90c942f7dedd31999b4ae56c83f93e914aaff5e68ad57eff6",
    "4bfccdcb9392a850e2562c4825a286d1155759dce638a8f6fde712571b946546",
    "1f735e2b3335dda0aaab4655b25520c0675e51c05ffe9be963f1d866f47198ad",
    "931a39f54ca28d3e85c8b37dae1c1ebca925b00ea2ee8ad72b8186e8aeb6a5f7",
)
# The project ground is a 64x32 diamond: tile axes project to (32,16) and
# (-32,16). Rotate in tile space, then project back to screen space. The
# individual placement values are a default; the browser offers arrow-key
# adjustment for each direction of each candidate.
DIAMOND_BASIS = np.array(((32.0, -32.0), (16.0, 16.0)))
DIAMOND_INVERSE = np.linalg.inv(DIAMOND_BASIS)
REFERENCE_TILE_ROTATION = (45, 0, -45, -90, -135, -180, 135, 90)
REFERENCE_PROJECTION_SCALE = (.72, 1.0, .75, .68, .75, 1.0, .75, .68)
REFERENCE_DIRECTION_SHIFT = ((35, 35), (0, 0), (-20, 0), (-10, -25),
                             (0, -45), (30, -40), (50, -10), (56, 20))
# The SW reference is a tall, open crescent. A direct diamond-basis rotation
# folds that crescent into a narrow hook at the four cardinal facings. Keep
# the intended screen-space arc and project its depth to 65% instead. These
# defaults leave room for the editor's per-direction position adjustment.
REFERENCE_CARDINAL_ARC = {
    0: (45, .65, 25, -15),
    2: (-45, .65, -15, -15),
    4: (-135, .65, 0, -25),
    6: (135, .65, 45, -15),
}

BASE = {
    "arc_radius": 61.0, "arc_span_degrees": 157.0, "arc_thickness": 13.0,
    "inner_radius": 54.5, "outer_radius": 67.5,
    "head_taper": 0.70, "tail_taper": 0.85,
    "edge_sharpness": 0.72, "ellipse_ratio": 0.79,
    "perspective_compression": 0.20,
    "core_width": 3.4, "core_intensity": 0.85,
    "core_position": -0.18, "core_sharpness": 0.78,
    "inner_glow_size": 5.0, "inner_glow_strength": 0.45,
    "outer_glow_size": 8.0, "outer_glow_strength": 0.24,
    "trail_length": 0.24, "trail_width": 7.0,
    "trail_opacity": 0.36, "trail_falloff": 0.70, "trail_breakup": 0.28,
    "breakup_amount": 0.22, "breakup_scale": 3.0,
    "breakup_seed": 0, "edge_noise": 0.24,
    "spark_count": 4, "spark_size": 1.7,
    "spark_spread": 11.0, "spark_lifetime": 0.32,
    "spark_velocity": 6.0, "spark_seed": 0,
    "rotation": 0.0,
    "gradient": {
        "core": "#fff1c3", "body": "#ba873c",
        "outer": "#69401f", "trail": "#926035",
    },
    "frame_envelope": list(FRAME_ENVELOPE),
}

PRESETS = {
    "classic_heavy": {
        "arc_thickness": 17.0, "arc_radius": 59.0, "core_width": 3.8,
        "outer_glow_strength": 0.16, "spark_count": 2, "trail_length": 0.21,
        "gradient": {"core": "#f9e5ad", "body": "#9d743d", "outer": "#5b3924", "trail": "#806043"},
    },
    "sharp_gold": {
        "arc_thickness": 9.7, "arc_radius": 65.0, "core_width": 3.1,
        "core_intensity": 0.98, "edge_sharpness": 0.89,
        "gradient": {"core": "#fff7d5", "body": "#d9a94f", "outer": "#76532c", "trail": "#ae7432"},
    },
    "dark_gold": {
        "arc_thickness": 14.0, "arc_radius": 63.0,
        "outer_glow_strength": 0.12, "spark_count": 2,
        "gradient": {"core": "#e4d2a0", "body": "#886737", "outer": "#402d21", "trail": "#705331"},
    },
    "brutal_slash": {
        "arc_span_degrees": 170.0, "arc_thickness": 15.5,
        "breakup_amount": 0.36, "trail_length": 0.34, "spark_count": 6,
        "gradient": {"core": "#ffe6b5", "body": "#bb7940", "outer": "#693829", "trail": "#995734"},
    },
    "minimal_classic": {
        "arc_thickness": 9.2, "outer_glow_strength": 0.08,
        "inner_glow_strength": 0.24, "spark_count": 1,
        "trail_opacity": 0.22, "breakup_amount": 0.10,
        "gradient": {"core": "#e8dfbe", "body": "#a28d67", "outer": "#5b5141", "trail": "#76694f"},
    },
}

MUTATION = {
    "arc_radius": 5.0, "arc_span_degrees": 22.0,
    "arc_thickness": 5.0, "head_taper": 0.15, "tail_taper": 0.15,
    "edge_sharpness": 0.14, "ellipse_ratio": 0.12,
    "core_width": 1.2, "core_intensity": 0.18,
    "inner_glow_strength": 0.16, "outer_glow_strength": 0.13,
    "trail_length": 0.13, "trail_opacity": 0.15,
    "breakup_amount": 0.14, "spark_count": 3,
}

LIMITS = {
    "arc_radius": (35, 78), "arc_span_degrees": (95, 195),
    "arc_thickness": (5, 24), "head_taper": (0.3, 1),
    "tail_taper": (0.3, 1), "edge_sharpness": (0.1, 1),
    "ellipse_ratio": (0.45, 1.2), "core_width": (1, 8),
    "core_intensity": (0.2, 1), "inner_glow_strength": (0, 0.9),
    "outer_glow_strength": (0, 0.8), "trail_length": (0, 0.7),
    "trail_opacity": (0, 0.8), "breakup_amount": (0, 0.65),
    "spark_count": (0, 12),
}


def stable_seed(*values: object) -> int:
    payload = json.dumps(values, ensure_ascii=False, sort_keys=True).encode("utf-8")
    return int.from_bytes(hashlib.sha256(payload).digest()[:4], "big")


def preset_parameters(preset: str) -> dict:
    if preset not in PRESETS:
        raise ValueError(f"Unknown preset: {preset}")
    result = copy.deepcopy(BASE)
    result.update(copy.deepcopy(PRESETS[preset]))
    result["inner_radius"] = result["arc_radius"] - result["arc_thickness"] / 2
    result["outer_radius"] = result["arc_radius"] + result["arc_thickness"] / 2
    return result


def _vary(parameters: dict, seed: int, amount: float) -> tuple[dict, dict]:
    rng = np.random.default_rng(seed)
    result = copy.deepcopy(parameters)
    delta = {}
    for key, spread in MUTATION.items():
        low, high = LIMITS[key]
        value = float(parameters[key]) + float(rng.uniform(-spread, spread)) * amount
        value = max(low, min(high, value))
        value = int(round(value)) if key == "spark_count" else round(value, 3)
        result[key] = value
        delta[key] = round(float(value) - float(parameters[key]), 3)
    result["inner_radius"] = round(result["arc_radius"] - result["arc_thickness"] / 2, 3)
    result["outer_radius"] = round(result["arc_radius"] + result["arc_thickness"] / 2, 3)
    result["breakup_seed"] = stable_seed(seed, "breakup")
    result["spark_seed"] = stable_seed(seed, "sparks")
    return result, delta


def _candidate(candidate_id: str, preset: str, seed: int, parameters: dict,
               parent_id: str | None = None, delta: dict | None = None,
               render_version: int = 1) -> dict:
    return {"schema_version": 1, "candidate_id": candidate_id,
            "render_version": render_version,
            "parent_id": parent_id, "preset": preset, "seed": seed,
            "parameters": parameters, "parameter_delta": delta or {},
            "direction_overrides": {}, "favorite": False}


def first_generation(seed: int) -> list[dict]:
    # Three coherent families, four controlled variations each.
    groups = (("A", "classic_heavy"), ("B", "sharp_gold"),
              ("C", "dark_gold"))
    silhouettes = {
        "A": ((128, 20, 55, -12), (171, 13, 64, 10),
              (188, 18, 69, -17), (143, 11, 60, 18)),
        "B": ((130, 11, 58, -12), (175, 6, 69, 10),
              (190, 12, 73, -17), (145, 7.5, 63, 18)),
        "C": ((122, 17, 57, -12), (172, 10, 67, 10),
              (191, 19, 70, -17), (145, 9, 62, 18)),
    }
    candidates = []
    for label, preset in groups:
        for index in range(1, 5):
            child_seed = stable_seed(seed, label, index)
            style = "brutal_slash" if label == "C" and index >= 3 else preset
            parameters, delta = _vary(preset_parameters(style), child_seed, 0.38)
            span, thickness, radius, rotation = silhouettes[label][index - 1]
            parameters["arc_span_degrees"] = span
            parameters["arc_thickness"] = thickness
            parameters["arc_radius"] = radius
            parameters["rotation"] = rotation
            parameters["inner_radius"] = radius - thickness / 2
            parameters["outer_radius"] = radius + thickness / 2
            parameters["trail_length"] = round(min(.7, parameters["trail_length"] + (0.12 if index == 3 else 0)), 3)
            parameters["breakup_amount"] = round(min(.65, parameters["breakup_amount"] + (0.14 if index == 4 else 0)), 3)
            parameters["outer_glow_strength"] = round(min(.8, parameters["outer_glow_strength"] + (0.09 if index == 2 else 0)), 3)
            delta = {key: round(float(parameters[key]) - float(preset_parameters(style)[key]), 3)
                     for key in MUTATION}
            candidates.append(_candidate(f"HM_G01_{label}{index}", style,
                                         child_seed, parameters, delta=delta))
    return candidates


def mutate(parent: dict, generation: int) -> list[dict]:
    if generation < 2:
        raise ValueError("Child generation must be >= 2")
    result = []
    for index in range(12):
        child_seed = stable_seed(parent["seed"], generation, index)
        if int(parent.get("render_version", 1)) == 3:
            rng = np.random.default_rng(child_seed)
            parameters = copy.deepcopy(parent["parameters"])
            for key, spread, low, high in (("reference_scale", .06, .75, 1.12),
                                           ("reference_offset_x", 5, -12, 12),
                                           ("reference_offset_y", 5, -12, 12),
                                           ("reference_fade", .10, .25, .80)):
                parameters[key] = round(max(low, min(high, float(parameters[key]) +
                                                       float(rng.uniform(-spread, spread)))), 3)
            delta = {key: round(float(parameters[key]) - float(parent["parameters"][key]), 3)
                     for key in ("reference_scale", "reference_offset_x",
                                 "reference_offset_y", "reference_fade")}
            result.append(_candidate(f"HM_G{generation:02d}_{index + 1:02d}",
                                     parent["preset"], child_seed, parameters,
                                     parent["candidate_id"], delta, 3))
            continue
        parameters, delta = _vary(parent["parameters"], child_seed, 0.38)
        version = int(parent.get("render_version", 1))
        if version == 2:
            parameters["arc_span_degrees"] = 120
            parameters["rotation"] = 0
            parameters["arc_radius"] = round(min(parameters["arc_radius"],
                                                  64 - parameters["arc_thickness"] / 2), 3)
            parameters["inner_radius"] = round(parameters["arc_radius"] - parameters["arc_thickness"] / 2, 3)
            parameters["outer_radius"] = round(parameters["arc_radius"] + parameters["arc_thickness"] / 2, 3)
        result.append(_candidate(f"HM_G{generation:02d}_{index + 1:02d}",
                                 parent["preset"], child_seed, parameters,
                                 parent["candidate_id"], delta, version))
    return result


def fuse(shape: dict, color: dict, trail: dict, particles: dict,
         candidate_id: str) -> dict:
    result = copy.deepcopy(shape["parameters"])
    source = color["parameters"]
    for key in ("gradient", "inner_glow_size", "inner_glow_strength",
                "outer_glow_size", "outer_glow_strength"):
        result[key] = copy.deepcopy(source[key])
    for key in ("trail_length", "trail_width", "trail_opacity",
                "trail_falloff", "trail_breakup"):
        result[key] = trail["parameters"][key]
    for key in ("spark_count", "spark_size", "spark_spread", "spark_lifetime",
                "spark_velocity", "spark_seed"):
        result[key] = particles["parameters"][key]
    seed = stable_seed(shape["seed"], color["seed"], trail["seed"], particles["seed"])
    child = _candidate(candidate_id, shape["preset"], seed, result,
                       shape["candidate_id"], render_version=int(shape.get("render_version", 1)))
    child["fusion_sources"] = {"shape": shape["candidate_id"],
                               "color": color["candidate_id"],
                               "trail": trail["candidate_id"],
                               "particles": particles["candidate_id"]}
    return child


def _direction_transform(index: int, override: dict) -> tuple:
    # A shared source effect is projected for isometric facing. Each direction
    # has a distinct horizontal/vertical ratio and depth shift, not a flat rotate.
    angle = math.pi / 2 + index * math.pi / 4
    diagonal = index % 2 == 1
    # Calibrated against the current formal sheet's occupied cell bounds. The
    # master arc remains shared; only its screen projection and placement vary.
    offsets = ((20, -38), (28, -44), (46, -28), (43, -31),
               (33, -29), (23, -38), (0, -50), (6, -32))
    defaults = {
        "scale_x": 0.88 if diagonal else 1.0,
        "scale_y": 0.75 if diagonal else (0.72 if index in (3, 4, 5) else 0.90),
        "offset_x": float(offsets[index][0]),
        "offset_y": float(offsets[index][1]),
        "skew": (-0.11 if index in (1, 3) else 0.11 if index in (5, 7) else 0.0),
        "ellipse_ratio": 1.0,
        "rotation": 90.0,
    }
    defaults.update(override)
    return angle, defaults


def _color(value: str) -> tuple[int, int, int]:
    value = value.lstrip("#")
    if len(value) != 6:
        raise ValueError("Gradient colors must be #RRGGBB")
    return tuple(int(value[i:i + 2], 16) for i in (0, 2, 4))


def _layer(mask: np.ndarray, color: tuple[int, int, int]) -> Image.Image:
    rgba = np.zeros((CELL[1], CELL[0], 4), dtype=np.uint8)
    rgba[:, :, :3] = color
    rgba[:, :, 3] = np.clip(mask * 255, 0, 255).astype(np.uint8)
    return Image.fromarray(rgba, "RGBA")


@lru_cache(maxsize=6)
def _sw_reference_frame(frame: int) -> Image.Image:
    path = SW_REFERENCE_DIR / f"sw_f{frame}.png"
    if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != SW_REFERENCE_SHA256[frame]:
        raise ValueError(f"Missing or changed SW reference: {path}")
    with Image.open(path) as source:
        if source.size != (1254, 1254):
            raise ValueError(f"Unexpected SW reference dimensions: {path}")
        return source.convert("RGBA")


def _render_sw_reference_cell(candidate: dict, direction: int, frame: int) -> Image.Image:
    p = candidate["parameters"]
    override = candidate.get("direction_overrides", {}).get(DIRECTIONS[direction], {})
    adjust_x = round(float(override.get("offset_x", 0)))
    adjust_y = round(float(override.get("offset_y", 0)))
    size = round(180 * float(p["reference_scale"]))
    source = _sw_reference_frame(frame).resize((size, size), Image.Resampling.LANCZOS)
    opacity = float(p["reference_fade"]) if frame == 5 else 1.0
    if opacity != 1:
        source.putalpha(source.getchannel("A").point(lambda value: round(value * opacity)))
    cell = Image.new("RGBA", CELL)
    cell.alpha_composite(source, (12 + round(float(p["reference_offset_x"])) +
                                  (adjust_x if direction == 1 else 0),
                                  27 + round(float(p["reference_offset_y"])) +
                                  (adjust_y if direction == 1 else 0)))
    if direction == 1:
        return cell
    if direction in REFERENCE_CARDINAL_ARC:
        screen_angle, depth_scale, shift_x, shift_y = REFERENCE_CARDINAL_ARC[direction]
        angle = math.radians(screen_angle)
        screen_rotation = np.array(((math.cos(angle), math.sin(angle)),
                                    (-math.sin(angle), math.cos(angle))))
        projection = np.diag((1.0, depth_scale)) @ screen_rotation
    else:
        angle = math.radians(REFERENCE_TILE_ROTATION[direction])
        tile_rotation = np.array(((math.cos(angle), math.sin(angle)),
                                  (-math.sin(angle), math.cos(angle))))
        projection = (REFERENCE_PROJECTION_SCALE[direction] * DIAMOND_BASIS @
                      tile_rotation @ DIAMOND_INVERSE)
        shift_x, shift_y = REFERENCE_DIRECTION_SHIFT[direction]
    inverse = np.linalg.inv(projection)
    anchor = np.array((96.0, 143.0))
    shift = np.array((shift_x + adjust_x, shift_y + adjust_y))
    bias = anchor - inverse @ (anchor + shift)
    affine = (float(inverse[0, 0]), float(inverse[0, 1]), float(bias[0]),
              float(inverse[1, 0]), float(inverse[1, 1]), float(bias[1]))
    return cell.transform(CELL, Image.Transform.AFFINE, affine,
                          resample=Image.Resampling.BICUBIC)


@lru_cache(maxsize=2)
def _original_atlas(stamp: tuple[int, int]) -> Image.Image:
    if hashlib.sha256(ORIGINAL_SOURCE.read_bytes()).hexdigest() != ORIGINAL_BASE_SHA256:
        raise ValueError("The archived original wide_hit.png changed; review its source before editing")
    with Image.open(ORIGINAL_SOURCE) as source:
        if source.size != (1440, 1792) or source.mode != "RGBA":
            raise ValueError("Unexpected original wide_hit.png contract")
        return source.copy()


def _smoothstep(value: np.ndarray) -> np.ndarray:
    fraction = np.clip(value, 0, 1)
    return fraction * fraction * (3 - 2 * fraction)


def _render_original_cell(candidate: dict, direction: int, frame: int) -> Image.Image:
    if candidate.get("source_sha256") != ORIGINAL_BASE_SHA256:
        raise ValueError("Original source identity does not match this working version")
    stat = ORIGINAL_SOURCE.stat()
    atlas = _original_atlas((stat.st_mtime_ns, stat.st_size))
    row = DIRECTION_ROWS[direction]
    source = atlas.crop((frame * CELL[0], row * CELL[1],
                         (frame + 1) * CELL[0], (row + 1) * CELL[1]))
    parameters = candidate["parameters"]
    pixels = np.asarray(source, dtype=np.float32)
    rgb = pixels[:, :, :3]
    luma = rgb @ np.array((.24, .57, .19), dtype=np.float32)
    blur = np.asarray(Image.fromarray(luma.astype(np.uint8)).filter(
        ImageFilter.GaussianBlur(1.5)), dtype=np.float32)
    detail = luma - blur
    edge_detail = float(parameters["edge_detail"])
    sharpened = np.clip(luma + detail * edge_detail, 0, 255)
    presence = _smoothstep((sharpened - 8) / 142)
    gradient = np.where(sharpened > 8, .12 + .88 * presence ** .72, 0)
    cleanup = float(parameters["haze_cleanup"])
    # 0..1 blends the untouched source into the cleaned gradient. Above 1,
    # raise that gradient to a power so the gray body continues to disappear
    # smoothly while the brightest cutting edge stays opaque.
    opacity = ((1 - cleanup) + cleanup * gradient if cleanup <= 1 else
               np.power(gradient, cleanup))
    alpha = pixels[:, :, 3] * opacity
    bright = np.clip(rgb * float(parameters["body_brightness"]) +
                     detail[:, :, None] * edge_detail * .8, 0, 255)
    highlight = _smoothstep((sharpened - 95) / 115)
    bright += (255 - bright) * (float(parameters["core_gain"]) * highlight[:, :, None])
    rgba = np.dstack((np.clip(bright, 0, 255), np.clip(alpha, 0, 255))).astype(np.uint8)
    result = Image.fromarray(rgba, "RGBA")
    override = candidate.get("direction_overrides", {}).get(DIRECTIONS[direction], {})
    dx = round(float(override.get("offset_x", 0)))
    dy = round(float(override.get("offset_y", 0)))
    if dx == 0 and dy == 0:
        return result
    placed = Image.new("RGBA", CELL)
    placed.paste(result, (dx, dy))
    return placed


def render_cell(candidate: dict, direction: int, frame: int) -> Image.Image:
    if not 0 <= direction < 8 or not 0 <= frame < FRAMES:
        raise ValueError("Invalid direction/frame")
    if int(candidate.get("render_version", 1)) == 4:
        return _render_original_cell(candidate, direction, frame)
    if int(candidate.get("render_version", 1)) == 3:
        return _render_sw_reference_cell(candidate, direction, frame)
    p = candidate["parameters"]
    temporal = int(candidate.get("render_version", 1)) == 2
    override = candidate.get("direction_overrides", {}).get(DIRECTIONS[direction], {})
    angle, transform = _direction_transform(direction, override)
    angle += math.radians(float(p.get("rotation", 0)) + float(transform["rotation"]) -
                          (90 if temporal else 0))
    y, x = np.mgrid[0:CELL[1], 0:CELL[0]].astype(np.float32)
    radius_scale, rise, gate_low, gate_high = (TEMPORAL_SWEEP[frame] if temporal
                                               else (1.0, 0, -180, 180))
    x = x - (96.0 + float(transform["offset_x"]) - (20 if temporal else 0))
    y = y - (143.0 + float(transform["offset_y"]) + rise)
    forward_x, forward_y = math.cos(angle), math.sin(angle)
    side_x, side_y = -forward_y, forward_x
    u = (x * side_x + y * side_y) / float(transform["scale_x"])
    v = (x * forward_x + y * forward_y) / float(transform["scale_y"])
    u -= float(transform["skew"]) * v
    v /= (float(p["ellipse_ratio"]) * float(transform["ellipse_ratio"]) *
          (1 + float(p["perspective_compression"]) * np.abs(u) / 150))
    theta = np.arctan2(u, v)
    radius = np.sqrt(u * u + v * v)
    span = math.radians(float(p["arc_span_degrees"])) / 2
    head = np.clip((span - theta) / max(0.01, span * 0.38), 0, 1)
    tail = np.clip((span + theta) / max(0.01, span * 0.50), 0, 1)
    taper = (head ** float(p["head_taper"])) * (tail ** float(p["tail_taper"]))
    limit = (np.abs(theta) < span).astype(np.float32)
    if temporal:
        limit *= ((theta >= math.radians(gate_low)) &
                  (theta <= math.radians(gate_high))).astype(np.float32)
    rng = np.random.default_rng(stable_seed(candidate["seed"], p["breakup_seed"], direction, frame))
    noise_scale = max(0.5, min(8, float(p["breakup_scale"]))) / 3.0
    coarse = rng.random((max(4, round(28 * noise_scale)),
                         max(4, round(30 * noise_scale))), dtype=np.float32)
    noise = np.asarray(Image.fromarray((coarse * 255).astype(np.uint8), "L").resize(
        CELL, Image.Resampling.BILINEAR), dtype=np.float32) / 255 - 0.5
    wave = np.sin(theta * 19 + float(p["breakup_seed"]) * 0.000001 + frame * 0.63)
    middle_radius = (float(p["inner_radius"]) + float(p["outer_radius"])) / 2
    full_width = float(p["outer_radius"]) - float(p["inner_radius"])
    ridge = middle_radius * radius_scale + noise * float(p["edge_noise"]) * 4 + wave * float(p["edge_noise"]) * 1.4
    width = np.maximum(0.9, full_width * taper * radius_scale)
    signed = np.abs(radius - ridge)
    edge = np.clip((width / 2 - signed) / (2.2 - float(p["edge_sharpness"]) * 1.7), 0, 1)
    breakup = np.clip((noise + 0.5) * 1.5 - float(p["breakup_amount"]) *
                      (np.abs(theta) / span) ** 2, 0, 1)
    body = edge * limit * breakup
    intensity = float(p.get("frame_envelope", FRAME_ENVELOPE)[frame])
    body = np.clip(body * intensity * 0.86, 0, 1)
    core_distance = np.abs(radius - (ridge + float(p["core_position"]) * width))
    core = np.clip((float(p["core_width"]) - core_distance) /
                   max(0.35, 2.0 - float(p["core_sharpness"])), 0, 1)
    core = core * limit * taper * breakup * min(1, intensity * float(p["core_intensity"]))
    colors = p["gradient"]
    result = Image.new("RGBA", CELL)
    outer = Image.fromarray(np.clip(body * 255, 0, 255).astype(np.uint8), "L")
    for size, strength in ((p["outer_glow_size"], p["outer_glow_strength"]),
                           (p["inner_glow_size"], p["inner_glow_strength"])):
        if float(strength) > 0:
            glow = np.asarray(outer.filter(ImageFilter.GaussianBlur(float(size))), dtype=np.float32) / 255
            result.alpha_composite(_layer(glow * float(strength), _color(colors["outer"])))
    # Broad swept ghost creates movement without a second unrelated shape.
    lag = float(p["trail_length"]) * (0.7 + frame / 8)
    ghost_angle = theta + lag
    ghost = np.exp(-((radius - ridge + float(p["trail_width"]) * 0.45) /
                     max(1.0, float(p["trail_width"]))) ** 2)
    ghost *= (ghost_angle > -span) & (ghost_angle < span)
    if temporal:
        ghost *= (ghost_angle >= math.radians(gate_low)) & (ghost_angle <= math.radians(gate_high))
    ghost *= np.clip((span - np.abs(ghost_angle)) / (span * 0.32), 0, 1)
    ghost *= np.clip((span - np.abs(ghost_angle)) / span, 0, 1) ** (float(p["trail_falloff"]) * 0.8)
    ghost *= np.clip((noise + 0.5) * 1.4 - float(p["trail_breakup"]) * 0.35, 0, 1)
    ghost *= float(p["trail_opacity"]) * min(1, intensity * 1.15)
    result.alpha_composite(_layer(ghost, _color(colors["trail"])))
    result.alpha_composite(_layer(body, _color(colors["body"])))
    # Two asymmetrical forged-metal streaks keep the body from reading as a
    # single flat ring. Their position follows the same arc and frame clock.
    bright_edge = np.exp(-((radius - (ridge - width * 0.34)) / 1.45) ** 2)
    bright_edge *= limit * taper * breakup * min(1, intensity) * 0.47
    result.alpha_composite(_layer(bright_edge, _color(colors["core"])))
    flowing_ridge = ridge + width * 0.20 + 2.2 * np.sin(theta * 3.1 + frame * 0.3)
    flowing = np.exp(-((radius - flowing_ridge) / 1.25) ** 2)
    flowing *= limit * np.clip((theta + span * 0.8) / (span * 0.5), 0, 1)
    flowing *= np.clip((span * 0.9 - theta) / (span * 0.5), 0, 1)
    flowing *= breakup * min(1, intensity) * 0.34
    result.alpha_composite(_layer(flowing, _color(colors["core"])))
    result.alpha_composite(_layer(core, _color(colors["core"])))
    if frame in ((2, 3, 4) if temporal else (2, 3)):
        accent = np.clip(core * (0.35 if frame == 2 else 0.22), 0, 1)
        result.alpha_composite(_layer(accent, (255, 246, 222)))
    spark_rng = np.random.default_rng(stable_seed(candidate["seed"], p["spark_seed"], direction, frame))
    draw = ImageDraw.Draw(result, "RGBA")
    if frame in (2, 3, 4):
        fragment_count = round(float(p["breakup_amount"]) * 13)
        for _ in range(fragment_count):
            low = max(-span * .98, math.radians(gate_low)) if temporal else -span * .98
            high = min(-span * .58, math.radians(gate_high)) if temporal else -span * .58
            if low >= high:
                break
            t = float(spark_rng.uniform(low, high))
            r = float(p["arc_radius"]) * radius_scale + float(spark_rng.uniform(-6, 8))
            fragment = []
            for radial, angular in ((r, t), (r + 5.5, t - 0.035), (r + 2.5, t + 0.04)):
                sx = math.sin(angular) * radial
                sy = math.cos(angular) * radial * float(p["ellipse_ratio"])
                sx += float(transform["skew"]) * sy
                fragment.append((96 + float(transform["offset_x"]) - (20 if temporal else 0) +
                                 sx * side_x * float(transform["scale_x"]) +
                                 sy * forward_x * float(transform["scale_y"]),
                                 143 + float(transform["offset_y"]) + rise +
                                 sx * side_y * float(transform["scale_x"]) +
                                 sy * forward_y * float(transform["scale_y"])))
            draw.polygon(fragment, fill=(*_color(colors["trail"]), round(110 * min(1, intensity))))
    spark_life = max(0.05, float(p["spark_lifetime"]))
    spark_decay = max(0.1, 1 - max(0, frame - 2) * 0.13 / spark_life)
    count = round(float(p["spark_count"]) * min(1.0, intensity))
    for _ in range(count):
        low = max(-span * .86, math.radians(gate_low)) if temporal else -span * .86
        high = min(span * .86, math.radians(gate_high)) if temporal else span * .86
        if low >= high:
            break
        t = float(spark_rng.uniform(low, high))
        r = (float(p["arc_radius"]) * radius_scale +
             float(spark_rng.uniform(-p["spark_spread"], p["spark_spread"])) +
             max(0, frame - 2) * float(p["spark_velocity"]))
        sx = math.sin(t) * r
        sy = math.cos(t) * r * float(p["ellipse_ratio"]) * float(transform["ellipse_ratio"])
        sx += float(transform["skew"]) * sy
        px = 96 + float(transform["offset_x"]) - (20 if temporal else 0) + (sx * side_x * float(transform["scale_x"]) + sy * forward_x * float(transform["scale_y"]))
        py = 143 + float(transform["offset_y"]) + rise + (sx * side_y * float(transform["scale_x"]) + sy * forward_y * float(transform["scale_y"]))
        size = float(p["spark_size"]) * float(spark_rng.uniform(0.5, 1.25))
        draw.ellipse((px - size, py - size, px + size, py + size),
                     fill=(*_color(colors["core"]), round(170 * min(1, intensity) * spark_decay)))
    return result


def bake(candidate: dict) -> Image.Image:
    atlas = Image.new("RGBA", (CELL[0] * FRAMES, CELL[1] * 8))
    for direction in range(8):
        row = DIRECTION_ROWS[direction]
        for frame in range(FRAMES):
            atlas.paste(render_cell(candidate, direction, frame),
                        (frame * CELL[0], row * CELL[1]))
    return atlas


def approved_atlas() -> Image.Image:
    """Rebuild the user-approved 150% atlas independently of live editor state."""
    candidate = _new_original_candidate(1839421)
    candidate["parameters"] = dict(APPROVED_PARAMETERS)
    return bake(candidate)


def preview_strip(candidate: dict, direction: int) -> Image.Image:
    strip = Image.new("RGBA", (CELL[0] * FRAMES, CELL[1]))
    for frame in range(FRAMES):
        strip.paste(render_cell(candidate, direction, frame), (frame * CELL[0], 0))
    return strip


def inspect_cells(atlas: Image.Image) -> list[dict]:
    if atlas.size != (1440, 1792) or atlas.mode != "RGBA":
        raise ValueError("Expected 1440x1792 RGBA atlas")
    cells = []
    for row in range(8):
        for frame in range(FRAMES):
            alpha = np.asarray(atlas.crop((frame * 240, row * 224,
                                           (frame + 1) * 240, (row + 1) * 224)).getchannel("A"))
            ys, xs = np.nonzero(alpha > 8)
            bounds = [int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())] if len(xs) else None
            cells.append({"row": row, "frame": frame,
                          "alpha_pixels": int(len(xs)), "bounds": bounds,
                          "center": [round(float(xs.mean()), 2), round(float(ys.mean()), 2)] if len(xs) else None})
    return cells


def warnings_for(atlas: Image.Image, candidate: dict | None = None) -> list[str]:
    cells = inspect_cells(atlas)
    warnings = []
    for cell in cells:
        label = f"row={cell['row']} frame={cell['frame']}"
        bounds = cell["bounds"]
        if bounds is None:
            warnings.append(f"EMPTY_FRAME {label}")
        elif bounds[0] <= 1 or bounds[1] <= 1 or bounds[2] >= 238 or bounds[3] >= 222:
            warnings.append(f"CLIPPED_EDGE {label}")
        if cell["alpha_pixels"] > CELL[0] * CELL[1] * 0.55:
            warnings.append(f"FULL_SCREEN_ALPHA {label}")
    for row in range(8):
        sequence = cells[row * FRAMES:(row + 1) * FRAMES]
        for a, b in zip(sequence, sequence[1:]):
            # The six supplied SW frames intentionally jump from a compact
            # opening blade to the long fan on F1. The source pixels are the
            # authority for that transition; edge clipping is still checked.
            if candidate and int(candidate.get("render_version", 1)) == 3 and a["frame"] == 0:
                continue
            label = f"row={row} {a['frame']}->{b['frame']}"
            if (a["center"] and b["center"] and
                    math.dist(a["center"], b["center"]) > 24):
                warnings.append(f"POSSIBLE_FRAME_POP center {label}")
            smaller = min(a["alpha_pixels"], b["alpha_pixels"])
            larger = max(a["alpha_pixels"], b["alpha_pixels"])
            if smaller > 0 and larger / smaller > 4:
                warnings.append(f"POSSIBLE_FRAME_POP alpha_area {label}")
            if a["bounds"] and b["bounds"]:
                widths = (a["bounds"][2] - a["bounds"][0],
                          b["bounds"][2] - b["bounds"][0])
                heights = (a["bounds"][3] - a["bounds"][1],
                           b["bounds"][3] - b["bounds"][1])
                if abs(widths[0] - widths[1]) > 70 or abs(heights[0] - heights[1]) > 70:
                    warnings.append(f"POSSIBLE_FRAME_POP bounds {label}")
    peaks = [cells[row * FRAMES + 3]["alpha_pixels"] for row in range(8)]
    if min(peaks) > 0 and max(peaks) / min(peaks) > 3:
        warnings.append("DIRECTION_SIZE_IMBALANCE frame=3")
    return warnings


def bake_preview(candidate: dict, target: Path) -> dict:
    target = target.resolve()
    if target == FORMAL.resolve() or not target.is_relative_to(OUTPUT_DIR.resolve()):
        raise ValueError("Bake Preview must remain inside outputs/half_moon_generator")
    target.parent.mkdir(parents=True, exist_ok=True)
    atlas = bake(candidate)
    atlas.save(target, format="PNG", optimize=False)
    return {"path": str(target), "sha256": hashlib.sha256(target.read_bytes()).hexdigest(),
            "warnings": warnings_for(atlas, candidate)}


def export_contact_sheet(candidate: dict) -> Path:
    candidate_id = str(candidate["candidate_id"])
    if not re.fullmatch(r"HM_[A-Z0-9_]+", candidate_id):
        raise ValueError("Invalid candidate ID")
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    target = (OUTPUT_DIR / f"{candidate_id}_contact_sheet.png").resolve()
    bake(candidate).save(target, format="PNG", optimize=False)
    return target


def new_project(seed: int = 1839421) -> dict:
    first = first_generation(seed)
    return {"schema_version": 1, "project_id": "hardcore.half_moon.v1",
            "base_seed": seed, "active_generation": 1,
            "selected_id": first[0]["candidate_id"],
            "generations": [{"generation": 1, "parent_id": None,
                             "candidate_ids": [c["candidate_id"] for c in first]}],
            "candidates": {c["candidate_id"]: c for c in first}}


def new_single_sw_project(seed: int = 1839421) -> dict:
    """Create one editable SW-derived animation from the six supplied frames."""
    for frame in range(FRAMES):
        _sw_reference_frame(frame)
    parameters = preset_parameters("minimal_classic")
    parameters.update(reference_scale=1.0, reference_offset_x=0,
                      reference_offset_y=0, reference_fade=.5)
    candidate = _candidate("HM_SW_WORK", "sw_reference", seed, parameters,
                           render_version=3)
    return {"schema_version": 1, "project_id": "hardcore.half_moon.v1",
            "base_seed": seed, "active_generation": 1,
            "selected_id": candidate["candidate_id"],
            "generations": [{"generation": 1, "parent_id": None,
                             "kind": "sw_reference_v3", "curated": True,
                             "candidate_ids": [candidate["candidate_id"]]}],
            "candidates": {candidate["candidate_id"]: candidate}}


def _new_original_candidate(seed: int) -> dict:
    candidate = _candidate(ORIGINAL_WORK_ID, "original_cleanup", seed,
                           dict(ORIGINAL_CLEANUP), render_version=4)
    candidate["source_sha256"] = ORIGINAL_BASE_SHA256
    return candidate


def new_original_project(seed: int = 1839421) -> dict:
    stat = ORIGINAL_SOURCE.stat()
    _original_atlas((stat.st_mtime_ns, stat.st_size))
    candidate = _new_original_candidate(seed)
    return {"schema_version": 1, "project_id": "hardcore.half_moon.v1",
            "base_seed": seed, "active_generation": 1,
            "selected_id": ORIGINAL_WORK_ID,
            "generations": [{"generation": 1, "parent_id": None,
                             "kind": "original_cleanup_v4",
                             "candidate_ids": [ORIGINAL_WORK_ID]}],
            "candidates": {ORIGINAL_WORK_ID: candidate}}


def select_original_work(project: dict) -> bool:
    """Preserve historical candidates and select one editable original-material copy."""
    stat = ORIGINAL_SOURCE.stat()
    _original_atlas((stat.st_mtime_ns, stat.st_size))
    changed = False
    if ORIGINAL_WORK_ID not in project["candidates"]:
        project["candidates"][ORIGINAL_WORK_ID] = _new_original_candidate(
            int(project["base_seed"]))
        generation = len(project["generations"]) + 1
        project["generations"].append({"generation": generation,
                                       "parent_id": None,
                                       "kind": "original_cleanup_v4",
                                       "candidate_ids": [ORIGINAL_WORK_ID]})
        project["active_generation"] = generation
        changed = True
    candidate = project["candidates"][ORIGINAL_WORK_ID]
    if candidate.get("render_version") != 4 or candidate.get("source_sha256") != ORIGINAL_BASE_SHA256:
        raise ValueError("Saved original-material working version has a conflicting identity")
    if project["selected_id"] != ORIGINAL_WORK_ID:
        project["selected_id"] = ORIGINAL_WORK_ID
        changed = True
    return changed


def load_project(path: Path = PROJECT_PATH) -> dict:
    if not path.exists():
        return new_project()
    project = json.loads(path.read_text(encoding="utf-8"))
    if project.get("schema_version") != 1 or project.get("project_id") != "hardcore.half_moon.v1":
        raise ValueError("Unsupported Half Moon project")
    if not isinstance(project.get("candidates"), dict) or not isinstance(project.get("generations"), list):
        raise ValueError("Invalid Half Moon project")
    return project


def save_project(project: dict, path: Path = PROJECT_PATH) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(".json.tmp")
    temporary.write_text(json.dumps(project, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
                         encoding="utf-8")
    temporary.replace(path)


def add_mutation(project: dict, parent_id: str) -> list[dict]:
    parent = project["candidates"][parent_id]
    generation = len(project["generations"]) + 1
    children = mutate(parent, generation)
    project["candidates"].update({c["candidate_id"]: c for c in children})
    project["generations"].append({"generation": generation, "parent_id": parent_id,
                                   "candidate_ids": [c["candidate_id"] for c in children]})
    project["active_generation"] = generation
    project["selected_id"] = children[0]["candidate_id"]
    return children


def add_generation(project: dict, preset: str, seed: int) -> list[dict]:
    return add_temporal_batch(project, preset, seed)


def add_temporal_batch(project: dict, preset: str | None = None,
                       seed: int | None = None) -> list[dict]:
    """Append a six-frame 120-degree swing without changing saved candidates."""
    if preset is None and any(g.get("kind") == "temporal_120_v2" and
                              g.get("curated") for g in project["generations"]):
        raise ValueError("Curated temporal batch already exists")
    if preset is not None and preset not in PRESETS:
        raise ValueError(f"Unknown preset: {preset}")
    generation = len(project["generations"]) + 1
    chosen_seed = int(project["base_seed"] if seed is None else seed)
    children = []
    for index in range(12):
        family = index // 4
        turn = index % 4
        style = preset or ("classic_heavy", "sharp_gold", "dark_gold")[family]
        base = preset_parameters(style)
        child_seed = stable_seed(chosen_seed, style, generation, index, "temporal_120_v2")
        parameters, _ = _vary(base, child_seed, 0.20)
        parameters["arc_span_degrees"] = 120
        parameters["arc_thickness"] = ((17, 15, 18, 16), (10, 9, 11, 8),
                                        (14, 12, 15, 13))[family][turn]
        parameters["arc_radius"] = ((49, 52, 46, 54), (53, 55, 51, 56),
                                     (52, 54, 48, 55))[family][turn]
        parameters["rotation"] = 0
        parameters["frame_envelope"] = list(TEMPORAL_ENVELOPE)
        parameters["inner_radius"] = round(parameters["arc_radius"] - parameters["arc_thickness"] / 2, 3)
        parameters["outer_radius"] = round(parameters["arc_radius"] + parameters["arc_thickness"] / 2, 3)
        if family == 2:
            parameters["breakup_amount"] = round(min(.65, parameters["breakup_amount"] + .13), 3)
            parameters["trail_length"] = round(min(.7, parameters["trail_length"] + .09), 3)
        delta = {key: round(float(parameters[key]) - float(base[key]), 3) for key in MUTATION}
        suffix = f"{'ABC'[family]}{turn + 1}" if preset is None else f"{index + 1:02d}"
        children.append(_candidate(f"HM_G{generation:02d}_{suffix}", style,
                                   child_seed, parameters, delta=delta, render_version=2))
    project["candidates"].update({c["candidate_id"]: c for c in children})
    project["generations"].append({"generation": generation, "parent_id": None,
                                   "kind": "temporal_120_v2", "curated": preset is None,
                                   "candidate_ids": [c["candidate_id"] for c in children]})
    project["active_generation"] = generation
    project["selected_id"] = children[0]["candidate_id"]
    return children


def add_sw_reference_batch(project: dict) -> list[dict]:
    """Append 12 scaled/placed variants of the user-approved SW six frames."""
    if any(g.get("kind") == "sw_reference_v3" and g.get("curated")
           for g in project["generations"]):
        raise ValueError("SW reference batch already exists")
    for frame in range(FRAMES):
        _sw_reference_frame(frame)
    generation = len(project["generations"]) + 1
    variants = ((.88, -3, 1), (.91, 0, 0), (.94, 3, -2), (.96, -2, -3),
                (1.0, 0, 0), (1.0, 4, 0), (1.0, 0, -4), (1.0, -4, 3),
                (1.04, 0, -2), (1.06, 2, -4), (1.08, -2, -4), (1.08, 2, 0))
    children = []
    for index, (scale, x, y) in enumerate(variants):
        parameters = preset_parameters("minimal_classic")
        parameters.update(reference_scale=scale, reference_offset_x=x,
                          reference_offset_y=y, reference_fade=.5)
        label = "ABC"[index // 4] + str(index % 4 + 1)
        children.append(_candidate(f"HM_G{generation:02d}_{label}", "sw_reference",
                                   stable_seed(project["base_seed"], generation, label,
                                               "sw_reference_v3"),
                                   parameters, render_version=3))
    project["candidates"].update({c["candidate_id"]: c for c in children})
    project["generations"].append({"generation": generation, "parent_id": None,
                                   "kind": "sw_reference_v3", "curated": True,
                                   "candidate_ids": [c["candidate_id"] for c in children]})
    project["active_generation"] = generation
    project["selected_id"] = children[4]["candidate_id"]
    return children


def add_curated_batch(project: dict) -> list[dict]:
    generation = len(project["generations"]) + 1
    children = copy.deepcopy(first_generation(project["base_seed"]))
    for child in children:
        child["candidate_id"] = child["candidate_id"].replace("HM_G01_", f"HM_G{generation:02d}_", 1)
    project["candidates"].update({c["candidate_id"]: c for c in children})
    project["generations"].append({"generation": generation, "parent_id": None,
                                   "kind": "curated_a_b_c",
                                   "candidate_ids": [c["candidate_id"] for c in children]})
    project["active_generation"] = generation
    project["selected_id"] = children[0]["candidate_id"]
    return children


def add_fusion(project: dict, shape_id: str, color_id: str,
               trail_id: str, particles_id: str) -> dict:
    sources = project["candidates"]
    candidate_id = f"HM_FUSION_{1 + sum(k.startswith('HM_FUSION_') for k in sources):03d}"
    candidate = fuse(sources[shape_id], sources[color_id], sources[trail_id],
                     sources[particles_id], candidate_id)
    sources[candidate_id] = candidate
    project["selected_id"] = candidate_id
    return candidate


def set_favorite(project: dict, candidate_id: str, favorite: bool) -> None:
    project["candidates"][candidate_id]["favorite"] = bool(favorite)


def edit_candidate(project: dict, candidate_id: str, changes: dict,
                   direction: str | None = None) -> None:
    candidate = project["candidates"][candidate_id]
    if direction is not None:
        if direction not in DIRECTIONS:
            raise ValueError("Unknown direction")
        allowed = ({"offset_x", "offset_y"}
                   if int(candidate.get("render_version", 1)) in (3, 4) else
                   {"scale_x", "scale_y", "offset_x", "offset_y", "skew",
                    "ellipse_ratio", "rotation"})
        if set(changes) - allowed:
            raise ValueError("Unknown direction transform")
        target = copy.deepcopy(candidate["direction_overrides"].get(direction, {}))
    else:
        target = copy.deepcopy(candidate["parameters"])
        version = int(candidate.get("render_version", 1))
        allowed = (set(ORIGINAL_CLEANUP) if version == 4 else
                   set(BASE) - {"inner_radius", "outer_radius"})
        if version == 3:
            allowed |= {"reference_scale", "reference_offset_x",
                        "reference_offset_y", "reference_fade"}
        if set(changes) - allowed:
            raise ValueError("Unknown parameter")
    for key, value in changes.items():
        if key == "gradient" and direction is None:
            if (not isinstance(value, dict) or set(value) != {"core", "body", "outer", "trail"}
                    or any(not isinstance(color, str) or not re.fullmatch(r"#[0-9a-fA-F]{6}", color)
                           for color in value.values())):
                raise ValueError("Invalid four-part gradient")
            target[key] = copy.deepcopy(value)
            continue
        if key == "frame_envelope" and direction is None:
            if (not isinstance(value, list) or len(value) != FRAMES
                    or any(not isinstance(v, (int, float)) or not math.isfinite(v)
                           or not 0.03 <= v <= 1.5 for v in value)):
                raise ValueError("Invalid six-frame envelope")
            target[key] = list(value)
            continue
        if not isinstance(value, (int, float)) or not math.isfinite(value):
            raise ValueError(f"Invalid value for {key}")
        if direction is not None and int(candidate.get("render_version", 1)) in (3, 4) and key in ("offset_x", "offset_y"):
            if not -80 <= value <= 80:
                raise ValueError(f"Direction offset exceeds 80 pixels: {key}")
        if direction is None and int(candidate.get("render_version", 1)) == 4:
            low, high = {"haze_cleanup": (0, 2), "body_brightness": (1, 1.5),
                         "core_gain": (0, .6), "edge_detail": (0, 2)}[key]
            if not low <= value <= high:
                raise ValueError(f"Out of range: {key}")
        if key in ("reference_scale", "reference_offset_x", "reference_offset_y", "reference_fade"):
            low, high = {"reference_scale": (.75, 1.12),
                         "reference_offset_x": (-12, 12),
                         "reference_offset_y": (-12, 12),
                         "reference_fade": (.25, .80)}[key]
            if not low <= value <= high:
                raise ValueError(f"Out of range: {key}")
        if key in LIMITS and not LIMITS[key][0] <= value <= LIMITS[key][1]:
            raise ValueError(f"Out of range: {key}")
        if direction is None and int(candidate.get("render_version", 1)) == 2:
            if key == "arc_span_degrees" and value != 120:
                raise ValueError("Temporal Half Moon fan must remain 120 degrees")
            if key == "rotation" and value != 0:
                raise ValueError("Temporal Half Moon fan must stay centered on facing")
        target[key] = value
    if direction is None:
        if int(candidate.get("render_version", 1)) != 4:
            target["inner_radius"] = round(target["arc_radius"] - target["arc_thickness"] / 2, 3)
            target["outer_radius"] = round(target["arc_radius"] + target["arc_thickness"] / 2, 3)
            if int(candidate.get("render_version", 1)) == 2 and target["outer_radius"] > 64:
                raise ValueError("Temporal Half Moon reach must remain within two cells")
        if target != candidate["parameters"]:
            candidate.setdefault("revisions", []).append({
                "parameters": copy.deepcopy(candidate["parameters"]),
                "direction_overrides": copy.deepcopy(candidate["direction_overrides"]),
            })
        candidate["parameters"] = target
    else:
        if target != candidate["direction_overrides"].get(direction, {}):
            candidate.setdefault("revisions", []).append({
                "parameters": copy.deepcopy(candidate["parameters"]),
                "direction_overrides": copy.deepcopy(candidate["direction_overrides"]),
            })
        candidate["direction_overrides"][direction] = target


def _runtime_art_paths() -> dict:
    layer = json.loads((ROOT / "assets/data/layers/presentation_layer.json").read_text(encoding="utf-8"))
    skin = layer["skins"][layer["activeSkin"]]
    manifest = json.loads((ROOT / skin["manifest"].removeprefix("res://")).read_text(encoding="utf-8"))
    return manifest["runtimeAssets"]


@lru_cache(maxsize=3)
def weapon_anchor(filename: str) -> tuple[int, int]:
    path = f"res://assets/art/characters/warrior/wear/weapon/{filename}"
    catalog = json.loads((ROOT / "assets/data/warrior_wear_sources.json").read_text(encoding="utf-8"))
    matches = []

    def visit(value):
        if isinstance(value, dict):
            if value.get("path") == path and "footAnchor" in value:
                matches.append(tuple(int(part) for part in value["footAnchor"]))
            for child in value.values():
                visit(child)
        elif isinstance(value, list):
            for child in value:
                visit(child)

    visit(catalog)
    if not matches or len(set(matches)) != 1:
        raise ValueError(f"No unique source foot anchor for {filename}")
    return matches[0]


def actor_strip(direction: int, equipment: str = "base") -> Image.Image:
    if direction not in range(8):
        raise ValueError("Invalid direction")
    weapon_names = {"base": None, "sword": "weapon_004_attack.png",
                    "heavy": "weapon_008_attack.png"}
    if equipment not in weapon_names:
        raise ValueError("Unknown representative equipment")
    assets = _runtime_art_paths()
    body_path = ROOT / assets["player"]["attack"].removeprefix("res://")
    with Image.open(body_path) as image:
        body = image.convert("RGBA")
    weapon = None
    weapon_foot = None
    if weapon_names[equipment]:
        weapon_path = (ROOT / "assets/art/characters/warrior/wear/weapon" /
                       weapon_names[equipment])
        with Image.open(weapon_path) as image:
            weapon = image.convert("RGBA")
        weapon_foot = weapon_anchor(weapon_names[equipment])
    row = DIRECTION_ROWS[direction]
    strip = Image.new("RGBA", (CELL[0] * FRAMES, CELL[1]))
    for frame in range(FRAMES):
        cell = Image.new("RGBA", CELL)
        source = body.crop((frame * 192, row * 160, (frame + 1) * 192, (row + 1) * 160))
        cell.alpha_composite(source, (96 - 64, 143 - 80))
        if weapon is not None:
            source = weapon.crop((frame * 192, row * 224, (frame + 1) * 192, (row + 1) * 224))
            cell.alpha_composite(source, (96 - weapon_foot[0], 143 - weapon_foot[1]))
        strip.paste(cell, (frame * CELL[0], 0))
    return strip


def original_strip(direction: int) -> Image.Image:
    row = DIRECTION_ROWS[direction]
    with Image.open(FORMAL) as image:
        return image.crop((0, row * CELL[1], CELL[0] * FRAMES,
                           (row + 1) * CELL[1])).convert("RGBA")


def composite_strip(candidate: dict | None, direction: int, equipment: str = "base") -> Image.Image:
    actor = actor_strip(direction, equipment)
    effect = original_strip(direction) if candidate is None else preview_strip(candidate, direction)
    for frame in range(FRAMES):
        rect = (frame * CELL[0], 0, (frame + 1) * CELL[0], CELL[1])
        cell = actor.crop(rect)
        cell.alpha_composite(effect.crop(rect))
        actor.paste(cell, (frame * CELL[0], 0))
    return actor
