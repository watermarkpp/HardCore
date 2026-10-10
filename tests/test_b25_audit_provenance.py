"""B25 provenance checks using current audit and drop-source inputs."""
import importlib.util
import hashlib
import json
import pathlib
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


def load(name):
    path = ROOT / "tools" / name
    spec = importlib.util.spec_from_file_location(name[:-3], path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class B25AuditProvenance(unittest.TestCase):
    def test_skill_marker_uses_current_manifest_and_ignores_old_pass(self):
        tool = load("generate_mir2_human_skill_audit.py")
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            current = root / "sample.stdout.log"
            runner = root / "runner.json"
            freeze = root / "freeze.json"
            binding = root / "binding.json"
            source_hash = hashlib.sha256((ROOT / "tools/generate_mir2_human_skill_audit.py").read_bytes()).hexdigest()
            test_path = "tests/sample.tscn"
            def write_case(text, result, exit_code, marker):
                current.write_text(text, encoding="utf-8")
                result_row = {"test_path": test_path, "effective_exit_code": exit_code, "pass_marker_found": marker, "process_exited": True, "cleanup_warning_evidence": {"raw_log_paths": [str(current)]}}
                runner.write_text(json.dumps({"source_content_sha256": source_hash, "invocation_id": "invoke-1", "results": [result_row]}), encoding="utf-8")
                freeze.write_text(json.dumps({"status": "PASS", "input_freeze_status": "PASS", "source_fingerprint": source_hash, "invocation_id": "invoke-1", "results": [{"test_path": test_path, "result": result, "effective_exit_code": exit_code}]}), encoding="utf-8")
                binding.write_text(json.dumps({"test_name": "sample", "runner_results_path": str(runner), "freeze_receipt_path": str(freeze), "test_path": test_path, "expected_marker": "CURRENT_SKILL_PASS", "raw_log_sha256": {str(current): hashlib.sha256(current.read_bytes()).hexdigest()}}), encoding="utf-8")
            old_logs, old_manifest = tool.TEST_LOGS, tool.CURRENT_RUN_MANIFEST
            try:
                tool.CURRENT_RUN_MANIFEST = binding
                write_case("CURRENT_SKILL_FAIL\n", "PASS", 0, False)
                self.assertEqual(tool.test_marker("sample")[0], "fail")
                write_case("CURRENT_SKILL_PASS\n", "PASS", 0, True)
                self.assertEqual(tool.test_marker("sample")[0], "pass")
                write_case("OTHER_TEST_PASS\n", "PASS", 0, True)
                self.assertEqual(tool.test_marker("sample")[0], "fail")
                write_case("CURRENT_SKILL_PASS\nCURRENT_SKILL_FAIL\n", "PASS", 0, True)
                self.assertEqual(tool.test_marker("sample")[0], "fail")
                write_case("CURRENT_SKILL_PASS\n", "PASS", 0, True)
                current.write_text("changed\n", encoding="utf-8")
                self.assertEqual(tool.test_marker("sample")[0], "not_run")
                write_case("CURRENT_SKILL_PASS\n", "PASS", 0, True)
                changed = json.loads(freeze.read_text())
                changed["source_fingerprint"] = "0" * 64
                freeze.write_text(json.dumps(changed))
                self.assertEqual(tool.test_marker("sample")[0], "not_run")
                binding.unlink()
                (root / "old.stdout.log").write_text("CURRENT_SKILL_PASS\n")
                self.assertEqual(tool.test_marker("sample")[0], "not_run")
            finally:
                tool.TEST_LOGS, tool.CURRENT_RUN_MANIFEST = old_logs, old_manifest

    def test_warrior_visual_classification_keeps_real_missing_effect_explicit(self):
        tool = load("generate_mir2_human_skill_audit.py")
        skills = json.loads(tool.SKILLS_PATH.read_text(encoding="utf-8"))
        magic = json.loads(tool.MAGIC_INFO_PATH.read_text(encoding="utf-8"))
        visuals = json.loads(tool.VISUALS_PATH.read_text(encoding="utf-8"))
        icons = json.loads(tool.WARRIOR_ICONS_PATH.read_text(encoding="utf-8"))
        if not tool.PARADOX_MAGIC_PATH.exists():
            external_magic = pathlib.Path(r"C:\Users\Administrator\Documents\HardCore\dev_art_sources\reference\mir2_database_candidates\mylgd_mir2server_176\Mud2\DB\Magic.DB")
            if not external_magic.exists():
                self.skipTest("DATA_MISSING: formal Magic.DB source is unavailable in this checkout")
            tool.PARADOX_MAGIC_PATH = external_magic
            tool.ROOT = external_magic.parents[6]
        paradox_rows, _ = tool.read_paradox_magic_db()
        base = {r["skill_id"]: r for r in skills["records"] if int(r["skillLevel"]) == 0}
        magic_rows = {r["skill_id"]: r for r in magic["records"]}
        paradox = {r["MagName"]: r for r in paradox_rows if int(r["MagID"]) <= 33}
        result = tool.build_visuals({}, sorted(base), base, magic_rows, paradox, visuals, icons)
        records = {r["skill_id"]: r for r in result["records"]}
        self.assertTrue(all(records[key]["visual_status"] == "formal_primary_client_warrior_action_effect" for key in (
            "warrior.fire_sword", "warrior.half_moon", "warrior.slaying_swordsmanship", "warrior.thrusting"
        )))
        self.assertEqual(records["warrior.wild_rush"]["visual_status"], "missing_formal_skill_effect")
        self.assertEqual(records["warrior.basic_swordsmanship"]["visual_status"], "no_runtime_visual_passive")
        consumption = json.loads((ROOT / "reports/skill_resource_consumption.json").read_text(encoding="utf-8"))
        unresolved = tool.build_unresolved({}, sorted(base), base, result, consumption)
        unresolved_by_id = {row["skill_id"]: row for row in unresolved["records"]}
        self.assertIn("formal per-skill visual binding is absent", unresolved_by_id["warrior.wild_rush"]["issues"])
        self.assertNotIn("formal per-skill visual binding is absent", unresolved_by_id["warrior.thrusting"]["issues"])
        mutated = json.loads(json.dumps(result))
        mutated["records"][0]["visual_status"] = "unregistered_status"
        mutated_unresolved = tool.build_unresolved({}, sorted(base), base, mutated, consumption)
        self.assertIn("UNKNOWN_VISUAL_STATUS", mutated_unresolved["records"][0]["error_classes"])

    def test_drop_source_provenance_fields_are_part_of_real_reconciliation(self):
        tool = load("import_canonical_monster_drop_excel.py")
        source = json.loads((ROOT / "assets/data/canonical_monster_drop_source_v2.json").read_text(encoding="utf-8"))
        required = {"source_distribution", "source_path", "source_sha256"}
        self.assertTrue(required.issubset(set(tool.RECORD_COMPARE_FIELDS)))
        self.assertEqual(len(source["records"]), 217)
        for record in source["records"]:
            self.assertTrue(required.issubset(record))
            self.assertTrue(record["source_distribution"])
            self.assertTrue(record["source_path"])
            self.assertEqual(record["source_sha256"], tool.EXPECTED_WORKBOOK_SHA256)
        self.assertEqual(tool._compare_record(source["records"][0], source["records"][0]), [])
        tampered_record = json.loads(json.dumps(source["records"][0], ensure_ascii=False))
        tampered_record["source_path"] += "::tampered"
        self.assertEqual(tool._compare_record(source["records"][0], tampered_record), ["source_path"])
        tampered_record = json.loads(json.dumps(source["records"][0], ensure_ascii=False))
        tampered_record["source_distribution"] = "not_the_formal_distribution"
        self.assertEqual(tool._compare_record(source["records"][0], tampered_record), ["source_distribution"])

        candidates = [
            ROOT / "热血传奇1.76_217怪物_完整掉落槽版.xlsx",
            pathlib.Path.home() / "Downloads" / "热血传奇1.76_217怪物_完整掉落槽版.xlsx",
        ]
        workbook_path = next((path for path in candidates if path.is_file()), None)
        if workbook_path is None:
            return
        workbook = tool.Workbook(workbook_path)
        expected = tool._build_source(workbook)
        self.assertEqual(tool._check(workbook, expected, source), 0)
        tampered = json.loads(json.dumps(source, ensure_ascii=False))
        tampered["records"][0]["source_path"] += "::tampered"
        self.assertNotEqual(tool._check(workbook, expected, tampered), 0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
