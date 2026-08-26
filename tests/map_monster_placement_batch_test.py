import hashlib
import importlib.util
import json
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "assets/data/map_design/map_monster_placement_plans_v2/manifest.json"
POLICY = ROOT / "assets/data/map_design/map_monster_placement_execution_policy_v1.json"
CATALOG = ROOT / "assets/data/runtime/canonical_monster_catalog.json"
SNAPSHOT = ROOT / "assets/data/map_design/map_authoring_snapshot_20260826.json"
EDITOR_ROOT = ROOT / "map_editor_workspace"


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


PLANNER = load_module("map_monster_auto_planner_batch_test", ROOT / "tools/map_editor/plan_map_monster_auto_placement.py")
WRITER = load_module("map_monster_safe_writer_batch_test", ROOT / "tools/map_editor/map_monster_placement_safe_writer.py")


def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def canonical_sha256(value):
    raw = json.dumps(
        value,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
        allow_nan=False,
    ).encode("utf-8")
    return hashlib.sha256(raw).hexdigest()


class MapMonsterPlacementBatchTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.manifest = load(MANIFEST)
        cls.policy = load(POLICY)
        cls.catalog = load(CATALOG)
        cls.catalog_by_id = {row["monster_id"]: row for row in cls.catalog["entries"]}
        cls.snapshot_by_map_id = {row["map_id"]: row for row in load(SNAPSHOT)["maps"]}

    def test_current_library_and_map_counts_are_frozen(self):
        raw = CATALOG.read_bytes()
        self.assertEqual(
            self.policy["current_monster_library"]["sha256"],
            hashlib.sha256(raw).hexdigest(),
        )
        self.assertEqual(156, len(self.catalog_by_id))
        self.assertEqual(67, self.manifest["summary"]["formal_map_count"])
        self.assertEqual(66, self.manifest["summary"]["candidate_map_count"])
        self.assertEqual(0, self.manifest["summary"]["transition_backfill_map_count"])
        self.assertEqual(1, self.manifest["summary"]["preserved_map_count"])
        self.assertEqual(0, self.manifest["summary"]["no_fixed_spawn_map_count"])

    def test_replacement_policy_and_inheritance_contract_are_explicit(self):
        self.assertEqual(
            {
                "world_bich_province",
                "world_wooma_forest",
                "wooma_temple_f1",
                "wooma_temple_f2",
                "wooma_temple_boss_hall",
            },
            set(self.policy["replace_existing_spawn_maps"]),
        )
        override = self.policy["pool_inheritance_overrides"][0]
        self.assertEqual("mengzhong_stone_coffin_room", override["map_id"])
        self.assertEqual(
            ["mengzhong_death_valley_dungeon", "mengzhong_dark_area"],
            override["source_map_ids"],
        )
        self.assertEqual([110, 112, 114, 116, 118, 120], override["expected_monster_ids"])
        self.assertEqual([], self.policy["transition_backfill_maps"])
        self.assertEqual([], self.policy["no_fixed_spawn_maps"])

    def test_stone_coffin_inherits_adjacent_pool_and_binds_target_map(self):
        row = next(value for value in self.manifest["maps"] if value["map_id"] == "mengzhong_stone_coffin_room")
        self.assertEqual("CANDIDATE_WRITTEN", row["status"])
        self.assertEqual({110, 112, 114, 116, 118, 120}, {value["monster_id"] for value in row["selected"]})
        self.assertEqual({"mengzhong_death_valley_dungeon", "mengzhong_dark_area"}, set(row["pool_inheritance"]["source_map_ids"]))
        candidate_path = EDITOR_ROOT / row["legacy_map_id"] / f"{row['legacy_map_id']}.editor.json"
        candidate = load(candidate_path)
        entries = candidate["layers"]["monster_spawn"] + candidate["layers"]["boss_spawn"]
        self.assertEqual({110, 112, 114, 116, 118, 120}, {entry["monster_id"] for entry in entries})
        self.assertEqual(6, len(entries))
        for entry in entries:
            self.assertEqual("mengzhong_stone_coffin_room", entry["authority_ref"]["map_id"])
            self.assertEqual("adjacent_pool_union", entry["placement_evidence"]["pool_inheritance"]["mode"])

    def test_replacement_maps_have_safe_fresh_positions(self):
        replacement_ids = set(self.policy["replace_existing_spawn_maps"])
        for row in self.manifest["maps"]:
            if row["map_id"] not in replacement_ids:
                continue
            candidate_path = EDITOR_ROOT / row["legacy_map_id"] / f"{row['legacy_map_id']}.editor.json"
            candidate = load(candidate_path)
            collision = PLANNER.build_collision(candidate)
            collision["blocked"] = set(collision["blocked"]) | WRITER._collect_static_blocked(candidate, collision["size"])
            reservations = PLANNER.build_reservations(candidate, collision)
            occupied = set()
            entries = candidate["layers"]["monster_spawn"] + candidate["layers"]["boss_spawn"]
            self.assertTrue(entries, row["map_id"])
            for entry in entries:
                tile = tuple(entry["tile"])
                self.assertNotIn(tile, collision["blocked"], row["map_id"])
                self.assertNotIn(tile, reservations["reserved"], row["map_id"])
                self.assertNotIn(tile, occupied, row["map_id"])
                occupied.add(tile)
            self.assertIn("replaced_source_spawn_count", row)

    def test_candidates_only_change_spawn_layers_and_use_current_library(self):
        for row in self.manifest["maps"]:
            if row["status"] != "CANDIDATE_WRITTEN":
                continue
            legacy = row["legacy_map_id"]
            candidate_path = EDITOR_ROOT / legacy / f"{legacy}.editor.json"
            candidate = load(candidate_path)
            source_inventory = self.snapshot_by_map_id[row["map_id"]]["layers"]
            self.assertEqual(row["candidate_sha256"], hashlib.sha256(candidate_path.read_bytes()).hexdigest())
            for name, descriptor in source_inventory.items():
                # Portal endpoints are normalized by the independent portal
                # suite after this historical monster snapshot was produced.
                # Keep every other non-spawn layer under the original strict
                # snapshot freeze contract.
                if name in {"monster_spawn", "boss_spawn"} or any(
                    layer in {"map_exit_points", "door_points"}
                    for layer in descriptor["source_layers"]
                ):
                    continue
                source_layers = descriptor["source_layers"]
                values = {layer: candidate["layers"].get(layer, []) for layer in source_layers}
                hashed_value = values[source_layers[0]] if len(source_layers) == 1 else values
                self.assertEqual(descriptor["sha256"], canonical_sha256(hashed_value), f"{row['map_id']}:{name}")
            ids = []
            for layer in ("monster_spawn", "boss_spawn"):
                for entry in candidate["layers"][layer]:
                    monster_id = entry["monster_id"]
                    ids.append(monster_id)
                    self.assertIn(monster_id, self.catalog_by_id, row["map_id"])
                    self.assertTrue(self.catalog_by_id[monster_id]["runtime_allowed"], row["map_id"])
                    self.assertEqual(1, entry["count"])
                    self.assertEqual(1, entry["max_alive"])
                    self.assertIn("authority_ref", entry)
            self.assertEqual(len(ids), len(set(ids)), row["map_id"])
            self.assertNotIn(159, ids, row["map_id"])

    def test_unknown_dark_exact_variants_and_deleted_variants_skipped(self):
        row = next(value for value in self.manifest["maps"] if value["map_id"] == "snake_unknown_dark_palace")
        self.assertEqual(
            set(self.policy["unknown_dark_palace"]["exact_current_library_ids"]),
            {value["monster_id"] for value in row["selected"]},
        )
        self.assertEqual(
            set(self.policy["unknown_dark_palace"]["missing_or_deleted_variants"]),
            {value["raw_token"] for value in row["skipped"]},
        )
        self.assertTrue(all(value["reason"] == "SKIP_DELETED_OR_NOT_IN_CURRENT_LIBRARY" for value in row["skipped"]))

    def test_frozen_purgatory_is_not_rewritten(self):
        frozen = self.policy["frozen_maps"][0]
        source = EDITOR_ROOT / frozen["legacy_map_id"] / f"{frozen['legacy_map_id']}.editor.json"
        self.assertEqual(frozen["source_sha256"], hashlib.sha256(source.read_bytes()).hexdigest())
        row = next(value for value in self.manifest["maps"] if value["map_id"] == frozen["map_id"])
        self.assertEqual("PRESERVE_USER_ACCEPTED", row["status"])


if __name__ == "__main__":
    unittest.main()
