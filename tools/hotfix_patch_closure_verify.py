#!/usr/bin/env python3
"""Read-only verifier for the 2026-09-05 Device Lab XP/town PCK.

The verifier reads the Godot 4 PCK directory directly.  It does not mount a
pack, mutate project files, or run the game.  The base APK/PCK byte evidence is
checked against the already recorded fresh Godot verification report; the
patch itself is checked for directory flags, payload ranges/MD5s, effective
closure, and unintended base-path replacement.
"""

from __future__ import annotations

import argparse
import collections
import hashlib
import json
import struct
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, BinaryIO


PACK_HEADER_MAGIC = 0x43504447  # "GDPC"
PACK_FORMAT_VERSION_V4 = 4
PACK_FILE_ENCRYPTED = 1 << 0
PACK_FILE_REMOVAL = 1 << 1
PACK_FILE_DELTA = 1 << 2

EXPECTED_PATCH_ID = "hotfix-20260905-xp-town"
EXPECTED_PATCH_COMMIT = "930c17aaa269da02e3313713b7c2604ccc70172f"
EXPECTED_FEATURE_COMMIT = "0abc83e94a58ba4f71b0e15485d384935ab4dd56"
EXPECTED_BASE_COMMIT = "52ae0565856c2d99a28639b2bf0c6278186e0858"
EXPECTED_BASE_APK_SHA256 = (
    "26584B871F61B2F6EC2DDDAF52432263E7D68A6B8BEA35B2A3196D59D5B21664"
)
EXPECTED_BASE_PCK_SHA256 = (
    "0FC6C2DAE3672130F9EEB8F9ED1A8C250DF119435BC43E55E5D47802FE0A4E5B"
)
EXPECTED_PATCH_SHA256 = (
    "B5811F685A4CF8BC55A3FEA39AF1A6F7837A53AAA57A0C280EBFCE993A695839"
)
EXPECTED_BASE_RESOURCE_COUNT = 16001
EXPECTED_BASE_RESOURCE_BYTES = 510109897

RUNTIME_SOURCES = {
    "assets/audio/town/main_city_bgm.ogg",
    "assets/audio/town/main_city_bgm.source.json",
    "scripts/game_root.gd",
    "scripts/hud.gd",
    "scripts/player_state.gd",
    "scripts/player_visual.gd",
    "scripts/town_music_controller.gd",
    "scripts/town_music_controller.gd.uid",
    "scripts/ui_level_up_preview.gd",
    "scripts/ui_level_up_preview.gd.uid",
}
EXPECTED_COMPILED_SCRIPTS = {
    "scripts/game_root.gdc",
    "scripts/hud.gdc",
    "scripts/player_state.gdc",
    "scripts/player_visual.gdc",
    "scripts/town_music_controller.gdc",
    "scripts/ui_level_up_preview.gdc",
}
EXPECTED_NEW_REMAPS = {
    "scripts/town_music_controller.gd.remap",
    "scripts/ui_level_up_preview.gd.remap",
}
EXPECTED_AUDIO_CLOSURE = {
    "assets/audio/town/main_city_bgm.ogg.import",
    "assets/audio/town/main_city_bgm.source.json",
    ".godot/imported/main_city_bgm.ogg-0266bce75d6e2d820dbb960ab2ff9c87.oggvorbisstr",
}
EXPECTED_GENERATED_DEPENDENCIES = {
    ".godot/global_script_class_cache.cfg",
    ".godot/uid_cache.bin",
}
EXPECTED_CLOSURE = (
    EXPECTED_COMPILED_SCRIPTS
    | EXPECTED_NEW_REMAPS
    | EXPECTED_AUDIO_CLOSURE
    | EXPECTED_GENERATED_DEPENDENCIES
)


class VerifyError(RuntimeError):
    pass


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while chunk := stream.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest().upper()


def _read_exact(stream: BinaryIO, size: int) -> bytes:
    value = stream.read(size)
    if len(value) != size:
        raise VerifyError(f"truncated file while reading {size} bytes")
    return value


def _u32(stream: BinaryIO) -> int:
    return struct.unpack("<I", _read_exact(stream, 4))[0]


def _u64(stream: BinaryIO) -> int:
    return struct.unpack("<Q", _read_exact(stream, 8))[0]


def parse_pck(path: Path, *, verify_payload_md5: bool) -> dict[str, Any]:
    file_size = path.stat().st_size
    rows: list[dict[str, Any]] = []
    with path.open("rb") as stream:
        header = _read_exact(stream, 40)
        magic, version, godot_major, godot_minor, godot_patch, pack_flags = struct.unpack(
            "<6I", header[:24]
        )
        file_base, directory_offset = struct.unpack("<QQ", header[24:40])
        if magic != PACK_HEADER_MAGIC:
            raise VerifyError(f"{path}: invalid PCK magic 0x{magic:08x}")
        if version != PACK_FORMAT_VERSION_V4:
            raise VerifyError(f"{path}: unsupported PCK version {version}")
        if directory_offset >= file_size:
            raise VerifyError(f"{path}: directory offset is outside file")
        stream.seek(directory_offset)
        file_count = _u32(stream)
        for index in range(file_count):
            string_length = _u32(stream)
            if string_length > file_size:
                raise VerifyError(f"{path}: entry {index} has invalid path length")
            encoded_path = _read_exact(stream, string_length)
            try:
                resource_path = encoded_path.rstrip(b"\0").decode("utf-8")
            except UnicodeDecodeError as exc:
                raise VerifyError(f"{path}: entry {index} path is not UTF-8") from exc
            relative_offset = _u64(stream)
            payload_size = _u64(stream)
            directory_md5 = _read_exact(stream, 16).hex()
            entry_flags = _u32(stream)
            absolute_offset = file_base + relative_offset
            row: dict[str, Any] = {
                "path": resource_path,
                "offset": relative_offset,
                "absolute_offset": absolute_offset,
                "size": payload_size,
                "md5": directory_md5,
                "flags": entry_flags,
            }
            if entry_flags & PACK_FILE_REMOVAL:
                # Removal entries intentionally have no payload.  They are a
                # safety finding, not a truncated-payload failure.
                row["payload_md5"] = None
                row["payload_status"] = "removal"
            elif entry_flags & PACK_FILE_ENCRYPTED:
                row["payload_md5"] = None
                row["payload_status"] = "encrypted_unverified"
            else:
                if absolute_offset + payload_size > file_size:
                    raise VerifyError(
                        f"{path}: {resource_path} payload exceeds file "
                        f"(offset={absolute_offset}, size={payload_size})"
                    )
                if verify_payload_md5:
                    stream_position = stream.tell()
                    stream.seek(absolute_offset)
                    digest = hashlib.md5()
                    remaining = payload_size
                    while remaining:
                        chunk = stream.read(min(1024 * 1024, remaining))
                        if not chunk:
                            raise VerifyError(
                                f"{path}: {resource_path} payload ended early"
                            )
                        digest.update(chunk)
                        remaining -= len(chunk)
                    payload_md5 = digest.hexdigest()
                    row["payload_md5"] = payload_md5
                    row["payload_status"] = (
                        "ok" if payload_md5 == directory_md5 else "md5_mismatch"
                    )
                    stream.seek(stream_position)
                else:
                    row["payload_md5"] = None
                    row["payload_status"] = "range_only"
            rows.append(row)

    paths = [row["path"] for row in rows]
    duplicates = sorted(
        path for path, count in collections.Counter(paths).items() if count > 1
    )
    return {
        "path": str(path.resolve()),
        "bytes": file_size,
        "sha256": sha256_file(path),
        "header": {
            "magic": f"0x{magic:08x}",
            "version": version,
            "godot": [godot_major, godot_minor, godot_patch],
            "pack_flags": pack_flags,
            "file_base": file_base,
            "directory_offset": directory_offset,
            "entry_count": file_count,
        },
        "rows": rows,
        "duplicate_paths": duplicates,
        "flag_counts": {
            "encrypted": sum(bool(row["flags"] & PACK_FILE_ENCRYPTED) for row in rows),
            "removal": sum(bool(row["flags"] & PACK_FILE_REMOVAL) for row in rows),
            "delta": sum(bool(row["flags"] & PACK_FILE_DELTA) for row in rows),
        },
        "payload_md5_mismatches": [
            row["path"] for row in rows if row["payload_status"] == "md5_mismatch"
        ],
    }


def rows_by_path(pack: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {row["path"]: row for row in pack["rows"]}


def category_counts(paths: list[str]) -> dict[str, int]:
    return dict(collections.Counter(Path(path).suffix.lower() or "<none>" for path in paths))


def read_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise VerifyError(f"cannot read JSON {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise VerifyError(f"JSON root is not an object: {path}")
    return value


def verify_base_report(
    base_pack_path: Path,
    base_report_path: Path,
    apk_path: Path,
) -> dict[str, Any]:
    report = read_json(base_report_path)
    verification = report.get("verification", {})
    report_pack = report.get("pack", {})
    report_apk = report.get("apk", {})
    direct_pack_sha = sha256_file(base_pack_path)
    direct_apk_sha = sha256_file(apk_path)
    checks = {
        "report_verification_ok": verification.get("ok") is True,
        "report_resource_count": verification.get("resourceCount") == EXPECTED_BASE_RESOURCE_COUNT,
        "report_resource_bytes": verification.get("resourceBytes") == EXPECTED_BASE_RESOURCE_BYTES,
        "report_base_commit": report.get("sourceCommit") == EXPECTED_BASE_COMMIT,
        "report_apk_sha256": report_apk.get("sha256", "").upper() == EXPECTED_BASE_APK_SHA256,
        "report_pack_sha256": report_pack.get("sha256", "").upper() == EXPECTED_BASE_PCK_SHA256,
        "direct_apk_sha256": direct_apk_sha == EXPECTED_BASE_APK_SHA256,
        "direct_pack_sha256": direct_pack_sha == EXPECTED_BASE_PCK_SHA256,
    }
    base_pack = parse_pck(base_pack_path, verify_payload_md5=False)
    checks["base_outer_pck_has_no_removals"] = base_pack["flag_counts"]["removal"] == 0
    checks["base_outer_pck_has_no_deltas"] = base_pack["flag_counts"]["delta"] == 0
    checks["base_outer_entry_count"] = base_pack["header"]["entry_count"] == EXPECTED_BASE_RESOURCE_COUNT
    if not all(checks.values()):
        failed = [name for name, passed in checks.items() if not passed]
        raise VerifyError(f"base APK/PCK evidence checks failed: {failed}")
    return {
        "report": report,
        "direct_sha256": {"apk": direct_apk_sha, "pack": direct_pack_sha},
        "checks": checks,
        "outer_pck": {
            "bytes": base_pack["bytes"],
            "entry_count": base_pack["header"]["entry_count"],
            "flag_counts": base_pack["flag_counts"],
        },
        "rows": base_pack["rows"],
    }


def build_report(args: argparse.Namespace) -> dict[str, Any]:
    base_pack_path = args.base_pack.resolve()
    patch_path = args.patch.resolve()
    base_report_path = args.base_report.resolve()
    patch_report_path = args.patch_report.resolve()
    apk_path = args.apk.resolve()
    for path in (base_pack_path, patch_path, base_report_path, patch_report_path, apk_path):
        if not path.is_file():
            raise VerifyError(f"required input is missing: {path}")

    base_evidence = verify_base_report(base_pack_path, base_report_path, apk_path)
    base_rows = rows_by_path({"rows": base_evidence["rows"]})
    patch = parse_pck(patch_path, verify_payload_md5=True)
    patch_rows = rows_by_path(patch)
    patch_manifest = read_json(patch_report_path)

    expected_patch_sha = patch_manifest.get("sha256", "").upper()
    expected_patch_size = patch_manifest.get("size")
    patch_checks = {
        "patch_id": patch_manifest.get("patchId") == EXPECTED_PATCH_ID,
        "patch_commit": patch_manifest.get("patchCommit") == EXPECTED_PATCH_COMMIT,
        "base_commit": patch_manifest.get("baseCommit") == EXPECTED_BASE_COMMIT,
        "patch_report_sha256": expected_patch_sha == patch["sha256"],
        "patch_report_size": expected_patch_size == patch["bytes"],
        "patch_sha256_fixed": patch["sha256"] == EXPECTED_PATCH_SHA256,
        "patch_commit_matches_requested": args.patch_commit == EXPECTED_PATCH_COMMIT,
        "feature_commit_resolved": args.feature_commit == EXPECTED_FEATURE_COMMIT,
    }

    patch_paths = set(patch_rows)
    base_paths = set(base_rows)
    overlap = sorted(patch_paths & base_paths)
    added = sorted(patch_paths - base_paths)
    changed_overlap = sorted(
        path
        for path in overlap
        if patch_rows[path]["flags"] & (PACK_FILE_REMOVAL | PACK_FILE_DELTA)
        or patch_rows[path]["size"] != base_rows[path]["size"]
        or patch_rows[path]["md5"] != base_rows[path]["md5"]
    )
    identical_overlap = sorted(set(overlap) - set(changed_overlap))
    removal_paths = sorted(
        row["path"] for row in patch["rows"] if row["flags"] & PACK_FILE_REMOVAL
    )
    delta_paths = sorted(
        row["path"] for row in patch["rows"] if row["flags"] & PACK_FILE_DELTA
    )

    missing_compiled = sorted(EXPECTED_COMPILED_SCRIPTS - patch_paths)
    missing_remaps = sorted(
        path
        for path in EXPECTED_NEW_REMAPS
        if path not in patch_paths
    )
    missing_audio = sorted(EXPECTED_AUDIO_CLOSURE - patch_paths)
    missing_generated = sorted(EXPECTED_GENERATED_DEPENDENCIES - patch_paths)
    runtime_manifest = set(patch_manifest.get("resources", []))
    runtime_manifest = {path.removeprefix("res://") for path in runtime_manifest}
    runtime_manifest_match = runtime_manifest == RUNTIME_SOURCES

    # These are the minimal compiled/imported resources needed by the ten
    # source changes.  Existing remaps for game_root/hud/player_state/
    # player_visual are supplied by the verified base PCK and therefore do not
    # need to be repeated in the patch.
    unexpected_paths = sorted(patch_paths - EXPECTED_CLOSURE)
    expected_changed_overlap = sorted(set(changed_overlap) & EXPECTED_CLOSURE)
    unexpected_changed_overlap = sorted(
        set(changed_overlap) - set(expected_changed_overlap)
    )
    unexpected_audio = sorted(
        path
        for path in patch_paths
        if path.startswith("assets/audio/") and path not in EXPECTED_AUDIO_CLOSURE
    )
    artifact_paths = sorted(path for path in patch_paths if path.startswith("artifacts/"))
    translation_paths = sorted(
        path for path in patch_paths if path.lower().endswith(".translation")
    )
    import_paths = sorted(
        path for path in patch_paths if path.lower().endswith(".import")
    )
    unrelated_import_paths = sorted(set(import_paths) - set(EXPECTED_AUDIO_CLOSURE))

    safety_reasons: list[str] = []
    if removal_paths:
        safety_reasons.append(
            "PCK removal flags delete base resources: " + ", ".join(removal_paths)
        )
    if unexpected_changed_overlap:
        safety_reasons.append(
            f"{len(unexpected_changed_overlap)} changed base paths are outside the approved runtime closure"
        )
    if unexpected_paths:
        safety_reasons.append(
            f"{len(unexpected_paths)} PCK entries are outside the approved runtime closure"
        )
    if missing_compiled or missing_remaps or missing_audio:
        safety_reasons.append("required compiled/remap/audio closure is incomplete")
    if patch["payload_md5_mismatches"]:
        safety_reasons.append("one or more regular PCK payload MD5s do not match directory hashes")

    result = {
        "schemaVersion": 1,
        "kind": "hotfix_patch_closure_verification",
        "generatedAtUtc": datetime.now(timezone.utc).isoformat(),
        "inputs": {
            "featureCommit": args.feature_commit,
            "patchCommit": args.patch_commit,
            "basePack": str(base_pack_path),
            "patch": str(patch_path),
            "baseReport": str(base_report_path),
            "patchReport": str(patch_report_path),
            "apk": str(apk_path),
        },
        "baseEvidence": {
            "checks": base_evidence["checks"],
            "directSha256": base_evidence["direct_sha256"],
            "outerPck": base_evidence["outer_pck"],
        },
        "patch": {
            "bytes": patch["bytes"],
            "mib": round(patch["bytes"] / (1024 * 1024), 3),
            "sha256": patch["sha256"],
            "header": patch["header"],
            "flagCounts": patch["flag_counts"],
            "payloadMd5Mismatches": patch["payload_md5_mismatches"],
            "duplicatePaths": patch["duplicate_paths"],
            "manifestChecks": patch_checks,
        },
        "closure": {
            "runtimeManifestExact": runtime_manifest_match,
            "runtimeManifestExpected": sorted(RUNTIME_SOURCES),
            "runtimeManifestActual": sorted(runtime_manifest),
            "expectedCompiledScripts": sorted(EXPECTED_COMPILED_SCRIPTS),
            "missingCompiledScripts": missing_compiled,
            "expectedNewRemaps": sorted(EXPECTED_NEW_REMAPS),
            "missingNewRemaps": missing_remaps,
            "expectedAudioClosure": sorted(EXPECTED_AUDIO_CLOSURE),
            "missingAudioClosure": missing_audio,
            "expectedGeneratedDependencies": sorted(EXPECTED_GENERATED_DEPENDENCIES),
            "missingGeneratedDependencies": missing_generated,
            "rawTownOggInPatch": "assets/audio/town/main_city_bgm.ogg" in patch_paths,
            "unexpectedAudioPaths": unexpected_audio,
        },
        "baseComparison": {
            "baseEntryCount": len(base_paths),
            "patchEntryCount": len(patch_paths),
            "overlapCount": len(overlap),
            "addedCount": len(added),
            "identicalOverlapCount": len(identical_overlap),
            "changedOverlapCount": len(changed_overlap),
            "expectedChangedOverlap": expected_changed_overlap,
            "unexpectedChangedOverlapCount": len(unexpected_changed_overlap),
            "unexpectedChangedOverlapSample": unexpected_changed_overlap[:80],
            "removalPaths": removal_paths,
            "deltaPaths": delta_paths,
            "unexpectedPatchEntryCount": len(unexpected_paths),
            "unexpectedPatchEntrySample": unexpected_paths[:80],
            "categoryCounts": category_counts(unexpected_paths),
            "unrelatedImportCount": len(unrelated_import_paths),
            "unrelatedImportSample": unrelated_import_paths[:40],
            "artifactCount": len(artifact_paths),
            "translationCount": len(translation_paths),
        },
        "safety": {
            "safeForInstall": not safety_reasons,
            "reasons": safety_reasons,
            "recommendation": (
                "DO_NOT_INSTALL until the patch is rebuilt from a clean/export-controlled "
                "closure and removal entries are eliminated."
                if safety_reasons
                else "Static closure checks passed; runtime mount/device acceptance remains required."
            ),
        },
    }
    return result


def write_outputs(result: dict[str, Any], output_dir: Path, stem: str) -> tuple[Path, Path]:
    output_dir.mkdir(parents=True, exist_ok=True)
    json_path = output_dir / f"{stem}.json"
    text_path = output_dir / f"{stem}.txt"
    if json_path.exists() or text_path.exists():
        raise VerifyError(f"refusing to overwrite existing evidence for {stem}")
    json_path.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    patch = result["patch"]
    comparison = result["baseComparison"]
    closure = result["closure"]
    safety = result["safety"]
    lines = [
        "HOTFIX_PATCH_CLOSURE_VERIFY",
        f"safe_for_install={str(safety['safeForInstall']).upper()}",
        f"patch_bytes={patch['bytes']} patch_mib={patch['mib']} sha256={patch['sha256']}",
        f"patch_entries={patch['header']['entry_count']} removals={patch['flagCounts']['removal']} deltas={patch['flagCounts']['delta']}",
        f"base_overlap={comparison['overlapCount']} changed_overlap={comparison['changedOverlapCount']} unexpected_changed_overlap={comparison['unexpectedChangedOverlapCount']}",
        f"unexpected_entries={comparison['unexpectedPatchEntryCount']} artifacts={comparison['artifactCount']} translations={comparison['translationCount']} unrelated_imports={comparison['unrelatedImportCount']}",
        f"compiled_missing={len(closure['missingCompiledScripts'])} remap_missing={len(closure['missingNewRemaps'])} audio_missing={len(closure['missingAudioClosure'])}",
        "reasons:",
    ]
    lines.extend(f"- {reason}" for reason in safety["reasons"])
    text_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return json_path, text_path


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-pack", type=Path, required=True)
    parser.add_argument("--patch", type=Path, required=True)
    parser.add_argument("--base-report", type=Path, required=True)
    parser.add_argument("--patch-report", type=Path, required=True)
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--stem", default="closure_verify_930c17aa")
    parser.add_argument("--patch-commit", default=EXPECTED_PATCH_COMMIT)
    parser.add_argument("--feature-commit", default=EXPECTED_FEATURE_COMMIT)
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    try:
        result = build_report(args)
        json_path, text_path = write_outputs(result, args.output_dir.resolve(), args.stem)
    except (OSError, struct.error, VerifyError) as exc:
        print(f"HOTFIX_PATCH_CLOSURE_VERIFY_FAIL: {exc}", file=sys.stderr)
        return 1
    print(json.dumps({
        "ok": True,
        "safeForInstall": result["safety"]["safeForInstall"],
        "json": str(json_path),
        "text": str(text_path),
        "removals": result["patch"]["flagCounts"]["removal"],
        "unexpectedChangedOverlap": result["baseComparison"]["unexpectedChangedOverlapCount"],
        "unexpectedEntries": result["baseComparison"]["unexpectedPatchEntryCount"],
    }, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
