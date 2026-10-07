"""Isolated original-material preview for the warrior power-hit animation."""

from __future__ import annotations

import hashlib
import io
import json
import threading
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

from tools.half_moon_generator import hmg


SOURCE = Path(__file__).with_name("source") / "power_hit_original.png"
FORMAL = hmg.ROOT / "assets/art/characters/warrior/effects/power_hit.png"
SOURCE_SHA256 = "4300ce585417a5ebfcd3aae77f747e69ce4b878d95ae888f8eb38e056f23a1cb"
APPROVED_STRENGTH = 2.0
APPROVED_SHA256 = "aa1de8bef130f307ad6df12ded3f16e45907aa213bdd2da6de807737baa5b222"
PROJECT_PATH = hmg.PROJECT_DIR / "power_hit_project.json"
SOURCE_CELL = (224, 224)
PREVIEW_OFFSET = (96 - 86, 143 - 130)


def source_atlas() -> Image.Image:
    if hashlib.sha256(SOURCE.read_bytes()).hexdigest() != SOURCE_SHA256:
        raise ValueError("Archived power-hit source identity changed")
    with Image.open(SOURCE) as image:
        if image.size != (1344, 1792) or image.mode != "RGBA":
            raise ValueError("Unexpected power-hit source layout")
        return image.copy()


def clean_cell(cell: Image.Image, strength: float) -> Image.Image:
    if not 0 <= strength <= 3:
        raise ValueError("Dark-haze cleanup must be 0..300%")
    if strength == 0:
        return cell.copy()
    pixels = np.asarray(cell, dtype=np.float32).copy()
    luma = pixels[:, :, :3] @ np.array((.24, .57, .19), dtype=np.float32)
    blur = np.asarray(Image.fromarray(luma.astype(np.uint8)).filter(
        ImageFilter.GaussianBlur(1.5)), dtype=np.float32)
    # The current review keeps all RGB and edge-detail controls at their source values.
    sharpened = np.clip(luma + (luma - blur) * 0, 0, 255)
    presence = hmg._smoothstep((sharpened - 8) / 142)
    gradient = np.where(sharpened > 8, .12 + .88 * presence ** .72, 0)
    opacity = ((1 - strength) + strength * gradient if strength <= 1 else
               np.power(gradient, strength))
    pixels[:, :, 3] *= opacity
    return Image.fromarray(np.clip(pixels, 0, 255).astype(np.uint8), "RGBA")


def clean_atlas(strength: float) -> Image.Image:
    source = source_atlas()
    atlas = Image.new("RGBA", source.size)
    for row in range(8):
        for frame in range(6):
            box = (frame * 224, row * 224, (frame + 1) * 224, (row + 1) * 224)
            atlas.paste(clean_cell(source.crop(box), strength), box)
    return atlas


def preview_strip(direction: int, equipment: str, strength: float) -> Image.Image:
    if direction not in range(8):
        raise ValueError("Unknown direction")
    source = source_atlas()
    actor = hmg.actor_strip(direction, equipment)
    row = hmg.DIRECTION_ROWS[direction]
    for frame in range(6):
        box = (frame * 224, row * 224, (frame + 1) * 224, (row + 1) * 224)
        effect = clean_cell(source.crop(box), strength)
        destination = (frame * 240 + PREVIEW_OFFSET[0], PREVIEW_OFFSET[1])
        actor.alpha_composite(effect, destination)
    return actor


class Workspace:
    def __init__(self, project_path: Path = PROJECT_PATH):
        self.lock = threading.RLock()
        self.project_path = project_path
        self.source = source_atlas()
        self.project = (json.loads(project_path.read_text(encoding="utf-8"))
                        if project_path.exists() else
                        {"schema_version": 1, "asset": "power_hit", "source_sha256": SOURCE_SHA256,
                         "haze_cleanup": APPROVED_STRENGTH, "revisions": []})
        if (self.project.get("schema_version") != 1 or
                self.project.get("asset") != "power_hit" or
                self.project.get("source_sha256") != SOURCE_SHA256 or
                not isinstance(self.project.get("revisions"), list)):
            raise ValueError("Invalid power-hit authoring project")
        if not project_path.exists():
            hmg.save_project(self.project, project_path)
        self.revision = 0
        self.cache: dict[tuple, bytes] = {}

    def state(self) -> dict:
        with self.lock:
            return {"revision": self.revision, "haze_cleanup": self.project["haze_cleanup"],
                    "undo_available": bool(self.project["revisions"]),
                    "formal_sha256": hashlib.sha256(FORMAL.read_bytes()).hexdigest()}

    def image(self, direction: int, equipment: str) -> bytes:
        with self.lock:
            key = (self.revision, direction, equipment)
            if key not in self.cache:
                image = preview_strip(direction, equipment, self.project["haze_cleanup"])
                buffer = io.BytesIO()
                image.save(buffer, format="PNG", optimize=False)
                self.cache[key] = buffer.getvalue()
            return self.cache[key]

    def action(self, request: dict) -> dict:
        with self.lock:
            if request.get("action") == "tune":
                value = float(request["haze_cleanup"])
                if not 0 <= value <= 3:
                    raise ValueError("Dark-haze cleanup must be 0..300%")
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
