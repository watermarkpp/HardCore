import importlib.util
import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("mir2_import", ROOT / "tools/import_mir2_server_data.py")
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


class Mir2ServerImportTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = ROOT / "tests/fixtures/mir2_server"
        cls.manifest = MODULE.load_manifest(cls.source)

    def test_all_supported_sources_parse(self):
        maps, portals = MODULE.parse_map_info(self.source / "Envir/MapInfo.txt", self.source, self.manifest)
        spawns = MODULE.parse_mon_gen(self.source / "Envir/MonGen.txt", self.source, self.manifest)
        drops = MODULE.parse_mon_items(self.source / "Envir/MonItems", self.source, self.manifest)
        merchants = MODULE.parse_merchants(self.source / "Envir/Merchant.txt", self.source, self.manifest)
        tasks = MODULE.parse_task_scripts(self.source / "Envir/Market_Def", self.source, self.manifest)
        monsters, _, error = MODULE.read_table(self.source, "Monster")
        self.assertEqual((len(maps), len(portals), len(spawns), len(drops), len(monsters)), (2, 1, 2, 3, 2))
        self.assertIsNone(error)
        self.assertEqual(maps[0]["versionTag"], MODULE.BASELINE)
        self.assertEqual(drops[1]["denominator"], 20)
        self.assertEqual((len(merchants), len(tasks)), (1, 1))

    def test_dry_run_never_changes_runtime_database(self):
        before = MODULE.PROJECT_DATA.read_bytes()
        report = MODULE.run_import(self.source, apply=False)
        after = MODULE.PROJECT_DATA.read_bytes()
        self.assertEqual(before, after)
        self.assertEqual(report["parsed"]["bosses"], 1)
        self.assertEqual(report["parsed"]["skills"], 4)
        self.assertEqual(report["parsed"]["tasks"], 1)
        self.assertEqual(report["parsed"]["serverMerchants"], 1)
        self.assertEqual(report["missing"], [])
        candidate = json.loads(MODULE.OUTPUT_DATA.read_text(encoding="utf-8"))
        self.assertEqual(candidate["bosses"][0]["name"], "骷髅精灵")

    def test_late_content_tag_isolated(self):
        fake = self.source / "Envir/MonGen_幻境.txt"
        self.assertEqual(MODULE.source_version(fake, self.source, self.manifest), MODULE.LATE_CONTENT)

    def test_nested_mir200_root_is_detected(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            shutil.copytree(self.source, root / "MirServer" / "Mir200")
            data_root, discovery = MODULE.detect_data_root(root)
            self.assertEqual(data_root, (root / "MirServer" / "Mir200").resolve())
            self.assertEqual(discovery[0]["score"], 8)

    def test_apply_requires_explicit_version_manifest(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "Envir").mkdir()
            with self.assertRaisesRegex(ValueError, "import_manifest"):
                MODULE.run_import(root, apply=True)


if __name__ == "__main__":
    unittest.main()
