#!/usr/bin/env python3
"""Verify the formal map ground-chunk closure in an exported APK.

This is deliberately a ZIP-level verifier.  It does not run Godot and it does
not require the source PNGs to be present in the APK: every source PNG named by
the formal visual manifests must instead have an APK ``.png.import`` whose
remap/destination ``.ctex`` files are present and non-empty in the package.

The verifier intentionally stops at the formal runtime registry -> runtime /
visual JSON -> SHA-256 ground-chunk closure.  It does not claim to verify the
larger map instance/wall texture graph, because that graph has additional
catalog and split-wall resolution rules that are not represented by this
APK-only contract.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import stat
import subprocess
import sys
import zipfile
from pathlib import Path
from typing import Any, Iterable


REGISTRY_RELATIVE_PATH = "assets/data/runtime/map_editor/map_runtime_release_registry.json"
RUNTIME_ROOT = "assets/data/runtime/map_editor/"
FORMAL_CHUNK_ROOT = (
    "assets/data/runtime/map_editor/formal_ground_chunks/sha256/"
)
EXPECTED_FORMAL_MAPS = 67
EXPECTED_AUTHORED_CHUNKS = 445
EXPECTED_UNIQUE_CHUNKS = 208
SHA256_RE = re.compile(r"^[0-9a-f]{64}$", re.IGNORECASE)
CTEX_REFERENCE_RE = re.compile(r"res://([^\"\s,\]]+\.ctex)")
SOURCE_FILE_RE = re.compile(r"(?m)^source_file=\"res://([^\"]+)\"\s*$")


def _normalise_resource_path(value: object) -> str | None:
    """Return a safe project-relative resource path, or ``None``.

    Godot resource strings use ``res://`` and APK ZIP entries use ordinary
    slash-separated names.  Backslashes, absolute paths and dot traversal are
    rejected rather than silently rewritten.
    """

    if not isinstance(value, str):
        return None
    path = value
    if path.startswith("res://"):
        path = path[6:]
    if not path or "\\" in path or path.startswith("/"):
        return None
    parts = path.split("/")
    if any(not part or part in {".", ".."} for part in parts):
        return None
    return "/".join(parts)


def _normalise_zip_path(value: str) -> str | None:
    """Normalise a ZIP member name without accepting traversal."""

    if not value or "\\" in value or value.startswith("/"):
        return None
    parts = value.split("/")
    if any(not part or part in {".", ".."} for part in parts):
        return None
    return "/".join(parts)


def _sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _read_json_file(path: Path) -> tuple[dict[str, Any] | None, bytes | None, str | None]:
    try:
        raw = path.read_bytes()
        value = json.loads(raw.decode("utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        return None, None, f"{path}: cannot read JSON: {exc}"
    if not isinstance(value, dict):
        return None, raw, f"{path}: JSON root must be an object"
    return value, raw, None


def _read_git_head(root: Path) -> str:
    try:
        result = subprocess.run(
            ["git", "-C", str(root), "rev-parse", "HEAD"],
            check=True,
            capture_output=True,
            text=True,
            timeout=5,
        )
    except (OSError, subprocess.SubprocessError):
        return "unknown"
    head = result.stdout.strip()
    return head or "unknown"


def _as_integer(value: object) -> int | None:
    if isinstance(value, bool):
        return None
    if isinstance(value, int):
        return value
    if isinstance(value, float) and value.is_integer():
        return int(value)
    return None


class PackageIndex:
    """Index safe, regular-file members of an APK ZIP."""

    def __init__(self, archive: zipfile.ZipFile, errors: list[dict[str, Any]]) -> None:
        self.archive = archive
        self.errors = errors
        self.members: dict[str, zipfile.ZipInfo] = {}
        for info in archive.infolist():
            normalised = _normalise_zip_path(info.filename)
            if normalised is None:
                self._error(
                    "unsafe_zip_member",
                    f"unsafe APK member path: {info.filename!r}",
                )
                continue
            if normalised in self.members:
                self._error(
                    "duplicate_zip_member",
                    f"duplicate APK member path: {normalised}",
                )
                continue
            mode = (info.external_attr >> 16) & 0xFFFF
            if stat.S_ISLNK(mode):
                self._error(
                    "symlink_zip_member",
                    f"symlink APK member is not accepted: {normalised}",
                )
                continue
            self.members[normalised] = info

    def _error(self, code: str, message: str, **details: Any) -> None:
        item: dict[str, Any] = {"code": code, "message": message}
        item.update(details)
        self.errors.append(item)

    @staticmethod
    def _candidate_paths(resource_path: str) -> Iterable[str]:
        normalised = _normalise_resource_path(resource_path)
        if normalised is None:
            return ()
        candidates = [normalised]
        # Godot exports may place .godot/imported resources beside the data
        # tree under assets/, while project resources remain assets/data/...
        # Android APKs add the APK assets directory in front of the project's
        # own assets/ tree, so res://assets/... is packaged as
        # assets/assets/.... Keep the exact project-relative path first, then
        # try that container prefix without accepting any rewritten path.
        if normalised.startswith("assets/"):
            candidates.append(f"assets/{normalised}")
        else:
            candidates.append(f"assets/{normalised}")
            candidates.append(f"assets/data/{normalised}")
        return candidates

    def find(self, resource_path: str) -> tuple[str, zipfile.ZipInfo] | None:
        for candidate in self._candidate_paths(resource_path):
            info = self.members.get(candidate)
            if info is not None:
                return candidate, info
        return None

    def read(self, resource_path: str) -> tuple[str, bytes] | None:
        found = self.find(resource_path)
        if found is None:
            return None
        path, info = found
        return path, self.archive.read(info)

    def non_empty(self, resource_path: str) -> tuple[str, int] | None:
        found = self.find(resource_path)
        if found is None:
            return None
        path, info = found
        if info.file_size <= 0:
            return path, 0
        # A ZIP header can claim a size, but reading one byte makes the
        # non-empty check explicit without loading an entire texture into RAM.
        with self.archive.open(info, "r") as handle:
            first_byte = handle.read(1)
        return path, info.file_size if first_byte else 0


def _add_error(
    errors: list[dict[str, Any]], code: str, message: str, **details: Any
) -> None:
    item: dict[str, Any] = {"code": code, "message": message}
    item.update(details)
    errors.append(item)


def _compare_package_json(
    package: PackageIndex,
    errors: list[dict[str, Any]],
    resource_path: str,
    source_bytes: bytes,
    label: str,
) -> bytes | None:
    package_value = package.read(resource_path)
    if package_value is None:
        _add_error(
            errors,
            "missing_package_json",
            f"APK is missing {label}: {resource_path}",
            path=resource_path,
        )
        return None
    package_path, package_bytes = package_value
    source_sha = _sha256_bytes(source_bytes)
    package_sha = _sha256_bytes(package_bytes)
    if source_sha != package_sha:
        _add_error(
            errors,
            "json_sha256_mismatch",
            f"APK {label} differs from source: {resource_path}",
            path=resource_path,
            source_sha256=source_sha,
            package_sha256=package_sha,
            package_path=package_path,
        )
    try:
        source_json = json.loads(source_bytes.decode("utf-8"))
        package_json = json.loads(package_bytes.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        _add_error(
            errors,
            "package_json_invalid",
            f"invalid JSON for {resource_path}: {exc}",
            path=resource_path,
        )
    else:
        if source_json != package_json:
            _add_error(
                errors,
                "json_content_mismatch",
                f"APK {label} JSON content differs from source: {resource_path}",
                path=resource_path,
            )
    return package_bytes


def verify(root: Path, apk: Path) -> dict[str, Any]:
    errors: list[dict[str, Any]] = []
    counts: dict[str, int] = {
        "formal_registry_entries": 0,
        "implemented_playable_entries": 0,
        "runtime_files_checked": 0,
        "visual_files_checked": 0,
        "authored_chunk_refs": 0,
        "unique_chunk_pngs": 0,
        "chunk_imports_checked": 0,
        "ctex_targets_checked": 0,
        "non_empty_ctex_targets": 0,
    }
    expected_counts = {
        "formal_registry_entries": EXPECTED_FORMAL_MAPS,
        "implemented_playable_entries": EXPECTED_FORMAL_MAPS,
        "authored_chunk_refs": EXPECTED_AUTHORED_CHUNKS,
        "unique_chunk_pngs": EXPECTED_UNIQUE_CHUNKS,
    }
    report: dict[str, Any] = {
        "contract": "hardcore.formal_map_apk_closure.v1",
        "ok": False,
        "scope": "formal_registry_runtime_visual_ground_chunk_closure_only",
        "scopeLimitations": [
            "The 922-entry runtime asset/wall texture chain is not verified by this tool.",
            "Source PNGs are not required in the APK; their .import -> .ctex closure is required.",
            "ETC2 is not required; ordinary non-empty .ctex targets are accepted.",
        ],
        "root": str(root),
        "apk": str(apk),
        "rootHEAD": _read_git_head(root),
        "apkSHA": "",
        "expectedCounts": expected_counts,
        "counts": counts,
        "registry": {
            "sourcePath": REGISTRY_RELATIVE_PATH,
            "packagePath": None,
            "sourceSHA256": None,
            "packageSHA256": None,
        },
        "errors": errors,
    }

    if not root.is_dir():
        _add_error(errors, "missing_root", f"source root is not a directory: {root}")
        return report
    if not apk.is_file():
        _add_error(errors, "missing_apk", f"APK is not a file: {apk}")
        return report

    try:
        report["apkSHA"] = _sha256_file(apk)
    except OSError as exc:
        _add_error(errors, "apk_read_error", f"cannot hash APK: {exc}")
        return report

    registry_path = root / Path(REGISTRY_RELATIVE_PATH)
    registry, registry_bytes, registry_error = _read_json_file(registry_path)
    if registry_error is not None or registry is None or registry_bytes is None:
        _add_error(errors, "source_registry_error", registry_error or "source registry unavailable")
        return report

    maps_value = registry.get("maps")
    maps = list(maps_value) if isinstance(maps_value, list) else []
    counts["formal_registry_entries"] = len(maps)
    playable_maps = [
        entry
        for entry in maps
        if isinstance(entry, dict)
        and str(entry.get("release_state", "")) == "implemented_playable"
    ]
    counts["implemented_playable_entries"] = len(playable_maps)
    if len(maps) != EXPECTED_FORMAL_MAPS:
        _add_error(
            errors,
            "formal_registry_count_mismatch",
            f"formal registry has {len(maps)} entries, expected {EXPECTED_FORMAL_MAPS}",
            expected=EXPECTED_FORMAL_MAPS,
            actual=len(maps),
        )
    if len(playable_maps) != EXPECTED_FORMAL_MAPS:
        _add_error(
            errors,
            "implemented_playable_count_mismatch",
            f"registry has {len(playable_maps)} implemented_playable entries, expected {EXPECTED_FORMAL_MAPS}",
            expected=EXPECTED_FORMAL_MAPS,
            actual=len(playable_maps),
        )

    unique_maps: set[str] = set()
    unique_runtime_ids: set[int] = set()
    source_json_by_path: dict[str, tuple[Path, bytes, dict[str, Any]]] = {}
    unique_chunk_paths: set[str] = set()
    source_chunk_digests: dict[str, str] = {}

    try:
        with zipfile.ZipFile(apk, "r") as archive:
            package = PackageIndex(archive, errors)
            registry_package = package.read(REGISTRY_RELATIVE_PATH)
            report["registry"]["sourceSHA256"] = _sha256_bytes(registry_bytes)
            if registry_package is None:
                _add_error(
                    errors,
                    "missing_package_registry",
                    f"APK is missing formal registry: {REGISTRY_RELATIVE_PATH}",
                )
            else:
                package_registry_path, package_registry_bytes = registry_package
                report["registry"]["packagePath"] = package_registry_path
                report["registry"]["packageSHA256"] = _sha256_bytes(package_registry_bytes)
                if package_registry_bytes != registry_bytes:
                    _add_error(
                        errors,
                        "registry_sha256_mismatch",
                        "APK formal registry does not match source registry",
                        source_sha256=_sha256_bytes(registry_bytes),
                        package_sha256=_sha256_bytes(package_registry_bytes),
                    )

            for entry in maps:
                if not isinstance(entry, dict):
                    _add_error(errors, "invalid_registry_entry", "registry map entry is not an object")
                    continue
                map_key = str(entry.get("map_key", ""))
                runtime_map_id = _as_integer(entry.get("runtime_map_id"))
                if not map_key or map_key in unique_maps:
                    _add_error(errors, "duplicate_or_empty_map_key", f"invalid map_key: {map_key!r}")
                unique_maps.add(map_key)
                if runtime_map_id is None or runtime_map_id in unique_runtime_ids:
                    _add_error(
                        errors,
                        "duplicate_or_invalid_runtime_map_id",
                        f"invalid or duplicate runtime_map_id for {map_key}: {entry.get('runtime_map_id')!r}",
                    )
                if runtime_map_id is not None:
                    unique_runtime_ids.add(runtime_map_id)

                runtime_path = _normalise_resource_path(entry.get("runtime_path"))
                expected_runtime_path = f"{RUNTIME_ROOT}{map_key}.runtime.json"
                if runtime_path != expected_runtime_path:
                    _add_error(
                        errors,
                        "runtime_path_mapping_mismatch",
                        f"registry runtime_path for {map_key} is not the formal map runtime path",
                        expected=expected_runtime_path,
                        actual=runtime_path,
                    )
                    runtime_path = expected_runtime_path
                visual_path = f"{RUNTIME_ROOT}{map_key}.visual.json"

                if runtime_path not in source_json_by_path:
                    runtime_file = root / Path(runtime_path)
                    runtime_json, runtime_bytes, runtime_error = _read_json_file(runtime_file)
                    if runtime_error is not None or runtime_json is None or runtime_bytes is None:
                        _add_error(errors, "source_runtime_error", runtime_error or f"missing runtime: {runtime_file}")
                    else:
                        source_json_by_path[runtime_path] = (runtime_file, runtime_bytes, runtime_json)
                runtime_record = source_json_by_path.get(runtime_path)
                if runtime_record is not None:
                    _, runtime_bytes, runtime_json = runtime_record
                    _compare_package_json(
                        package,
                        errors,
                        runtime_path,
                        runtime_bytes,
                        "runtime JSON",
                    )
                    counts["runtime_files_checked"] += 1
                    source = runtime_json.get("source")
                    if isinstance(source, dict):
                        if source.get("map_id") != map_key:
                            _add_error(
                                errors,
                                "runtime_identity_mismatch",
                                f"runtime source.map_id mismatch for {map_key}",
                            )
                        if _as_integer(source.get("runtime_map_id")) != runtime_map_id:
                            _add_error(
                                errors,
                                "runtime_identity_mismatch",
                                f"runtime source.runtime_map_id mismatch for {map_key}",
                            )

                visual_file = root / Path(visual_path)
                visual_json, visual_bytes, visual_error = _read_json_file(visual_file)
                if visual_error is not None or visual_json is None or visual_bytes is None:
                    _add_error(errors, "source_visual_error", visual_error or f"missing visual: {visual_file}")
                    continue
                _compare_package_json(
                    package,
                    errors,
                    visual_path,
                    visual_bytes,
                    "visual JSON",
                )
                counts["visual_files_checked"] += 1
                if visual_json.get("map_id") != map_key:
                    _add_error(
                        errors,
                        "visual_identity_mismatch",
                        f"visual map_id mismatch for {map_key}",
                    )
                if _as_integer(visual_json.get("runtime_map_id")) != runtime_map_id:
                    _add_error(
                        errors,
                        "visual_identity_mismatch",
                        f"visual runtime_map_id mismatch for {map_key}",
                    )
                chunks = visual_json.get("chunks")
                if not isinstance(chunks, list):
                    _add_error(errors, "visual_chunks_invalid", f"visual chunks is not a list: {visual_path}")
                    continue
                coverage = visual_json.get("coverage")
                if isinstance(coverage, dict):
                    for coverage_key in ("required_chunk_count", "packaged_chunk_count"):
                        coverage_count = _as_integer(coverage.get(coverage_key))
                        if coverage_count != len(chunks):
                            _add_error(
                                errors,
                                "visual_coverage_count_mismatch",
                                f"{visual_path} {coverage_key} does not match chunk list",
                                expected=len(chunks),
                                actual=coverage.get(coverage_key),
                            )
                    if coverage.get("complete") is not True:
                        _add_error(errors, "visual_coverage_incomplete", f"visual coverage is not complete: {visual_path}")
                for chunk in chunks:
                    if not isinstance(chunk, dict):
                        _add_error(errors, "invalid_visual_chunk", f"visual chunk is not an object: {visual_path}")
                        continue
                    counts["authored_chunk_refs"] += 1
                    image_path = _normalise_resource_path(chunk.get("image"))
                    declared_sha = str(chunk.get("sha256", "")).lower()
                    if image_path is None or not image_path.startswith(FORMAL_CHUNK_ROOT) or not image_path.endswith(".png"):
                        _add_error(
                            errors,
                            "invalid_formal_chunk_path",
                            f"visual chunk is outside the formal SHA-256 chunk store: {chunk.get('image')!r}",
                            visual_path=visual_path,
                        )
                        continue
                    if not SHA256_RE.fullmatch(declared_sha):
                        _add_error(
                            errors,
                            "invalid_chunk_sha256",
                            f"visual chunk has invalid sha256: {image_path}",
                            declared_sha256=declared_sha,
                        )
                        continue
                    expected_sha_from_name = Path(image_path).stem.lower()
                    if expected_sha_from_name != declared_sha:
                        _add_error(
                            errors,
                            "chunk_name_sha256_mismatch",
                            f"chunk filename digest differs from manifest digest: {image_path}",
                            filename_sha256=expected_sha_from_name,
                            declared_sha256=declared_sha,
                        )
                    unique_chunk_paths.add(image_path)
                    source_chunk_digests[image_path] = declared_sha

            counts["unique_chunk_pngs"] = len(unique_chunk_paths)
            for image_path, declared_sha in sorted(source_chunk_digests.items()):
                source_png = root / Path(image_path)
                if not source_png.is_file() or source_png.is_symlink():
                    _add_error(errors, "missing_source_chunk_png", f"source PNG is missing: {source_png}")
                else:
                    actual_sha = _sha256_file(source_png)
                    if actual_sha != declared_sha:
                        _add_error(
                            errors,
                            "source_chunk_sha256_mismatch",
                            f"source PNG SHA-256 differs from visual manifest: {image_path}",
                            path=image_path,
                            expected=declared_sha,
                            actual=actual_sha,
                        )
                import_path = f"{image_path}.import"
                import_value = package.read(import_path)
                if import_value is None:
                    _add_error(
                        errors,
                        "missing_chunk_import",
                        f"APK is missing formal chunk import metadata: {import_path}",
                        path=import_path,
                    )
                    continue
                package_import_path, import_bytes = import_value
                counts["chunk_imports_checked"] += 1
                if not import_bytes:
                    _add_error(errors, "empty_chunk_import", f"APK chunk import is empty: {package_import_path}")
                    continue
                import_text = import_bytes.decode("utf-8", errors="replace")
                source_match = SOURCE_FILE_RE.search(import_text)
                # Exported Godot .import members may omit source_file after
                # import metadata is packaged. The manifest member path still
                # binds this metadata to image_path; when source_file is
                # present, retain the exact identity check.
                if (
                    source_match is not None
                    and _normalise_resource_path(source_match.group(1)) != image_path
                ):
                    _add_error(
                        errors,
                        "chunk_import_source_mismatch",
                        f"chunk import source_file does not point to {image_path}",
                        import_path=package_import_path,
                    )
                remap_text = import_text.split("[deps]", 1)[0]
                remap_targets = [
                    _normalise_resource_path(match)
                    for match in CTEX_REFERENCE_RE.findall(remap_text)
                ]
                remap_targets = [target for target in remap_targets if target is not None]
                all_targets = [
                    _normalise_resource_path(match)
                    for match in CTEX_REFERENCE_RE.findall(import_text)
                ]
                all_targets = [target for target in all_targets if target is not None]
                if not remap_targets:
                    _add_error(
                        errors,
                        "missing_chunk_remap_ctex",
                        f"chunk import has no remap .ctex target: {package_import_path}",
                        import_path=package_import_path,
                    )
                for target in sorted(set(all_targets)):
                    counts["ctex_targets_checked"] += 1
                    non_empty = package.non_empty(target)
                    if non_empty is None:
                        _add_error(
                            errors,
                            "missing_ctex_target",
                            f"chunk import target is absent from APK: {target}",
                            import_path=package_import_path,
                            target=target,
                        )
                    elif non_empty[1] <= 0:
                        _add_error(
                            errors,
                            "empty_ctex_target",
                            f"chunk import target is empty in APK: {target}",
                            import_path=package_import_path,
                            target=target,
                        )
                    else:
                        counts["non_empty_ctex_targets"] += 1
    except (OSError, zipfile.BadZipFile) as exc:
        _add_error(errors, "apk_zip_error", f"cannot inspect APK ZIP: {exc}")

    for key, expected in expected_counts.items():
        actual = counts.get(key, 0)
        if actual != expected:
            _add_error(
                errors,
                "source_count_mismatch",
                f"{key} is {actual}, expected {expected}",
                key=key,
                expected=expected,
                actual=actual,
            )
    report["ok"] = not errors
    return report


def _write_report(path: Path, report: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, type=Path, help="source project root")
    parser.add_argument("--apk", required=True, type=Path, help="APK ZIP to inspect")
    parser.add_argument("--out", required=True, type=Path, help="JSON evidence output path")
    args = parser.parse_args(argv)

    report = verify(args.root.resolve(), args.apk.resolve())
    try:
        _write_report(args.out.resolve(), report)
    except OSError as exc:
        print(f"cannot write evidence JSON: {exc}", file=sys.stderr)
        return 2

    status = "FORMAL_MAP_APK_CLOSURE_PASS" if report["ok"] else "FORMAL_MAP_APK_CLOSURE_FAIL"
    print(
        f"{status} maps={report['counts']['formal_registry_entries']} "
        f"refs={report['counts']['authored_chunk_refs']} "
        f"unique_chunks={report['counts']['unique_chunk_pngs']} "
        f"ctex_targets={report['counts']['ctex_targets_checked']} "
        f"errors={len(report['errors'])} out={args.out.resolve()}"
    )
    return 0 if report["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
