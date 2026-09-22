from __future__ import annotations

import importlib.util
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
TOOL_PATH = ROOT / "tools/build_dpv2_21cq_direct_baseline.py"
SPEC = importlib.util.spec_from_file_location("dpv2_21cq_builder", TOOL_PATH)
assert SPEC is not None and SPEC.loader is not None
builder = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(builder)


class SourceAuditTests(unittest.TestCase):
    def test_full_source_ledger_closes(self) -> None:
        audit = builder.parse_source()
        metrics = audit["metrics"]
        self.assertEqual(metrics["logical_monster_records"], 217)
        self.assertEqual(metrics["logical_source_rows"], 9590)
        self.assertEqual(metrics["parsed_rows_after_correction"], 9590)
        self.assertEqual(metrics["uncorrected_invalid_probability_rows"], 0)

    def test_only_invalid_source_token_is_explicitly_corrected(self) -> None:
        audit = builder.parse_source()
        self.assertEqual(len(audit["invalid_source_rows"]), 1)
        self.assertEqual(len(audit["corrected_rows"]), 1)
        invalid = audit["invalid_source_rows"][0]
        correction = audit["corrected_rows"][0]
        self.assertEqual(
            (invalid["monster_id"], invalid["line_number"], invalid["chance"]),
            (168, 20, "1/00"),
        )
        self.assertEqual(
            (
                correction["corrected_base_numerator"],
                correction["corrected_base_denominator"],
            ),
            (1, 2800),
        )

    def test_duplicate_rows_are_retained(self) -> None:
        audit = builder.parse_source()
        metrics = audit["metrics"]
        self.assertGreater(metrics["duplicate_item_rows_beyond_first"], 0)
        self.assertGreater(metrics["exact_duplicate_rows_beyond_first"], 0)
        slot_keys = {
            (row["monster_id"], row["slot_index"])
            for row in audit["parsed_rows"]
        }
        self.assertEqual(len(slot_keys), 9590)

    def test_source_is_logical_json_not_physical_monitems(self) -> None:
        metrics = builder.parse_source()["metrics"]
        self.assertEqual(metrics["physical_raw_monitems_files_in_git"], 0)
        self.assertEqual(metrics["tracked_encoding"], "UTF-8 JSON")
        self.assertEqual(metrics["physical_monitems_encoding"], "NOT_AVAILABLE_IN_GIT")


if __name__ == "__main__":
    unittest.main()
