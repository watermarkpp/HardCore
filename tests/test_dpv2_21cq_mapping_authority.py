from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
TOOL_PATH = ROOT / "tools/build_dpv2_21cq_direct_baseline.py"
SPEC = importlib.util.spec_from_file_location("dpv2_21cq_builder_mapping", TOOL_PATH)
assert SPEC is not None and SPEC.loader is not None
builder = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(builder)


class MappingAuthorityTests(unittest.TestCase):
    def setUp(self) -> None:
        self.audit = builder.parse_source()
        self.monsters = builder.build_monster_mapping(self.audit)
        self.items = builder.build_item_mapping(self.audit, self.monsters)
        self.overflow = builder.build_overflow_authority(self.items)

    def test_monster_mapping_and_disposition_closure(self) -> None:
        summary = self.monsters["summary"]
        self.assertEqual(summary["source_monster_records"], 217)
        self.assertEqual(summary["canonical_profiles"], 156)
        self.assertEqual(summary["active_canonical_monsters"], 153)
        self.assertEqual(summary["runtime_allowed_monsters"], 153)
        self.assertEqual(summary["drop_enabled_monsters"], 144)
        self.assertEqual(summary["explicit_non_loot_monsters"], 9)
        self.assertEqual(summary["runtime_disabled_monsters"], 3)
        self.assertEqual(summary["non_loot_monsters"], 9)
        self.assertEqual(summary["mapping_unresolved"], 0)
        self.assertEqual(
            summary["source_disposition_row_counts"],
            {
                "LEGACY_21CQ_COMPILED": 6740,
                "PROJECT_EXTENSION_COMPILED": 69,
                "EXPLICIT_NON_LOOT_EXCLUDED": 223,
                "RETIRED_OUT_OF_RUNTIME": 2558,
            },
        )
        self.assertEqual(summary["source_disposition_row_sum"], 9590)

    def test_project_extension_and_non_loot_are_explicit(self) -> None:
        by_id = {
            int(row["canonical_monster_id"]): row
            for row in self.monsters["records"]
        }
        dark_cow = by_id[225]
        self.assertEqual(dark_cow["mapping_status"], "PROJECT_EXTENSION")
        self.assertEqual(dark_cow["baseline_origin"], "PROJECT_EXTENSION")
        self.assertEqual(dark_cow["source_row_count"], 69)
        non_loot = [
            row for row in by_id.values()
            if row["mapping_status"] == "EXPLICIT_NON_LOOT"
        ]
        self.assertEqual(len(non_loot), 9)
        self.assertTrue(
            all(
                row["drop_enabled"] is False
                and row["drop_profile_id"] is None
                for row in non_loot
            )
        )
        runtime_disabled = [
            row for row in by_id.values()
            if row["mapping_status"] == "RUNTIME_DISABLED"
        ]
        self.assertEqual(len(runtime_disabled), 3)
        self.assertTrue(
            all(
                row["runtime_allowed"] is False
                and row["drop_enabled"] is False
                and row["drop_profile_id"] is None
                and row["source_row_count"] == 0
                for row in runtime_disabled
            )
        )

    def test_item_labels_resolve_without_runtime_lookup(self) -> None:
        summary = self.items["summary"]
        self.assertEqual(summary["canonical_item_ids_covered"], 233)
        self.assertEqual(summary["mapping_unresolved"], 0)
        self.assertEqual(
            summary["retired_source_only_not_in_canonical_catalog"], 5
        )
        by_label = {row["source_item_label"]: row for row in self.items["records"]}
        self.assertEqual(by_label["金币"]["reward_kind"], "gold")
        self.assertIsNone(by_label["金币"]["canonical_item_id"])
        self.assertEqual(by_label["群体治愈术"]["mapping_status"], "EXPLICIT_ALIAS")
        self.assertEqual(by_label["群体治愈术"]["canonical_item_name"], "群体治疗术")
        for label in {"鸡肉", "鹿血", "神水", "鹿茸", "血饮"}:
            row = by_label[label]
            self.assertEqual(
                row["mapping_status"],
                "RETIRED_SOURCE_ONLY_NOT_IN_CANONICAL_CATALOG",
            )
            self.assertIsNone(row["canonical_item_id"])
            self.assertTrue(
                all(
                    occurrence["source_disposition"] == "RETIRED_OUT_OF_RUNTIME"
                    for occurrence in row["source_occurrences"]
                )
            )

    def test_overflow_authority_has_no_probability_classification(self) -> None:
        forbidden = {"tier", "drop_role", "role_factor", "tier_factor", "base_denominator"}

        def visit(value: object) -> None:
            if isinstance(value, dict):
                self.assertTrue(forbidden.isdisjoint(value))
                for child in value.values():
                    visit(child)
            elif isinstance(value, list):
                for child in value:
                    visit(child)

        visit(self.overflow)
        self.assertEqual(len(self.overflow["records"]), 233)
        self.assertEqual(self.overflow["policy"]["gold"]["overflow_priority"], 100)
        self.assertTrue(
            all(row["probability_effect"] == "NONE" for row in self.overflow["records"])
        )

    def test_source_priority_lane_is_strictly_scoped(self) -> None:
        policy = json.loads(
            (ROOT / "assets/data/source_priority_policy.json").read_text(encoding="utf-8")
        )
        self.assertEqual(
            policy["routing"]["monster_drop_probability_and_post_rng_overflow"],
            "monster_drop_probability",
        )
        lane = policy["lanes"]["monster_drop_probability"]
        excluded = set(lane["scopeExclusions"]["server_data"])
        self.assertTrue(
            {
                "monster_identity",
                "monster_stats",
                "monster_ai",
                "monster_respawn",
                "monster_map_placement",
                "item_attributes",
            }.issubset(excluded)
        )


if __name__ == "__main__":
    unittest.main()
