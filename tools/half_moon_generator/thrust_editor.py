"""Separate eight-direction preview of the original warrior long-hit animation."""

from __future__ import annotations

import hashlib
import io
import json
import threading
from pathlib import Path

from PIL import Image

from tools.half_moon_generator import hmg, power_editor


SOURCE = Path(__file__).with_name("source") / "long_hit_original.png"
FORMAL = hmg.ROOT / "assets/art/characters/warrior/effects/long_hit.png"
SOURCE_SHA256 = "97e558356f1d4c7bbc8c63a7ef1dedb7f7f397fa7e8385075cda72169fe864c3"
APPROVED_STRENGTH = 1.5
APPROVED_SHA256 = "b638235af9cc2bcf7cd6097b5934907e21bdaf7684e1b3e0ed4433f52ec563ec"
PROJECT_PATH = hmg.PROJECT_DIR / "long_hit_project.json"
SOURCE_CELL = (288, 224)
PREVIEW_CELL = (320, 240)
ACTOR_OFFSET = (32, 8)
EFFECT_OFFSET = (ACTOR_OFFSET[0] + 96 - 119, ACTOR_OFFSET[1] + 143 - 144)


def source_atlas() -> Image.Image:
    if hashlib.sha256(SOURCE.read_bytes()).hexdigest() != SOURCE_SHA256:
        raise ValueError("Archived long-hit source identity changed")
    with Image.open(SOURCE) as image:
        if image.size != (1728, 1792) or image.mode != "RGBA":
            raise ValueError("Unexpected long-hit source layout")
        return image.copy()


def clean_atlas(strength: float) -> Image.Image:
    source = source_atlas()
    atlas = Image.new("RGBA", source.size)
    for row in range(8):
        for frame in range(6):
            box = (frame * 288, row * 224, (frame + 1) * 288, (row + 1) * 224)
            atlas.paste(power_editor.clean_cell(source.crop(box), strength), box)
    return atlas


def preview_strip(direction: int, equipment: str, strength: float) -> Image.Image:
    if direction not in range(8):
        raise ValueError("Unknown direction")
    source = source_atlas()
    actor = hmg.actor_strip(direction, equipment)
    row = hmg.DIRECTION_ROWS[direction]
    strip = Image.new("RGBA", (PREVIEW_CELL[0] * 6, PREVIEW_CELL[1]))
    for frame in range(6):
        cell = Image.new("RGBA", PREVIEW_CELL)
        cell.alpha_composite(actor.crop((frame * 240, 0, (frame + 1) * 240, 224)),
                             ACTOR_OFFSET)
        box = (frame * 288, row * 224, (frame + 1) * 288, (row + 1) * 224)
        cell.alpha_composite(power_editor.clean_cell(source.crop(box), strength), EFFECT_OFFSET)
        strip.alpha_composite(cell, (frame * PREVIEW_CELL[0], 0))
    return strip


class Workspace(power_editor.Workspace):
    def __init__(self, project_path: Path = PROJECT_PATH):
        self.lock = threading.RLock()
        self.project_path = project_path
        source_atlas()
        self.project = (json.loads(project_path.read_text(encoding="utf-8"))
                        if project_path.exists() else
                        {"schema_version": 1, "asset": "long_hit", "source_sha256": SOURCE_SHA256,
                         "haze_cleanup": 0.0, "revisions": []})
        if (self.project.get("schema_version") != 1 or
                self.project.get("asset") != "long_hit" or
                self.project.get("source_sha256") != SOURCE_SHA256 or
                not isinstance(self.project.get("revisions"), list)):
            raise ValueError("Invalid long-hit authoring project")
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
