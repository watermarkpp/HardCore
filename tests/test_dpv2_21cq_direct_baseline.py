from __future__ import annotations

import hashlib
import importlib.util
import json
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
TOOL_PATH = ROOT / "tools/build_dpv2_21cq_direct_baseline.py"
BASELINE_PATH = ROOT / "assets/data/drop/dpv2_direct_baseline_v2.json"
PROVENANCE_PATH = ROOT / "assets/data/drop/dpv2_21cq_source_provenance_v1.json"
MANIFEST_PATH = ROOT / "assets/data/drop/dpv2_direct_baseline_manifest_v2.json"
SPEC = importlib.util.spec_from_file_location("dpv2_21cq_builder_direct", TOOL_PATH)
assert SPEC is not None and SPEC.loader is not None
builder = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(builder)


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def lf_sha(path: Path) -> str:
    text = path.read_text(encoding="utf-8")
    normalized = text.replace("\r\n", "\n").replace("\r", "\n")
    return hashlib.sha256(normalized.encode("utf-8")).hexdigest().upper()


class DirectBaselineTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.baseline = load_json(BASELINE_PATH)
        cls.provenance = load_json(PROVENANCE_PATH)
        cls.manifest = load_json(MANIFEST_PATH)

    def test_active_profiles_and_compiled_slot_counts_close(self) -> None:
        summary = self.baseline["summary"]
        self.assertTrue(self.baseline["production_active"])
        self.assertEqual(self.baseline["production_runtime"], "V2_DIRECT_BASELINE")
        self.assertEqual(summary["active_monsters"], 156)
        self.assertEqual(summary["runtime_allowed_monsters"], 153)
        self.assertEqual(summary["drop_enabled_monsters"], 144)
        self.assertEqual(summary["explicit_non_loot_monsters"], 9)
        self.assertEqual(summary["runtime_disabled_monsters"], 3)
        self.assertEqual(summary["non_loot_monsters"], 9)
        self.assertEqual(summary["compiled_slots"], 6809)
        self.assertEqual(
            self.baseline["probability_policy"]["global_drop_rate_scale"], 1.0
        )
        self.assertTrue(
            self.baseline["probability_policy"][
                "global_drop_rate_scale_is_only_multiplier"
            ]
        )
        self.assertEqual(
            summary["baseline_origin_counts"],
            {"LEGACY_21CQ_MONITEMS": 6740, "PROJECT_EXTENSION": 69},
        )

    def test_non_loot_is_not_a_probability_role(self) -> None:
        non_loot = [
            profile
            for profile in self.baseline["profiles"]
            if profile["semantic_status"] == "EXPLICIT_NON_LOOT"
        ]
        self.assertEqual(len(non_loot), 9)
        self.assertTrue(
            all(
                profile["drop_profile_id"] is None
                and profile["reporting_label"] == "NON_LOOT"
                and profile["slots"] == []
                for profile in non_loot
            )
        )
        runtime_disabled = [
            profile
            for profile in self.baseline["profiles"]
            if profile["semantic_status"] == "RUNTIME_DISABLED"
        ]
        self.assertEqual(len(runtime_disabled), 3)
        self.assertTrue(
            all(
                profile["drop_enabled"] is False
                and profile["drop_profile_id"] is None
                and profile["slots"] == []
                for profile in runtime_disabled
            )
        )

    def test_slot_contract_contains_only_direct_probability_and_overflow(self) -> None:
        shared = {
            "slot_uid",
            "base_numerator",
            "base_denominator",
            "overflow_priority",
            "protected_drop",
            "baseline_origin",
            "source_provenance_id",
        }
        slot_uids: list[str] = []
        provenance_ids: list[str] = []
        for profile in self.baseline["profiles"]:
            for slot in profile["slots"]:
                reward_keys = {"canonical_item_id", "gold_amount"} & set(slot)
                self.assertEqual(len(reward_keys), 1)
                self.assertEqual(set(slot), shared | reward_keys)
                self.assertGreater(slot["base_numerator"], 0)
                self.assertGreater(slot["base_denominator"], 0)
                slot_uids.append(slot["slot_uid"])
                provenance_ids.append(slot["source_provenance_id"])
        self.assertEqual(len(slot_uids), 6809)
        self.assertEqual(len(set(slot_uids)), 6809)
        self.assertEqual(len(set(provenance_ids)), 6809)

    def test_x1_values_match_every_effective_compiled_source_row(self) -> None:
        audit = builder.parse_source()
        monsters = builder.build_monster_mapping(audit)
        disposition = {
            int(row["source_monster_id"]): row["source_disposition"]
            for row in monsters["records"]
        }
        expected = {
            builder._compiled_slot_uid(int(row["monster_id"]), row["slot_index"]): (
                int(row["base_numerator"]),
                int(row["base_denominator"]),
            )
            for row in audit["parsed_rows"]
            if disposition[int(row["monster_id"])]
            in {"LEGACY_21CQ_COMPILED", "PROJECT_EXTENSION_COMPILED"}
        }
        actual = {
            slot["slot_uid"]: (
                int(slot["base_numerator"]),
                int(slot["base_denominator"]),
            )
            for profile in self.baseline["profiles"]
            for slot in profile["slots"]
        }
        self.assertEqual(actual, expected)
        self.assertEqual(self.baseline["summary"]["x1_probability_mismatch"], 0)
        self.assertEqual(self.baseline["summary"]["duplicate_slot_collapse"], 0)

    def test_correction_is_explicit_and_historical_value_is_preserved(self) -> None:
        slot = next(
            slot
            for profile in self.baseline["profiles"]
            for slot in profile["slots"]
            if slot["slot_uid"] == "dpv2.direct.m168.slot_020"
        )
        evidence = next(
            row
            for row in self.provenance["records"]
            if row["source_provenance_id"] == "dpv2.source.m168.slot_020"
        )
        self.assertEqual(slot["base_denominator"], 2800)
        self.assertEqual(evidence["source_chance"], "1/00")
        self.assertEqual(evidence["effective_base_denominator"], 2800)
        self.assertEqual(
            evidence["correction_id"],
            "21cq.monster_168.slot_020.invalid_1_over_00",
        )

    def test_full_source_disposition_and_provenance_close(self) -> None:
        summary = self.provenance["summary"]
        self.assertEqual(summary["source_rows"], 9590)
        self.assertEqual(summary["disposition_sum"], 9590)
        self.assertEqual(
            summary["disposition_counts"],
            {
                "LEGACY_21CQ_COMPILED": 6740,
                "PROJECT_EXTENSION_COMPILED": 69,
                "EXPLICIT_NON_LOOT_EXCLUDED": 223,
                "RETIRED_OUT_OF_RUNTIME": 2558,
            },
        )
        ids = [row["source_provenance_id"] for row in self.provenance["records"]]
        self.assertEqual(len(ids), len(set(ids)))

    def test_monster_225_is_project_extension(self) -> None:
        profile = next(
            row
            for row in self.baseline["profiles"]
            if row["canonical_monster_id"] == 225
        )
        self.assertTrue(profile["drop_enabled"])
        self.assertEqual(profile["baseline_origin"], "PROJECT_EXTENSION")
        self.assertEqual(len(profile["slots"]), 69)
        self.assertTrue(
            all(slot["baseline_origin"] == "PROJECT_EXTENSION" for slot in profile["slots"])
        )
        project_provenance = [
            row
            for row in self.provenance["records"]
            if row["source_monster_id"] == 225
        ]
        self.assertEqual(len(project_provenance), 69)
        self.assertTrue(
            all(
                row["source_authority_interpretation"]
                == "PROJECT_EXTENSION_SNAPSHOT_ONLY_NOT_21CQ_AUTHORITY"
                for row in project_provenance
            )
        )

    def test_manifest_hashes_all_authority_outputs_with_lf_normalization(self) -> None:
        self.assertEqual(
            self.manifest["tracked_logical_source"]["sha256_raw"],
            builder.sha256_raw(builder.SOURCE_PATH),
        )
        self.assertEqual(
            self.manifest["tracked_logical_source"]["upstream_workbook_sha256"],
            builder.EXPECTED_WORKBOOK_SHA256,
        )
        for artifact in self.manifest["artifacts"].values():
            path = ROOT / artifact["path"]
            self.assertEqual(artifact["hash_normalization"], "lf_text")
            self.assertEqual(artifact["sha256"], lf_sha(path))


if __name__ == "__main__":
    unittest.main()
