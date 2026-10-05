"""Real-engine tests of the portable formal validation entry point."""
from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class FingerprintIdentityTests(unittest.TestCase):
    def test_commit_change_invalidates_otherwise_identical_source(self):
        from tools import source176_r3_validation as validation
        before = {"files": {"owned.gd": "same"}, "tested_sha": "commit-a", "branch": "candidate",
                  "engine_sha256": "engine", "shell_sha256": "shell", "native_launcher_sha256": "launcher"}
        after = {**before, "tested_sha": "commit-b"}
        self.assertTrue(hasattr(validation, "identity_is_stable"), "source driver lacks commit identity gate")
        self.assertFalse(validation.identity_is_stable(before, after))
        self.assertTrue(validation.identity_is_stable(before, before))


class CloudValidationTests(unittest.TestCase):
    attempts = []

    @classmethod
    def tearDownClass(cls):
        index = ROOT / "outputs/cloud_continuation_20261005/runner_self_test_index.json"
        index.parent.mkdir(parents=True, exist_ok=True)
        index.write_text(json.dumps({"attempts": cls.attempts}, ensure_ascii=False, indent=2))

    def invoke(self, scene: str | list[str], label: str, timeout: int = 30, overrides=None):
        scenes = [scene] if isinstance(scene, str) else scene
        result = subprocess.run(
            [sys.executable, str(ROOT / "tools/source176_r3_validation.py"),
             label, "--tests", *scenes, "--timeout", str(timeout)],
            cwd=ROOT, env={**os.environ, **(overrides or {})}, capture_output=True, text=True,
            timeout=timeout * len(scenes) + 40,
        )
        records = []
        for line in result.stdout.splitlines():
            try:
                value = json.loads(line)
                if "evidence" in value:
                    records.append(value)
            except (ValueError, TypeError):
                pass
        self.assertTrue(records, result.stdout + result.stderr)
        self.attempts.append({"test": self.id(), **records[-1]})
        return result, records[-1], Path(records[-1]["evidence"])

    def test_symlink_userdata_is_rejected_before_native_writes(self):
        external = ROOT.parent / ".hardcore-cloud/probes"
        external.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=external) as target:
            link = ROOT / ".godot/runtime_appdata" / ("link_" + Path(target).name)
            link.symlink_to(target, target_is_directory=True)
            try:
                native, summary, evidence = self.invoke(
                    "tests/framework/fixtures/proof_positive_control.tscn", "linux_link_userdata",
                    overrides={"HARDCORE_AUDIT_RUNTIME_APPDATA": str(link)})
                self.assertEqual(native.returncode, 1, summary)
                self.assertEqual(list(Path(target).iterdir()), [], "native launch wrote outside checkout")
                self.assertIn("symlink", (evidence / "runner.log").read_text().lower())
            finally:
                link.unlink()

    def test_owned_orphan_pipe_is_rejected_and_bounded(self):
        import time
        started = time.monotonic()
        _, summary, evidence = self.invoke(
            "tests/framework/fixtures/proof_orphan_pipe.tscn", "linux_orphan_pipe")
        elapsed = time.monotonic() - started
        self.assertLess(elapsed, 35, "native parent exit left an unbounded pipe drain")
        self.assertEqual(summary["status"], "FAIL")
        report = json.loads((evidence / "runner_results.json").read_text(encoding="utf-8-sig"))
        row = report["results"][0]
        self.assertEqual(row["effective_exit_code"], 0)
        self.assertIn("lingering_native_children", row["reason"])
        handoff = json.loads((evidence / "framework/native_handoffs.json").read_text())
        self.assertEqual(handoff["producers"], {})

    def test_orphan_cleanup_preserves_another_native_engine(self):
        import time
        from tools import source176_r3_validation as validation
        log_root = ROOT / "outputs/cloud_continuation_20261005/peer_probe"
        log_root.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=ROOT / ".godot/runtime_appdata") as userdata:
            with (log_root / "stdout.log").open("wb") as stdout, (log_root / "stderr.log").open("wb") as stderr:
                peer = subprocess.Popen(
                    [str(validation.engine_path()), "--headless", "--path", str(ROOT), "--max-fps", "60",
                     "--log-file", str(log_root / "engine.log"), "tests/runner_fixtures/case4_pass_then_hang.tscn"],
                    cwd=ROOT, env={**os.environ, "APPDATA": userdata, "XDG_DATA_HOME": userdata},
                    stdout=stdout, stderr=stderr, start_new_session=True)
                try:
                    deadline = time.monotonic() + 20
                    while b"Q0A_SELF_CASE4_PASS" not in (log_root / "stdout.log").read_bytes() and peer.poll() is None and time.monotonic() < deadline:
                        time.sleep(0.1)
                    self.assertIsNone(peer.poll(), "peer engine exited before ownership probe")
                    self.assertIn(b"Q0A_SELF_CASE4_PASS", (log_root / "stdout.log").read_bytes())
                    _, summary, _ = self.invoke(
                        "tests/framework/fixtures/proof_orphan_pipe.tscn", "linux_orphan_with_peer")
                    self.assertEqual(summary["status"], "FAIL")
                    self.assertIsNone(peer.poll(), "runner killed another engine process")
                finally:
                    if peer.poll() is None:
                        peer.terminate()
                        try: peer.wait(timeout=5)
                        except subprocess.TimeoutExpired:
                            peer.kill(); peer.wait(timeout=5)

    def test_positive_control_has_native_receipt_and_owned_userdata(self):
        native, summary, evidence = self.invoke(
            "tests/framework/fixtures/proof_positive_control.tscn", "linux_positive_control")
        self.assertEqual(native.returncode, 0, summary)
        self.assertEqual(summary["status"], "PASS")
        self.assertTrue(summary["source_stable_during_run"])
        report = json.loads((evidence / "runner_results.json").read_text(encoding="utf-8-sig"))
        row = report["results"][0]
        self.assertTrue(row["process_exited"])
        self.assertEqual(row["effective_exit_code"], 0)
        self.assertTrue(row["framework_receipt_valid"])
        receipt = json.loads((evidence / "framework/proof_positive_control.result.json").read_text())
        self.assertEqual(receipt["invocation_id"], report["invocation_id"])
        self.assertEqual(receipt["run_id"], row["framework_run_id"])
        runtime = receipt["runtime_environment"]
        self.assertEqual(runtime["native_process_id"], row["wrapper_process_id"])
        self.assertTrue(Path(runtime["user_data_directory"]).is_relative_to(Path(row["runtime_appdata"])))
        before = json.loads((evidence / "before.json").read_text())
        self.assertEqual(receipt["source_content_sha256"], before["content_set_sha256"])
        self.assertEqual(before["engine_version"], "4.7.stable.official.5b4e0cb0f")
        handoff = json.loads((evidence / "framework/native_handoffs.json").read_text())
        self.assertEqual(handoff["producers"]["proof_positive_control"]["run_id"], row["framework_run_id"])

    def test_false_marker_never_grants_producer_and_returns_native_runner_failure(self):
        native, summary, evidence = self.invoke(
            "tests/framework/fixtures/proof_false_marker.tscn", "linux_false_marker")
        self.assertEqual(native.returncode, 1)
        self.assertEqual(summary["exit_code"], 1)
        self.assertEqual(summary["status"], "FAIL")
        report = json.loads((evidence / "runner_results.json").read_text(encoding="utf-8-sig"))
        self.assertIn("framework_checks_failed", report["results"][0]["reason"])
        handoff = json.loads((evidence / "framework/native_handoffs.json").read_text())
        self.assertEqual(handoff["producers"], {})

    def test_zero_checks_and_marker_only_fail_without_producer(self):
        for scene, token in [("proof_zero_checks", "framework_zero_checks"),
                             ("proof_marker_only", "framework_receipt_missing")]:
            with self.subTest(scene=scene):
                _, summary, evidence = self.invoke(
                    f"tests/framework/fixtures/{scene}.tscn", "linux_" + scene)
                self.assertEqual(summary["status"], "FAIL")
                report = json.loads((evidence / "runner_results.json").read_text(encoding="utf-8-sig"))
                self.assertTrue(report["results"][0]["pass_marker_found"])
                self.assertIn(token, report["results"][0]["reason"])
                handoff = json.loads((evidence / "framework/native_handoffs.json").read_text())
                self.assertEqual(handoff["producers"], {})

    def test_post_pass_nonzero_engine_error_and_timeout_are_failures(self):
        for scene, token in [("case3_pass_then_nonzero_exit", "non_zero_exit_code"),
                             ("case6_engine_log_fatal", "engine_log_failures"),
                             ("case4_pass_then_hang", "timeout_30s")]:
            with self.subTest(scene=scene):
                _, summary, evidence = self.invoke(
                    f"tests/runner_fixtures/{scene}.tscn", "linux_" + scene)
                self.assertEqual(summary["status"], "FAIL")
                report = json.loads((evidence / "runner_results.json").read_text(encoding="utf-8-sig"))
                row = report["results"][0]
                self.assertTrue(row["pass_marker_found"])
                self.assertIn(token, row["reason"])

    def test_changed_source_is_rejected_and_exact_probe_bytes_are_restored(self):
        marker = ROOT / "tests/framework/fixtures/source_mutation_marker.gd"
        original = marker.read_bytes()
        try:
            _, summary, evidence = self.invoke(
                "tests/framework/fixtures/proof_source_changed.tscn", "linux_source_changed")
            self.assertEqual(summary["status"], "FAIL")
            self.assertFalse(summary["source_stable_during_run"])
            before = json.loads((evidence / "before.json").read_text())
            after = json.loads((evidence / "after.json").read_text())
            self.assertNotEqual(before["files"][marker.relative_to(ROOT).as_posix()],
                                after["files"][marker.relative_to(ROOT).as_posix()])
        finally:
            marker.write_bytes(original)

    def test_existing_cold_receipt_counterexamples_use_real_isolated_save(self):
        _, summary, _ = self.invoke(
            "tests/framework/combined_cold_receipt_gate_test.tscn", "linux_cold_receipt_gate")
        self.assertEqual(summary["status"], "PASS")

    def test_repeated_scene_loses_old_producer_and_keeps_both_attempt_receipts(self):
        scene = "tests/framework/fixtures/proof_repeat_once.tscn"
        _, summary, evidence = self.invoke([scene, scene], "linux_repeat_producer")
        self.assertEqual(summary["status"], "FAIL")
        report = json.loads((evidence / "runner_results.json").read_text(encoding="utf-8-sig"))
        self.assertEqual([row["result"] for row in report["results"]], ["PASS", "FAIL"])
        first, second = report["results"]
        self.assertNotEqual(first["framework_run_id"], second["framework_run_id"])
        handoff = json.loads((evidence / "framework/native_handoffs.json").read_text())
        self.assertEqual(handoff["producers"], {})
        for row in report["results"]:
            attempt = evidence / "attempts" / row["framework_run_id"]
            receipt = json.loads((attempt / "proof_repeat_once.result.json").read_text())
            self.assertEqual(receipt["run_id"], row["framework_run_id"])
            self.assertTrue((attempt / "native_result.json").is_file())


if __name__ == "__main__":
    unittest.main()
