#!/usr/bin/env python3
"""Build the source-audited male Weapon.wil world-wear contract."""

from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
WEAPON = ROOT / "dev_art_sources/reference/mir2_client_raw/Data/Weapon.wil"
VISUAL_CATALOG = ROOT / "assets/data/equipment_visual_catalog.json"
COMPATIBILITY = (
    ROOT / "assets/data/equipment_primary_weapon_compatibility.json"
)
ATLAS_ROOT = ROOT / "assets/art/items/client/world_wear/weapon/male"
OUTPUT = ROOT / "assets/data/equipment_male_weapon_world_wear.json"

CONTRACT_ID = "equipment.world_wear.male_weapon.v1"
HIDDEN_ITEM_IDS: set[int] = set()
UNRESOLVED_ITEM_IDS = {110, 111}
INTEGRATION_SHARED_PRIMARY_ITEM_IDS = {88}
USER_CONFIRMED_CLASS_ITEM_IDS = {99, 105, 107, 108}
CELL = (224, 224)
ACTOR_ORIGIN = (80, 116)
FOOT_POINT = ACTOR_ORIGIN
BLOCK_FRAMES = 600
ACTIONS = {
    "idle": {"start": 0, "frames": 4},
    "walk": {"start": 64, "frames": 6},
    "attack": {"start": 200, "frames": 6},
    "cast": {"start": 392, "frames": 6},
    "hit": {"start": 472, "frames": 3},
    "death": {"start": 536, "frames": 4},
}
SOURCE_FRAME_ENCODING = (
    "sourceIndex|direction|frame|hotX|hotY|width|height|"
    "sourceOpaquePixelCount|transparentEmpty(0/1)|sourceRgbaSha256"
)
CLASSIC_EMPTY_MARKER_SIZE = (4, 1)
CLASSIC_EMPTY_MARKER_HOT = (7, -44)
CLASSIC_EMPTY_MARKER_RGBA_SHA256 = (
    "68b642431daaf03078c0214c0c2feb9b6d38e4fffa73a84769f2b49b18731c82"
)

sys.path.insert(0, str(ROOT / "tools/vendor"))
from extract_wil import decode_sprite, read_library  # noqa: E402


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def resource_path(path: Path) -> str:
    return f"res://{path.relative_to(ROOT).as_posix()}"


def rgba_sha256(image: Image.Image) -> str:
    return hashlib.sha256(image.convert("RGBA").tobytes()).hexdigest()


def packed_source_frame(
    source_index: int,
    direction: int,
    frame: int,
    hot_x: int,
    hot_y: int,
    image: Image.Image,
    source_opaque_pixels: int,
    transparent_empty: bool,
) -> str:
    return "|".join([
        str(source_index),
        str(direction),
        str(frame),
        str(hot_x),
        str(hot_y),
        str(image.width),
        str(image.height),
        str(source_opaque_pixels),
        "1" if transparent_empty else "0",
        rgba_sha256(image),
    ])


def is_classic_transparent_empty(
    feature: int,
    hot_x: int,
    hot_y: int,
    image: Image.Image,
) -> bool:
    return (
        feature == 0
        and image.size == CLASSIC_EMPTY_MARKER_SIZE
        and (hot_x, hot_y) == CLASSIC_EMPTY_MARKER_HOT
        and rgba_sha256(image) == CLASSIC_EMPTY_MARKER_RGBA_SHA256
    )


def build_feature_action(feature: int, action: str, library: tuple) -> dict:
    data, palette, offsets, info = library
    spec = ACTIONS[action]
    frame_count = int(spec["frames"])
    atlas = Image.new(
        "RGBA",
        (CELL[0] * frame_count, CELL[1] * 8),
        (0, 0, 0, 0),
    )
    packed_frames: list[str] = []
    transparent_empty_frames: list[int] = []
    for direction in range(8):
        for frame in range(frame_count):
            source_index = (
                feature * BLOCK_FRAMES
                + int(spec["start"])
                + direction * 8
                + frame
            )
            if source_index >= len(offsets):
                raise RuntimeError(
                    f"Weapon feature {feature} {action} source "
                    f"{source_index} exceeds library"
                )
            image, metadata = decode_sprite(
                data,
                offsets[source_index],
                palette,
            )
            image = image.convert("RGBA")
            hot_x = int(metadata["x"])
            hot_y = int(metadata["y"])
            local_x = ACTOR_ORIGIN[0] + hot_x
            local_y = ACTOR_ORIGIN[1] + hot_y
            if (
                local_x < 0
                or local_y < 0
                or local_x + image.width > CELL[0]
                or local_y + image.height > CELL[1]
            ):
                raise RuntimeError(
                    f"Weapon feature {feature} {action} d{direction} f{frame} "
                    f"does not fit cell {CELL} at actor origin {ACTOR_ORIGIN}: "
                    f"hot=({hot_x},{hot_y}) size={image.size}"
                )
            source_opaque_pixels = sum(
                alpha != 0 for alpha in image.getchannel("A").tobytes()
            )
            transparent_empty = is_classic_transparent_empty(
                feature,
                hot_x,
                hot_y,
                image,
            )
            if transparent_empty:
                transparent_empty_frames.append(source_index)
            rendered = (
                Image.new("RGBA", image.size, (0, 0, 0, 0))
                if transparent_empty
                else image
            )
            # Feature 0 uses the classic 4x1 no-weapon marker. Its output is
            # an empty cell; no previous frame is ever copied or synthesized.
            atlas.alpha_composite(
                rendered,
                (
                    frame * CELL[0] + local_x,
                    direction * CELL[1] + local_y,
                ),
            )
            packed_frames.append(packed_source_frame(
                source_index,
                direction,
                frame,
                hot_x,
                hot_y,
                image,
                source_opaque_pixels,
                transparent_empty,
            ))

    target = ATLAS_ROOT / f"weapon_{feature:03d}_{action}.png"
    if target.exists():
        exported = Image.open(target).convert("RGBA")
        if exported.size != atlas.size or exported.tobytes() != atlas.tobytes():
            legacy_opaque_pixels = sum(
                alpha != 0 for alpha in exported.getchannel("A").tobytes()
            )
            if (
                feature != 0
                or legacy_opaque_pixels != frame_count * 8
                or atlas.getbbox() is not None
            ):
                raise AssertionError(
                    f"{target} differs from its complete Weapon.wil frames"
                )
            # Upgrade only the previously exported feature-0 marker atlas.
            atlas.save(target, format="PNG", optimize=False)
            exported = Image.open(target).convert("RGBA")
    else:
        target.parent.mkdir(parents=True, exist_ok=True)
        atlas.save(target, format="PNG", optimize=False)
        exported = Image.open(target).convert("RGBA")
    return {
        "path": resource_path(target),
        "cell": list(CELL),
        "actorOrigin": list(ACTOR_ORIGIN),
        "footPoint": list(FOOT_POINT),
        "directions": 8,
        "framesPerDirection": frame_count,
        "sourceFeature": feature,
        "decodedFrameCount": len(packed_frames),
        "missingFrames": [],
        "transparentEmptyFrames": transparent_empty_frames,
        "transparentFramePolicy": (
            "classic feature-0 4x1 marker is an empty no-weapon frame; "
            "never copy or synthesize prior frames"
        ),
        "pixelActionConfidence": "A",
        "atlasRgbaSha256": rgba_sha256(exported),
        "sourceFrameEncoding": SOURCE_FRAME_ENCODING,
        "sourceFramesPacked": packed_frames,
        "libraryImageCount": int(info["image_count"]),
    }


def build_feature_family(feature: int, library: tuple) -> dict:
    return {
        "feature": feature,
        "source": "Weapon.wil",
        "sex": "male",
        "cell": list(CELL),
        "actorOrigin": list(ACTOR_ORIGIN),
        "footPoint": list(FOOT_POINT),
        "actions": {
            action: build_feature_action(feature, action, library)
            for action in ACTIONS
        },
    }


def main() -> None:
    for source in (WEAPON, VISUAL_CATALOG, COMPATIBILITY):
        if not source.exists():
            raise FileNotFoundError(f"missing male weapon input: {source}")

    catalog = load_json(VISUAL_CATALOG)
    compatibility = load_json(COMPATIBILITY)
    if compatibility.get("contractId") != (
        "equipment.weapon_compatibility.primary.v1"
    ):
        raise AssertionError("primary weapon compatibility contract changed")
    compatibility_items = compatibility.get("itemsById", {})
    if len(compatibility_items) != 37:
        raise AssertionError("primary weapon compatibility must cover 37 items")
    entries = catalog.get("itemsById", {})
    runtime_mappings = catalog.get("runtimeMappings", {})
    formal_weapons: list[tuple[int, dict]] = sorted(
        (
            (int(item_key), item)
            for item_key, item in entries.items()
            if item.get("category") == "武器"
        ),
        key=lambda row: row[0],
    )
    if len(formal_weapons) != 37:
        raise AssertionError(f"expected 37 formal weapons, got {len(formal_weapons)}")

    classified = {"visible": [], "hidden_by_classic_rule": [], "unresolved": []}
    for item_id, entry in formal_weapons:
        status = str(entry.get("worldWear", {}).get("status", ""))
        if status == "exact_client_animation":
            classified["visible"].append(item_id)
        elif status == "classic_client_hidden_weapon":
            classified["hidden_by_classic_rule"].append(item_id)
        elif status == "unresolved_no_placeholder":
            classified["unresolved"].append(item_id)
        else:
            raise AssertionError(
                f"unexpected world weapon status for {item_id}: {status}"
            )
    if len(classified["visible"]) != 35:
        raise AssertionError("visible primary weapon count must be 35")
    if set(classified["hidden_by_classic_rule"]) != HIDDEN_ITEM_IDS:
        raise AssertionError("classic hidden weapon set changed")
    if set(classified["unresolved"]) != UNRESOLVED_ITEM_IDS:
        raise AssertionError("unresolved weapon set changed")

    library = read_library(WEAPON)
    _data, _palette, offsets, library_info = library
    feature_count = len(offsets) // BLOCK_FRAMES
    if feature_count != 68:
        raise AssertionError(f"expected 68 Weapon features, got {feature_count}")
    male_features = list(range(0, feature_count, 2))
    if len(male_features) != 34:
        raise AssertionError("Weapon.wil must expose 34 male feature families")
    feature_families = {
        str(feature): build_feature_family(feature, library)
        for feature in male_features
    }

    items_by_id: dict[str, dict] = {}
    runtime_by_item_id: dict[str, dict] = {}
    for item_id, entry in formal_weapons:
        name = str(entry.get("itemName", ""))
        world = entry.get("worldWear", {})
        evidence = world.get("shapeEvidence", {})
        compatibility_record = compatibility_items.get(str(item_id), {})
        if (
            int(compatibility_record.get("itemId", -1)) != item_id
            or str(compatibility_record.get("itemName", "")) != name
        ):
            raise ValueError(
                f"{item_id} {name} compatibility identity mismatch"
            )
        if item_id in UNRESOLVED_ITEM_IDS:
            if compatibility_record.get("status") != "unresolved":
                raise ValueError(
                    f"{item_id} {name} must remain compatibility-unresolved"
                )
            record = {
                "itemId": item_id,
                "itemName": name,
                "profession": str(entry.get("profession", "")),
                "slot": "weapon",
                "sex": "male",
                "status": "unresolved",
                "mappingAssessment": {
                    "confidence": "unresolved",
                    "source": (
                        "res://assets/data/"
                        "equipment_primary_weapon_compatibility.json"
                        f"#/itemsById/{item_id}"
                    ),
                    "reason": str(
                        evidence.get(
                            "reason",
                            "no evidence-backed Weapon shape",
                        )
                    ),
                    "pixelAndActionConfidence": "not_applicable",
                },
                "runtimePolicy": (
                    "draw no weapon layer; do not guess a Weapon feature"
                ),
            }
            items_by_id[str(item_id)] = record
            continue

        runtime = runtime_mappings.get(name, {}).get("weaponAppearance", {})
        if not runtime:
            raise ValueError(f"{item_id} {name} lacks runtime weaponAppearance")
        if compatibility_record.get("status") != "resolved_primary_pixels":
            raise ValueError(
                f"{item_id} {name} lacks resolved primary compatibility"
            )
        shape = int(compatibility_record.get("classicWeaponShape", -1))
        raw_crystal_shape = compatibility_record.get("crystalShape")
        crystal_shape = (
            int(raw_crystal_shape)
            if raw_crystal_shape is not None
            else None
        )
        feature = int(runtime.get("feature", -1))
        if (
            feature != int(compatibility_record.get("maleFeature", -1))
            or feature != shape * 2
            or feature not in male_features
        ):
            raise ValueError(
                f"{item_id} {name} violates reviewed classic compatibility"
            )
        if item_id in INTEGRATION_SHARED_PRIMARY_ITEM_IDS:
            mapping_confidence = (
                "integration_user_required_shared_primary_appearance"
            )
        elif item_id in USER_CONFIRMED_CLASS_ITEM_IDS:
            mapping_confidence = (
                "user_confirmed_primary_pixel_compatibility"
            )
        else:
            mapping_confidence = "primary_pixel_compatibility"
        mapping_source = (
            "res://assets/data/"
            "equipment_primary_weapon_compatibility.json"
            f"#/itemsById/{item_id}"
        )
        if str(evidence.get("confidence", "")) != (
            "primary_pixel_compatibility"
        ):
            raise ValueError(
                f"{item_id} {name} must use primary pixel compatibility"
            )

        visible = True
        status = "visible"
        appearance = {
            "sex": "male",
            "shape": shape,
            "classicShape": shape,
            "feature": feature,
            "visualWeaponClass": str(
                compatibility_record.get("visualWeaponClass", "")
            ),
            "featureRef": f"featureFamilies.{feature}",
            "visible": visible,
            "actions": {
                action: {
                    "featureActionRef": (
                        f"featureFamilies.{feature}.actions.{action}"
                    ),
                    "path": feature_families[str(feature)]["actions"][
                        action
                    ]["path"],
                    "framesPerDirection": int(ACTIONS[action]["frames"]),
                }
                for action in ACTIONS
            },
            "actionFallbacks": {},
        }
        if crystal_shape is None:
            appearance["crystalShapeStatus"] = str(
                compatibility_record.get("crystalShapeStatus", "")
            )
        else:
            appearance["crystalShape"] = crystal_shape
        mapping_rule = (
            "male feature = integration-reviewed primary client Weapon "
            "shape * 2; no database Shape is available or adopted"
            if item_id in INTEGRATION_SHARED_PRIMARY_ITEM_IDS
            else (
                "male feature = reviewed classic Weapon shape * 2; "
                "Crystal Shape is never multiplied directly"
            )
        )
        item_record = {
            "itemId": item_id,
            "itemName": name,
            "profession": str(entry.get("profession", "")),
            "slot": "weapon",
            "sex": "male",
            "status": status,
            "mappingAssessment": {
                "confidence": mapping_confidence,
                "source": mapping_source,
                "mappingType": str(
                    compatibility_record.get("mappingType", "")
                ),
                "rule": mapping_rule,
                "crystalShapeUsedAsClassicShape": False,
                "pixelAndActionConfidence": "A",
            },
            "maleAppearance": appearance,
        }
        items_by_id[str(item_id)] = item_record
        runtime_by_item_id[str(item_id)] = {
            "weaponAppearance": appearance
        }

    payload = {
        "schemaVersion": 1,
        "contractId": CONTRACT_ID,
        "sex": "male",
        "source": {
            "library": "Weapon.wil",
            "path": (
                "dev_art_sources/reference/mir2_client_raw/Data/Weapon.wil"
            ),
            "imageCount": int(library_info["image_count"]),
            "blockFrames": BLOCK_FRAMES,
            "maleFeatureRule": (
                "feature = reviewed classic Weapon shape * 2; "
                "never Crystal Shape * 2"
            ),
            "primaryCompatibilityContract": (
                "res://assets/data/"
                "equipment_primary_weapon_compatibility.json"
            ),
            "provenance": compatibility.get("primarySources", {}),
        },
        "actorContract": {
            "contractId": "player.visual.classic_eight_direction.v1",
            "cell": list(CELL),
            "actorOrigin": list(ACTOR_ORIGIN),
            "footPoint": list(FOOT_POINT),
            "placementRule": (
                "frame local position = actorOrigin + original Weapon HotX/HotY"
            ),
            "directions": 8,
            "actions": ACTIONS,
            "footPointContractChanged": False,
        },
        "mappingPolicy": {
            "pixelAndActionCompleteness": "A",
            "itemNameToShape": "primary Image/StateItem/Weapon compatibility",
            "crystalShapeDirectMapping": False,
            "femaleExcluded": True,
            "unresolvedPolicy": "never infer or borrow a Weapon feature",
            "transparentEmptyFramePolicy": (
                "retain source transparency; never use a prior frame as fill"
            ),
        },
        "coverage": {
            "formalWeapons": len(formal_weapons),
            "visible": len(classified["visible"]),
            "hiddenByClassicRule": len(
                classified["hidden_by_classic_rule"]
            ),
            "unresolved": len(classified["unresolved"]),
            "maleWeaponFeatureFamilies": len(feature_families),
            "actionsPerFeature": len(ACTIONS),
            "directionsPerAction": 8,
            "missingFrames": 0,
            "transparentEmptyFrames": sum(
                len(action["transparentEmptyFrames"])
                for feature in feature_families.values()
                for action in feature["actions"].values()
            ),
            "femaleItems": 0,
        },
        "classification": classified,
        "featureFamilies": feature_families,
        "itemsById": items_by_id,
        "runtimeMappingsByItemId": runtime_by_item_id,
    }
    OUTPUT.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(
        "EQUIPMENT_MALE_WEAPON_WORLD_WEAR_PASS "
        "items=37 visible=35 hidden=0 unresolved=2 "
        f"features={len(feature_families)} actions=6 directions=8"
    )


if __name__ == "__main__":
    main()
