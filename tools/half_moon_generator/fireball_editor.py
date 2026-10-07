"""Read-only-source preview of the production 16-direction fireball animation."""

from __future__ import annotations

import hashlib
import io
import json
import threading
from functools import lru_cache
from pathlib import Path

import numpy as np
from PIL import Image

from tools.half_moon_generator import hmg
from tools.vendor.extract_wil import decode_sprite, read_library


MANIFEST = hmg.ROOT / "assets/data/caster_skill_visuals.json"
PROJECT_PATH = hmg.PROJECT_DIR / "fireball_project.json"
PRIMARY_WIL = hmg.ROOT / "dev_art_sources/reference/mir2_client_raw/Data/Magic.wil"
PRIMARY_WIL_SHA256 = "be46a0258349b26db9ba7dba595abac1f0767d52fef11d9f508e704f2f6deaac"


def png_bytes(image: Image.Image) -> bytes:
    stream = io.BytesIO()
    image.save(stream, format="PNG")
    return stream.getvalue()


@lru_cache(maxsize=1)
def animation() -> dict:
    asset = json.loads(MANIFEST.read_text(encoding="utf-8"))["assets"]["fireball"]
    result = asset["animation"]
    if (result["contract"] != "caster_skill_animation.v1" or
            result["direction_count"] != 16 or result["frame_count"] != 6 or
            len(result["sequences"]) != 16 or
            asset["render"]["scale_mode"] != "fit_extent" or
            asset["render"]["fit_extent"] != 34.0):
        raise ValueError("Fireball production animation contract changed")
    for direction, sequence in enumerate(result["sequences"]):
        if sequence["direction_index"] != direction or len(sequence["frames"]) != 6:
            raise ValueError("Fireball direction or frame ordering changed")
        for frame, row in enumerate(sequence["frames"]):
            expected = (f"assets/art/characters/caster_skill_frames/fireball/"
                        f"direction_{direction:02d}/frame_{frame:02d}.png")
            if (row["frame_index"] != frame or row["path"] != expected or
                    row["source_index"] != 10 + direction * 10 + frame):
                raise ValueError("Unexpected fireball frame source")
    return result


def source_identity() -> str:
    hashes = [row.get("original_png_sha256", row["png_sha256"])
              for sequence in animation()["sequences"]
              for row in sequence["frames"]]
    return hashlib.sha256("\n".join(hashes).encode("ascii")).hexdigest()


@lru_cache(maxsize=1)
def primary_library() -> tuple:
    if hashlib.sha256(PRIMARY_WIL.read_bytes()).hexdigest() != PRIMARY_WIL_SHA256:
        raise ValueError("Primary Magic.wil identity changed")
    return read_library(PRIMARY_WIL)


@lru_cache(maxsize=96)
def source_frame(direction: int, frame: int) -> Image.Image:
    if direction not in range(16) or frame not in range(6):
        raise ValueError("Unknown fireball direction or frame")
    row = animation()["sequences"][direction]["frames"][frame]
    data, palette, offsets, _info = primary_library()
    source, sprite = decode_sprite(data, offsets[row["source_index"]], palette)
    if (source.mode != "RGBA" or list(source.size) != row["pixel_size"] or
            [sprite["x"] - 32, sprite["y"] - 16] != row["top_left_from_world_anchor"]):
        raise ValueError(f"Unexpected primary fireball layout: {direction}/{frame}")
    # The primary WIL hash and source slot identify the pixels. PNG encoder
    # bytes vary across supported Pillow versions, even for identical pixels.
    return source


def clean_frame(source: Image.Image, strength: float) -> Image.Image:
    if not 0 <= strength <= 3:
        raise ValueError("Fireball dark-area cleanup must be 0..300%")
    if strength == 0:
        return source.copy()
    pixels = np.asarray(source, dtype=np.float32).copy()
    energy = np.maximum(pixels[:, :, 0] * .9, pixels[:, :, 1] * 1.3)
    presence = hmg._smoothstep((energy - 12) / 155)
    gradient = np.where(energy > 12, .12 + .88 * presence, 0)
    opacity = ((1 - strength) + strength * gradient if strength <= 1 else
               np.power(gradient, strength))
    pixels[:, :, 3] *= opacity
    return Image.fromarray(np.clip(pixels, 0, 255).astype(np.uint8), "RGBA")


class Workspace:
    def __init__(self, project_path: Path = PROJECT_PATH):
        self.lock = threading.RLock()
        self.project_path = project_path
        identity = source_identity()
        self.project = (json.loads(project_path.read_text(encoding="utf-8"))
                        if project_path.exists() else
                        {"schema_version": 1, "asset": "fireball",
                         "source_identity": identity, "haze_cleanup": 0.0,
                         "revisions": []})
        if (self.project.get("schema_version") != 1 or
                self.project.get("asset") != "fireball" or
                self.project.get("source_identity") != identity or
                not isinstance(self.project.get("revisions"), list) or
                not 0 <= float(self.project.get("haze_cleanup", -1)) <= 3):
            raise ValueError("Invalid fireball preview project")
        if not project_path.exists():
            hmg.save_project(self.project, project_path)
        self.revision = 0
        self.cache: dict[tuple, bytes] = {}

    def state(self) -> dict:
        with self.lock:
            data = animation()
            return {"revision": self.revision,
                    "haze_cleanup": self.project["haze_cleanup"],
                    "undo_available": bool(self.project["revisions"]),
                    "frame_time_ms": data["frame_time_ms"],
                    "fit_extent": 34,
                    "native_extent": max(data["native_extent"]),
                    "positions": [[row["top_left_from_world_anchor"]
                                   for row in seq["frames"]]
                                  for seq in data["sequences"]],
                    "source_identity": self.project["source_identity"]}

    def image(self, direction: int, frame: int) -> bytes:
        with self.lock:
            key = (self.revision, direction, frame)
            if key not in self.cache:
                result = clean_frame(source_frame(direction, frame),
                                     self.project["haze_cleanup"])
                stream = io.BytesIO()
                result.save(stream, format="PNG", optimize=False)
                self.cache[key] = stream.getvalue()
            return self.cache[key]

    def action(self, request: dict) -> dict:
        with self.lock:
            if request.get("action") == "tune":
                value = float(request["haze_cleanup"])
                if not 0 <= value <= 3:
                    raise ValueError("Fireball dark-area cleanup must be 0..300%")
                if value != self.project["haze_cleanup"]:
                    self.project["revisions"].append(self.project["haze_cleanup"])
                    self.project["haze_cleanup"] = value
            elif request.get("action") == "undo":
                if not self.project["revisions"]:
                    raise ValueError("No previous edit")
                self.project["haze_cleanup"] = self.project["revisions"].pop()
            else:
                raise ValueError("Unknown action")
            hmg.save_project(self.project, self.project_path)
            self.revision += 1
            self.cache.clear()
            return self.state()
