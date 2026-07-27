#!/usr/bin/env python3
"""Validate the male world-helmet extension, atlases and runtime mapping."""

from __future__ import annotations

import hashlib
import json
import math
import sys
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
RECIPES = ROOT / "assets/data/equipment_male_world_helmet_recipes.json"
CONTRACT = ROOT / "assets/data/equipment_male_world_helmet.json"
CATALOG = ROOT / "assets/data/equipment_visual_catalog.json"
BUILDER = ROOT / "tools/build_male_world_helmet_assets.py"
HAIR = ROOT / "dev_art_sources/external/mir2opensource_full/Data/Hair.wil"

CONTRACT_ID = "equipment.world_helmet.male.extension.v1"
DIRECTIONS = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
CELL = (192, 160)
FOOT_ANCHOR = [64, 80]
HAIR_APPEARANCE = 2
HAIR_STRIDE = 2224
ACTIONS = {
    "idle": {"start": 0, "frames": 4},
    "walk": {"start": 64, "frames": 6},
    "attack": {"start": 200, "frames": 6},
    "cast": {"start": 392, "frames": 6},
    "hit": {"start": 472, "frames": 3},
    "death": {"start": 536, "frames": 4},
}
ITEMS = {
    146: ("精灵头盔", 105, "elf"),
    147: ("青铜头盔", 100, "bronze_magic"),
    148: ("魔法头盔", 100, "bronze_magic"),
    149: ("道士头盔", 106, "taoist"),
    150: ("骷髅头盔", 103, "skeleton"),
    151: ("黑铁头盔", 344, "black_iron"),
    218: ("神秘头盔", 111, "mystery"),
    224: ("祈祷头盔", 110, "prayer"),
    228: ("记忆头盔", 109, "memory"),
    232: ("圣战头盔", 104, "holy_war"),
    236: ("法神头盔", 101, "god_magic"),
    240: ("天尊头盔", 102, "heavenly_taoist"),
}
GROUP_B_SOURCE_ORDER = ["N", "NW", "W", "E", "S", "SW", "SE", "NE"]
GROUP_B_CANONICAL_SLOTS = [0, 7, 3, 6, 4, 5, 2, 1]
PRESERVED_BLACK_IRON_FILE_SHA256 = {
    "idle": "8a78c841d88b47946ef6f559f731cbbe9c08313e11c7ef48e5457d12d839e052",
    "walk": "8b32472b1dd8ebe2723b34cb1fd2d5d73d151891c7372dfc4f93a4f5d3ceb4a6",
    "attack": "427855f0a799fd8cc442071255861e6a22456532facb3801e9774c4236f069ca",
    "hit": "605d12ebd303bbc9be5ee3da645145ad53f9077d28e0fff83ac5d95970575cf7",
    "death": "f99492398eadb01b1b7e50f1f7c5bb347b42994054a165e3318922fd5599beec",
}
BRONZE_APPROVED_OTHER_DIRECTION_RGBA_SHA256 = {
    "NE": "38621221e718547c422368f91b57e5ad677a6a4f0901a0d323d43c319a70aaf8",
    "E": "b9666e04f14e81a30b5366762dc8106ca7e112ca19575476eb5e8061e6be2274",
    "SE": "96ab5a43913c731603d540996891ca873ef2d41231496aa4891231593e7f6525",
    "S": "2577794ac10fb80703901371bc65706a5d0f92accffbbc1d0ec00e367031b260",
    "SW": "38ae1aa08459f79666e237551dc548ab46dd1e58c33c00addc7e6d11ccaa410c",
    "W": "51ae88f12bc2edf18d9a30bd9d670ce212bb8ced8f329b27f009f5fb09abe0b1",
    "NW": "51b1f4abe51bab89060ca2a882546c515d3e8ed31f8beb8671487f46d554d249",
}

sys.path.insert(0, str(ROOT / "tools/vendor"))
from extract_wil import decode_sprite, read_library  # noqa: E402


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def disk_path(value: str) -> Path:
    assert value.startswith("res://")
    return ROOT / value.removeprefix("res://")


def file_sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rgba_sha256(image: Image.Image) -> str:
    return hashlib.sha256(image.convert("RGBA").tobytes()).hexdigest()


def cropped_visible(image: Image.Image) -> Image.Image:
    rgba = image.convert("RGBA")
    box = rgba.getchannel("A").getbbox()
    assert box is not None
    return rgba.crop(box)


def assert_ascii_schema_keys(value: object, location: str = "$") -> None:
    if isinstance(value, dict):
        for key, child in value.items():
            assert str(key).isascii(), (
                f"non-ASCII schema key at {location}: {key!r}"
            )
            assert_ascii_schema_keys(child, f"{location}.{key}")
    elif isinstance(value, list):
        for index, child in enumerate(value):
            assert_ascii_schema_keys(child, f"{location}[{index}]")


def main() -> None:
    recipes = load_json(RECIPES)
    contract = load_json(CONTRACT)
    catalog = load_json(CATALOG)
    builder_source = BUILDER.read_text(encoding="utf-8")
    assert_ascii_schema_keys(recipes)
    assert_ascii_schema_keys(contract)

    assert recipes["contractId"] == CONTRACT_ID
    assert recipes["sex"] == "male"
    assert recipes["sourcePolicy"]["stateItemPixelsUsed"] is False
    assert recipes["sourcePolicy"]["hairPixelsUsed"] is False
    assert recipes["sourcePolicy"]["femaleExcluded"] is True
    assert recipes["actorContract"]["cell"] == list(CELL)
    assert recipes["actorContract"]["footAnchor"] == FOOT_ANCHOR
    assert recipes["actorContract"]["directions"] == DIRECTIONS
    assert recipes["actorContract"]["actions"] == ACTIONS
    assert "sourceSlotDirectionOrder" in builder_source
    assert "canonicalRowSourceSlots" in builder_source
    assert "zip(DIRECTIONS" not in builder_source
    assert "assets/art/items/client/equipped" not in builder_source

    recipe_identities = {
        recipe["identityId"]: recipe for recipe in recipes["identities"]
    }
    assert len(recipe_identities) == 11
    for identity_id, recipe in recipe_identities.items():
        assert recipe["directionClassificationStatus"] == (
            "accepted_manual_visual_classification"
        )
        assert recipe["directionClassificationEvidence"]
        assert math.prod(recipe["sourceGrid"]) == 8
        source_order = recipe["sourceSlotDirectionOrder"]
        canonical_slots = recipe["canonicalRowSourceSlots"]
        assert len(source_order) == 8
        assert sorted(source_order) == sorted(DIRECTIONS)
        assert canonical_slots == [
            source_order.index(direction) for direction in DIRECTIONS
        ]
        assert sorted(canonical_slots) == list(range(8))
        assert disk_path(recipe["concept"]).exists()
    taoist_diameter_policy = recipe_identities["taoist"][
        "angleAwareHorizontalDiameter"
    ]
    assert taoist_diameter_policy == {
        "lateralDiameterPercent": 90,
        "depthDiameterPercent": 90,
        "depthToWidthRatio": 1.0,
        "heightPercent": 100,
        "filter": "nearest",
        "pivotPolicy": "direction_frame_head_pivot_preserved",
    }
    skeleton_body_policy = recipe_identities["skeleton"][
        "bodyDrivenSizing"
    ]
    assert recipe_identities["skeleton"]["despillGreenCutouts"] is True
    assert skeleton_body_policy == {
        "method": "central_column_density",
        "columnDensityThresholdPercent": 30,
        "maximumColumnGapPercent": 4,
        "horizontalPaddingPercent": 2.5,
        "minimumBodyWidthFraction": 0.35,
        "maximumBodyWidthFraction": 0.65,
        "scaleBasis": "main_helmet_body_only",
        "excludedAccessory": "two_long_lateral_horns",
        "preserveAccessoryToBodyRatio": True,
        "fullBoundsMayExceedClientEnvelope": True,
        "sharedBodyTargetHeightPixels": 18,
        "uniformEditorScaleAcrossDirections": True,
        "filter": "lanczos_downsample_then_nearest_runtime",
    }
    for identity_id in (
        "prayer",
        "memory",
        "holy_war",
        "god_magic",
        "heavenly_taoist",
    ):
        assert (
            recipe_identities[identity_id]["sourceSlotDirectionOrder"]
            == GROUP_B_SOURCE_ORDER
        )
        assert (
            recipe_identities[identity_id]["canonicalRowSourceSlots"]
            == GROUP_B_CANONICAL_SLOTS
        )

    assert contract["contractId"] == CONTRACT_ID
    assert contract["sex"] == "male"
    assert contract["actorContract"]["cell"] == list(CELL)
    assert contract["actorContract"]["footAnchor"] == FOOT_ANCHOR
    assert contract["actorContract"]["directions"] == DIRECTIONS
    assert contract["actorContract"]["actions"] == ACTIONS
    assert contract["actorContract"]["footPointContractChanged"] is False
    assert contract["sourcePolicy"]["stateItemPixelsUsed"] is False
    assert contract["sourcePolicy"]["hairPixelsUsed"] is False
    assert contract["sourcePolicy"]["femaleExcluded"] is True
    assert contract["sourcePolicy"]["actionFallbacks"] == {}
    assert contract["coverage"] == {
        "formalHelmetItems": 12,
        "visualIdentities": 11,
        "actionsPerIdentity": 6,
        "directionsPerAction": 8,
        "physicalAtlasCells": 2552,
        "logicalItemCells": 2784,
        "missingFrames": 0,
        "maleItems": 12,
        "femaleItems": 0,
        "acceptedBlackIronAtlasesPreserved": 5,
    }
    assert (
        contract["acceptedBlackIronAtlasFileSha256"]
        == PRESERVED_BLACK_IRON_FILE_SHA256
    )

    items = contract["itemsById"]
    runtime_by_item_id = contract["runtimeMappingsByItemId"]
    assert {int(item_id) for item_id in items} == set(ITEMS)
    assert set(runtime_by_item_id) == set(items)
    catalog_runtime = catalog["runtimeMappings"]
    catalog_items = catalog["itemsById"]
    for item_id, (name, source_index, identity_id) in ITEMS.items():
        item_key = str(item_id)
        item = items[item_key]
        assert item["itemId"] == item_id
        assert item["itemName"] == name
        assert item["sourceIndex"] == source_index
        assert item["identityId"] == identity_id
        assert item["sex"] == "male"
        assert item["slot"] == "helmet"
        assert item["status"] == "approved_project_extension"
        assert item["identityEvidence"]["sourceIndex"] == source_index
        assert item["identityEvidence"]["stateItemPixelsUsed"] is False
        appearance = item["maleAppearance"]
        assert appearance["sex"] == "male"
        assert appearance["visible"] is True
        assert set(appearance["actions"]) == set(ACTIONS)
        assert appearance["actionFallbacks"] == {}
        assert (
            runtime_by_item_id[item_key]["helmetAppearance"]
            == appearance
        )
        catalog_item = catalog_items[item_key]
        assert catalog_item["paperDoll"]["sourceIndex"] == source_index
        assert catalog_item["worldWear"]["contractId"] == CONTRACT_ID
        assert catalog_item["worldWear"]["identityId"] == identity_id
        assert (
            catalog_item["worldWear"]["helmetAppearance"] == appearance
        )
        assert (
            catalog_runtime[name]["helmetAppearance"] == appearance
        )
    assert items["147"]["maleAppearance"] == items["148"]["maleAppearance"]

    hair_data, hair_palette, hair_offsets, _hair_info = read_library(HAIR)
    hair_hashes: dict[int, str] = {}
    stateitem_visible_by_identity: dict[str, Image.Image] = {}
    for _item_id, (_name, source_index, identity_id) in ITEMS.items():
        if identity_id in stateitem_visible_by_identity:
            continue
        stateitem_visible_by_identity[identity_id] = cropped_visible(
            Image.open(
                ROOT
                / "assets/art/items/client/equipped"
                / f"{source_index}.png"
            )
        )

    identities = contract["visualIdentities"]
    assert set(identities) == set(recipe_identities)
    physical_paths: set[str] = set()
    total_physical_cells = 0
    for identity_id, identity in identities.items():
        assert identity["sex"] == "male"
        assert identity["stateItemPixelsUsed"] is False
        assert identity["hairPixelsUsed"] is False
        assert file_sha256(disk_path(identity["concept"])) == (
            identity["conceptFileSha256"]
        )
        source_order = identity["sourceSlotDirectionOrder"]
        canonical_slots = identity["canonicalRowSourceSlots"]
        assert source_order == (
            recipe_identities[identity_id]["sourceSlotDirectionOrder"]
        )
        assert canonical_slots == [
            source_order.index(direction) for direction in DIRECTIONS
        ]
        acceptance = identity["directionAcceptance"]
        acceptance_path = disk_path(acceptance["path"])
        assert acceptance_path.exists()
        assert file_sha256(acceptance_path) == acceptance["fileSha256"]
        assert acceptance["sourceSlotDirectionOrder"] == source_order
        assert acceptance["canonicalRowSourceSlots"] == canonical_slots
        assert acceptance["classificationStatus"] == (
            "accepted_manual_visual_classification"
        )
        assert acceptance["classificationEvidence"]

        cutouts = identity["directionCutouts"]
        assert set(cutouts) == set(DIRECTIONS)
        assert len(
            {
                record["sourceCutoutRgbaSha256"]
                for record in cutouts.values()
            }
        ) == 8
        assert len(
            {
                record["generatedRgbaSha256"]
                for record in cutouts.values()
            }
        ) == 8
        stateitem = stateitem_visible_by_identity[identity_id]
        assert all(
            record["sourceCutoutRgbaSha256"] != rgba_sha256(stateitem)
            for record in cutouts.values()
        )

        assert set(identity["actions"]) == set(ACTIONS)
        for action_name, spec in ACTIONS.items():
            action = identity["actions"][action_name]
            path = disk_path(action["path"])
            physical_paths.add(action["path"])
            atlas = Image.open(path).convert("RGBA")
            assert atlas.size == (
                CELL[0] * spec["frames"],
                CELL[1] * 8,
            )
            assert file_sha256(path) == action["fileSha256"]
            assert rgba_sha256(atlas) == action["atlasRgbaSha256"]
            assert action["cell"] == list(CELL)
            assert action["footAnchor"] == FOOT_ANCHOR
            assert action["directions"] == 8
            assert action["framesPerDirection"] == spec["frames"]
            assert action["physicalCellCount"] == 8 * spec["frames"]
            assert action["missingFrames"] == []
            assert action["confidence"] == "project_approved_exact"
            total_physical_cells += action["physicalCellCount"]
            records = action["frames"]
            assert len(records) == 8 * spec["frames"]
            coordinates = {
                (int(record["directionRow"]), int(record["frame"]))
                for record in records
            }
            assert coordinates == {
                (direction, frame)
                for direction in range(8)
                for frame in range(spec["frames"])
            }
            row_signatures: set[str] = set()
            for direction in range(8):
                row_signatures.add(
                    rgba_sha256(
                        atlas.crop(
                            (
                                0,
                                direction * CELL[1],
                                atlas.width,
                                (direction + 1) * CELL[1],
                            )
                        )
                    )
                )
            assert len(row_signatures) == 8

            for record in records:
                direction = int(record["directionRow"])
                frame = int(record["frame"])
                assert record["direction"] == DIRECTIONS[direction]
                assert record["stateItemPixelsUsed"] is False
                assert record["hairPixelsUsed"] is False
                assert not record["pixelSource"].endswith(
                    f"/equipped/{identity['sourceIndex']}.png"
                )
                expected_hair_index = (
                    HAIR_APPEARANCE * HAIR_STRIDE
                    + spec["start"]
                    + direction * 8
                    + frame
                )
                hair_frame = record["hairFrame"]
                assert hair_frame["sourceIndex"] == expected_hair_index
                if expected_hair_index not in hair_hashes:
                    decoded, _meta = decode_sprite(
                        hair_data,
                        hair_offsets[expected_hair_index],
                        hair_palette,
                    )
                    hair_hashes[expected_hair_index] = rgba_sha256(
                        decoded.convert("RGBA")
                    )
                assert (
                    hair_frame["sourceRgbaSha256"]
                    == hair_hashes[expected_hair_index]
                )
                assert float(record["headDistancePixels"]) <= 10.0
                assert math.dist(
                    [
                        float(value)
                        for value in record["helmetAnchorCentroid"]
                    ],
                    [
                        float(value)
                        for value in record["hairAnchorCentroid"]
                    ],
                ) <= 10.0001
                paste = [int(value) for value in record["paste"]]
                size = [int(value) for value in record["generatedSize"]]
                anchor = [
                    round(float(value))
                    for value in record["helmetAnchorCentroid"]
                ]
                assert abs(paste[0] + size[0] // 2 - anchor[0]) <= 1
                assert abs(paste[1] + size[1] // 2 - anchor[1]) <= 1
                assert paste[0] >= 0 and paste[1] >= 0
                assert paste[0] + size[0] <= CELL[0]
                assert paste[1] + size[1] <= CELL[1]
                cell = atlas.crop(
                    (
                        frame * CELL[0],
                        direction * CELL[1],
                        (frame + 1) * CELL[0],
                        (direction + 1) * CELL[1],
                    )
                )
                assert cell.getchannel("A").getbbox() is not None
                assert rgba_sha256(cell) == record["cellRgbaSha256"]
                assert all(
                    cell.getpixel(point)[3] == 0
                    for point in (
                        (0, 0),
                        (CELL[0] - 1, 0),
                        (0, CELL[1] - 1),
                        (CELL[0] - 1, CELL[1] - 1),
                    )
                )
                cell_bytes = cell.tobytes()
                assert all(
                    not (
                        cell_bytes[offset] == 0
                        and cell_bytes[offset + 1] == 255
                        and cell_bytes[offset + 2] == 0
                        and cell_bytes[offset + 3] > 0
                    )
                    for offset in range(0, len(cell_bytes), 4)
                )
                visible = cropped_visible(cell)
                assert not (
                    visible.size == stateitem.size
                    and visible.tobytes() == stateitem.tobytes()
                ), (
                    f"{identity_id} {action_name} d{direction} f{frame} "
                    "reuses the StateItem rectangle"
                )

    assert len(physical_paths) == 66
    assert total_physical_cells == 2552
    bronze_idle = Image.open(
        disk_path(identities["bronze_magic"]["actions"]["idle"]["path"])
    ).convert("RGBA")
    bronze_cutouts = identities["bronze_magic"]["directionCutouts"]
    assert all(
        record["calibrationBaseScalePercent"] == 83
        for record in bronze_cutouts.values()
    )
    assert bronze_cutouts["N"]["calibrationDirectionScalePercent"] == 100
    assert bronze_cutouts["N"]["generatedSize"] == [10, 16]
    assert bronze_cutouts["N"]["preparedPixelPolicy"] == (
        "concept_direct_resize"
    )
    assert all(
        bronze_cutouts[direction]["calibrationDirectionScalePercent"] == 83
        for direction in BRONZE_APPROVED_OTHER_DIRECTION_RGBA_SHA256
    )
    assert {
        direction: bronze_cutouts[direction]["generatedRgbaSha256"]
        for direction in BRONZE_APPROVED_OTHER_DIRECTION_RGBA_SHA256
    } == BRONZE_APPROVED_OTHER_DIRECTION_RGBA_SHA256
    assert min(
        record["generatedSize"][1] for record in bronze_cutouts.values()
    ) >= 13
    assert all(
        record["generatedSize"][1] <= 18
        for record in bronze_cutouts.values()
    )
    assert bronze_cutouts["S"]["generatedSize"][0] >= 8
    assert identities["bronze_magic"]["calibrationPreparedSourceRows"] == []
    assert identities["bronze_magic"]["calibrationSourceSheet"].endswith(
        "bronze_magic_helmet_8dir_transparent.png"
    )
    assert identities["bronze_magic"]["calibrationSourceMatte"] == (
        "transparent_user_approved_despill_v1"
    )
    assert identities["bronze_magic"]["calibrationResizeFilter"] == (
        "lanczos_downsample_nearest_runtime_v1"
    )
    bronze_front = cropped_visible(
        bronze_idle.crop((0, 4 * CELL[1], CELL[0], 5 * CELL[1]))
    )
    bronze_rear = cropped_visible(
        bronze_idle.crop((0, 0, CELL[0], CELL[1]))
    )
    face_x = bronze_front.width // 2
    face_y = bronze_front.height - 3
    assert bronze_front.getpixel((face_x, face_y))[3] == 0
    assert bronze_front.getpixel((face_x - 3, face_y))[3] > 0
    assert bronze_front.getpixel((face_x + 3, face_y))[3] > 0
    assert bronze_rear.getpixel(
        (bronze_rear.width // 2, bronze_rear.height - 3)
    )[3] > 0
    taoist_cutouts = identities["taoist"]["directionCutouts"]
    taoist_yaw = {
        "N": 180.0,
        "NE": 135.0,
        "E": 90.0,
        "SE": 45.0,
        "S": 0.0,
        "SW": -45.0,
        "W": -90.0,
        "NW": -135.0,
    }
    for direction, expected_yaw in taoist_yaw.items():
        record = taoist_cutouts[direction]
        projection = record["angleAwareHorizontalDiameter"]
        assert projection["yawDegrees"] == expected_yaw
        assert projection["lateralDiameterPercent"] == 90.0
        assert projection["depthDiameterPercent"] == 90.0
        assert projection["projectedHorizontalPercent"] == 90.0
        assert projection["heightPercent"] == 100
        assert projection["filter"] == "nearest"
        assert projection["pivotPolicy"] == (
            "direction_frame_head_pivot_preserved"
        )
        assert projection["postProjectionSize"][0] < (
            projection["preProjectionSize"][0]
        )
        assert projection["postProjectionSize"][1] == (
            projection["preProjectionSize"][1]
        )
        assert record["generatedSize"] == projection["postProjectionSize"]
        assert record["preparedPixelPolicy"].endswith(
            "_angle_aware_diameter_projection"
        )
    skeleton_cutouts = identities["skeleton"]["directionCutouts"]
    skeleton_body_heights = []
    for direction in DIRECTIONS:
        record = skeleton_cutouts[direction]
        sizing = record["bodyDrivenSizing"]
        assert sizing["enabled"] is True
        assert sizing["clientEnvelopeAppliedTo"] == (
            "main_helmet_body_only"
        )
        assert sizing["excludedAccessory"] == (
            "two_long_lateral_horns"
        )
        assert sizing["hornsExcludedFromScaleCalculation"] is True
        assert sizing["fullBoundsMayExceedClientEnvelope"] is True
        assert sizing["sharedBodyTargetHeightPixels"] == 18
        assert sizing["uniformEditorScaleAcrossDirections"] is True
        skeleton_body_heights.append(sizing["generatedBodySize"][1])
        assert sizing["fullGeneratedSize"] == record["generatedSize"]
        assert record["preparedPixelPolicy"] == (
            "concept_body_driven_resize_horns_excluded_v1"
            "_source_green_despill"
        )
    assert set(skeleton_body_heights) == {18}
    assert all(
        skeleton_cutouts[direction]["generatedSize"][0]
        > skeleton_cutouts[direction]["bodyDrivenSizing"][
            "generatedBodySize"
        ][0]
        for direction in DIRECTIONS
    )
    assert any(
        skeleton_cutouts[direction]["generatedSize"][0]
        > skeleton_cutouts[direction]["calibrationEnvelope"][0]
        for direction in DIRECTIONS
    )
    black_actions = identities["black_iron"]["actions"]
    assert black_actions["cast"]["atlasRgbaSha256"] != (
        black_actions["idle"]["atlasRgbaSha256"]
    )
    assert "/black_iron_helmet_cast.png" in black_actions["cast"]["path"]
    assert all(
        black_actions[action]["fileSha256"]
        == PRESERVED_BLACK_IRON_FILE_SHA256[action]
        for action in PRESERVED_BLACK_IRON_FILE_SHA256
    )

    assert catalog["coverage"]["exactMaleWorldWear"] == 60
    assert catalog["coverage"]["exactFemaleWorldWear"] == 12
    print(
        "EQUIPMENT_MALE_WORLD_HELMET_TEST_PASS "
        "items=12 identities=11 physical_atlases=66 "
        "physical_cells=2552 logical_cells=2784 "
        "actions=6 directions=8 stateitem_world_pixels=0 female=0"
    )


if __name__ == "__main__":
    main()
