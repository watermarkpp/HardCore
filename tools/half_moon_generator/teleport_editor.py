"""Local preview of the primary teleport departure and arrival frames."""

from __future__ import annotations

import hashlib
import io
import json
import threading
from functools import lru_cache
from pathlib import Path

from PIL import Image

from tools.half_moon_generator import fireball_editor, hmg, power_editor
from tools.vendor.extract_wil import decode_sprite


PROJECT_PATH = hmg.PROJECT_DIR / "teleport_project.json"


@lru_cache(maxsize=1)
def frames() -> list[dict]:
    asset = json.loads(fireball_editor.MANIFEST.read_text(encoding="utf-8"))["assets"]["teleport"]
    if asset["source_sha256"] != fireball_editor.PRIMARY_WIL_SHA256:
        raise ValueError("Teleport primary source changed")
    result = []
    for phase, start, attachment in (("departure", 1590, "world_anchor"),
                                     ("arrival", 1600, "caster_actor")):
        data = asset["animation_phases"][phase]
        render = asset["render"] if phase == "departure" else data["render"]
        rows = data["sequences"][0]["frames"]
        if (data["contract"] != "caster_skill_animation.v1" or
                data["phase_id"] != phase or data["direction_count"] != 1 or
                data["frame_count"] != 10 or data["frame_time_ms"] != 30 or
                data["playback"] != "once" or len(data["sequences"]) != 1 or
                len(rows) != 10 or render["scale_mode"] != "source_pixels" or
                render["attachment_policy"] != attachment):
            raise ValueError(f"Teleport {phase} production contract changed")
        for index, row in enumerate(rows):
            expected = ("assets/art/characters/caster_skill_frames/teleport/"
                        f"direction_00/frame_{index:02d}.png" if phase == "departure" else
                        "assets/art/characters/caster_skill_frames/teleport_arrival/"
                        f"direction_00/frame_{index:02d}.png")
            if (row["source_index"] != start + index or row["frame_index"] != index or
                    row["path"] != expected):
                raise ValueError(f"Unexpected Teleport {phase} frame: {index}")
            result.append(row)
    if asset["animation"] != asset["animation_phases"]["departure"]:
        raise ValueError("Teleport departure aliases disagree")
    return result


def source_identity() -> str:
    return hashlib.sha256("\n".join(row.get("original_png_sha256", row["png_sha256"])
                                    for row in frames()).encode("ascii")).hexdigest()


@lru_cache(maxsize=20)
def source_frame(index: int) -> Image.Image:
    if index not in range(20):
        raise ValueError("Unknown Teleport frame")
    row = frames()[index]
    data, palette, offsets, _info = fireball_editor.primary_library()
    source, sprite = decode_sprite(data, offsets[row["source_index"]], palette)
    path = hmg.ROOT / row["path"]
    with Image.open(path) as formal:
        expected = (power_editor.clean_cell(source, 1.0)
                    if "original_png_sha256" in row else source)
        same_pixels = formal.convert("RGBA").tobytes() == expected.tobytes()
    if (hashlib.sha256(path.read_bytes()).hexdigest() != row["png_sha256"] or
            not same_pixels or list(source.size) != row["pixel_size"] or
            [sprite["x"] - 32, sprite["y"] - 16] != row["top_left_from_world_anchor"]):
        raise ValueError(f"Teleport primary frame differs: {index}")
    return source


class Workspace:
    def __init__(self, project_path: Path = PROJECT_PATH):
        self.lock = threading.RLock()
        self.project_path = project_path
        identity = source_identity()
        self.project = (json.loads(project_path.read_text(encoding="utf-8"))
                        if project_path.exists() else
                        {"schema_version": 1, "asset": "teleport", "source_identity": identity,
                         "haze_cleanup": 0.0, "revisions": []})
        if (self.project.get("schema_version") != 1 or self.project.get("asset") != "teleport" or
                self.project.get("source_identity") != identity or
                not isinstance(self.project.get("revisions"), list) or
                not 0 <= float(self.project.get("haze_cleanup", -1)) <= 3):
            raise ValueError("Invalid Teleport preview project")
        if not project_path.exists():
            hmg.save_project(self.project, project_path)
        self.revision = 0
        self.cache: dict[tuple[int, int], bytes] = {}

    def state(self) -> dict:
        with self.lock:
            return {"revision": self.revision, "haze_cleanup": self.project["haze_cleanup"],
                    "undo_available": bool(self.project["revisions"]),
                    "frame_time_ms": 30, "frame_count": 20, "center_rebase": [0, 0],
                    "positions": [row["top_left_from_world_anchor"] for row in frames()],
                    "source_identity": self.project["source_identity"]}

    def image(self, index: int) -> bytes:
        with self.lock:
            key = (self.revision, index)
            if key not in self.cache:
                image = power_editor.clean_cell(source_frame(index), self.project["haze_cleanup"])
                stream = io.BytesIO()
                image.save(stream, format="PNG")
                self.cache[key] = stream.getvalue()
            return self.cache[key]

    def action(self, request: dict) -> dict:
        with self.lock:
            if request.get("action") == "tune":
                value = float(request["haze_cleanup"])
                if not 0 <= value <= 3:
                    raise ValueError("Teleport dark-area cleanup must be 0..300%")
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
