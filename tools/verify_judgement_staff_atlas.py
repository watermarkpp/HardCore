#!/usr/bin/env python3
"""Verify the judgement-staff atlases pixel-for-pixel against Weapon.wil."""

from __future__ import annotations

import json
import sys
from pathlib import Path

from PIL import Image, ImageChops


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools/vendor"))
from extract_wil import decode_sprite, read_library  # noqa: E402


ACTIONS = {
    "idle": (0, 4),
    "walk": (64, 6),
    "attack": (200, 6),
    "hit": (472, 3),
    "death": (536, 4),
}
# Classic Weapon.wil Shape 24, male appearance feature = Shape * 2.
FEATURE = 48


def main() -> int:
    library = ROOT / "dev_art_sources/reference/mir2_client_raw/Data/Weapon.wil"
    manifest_path = ROOT / "assets/data/warrior_wear_sources.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    mapping = manifest["runtimeMappings"]["裁决之杖"]["weaponAppearance"]
    assert mapping["feature"] == FEATURE and mapping["visible"] is True
    data, palette, offsets, _info = read_library(library)

    for action, (start, frame_count) in ACTIONS.items():
        action_info = mapping["actions"][action]
        cell = tuple(action_info["cell"])
        foot_anchor = tuple(action_info["footAnchor"])
        expected = Image.new("RGBA", (cell[0] * frame_count, cell[1] * 8), (0, 0, 0, 0))
        expected_indices = []
        for direction in range(8):
            for frame in range(frame_count):
                index = FEATURE * 600 + start + direction * 8 + frame
                sprite, meta = decode_sprite(data, offsets[index], palette)
                paste = (
                    frame * cell[0] + foot_anchor[0] + meta["x"],
                    direction * cell[1] + foot_anchor[1] + meta["y"],
                )
                expected.alpha_composite(sprite.convert("RGBA"), paste)
                expected_indices.append(index)
        actual_indices = [record["index"] for record in action_info["sourceFrames"]]
        assert actual_indices == expected_indices, f"{action}: source-frame order differs"
        actual = Image.open(ROOT / action_info["path"].removeprefix("res://")).convert("RGBA")
        assert ImageChops.difference(actual, expected).getbbox() is None, f"{action}: atlas pixels differ"
        northwest = actual.crop((0, cell[1] * 7, actual.width, cell[1] * 8))
        assert northwest.getbbox() is not None, f"{action}: NW/left-up row is empty"

    print("JUDGEMENT_STAFF_ATLAS_PASS: 5 actions, 8 directions, NW row and source pixels verified")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
