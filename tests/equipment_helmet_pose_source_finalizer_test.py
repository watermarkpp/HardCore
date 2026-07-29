#!/usr/bin/env python3
"""Verify independent per-pose source selection without touching real drafts."""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "tools/finalize_helmet_calibrations.py"
SPEC = importlib.util.spec_from_file_location("helmet_finalizer", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
FINALIZER = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = FINALIZER
SPEC.loader.exec_module(FINALIZER)


def verify() -> None:
    directions = {
        direction: {
            "source_row": index,
            "scale_percent": 60,
        }
        for index, direction in enumerate(FINALIZER.DIRECTIONS)
    }
    draft = {
        "directions": directions,
        "poseTransforms": {
            "hit": {
                "S": {
                    "0": {
                        "source_row": 4,
                        "offset": [1.0, -0.5],
                        "scale_x_percent": 55,
                        "scale_y_percent": 60,
                        "rotation_degrees": -5.0,
                    }
                },
                "W": {
                    "0": {
                        "source_row": 4,
                        "offset": [-3.0, 2.5],
                        "scale_x_percent": 65,
                        "scale_y_percent": 50,
                        "rotation_degrees": 10.0,
                    }
                },
            }
        },
    }
    south = FINALIZER.resolved_pose_transform(draft, "hit", "S", 0)
    west = FINALIZER.resolved_pose_transform(draft, "hit", "W", 0)
    assert south["source_row"] == west["source_row"] == 4
    assert south["offset"] != west["offset"]
    assert south["scale_x_percent"] != west["scale_x_percent"]
    assert south["rotation_degrees"] != west["rotation_degrees"]

    source = Image.new("RGBA", (160, 220), (0, 0, 0, 0))
    draw = ImageDraw.Draw(source)
    draw.polygon(
        [(80, 4), (150, 180), (80, 216), (10, 180)],
        fill=(230, 180, 40, 255),
    )
    south_cell = FINALIZER.premultiplied_affine_to_cell(
        source,
        (24, 33),
        south["rotation_degrees"],
        (96.0 + south["offset"][0], 58.0 + south["offset"][1]),
    )
    west_cell = FINALIZER.premultiplied_affine_to_cell(
        source,
        (29, 28),
        west["rotation_degrees"],
        (96.0 + west["offset"][0], 58.0 + west["offset"][1]),
    )
    assert south_cell.getchannel("A").getbbox() is not None
    assert west_cell.getchannel("A").getbbox() is not None
    assert south_cell.tobytes() != west_cell.tobytes()


if __name__ == "__main__":
    verify()
    print(
        "EQUIPMENT_HELMET_POSE_SOURCE_FINALIZER_PASS "
        "shared_source=true independent_transform=true single_pass_affine=true"
    )
