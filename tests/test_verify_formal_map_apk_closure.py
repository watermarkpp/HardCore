#!/usr/bin/env python3
"""Synthetic ZIP tests for the formal map APK closure verifier."""

from __future__ import annotations

import hashlib
import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
TOOL_PATH = ROOT / "tools/map_assets/verify_formal_map_apk_closure.py"
REGISTRY_PATH = "assets/data/runtime/map_editor/map_runtime_release_registry.json"
RUNTIME_ROOT = "assets/data/runtime/map_editor/"
CHUNK_ROOT = "assets/data/runtime/map_editor/formal_ground_chunks/sha256/"
FORMAL_MAPS = 67
AUTHORED_REFS = 445
UNIQUE_CHUNKS = 208


def _load_tool():
    spec = importlib.util.spec_from_file_location("formal_map_apk_closure", TOOL_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load verifier: {TOOL_PATH}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


VERIFIER = _load_tool()


def _json_bytes(value: object) -> bytes:
    return (json.dumps(value, ensure_ascii=False, indent=2) + "\n").encode("utf-8")


def _fixture(root: Path) -> dict[str, bytes]:
    entries: dict[str, bytes] = {}
    registry_entries: list[dict[str, object]] = []
    chunk_paths: list[str] = []

    for index in range(UNIQUE_CHUNKS):
        data = f"synthetic-formal-chunk-{index}".encode("ascii")
        digest = hashlib.sha256(data).hexdigest()
        image_path = f"{CHUNK_ROOT}{digest}.png"
        chunk_paths.append(image_path)
        image_file = root / Path(image_path)
        image_file.parent.mkdir(parents=True, exist_ok=True)
        image_file.write_bytes(data)

    for map_index in range(FORMAL_MAPS):
        map_key = f"synthetic_formal_map_{map_index:02d}"
        runtime_map_id = 700000 + map_index
        runtime_path = f"{RUNTIME_ROOT}{map_key}.runtime.json"
        registry_entries.append(
            {
                "map_key": map_key,
                "release_state": "implemented_playable",
                "runtime_map_id": runtime_map_id,
                "runtime_path": f"res://{runtime_path}",
            }
        )

    registry = {
        "registry_contract_id": "mse.map.runtime.release.v1",
        "maps": registry_entries,
    }
    registry_bytes = _json_bytes(registry)
    (root / Path(REGISTRY_PATH)).parent.mkdir(parents=True, exist_ok=True)
    (root / Path(REGISTRY_PATH)).write_bytes(registry_bytes)
    entries[REGISTRY_PATH] = registry_bytes

    refs_by_map: list[list[int]] = [[] for _ in range(FORMAL_MAPS)]
    for ref_index in range(AUTHORED_REFS):
        refs_by_map[ref_index % FORMAL_MAPS].append(ref_index % UNIQUE_CHUNKS)

    for map_index, registry_entry in enumerate(registry_entries):
        map_key = str(registry_entry["map_key"])
        runtime_map_id = int(registry_entry["runtime_map_id"])
        runtime_path = f"{RUNTIME_ROOT}{map_key}.runtime.json"
        runtime = {
            "runtime_schema_version": 2,
            "source": {
                "map_id": map_key,
                "runtime_map_id": runtime_map_id,
            },
            "instances": [],
        }
        runtime_bytes = _json_bytes(runtime)
        (root / Path(runtime_path)).parent.mkdir(parents=True, exist_ok=True)
        (root / Path(runtime_path)).write_bytes(runtime_bytes)
        entries[runtime_path] = runtime_bytes

        chunks = []
        for chunk_index, source_index in enumerate(refs_by_map[map_index]):
            image_path = chunk_paths[source_index]
            digest = Path(image_path).stem
            chunks.append(
                {
                    "chunk_id": f"c_{chunk_index}",
                    "image": image_path,
                    "sha256": digest,
                }
            )
        visual = {
            "map_id": map_key,
            "runtime_map_id": runtime_map_id,
            "render_mode": "batched_canvas_draw",
            "visual_contract_id": "mse.map.runtime.visual.v1",
            "coverage": {
                "required_chunk_count": len(chunks),
                "packaged_chunk_count": len(chunks),
                "complete": True,
            },
            "chunks": chunks,
        }
        visual_path = f"{RUNTIME_ROOT}{map_key}.visual.json"
        visual_bytes = _json_bytes(visual)
        (root / Path(visual_path)).write_bytes(visual_bytes)
        entries[visual_path] = visual_bytes

    for image_path in chunk_paths:
        digest = Path(image_path).stem
        import_path = f"{image_path}.import"
        ctex_path = f".godot/imported/{digest}.ctex"
        import_text = (
            "[remap]\n"
            f'path="res://{ctex_path}"\n'
            "\n[deps]\n"
            f'source_file="res://{image_path}"\n'
            f'dest_files=["res://{ctex_path}"]\n'
        )
        entries[import_path] = import_text.encode("utf-8")
        entries[ctex_path] = b"synthetic-ctex-payload"

    return entries


def _write_zip(path: Path, entries: dict[str, bytes], omit: set[str] | None = None) -> None:
    omitted = omit or set()
    with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for name, data in entries.items():
            if name not in omitted:
                archive.writestr(name, data)


def _run(root: Path, apk: Path, out: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [
            sys.executable,
            str(TOOL_PATH),
            "--root",
            str(root),
            "--apk",
            str(apk),
            "--out",
            str(out),
        ],
        check=False,
        capture_output=True,
        text=True,
    )


class VerifyFormalMapApkClosureTest(unittest.TestCase):
    def test_valid_package_closes_formal_chunks_without_source_pngs(self) -> None:
        with tempfile.TemporaryDirectory(prefix="formal-map-apk-test-") as temporary:
            temp = Path(temporary)
            source_root = temp / "source"
            source_root.mkdir()
            entries = _fixture(source_root)
            apk = temp / "valid.apk"
            evidence = temp / "valid.json"
            _write_zip(apk, entries)

            result = _run(source_root, apk, evidence)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            report = json.loads(evidence.read_text(encoding="utf-8"))
            self.assertTrue(report["ok"])
            self.assertEqual(report["counts"]["formal_registry_entries"], FORMAL_MAPS)
            self.assertEqual(report["counts"]["authored_chunk_refs"], AUTHORED_REFS)
            self.assertEqual(report["counts"]["unique_chunk_pngs"], UNIQUE_CHUNKS)
            self.assertEqual(report["counts"]["chunk_imports_checked"], UNIQUE_CHUNKS)
            self.assertGreater(report["counts"]["ctex_targets_checked"], 0)
            self.assertEqual(report["scope"], "formal_registry_runtime_visual_ground_chunk_closure_only")
            with zipfile.ZipFile(apk) as archive:
                self.assertFalse(any(name.endswith(".png") for name in archive.namelist()))

    def test_android_assets_prefix_is_resolved_without_relaxing_hash_checks(self) -> None:
        with tempfile.TemporaryDirectory(prefix="formal-map-apk-android-assets-test-") as temporary:
            temp = Path(temporary)
            source_root = temp / "source"
            source_root.mkdir()
            entries = _fixture(source_root)
            # Android packages the project's res://assets/... tree below the
            # APK assets container, while .godot/imported remains a sibling
            # under that same container. This mirrors the real APK layout and
            # must not bypass byte/hash or source-PNG checks.
            android_entries: dict[str, bytes] = {}
            for name, data in entries.items():
                if name.endswith(".png.import"):
                    # Match the real exported APK metadata: the member path
                    # identifies the imported PNG, while source_file is not
                    # serialized. Remap closure and all source/hash checks
                    # must still remain mandatory.
                    data = b"\n".join(
                        line
                        for line in data.splitlines()
                        if not line.startswith(b"source_file=")
                    ) + b"\n"
                android_entries[f"assets/{name}"] = data
            apk = temp / "android-assets-prefix.apk"
            evidence = temp / "android-assets-prefix.json"
            _write_zip(apk, android_entries)

            result = _run(source_root, apk, evidence)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            report = json.loads(evidence.read_text(encoding="utf-8"))
            self.assertTrue(report["ok"])
            self.assertEqual(
                report["registry"]["packagePath"],
                f"assets/{REGISTRY_PATH}",
            )
            self.assertEqual(report["counts"]["chunk_imports_checked"], UNIQUE_CHUNKS)
            self.assertEqual(
                report["counts"]["non_empty_ctex_targets"],
                UNIQUE_CHUNKS,
            )

    def test_missing_ctex_is_a_failure(self) -> None:
        with tempfile.TemporaryDirectory(prefix="formal-map-apk-test-") as temporary:
            temp = Path(temporary)
            source_root = temp / "source"
            source_root.mkdir()
            entries = _fixture(source_root)
            first_ctex = next(name for name in entries if name.endswith(".ctex"))
            apk = temp / "missing-ctex.apk"
            evidence = temp / "missing-ctex.json"
            _write_zip(apk, entries, {first_ctex})

            result = _run(source_root, apk, evidence)
            self.assertNotEqual(result.returncode, 0)
            report = json.loads(evidence.read_text(encoding="utf-8"))
            self.assertFalse(report["ok"])
            self.assertIn("missing_ctex_target", {item["code"] for item in report["errors"]})

    def test_package_json_sha_mismatch_is_a_failure(self) -> None:
        with tempfile.TemporaryDirectory(prefix="formal-map-apk-test-") as temporary:
            temp = Path(temporary)
            source_root = temp / "source"
            source_root.mkdir()
            entries = _fixture(source_root)
            visual_path = next(name for name in entries if name.endswith(".visual.json"))
            entries[visual_path] += b"\n"
            apk = temp / "mismatch.apk"
            evidence = temp / "mismatch.json"
            _write_zip(apk, entries)

            result = _run(source_root, apk, evidence)
            self.assertNotEqual(result.returncode, 0)
            report = json.loads(evidence.read_text(encoding="utf-8"))
            self.assertFalse(report["ok"])
            self.assertIn("json_sha256_mismatch", {item["code"] for item in report["errors"]})

    def test_source_chunk_sha_mismatch_is_a_failure(self) -> None:
        with tempfile.TemporaryDirectory(prefix="formal-map-apk-test-") as temporary:
            temp = Path(temporary)
            source_root = temp / "source"
            source_root.mkdir()
            entries = _fixture(source_root)
            source_png = next(
                path
                for path in (source_root / Path(CHUNK_ROOT)).glob("*.png")
            )
            source_png.write_bytes(b"tampered-source-png")
            apk = temp / "source-sha-mismatch.apk"
            evidence = temp / "source-sha-mismatch.json"
            _write_zip(apk, entries)

            result = _run(source_root, apk, evidence)
            self.assertNotEqual(result.returncode, 0)
            report = json.loads(evidence.read_text(encoding="utf-8"))
            self.assertFalse(report["ok"])
            self.assertIn(
                "source_chunk_sha256_mismatch",
                {item["code"] for item in report["errors"]},
            )


if __name__ == "__main__":
    unittest.main()
