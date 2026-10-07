"""Primary Magic.wil preview of the six-frame Hellfire trail decoration."""

from __future__ import annotations

import hashlib
import io
import json
import math
import threading
from functools import lru_cache
from pathlib import Path

from PIL import Image

from tools.half_moon_generator import fireball_editor, hmg
from tools.vendor.extract_wil import decode_sprite


PROJECT_PATH = hmg.PROJECT_DIR / "hellfire_project.json"


@lru_cache(maxsize=1)
def animation() -> dict:
    asset = json.loads(fireball_editor.MANIFEST.read_text(encoding="utf-8"))["assets"]["hellfire"]
    data = asset["animation"]
    render = asset["render"]
    if (asset["source_sha256"] != fireball_editor.PRIMARY_WIL_SHA256 or
            data["contract"] != "caster_skill_animation.v1" or
            data["direction_count"] != 1 or data["frame_count"] != 6 or
            data["frame_time_ms"] != 50 or data["playback"] != "once" or
            len(data["sequences"]) != 1 or len(data["sequences"][0]["frames"]) != 6 or
            render["scale_mode"] != "source_pixels" or
            render["playback_strategy"] != "firegun_trail" or
            render["trajectory_step_ms"] != 50 or
            render["trail_frame_count"] != 6 or
            render["trail_emission_policy"] != "resample_to_canonical_geometry_endpoint"):
        raise ValueError("Hellfire production animation contract changed")
    for frame, row in enumerate(data["sequences"][0]["frames"]):
        expected = ("assets/art/characters/caster_skill_frames/hellfire/"
                    f"direction_00/frame_{frame:02d}.png")
        if (row["frame_index"] != frame or row["source_index"] != 930 + frame or
                row["path"] != expected):
            raise ValueError(f"Unexpected Hellfire source frame: {frame}")
    return {"animation": data, "render": render}


def source_identity() -> str:
    rows = animation()["animation"]["sequences"][0]["frames"]
    return hashlib.sha256("\n".join(row.get("original_png_sha256", row["png_sha256"])
                                    for row in rows).encode("ascii")).hexdigest()


@lru_cache(maxsize=6)
def source_frame(frame: int) -> Image.Image:
    if frame not in range(6):
        raise ValueError("Unknown Hellfire frame")
    row = animation()["animation"]["sequences"][0]["frames"][frame]
    library, palette, offsets, _info = fireball_editor.primary_library()
    source, sprite = decode_sprite(library, offsets[row["source_index"]], palette)
    path = hmg.ROOT / row["path"]
    if hashlib.sha256(path.read_bytes()).hexdigest() != row["png_sha256"]:
        raise ValueError(f"Hellfire formal frame hash differs: {frame}")
    with Image.open(path) as formal:
        formal_rgba = formal.convert("RGBA")
        expected = (fireball_editor.clean_frame(source, 1.5)
                    if "original_png_sha256" in row else source)
        formal_match = (formal_rgba.size == expected.size and
                        formal_rgba.tobytes() == expected.tobytes())
    if (not formal_match or list(source.size) != row["pixel_size"] or
            [sprite["x"] - 32, sprite["y"] - 16] != row["top_left_from_world_anchor"]):
        raise ValueError(f"Hellfire original frame layout differs: {frame}")
    return source


def sequence_center() -> list[float]:
    rows = animation()["animation"]["sequences"][0]["frames"]
    left = min(row["top_left_from_world_anchor"][0] for row in rows)
    top = min(row["top_left_from_world_anchor"][1] for row in rows)
    right = max(row["top_left_from_world_anchor"][0] + row["pixel_size"][0] for row in rows)
    bottom = max(row["top_left_from_world_anchor"][1] + row["pixel_size"][1] for row in rows)
    return [(left + right) / 2, (top + bottom) / 2]


def emission_count(endpoint: tuple[float, float]) -> int:
    render = animation()["render"]
    step = render["trajectory_dominant_axis_pixels_per_second"] * render["trajectory_step_ms"] / 1000
    dominant = max(abs(endpoint[0]), abs(endpoint[1]))
    return max(1, math.ceil(dominant / step))


class Workspace:
    def __init__(self, project_path: Path = PROJECT_PATH):
        self.lock = threading.RLock()
        self.project_path = project_path
        identity = source_identity()
        self.project = (json.loads(project_path.read_text(encoding="utf-8"))
                        if project_path.exists() else
                        {"schema_version": 1, "asset": "hellfire", "source_identity": identity,
                         "haze_cleanup": 1.0, "revisions": []})
        if (self.project.get("schema_version") != 1 or self.project.get("asset") != "hellfire" or
                self.project.get("source_identity") != identity or
                not isinstance(self.project.get("revisions"), list) or
                not 0 <= float(self.project.get("haze_cleanup", -1)) <= 3):
            raise ValueError("Invalid Hellfire preview project")
        if not project_path.exists():
            hmg.save_project(self.project, project_path)
        self.revision = 0
        self.cache: dict[tuple[int, int], bytes] = {}

    def state(self) -> dict:
        with self.lock:
            profile = animation()
            rows = profile["animation"]["sequences"][0]["frames"]
            return {"revision": self.revision, "haze_cleanup": self.project["haze_cleanup"],
                    "undo_available": bool(self.project["revisions"]),
                    "frame_time_ms": profile["animation"]["frame_time_ms"],
                    "frame_count": 6, "positions": [row["top_left_from_world_anchor"] for row in rows],
                    "sequence_center": sequence_center(),
                    "emission_count": emission_count((160, 80)),
                    "source_identity": self.project["source_identity"]}

    def image(self, frame: int) -> bytes:
        with self.lock:
            key = (self.revision, frame)
            if key not in self.cache:
                image = fireball_editor.clean_frame(source_frame(frame), self.project["haze_cleanup"])
                buffer = io.BytesIO()
                image.save(buffer, format="PNG")
                self.cache[key] = buffer.getvalue()
            return self.cache[key]

    def action(self, request: dict) -> dict:
        with self.lock:
            if request.get("action") == "tune":
                value = float(request["haze_cleanup"])
                if not 0 <= value <= 3:
                    raise ValueError("Hellfire cleanup must be 0..300%")
                if value != self.project["haze_cleanup"]:
                    self.project["revisions"].append(self.project["haze_cleanup"])
                    self.project["haze_cleanup"] = value
            elif request.get("action") == "undo":
                if not self.project["revisions"]:
                    raise ValueError("No previous edit")
                self.project["haze_cleanup"] = self.project["revisions"].pop()
            else:
                raise ValueError("Unknown Hellfire action")
            hmg.save_project(self.project, self.project_path)
            self.revision += 1
            self.cache.clear()
            return self.state()
