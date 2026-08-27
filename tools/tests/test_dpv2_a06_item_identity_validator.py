#!/usr/bin/env python3
"""Focused tests for the data-only DPV2 A0.6 item identity closure."""

from __future__ import annotations

import copy
import importlib.util
import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
VALIDATOR_PATH = ROOT / "tools" / "dpv2_a06_item_identity_validator.py"
AUTHORITY_PATH = ROOT / "assets" / "data" / "drop" / "dpv2_item_identity_authority_v1.json"
SNAPSHOT_PATH = ROOT / "outputs" / "monster_drop_p1a" / "runtime_snapshot.json"
CATALOG_PATH = ROOT / "assets" / "data" / "service_item_catalog.json"

_SPEC = importlib.util.spec_from_file_location(
    "dpv2_a06_item_identity_validator", VALIDATOR_PATH
)
if _SPEC is None or _SPEC.loader is None:
    raise RuntimeError(f"cannot load validator: {VALIDATOR_PATH}")
_VALIDATOR = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(_VALIDATOR)


def _load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


class Dpv2A06ItemIdentityValidatorTests(unittest.TestCase):
    def test_closure_is_233_positive_unique_with_exact_53_overlay(self) -> None:
        result = _VALIDATOR.validate_authority(repo_root=ROOT)
        self.assertEqual(result["status"], "PASS")
        self.assertEqual(result["authority_records"], 53)
        self.assertEqual(result["p1a_normalized_items"], 233)
        self.assertEqual(result["p1a_existing_positive_items"], 180)
        self.assertEqual(result["p1a_missing_items"], 53)
        self.assertEqual(result["overlay_positive_unique_items"], 233)
        self.assertEqual(result["new_allocated_count"], 53)
        self.assertEqual(result["existing_formal_bindings"], 0)
        self.assertEqual(result["reserved_interval"], [920001, 920053])
        self.assertEqual(result["reserved_interval_collision_count"], 0)
        self.assertEqual(result["reserved_text_collision_count"], 0)
        self.assertTrue(result["user_authoritative_override_verified"])
        self.assertFalse(result["runtime_production_consumption"])
        self.assertFalse(result["persistence_production_consumption"])

    def test_each_record_is_explicit_and_service_index_is_locator_only(self) -> None:
        authority = _load(AUTHORITY_PATH)
        records = authority["records"]
        self.assertEqual(len(records), 53)
        self.assertEqual(
            authority["identity_policy"]["service_index_role"],
            "legacy_source_locator_plus_provenance_only",
        )
        forbidden = {"item_id", "itemId", "stableItemId", "service_index", "serviceIndex"}
        self.assertTrue(all(not forbidden.intersection(record) for record in records))
        self.assertEqual(
            [record["canonical_item_id"] for record in records],
            list(range(920001, 920054)),
        )
        self.assertEqual(
            [record["current_canonical_item_id"] for record in records],
            [-1] * 53,
        )

    def test_duplicate_canonical_id_is_rejected(self) -> None:
        authority = _load(AUTHORITY_PATH)
        snapshot = _load(SNAPSHOT_PATH)
        catalog = _load(CATALOG_PATH)
        mutated = copy.deepcopy(authority)
        mutated["records"][1]["canonical_item_id"] = mutated["records"][0]["canonical_item_id"]
        with self.assertRaises(_VALIDATOR.AuthorityValidationError):
            _VALIDATOR.validate_authority_documents(
                mutated,
                snapshot,
                catalog,
                repo_root=ROOT,
                authority_path=AUTHORITY_PATH,
            )


if __name__ == "__main__":
    unittest.main()
