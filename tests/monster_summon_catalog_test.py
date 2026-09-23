"""Scoped generation must not rebuild frozen monster/drop/art data."""
import copy
import importlib.util
from pathlib import Path
import unittest
import sys
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
SPEC = importlib.util.spec_from_file_location("catalog_builder", ROOT / "tools/build_canonical_monster_catalog.py")
builder = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(builder)


class EnemySummonCatalogTest(unittest.TestCase):
    def setUp(self):
        self.catalog = builder.load_json(builder.DEFAULT_OUTPUT)

    def test_scoped_generation_and_idempotence(self):
        before = copy.deepcopy(self.catalog)
        generated = builder.build_spawn_and_summons(self.catalog)
        self.assertEqual(self.catalog, before, "input must not mutate")
        self.assertEqual(builder.build_spawn_and_summons(generated), generated)
        by_id = generated["entries_by_id"]
        self.assertEqual(by_id["182"]["combat"]["behavior_profile"]["summonRule"]["monsterIds"], [183])
        self.assertEqual(by_id["126"]["combat"]["behavior_profile"]["summonRule"]["maxActive"], 5)
        boss = by_id["160"]["combat"]["boss_rule"]["mechanics"]["healthStageSummon"]
        self.assertEqual((boss["minCount"], boss["maxCount"], boss["maxActive"]), (4, 7, 15))
        self.assertEqual(boss["monsterIds"], [156, 153, 150, 128])
        for monster_id in (33, 183, 241):
            self.assertTrue(by_id[str(monster_id)]["runtime_allowed"])
        self.assertEqual(before["drop_profiles"], generated["drop_profiles"])
        # Mask precisely the permitted fields, then compare every other value.
        for doc in (before, generated):
            doc["runtime_policy"].pop("drops_gate_spawn", None)
            doc["summary"].pop("runtime_allowed_count", None)
            doc["summary"].pop("unresolved_count", None)
            for entry in doc["entries"] + list(doc["entries_by_id"].values()):
                entry["source_evidence"].pop("enemy_summons", None)
                if entry["monster_id"] in (33, 183, 241):
                    entry.pop("runtime_allowed", None)
                    entry.pop("status", None)
                    entry["runtime_capability"].pop("allowed", None)
                    entry["runtime_capability"].pop("blockers", None)
                    entry["source_evidence"].pop("spawn_drop_policy", None)
                    entry["source_evidence"]["status"].pop("runtime_allowed", None)
                combat = entry["combat"]
                rule = combat["behavior_profile"].get("summonRule", {})
                rule.pop("maxActive", None)
                if entry["monster_id"] == 182:
                    rule.pop("monsterIds", None)
                    rule.pop("compatibilityNote", None)
                if entry["monster_id"] == 160:
                    boss = combat["boss_rule"]["mechanics"]["healthStageSummon"]
                    for key in ("minCount", "maxCount", "maxActive", "monsterIds"):
                        boss.pop(key, None)
        self.assertEqual(before, generated, "all non-summon fields and unrelated summon parameters are frozen")

    def test_empty_drops_do_not_override_other_birth_restrictions(self):
        entry = self.catalog["entries_by_id"]["183"]
        entry["runtime_capability"]["blockers"] = ["drop_policy_not_closed", "art_not_formal"]
        entry["runtime_capability"]["art_ok"] = False
        for index, listed in enumerate(self.catalog["entries"]):
            if listed["monster_id"] == 183:
                self.catalog["entries"][index] = copy.deepcopy(entry)
        builder.apply_spawn_drop_policy(self.catalog, builder.load_json(builder.POLICY_PATH))
        result = self.catalog["entries_by_id"]["183"]
        self.assertFalse(result["runtime_allowed"])
        self.assertEqual(result["runtime_capability"]["blockers"], ["art_not_formal"])

    def test_rejects_divergent_mirrors(self):
        self.catalog["entries_by_id"]["182"]["classification"] = "invalid"
        with self.assertRaisesRegex(RuntimeError, "mirrors differ"):
            builder.build_spawn_and_summons(self.catalog)

    def test_rejects_duplicate_identity(self):
        self.catalog["entries"].append(self.catalog["entries"][0])
        with self.assertRaisesRegex(RuntimeError, "identities"):
            builder.build_spawn_and_summons(self.catalog)

    def test_rejects_bad_cap_or_missing_child(self):
        for field, bad_value in (("maxActive", 30), ("maxActive", 0), ("maxActive", True),
                                 ("monsterIds", [999999]), ("monsterIds", ["183"])):
            load = builder.load_json
            def malformed(path):
                data = load(path)
                if path == builder.BEHAVIOR_PATH:
                    data["profiles"]["stationary_spider"]["summonRule"][field] = bad_value
                return data
            with self.subTest(field=field, value=bad_value), patch.object(builder, "load_json", malformed):
                with self.assertRaises(RuntimeError):
                    builder.build_spawn_and_summons(self.catalog)


if __name__ == "__main__":
    unittest.main()
