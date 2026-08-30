#!/usr/bin/env python3
"""Source and runtime validation for the male Hum.wil dress contract."""

from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
CONTRACT = ROOT / "assets/data/equipment_male_dress_world_wear.json"
CATALOG = ROOT / "assets/data/equipment_visual_catalog.json"
HUM = ROOT / "dev_art_sources/reference/mir2_client_raw/Data/Hum.wil"
EXPECTED_IDS = {116, 118, 120, 122, 124, 126, 128, 130, 132, 140, 142, 144}
EXPECTED_FEATURES = set(range(0, 18, 2))
EXPECTED_ITEM_FEATURES = {
    116: 2,
    118: 4,
    120: 4,
    122: 6,
    128: 6,
    140: 12,
    124: 8,
    130: 8,
    142: 14,
    126: 10,
    132: 10,
    144: 16,
}
ACTION_FRAMES = {
    "idle": 4,
    "walk": 6,
    "run": 6,
    "attack": 6,
    "cast": 6,
    "hit": 3,
    "death": 4,
}

sys.path.insert(0, str(ROOT / "tools/vendor"))
from extract_wil import decode_sprite, read_library  # noqa: E402


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def disk_path(resource_path: str) -> Path:
    assert resource_path.startswith("res://")
    return ROOT / resource_path.removeprefix("res://")


def rgba_sha256(image: Image.Image) -> str:
    return hashlib.sha256(image.convert("RGBA").tobytes()).hexdigest()


def assert_ascii_schema_keys(value: object, location: str = "$") -> None:
    if isinstance(value, dict):
        for key, child in value.items():
            assert str(key).isascii(), f"non-ASCII schema key at {location}: {key!r}"
            assert_ascii_schema_keys(child, f"{location}.{key}")
    elif isinstance(value, list):
        for index, child in enumerate(value):
            assert_ascii_schema_keys(child, f"{location}[{index}]")


def main() -> None:
    contract = load_json(CONTRACT)
    catalog = load_json(CATALOG)
    assert_ascii_schema_keys(contract)
    assert contract["contractId"] == "equipment.world_wear.male_dress.v1"
    assert contract["sex"] == "male"
    assert contract["mappingPolicy"]["femaleExcluded"] is True
    assert contract["actorContract"]["cell"] == [192, 160]
    assert contract["actorContract"]["actorOrigin"] == [64, 80]
    assert contract["actorContract"]["directions"] == 8
    assert contract["actorContract"]["footPointContractChanged"] is False
    assert len(contract["source"]["sha256"]["wil"]) == 64
    assert len(contract["source"]["sha256"]["wix"]) == 64
    assert contract["coverage"] == {
        "maleArmorItems": 12,
        "expectedMaleArmorItems": 12,
        "maleHumFeatureFamiliesIncludingBase": 9,
        "dressedFeatureFamilies": 8,
        "actionsPerFeature": 7,
        "directionsPerAction": 8,
        "missingFrames": 0,
        "femaleItems": 0,
    }

    items = contract["itemsById"]
    assert {int(item_id) for item_id in items} == EXPECTED_IDS
    features = contract["featureFamilies"]
    assert {int(feature) for feature in features} == EXPECTED_FEATURES
    assert "appearancesByGender" not in CONTRACT.read_text(encoding="utf-8")
    acceptance = contract["acceptance"]
    assert acceptance["automaticRemappingProhibited"] is True
    review = acceptance["fullAtlasUserReview"]
    assert review["authority"] == "explicit_user_confirmation"
    assert review["confirmationDate"] == "2026-07-25"
    assert int(review["mappingCount"]) == 12
    assert review["femaleAssetsConfirmed"] == 0
    assert review["sharedFeatureGroups"] == {
        "4": [118, 120],
        "6": [122, 128],
        "8": [124, 130],
        "10": [126, 132],
    }
    assert {
        int(value["itemId"]): int(value["maleFeature"])
        for value in review["mappings"]
    } == EXPECTED_ITEM_FEATURES
    review_for_hash = {
        key: value
        for key, value in review.items()
        if key not in {"reviewManifestSha256", "runtimeArtifactPolicy"}
    }
    canonical_review = json.dumps(
        review_for_hash,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")
    assert hashlib.sha256(canonical_review).hexdigest() == (
        review["reviewManifestSha256"]
    )

    catalog_runtime = catalog["runtimeMappings"]
    for item_key, item in items.items():
        assert int(item_key) == int(item["itemId"])
        assert item["sex"] == "male"
        assert item["slot"] == "dress"
        assessment = item["mappingAssessment"]
        assert assessment["confidence"] == (
            "user_confirmed_full_atlas_review"
        )
        assert assessment["confidence"] != "A"
        assert assessment["pixelAndActionConfidence"] == "A"
        user_review = item["userAtlasReviewEvidence"]
        assert user_review["authority"] == "explicit_user_confirmation"
        assert user_review["confirmed"] is True
        assert int(user_review["maleFeature"]) == (
            EXPECTED_ITEM_FEATURES[int(item_key)]
        )
        assert user_review["reviewManifestSha256"] == (
            review["reviewManifestSha256"]
        )
        appearance = item["maleAppearance"]
        assert appearance["sex"] == "male"
        assert int(appearance["feature"]) == int(appearance["shape"]) * 2
        assert int(appearance["feature"]) % 2 == 0
        assert int(appearance["feature"]) == (
            EXPECTED_ITEM_FEATURES[int(item_key)]
        )
        feature = features[str(int(appearance["feature"]))]
        assert appearance["featureRef"] == (
            f"featureFamilies.{int(appearance['feature'])}"
        )
        runtime = catalog_runtime[item["itemName"]]["dressAppearance"]
        assert int(runtime["feature"]) == int(appearance["feature"])
        assert int(runtime["shape"]) == int(appearance["shape"])
        assert set(appearance["actions"]) == set(ACTION_FRAMES)
        for action, frames_per_direction in ACTION_FRAMES.items():
            action_ref = appearance["actions"][action]
            feature_action = feature["actions"][action]
            assert action_ref["path"] == feature_action["path"]
            assert runtime["actions"][action]["path"] == feature_action["path"]
            assert runtime["actions"][action]["missingFrames"] == []
            assert int(action_ref["framesPerDirection"]) == frames_per_direction
            assert "/female/" not in action_ref["path"]

    data, palette, offsets, _info = read_library(HUM)
    for feature_key, feature in features.items():
        feature_id = int(feature_key)
        assert feature["sex"] == "male"
        assert int(feature["feature"]) == feature_id
        assert feature["cell"] == [192, 160]
        assert feature["actorOrigin"] == [64, 80]
        for action, frames_per_direction in ACTION_FRAMES.items():
            record = feature["actions"][action]
            assert record["directions"] == 8
            assert record["framesPerDirection"] == frames_per_direction
            assert record["decodedFrameCount"] == 8 * frames_per_direction
            assert record["missingFrames"] == []
            assert record["pixelActionConfidence"] == "A"

            atlas = Image.open(disk_path(record["path"])).convert("RGBA")
            assert atlas.size == (192 * frames_per_direction, 160 * 8)
            assert rgba_sha256(atlas) == record["atlasRgbaSha256"]
            rebuilt = Image.new("RGBA", atlas.size, (0, 0, 0, 0))
            transparent_indices: list[int] = []
            if action == "run":
                assert "sourceFrames" not in record
                assert int(record["sourceStart"]) == 128
                source_frames = [
                    {
                        "sourceIndex": feature_id * 600 + 128 + direction * 8 + frame,
                        "direction": direction,
                        "frame": frame,
                    }
                    for direction in range(8)
                    for frame in range(frames_per_direction)
                ]
            else:
                source_frames = record["sourceFrames"]
                assert len(source_frames) == 8 * frames_per_direction
            for frame in source_frames:
                source_index = int(frame["sourceIndex"])
                decoded, metadata = decode_sprite(
                    data,
                    offsets[source_index],
                    palette,
                )
                decoded = decoded.convert("RGBA")
                hot = [int(metadata["x"]), int(metadata["y"])]
                opaque_pixels = sum(
                    alpha != 0 for alpha in decoded.getchannel("A").tobytes()
                )
                if action != "run":
                    assert hot == frame["hot"]
                    assert [decoded.width, decoded.height] == frame["sourceSize"]
                    assert rgba_sha256(decoded) == frame["rgbaSha256"]
                    assert opaque_pixels == int(frame["opaquePixelCount"])
                    assert bool(frame["transparentEmpty"]) == (opaque_pixels == 0)
                else:
                    assert opaque_pixels > 0
                if opaque_pixels == 0:
                    transparent_indices.append(source_index)
                x = (
                    int(frame["frame"]) * 192
                    + 64
                    + hot[0]
                )
                y = (
                    int(frame["direction"]) * 160
                    + 80
                    + hot[1]
                )
                rebuilt.alpha_composite(decoded, (x, y))
            assert transparent_indices == record["transparentEmptyFrames"]
            assert rebuilt.tobytes() == atlas.tobytes()

    print(
        "EQUIPMENT_MALE_DRESS_WORLD_WEAR_TEST_PASS "
        "items=12 features=9 actions=7 directions=8"
    )


if __name__ == "__main__":
    main()
