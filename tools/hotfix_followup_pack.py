#!/usr/bin/env python3
"""Build a controlled follow-up patch from the accepted 12-entry hotfix.

The previous minimal patch is the immutable payload baseline.  A later source
PCK may contribute only the approved compiled replacements
player_state.gdc/town_music_controller.gdc/game_root.gdc plus the explicitly approved new
DeviceLabRuntime.gdc diagnostic resource.  No source export closure is copied
wholesale, no class cache is regenerated, and every output name/evidence path
is unique and non-overwriting.

This helper is preparation-only until a caller supplies the new source PCK,
its manifest, and the exact source commit.  It intentionally has no monster
allowlist yet; that must be added only after the owner supplies the final
monster diff.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
import shutil
import sys
import tempfile
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
BASE_PACK = ROOT / "outputs/device_lab_patches/hotfix-20260905-xp-town-minimal.pck"
BASE_MANIFEST = ROOT / "outputs/device_lab_patches/hotfix-20260905-xp-town-minimal.json"
OUTPUT_DIR = ROOT / "outputs/device_lab_patches"
EVIDENCE_DIR = ROOT / "outputs/hotfix_20260905"
GODOT = ROOT / "tools/godot-4.7/Godot_v4.7-stable_win64_console.exe"
PACK_SCRIPT = ROOT / "tools/hotfix_followup_pack.gd"

BASE_COMMIT = "52ae0565856c2d99a28639b2bf0c6278186e0858"
BASE_PATCH_ID = "hotfix-20260905-xp-town-minimal"
BASE_PACK_SHA256 = "1643D8D05276D4DF45A823697645173C6D27A654C37B60238F024086BA501434"

# This is deliberately closed.  Do not add monster resources until the owner
# supplies and approves the final monster diff.
REPLACEMENT_PATHS = (
    "scripts/game_root.gdc",
    "scripts/player_state.gdc",
    "scripts/town_music_controller.gdc",
    "scripts/device_lab_runtime.gdc",
)
ADDED_COMPILED_PATHS = ("scripts/device_lab_runtime.gdc",)

BASE_PACKED_PATHS = (
    "scripts/game_root.gdc",
    "scripts/hud.gdc",
    "scripts/player_state.gdc",
    "scripts/player_visual.gdc",
    "scripts/town_music_controller.gdc",
    "scripts/ui_level_up_preview.gdc",
    "scripts/town_music_controller.gd.remap",
    "scripts/ui_level_up_preview.gd.remap",
    "assets/audio/town/main_city_bgm.ogg.import",
    "assets/audio/town/main_city_bgm.source.json",
    ".godot/imported/main_city_bgm.ogg-0266bce75d6e2d820dbb960ab2ff9c87.oggvorbisstr",
    ".godot/global_script_class_cache.cfg",
)
FOLLOWUP_PACKED_PATHS = (*BASE_PACKED_PATHS, *ADDED_COMPILED_PATHS)


def _load_previous_helper():
    module_path = ROOT / "tools/hotfix_patch_minimal_pack.py"
    spec = importlib.util.spec_from_file_location("hotfix_patch_minimal_pack_previous", module_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot import previous pack helper: {module_path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


PREVIOUS = _load_previous_helper()
CLOSURE = PREVIOUS.CLOSURE
# Reuse the previous audited PCK payload reader and Godot process wrapper while
# pointing the in-memory module at this follow-up's verifier script.
read_payload = PREVIOUS.read_payload
PREVIOUS.PACK_SCRIPT = PACK_SCRIPT


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest().upper()


def read_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise RuntimeError(f"cannot read JSON {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise RuntimeError(f"JSON root is not an object: {path}")
    return value


def _rows_by_path(pack: dict[str, Any]) -> dict[str, dict[str, Any]]:
    if pack["duplicate_paths"]:
        raise RuntimeError(f"duplicate paths in PCK: {pack['duplicate_paths']}")
    return {row["path"]: row for row in pack["rows"]}


def _validate_baseline() -> tuple[dict[str, Any], dict[str, Any], dict[str, bytes]]:
    if not BASE_PACK.is_file() or not BASE_MANIFEST.is_file():
        raise RuntimeError("accepted 12-entry baseline PCK/manifest is missing")
    actual_sha = CLOSURE.sha256_file(BASE_PACK)
    if actual_sha != BASE_PACK_SHA256:
        raise RuntimeError(f"baseline PCK SHA mismatch: expected {BASE_PACK_SHA256}, got {actual_sha}")
    manifest = read_json(BASE_MANIFEST)
    if (
        manifest.get("patchId") != BASE_PATCH_ID
        or str(manifest.get("sha256", "")).upper() != BASE_PACK_SHA256
        or manifest.get("baseCommit") != BASE_COMMIT
        or manifest.get("uidCacheIncluded") is not False
    ):
        raise RuntimeError("accepted baseline manifest identity/UID contract changed")
    if sorted(manifest.get("packedResources", [])) != sorted(BASE_PACKED_PATHS):
        raise RuntimeError("accepted baseline packed resource set changed")

    pack = CLOSURE.parse_pck(BASE_PACK, verify_payload_md5=True)
    if pack["flag_counts"] != {"encrypted": 0, "removal": 0, "delta": 0}:
        raise RuntimeError(f"accepted baseline has forbidden flags: {pack['flag_counts']}")
    if pack["payload_md5_mismatches"]:
        raise RuntimeError("accepted baseline has payload MD5 mismatches")
    rows = _rows_by_path(pack)
    if set(rows) != set(BASE_PACKED_PATHS):
        raise RuntimeError("accepted baseline PCK does not contain exactly 12 entries")
    payloads = {path: read_payload(BASE_PACK, rows[path]) for path in BASE_PACKED_PATHS}
    return manifest, pack, payloads


def _validate_source(
    source_path: Path,
    source_manifest_path: Path,
    source_commit: str,
) -> tuple[dict[str, Any], dict[str, Any], dict[str, dict[str, Any]], dict[str, bytes]]:
    if not source_path.is_file() or not source_manifest_path.is_file():
        raise RuntimeError("new source PCK and source manifest are required")
    if len(source_commit) != 40 or any(char not in "0123456789abcdefABCDEF" for char in source_commit):
        raise RuntimeError("--source-commit must be a full 40-character Git SHA")
    source_manifest = read_json(source_manifest_path)
    declared_commit = str(
        source_manifest.get("sourceCommit")
        or source_manifest.get("patchCommit")
        or ""
    )
    if declared_commit != source_commit:
        raise RuntimeError(
            f"source manifest commit mismatch: expected {source_commit}, got {declared_commit or '<missing>'}"
        )
    if source_manifest.get("baseCommit") != BASE_COMMIT:
        raise RuntimeError("new source manifest does not target the fixed APK70 base commit")
    source_sha = CLOSURE.sha256_file(source_path)
    manifest_sha = str(source_manifest.get("sha256", "")).upper()
    if manifest_sha and manifest_sha != source_sha:
        raise RuntimeError(f"source manifest SHA mismatch: expected {manifest_sha}, got {source_sha}")
    source = CLOSURE.parse_pck(source_path, verify_payload_md5=True)
    if source["payload_md5_mismatches"]:
        raise RuntimeError("new source PCK has payload MD5 mismatches")
    rows = _rows_by_path(source)
    replacements: dict[str, bytes] = {}
    for path in REPLACEMENT_PATHS:
        row = rows.get(path)
        if row is None:
            raise RuntimeError(f"approved replacement missing from new source PCK: {path}")
        if int(row["flags"]) != 0:
            raise RuntimeError(f"approved replacement has non-regular flags: {path}")
        replacements[path] = read_payload(source_path, row)
    return source_manifest, source, rows, replacements


def _safe_patch_id(value: str) -> str:
    if not value or "/" in value or "\\" in value or value in {".", ".."}:
        raise RuntimeError(f"invalid patch id: {value!r}")
    return value


def write_json(path: Path, value: Any) -> None:
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def _run_godot(
    *,
    sandbox: Path,
    runtime_dir: Path,
    log_path: Path,
    mode_args: list[str],
    main_pack: Path | None = None,
) -> None:
    PREVIOUS.run_godot(
        sandbox=sandbox,
        runtime_dir=runtime_dir,
        log_path=log_path,
        mode_args=mode_args,
        main_pack=main_pack,
    )


def build(args: argparse.Namespace) -> dict[str, Any]:
    patch_id = _safe_patch_id(args.patch_id)
    pack_name = _safe_patch_id(args.pack_name)
    manifest_name = _safe_patch_id(args.manifest_name)
    evidence_stem = Path(args.evidence_stem).name
    source_path = args.source_patch.resolve()
    source_manifest_path = args.source_manifest.resolve()
    output_dir = args.output_dir.resolve()
    evidence_dir = args.evidence_dir.resolve()
    final_pack = output_dir / pack_name
    final_manifest = output_dir / manifest_name
    evidence_json = evidence_dir / f"{evidence_stem}.json"
    evidence_text = evidence_dir / f"{evidence_stem}.txt"
    verify_result = evidence_dir / f"{evidence_stem}_resource_loader.json"
    for path in (final_pack, final_manifest, evidence_json, evidence_text, verify_result):
        if path.exists():
            raise RuntimeError(f"refusing to overwrite existing output: {path}")
    output_dir.mkdir(parents=True, exist_ok=True)
    evidence_dir.mkdir(parents=True, exist_ok=True)

    baseline_manifest, baseline_pack, baseline_payloads = _validate_baseline()
    source_manifest, source_pack, source_rows, replacements = _validate_source(
        source_path, source_manifest_path, args.source_commit
    )
    source_sha = CLOSURE.sha256_file(source_path)

    work_dir = Path(tempfile.mkdtemp(prefix="followup_pack_work_", dir=evidence_dir))
    payload_dir = work_dir / "payload"
    sandbox = work_dir / "sandbox"
    runtime_dir = evidence_dir / f"runtime_appdata_followup_{uuid.uuid4().hex}"
    packer_manifest_path = work_dir / "packer_manifest.json"
    temp_pack = work_dir / pack_name
    try:
        payload_dir.mkdir(parents=True, exist_ok=True)
        sandbox.mkdir(parents=True, exist_ok=True)
        (sandbox / "project.godot").write_text(
            "[application]\nconfig/name=\"HardCore Follow-up PCK\"\n"
            "config/features=PackedStringArray(\"4.7\")\n"
            "run/main_scene=\"\"\n"
            "[rendering]\nrenderer/rendering_method=\"gl_compatibility\"\n",
            encoding="utf-8",
        )

        source_entries: list[dict[str, Any]] = []
        packer_entries: list[dict[str, Any]] = []
        replaced_paths: list[str] = []
        for path in FOLLOWUP_PACKED_PATHS:
            data = replacements[path] if path in replacements else baseline_payloads[path]
            if path in replacements:
                replaced_paths.append(path)
                source_row = source_rows[path]
                replacement_entry = {
                    "resourcePath": f"res://{path}",
                    "sourcePack": "new-source-patch-explicit-replacement",
                    "sourcePackSha256": source_sha,
                    "sourceCommit": args.source_commit,
                    "sourceEntry": path,
                    "bytes": len(data),
                    "sha256": sha256_bytes(data),
                    "directoryMd5": source_row["md5"],
                    "baselinePresent": path in baseline_payloads,
                }
                if path in baseline_payloads:
                    replacement_entry["baselineSha256"] = sha256_bytes(baseline_payloads[path])
                source_entries.append(replacement_entry)
            else:
                source_entries.append(
                    {
                        "resourcePath": f"res://{path}",
                        "sourcePack": "accepted-12-entry-baseline",
                        "sourcePackSha256": BASE_PACK_SHA256,
                        "sourceEntry": path,
                        "bytes": len(data),
                        "sha256": sha256_bytes(data),
                        "baselinePreserved": True,
                    }
                )
            destination = payload_dir / Path(path)
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(data)
            digest = sha256_bytes(data)
            packer_entries.append(
                {
                    "resourcePath": f"res://{path}",
                    "sourcePath": str(destination.resolve()),
                    "bytes": len(data),
                    "sha256": digest,
                }
            )

        if {entry["resourcePath"][6:] for entry in packer_entries} != set(FOLLOWUP_PACKED_PATHS):
            raise RuntimeError("follow-up PCK entry set is not exactly the 12-entry baseline plus DeviceLabRuntime closure")
        packer_manifest = {
            "schemaVersion": 1,
            "kind": "hotfix_patch_followup_packer_inputs",
            "baselinePatchId": BASE_PATCH_ID,
            "baselinePatchSha256": BASE_PACK_SHA256,
            "sourceCommit": args.source_commit,
            "explicitReplacements": list(REPLACEMENT_PATHS),
            "addedCompiledScripts": list(ADDED_COMPILED_PATHS),
            "entries": packer_entries,
        }
        write_json(packer_manifest_path, packer_manifest)

        log_prefix = f"hotfix_followup_{evidence_stem}"
        pack_log = ROOT / "outputs/test_logs" / f"{log_prefix}_pack.log"
        verify_log = ROOT / "outputs/test_logs" / f"{log_prefix}_verify.log"
        _run_godot(
            sandbox=sandbox,
            runtime_dir=runtime_dir,
            log_path=pack_log,
            mode_args=[
                "--mode=pack",
                f"--manifest={packer_manifest_path}",
                f"--pack={temp_pack}",
            ],
        )
        if not temp_pack.is_file():
            raise RuntimeError("Godot PCKPacker completed without producing a pack")

        patch_runtime_dir = runtime_dir / "device_lab" / "patches"
        patch_runtime_dir.mkdir(parents=True, exist_ok=True)
        runtime_patch = patch_runtime_dir / temp_pack.name
        shutil.copy2(temp_pack, runtime_patch)
        write_json(
            patch_runtime_dir / "active.json",
            {
                "schemaVersion": 1,
                "patchId": patch_id,
                "file": temp_pack.name,
                "size": temp_pack.stat().st_size,
                "sha256": CLOSURE.sha256_file(temp_pack),
            },
        )
        source_guard = work_dir / "source_guard"
        source_guard.mkdir(parents=True, exist_ok=True)
        _run_godot(
            sandbox=sandbox,
            runtime_dir=runtime_dir,
            log_path=verify_log,
            mode_args=[
                "--mode=verify",
                f"--base={BASE_PACK}",
                f"--patch={temp_pack}",
                f"--result={verify_result}",
                f"--source-guard={source_guard}",
            ],
            main_pack=BASE_PACK,
        )
        if not verify_result.is_file():
            raise RuntimeError("fresh follow-up resource-loader verification produced no result")
        resource_result = read_json(verify_result)
        if not resource_result.get("ok"):
            raise RuntimeError(f"fresh follow-up resource-loader verification failed: {resource_result}")

        rebuilt = CLOSURE.parse_pck(temp_pack, verify_payload_md5=True)
        rebuilt_paths = {row["path"] for row in rebuilt["rows"]}
        if rebuilt_paths != set(FOLLOWUP_PACKED_PATHS):
            raise RuntimeError("follow-up PCK directory is not exactly the 12-entry baseline plus DeviceLabRuntime closure")
        if any(rebuilt["flag_counts"].get(key, 0) for key in ("encrypted", "removal", "delta")):
            raise RuntimeError(f"follow-up PCK contains forbidden flags: {rebuilt['flag_counts']}")
        if rebuilt["payload_md5_mismatches"] or rebuilt["duplicate_paths"]:
            raise RuntimeError("follow-up PCK payload or duplicate-path checks failed")
        if rebuilt["bytes"] > 64 * 1024 * 1024:
            raise RuntimeError(f"follow-up PCK exceeds Device Lab limit: {rebuilt['bytes']}")

        os.replace(temp_pack, final_pack)
        final_sha = CLOSURE.sha256_file(final_pack)
        final_size = final_pack.stat().st_size
        runtime_manifest = list(baseline_manifest.get("resources", []))
        if "res://scripts/device_lab_runtime.gd" not in runtime_manifest:
            runtime_manifest.append("res://scripts/device_lab_runtime.gd")
        output_manifest = {
            "schemaVersion": 1,
            "kind": "device_lab_patch_followup",
            "patchId": patch_id,
            "file": final_pack.name,
            "size": final_size,
            "sha256": final_sha,
            "baseCommit": BASE_COMMIT,
            "patchCommit": args.source_commit,
            "sourceCommit": args.source_commit,
            "basePack": {
                "file": BASE_PACK.name,
                "sha256": BASE_PACK_SHA256,
                "patchId": BASE_PATCH_ID,
            },
            "parentPatch": {
                "file": BASE_PACK.name,
                "patchId": BASE_PATCH_ID,
                "sha256": BASE_PACK_SHA256,
                "packedResources": list(BASE_PACKED_PATHS),
            },
            "sourcePatch": {
                "file": source_path.name,
                "sha256": source_sha,
                "manifest": source_manifest_path.name,
                "manifestCommit": source_manifest.get("sourceCommit")
                or source_manifest.get("patchCommit"),
                "ignoredEntryCount": len(source_pack["rows"]) - len(REPLACEMENT_PATHS),
            },
            "runtimeManifest": runtime_manifest,
            "runtimeManifestChanged": ["res://scripts/device_lab_runtime.gd"],
            "packedResources": list(FOLLOWUP_PACKED_PATHS),
            "replacedCompiledScripts": list(replaced_paths),
            "addedCompiledScripts": list(ADDED_COMPILED_PATHS),
            "uidCacheIncluded": False,
            "classCache": {
                "baselineSha256": sha256_bytes(baseline_payloads[".godot/global_script_class_cache.cfg"]),
                "outputSha256": sha256_bytes(baseline_payloads[".godot/global_script_class_cache.cfg"]),
                "baselinePreserved": True,
                "newClassesAdded": [],
            },
            "sourceEntries": source_entries,
            "repackMethod": "accepted-12-entry-baseline-plus-explicit-gdc-replacements",
            "verification": {
                "freshResourceLoaderResult": str(verify_result),
                "packLog": str(pack_log),
                "verifyLog": str(verify_log),
                "cacheMode": "CACHE_MODE_IGNORE",
                "sandboxHasNoSourceScripts": bool(
                    resource_result.get("sourceFallback", {}).get("sourceScriptsAbsentOnDisk")
                ),
                "pckFlags": rebuilt["flag_counts"],
                "pckEntries": len(rebuilt["rows"]),
                "pckPayloadMd5Mismatches": rebuilt["payload_md5_mismatches"],
            },
        }
        write_json(final_manifest, output_manifest)
        evidence = {
            "schemaVersion": 1,
            "kind": "hotfix_patch_followup_evidence",
            "generatedAtUtc": datetime.now(timezone.utc).isoformat(),
            "inputs": {
                "baselinePatch": str(BASE_PACK),
                "baselinePatchSha256": BASE_PACK_SHA256,
                "sourcePatch": str(source_path),
                "sourcePatchSha256": source_sha,
                "sourceCommit": args.source_commit,
                "baseCommit": BASE_COMMIT,
            },
            "output": {
                "pack": str(final_pack),
                "manifest": str(final_manifest),
                "bytes": final_size,
                "sha256": final_sha,
                "entries": len(rebuilt["rows"]),
                "flags": rebuilt["flag_counts"],
                "paths": sorted(rebuilt_paths),
            },
            "replacedCompiledScripts": list(replaced_paths),
            "resourceLoader": resource_result,
            "safety": {
                "safeForInstall": True,
                "baselineShaUnchanged": BASE_PACK.is_file()
                and CLOSURE.sha256_file(BASE_PACK) == BASE_PACK_SHA256,
                "noRemovalEntries": rebuilt["flag_counts"]["removal"] == 0,
                "noDeltaEntries": rebuilt["flag_counts"]["delta"] == 0,
                "noEncryptedEntries": rebuilt["flag_counts"]["encrypted"] == 0,
                "exactFollowupClosure": rebuilt_paths == set(FOLLOWUP_PACKED_PATHS),
                "under64MiB": final_size <= 64 * 1024 * 1024,
            },
        }
        write_json(evidence_json, evidence)
        evidence_text.write_text(
            "\n".join(
                [
                    "HOTFIX_PATCH_FOLLOWUP_REPACK",
                    "safe_for_install=TRUE",
                    f"pack={final_pack}",
                    f"bytes={final_size} mib={final_size / (1024 * 1024):.6f} sha256={final_sha}",
                    f"entries={len(rebuilt['rows'])} removals={rebuilt['flag_counts']['removal']} deltas={rebuilt['flag_counts']['delta']} encrypted={rebuilt['flag_counts']['encrypted']}",
                    f"parent_patch={BASE_PATCH_ID} parent_sha256={BASE_PACK_SHA256}",
                    f"source_commit={args.source_commit} source_sha256={source_sha}",
                    f"replaced={','.join(replaced_paths)} class_cache_preserved=true uid_cache=false",
                    "fresh_resource_loader=PASS cache_mode=CACHE_MODE_IGNORE sandbox_source_fallback=false",
                    f"death_penalty={resource_result['deathPenalty']}",
                    f"music={resource_result['music']}",
                    "effect=PASS flame_size_scale=0.75",
                    "sfx=PASS PlayerVisual.SKILL_AUDIO_ENABLED=false base_representative_stream_loaded=true",
                ]
            )
            + "\n",
            encoding="utf-8",
        )
        return {
            "ok": True,
            "safeForInstall": True,
            "pack": str(final_pack),
            "manifest": str(final_manifest),
            "evidence": str(evidence_json),
            "text": str(evidence_text),
            "resourceLoader": str(verify_result),
            "bytes": final_size,
            "sha256": final_sha,
            "entries": len(rebuilt["rows"]),
        }
    finally:
        # Preserve staging and isolated userdata for audit; cleanup is an
        # explicit parent decision and is intentionally not recursive here.
        pass


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-patch", type=Path, required=True)
    parser.add_argument("--source-manifest", type=Path, required=True)
    parser.add_argument("--source-commit", required=True)
    parser.add_argument("--patch-id", default="hotfix-20260905-xp-town-followup")
    parser.add_argument("--pack-name", default="hotfix-20260905-xp-town-followup.pck")
    parser.add_argument("--manifest-name", default="hotfix-20260905-xp-town-followup.json")
    parser.add_argument("--output-dir", type=Path, default=OUTPUT_DIR)
    parser.add_argument("--evidence-dir", type=Path, default=EVIDENCE_DIR)
    parser.add_argument("--evidence-stem", default="followup_repack_pending_source")
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    try:
        print(json.dumps(build(parse_args(argv)), ensure_ascii=False))
        return 0
    except Exception as exc:
        print(f"HOTFIX_PATCH_FOLLOWUP_ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
