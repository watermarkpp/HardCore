import hashlib
import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "assets/data/map_design/map_monster_placement_plans_v2/manifest.json"
POLICY = ROOT / "assets/data/map_design/map_monster_placement_execution_policy_v1.json"
CATALOG = ROOT / "assets/data/runtime/canonical_monster_catalog.json"
SNAPSHOT = ROOT / "assets/data/map_design/map_authoring_snapshot_20260826.json"
EDITOR_ROOT = ROOT / "map_editor_workspace"


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
        self.assertEqual(60, self.manifest["summary"]["candidate_map_count"])
        self.assertEqual(5, self.manifest["summary"]["transition_backfill_map_count"])
        self.assertEqual(1, self.manifest["summary"]["preserved_map_count"])
        self.assertEqual(1, self.manifest["summary"]["no_fixed_spawn_map_count"])

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
                if name in {"monster_spawn", "boss_spawn"}:
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
