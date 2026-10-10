#!/usr/bin/env python3
"""Focused B07A regression tests for the bounded correction check-only mode."""

from __future__ import annotations

import hashlib
import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def load_builder():
    spec = importlib.util.spec_from_file_location(
        "build_equipment_attribute_master", ROOT / "tools/build_equipment_attribute_master.py"
    )
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class EquipmentCorrectionCheckOnlyTest(unittest.TestCase):
    def _copy_authority_inputs(self, directory: Path) -> tuple[Path, Path]:
        master = directory / "equipment_attribute_master.json"
        items = directory / "items.json"
        master.write_bytes((ROOT / "assets/data/equipment_attribute_master.json").read_bytes())
        items.write_bytes((ROOT / "assets/data/vanilla_176/items.json").read_bytes())
        return master, items

    def test_check_only_does_not_write_authority_files(self):
        builder = load_builder()
        with tempfile.TemporaryDirectory() as directory:
            temp = Path(directory)
            master, items = self._copy_authority_inputs(temp)
            before_master = hashlib.sha256(master.read_bytes()).digest()
            before_items = hashlib.sha256(items.read_bytes()).digest()
            builder.MASTER_PATH = master
            builder.ITEMS_PATH = items
            audit = builder.apply_female_armor_correction_only(
                write_outputs=False,
                audit_output=temp / "check-only-audit.json",
            )
            self.assertFalse(audit["writeOutputs"])
            self.assertEqual(12, audit["femaleArmorCorrectionCount"])
            self.assertEqual(before_master, hashlib.sha256(master.read_bytes()).digest())
            self.assertEqual(before_items, hashlib.sha256(items.read_bytes()).digest())
            self.assertTrue((temp / "check-only-audit.json").is_file())

    def test_cli_check_only_entrypoint_does_not_write_authority_files(self):
        builder = load_builder()
        with tempfile.TemporaryDirectory() as directory:
            temp = Path(directory)
            master, items = self._copy_authority_inputs(temp)
            before_master = hashlib.sha256(master.read_bytes()).digest()
            before_items = hashlib.sha256(items.read_bytes()).digest()
            audit = temp / "cli-check-only-audit.json"
            builder.MASTER_PATH = master
            builder.ITEMS_PATH = items
            old_argv = sys.argv
            try:
                sys.argv = [
                    "build_equipment_attribute_master.py",
                    "--female-armor-correction-only",
                    "--check-only",
                    "--audit-output",
                    str(audit),
                ]
                builder.main()
            finally:
                sys.argv = old_argv
            self.assertEqual(before_master, hashlib.sha256(master.read_bytes()).digest())
            self.assertEqual(before_items, hashlib.sha256(items.read_bytes()).digest())
            self.assertEqual(False, json.loads(audit.read_text(encoding="utf-8"))["writeOutputs"])

    def test_audit_output_cannot_alias_authority(self):
        builder = load_builder()
        with tempfile.TemporaryDirectory() as directory:
            master, items = self._copy_authority_inputs(Path(directory))
            builder.MASTER_PATH = master
            builder.ITEMS_PATH = items
            with self.assertRaises(ValueError):
                builder.apply_female_armor_correction_only(
                    write_outputs=False, audit_output=master
                )

    def test_write_mode_is_bounded_to_temp_authority_copies(self):
        builder = load_builder()
        with tempfile.TemporaryDirectory() as directory:
            temp = Path(directory)
            master, items = self._copy_authority_inputs(temp)
            before_master = json.loads(master.read_text(encoding="utf-8"))
            before_items = json.loads(items.read_text(encoding="utf-8"))
            builder.MASTER_PATH = master
            builder.ITEMS_PATH = items
            audit = builder.apply_female_armor_correction_only(write_outputs=True)
            self.assertTrue(audit["writeOutputs"])
            after_master = json.loads(master.read_text(encoding="utf-8"))
            after_items = json.loads(items.read_text(encoding="utf-8"))
            self.assertEqual(175, len(after_master["records"]))
            self.assertEqual(175, len(after_items["records"]))
            target_ids = set(builder.FEMALE_ARMOR_PAIRS)
            before_master_by_id = {int(r["itemId"]): r for r in before_master["records"]}
            after_master_by_id = {int(r["itemId"]): r for r in after_master["records"]}
            before_items_by_id = {int(r["itemId"]): r for r in before_items["records"]}
            after_items_by_id = {int(r["itemId"]): r for r in after_items["records"]}
            for item_id in before_master_by_id.keys() - target_ids:
                self.assertEqual(before_master_by_id[item_id], after_master_by_id[item_id])
            for item_id in before_items_by_id.keys() - target_ids:
                self.assertEqual(before_items_by_id[item_id], after_items_by_id[item_id])


if __name__ == "__main__":
    unittest.main()
