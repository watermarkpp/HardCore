#!/usr/bin/env python3
"""B07A regressions for the equipment generator's coupled authority write set."""

from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "equipment_generator", ROOT / "tools/build_equipment_attribute_master.py"
)
BUILDER = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(BUILDER)


class EquipmentGeneratorWriteSetTests(unittest.TestCase):
    def _paths(self, directory: Path) -> tuple[Path, Path]:
        return directory / "master.json", directory / "items.json"

    def test_normal_publish_updates_both_outputs_and_cleans_stage(self):
        with tempfile.TemporaryDirectory() as directory:
            master, items = self._paths(Path(directory))
            master.write_bytes(b'{"old":"master"}\n')
            items.write_bytes(b'{"old":"items"}\n')
            new_master = b'{"new":"master"}\n'
            new_items = b'{"new":"items"}\n'

            BUILDER.publish_equipment_write_set(
                {master: new_master, items: new_items}
            )

            self.assertEqual(new_master, master.read_bytes())
            self.assertEqual(new_items, items.read_bytes())
            self.assertEqual([], list(Path(directory).glob(".*.tmp")))

    def test_second_replace_failure_restores_first_output(self):
        with tempfile.TemporaryDirectory() as directory:
            master, items = self._paths(Path(directory))
            old_master = b'{"old":"master"}\n'
            old_items = b'{"old":"items"}\n'
            master.write_bytes(old_master)
            items.write_bytes(old_items)
            new_master = b'{"new":"master"}\n'
            new_items = b'{"new":"items"}\n'
            real_replace = BUILDER.os.replace

            def fail_items(source: str | bytes | Path, destination: str | bytes | Path):
                if Path(destination) == items and ".writeset-" in str(source):
                    raise OSError("simulated second authority replace failure")
                return real_replace(source, destination)

            with mock.patch.object(BUILDER.os, "replace", side_effect=fail_items):
                with self.assertRaisesRegex(RuntimeError, "publish failed"):
                    BUILDER.publish_equipment_write_set(
                        {master: new_master, items: new_items}
                    )

            self.assertEqual(old_master, master.read_bytes())
            self.assertEqual(old_items, items.read_bytes())
            self.assertEqual([], list(Path(directory).glob(".*.tmp")))

    def test_first_replace_failure_leaves_both_outputs_unchanged(self):
        with tempfile.TemporaryDirectory() as directory:
            master, items = self._paths(Path(directory))
            old_master = b'{"old":"master"}\n'
            old_items = b'{"old":"items"}\n'
            master.write_bytes(old_master)
            items.write_bytes(old_items)
            real_replace = BUILDER.os.replace

            def fail_master(source: str | bytes | Path, destination: str | bytes | Path):
                if Path(destination) == master and ".writeset-" in str(source):
                    raise OSError("simulated first authority replace failure")
                return real_replace(source, destination)

            with mock.patch.object(BUILDER.os, "replace", side_effect=fail_master):
                with self.assertRaises(RuntimeError):
                    BUILDER.publish_equipment_write_set(
                        {master: b'{"new":"master"}\n', items: b'{"new":"items"}\n'}
                    )

            self.assertEqual(old_master, master.read_bytes())
            self.assertEqual(old_items, items.read_bytes())
            self.assertEqual([], list(Path(directory).glob(".*.tmp")))

    def test_missing_output_is_restored_to_missing_state_after_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            master, items = self._paths(Path(directory))
            old_master = b'{"old":"master"}\n'
            master.write_bytes(old_master)
            new_master = b'{"new":"master"}\n'
            new_items = b'{"new":"items"}\n'
            real_replace = BUILDER.os.replace

            def fail_items(source: str | bytes | Path, destination: str | bytes | Path):
                if Path(destination) == items and ".writeset-" in str(source):
                    raise OSError("simulated missing-target replace failure")
                return real_replace(source, destination)

            with mock.patch.object(BUILDER.os, "replace", side_effect=fail_items):
                with self.assertRaises(RuntimeError):
                    BUILDER.publish_equipment_write_set(
                        {master: new_master, items: new_items}
                    )

            self.assertEqual(old_master, master.read_bytes())
            self.assertFalse(items.exists())

    def test_first_originally_missing_output_is_removed_after_second_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            master, items = self._paths(Path(directory))
            old_items = b'{"old":"items"}\n'
            items.write_bytes(old_items)
            real_replace = BUILDER.os.replace

            def fail_items(source: str | bytes | Path, destination: str | bytes | Path):
                if Path(destination) == items and ".writeset-" in str(source):
                    raise OSError("simulated second authority replace failure")
                return real_replace(source, destination)

            with mock.patch.object(BUILDER.os, "replace", side_effect=fail_items):
                with self.assertRaises(RuntimeError):
                    BUILDER.publish_equipment_write_set(
                        {master: b'{"new":"master"}\n', items: b'{"new":"items"}\n'}
                    )

            self.assertFalse(master.exists())
            self.assertEqual(old_items, items.read_bytes())
            self.assertEqual([], list(Path(directory).glob(".*.tmp")))

    def test_intervening_manual_change_is_preserved_and_publish_fails_closed(self):
        with tempfile.TemporaryDirectory() as directory:
            master, items = self._paths(Path(directory))
            old_master = b'{"old":"master"}\n'
            old_items = b'{"old":"items"}\n'
            manual_items = b'{"manual":"edit"}\n'
            master.write_bytes(old_master)
            items.write_bytes(old_items)
            new_master = b'{"new":"master"}\n'
            new_items = b'{"new":"items"}\n'
            real_replace = BUILDER.os.replace

            def mutate_items_after_first_replace(
                source: str | bytes | Path, destination: str | bytes | Path
            ):
                result = real_replace(source, destination)
                if Path(destination) == master and ".writeset-" in str(source):
                    items.write_bytes(manual_items)
                return result

            with mock.patch.object(
                BUILDER.os, "replace", side_effect=mutate_items_after_first_replace
            ):
                with self.assertRaisesRegex(RuntimeError, "changed before replace"):
                    BUILDER.publish_equipment_write_set(
                        {master: new_master, items: new_items}
                    )

            self.assertEqual(old_master, master.read_bytes())
            self.assertEqual(manual_items, items.read_bytes())
            self.assertEqual([], list(Path(directory).glob(".*.tmp")))

    def test_rollback_replace_failure_retains_original_backup(self):
        with tempfile.TemporaryDirectory() as directory:
            master, items = self._paths(Path(directory))
            old_master = b'{"old":"master"}\n'
            old_items = b'{"old":"items"}\n'
            master.write_bytes(old_master)
            items.write_bytes(old_items)
            real_replace = BUILDER.os.replace

            def fail_rollback(source: str | bytes | Path, destination: str | bytes | Path):
                if Path(destination) == items and ".writeset-" in str(source):
                    raise OSError("simulated second authority replace failure")
                if Path(destination) == master and ".rollback-" in str(source):
                    raise OSError("simulated rollback replace failure")
                return real_replace(source, destination)

            with mock.patch.object(BUILDER.os, "replace", side_effect=fail_rollback):
                with self.assertRaisesRegex(RuntimeError, "original backup retained") as failure:
                    BUILDER.publish_equipment_write_set(
                        {master: b'{"new":"master"}\n', items: b'{"new":"items"}\n'}
                    )

            self.assertIn("master.json", str(failure.exception))
            # The failed rollback does not overwrite the current published
            # bytes; the original bytes remain available in the retained file.
            self.assertEqual(b'{"new":"master"}\n', master.read_bytes())
            self.assertEqual(old_items, items.read_bytes())
            retained = list(Path(directory).glob(".master.json.rollback-*.tmp"))
            self.assertEqual(1, len(retained))
            self.assertEqual(old_master, retained[0].read_bytes())

    def test_rollback_read_failure_retains_original_backup_and_continues(self):
        with tempfile.TemporaryDirectory() as directory:
            master, items = self._paths(Path(directory))
            old_master = b'{"old":"master"}\n'
            old_items = b'{"old":"items"}\n'
            master.write_bytes(old_master)
            items.write_bytes(old_items)
            real_replace = BUILDER.os.replace
            fail_read = {"enabled": False}

            def fail_items(source: str | bytes | Path, destination: str | bytes | Path):
                if Path(destination) == items and ".writeset-" in str(source):
                    fail_read["enabled"] = True
                    raise OSError("simulated second authority replace failure")
                return real_replace(source, destination)

            original_read_bytes = Path.read_bytes

            def fail_master_read(self: Path):
                if fail_read["enabled"] and self == master:
                    fail_read["enabled"] = "consumed"
                    raise OSError("simulated rollback read failure")
                return original_read_bytes(self)

            with mock.patch.object(BUILDER.os, "replace", side_effect=fail_items):
                with mock.patch.object(Path, "read_bytes", autospec=True, side_effect=fail_master_read):
                    with self.assertRaisesRegex(RuntimeError, "rollback read failed") as failure:
                        BUILDER.publish_equipment_write_set(
                            {master: b'{"new":"master"}\n', items: b'{"new":"items"}\n'}
                        )

            self.assertIn("master.json", str(failure.exception))
            self.assertEqual(b'{"new":"master"}\n', master.read_bytes())
            self.assertEqual(old_items, items.read_bytes())
            retained = list(Path(directory).glob(".master.json.rollback-*.tmp"))
            self.assertEqual(1, len(retained))
            self.assertEqual(old_master, retained[0].read_bytes())

    def test_real_correction_entrypoint_rolls_back_second_replace_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            temp = Path(directory)
            master, items = self._paths(temp)
            master.write_bytes((ROOT / "assets/data/equipment_attribute_master.json").read_bytes())
            items.write_bytes((ROOT / "assets/data/vanilla_176/items.json").read_bytes())
            old_master = master.read_bytes()
            old_items = items.read_bytes()
            old_master_path, old_items_path = BUILDER.MASTER_PATH, BUILDER.ITEMS_PATH
            real_replace = BUILDER.os.replace
            try:
                BUILDER.MASTER_PATH, BUILDER.ITEMS_PATH = master, items

                def fail_items(source: str | bytes | Path, destination: str | bytes | Path):
                    if Path(destination) == items and ".writeset-" in str(source):
                        raise OSError("simulated correction second replace failure")
                    return real_replace(source, destination)

                with mock.patch.object(BUILDER.os, "replace", side_effect=fail_items):
                    with self.assertRaises(RuntimeError):
                        BUILDER.apply_female_armor_correction_only(write_outputs=True)
            finally:
                BUILDER.MASTER_PATH, BUILDER.ITEMS_PATH = old_master_path, old_items_path

            self.assertEqual(old_master, master.read_bytes())
            self.assertEqual(old_items, items.read_bytes())
            self.assertEqual([], list(temp.glob(".*.tmp")))


if __name__ == "__main__":
    unittest.main()
