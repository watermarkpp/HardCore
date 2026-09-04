#!/usr/bin/env python3
"""Validate transparent player-facing paper-doll presentation modes."""

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "assets/data/equipment_paper_doll_presentation_modes.json"
VISUAL = ROOT / "assets/data/equipment_visual_catalog.json"
HEAD_PATCHES = ROOT / "assets/data/equipment_classic_avatar_head_patches.json"


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def disk_path(resource_path: str) -> Path:
    assert resource_path.startswith("res://")
    return ROOT / resource_path.removeprefix("res://")


def image(resource_path: str) -> Image.Image:
    return Image.open(disk_path(resource_path)).convert("RGBA")


def assert_transparent_corners(value: Image.Image, label: str) -> None:
    corners = [
        value.getpixel((0, 0))[3],
        value.getpixel((value.width - 1, 0))[3],
        value.getpixel((0, value.height - 1))[3],
        value.getpixel((value.width - 1, value.height - 1))[3],
    ]
    assert corners == [0, 0, 0, 0], f"{label} has opaque outer corners"
    assert value.getbbox() is not None, f"{label} is empty"


def male_appearance(mapping: dict) -> dict:
    for appearance in mapping.values():
        if isinstance(appearance, dict) and appearance.get("gender") == "男":
            return appearance
    raise AssertionError("male appearance missing")


def layer_image(record: dict, action: str = "idle") -> Image.Image:
    return image(record["actions"][action]["path"])


def alpha_composite_at(
    target: Image.Image,
    source: Image.Image,
    position: list[int] | tuple[int, int],
) -> None:
    target.alpha_composite(source, (int(position[0]), int(position[1])))


def world_frame(record: dict, direction: int, frame: int) -> Image.Image:
    action = record["actions"]["idle"]
    atlas = image(action["path"])
    cell_width, cell_height = [int(value) for value in action["cell"]]
    return atlas.crop((
        frame * cell_width,
        direction * cell_height,
        (frame + 1) * cell_width,
        (direction + 1) * cell_height,
    ))


def main() -> None:
    manifest = load_json(MANIFEST)
    visual = load_json(VISUAL)
    head_patches = load_json(HEAD_PATCHES)
    assert manifest["contractId"] == "equipment.paper_doll.presentation_modes.v1"
    assert manifest["defaultMode"] == "world_avatar"
    assert manifest["sex"] == "male"
    assert manifest["sourcePolicy"]["fallbackUsed"] is False

    modes = manifest["modes"]
    assert set(modes) == {"world_avatar", "classic_avatar"}
    world = modes["world_avatar"]
    classic = modes["classic_avatar"]["avatarOnly"]
    assert world["contractId"] == "equipment.paper_doll.world_avatar.v1"
    assert classic["contractId"] == "equipment.paper_doll.avatar_only.v1"
    assert world["drawOrder"] == ["base", "dress", "weapon", "helmet"]
    assert classic["drawOrder"] == [
        "base",
        "dress",
        "weapon",
        "flattenedHeadPatch",
    ]
    assert classic["headPatchSelector"].endswith(
        "equipment_classic_avatar_head_patches.json#/"
        "itemsById/{itemId}/flattenedHeadPatch"
    )

    legacy = manifest["legacyFullPanel"]
    assert legacy["forbiddenForPlayerUI"] is True
    assert legacy["containsBackground"] is True
    assert legacy["containsEquipmentSlotFrames"] is True

    base = image(classic["base"]["path"])
    assert base.size == tuple(classic["canvasSize"])
    assert_transparent_corners(base, "classic anatomy")
    for x, y, width, height in classic["slotExclusionRects"]:
        alpha = base.getchannel("A").crop((x, y, x + width, y + height))
        assert alpha.getbbox() is None, (
            f"classic anatomy retained full-panel slot pixels at {x},{y}"
        )
    hair = image(classic["hair"]["path"])
    assert hair.getchannel("A").getextrema() == (0, 255)

    loadouts = visual["loadoutVisualContracts"]
    assert sorted(loadouts) == manifest["validation"]["loadoutContractIds"]
    categories = {"衣服": "dress", "武器": "weapon", "头盔": "helmet"}
    for loadout_id, loadout in loadouts.items():
        profession_id = loadout_id.split(".")[2]
        profession = visual["professionManifests"][profession_id]
        base_appearance = male_appearance(profession["worldBaseByGender"])
        classic_composite = Image.new("RGBA", tuple(classic["canvasSize"]))
        alpha_composite_at(classic_composite, base, [0, 0])
        world_composite = Image.new("RGBA", tuple(world["canvasSize"]))
        selected_world: dict[str, dict] = {"base": base_appearance}
        selected_classic: dict[str, dict] = {}
        selected_head_patch: dict = {}
        for slot, layer_name in categories.items():
            item_id = str(loadout["visualSlots"][slot]["itemId"])
            item = visual["itemsById"][item_id]
            paper = item["paperDoll"]
            if layer_name == "helmet":
                selected_head_patch = head_patches["itemsById"][item_id][
                    "flattenedHeadPatch"
                ]
            else:
                selected_classic[layer_name] = paper
            world_wear = item["worldWear"]
            if layer_name == "helmet":
                appearance = world_wear["helmetAppearance"]
            else:
                appearance = male_appearance(
                    world_wear["appearancesByGender"]
                )
            selected_world[layer_name] = appearance

        for layer_name in ("dress", "weapon"):
            paper = selected_classic[layer_name]
            alpha_composite_at(
                classic_composite,
                image(paper["path"]),
                paper["drawOffset"],
            )
        alpha_composite_at(
            classic_composite,
            image(selected_head_patch["path"]),
            selected_head_patch["drawOffset"],
        )
        assert_transparent_corners(
            classic_composite, f"{loadout_id} classic composite"
        )

        # A world dress is a complete Hum frame and replaces the naked base.
        # The remaining world layers retain the runtime front-facing order.
        direction = int(world["frameSelection"]["directionIndex"])
        frame = int(world["frameSelection"]["frame"])
        for layer_name in ("dress", "weapon", "helmet"):
            appearance = selected_world[layer_name]
            alpha_composite_at(
                world_composite,
                world_frame(appearance, direction, frame),
                world["layerLayouts"][layer_name]["stagePosition"],
            )
        assert_transparent_corners(
            world_composite, f"{loadout_id} world composite"
        )

    assert manifest["validation"]["femaleAssetsGenerated"] == 0
    print(
        "EQUIPMENT_PAPER_DOLL_PRESENTATION_MODES_TEST_PASS "
        "modes=2 loadouts=9 legacy_forbidden=true"
    )


if __name__ == "__main__":
    main()
