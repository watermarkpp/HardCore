#!/usr/bin/env python3
"""Focused regression tests for the precise authored-placement migration.

This is a standalone Python test (not a production Godot suite entry) so it
can validate the frozen snapshot, exact row projections, and release freeze
without invoking map build/publish code.
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import subprocess
import sys
import unittest
from pathlib import Path
from typing import Any


TOOL_PATH = Path(__file__).resolve().parents[1] / "map_editor" / "migrate_precise_map_placements.py"
SPEC = importlib.util.spec_from_file_location("precise_migration", TOOL_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"cannot load migration tool: {TOOL_PATH}")
MIGRATION = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MIGRATION)

_TEST_SOURCE_ROOT: Path | None = None
_TEST_TARGET_ROOT: Path | None = None


def _read_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8-sig"))


class PrecisePlacementMigrationTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if _TEST_SOURCE_ROOT is None:
            parser = argparse.ArgumentParser(add_help=False)
            parser.add_argument("--source-root", required=True)
            parser.add_argument("--target-root", default=str(TOOL_PATH.parents[2]))
            parsed, _ = parser.parse_known_args()
            cls.source_root = Path(parsed.source_root).resolve()
            cls.target_root = Path(parsed.target_root).resolve()
        else:
            cls.source_root = _TEST_SOURCE_ROOT
            cls.target_root = _TEST_TARGET_ROOT or TOOL_PATH.parents[2]
        cls.registry = _read_json(cls.target_root / MIGRATION.REGISTRY_REL)
        cls.catalog = _read_json(cls.target_root / MIGRATION.CATALOG_REL)
        cls.audit_path = cls.target_root / MIGRATION.AUDIT_REL
        cls.audit = _read_json(cls.audit_path)
        cls.mappings = MIGRATION.validate_registry(cls.registry)

    def test_manifest_summary_and_all_zero_gaps(self) -> None:
        self.assertEqual(len(self.mappings), 67)
        self.assertEqual(self.audit["summary"]["monster_spawn"], 1607)
        self.assertEqual(self.audit["summary"]["boss_spawn"], 273)
        self.assertEqual(self.audit["summary"]["total"], 1880)
        checks = self.audit["checks"]
        for key in (
            "unknown_monster_count",
            "disabled_monster_count",
            "illegal_layer_placement_count",
            "missing_authority_count",
            "missing_semantic_count",
            "missing_spawn_group_count",
            "semantic_duplicate_count",
            "spawn_group_duplicate_count",
            "non_identity_diff_count",
            "target_non_spawn_diff_count",
            "sandbox_migrated_count",
        ):
            self.assertEqual(checks[key], 0, key)
        self.assertEqual(self.audit["special_normal"]["placement_count"], 8)
        self.assertEqual(
            self.audit["special_normal"]["canonical_ids"],
            [39, 57, 74, 77, 90, 121, 137, 142],
        )

    def test_every_target_row_is_exact_source_projection(self) -> None:
        semantics: set[str] = set()
        groups: set[str] = set()
        target_count = {layer: 0 for layer in MIGRATION.LAYERS}
        for mapping in self.mappings:
            legacy = mapping["legacy_map_id"]
            formal = mapping["map_id"]
            source_path = MIGRATION.document_path(self.source_root, legacy)
            target_path = MIGRATION.document_path(self.target_root, formal)
            source = _read_json(source_path)
            target = _read_json(target_path)
            self.assertEqual(target["map_id"], formal)
            record = next(row for row in self.audit["maps"] if row["legacy_map_id"] == legacy)
            self.assertEqual(record["source_document_sha256"], MIGRATION.sha256_file(source_path))
            for layer in MIGRATION.LAYERS:
                source_rows = source["layers"][layer]
                target_rows = target["layers"][layer]
                target_count[layer] += len(target_rows)
                self.assertEqual(len(source_rows), len(target_rows), f"{formal}:{layer}")
                for index, source_row in enumerate(source_rows):
                    expected = MIGRATION.project_row_identity(source_row, formal, layer, index + 1)
                    self.assertEqual(
                        MIGRATION.canonical_json_bytes(target_rows[index]),
                        MIGRATION.canonical_json_bytes(expected),
                        f"row mismatch {formal}:{layer}:{index}",
                    )
                    semantic = target_rows[index].get("semantic_id")
                    group = target_rows[index].get("spawn_group_id")
                    self.assertIsInstance(semantic, str)
                    self.assertIsInstance(group, str)
                    self.assertNotIn(semantic, semantics)
                    self.assertNotIn(group, groups)
                    semantics.add(semantic)
                    groups.add(group)
                # The source document's full non-spawn payload is not copied
                # into the target; the existing formal target payload must be
                # preserved byte-semantically around the two replaced layers.
                baseline = subprocess.check_output(
                    ["git", "show", f"HEAD:{MIGRATION.relative_posix(target_path, self.target_root)}"],
                    cwd=self.target_root,
                )
                baseline_doc = json.loads(baseline.decode("utf-8-sig"))
                self.assertEqual(
                    MIGRATION.non_spawn_fingerprint(baseline_doc),
                    MIGRATION.non_spawn_fingerprint(target),
                    f"non-spawn changed {formal}",
                )
        self.assertEqual(target_count, {"monster_spawn": 1607, "boss_spawn": 273})
        self.assertEqual(len(semantics), 1880)
        self.assertEqual(len(groups), 1880)

    def test_special_normal_and_release_freeze(self) -> None:
        special = set(self.audit["special_normal"]["canonical_ids"])
        found: dict[int, dict[str, Any]] = {}
        for mapping in self.mappings:
            target = _read_json(MIGRATION.document_path(self.target_root, mapping["map_id"]))
            for row in target["layers"]["monster_spawn"]:
                monster_id = int(row["monster_id"])
                if monster_id in special:
                    self.assertNotIn(monster_id, found)
                    self.assertEqual(row["kind"], "monster_spawn")
                    self.assertEqual(int(row["count"]), 1)
                    self.assertEqual(int(row["max_alive"]), 1)
                    found[monster_id] = row
        self.assertEqual(set(found), special)
        release = MIGRATION.runtime_release_fingerprint(self.target_root)
        self.assertEqual(release, self.audit["release_freeze"])
        sandbox = self.target_root / "map_editor_workspace" / "sandbox_64" / "sandbox_64.editor.json"
        self.assertEqual(self.audit["sandbox_excluded"]["target_document_sha256_after"], MIGRATION.sha256_file(sandbox))
        self.assertEqual(self.audit["sandbox_excluded"]["migrated_count"], 0)

    def test_target_lineage_and_frozen_release_baseline(self) -> None:
        self.assertTrue(MIGRATION.verify_target_baseline_lineage(self.target_root))
        expected = {
            "runtime_release_fingerprint_sha256": MIGRATION.EXPECTED_RELEASE_RUNTIME_FINGERPRINT_SHA256,
            "registry_raw_sha256": MIGRATION.EXPECTED_RELEASE_REGISTRY_SHA256,
        }
        release = MIGRATION.runtime_release_fingerprint(self.target_root)
        MIGRATION.assert_release_baseline(release)
        self.assertEqual(release["canonical_sha256"], MIGRATION.EXPECTED_RELEASE_RUNTIME_FINGERPRINT_SHA256)
        self.assertEqual(release["registry_sha256"], MIGRATION.EXPECTED_RELEASE_REGISTRY_SHA256)
        self.assertEqual(release["baseline_expected"], expected)
        self.assertEqual(release["baseline_actual"], expected)
        self.assertEqual(
            self.audit["baseline"]["target_git_head"],
            MIGRATION.BASELINE_TARGET_HEAD,
        )
        self.assertNotIn("current_git_head", self.audit["baseline"])
        self.assertNotIn("target_current_git_head", self.audit["baseline"])
        self.assertTrue(self.audit["baseline"]["target_baseline_lineage_verified"])
        self.assertEqual(self.audit["release_freeze"], release)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--source-root", required=True)
    parser.add_argument("--target-root", default=str(TOOL_PATH.parents[2]))
    parsed, remaining = parser.parse_known_args()
    _TEST_SOURCE_ROOT = Path(parsed.source_root).resolve()
    _TEST_TARGET_ROOT = Path(parsed.target_root).resolve()
    raise SystemExit(unittest.main(argv=[sys.argv[0], *remaining]))
