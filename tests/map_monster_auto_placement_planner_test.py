#!/usr/bin/env python3
"""Focused tests for the fail-closed automatic monster placement planner."""

from __future__ import annotations

import copy
import hashlib
import importlib.util
import json
import sys
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
PLANNER_PATH = REPO_ROOT / "tools" / "map_editor" / "plan_map_monster_auto_placement.py"
SPEC = importlib.util.spec_from_file_location("map_monster_auto_placement_planner", PLANNER_PATH)
assert SPEC is not None and SPEC.loader is not None
PLANNER = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = PLANNER
SPEC.loader.exec_module(PLANNER)


def _token(
    monster_id: int,
    *,
    classification: str = "ordinary",
    source_line: int = 10,
    token_index: int = 1,
    map_id: str = "formal_test_map",
) -> dict[str, object]:
    role = "ordinary" if classification == "ordinary" else classification
    layer = "monster_spawn" if classification == "ordinary" else "boss_spawn"
    return {
        "map_id": map_id,
        "source_line": source_line,
        "source_category_role": role,
        "source_token_index": token_index,
        "auto_placement_status": PLANNER.ALLOWED_STATUS,
        "auto_placement_allowed": True,
        "placement_allowed": True,
        "status": "resolved",
        "resolution_status": "resolved",
        "resolved_monster_ids": [monster_id],
        "resolved_monster_id": monster_id,
        "resolved_canonical_names": [f"Monster {monster_id}"],
        "classification": classification,
        "placement_kind": layer,
    }


def _map_record(tokens: list[dict[str, object]]) -> dict[str, object]:
    return {
        "map_id": "formal_test_map",
        "legacy_map_id": "legacy_test_map",
        "runtime_map_id": 900001,
        "legacy_runtime_id": 301,
        "display_name": "Synthetic Dungeon",
        "series": "synthetic_dungeon",
        "tokens": tokens,
    }


def _document(*, size: tuple[int, int] = (20, 14)) -> dict[str, object]:
    layers = {
        layer: []
        for layer in (
            "boss_spawn",
            "collision",
            "collision_erase",
            "door_points",
            "interactables",
            "map_entrance_points",
            "map_exit_points",
            "monster_spawn",
            "npc_points",
            "object_base",
            "object_front",
            "respawn_points",
            "safe_area",
            "terrain_base",
            "terrain_front",
        )
    }
    layers["collision"] = [
        {
            "collision_id": "partition-wall",
            "shape": "rect",
            "data": {"rect": [9, 0, 1, size[1]]},
            "blocks_monster": True,
        }
    ]
    return {
        "schema_version": 1,
        "map_id": "legacy_test_map",
        "runtime_map_id": 301,
        "design": {"design_size": list(size)},
        "layers": layers,
    }


class AutoPlacementPlannerTest(unittest.TestCase):
    def test_connected_partition_and_collision_erase_are_deterministic(self) -> None:
        document = _document(size=(20, 14))
        uncut_collision = PLANNER.build_collision(document)
        all_cells = {(x, y) for y in range(14) for x in range(20)}
        partitioned = PLANNER.connected_components(all_cells - uncut_collision["blocked"])
        self.assertEqual([len(component) for component in partitioned], [140, 126])
        document["layers"]["collision_erase"] = [{"tile": [9, 7]}]
        collision = PLANNER.build_collision(document)
        self.assertIn((9, 6), collision["blocked"])
        self.assertNotIn((9, 7), collision["blocked"])
        components = PLANNER.connected_components(all_cells - collision["blocked"])
        self.assertEqual([len(component) for component in components], [267])
        self.assertEqual(components, PLANNER.connected_components(all_cells - collision["blocked"]))

    def test_authority_consumes_only_allowed_unique_ids_and_uses_four_field_ref(self) -> None:
        duplicate = _token(21, source_line=11, token_index=2)
        multi = _token(79, source_line=12, token_index=1)
        multi["resolved_monster_ids"] = [79, 81, 83]
        multi["resolved_monster_id"] = None
        multi["resolved_canonical_names"] = ["Zombie 1", "Zombie 2", "Zombie 3"]
        excluded = _token(55, source_line=13)
        excluded["auto_placement_status"] = "EXCLUDED"
        excluded["auto_placement_allowed"] = False
        identities, skipped, blockers = PLANNER.authority_identities(
            _map_record(
                [
                    _token(21, source_line=10),
                    duplicate,
                    _token(100, classification="boss", source_line=20),
                    multi,
                    excluded,
                ]
            )
        )
        self.assertEqual([row["monster_id"] for row in identities], [21, 100])
        self.assertEqual(blockers, [])
        self.assertEqual(skipped["AUTO_PLACEMENT_ALLOWED_NON_UNIQUE_MONSTER_ID"], 1)
        self.assertEqual(skipped["EXCLUDED"], 1)
        self.assertEqual(
            set(identities[0]["authority_ref"]),
            {"map_id", "source_line", "source_category_role", "source_token_index"},
        )
        self.assertEqual(identities[0]["authority_duplicate_token_count"], 2)

    def test_entrance_safe_npc_and_solid_footprints_are_reserved(self) -> None:
        document = _document()
        layers = document["layers"]
        layers["map_entrance_points"] = [{"tile": [2, 2]}]
        layers["map_exit_points"] = [{"tile": [17, 11]}]
        layers["respawn_points"] = [{"tile": [2, 11]}]
        layers["safe_area"] = [{"tile": [5, 5], "shape": "circle", "radius_gu": 1}]
        layers["npc_points"] = [{"tile": [14, 4], "occupancy_footprint_tiles": [2, 1]}]
        layers["object_base"] = [
            {
                "instance_id": "solid-crate",
                "tile": [12, 8],
                "footprint_tiles": [2, 2],
                "collision_footprint_tiles": [2, 2],
                "collision_policy": "solid",
            }
        ]
        report = PLANNER.evaluate_map(
            _map_record([_token(21), _token(100, classification="boss", source_line=20)]),
            document,
            hashlib.sha256(PLANNER.canonical_bytes(document)).hexdigest(),
            "a" * 64,
        )
        self.assertEqual(report["status"], "READY")
        self.assertEqual(report["placement_summary"]["monster_spawn_count"], 1)
        self.assertEqual(report["placement_summary"]["boss_spawn_count"], 1)
        self.assertEqual(report["placement_summary"]["AUTO_POSITIONED_BOSS"], 1)
        collision = PLANNER.build_collision(document)
        reservations = PLANNER.build_reservations(document, collision)
        tiles = [tuple(entry["tile"]) for entry in report["placements"]]
        self.assertEqual(len(tiles), len(set(tiles)))
        for tile in tiles:
            self.assertNotIn(tile, collision["blocked"])
            self.assertNotIn(tile, reservations["reserved"])
            self.assertGreater(max(abs(tile[0] - 2), abs(tile[1] - 2)), PLANNER.PORTAL_BUFFER)
        boss = next(entry for entry in report["placements"] if entry["classification"] == "boss")
        self.assertEqual(boss["kind"], "boss_spawn")
        self.assertNotIn("respawn_policy_id", boss)
        ordinary = next(entry for entry in report["placements"] if entry["classification"] == "ordinary")
        self.assertEqual(ordinary["respawn_policy_id"], "normal_cave")

    def test_evaluation_is_byte_stable(self) -> None:
        document = _document()
        record = _map_record([_token(21), _token(34, source_line=11, token_index=2)])
        first = PLANNER.evaluate_map(record, copy.deepcopy(document), "b" * 64, "c" * 64)
        second = PLANNER.evaluate_map(record, copy.deepcopy(document), "b" * 64, "c" * 64)
        self.assertEqual(PLANNER.canonical_bytes(first), PLANNER.canonical_bytes(second))
        ids = [entry["semantic_id"] for entry in first["placements"]]
        groups = [entry["spawn_group_id"] for entry in first["placements"]]
        self.assertEqual(len(ids), len(set(ids)))
        self.assertEqual(len(groups), len(set(groups)))

    def test_empty_collision_fails_closed_without_guessing(self) -> None:
        document = _document()
        document["layers"]["collision"] = []
        report = PLANNER.evaluate_map(
            _map_record([_token(21)]), document, "d" * 64, "e" * 64
        )
        self.assertEqual(report["status"], "BLOCKED")
        self.assertIn("collision_incomplete_or_empty", report["blockers"])
        self.assertEqual(report["placements"], [])


if __name__ == "__main__":
    unittest.main()
