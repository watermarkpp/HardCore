#!/usr/bin/env python3
"""Verify finalized helmet inventory/drop runtime routes and frozen pixels."""

from __future__ import annotations

import hashlib
import json
import subprocess
import sys
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
CATALOG_PATH = ROOT / "assets/data/equipment_visual_catalog.json"
MANIFEST_PATH = ROOT / "assets/data/equipment_helmet_finalization_manifest.json"
ROUTES_PATH = (
    ROOT / "assets/data/equipment_helmet_runtime_icon_routes.json"
)
ITEM_IDS = (146, 147, 148, 149, 150, 151, 218, 224, 228, 232, 236, 240)
EXPECTED_SELECTIONS = {
    146: (("direction", "S"), ("direction", "W")),
    147: (("direction", "S"), ("direction", "SW")),
    148: (("direction", "S"), ("direction", "SW")),
    149: (("dedicated_inventory", "S"), ("direction", "E")),
    150: (("direction", "S"), ("direction", "SW")),
    151: (("direction", "S"), ("direction", "SW")),
    218: (("dedicated_inventory", "S"), ("direction", "E")),
    224: (("dedicated_inventory", "S"), ("direction", "E")),
    228: (("direction", "S"), ("direction", "SW")),
    232: (("direction", "S"), ("direction", "SW")),
    236: (("direction", "S"), ("direction", "S")),
    240: (
        ("dedicated_inventory", "S"),
        ("dedicated_ground", "S"),
    ),
}
EXPECTED_TARGET_CONTENT_SIZES = {
    146: ((33, 23), (10, 7)),
    147: ((18, 29), (14, 22)),
    148: ((18, 29), (14, 22)),
    149: ((23, 37), (11, 16)),
    150: ((28, 43), (14, 18)),
    151: ((20, 29), (9, 14)),
    218: ((23, 31), (10, 12)),
    224: ((20, 30), (10, 13)),
    228: ((21, 31), (10, 16)),
    232: ((28, 37), (12, 20)),
    236: ((28, 28), (13, 13)),
    240: ((22, 38), (11, 18)),
}
EXPECTED_CLASSIC_LOOKS = {
    146: 105,
    147: 100,
    148: 100,
    149: 106,
    150: 103,
    151: 344,
    218: 111,
    224: 110,
    228: 109,
    232: 104,
    236: 101,
    240: 102,
}


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def project_path(value: str) -> Path:
    assert value.startswith("res://"), value
    return ROOT / value.removeprefix("res://")


def owner(manifest: dict, item_id: int) -> dict:
    matches = [
        record
        for record in manifest["items"].values()
        if item_id in [int(value) for value in record["sharedItemIds"]]
    ]
    assert len(matches) == 1, (item_id, len(matches))
    return matches[0]


def verify() -> None:
    catalog = load_json(CATALOG_PATH)
    manifest = load_json(MANIFEST_PATH)
    routes = load_json(ROUTES_PATH)
    assert routes["contractId"] == "equipment.helmet.runtime_icon_routes.v1"
    assert routes["runtimeReadable"] is True
    assert {int(value) for value in routes["routesByItemId"]} == set(ITEM_IDS)

    paper_paths: set[Path] = set()
    world_paths: set[Path] = set()
    icon_paths: set[Path] = set()
    for item_id in ITEM_IDS:
        item_key = str(item_id)
        catalog_item = catalog["itemsById"][item_key]
        item_name = catalog_item["itemName"]
        runtime = catalog["runtimeMappings"][item_name]
        route = routes["routesByItemId"][item_key]
        assert route["itemId"] == item_id
        assert route["itemName"] == item_name
        finalized = owner(manifest, item_id)
        output = finalized["presentationOutputs"][item_key]

        for role, runtime_field in (
            ("inventory", "inventoryIcon"),
            ("ground", "groundIcon"),
        ):
            record = catalog_item["icons"][role]
            assert runtime[runtime_field] == record
            assert route[runtime_field] == record
            assert record == {
                key: value
                for key, value in output[role].items()
                if key != "provenance"
            }
            path = project_path(record["path"])
            assert sha256(path) == record["fileSha256"]
            image = Image.open(path).convert("RGBA")
            role_index = 0 if role == "inventory" else 1
            target = EXPECTED_TARGET_CONTENT_SIZES[item_id][role_index]
            assert tuple(record["targetContentSize"]) == target
            assert tuple(record["displaySize"]) == (
                target[0] + 2,
                target[1] + 2,
            )
            assert tuple(record["size"]) == tuple(record["displaySize"])
            assert image.size == tuple(record["displaySize"])
            assert max(image.size) <= 64
            assert record["classicReferenceLooks"] == (
                EXPECTED_CLASSIC_LOOKS[item_id]
            )
            assert record["classicReferenceLane"] == "client_assets"
            assert record["classicReferenceDistribution"] == (
                "client.classic_raw_complete"
            )
            assert record["userSourceLane"] == (
                "user_authorized_direct_source"
            )
            assert record["scaleRule"] == (
                "classic_content_area_equivalent_aspect_preserved_v1"
            )
            assert record["runtimeScale"] == [1, 1]
            assert record["runtimeTextureFilter"] == "nearest"
            assert record["singlePassDownsample"] is True
            assert record["sourceAspectPreserved"] is True
            assert len(record["sourceContentSize"]) == 2
            assert len(record["classicReferenceContentSize"]) == 2
            alpha = image.getchannel("A")
            assert alpha.crop((0, 0, image.width, 1)).getbbox() is None
            assert alpha.crop(
                (0, image.height - 1, image.width, image.height)
            ).getbbox() is None
            assert alpha.crop((0, 0, 1, image.height)).getbbox() is None
            assert alpha.crop(
                (image.width - 1, 0, image.width, image.height)
            ).getbbox() is None
            icon_paths.add(path)

        expected_inventory, expected_ground = EXPECTED_SELECTIONS[item_id]
        assert (
            runtime["inventoryIcon"]["sourceVariant"],
            runtime["inventoryIcon"]["sourceDirection"],
        ) == expected_inventory
        assert (
            runtime["groundIcon"]["sourceVariant"],
            runtime["groundIcon"]["sourceDirection"],
        ) == expected_ground

        paper = output["paperDoll"]
        paper_path = project_path(paper["path"])
        assert sha256(paper_path) == paper["fileSha256"]
        assert sha256(project_path(paper["eraseMaskPath"])) == paper[
            "eraseMaskFileSha256"
        ]
        paper_paths.add(paper_path)
        for action, path_value in finalized["runtimeAtlases"].items():
            path = project_path(path_value)
            assert sha256(path) == finalized["runtimeAtlasSha256"][action]
            world_paths.add(path)

    assert len(icon_paths) == 24
    assert len(paper_paths) == 12
    assert len(world_paths) == 66

    before = {
        path: sha256(path)
        for path in icon_paths | paper_paths | world_paths
    }
    completed = subprocess.run(
        [
            sys.executable,
            str(ROOT / "tools/route_final_helmet_runtime_icons.py"),
            "--project-root",
            str(ROOT),
            *sum(
                (["--item-id", str(item_id)] for item_id in ITEM_IDS),
                [],
            ),
            "--verify-only",
        ],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    assert "icons_written=0" in completed.stdout
    assert "paper_world_written=0" in completed.stdout
    assert {path: sha256(path) for path in before} == before

    loot_source = (ROOT / "scripts/loot_pickup.gd").read_text(
        encoding="utf-8"
    )
    assert "icon_sprite.texture = load(icon_path)" in loot_source
    assert "icon_sprite.scale" not in loot_source


if __name__ == "__main__":
    verify()
    print(
        "EQUIPMENT_HELMET_RUNTIME_ICON_ROUTES_TEST_PASS "
        "item_ids=12 inventory=12 ground=12 paper_frozen=12 "
        "world_atlases_frozen=66 runtime_scale=1x1"
    )
