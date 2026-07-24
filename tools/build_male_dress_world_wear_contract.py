#!/usr/bin/env python3
"""Build the source-audited male Hum.wil dress world-wear contract."""

from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
HUM = ROOT / "dev_art_sources/reference/mir2_client_raw/Data/Hum.wil"
VISUAL_CATALOG = ROOT / "assets/data/equipment_visual_catalog.json"
OUTPUT = ROOT / "assets/data/equipment_male_dress_world_wear.json"

CONTRACT_ID = "equipment.world_wear.male_dress.v1"
MALE_ARMOR_IDS = (116, 118, 120, 122, 128, 140, 124, 130, 142, 126, 132, 144)
USER_CONFIRMED_ITEM_IDS = {128}
CELL = (192, 160)
ACTOR_ORIGIN = (64, 80)
BLOCK_FRAMES = 600
ACTIONS = {
    "idle": {"start": 0, "frames": 4},
    "walk": {"start": 64, "frames": 6},
    "attack": {"start": 200, "frames": 6},
    "cast": {"start": 392, "frames": 6},
    "hit": {"start": 472, "frames": 3},
    "death": {"start": 536, "frames": 4},
}

sys.path.insert(0, str(ROOT / "tools/vendor"))
from extract_wil import decode_sprite, read_library  # noqa: E402


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def disk_path(resource_path: str) -> Path:
    if not resource_path.startswith("res://"):
        raise ValueError(f"not a project resource: {resource_path}")
    return ROOT / resource_path.removeprefix("res://")


def image_sha256(image: Image.Image) -> str:
    return hashlib.sha256(image.convert("RGBA").tobytes()).hexdigest()


def feature_action_path(feature: int, action: str) -> str:
    return (
        "res://assets/art/items/client/world_wear/dress/male/"
        f"dress_{feature:03d}_{action}.png"
    )


def decode_feature_action(
    feature: int,
    action: str,
    library: tuple,
) -> dict:
    data, palette, offsets, info = library
    spec = ACTIONS[action]
    frame_count = int(spec["frames"])
    atlas = Image.new(
        "RGBA",
        (CELL[0] * frame_count, CELL[1] * 8),
        (0, 0, 0, 0),
    )
    source_frames: list[dict] = []
    transparent_empty_frames: list[int] = []
    for direction in range(8):
        for frame in range(frame_count):
            within_block = int(spec["start"]) + direction * 8 + frame
            source_index = feature * BLOCK_FRAMES + within_block
            if source_index >= len(offsets):
                raise RuntimeError(
                    f"Hum feature {feature} {action} source {source_index} "
                    "exceeds library"
                )
            image, metadata = decode_sprite(
                data,
                offsets[source_index],
                palette,
            )
            image = image.convert("RGBA")
            hot = [int(metadata["x"]), int(metadata["y"])]
            local_x = ACTOR_ORIGIN[0] + hot[0]
            local_y = ACTOR_ORIGIN[1] + hot[1]
            if (
                local_x < 0
                or local_y < 0
                or local_x + image.width > CELL[0]
                or local_y + image.height > CELL[1]
            ):
                raise RuntimeError(
                    f"Hum feature {feature} {action} d{direction} f{frame} "
                    f"does not fit cell {CELL} at actor origin {ACTOR_ORIGIN}: "
                    f"hot={hot} size={image.size}"
                )
            opaque_pixels = sum(
                alpha != 0 for alpha in image.getchannel("A").tobytes()
            )
            if opaque_pixels == 0:
                transparent_empty_frames.append(source_index)
            atlas.alpha_composite(
                image,
                (frame * CELL[0] + local_x, direction * CELL[1] + local_y),
            )
            source_frames.append({
                "sourceIndex": source_index,
                "direction": direction,
                "frame": frame,
                "hot": hot,
                "sourceSize": [image.width, image.height],
                "opaquePixelCount": opaque_pixels,
                "transparentEmpty": opaque_pixels == 0,
                "rgbaSha256": image_sha256(image),
            })

    path = feature_action_path(feature, action)
    target = disk_path(path)
    if not target.exists():
        raise FileNotFoundError(f"missing existing male dress atlas: {target}")
    exported = Image.open(target).convert("RGBA")
    if exported.size != atlas.size or exported.tobytes() != atlas.tobytes():
        raise AssertionError(
            f"{path} is not an exact actor-origin/Hot reconstruction of Hum.wil"
        )
    return {
        "path": path,
        "cell": list(CELL),
        "actorOrigin": list(ACTOR_ORIGIN),
        "directions": 8,
        "framesPerDirection": frame_count,
        "sourceFeature": feature,
        "decodedFrameCount": len(source_frames),
        "missingFrames": [],
        "transparentEmptyFrames": transparent_empty_frames,
        "pixelActionConfidence": "A",
        "atlasRgbaSha256": image_sha256(exported),
        "sourceFrames": source_frames,
        "libraryImageCount": int(info["image_count"]),
    }


def build_feature_family(feature: int, library: tuple) -> dict:
    return {
        "feature": feature,
        "source": "Hum.wil",
        "sex": "male",
        "cell": list(CELL),
        "actorOrigin": list(ACTOR_ORIGIN),
        "actions": {
            action: decode_feature_action(feature, action, library)
            for action in ACTIONS
        },
    }


def main() -> None:
    for source in (HUM, VISUAL_CATALOG):
        if not source.exists():
            raise FileNotFoundError(f"missing male dress input: {source}")

    catalog = load_json(VISUAL_CATALOG)
    entries = catalog.get("itemsById", {})
    runtime_mappings = catalog.get("runtimeMappings", {})
    selected: list[tuple[int, dict, dict, dict]] = []
    for item_id in MALE_ARMOR_IDS:
        entry = entries.get(str(item_id), {})
        if not entry:
            raise ValueError(f"male armor item_id {item_id} missing from catalog")
        name = str(entry.get("itemName", ""))
        world = entry.get("worldWear", {})
        runtime = runtime_mappings.get(name, {}).get("dressAppearance", {})
        if world.get("status") != "exact_client_animation" or not runtime:
            raise ValueError(f"{item_id} {name} lacks runtime dressAppearance")
        feature = int(runtime.get("feature", -1))
        shape = int(runtime.get("shape", -1))
        if feature != shape * 2 or feature % 2 != 0:
            raise ValueError(
                f"{item_id} {name} violates male feature=Shape*2: "
                f"shape={shape} feature={feature}"
            )
        evidence = world.get("shapeEvidence", {})
        if str(evidence.get("confidence", "")) != "B":
            raise ValueError(
                f"{item_id} {name} name mapping must remain B-grade evidence"
            )
        selected.append((item_id, entry, runtime, evidence))

    feature_ids = sorted({0, *(int(row[2]["feature"]) for row in selected)})
    if feature_ids != list(range(0, 18, 2)):
        raise AssertionError(
            f"expected nine male Hum feature families 0..16, got {feature_ids}"
        )
    library = read_library(HUM)
    feature_families = {
        str(feature): build_feature_family(feature, library)
        for feature in feature_ids
    }

    items_by_id: dict[str, dict] = {}
    runtime_by_item_id: dict[str, dict] = {}
    for item_id, entry, runtime, evidence in selected:
        shape = int(runtime["shape"])
        feature = int(runtime["feature"])
        mapping_confidence = (
            "manually_confirmed"
            if item_id in USER_CONFIRMED_ITEM_IDS
            else "B"
        )
        mapping_source = (
            "user-confirmed accepted male Battle God armor appearance"
            if item_id in USER_CONFIRMED_ITEM_IDS
            else str(evidence.get("source", ""))
        )
        action_refs = {
            action: {
                "featureActionRef": (
                    f"featureFamilies.{feature}.actions.{action}"
                ),
                "path": feature_families[str(feature)]["actions"][action]["path"],
                "framesPerDirection": int(ACTIONS[action]["frames"]),
            }
            for action in ACTIONS
        }
        male_appearance = {
            "sex": "male",
            "shape": shape,
            "feature": feature,
            "featureRef": f"featureFamilies.{feature}",
            "visible": True,
            "actions": action_refs,
            "actionFallbacks": {},
        }
        item_record = {
            "itemId": item_id,
            "itemName": str(entry.get("itemName", "")),
            "profession": str(entry.get("profession", "")),
            "slot": "dress",
            "sex": "male",
            "mappingAssessment": {
                "confidence": mapping_confidence,
                "source": mapping_source,
                "rule": "male feature = dress Shape * 2",
                "pixelAndActionConfidence": "A",
            },
            "maleAppearance": male_appearance,
        }
        items_by_id[str(item_id)] = item_record
        runtime_by_item_id[str(item_id)] = {
            "dressAppearance": male_appearance
        }

    _data, _palette, _offsets, library_info = library
    payload = {
        "schemaVersion": 1,
        "contractId": CONTRACT_ID,
        "sex": "male",
        "source": {
            "library": "Hum.wil",
            "path": (
                "dev_art_sources/reference/mir2_client_raw/Data/Hum.wil"
            ),
            "imageCount": int(library_info["image_count"]),
            "blockFrames": BLOCK_FRAMES,
        },
        "actorContract": {
            "contractId": "player.visual.classic_eight_direction.v1",
            "cell": list(CELL),
            "actorOrigin": list(ACTOR_ORIGIN),
            "placementRule": (
                "frame local position = actorOrigin + original Hum HotX/HotY"
            ),
            "directions": 8,
            "actions": ACTIONS,
            "footPointContractChanged": False,
        },
        "mappingPolicy": {
            "pixelAndActionCompleteness": "A",
            "itemNameToShape": (
                "B unless an item explicitly records manually_confirmed"
            ),
            "femaleExcluded": True,
            "transparentEmptyFramePolicy": (
                "retain the source frame as transparent; never synthesize pixels"
            ),
        },
        "coverage": {
            "maleArmorItems": len(items_by_id),
            "expectedMaleArmorItems": 12,
            "maleHumFeatureFamiliesIncludingBase": len(feature_families),
            "dressedFeatureFamilies": len(feature_families) - 1,
            "actionsPerFeature": len(ACTIONS),
            "directionsPerAction": 8,
            "missingFrames": 0,
            "femaleItems": 0,
        },
        "featureFamilies": feature_families,
        "itemsById": items_by_id,
        "runtimeMappingsByItemId": runtime_by_item_id,
    }
    OUTPUT.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(
        "EQUIPMENT_MALE_DRESS_WORLD_WEAR_PASS "
        f"items={len(items_by_id)} features={len(feature_families)} "
        "actions=6 directions=8 missing=0"
    )


if __name__ == "__main__":
    main()
