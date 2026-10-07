"""Preview transparency cleanup on the primary Magic2.wil lightning frames."""

from __future__ import annotations

import hashlib
import io
import json
import threading
from functools import lru_cache
from pathlib import Path

from PIL import Image

from tools.half_moon_generator import hmg, power_editor
from tools.vendor.extract_wil import decode_sprite, read_library


PROJECT_PATH = hmg.PROJECT_DIR / "lightning_original_project.json"
PRIMARY_WIL = hmg.ROOT / "dev_art_sources/reference/mir2_client_raw/Data/Magic2.wil"
PRIMARY_WIL_SHA256 = "398e5376f19638df063cd6299199bf5c2365fa8525fe0c9e639eb3bb6c955d07"


@lru_cache(maxsize=1)
def primary_library() -> tuple:
    if hashlib.sha256(PRIMARY_WIL.read_bytes()).hexdigest() != PRIMARY_WIL_SHA256:
        raise ValueError("雷电术原始 Magic2.wil 已变化")
    return read_library(PRIMARY_WIL)


@lru_cache(maxsize=1)
def animation() -> dict:
    asset = json.loads((hmg.ROOT / "assets/data/caster_skill_visuals.json")
                       .read_text(encoding="utf-8"))["assets"]["lightning"]
    data = asset["animation"]
    if (data["direction_count"] != 1 or data["frame_count"] != 6 or
            data["frame_time_ms"] != 50 or data["playback"] != "once" or
            len(data["sequences"]) != 1 or len(data["sequences"][0]["frames"]) != 6 or
            asset["source_sha256"] != PRIMARY_WIL_SHA256 or
            asset["render"]["presentation_contract"] != "skills.wizard.lightning.slender_axis.v1" or
            asset["render"]["source_scale_x"] != .62):
        raise ValueError("雷电术 APNG 动画合同发生变化")
    library, palette, offsets, _info = primary_library()
    original_rows = []
    for index in range(6):
        image, sprite = decode_sprite(library, offsets[10 + index], palette)
        original_rows.append({"source_index": 10 + index,
                              "pixel_size": list(image.size),
                              "top_left_from_world_anchor": [sprite["x"] - 32, sprite["y"] - 16]})
    return {**data, "sequences": [{"frames": original_rows}]}


def source_identity() -> str:
    return hashlib.sha256(f"{PRIMARY_WIL_SHA256}:10:6".encode("ascii")).hexdigest()


@lru_cache(maxsize=6)
def source_frame(frame: int) -> Image.Image:
    if frame not in range(6):
        raise ValueError("未知雷电术帧")
    row = animation()["sequences"][0]["frames"][frame]
    data, palette, offsets, _info = primary_library()
    result, sprite = decode_sprite(data, offsets[row["source_index"]], palette)
    if (list(result.size) != row["pixel_size"] or
            [sprite["x"] - 32, sprite["y"] - 16] != row["top_left_from_world_anchor"]):
        raise ValueError(f"雷电术原始帧与 Magic2.wil 不一致: {frame}")
    return result


class Workspace:
    def __init__(self, project_path: Path = PROJECT_PATH):
        self.lock = threading.RLock()
        self.project_path = project_path
        identity = source_identity()
        self.project = (json.loads(project_path.read_text(encoding="utf-8"))
                        if project_path.exists() else
                        {"schema_version": 1, "asset": "lightning", "source_identity": identity,
                         "haze_cleanup": 1.5, "revisions": []})
        if (self.project.get("schema_version") != 1 or
                self.project.get("asset") != "lightning" or
                self.project.get("source_identity") != identity or
                not isinstance(self.project.get("revisions"), list) or
                not 0 <= float(self.project.get("haze_cleanup", -1)) <= 3):
            raise ValueError("雷电术预览工程版本无效")
        if not project_path.exists():
            hmg.save_project(self.project, project_path)
        self.revision = 0
        self.cache: dict[tuple[int, int], bytes] = {}

    def state(self) -> dict:
        with self.lock:
            data = animation()
            return {"revision": self.revision, "haze_cleanup": self.project["haze_cleanup"],
                    "undo_available": bool(self.project["revisions"]),
                    "frame_time_ms": data["frame_time_ms"], "frame_count": 6,
                    "positions": [row["top_left_from_world_anchor"]
                                  for row in data["sequences"][0]["frames"]],
                    "sizes": [row["pixel_size"] for row in data["sequences"][0]["frames"]],
                    "source_identity": self.project["source_identity"]}

    def image(self, frame: int) -> bytes:
        with self.lock:
            key = (self.revision, frame)
            if key not in self.cache:
                image = power_editor.clean_cell(source_frame(frame), self.project["haze_cleanup"])
                stream = io.BytesIO()
                image.save(stream, format="PNG")
                self.cache[key] = stream.getvalue()
            return self.cache[key]

    def action(self, request: dict) -> dict:
        with self.lock:
            if request.get("action") == "tune":
                value = float(request["haze_cleanup"])
                if not 0 <= value <= 3:
                    raise ValueError("雷电术暗部透明化仅允许 0–300%")
                if value != self.project["haze_cleanup"]:
                    self.project["revisions"].append(self.project["haze_cleanup"])
                    self.project["haze_cleanup"] = value
            elif request.get("action") == "undo":
                if not self.project["revisions"]:
                    raise ValueError("没有可撤销的调整")
                self.project["haze_cleanup"] = self.project["revisions"].pop()
            else:
                raise ValueError("未知编辑操作")
            hmg.save_project(self.project, self.project_path)
            self.revision += 1
            self.cache.clear()
            return self.state()
