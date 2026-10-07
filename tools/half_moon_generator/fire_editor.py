"""Independent preview of the original sharded warrior fire-sword effect."""

from __future__ import annotations

import hashlib
import io
import json
import threading
from functools import lru_cache
from pathlib import Path

import numpy as np
from PIL import Image

from tools.half_moon_generator import hmg, power_editor


SOURCE_DIR = Path(__file__).with_name("source")
FORMAL_DIR = hmg.ROOT / "assets/art/characters/warrior/effects"
SOURCE_HASHES = {
    "d0_f0": "092123752789cedb651b2f1aed023290760bfa707c5aebbcb9dcda5d8a3b5ae2",
    "d0_f1": "18e1da5a8af8ce017895c724a4b3fe53209738f8f06754f474855667ebf06a42",
    "d1_f0": "5f68ce38c199670db5c200d7121a6ae1c92a42fd320f168592b3b74929cb2bf6",
    "d1_f1": "c548ba01ea35f0797c7d77ca050b88c96632ab17a80431413ac539098637cafe",
}
APPROVED_STRENGTH = 0.3
APPROVED_HASHES = {
    "d0_f0": "13bd0f9cf30d160fc58efe77f6a8db46a1e4180f81dbc4ddcc4018bf7782f0ec",
    "d0_f1": "6b891619eda839505392ca7256d02a62ee13d510a8c1562c3f6ce402ae1dab2f",
    "d1_f0": "abd968e1ab6ce78e264d45e62b4b72bd0c85f2aba6e5720dfcb2db40283a9ea8",
    "d1_f1": "198e08a5dbd7d2923fadb6fe807ff400344db09fbbdb9f36e76f56af972b4ff7",
}
PROJECT_PATH = hmg.PROJECT_DIR / "fire_hit_project.json"
SOURCE_CELL = (640, 480)
PREVIEW_CELL = (800, 624)
ACTOR_OFFSET = (296, 216)
EFFECT_BASE_OFFSET = (64, 64)
WEAPONS = {"sword": "weapon_004_attack.png", "heavy": "weapon_008_attack.png"}


@lru_cache(maxsize=1)
def source_shards() -> dict[str, Image.Image]:
    result = {}
    for part, expected_hash in SOURCE_HASHES.items():
        path = SOURCE_DIR / f"fire_hit_{part}_original.png"
        if hashlib.sha256(path.read_bytes()).hexdigest() != expected_hash:
            raise ValueError(f"Archived fire-hit source identity changed: {part}")
        with Image.open(path) as image:
            if image.size != (1920, 1920) or image.mode != "RGBA":
                raise ValueError(f"Unexpected fire-hit shard layout: {part}")
            result[part] = image.copy()
    return result


@lru_cache(maxsize=1)
def fire_frames() -> list[dict]:
    manifest = json.loads((hmg.ROOT / "assets/data/warrior_client_art_sources.json")
                          .read_text(encoding="utf-8"))
    frames = manifest["effects"]["烈火剑法"]["sourceFrames"]
    if len(frames) != 48 or any("ignitionOffset" not in frame for frame in frames):
        raise ValueError("Fire-hit ignition metadata is incomplete")
    return frames


@lru_cache(maxsize=2)
def weapon_frames(equipment: str) -> list[dict]:
    if equipment not in WEAPONS:
        raise ValueError("Fire preview requires a sword or heavy weapon")
    catalog = json.loads((hmg.ROOT / "assets/data/warrior_wear_sources.json")
                         .read_text(encoding="utf-8"))
    suffix = WEAPONS[equipment]
    matches = [node.get("weaponAppearance", {}).get("actions", {}).get("attack", {})
               for node in catalog["runtimeMappings"].values()]
    matches = [row["sourceFrames"] for row in matches
               if row.get("path", "").endswith(suffix)]
    if not matches or any(row != matches[0] for row in matches) or len(matches[0]) != 48:
        raise ValueError(f"No unique weapon-tip sequence for {equipment}")
    return matches[0]


def source_cell(direction: int, frame: int) -> Image.Image:
    if direction not in range(8) or frame not in range(6):
        raise ValueError("Unknown fire-hit direction or frame")
    row = hmg.DIRECTION_ROWS[direction]
    part = f"d{row // 4}_f{frame // 3}"
    x, y = (frame % 3) * 640, (row % 4) * 480
    return source_shards()[part].crop((x, y, x + 640, y + 480))


def clean_cell(cell: Image.Image, strength: float) -> Image.Image:
    if not 0 <= strength <= 3:
        raise ValueError("Dark-fire cleanup must be 0..300%")
    if strength == 0:
        return cell.copy()
    pixels = np.asarray(cell, dtype=np.float32).copy()
    energy = np.maximum(pixels[:, :, 0] * .9, pixels[:, :, 1] * 1.3)
    presence = hmg._smoothstep((energy - 12) / 155)
    gradient = np.where(energy > 12, .12 + .88 * presence, 0)
    opacity = ((1 - strength) + strength * gradient if strength <= 1 else
               np.power(gradient, strength))
    pixels[:, :, 3] *= opacity
    return Image.fromarray(np.clip(pixels, 0, 255).astype(np.uint8), "RGBA")


def clean_shard(part: str, strength: float) -> Image.Image:
    if part not in SOURCE_HASHES:
        raise ValueError("Unknown fire-hit shard")
    return clean_cell(source_shards()[part], strength)


def preview_strip(direction: int, equipment: str, strength: float) -> Image.Image:
    if direction not in range(8):
        raise ValueError("Unknown direction")
    actor = hmg.actor_strip(direction, equipment)
    fire = fire_frames()
    weapon = weapon_frames(equipment)
    strip = Image.new("RGBA", (PREVIEW_CELL[0] * 6, PREVIEW_CELL[1]))
    for frame in range(6):
        cell = Image.new("RGBA", PREVIEW_CELL)
        cell.alpha_composite(actor.crop((frame * 240, 0, (frame + 1) * 240, 224)),
                             ACTOR_OFFSET)
        index = hmg.DIRECTION_ROWS[direction] * 6 + frame
        tip = weapon[index]["weaponTipOffset"]
        ignition = fire[index]["ignitionOffset"]
        offset = (EFFECT_BASE_OFFSET[0] + int(tip[0]) - int(ignition[0]),
                  EFFECT_BASE_OFFSET[1] + int(tip[1]) - int(ignition[1]))
        cell.alpha_composite(clean_cell(source_cell(direction, frame), strength), offset)
        strip.alpha_composite(cell, (frame * PREVIEW_CELL[0], 0))
    return strip


class Workspace(power_editor.Workspace):
    def __init__(self, project_path: Path = PROJECT_PATH):
        self.lock = threading.RLock()
        self.project_path = project_path
        source_shards()
        self.project = (json.loads(project_path.read_text(encoding="utf-8"))
                        if project_path.exists() else
                        {"schema_version": 1, "asset": "fire_hit",
                         "source_sha256": SOURCE_HASHES, "haze_cleanup": 0.0,
                         "revisions": []})
        if (self.project.get("schema_version") != 1 or
                self.project.get("asset") != "fire_hit" or
                self.project.get("source_sha256") != SOURCE_HASHES or
                not isinstance(self.project.get("revisions"), list)):
            raise ValueError("Invalid fire-hit authoring project")
        if not project_path.exists():
            hmg.save_project(self.project, project_path)
        self.revision = 0
        self.cache: dict[tuple, bytes] = {}

    def state(self) -> dict:
        with self.lock:
            return {"revision": self.revision, "haze_cleanup": self.project["haze_cleanup"],
                    "undo_available": bool(self.project["revisions"]),
                    "formal_sha256": {part: hashlib.sha256(
                        (FORMAL_DIR / f"fire_hit_{part}.png").read_bytes()).hexdigest()
                        for part in SOURCE_HASHES}}

    def image(self, direction: int, equipment: str) -> bytes:
        with self.lock:
            key = (self.revision, direction, equipment)
            if key not in self.cache:
                image = preview_strip(direction, equipment, self.project["haze_cleanup"])
                buffer = io.BytesIO()
                image.save(buffer, format="PNG", optimize=False)
                self.cache[key] = buffer.getvalue()
            return self.cache[key]
