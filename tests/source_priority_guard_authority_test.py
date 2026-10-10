#!/usr/bin/env python3
"""Focused B07A regression tests for policy-owned fallback authorization."""

from __future__ import annotations

import copy
import hashlib
import importlib.util
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]


def load_guard():
    spec = importlib.util.spec_from_file_location(
        "source_priority_guard", ROOT / "tools/source_priority_guard.py"
    )
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class SourcePriorityGuardAuthorityTest(unittest.TestCase):
    def _run_main(self, guard, argv):
        old = sys.argv
        try:
            sys.argv = ["source_priority_guard.py", *argv]
            return guard.main()
        finally:
            sys.argv = old

    def test_primary_catalog_false_cli_does_not_read_missing_catalog(self):
        guard = load_guard()
        result = self._run_main(guard, [
            "--policy", str(ROOT / "assets/data/source_priority_policy.json"),
            "--catalog", str(ROOT / "does-not-exist-catalog.json"),
            "authorize", "--lane", "item_categories",
            "--candidate", "hardcore.identity.categories",
        ])
        self.assertEqual(0, result)

    def test_catalog_required_auxiliary_missing_is_explicit_failure(self):
        guard = load_guard()
        result = self._run_main(guard, [
            "--policy", str(ROOT / "assets/data/source_priority_policy.json"),
            "--catalog", str(ROOT / "does-not-exist-catalog.json"),
            "authorize", "--lane", "server_data",
            "--candidate", "server.angelk727_full",
        ])
        self.assertEqual(2, result)

    def test_unknown_and_ineligible_candidates_are_rejected(self):
        guard = load_guard()
        for candidate in ("not-a-source", "server.crystal.NightWolf"):
            self.assertEqual(2, self._run_main(guard, [
                "--policy", str(ROOT / "assets/data/source_priority_policy.json"),
                "--catalog", str(ROOT / "does-not-exist-catalog.json"),
                "authorize", "--lane", "server_data", "--candidate", candidate,
            ]))

    def test_output_is_contained_and_non_destructive(self):
        guard = load_guard()
        with tempfile.TemporaryDirectory() as directory:
            temp = Path(directory)
            guard.OUTPUT_ROOT = temp / "outputs"
            target = guard.OUTPUT_ROOT / "owned" / "result.json"
            content = b'{"authorized": true}\n'
            self.assertEqual("created", guard.write_owned_output(target, content))
            self.assertEqual("reused", guard.write_owned_output(target, content))
            with self.assertRaises(ValueError):
                guard.write_owned_output(target, b'{"authorized": false}\n')
            with self.assertRaises(ValueError):
                guard.write_owned_output(temp / "outside.json", content)

    def test_preexisting_different_content_is_preserved_and_rejected(self):
        guard = load_guard()
        with tempfile.TemporaryDirectory() as directory:
            temp = Path(directory)
            guard.OUTPUT_ROOT = temp / "outputs"
            target = guard.OUTPUT_ROOT / "owned" / "race.json"
            target.parent.mkdir(parents=True)
            target.write_bytes(b"other-writer\n")
            with self.assertRaises(ValueError):
                guard.write_owned_output(target, b"our-content\n")
            self.assertEqual(b"other-writer\n", target.read_bytes())

    def test_directory_and_link_paths_fail_closed(self):
        guard = load_guard()
        with tempfile.TemporaryDirectory() as directory:
            temp = Path(directory)
            guard.OUTPUT_ROOT = temp / "outputs"
            directory_target = guard.OUTPUT_ROOT / "owned" / "as-directory"
            directory_target.mkdir(parents=True)
            with self.assertRaises(ValueError):
                guard.write_owned_output(directory_target, b"bytes\n")
            link_parent = guard.OUTPUT_ROOT / "linked"
            real_parent = guard.OUTPUT_ROOT / "real"
            real_parent.mkdir(parents=True)
            try:
                os.symlink(real_parent, link_parent, target_is_directory=True)
            except (OSError, NotImplementedError) as exc:
                self.skipTest(f"symlink boundary NOT_RUN: {exc}")
            with self.assertRaises(ValueError):
                guard.write_owned_output(link_parent / "result.json", b"bytes\n")

    def test_exclusive_create_race_preserves_other_writer(self):
        guard = load_guard()
        with tempfile.TemporaryDirectory() as directory:
            temp = Path(directory)
            guard.OUTPUT_ROOT = temp / "outputs"
            target = (guard.OUTPUT_ROOT / "owned" / "race-in-open.json").resolve()
            target.parent.mkdir(parents=True)
            original_open = Path.open
            injected = {"done": False}

            def race_open(path, *args, **kwargs):
                mode = args[0] if args else kwargs.get("mode", "r")
                if path == target and mode == "xb" and not injected["done"]:
                    injected["done"] = True
                    with original_open(path, "wb") as competitor:
                        competitor.write(b"other-writer\n")
                return original_open(path, *args, **kwargs)

            with mock.patch.object(Path, "open", race_open):
                with self.assertRaises(ValueError):
                    guard.write_owned_output(target, b"our-content\n")
            self.assertEqual(b"other-writer\n", target.read_bytes())

    def test_fsync_failure_leaves_created_path_and_fails_closed(self):
        guard = load_guard()
        with tempfile.TemporaryDirectory() as directory:
            temp = Path(directory)
            guard.OUTPUT_ROOT = temp / "outputs"
            target = guard.OUTPUT_ROOT / "owned" / "fsync-failure.json"
            with mock.patch.object(guard.os, "fsync", side_effect=OSError("sink fsync")):
                with self.assertRaises(ValueError):
                    guard.write_owned_output(target, b"partial-is-owned\n")
            self.assertTrue(target.is_file())
            self.assertEqual(b"partial-is-owned\n", target.read_bytes())

    def test_readback_failure_leaves_written_path_and_fails_closed(self):
        guard = load_guard()
        with tempfile.TemporaryDirectory() as directory:
            temp = Path(directory)
            guard.OUTPUT_ROOT = temp / "outputs"
            target = (guard.OUTPUT_ROOT / "owned" / "readback-failure.json").resolve()
            original_read_bytes = Path.read_bytes

            def fail_readback(path):
                if path == target:
                    raise OSError("sink readback")
                return original_read_bytes(path)

            with mock.patch.object(Path, "read_bytes", fail_readback):
                with self.assertRaises(ValueError):
                    guard.write_owned_output(target, b"written-before-readback\n")
            self.assertTrue(target.is_file())
            self.assertEqual(b"written-before-readback\n", original_read_bytes(target))
    def test_policy_statuses_are_fail_closed(self):
        guard = load_guard()
        policy = guard.load_json(ROOT / "assets/data/source_priority_policy.json")
        catalog = {"distributions": [{"distributionKey": "server.angelk727_full"}]}
        evidence = {
            "candidate": "server.angelk727_full",
            "requirement": "test requirement",
            "scope": "server_data",
            "checks": [{
                "distribution": "server.crystal.cjlaaa",
                "status": "unusable",
                "query": "isolated authority check",
                "proof": ["test-owned proof"],
            }],
        }
        with self.assertRaises(ValueError):
            guard.authorize(policy, catalog, "server_data", "server.angelk727_full", evidence)

        allowed = copy.deepcopy(evidence)
        allowed["checks"][0]["status"] = "missing"
        result = guard.authorize(
            policy, catalog, "server_data", "server.angelk727_full", allowed
        )
        self.assertTrue(result["authorized"])
        self.assertEqual(result["higherPriorityRejected"][0]["status"], "missing")

    def test_illegal_policy_is_rejected_before_lane_use(self):
        guard = load_guard()
        policy = {"lanes": {}, "rules": {"fallbackStatuses": ["unusable"]}}
        with self.assertRaises(ValueError):
            guard.validate_policy(policy)

    def test_policy_authority_input_is_unchanged(self):
        policy_path = ROOT / "assets/data/source_priority_policy.json"
        before = hashlib.sha256(policy_path.read_bytes()).digest()
        guard = load_guard()
        guard.validate_policy(guard.load_json(policy_path))
        self.assertEqual(before, hashlib.sha256(policy_path.read_bytes()).digest())


if __name__ == "__main__":
    unittest.main()
