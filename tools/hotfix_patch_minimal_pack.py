#!/usr/bin/env python3
"""Repack the approved XP/town closure with Godot PCKPacker.

The existing exported patch is treated as an immutable byte source.  This
helper extracts only the approved compiled/imported resources, reconstructs a
class cache from the verified base cache plus the two new classes, and asks a
fresh Godot process to create and load the new pack.  It never regenerates
runtime or audio content and refuses to overwrite any prior output.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
BASE_PACK = ROOT / "outputs/device_lab_base/52ae0565_apk_asset_base.pck"
DANGEROUS_PATCH = ROOT / "outputs/device_lab_patches/hotfix-20260905-xp-town.pck"
DANGEROUS_MANIFEST = ROOT / "outputs/device_lab_patches/hotfix-20260905-xp-town.json"
OUTPUT_DIR = ROOT / "outputs/device_lab_patches"
EVIDENCE_DIR = ROOT / "outputs/hotfix_20260905"
GODOT = ROOT / "tools/godot-4.7/Godot_v4.7-stable_win64_console.exe"
PACK_SCRIPT = ROOT / "tools/hotfix_patch_minimal_pack.gd"

BASE_COMMIT = "52ae0565856c2d99a28639b2bf0c6278186e0858"
PATCH_COMMIT = "930c17aaa269da02e3313713b7c2604ccc70172f"
FEATURE_COMMIT = "0abc83e94a58ba4f71b0e15485d384935ab4dd56"
BASE_SHA256 = "0FC6C2DAE3672130F9EEB8F9ED1A8C250DF119435BC43E55E5D47802FE0A4E5B"
DANGEROUS_PATCH_SHA256 = "B5811F685A4CF8BC55A3FEA39AF1A6F7837A53AAA57A0C280EBFCE993A695839"
APK_SHA256 = "26584B871F61B2F6EC2DDDAF52432263E7D68A6B8BEA35B2A3196D59D5B21664"

PATCH_PAYLOAD_PATHS = (
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
)
CLASS_CACHE_PATH = ".godot/global_script_class_cache.cfg"
PACKED_PATHS = (*PATCH_PAYLOAD_PATHS, CLASS_CACHE_PATH)
RUNTIME_MANIFEST_PATHS = (
    "res://assets/audio/town/main_city_bgm.ogg",
    "res://assets/audio/town/main_city_bgm.source.json",
    "res://scripts/game_root.gd",
    "res://scripts/hud.gd",
    "res://scripts/player_state.gd",
    "res://scripts/player_visual.gd",
    "res://scripts/town_music_controller.gd",
    "res://scripts/town_music_controller.gd.uid",
    "res://scripts/ui_level_up_preview.gd",
    "res://scripts/ui_level_up_preview.gd.uid",
)
NEW_CLASSES = {
    ("TownMusicController", "res://scripts/town_music_controller.gd"),
    ("UILevelUpPreview", "res://scripts/ui_level_up_preview.gd"),
}


def load_closure_module():
    module_path = ROOT / "tools/hotfix_patch_closure_verify.py"
    spec = importlib.util.spec_from_file_location("hotfix_patch_closure_verify", module_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot import verifier: {module_path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


CLOSURE = load_closure_module()


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest().upper()


def read_payload(pack_path: Path, row: dict[str, Any]) -> bytes:
    if int(row["flags"]) != 0:
        raise RuntimeError(f"approved source entry is not a regular file: {row['path']}")
    with pack_path.open("rb") as stream:
        stream.seek(int(row["absolute_offset"]))
        data = stream.read(int(row["size"]))
    if len(data) != int(row["size"]):
        raise RuntimeError(f"truncated source payload: {pack_path}::{row['path']}")
    actual_md5 = hashlib.md5(data).hexdigest()
    if actual_md5 != str(row["md5"]):
        raise RuntimeError(f"source payload MD5 mismatch: {pack_path}::{row['path']}")
    return data


def class_blocks(data: bytes) -> tuple[str, list[str], dict[tuple[str, str], str]]:
    text = data.decode("utf-8")
    if not text.endswith("}]\n"):
        raise RuntimeError("global script class cache has an unexpected closing form")
    blocks = re.findall(r"\{\n.*?\n\}", text, flags=re.DOTALL)
    records: dict[tuple[str, str], str] = {}
    for block in blocks:
        class_match = re.search(r'"class": &"([^"]+)"', block)
        path_match = re.search(r'"path": "([^"]+)"', block)
        if class_match is None or path_match is None:
            raise RuntimeError("global script class cache contains an unparseable record")
        key = (class_match.group(1), path_match.group(1))
        if key in records:
            raise RuntimeError(f"duplicate global script class record: {key}")
        records[key] = block
    return text, blocks, records


def merged_class_cache(base_data: bytes, patch_data: bytes) -> tuple[bytes, dict[str, Any]]:
    base_text, base_blocks, base_records = class_blocks(base_data)
    _, patch_blocks, patch_records = class_blocks(patch_data)
    if not NEW_CLASSES <= set(patch_records):
        raise RuntimeError("dangerous patch class cache is missing a new class")
    if set(patch_records) != set(base_records) | NEW_CLASSES:
        missing = sorted(set(base_records) - set(patch_records))
        extra = sorted(set(patch_records) - set(base_records) - NEW_CLASSES)
        raise RuntimeError(f"class cache source drift: missing={missing}, extra={extra}")
    if len(base_records) != 180 or len(patch_records) != 182:
        raise RuntimeError(
            f"unexpected class cache cardinality: base={len(base_records)} patch={len(patch_records)}"
        )
    new_blocks = [patch_records[key] for key in sorted(NEW_CLASSES)]
    base_prefix = base_text[:-2].rstrip("\n")
    merged_text = base_prefix + ", " + ", ".join(new_blocks) + "]\n"
    _, merged_blocks, merged_records = class_blocks(merged_text.encode("utf-8"))
    if set(merged_records) != set(base_records) | NEW_CLASSES or len(merged_records) != 182:
        raise RuntimeError("reconstructed class cache does not equal base plus two classes")
    return merged_text.encode("utf-8"), {
        "baseClassCount": len(base_records),
        "dangerousPatchClassCount": len(patch_records),
        "mergedClassCount": len(merged_records),
        "addedOnly": [list(key) for key in sorted(NEW_CLASSES)],
        "baseByteSha256": sha256_bytes(base_data),
        "dangerousPatchByteSha256": sha256_bytes(patch_data),
        "mergedByteSha256": sha256_bytes(merged_text.encode("utf-8")),
        "baseRecordBytesPreserved": base_text[:-2].encode("utf-8") == merged_text[: len(base_text) - 2].encode("utf-8"),
    }


def write_json(path: Path, value: Any) -> None:
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def run_godot(
    *,
    sandbox: Path,
    runtime_dir: Path,
    log_path: Path,
    mode_args: list[str],
    main_pack: Path | None = None,
) -> None:
    if not GODOT.is_file():
        raise RuntimeError(f"Godot console binary is missing: {GODOT}")
    runtime_dir.mkdir(parents=True, exist_ok=True)
    log_path.parent.mkdir(parents=True, exist_ok=True)
    appdata = runtime_dir / "appdata"
    local_appdata = runtime_dir / "localappdata"
    appdata.mkdir(parents=True, exist_ok=True)
    local_appdata.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env["APPDATA"] = str(appdata)
    env["LOCALAPPDATA"] = str(local_appdata)
    command = [str(GODOT), "--headless"]
    if main_pack is None:
        command.extend(["--path", str(sandbox)])
    else:
        command.extend(["--main-pack", str(main_pack)])
    command.extend([
        "--user-data-dir",
        str(runtime_dir),
        "--log-file",
        str(log_path),
        "--script",
        str(PACK_SCRIPT),
        "--",
        *mode_args,
    ])
    completed = subprocess.run(
        command,
        cwd=ROOT,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )
    log_path.write_text(completed.stdout, encoding="utf-8")
    print(completed.stdout, end="")
    if completed.returncode != 0:
        raise RuntimeError(f"Godot helper failed with exit code {completed.returncode}; see {log_path}")


def build(args: argparse.Namespace) -> dict[str, Any]:
    base_path = args.base.resolve()
    dangerous_path = args.dangerous_patch.resolve()
    dangerous_manifest_path = args.dangerous_manifest.resolve()
    output_dir = args.output_dir.resolve()
    evidence_dir = args.evidence_dir.resolve()
    final_pack = output_dir / args.pack_name
    final_manifest = output_dir / args.manifest_name
    evidence_json = evidence_dir / args.evidence_stem.with_suffix(".json")
    evidence_text = evidence_dir / args.evidence_stem.with_suffix(".txt")
    verify_result = evidence_dir / f"{args.evidence_stem.name}_resource_loader.json"
    for path in (base_path, dangerous_path, dangerous_manifest_path, PACK_SCRIPT):
        if not path.is_file():
            raise RuntimeError(f"required input is missing: {path}")
    for path in (final_pack, final_manifest, evidence_json, evidence_text, verify_result):
        if path.exists():
            raise RuntimeError(f"refusing to overwrite existing output: {path}")
    output_dir.mkdir(parents=True, exist_ok=True)
    evidence_dir.mkdir(parents=True, exist_ok=True)

    base_sha = CLOSURE.sha256_file(base_path)
    dangerous_sha = CLOSURE.sha256_file(dangerous_path)
    if base_sha != BASE_SHA256:
        raise RuntimeError(f"base PCK SHA mismatch: expected {BASE_SHA256}, got {base_sha}")
    if dangerous_sha != DANGEROUS_PATCH_SHA256:
        raise RuntimeError(
            f"dangerous patch SHA mismatch: expected {DANGEROUS_PATCH_SHA256}, got {dangerous_sha}"
        )
    dangerous_manifest = json.loads(dangerous_manifest_path.read_text(encoding="utf-8"))
    if (
        dangerous_manifest.get("baseCommit") != BASE_COMMIT
        or dangerous_manifest.get("patchCommit") != PATCH_COMMIT
        or dangerous_manifest.get("sha256", "").upper() != dangerous_sha
        or int(dangerous_manifest.get("size", -1)) != dangerous_path.stat().st_size
    ):
        raise RuntimeError("dangerous patch manifest identity is inconsistent")
    if sorted(dangerous_manifest.get("resources", [])) != sorted(RUNTIME_MANIFEST_PATHS):
        raise RuntimeError("dangerous patch runtime manifest changed unexpectedly")

    base = CLOSURE.parse_pck(base_path, verify_payload_md5=False)
    dangerous = CLOSURE.parse_pck(dangerous_path, verify_payload_md5=True)
    base_rows = {row["path"]: row for row in base["rows"]}
    dangerous_rows = {row["path"]: row for row in dangerous["rows"]}
    if len(base_rows) != 16001 or base["flag_counts"]["removal"] or base["flag_counts"]["delta"]:
        raise RuntimeError("base PCK directory contract changed")
    # The source export is intentionally the rejected pack: its removal and
    # broad export drift are preserved as evidence.  Only the twelve selected
    # rows below are allowed into the rebuilt pack, and each must be regular.
    for path in PATCH_PAYLOAD_PATHS:
        if path not in dangerous_rows:
            raise RuntimeError(f"approved payload missing from dangerous patch: {path}")
        if int(dangerous_rows[path]["flags"]) != 0:
            raise RuntimeError(f"approved payload has non-regular flags: {path}")
    if CLASS_CACHE_PATH not in base_rows or CLASS_CACHE_PATH not in dangerous_rows:
        raise RuntimeError("class cache source is missing")

    work_dir = Path(tempfile.mkdtemp(prefix="minimal_pack_work_", dir=evidence_dir))
    payload_dir = work_dir / "payload"
    sandbox = work_dir / "sandbox"
    runtime_dir = evidence_dir / f"runtime_appdata_{uuid.uuid4().hex}"
    packer_manifest_path = work_dir / "packer_manifest.json"
    temp_pack = work_dir / args.pack_name
    try:
        payload_dir.mkdir(parents=True, exist_ok=True)
        sandbox.mkdir(parents=True, exist_ok=True)
        (sandbox / "project.godot").write_text(
            "[application]\nconfig/name=\"HardCore Hotfix PCK Verifier\"\n"
            "config/features=PackedStringArray(\"4.7\")\n"
            "run/main_scene=\"\"\n"
            "[rendering]\nrenderer/rendering_method=\"gl_compatibility\"\n",
            encoding="utf-8",
        )

        source_entries: list[dict[str, Any]] = []
        packer_entries: list[dict[str, Any]] = []
        for path in PATCH_PAYLOAD_PATHS:
            data = read_payload(dangerous_path, dangerous_rows[path])
            destination = payload_dir / Path(path)
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(data)
            digest = sha256_bytes(data)
            source_entries.append(
                {
                    "resourcePath": f"res://{path}",
                    "sourcePack": "dangerous-exported-patch",
                    "sourcePackSha256": dangerous_sha,
                    "sourceEntry": path,
                    "bytes": len(data),
                    "sha256": digest,
                    "directoryMd5": dangerous_rows[path]["md5"],
                }
            )
            packer_entries.append(
                {
                    "resourcePath": f"res://{path}",
                    "sourcePath": str(destination.resolve()),
                    "bytes": len(data),
                    "sha256": digest,
                }
            )

        base_cache = read_payload(base_path, base_rows[CLASS_CACHE_PATH])
        dangerous_cache = read_payload(dangerous_path, dangerous_rows[CLASS_CACHE_PATH])
        merged_cache, cache_evidence = merged_class_cache(base_cache, dangerous_cache)
        cache_destination = payload_dir / Path(CLASS_CACHE_PATH)
        cache_destination.parent.mkdir(parents=True, exist_ok=True)
        cache_destination.write_bytes(merged_cache)
        source_entries.append(
            {
                "resourcePath": f"res://{CLASS_CACHE_PATH}",
                "sourcePack": "verified-base-plus-explicit-two-class-merge",
                "basePackSha256": base_sha,
                "baseEntry": CLASS_CACHE_PATH,
                "dangerousPatchSha256": dangerous_sha,
                "dangerousPatchEntry": CLASS_CACHE_PATH,
                "bytes": len(merged_cache),
                "sha256": sha256_bytes(merged_cache),
                "cacheEvidence": cache_evidence,
            }
        )
        packer_entries.append(
            {
                "resourcePath": f"res://{CLASS_CACHE_PATH}",
                "sourcePath": str(cache_destination.resolve()),
                "bytes": len(merged_cache),
                "sha256": sha256_bytes(merged_cache),
            }
        )
        if len(packer_entries) != 12 or {entry["resourcePath"][6:] for entry in packer_entries} != set(PACKED_PATHS):
            raise RuntimeError("minimal PCK entry set is not exactly the approved closure")
        packer_manifest = {
            "schemaVersion": 1,
            "kind": "hotfix_patch_minimal_packer_inputs",
            "entries": packer_entries,
        }
        write_json(packer_manifest_path, packer_manifest)

        pack_log = ROOT / "outputs/test_logs/hotfix_patch_minimal_pack.log"
        verify_log = ROOT / "outputs/test_logs/hotfix_patch_minimal_verify.log"
        run_godot(
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
        # Reproduce the physical Device Lab startup order: the base PCK is the
        # main pack, and DeviceLabPatch's first autoload sees this isolated
        # user:// manifest before GameData/PlayerState are instantiated.
        patch_runtime_dir = runtime_dir / "device_lab" / "patches"
        patch_runtime_dir.mkdir(parents=True, exist_ok=True)
        runtime_patch = patch_runtime_dir / temp_pack.name
        shutil.copy2(temp_pack, runtime_patch)
        write_json(
            patch_runtime_dir / "active.json",
            {
                "schemaVersion": 1,
                "patchId": "hotfix-20260905-xp-town-minimal",
                "file": temp_pack.name,
                "size": temp_pack.stat().st_size,
                "sha256": CLOSURE.sha256_file(temp_pack),
            },
        )
        source_guard = work_dir / "source_guard"
        source_guard.mkdir(parents=True, exist_ok=True)
        run_godot(
            sandbox=sandbox,
            runtime_dir=runtime_dir,
            log_path=verify_log,
            mode_args=[
                "--mode=verify",
                f"--base={base_path}",
                f"--patch={temp_pack}",
                f"--result={verify_result}",
                f"--source-guard={source_guard}",
            ],
            main_pack=base_path,
        )
        if not verify_result.is_file():
            raise RuntimeError("fresh resource-loader verification produced no result")
        resource_result = json.loads(verify_result.read_text(encoding="utf-8"))
        if not resource_result.get("ok"):
            raise RuntimeError(f"fresh resource-loader verification failed: {resource_result}")

        rebuilt = CLOSURE.parse_pck(temp_pack, verify_payload_md5=True)
        rebuilt_paths = {row["path"] for row in rebuilt["rows"]}
        if rebuilt_paths != set(PACKED_PATHS):
            raise RuntimeError("rebuilt PCK directory is not exactly the approved closure")
        if any(rebuilt["flag_counts"].get(key, 0) for key in ("encrypted", "removal", "delta")):
            raise RuntimeError(f"rebuilt PCK contains forbidden flags: {rebuilt['flag_counts']}")
        if rebuilt["payload_md5_mismatches"] or rebuilt["duplicate_paths"]:
            raise RuntimeError("rebuilt PCK payload or duplicate-path checks failed")
        if rebuilt["bytes"] > 64 * 1024 * 1024:
            raise RuntimeError(f"rebuilt PCK exceeds Device Lab limit: {rebuilt['bytes']}")
        os.replace(temp_pack, final_pack)
        final_sha = CLOSURE.sha256_file(final_pack)
        final_size = final_pack.stat().st_size
        output_manifest = {
            "schemaVersion": 1,
            "kind": "device_lab_patch_minimal",
            "patchId": "hotfix-20260905-xp-town-minimal",
            "file": final_pack.name,
            "size": final_size,
            "sha256": final_sha,
            "baseCommit": BASE_COMMIT,
            "patchCommit": PATCH_COMMIT,
            "sourceFeatureCommit": FEATURE_COMMIT,
            "basePack": {
                "file": base_path.name,
                "sha256": base_sha,
                "sourceCommit": BASE_COMMIT,
            },
            "sourceDangerousPatch": {
                "file": dangerous_path.name,
                "sha256": dangerous_sha,
                "patchCommit": PATCH_COMMIT,
            },
            "resources": list(RUNTIME_MANIFEST_PATHS),
            "packedResources": list(PACKED_PATHS),
            "runtimeManifestUnchanged": True,
            "uidCacheIncluded": False,
            "classCache": cache_evidence,
            "sourceEntries": source_entries,
            "repackMethod": "extract-approved-payloads-then-fresh-Godot-4.7-PCKPacker",
            "dangerousSourcePreserved": True,
            "verification": {
                "freshResourceLoaderResult": str(verify_result),
                "packLog": str(pack_log),
                "verifyLog": str(verify_log),
                "sandboxHasNoSourceScripts": bool(
                    resource_result.get("sourceFallback", {}).get("sourceScriptsAbsentOnDisk")
                ),
                "cacheMode": "CACHE_MODE_IGNORE",
                "pckFlags": rebuilt["flag_counts"],
                "pckEntries": len(rebuilt["rows"]),
                "pckPayloadMd5Mismatches": rebuilt["payload_md5_mismatches"],
            },
        }
        write_json(final_manifest, output_manifest)

        evidence = {
            "schemaVersion": 1,
            "kind": "hotfix_patch_minimal_repack_evidence",
            "generatedAtUtc": datetime.now(timezone.utc).isoformat(),
            "inputs": {
                "basePack": str(base_path),
                "basePackSha256": base_sha,
                "dangerousPatch": str(dangerous_path),
                "dangerousPatchSha256": dangerous_sha,
                "baseCommit": BASE_COMMIT,
                "patchCommit": PATCH_COMMIT,
                "featureCommit": FEATURE_COMMIT,
            },
            "output": {
                "pack": str(final_pack),
                "manifest": str(final_manifest),
                "bytes": final_size,
                "mib": round(final_size / (1024 * 1024), 6),
                "sha256": final_sha,
                "entries": len(rebuilt["rows"]),
                "flags": rebuilt["flag_counts"],
                "paths": sorted(rebuilt_paths),
            },
            "classCache": cache_evidence,
            "resourceLoader": resource_result,
            "sourceEntries": source_entries,
            "safety": {
                "safeForInstall": True,
                "noRemovalEntries": rebuilt["flag_counts"]["removal"] == 0,
                "noDeltaEntries": rebuilt["flag_counts"]["delta"] == 0,
                "noEncryptedEntries": rebuilt["flag_counts"]["encrypted"] == 0,
                "exactApprovedClosure": rebuilt_paths == set(PACKED_PATHS),
                "under64MiB": final_size <= 64 * 1024 * 1024,
                "dangerousPatchPreserved": dangerous_path.is_file()
                and CLOSURE.sha256_file(dangerous_path) == DANGEROUS_PATCH_SHA256,
            },
        }
        write_json(evidence_json, evidence)
        text_lines = [
            "HOTFIX_PATCH_MINIMAL_REPACK",
            "safe_for_install=TRUE",
            f"pack={final_pack}",
            f"bytes={final_size} mib={final_size / (1024 * 1024):.6f} sha256={final_sha}",
            f"entries={len(rebuilt['rows'])} removals={rebuilt['flag_counts']['removal']} deltas={rebuilt['flag_counts']['delta']} encrypted={rebuilt['flag_counts']['encrypted']}",
            f"source_base_sha256={base_sha}",
            f"source_dangerous_patch_sha256={dangerous_sha}",
            f"class_cache_base={cache_evidence['baseClassCount']} merged={cache_evidence['mergedClassCount']} added_only=TownMusicController,UILevelUpPreview uid_cache=false",
            "fresh_resource_loader=PASS cache_mode=CACHE_MODE_IGNORE sandbox_source_fallback=false",
            "xp=PASS source_level_1=100 gameplay_threshold_level_1=10 scale=0.10 minimum=1",
            "sfx=PASS PlayerVisual.SKILL_AUDIO_ENABLED=false base_representative_stream_loaded=true patch_adds_sfx=false",
            "level_up_effect=PASS flame_size_scale=0.75",
            f"town_music=PASS length_seconds={float(resource_result['music']['lengthSeconds']):.6f}",
        ]
        evidence_text.write_text("\n".join(text_lines) + "\n", encoding="utf-8")
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
        # Keep the exact generated staging/user-data tree for audit and for a
        # failed-run diagnosis.  It is scoped under the evidence directory and
        # is never used as an install target; cleanup is an explicit parent
        # decision after the evidence is accepted.
        pass


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", type=Path, default=BASE_PACK)
    parser.add_argument("--dangerous-patch", type=Path, default=DANGEROUS_PATCH)
    parser.add_argument("--dangerous-manifest", type=Path, default=DANGEROUS_MANIFEST)
    parser.add_argument("--output-dir", type=Path, default=OUTPUT_DIR)
    parser.add_argument("--evidence-dir", type=Path, default=EVIDENCE_DIR)
    parser.add_argument("--pack-name", default="hotfix-20260905-xp-town-minimal.pck")
    parser.add_argument("--manifest-name", default="hotfix-20260905-xp-town-minimal.json")
    parser.add_argument("--evidence-stem", type=Path, default=Path("minimal_repack_930c17aa"))
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    try:
        print(json.dumps(build(parse_args(argv)), ensure_ascii=False))
        return 0
    except Exception as exc:
        print(f"HOTFIX_PATCH_MINIMAL_ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
