#!/usr/bin/env python3
"""Migrate the frozen authored map placements into formal map documents.

This migration is intentionally narrower than the older map-identity and map
runtime tools.  The only source of placement rows is the explicitly supplied
snapshot payload.  The exact map identity registry maps each legacy document
to one formal document.  For every row only these identity projections are
written:

* ``authority_ref.map_id`` (creating ``authority_ref`` only when it is absent),
* ``semantic_id``, and
* ``spawn_group_id``.

All other source row values, including coordinates, monster identity,
classification, timing fields, and placement evidence, are copied unchanged.
The tool is deterministic, fail-closed, and supports a read-only ``--check``
mode.  It also emits an audit manifest containing source hashes, non-identity
row fingerprints, target non-spawn fingerprints, and frozen runtime hashes.

The source snapshot is never written.  This file deliberately does not call
any map build/publish code and does not touch the release registry.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import math
import os
import subprocess
import sys
from pathlib import Path
from typing import Any, Iterable


LAYERS = ("monster_spawn", "boss_spawn")
SANDBOX_ID = "sandbox_64"
IDENTITY_CONTRACT = "hardcore.formal_map_identity.v1"
AUDIT_ID = "hardcore.map_precise_placement_migration.v1"
AUDIT_SCHEMA_VERSION = 1
BASELINE_TARGET_HEAD = "6546dfecfb276e97d856235bb190a12b878797a3"
SOURCE_MAPS_HEAD = "4f35634d166d86280bac9cf367f5864242ee3168"
SOURCE_MANIFEST_SHA256 = "9642E94B4CF86F18082428D958148883CB4735D02F85744F91F629329C2456B1"
SPECIAL_NORMAL_IDS = (39, 57, 74, 77, 90, 121, 137, 142)
EXPECTED_FORMAL_MAP_COUNT = 67
EXPECTED_MONSTER_COUNT = 1607
EXPECTED_BOSS_COUNT = 273
EXPECTED_TOTAL_COUNT = 1880
EXPECTED_RELEASE_ENTRY_COUNT = 11
EXPECTED_RELEASE_RUNTIME_FINGERPRINT_SHA256 = "768BA7F180B2657C3FA114BB00E44FB4701CC945DF98C4020685E2E570EE90B5"
EXPECTED_RELEASE_REGISTRY_SHA256 = "3EEFA27BA2C12D09C4817EDF4BA60C57C8F18E044502E55EDF4E2FC10EE40D4D"

REGISTRY_REL = Path("assets/data/map_design/map_identity_registry.json")
CATALOG_REL = Path("assets/data/runtime/canonical_monster_catalog.json")
RELEASE_REGISTRY_REL = Path("assets/data/runtime/map_editor/map_runtime_release_registry.json")
AUDIT_REL = Path("assets/data/map_design/map_precise_placement_migration_authority_v1.json")


class MigrationError(RuntimeError):
    """A fail-closed validation or migration error."""


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest().upper()


def sha256_file(path: Path) -> str:
    return sha256_bytes(path.read_bytes())


def read_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise MigrationError(f"cannot read JSON {path}: {exc}") from exc


def _canonical_number(value: int | float) -> int | float:
    if isinstance(value, bool):
        return value
    if isinstance(value, float):
        if not math.isfinite(value):
            raise MigrationError("non-finite JSON number is not permitted")
        # JSON 1 and 1.0 represent the same normalized value for this audit.
        if value == 0.0 or value.is_integer():
            return int(value)
    return value


def normalize_json(value: Any) -> Any:
    """Normalize JSON for semantic fingerprints without changing list order."""

    if isinstance(value, bool) or value is None or isinstance(value, str):
        return value
    if isinstance(value, int) and not isinstance(value, bool):
        return value
    if isinstance(value, float):
        return _canonical_number(value)
    if isinstance(value, list):
        return [normalize_json(item) for item in value]
    if isinstance(value, dict):
        return {str(key): normalize_json(value[key]) for key in sorted(value)}
    raise MigrationError(f"unsupported JSON value type: {type(value).__name__}")


def canonical_json_bytes(value: Any) -> bytes:
    normalized = normalize_json(value)
    try:
        text = json.dumps(
            normalized,
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
            allow_nan=False,
        )
    except (TypeError, ValueError) as exc:
        raise MigrationError(f"cannot canonicalize JSON: {exc}") from exc
    return text.encode("utf-8")


def canonical_fingerprint(value: Any) -> str:
    return sha256_bytes(canonical_json_bytes(value))


def pretty_json_bytes(value: Any, newline: bytes = b"\n") -> bytes:
    try:
        text = json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True, allow_nan=False) + "\n"
    except (TypeError, ValueError) as exc:
        raise MigrationError(f"cannot serialize JSON: {exc}") from exc
    raw = text.encode("utf-8")
    if newline == b"\r\n":
        raw = raw.replace(b"\r\n", b"\n").replace(b"\n", b"\r\n")
    return raw


def document_path(root: Path, map_id: str) -> Path:
    return root / "map_editor_workspace" / map_id / f"{map_id}.editor.json"


def relative_posix(path: Path, root: Path) -> str:
    try:
        return path.resolve().relative_to(root.resolve()).as_posix()
    except ValueError as exc:
        raise MigrationError(f"path escapes root: {path}") from exc


def require_file(path: Path, label: str) -> None:
    if not path.is_file():
        raise MigrationError(f"missing {label}: {path}")


def numeric_id(value: Any, label: str) -> int:
    # Placement identities must be exact numeric canonical IDs.  Names,
    # aliases, fuzzy strings, and booleans are never accepted here.
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise MigrationError(f"{label} is not an exact numeric monster_id: {value!r}")
    if isinstance(value, float) and (not math.isfinite(value) or not value.is_integer()):
        raise MigrationError(f"{label} is not an integral monster_id: {value!r}")
    result = int(value)
    if result <= 0:
        raise MigrationError(f"{label} is not a positive monster_id: {value!r}")
    return result


def numeric_runtime_id(value: Any, label: str) -> int:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise MigrationError(f"{label} is not a numeric runtime_map_id: {value!r}")
    if isinstance(value, float) and (not math.isfinite(value) or not value.is_integer()):
        raise MigrationError(f"{label} is not an integral runtime_map_id: {value!r}")
    return int(value)


def verify_target_baseline_lineage(target_root: Path) -> bool:
    """Require the fixed migration baseline to be an ancestor of target HEAD.

    The current HEAD is intentionally used only as a transient git query.  It
    is never copied into the deterministic audit manifest, so advancing the
    worktree with an unrelated descendant does not create audit churn.
    """

    def run_git(*arguments: str) -> subprocess.CompletedProcess[str]:
        try:
            return subprocess.run(
                ["git", *arguments],
                cwd=target_root,
                check=False,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                encoding="utf-8",
                errors="replace",
            )
        except OSError as exc:
            raise MigrationError(f"cannot execute git for target lineage: {exc}") from exc

    baseline = run_git("rev-parse", "--verify", f"{BASELINE_TARGET_HEAD}^{{commit}}")
    if baseline.returncode != 0 or baseline.stdout.strip().lower() != BASELINE_TARGET_HEAD.lower():
        detail = baseline.stderr.strip() or baseline.stdout.strip()
        raise MigrationError(
            "target baseline commit is not resolvable in the target Git tree: "
            f"{BASELINE_TARGET_HEAD} ({detail})"
        )
    current = run_git("rev-parse", "--verify", "HEAD^{commit}")
    if current.returncode != 0 or not current.stdout.strip():
        detail = current.stderr.strip() or current.stdout.strip()
        raise MigrationError(f"target HEAD is not a resolvable Git commit: {detail}")
    ancestor = run_git("merge-base", "--is-ancestor", BASELINE_TARGET_HEAD, "HEAD")
    if ancestor.returncode != 0:
        detail = ancestor.stderr.strip()
        suffix = f" ({detail})" if detail else ""
        raise MigrationError(
            f"target HEAD is not descended from baseline {BASELINE_TARGET_HEAD}{suffix}"
        )
    return True


def _valid_coordinate(tile: Any) -> bool:
    if not isinstance(tile, list) or len(tile) != 2:
        return False
    for value in tile:
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            return False
        if isinstance(value, float) and not math.isfinite(value):
            return False
    return True


def non_spawn_projection(document: dict[str, Any]) -> dict[str, Any]:
    projected = copy.deepcopy(document)
    layers = projected.get("layers")
    if not isinstance(layers, dict):
        raise MigrationError("document layers must be an object")
    for layer in LAYERS:
        layers.pop(layer, None)
    return projected


def non_spawn_fingerprint(document: dict[str, Any]) -> str:
    return canonical_fingerprint(non_spawn_projection(document))


def non_identity_projection(row: dict[str, Any]) -> dict[str, Any]:
    """Remove exactly the three permitted identity projections."""

    projected = copy.deepcopy(row)
    projected.pop("semantic_id", None)
    projected.pop("spawn_group_id", None)
    authority = projected.get("authority_ref")
    if isinstance(authority, dict):
        authority.pop("map_id", None)
        # A missing authority_ref and a newly-created map_id-only authority_ref
        # are the same non-identity payload.  Other authority metadata remains.
        if not authority:
            projected.pop("authority_ref", None)
    return projected


def row_fingerprint(row: dict[str, Any]) -> str:
    return canonical_fingerprint(non_identity_projection(row))


def fingerprint_list_hash(values: Iterable[str]) -> str:
    return canonical_fingerprint(list(values))


def load_source_manifest(source_root: Path, manifest_path: Path | None) -> tuple[dict[str, Any], str, dict[str, dict[str, Any]]]:
    path = (manifest_path or source_root.parent / "file_manifest.json").resolve()
    require_file(path, "source snapshot manifest")
    actual_sha = sha256_file(path)
    if actual_sha != SOURCE_MANIFEST_SHA256:
        raise MigrationError(
            f"source manifest hash mismatch: expected {SOURCE_MANIFEST_SHA256}, got {actual_sha}"
        )
    manifest = read_json(path)
    if not isinstance(manifest, list):
        raise MigrationError("source snapshot manifest must be a JSON array")
    index: dict[str, dict[str, Any]] = {}
    for record in manifest:
        if not isinstance(record, dict) or not isinstance(record.get("path"), str):
            raise MigrationError("source snapshot manifest contains an invalid record")
        key = record["path"].replace("\\", "/")
        if key in index:
            raise MigrationError(f"source snapshot manifest has duplicate path: {key}")
        index[key] = record
    return {"path": relative_posix(path, source_root.parent), "record_count": len(manifest)}, actual_sha, index


def verify_source_file_manifest(
    source_path: Path,
    source_root: Path,
    manifest_index: dict[str, dict[str, Any]],
) -> None:
    rel = relative_posix(source_path, source_root).replace("\\", "/")
    record = manifest_index.get(rel)
    if record is None:
        raise MigrationError(f"source document missing from frozen manifest: {rel}")
    actual_sha = sha256_file(source_path)
    actual_size = source_path.stat().st_size
    expected_sha = str(record.get("sha256", "")).upper()
    expected_size = record.get("size_bytes")
    if actual_sha != expected_sha or actual_size != expected_size:
        raise MigrationError(
            f"source snapshot file changed: {rel} "
            f"expected={expected_size}/{expected_sha} actual={actual_size}/{actual_sha}"
        )


def validate_registry(registry: dict[str, Any]) -> list[dict[str, Any]]:
    if not isinstance(registry, dict):
        raise MigrationError("map identity registry must be an object")
    maps = registry.get("maps")
    if not isinstance(maps, list) or len(maps) != EXPECTED_FORMAL_MAP_COUNT:
        raise MigrationError(f"map identity registry maps count must be {EXPECTED_FORMAL_MAP_COUNT}")
    if int(registry.get("formal_map_count", -1)) != EXPECTED_FORMAL_MAP_COUNT:
        raise MigrationError("map identity registry formal_map_count mismatch")
    if registry.get("sandbox_excluded") != SANDBOX_ID:
        raise MigrationError("map identity registry sandbox exclusion mismatch")
    legacy_seen: set[str] = set()
    formal_seen: set[str] = set()
    for index, record in enumerate(maps):
        if not isinstance(record, dict):
            raise MigrationError(f"map identity record {index} is not an object")
        legacy = record.get("legacy_map_id")
        formal = record.get("map_id")
        if not isinstance(legacy, str) or not legacy or not isinstance(formal, str) or not formal:
            raise MigrationError(f"map identity record {index} has invalid IDs")
        if legacy in legacy_seen or formal in formal_seen:
            raise MigrationError(f"duplicate map identity at record {index}: {legacy} -> {formal}")
        legacy_seen.add(legacy)
        formal_seen.add(formal)
        numeric_runtime_id(record.get("runtime_map_id"), f"registry[{legacy}].runtime_map_id")
        if record.get("legacy_map_id") == SANDBOX_ID or formal == SANDBOX_ID:
            raise MigrationError("sandbox_64 must not be a formal registry map")
    return maps


def validate_catalog(catalog: dict[str, Any]) -> dict[str, Any]:
    if not isinstance(catalog, dict) or not isinstance(catalog.get("entries_by_id"), dict):
        raise MigrationError("canonical monster catalog entries_by_id missing")
    authority = catalog.get("special_normal_spawn_authority")
    if not isinstance(authority, dict):
        raise MigrationError("canonical special_normal authority missing")
    ids = tuple(int(value) for value in authority.get("canonical_monster_ids", []))
    if ids != SPECIAL_NORMAL_IDS:
        raise MigrationError(f"special_normal canonical IDs mismatch: {ids!r}")
    if authority.get("production_active") is not True:
        raise MigrationError("special_normal authority is not production_active")
    for monster_id in SPECIAL_NORMAL_IDS:
        entry = catalog["entries_by_id"].get(str(monster_id))
        if not isinstance(entry, dict):
            raise MigrationError(f"special_normal canonical entry missing: {monster_id}")
        spawn = entry.get("spawn_authority")
        if not isinstance(spawn, dict):
            raise MigrationError(f"special_normal spawn authority missing: {monster_id}")
        expected = {
            "spawn_classification": "special_normal",
            "placement_kind": "monster_spawn",
            "respawn_policy_id": "special_normal",
            "respawn_seconds": 900,
            "random_seconds": 0,
            "count": 1,
            "max_alive": 1,
        }
        for field, value in expected.items():
            if spawn.get(field) != value:
                raise MigrationError(f"special_normal authority mismatch id={monster_id} field={field}")
        if entry.get("runtime_allowed") is not True or entry.get("status") != "formal":
            raise MigrationError(f"special_normal entry is not runtime formal: {monster_id}")
    return catalog


def validate_source_document(
    document: dict[str, Any],
    legacy_map_id: str,
    catalog: dict[str, Any],
) -> dict[str, list[dict[str, Any]]]:
    if not isinstance(document, dict):
        raise MigrationError(f"source document is not an object: {legacy_map_id}")
    if document.get("map_id") != legacy_map_id:
        raise MigrationError(
            f"source document map_id mismatch {legacy_map_id}: {document.get('map_id')!r}"
        )
    layers = document.get("layers")
    if not isinstance(layers, dict):
        raise MigrationError(f"source layers missing: {legacy_map_id}")
    result: dict[str, list[dict[str, Any]]] = {}
    entries = catalog["entries_by_id"]
    for layer in LAYERS:
        rows = layers.get(layer)
        if not isinstance(rows, list):
            raise MigrationError(f"source layer {legacy_map_id}:{layer} is not an array")
        result[layer] = []
        for index, row in enumerate(rows):
            if not isinstance(row, dict):
                raise MigrationError(f"source row is not an object: {legacy_map_id}:{layer}:{index}")
            if row.get("kind") != layer:
                raise MigrationError(
                    f"illegal layer placement kind {legacy_map_id}:{layer}:{index}: {row.get('kind')!r}"
                )
            if row.get("runtime_export") is not True:
                raise MigrationError(f"non-runtime placement {legacy_map_id}:{layer}:{index}")
            if not _valid_coordinate(row.get("tile")):
                raise MigrationError(f"invalid tile placement {legacy_map_id}:{layer}:{index}")
            monster_id = numeric_id(row.get("monster_id"), f"source {legacy_map_id}:{layer}:{index}")
            entry = entries.get(str(monster_id))
            if not isinstance(entry, dict):
                raise MigrationError(f"unknown monster exact ID {monster_id} at {legacy_map_id}:{layer}:{index}")
            if entry.get("runtime_allowed") is not True or entry.get("status") != "formal":
                raise MigrationError(f"disabled/non-formal monster exact ID {monster_id} at {legacy_map_id}:{layer}:{index}")
            result[layer].append(row)
    return result


def project_row_identity(row: dict[str, Any], formal_map_id: str, layer: str, ordinal: int) -> dict[str, Any]:
    projected = copy.deepcopy(row)
    if "authority_ref" not in projected:
        projected["authority_ref"] = {"map_id": formal_map_id}
    elif not isinstance(projected["authority_ref"], dict):
        raise MigrationError(f"authority_ref must be an object or absent: {formal_map_id}:{layer}:{ordinal}")
    else:
        projected["authority_ref"]["map_id"] = formal_map_id
    projected["semantic_id"] = f"mse.placement.v1.{formal_map_id}.{layer}.{ordinal:06d}"
    projected["spawn_group_id"] = f"mse.group.v1.{formal_map_id}.{layer}.{ordinal:06d}"
    return projected


def runtime_release_fingerprint(root: Path) -> dict[str, Any]:
    registry_path = root / RELEASE_REGISTRY_REL
    require_file(registry_path, "map runtime release registry")
    registry = read_json(registry_path)
    if not isinstance(registry, dict) or not isinstance(registry.get("maps"), list):
        raise MigrationError("map runtime release registry is invalid")
    maps = registry["maps"]
    if len(maps) != EXPECTED_RELEASE_ENTRY_COUNT:
        raise MigrationError(f"runtime release registry entries must remain {EXPECTED_RELEASE_ENTRY_COUNT}")
    referenced: list[str] = []
    for index, entry in enumerate(maps):
        if not isinstance(entry, dict) or not isinstance(entry.get("runtime_path"), str):
            raise MigrationError(f"runtime release registry entry {index} is invalid")
        runtime_path = entry["runtime_path"]
        if not runtime_path.startswith("res://"):
            raise MigrationError(f"runtime release path is not res://: {runtime_path}")
        rel = runtime_path[len("res://"):]
        if rel not in referenced:
            referenced.append(rel)
    # Include every runtime/visual artifact in the release directory, including
    # an unreferenced sample, so an audit cannot accidentally miss a frozen
    # release-side file.
    release_dir = root / "assets/data/runtime/map_editor"
    files = sorted(
        path for path in release_dir.rglob("*")
        if path.is_file() and (path.name.endswith(".runtime.json") or path.name.endswith(".visual.json"))
    )
    artifacts: list[dict[str, Any]] = []
    for path in files:
        artifacts.append({
            "path": relative_posix(path, root),
            "size_bytes": path.stat().st_size,
            "sha256": sha256_file(path),
        })
    payload = {
        "registry_path": RELEASE_REGISTRY_REL.as_posix(),
        "registry_sha256": sha256_file(registry_path),
        "entry_count": len(maps),
        "entry_map_keys": [entry.get("map_key") for entry in maps],
        "registry_runtime_paths": referenced,
        "runtime_release_files": artifacts,
    }
    canonical_sha = canonical_fingerprint(payload)
    return {
        **payload,
        "canonical_sha256": canonical_sha,
        "baseline_expected": {
            "runtime_release_fingerprint_sha256": EXPECTED_RELEASE_RUNTIME_FINGERPRINT_SHA256,
            "registry_raw_sha256": EXPECTED_RELEASE_REGISTRY_SHA256,
        },
        "baseline_actual": {
            "runtime_release_fingerprint_sha256": canonical_sha,
            "registry_raw_sha256": payload["registry_sha256"],
        },
    }


def assert_release_baseline(fingerprint: dict[str, Any], label: str = "runtime release") -> None:
    """Require the release side to match the pre-migration frozen baseline."""

    expected = {
        "runtime_release_fingerprint_sha256": EXPECTED_RELEASE_RUNTIME_FINGERPRINT_SHA256,
        "registry_raw_sha256": EXPECTED_RELEASE_REGISTRY_SHA256,
    }
    actual = {
        "runtime_release_fingerprint_sha256": str(fingerprint.get("canonical_sha256", "")).upper(),
        "registry_raw_sha256": str(fingerprint.get("registry_sha256", "")).upper(),
    }
    if actual != expected:
        raise MigrationError(
            f"{label} differs from frozen baseline: expected={expected} actual={actual}"
        )
    if fingerprint.get("baseline_expected") != expected or fingerprint.get("baseline_actual") != actual:
        raise MigrationError(f"{label} baseline expected/actual metadata is inconsistent")


def assert_release_fingerprint_equal(before: dict[str, Any], after: dict[str, Any]) -> None:
    if canonical_json_bytes(before) != canonical_json_bytes(after):
        raise MigrationError("frozen runtime release registry or release artifact changed")


def _existing_audit(audit_path: Path) -> dict[str, Any] | None:
    if not audit_path.exists():
        return None
    value = read_json(audit_path)
    if not isinstance(value, dict) or value.get("audit_id") != AUDIT_ID:
        raise MigrationError(f"existing audit manifest is not {AUDIT_ID}: {audit_path}")
    if value.get("schema_version") != AUDIT_SCHEMA_VERSION:
        raise MigrationError("existing audit manifest schema version mismatch")
    return value


def _old_map_audit(existing: dict[str, Any] | None, legacy_map_id: str) -> dict[str, Any] | None:
    if not existing:
        return None
    maps = existing.get("maps")
    if not isinstance(maps, list):
        raise MigrationError("existing audit maps is not an array")
    for record in maps:
        if isinstance(record, dict) and record.get("legacy_map_id") == legacy_map_id:
            return record
    return None


def audit_requires_refresh(existing: dict[str, Any] | None) -> bool:
    """Identify an audit from before the lineage/release baseline contract."""

    if existing is None:
        return False
    baseline = existing.get("baseline")
    release = existing.get("release_freeze")
    expected_release = {
        "runtime_release_fingerprint_sha256": EXPECTED_RELEASE_RUNTIME_FINGERPRINT_SHA256,
        "registry_raw_sha256": EXPECTED_RELEASE_REGISTRY_SHA256,
    }
    return (
        not isinstance(baseline, dict)
        or baseline.get("target_baseline_lineage_verified") is not True
        or not isinstance(release, dict)
        or release.get("canonical_sha256") != EXPECTED_RELEASE_RUNTIME_FINGERPRINT_SHA256
        or release.get("registry_sha256") != EXPECTED_RELEASE_REGISTRY_SHA256
        or release.get("baseline_expected") != expected_release
        or release.get("baseline_actual") != expected_release
    )


def make_map_audit(
    mapping: dict[str, Any],
    source_path: Path,
    source_root: Path,
    source_doc: dict[str, Any],
    target_path: Path,
    target_before_bytes: bytes,
    target_before_doc: dict[str, Any],
    desired_doc: dict[str, Any],
    rows: dict[str, list[dict[str, Any]]],
    projected_rows: dict[str, list[dict[str, Any]]],
    prior: dict[str, Any] | None,
    target_root: Path,
) -> dict[str, Any]:
    source_sha = sha256_file(source_path)
    source_counts = {layer: len(rows[layer]) for layer in LAYERS}
    target_before_counts = {
        layer: len(target_before_doc.get("layers", {}).get(layer, [])) for layer in LAYERS
    }
    target_after_counts = {layer: len(projected_rows[layer]) for layer in LAYERS}
    source_hashes = {layer: [row_fingerprint(row) for row in rows[layer]] for layer in LAYERS}
    target_hashes = {layer: [row_fingerprint(row) for row in projected_rows[layer]] for layer in LAYERS}
    map_record: dict[str, Any] = {
        "legacy_map_id": mapping["legacy_map_id"],
        "formal_map_id": mapping["map_id"],
        # The editor document's existing runtime_map_id is deliberately
        # reported, not rewritten.  The identity registry's formal runtime
        # ID is recorded separately because this task does not authorize a
        # Runtime ID cutover.
        "target_runtime_map_id": numeric_runtime_id(target_before_doc.get("runtime_map_id"), f"target[{mapping['map_id']}].runtime_map_id"),
        "registry_runtime_map_id": numeric_runtime_id(mapping["runtime_map_id"], f"registry[{mapping['legacy_map_id']}].runtime_map_id"),
        "source_document_path": relative_posix(source_path, source_root),
        "source_document_sha256": source_sha,
        "source_document_size_bytes": source_path.stat().st_size,
        "source_counts": source_counts,
        "target_document_path": relative_posix(target_path, target_root),
        "target_document_sha256_before": sha256_bytes(target_before_bytes),
        "target_document_sha256_after": sha256_bytes(pretty_json_bytes(desired_doc, b"\r\n" if b"\r\n" in target_before_bytes else b"\n")),
        "target_counts_before": target_before_counts,
        "target_counts_after": target_after_counts,
        "target_non_spawn_fingerprint_before": non_spawn_fingerprint(target_before_doc),
        "target_non_spawn_fingerprint_after": non_spawn_fingerprint(desired_doc),
        "source_non_identity_fingerprint_list_sha256": {
            layer: fingerprint_list_hash(source_hashes[layer]) for layer in LAYERS
        },
        "target_non_identity_fingerprint_list_sha256": {
            layer: fingerprint_list_hash(target_hashes[layer]) for layer in LAYERS
        },
        "non_identity_fingerprints_by_layer": {
            layer: {
                "source_order": source_hashes[layer],
                "target_order": target_hashes[layer],
                "source_list_sha256": fingerprint_list_hash(source_hashes[layer]),
                "target_list_sha256": fingerprint_list_hash(target_hashes[layer]),
                "order_preserved": source_hashes[layer] == target_hashes[layer],
            }
            for layer in LAYERS
        },
        "identity_projection": {
            "authority_ref_map_id": mapping["map_id"],
            "semantic_id_rule": "mse.placement.v1.<formal_map_id>.<layer>.<source_order_1_based:06d>",
            "spawn_group_id_rule": "mse.group.v1.<formal_map_id>.<layer>.<source_order_1_based:06d>",
        },
    }
    if prior:
        for field in (
            "target_document_sha256_before",
            "target_non_spawn_fingerprint_before",
            "target_counts_before",
        ):
            if field in prior:
                map_record[field] = copy.deepcopy(prior[field])
    # These are required equality claims, kept explicit for machine audits.
    map_record["non_identity_diff_count"] = sum(
        source_hashes[layer] != target_hashes[layer] for layer in LAYERS
    )
    map_record["target_non_spawn_diff_count"] = int(
        map_record["target_non_spawn_fingerprint_before"]
        != map_record["target_non_spawn_fingerprint_after"]
    )
    return map_record


def build_audit_and_plan(
    source_root: Path,
    target_root: Path,
    source_manifest_sha: str,
    source_manifest_meta: dict[str, Any],
    manifest_index: dict[str, dict[str, Any]],
    registry: dict[str, Any],
    mappings: list[dict[str, Any]],
    catalog: dict[str, Any],
    release_before: dict[str, Any],
    target_lineage_verified: bool,
    existing: dict[str, Any] | None,
) -> tuple[dict[str, Any], list[dict[str, Any]], dict[str, Any]]:
    if target_lineage_verified is not True:
        raise MigrationError("target baseline lineage was not verified")
    assert_release_baseline(release_before, "runtime release before migration")
    global_semantics: set[str] = set()
    global_groups: set[str] = set()
    records: list[dict[str, Any]] = []
    plans: list[dict[str, Any]] = []
    totals = {"monster_spawn": 0, "boss_spawn": 0}
    target_before_totals = {"monster_spawn": 0, "boss_spawn": 0}
    missing_authority = 0
    missing_semantic = 0
    missing_group = 0
    semantic_duplicates = 0
    group_duplicates = 0
    nonidentity_diff = 0
    target_nonspawn_diff = 0
    illegal_placements = 0
    unknown_monsters = 0
    disabled_monsters = 0
    special_rows: dict[int, tuple[str, str, int]] = {}

    for mapping in mappings:
        legacy = mapping["legacy_map_id"]
        formal = mapping["map_id"]
        runtime_id = numeric_runtime_id(mapping["runtime_map_id"], f"registry[{legacy}].runtime_map_id")
        source_path = document_path(source_root, legacy)
        target_path = document_path(target_root, formal)
        require_file(source_path, f"source editor document {legacy}")
        require_file(target_path, f"formal target editor document {formal}")
        verify_source_file_manifest(source_path, source_root, manifest_index)
        source_doc = read_json(source_path)
        rows = validate_source_document(source_doc, legacy, catalog)
        target_before_bytes = target_path.read_bytes()
        target_before_doc = read_json(target_path)
        if not isinstance(target_before_doc, dict):
            raise MigrationError(f"target document is not an object: {formal}")
        if target_before_doc.get("map_id") != formal:
            raise MigrationError(f"target map_id mismatch {formal}: {target_before_doc.get('map_id')!r}")
        # Preserve the target document's existing runtime identity.  In this
        # migration the registry's new formal runtime ID is metadata only;
        # changing the document runtime_map_id would be an unauthorized
        # runtime cutover (some formal documents intentionally retain their
        # legacy runtime IDs).
        numeric_runtime_id(target_before_doc.get("runtime_map_id"), f"target[{formal}].runtime_map_id")
        if "legacy_map_id" in target_before_doc and target_before_doc.get("legacy_map_id") != legacy:
            raise MigrationError(f"target legacy_map_id mismatch {formal}: {target_before_doc.get('legacy_map_id')!r}")
        if "legacy_runtime_map_id" in target_before_doc:
            numeric_runtime_id(target_before_doc.get("legacy_runtime_map_id"), f"target[{formal}].legacy_runtime_map_id")
        target_layers = target_before_doc.get("layers")
        if not isinstance(target_layers, dict):
            raise MigrationError(f"target layers missing: {formal}")
        for layer in LAYERS:
            if not isinstance(target_layers.get(layer), list):
                raise MigrationError(f"target layer {formal}:{layer} is not an array")
            target_before_totals[layer] += len(target_layers[layer])

        projected_rows: dict[str, list[dict[str, Any]]] = {layer: [] for layer in LAYERS}
        for layer in LAYERS:
            totals[layer] += len(rows[layer])
            for zero_index, row in enumerate(rows[layer]):
                ordinal = zero_index + 1
                projected = project_row_identity(row, formal, layer, ordinal)
                projected_rows[layer].append(projected)
                # Verify only the three allowed identity projections changed.
                if row_fingerprint(row) != row_fingerprint(projected):
                    nonidentity_diff += 1
                authority = projected.get("authority_ref")
                if not isinstance(authority, dict) or not authority.get("map_id"):
                    missing_authority += 1
                elif authority.get("map_id") != formal:
                    raise MigrationError(f"authority_ref.map_id mismatch {formal}:{layer}:{ordinal}")
                semantic = projected.get("semantic_id")
                group = projected.get("spawn_group_id")
                if not isinstance(semantic, str) or not semantic:
                    missing_semantic += 1
                elif semantic in global_semantics:
                    semantic_duplicates += 1
                else:
                    global_semantics.add(semantic)
                if not isinstance(group, str) or not group:
                    missing_group += 1
                elif group in global_groups:
                    group_duplicates += 1
                else:
                    global_groups.add(group)
                monster_id = numeric_id(row.get("monster_id"), f"{legacy}:{layer}:{zero_index}")
                if monster_id in SPECIAL_NORMAL_IDS:
                    if layer != "monster_spawn":
                        raise MigrationError(f"special_normal ID {monster_id} is not in monster_spawn")
                    if monster_id in special_rows:
                        raise MigrationError(f"duplicate special_normal ID {monster_id}")
                    special_rows[monster_id] = (legacy, formal, ordinal)

        desired_doc = copy.deepcopy(target_before_doc)
        desired_doc["layers"]["monster_spawn"] = projected_rows["monster_spawn"]
        desired_doc["layers"]["boss_spawn"] = projected_rows["boss_spawn"]
        desired_nonspawn = non_spawn_fingerprint(desired_doc)
        before_nonspawn = non_spawn_fingerprint(target_before_doc)
        if desired_nonspawn != before_nonspawn:
            target_nonspawn_diff += 1
        prior = _old_map_audit(existing, legacy)
        if prior:
            expected_after = prior.get("target_non_spawn_fingerprint_after")
            if expected_after and expected_after != before_nonspawn:
                raise MigrationError(f"target non-spawn content changed since prior audit: {formal}")
        record = make_map_audit(
            mapping,
            source_path,
            source_root,
            source_doc,
            target_path,
            target_before_bytes,
            target_before_doc,
            desired_doc,
            rows,
            projected_rows,
            prior,
            target_root,
        )
        records.append(record)
        plans.append({
            "mapping": mapping,
            "source_path": source_path,
            "target_path": target_path,
            "source_doc": source_doc,
            "target_before_doc": target_before_doc,
            "target_before_bytes": target_before_bytes,
            "desired_doc": desired_doc,
            "rows": rows,
            "projected_rows": projected_rows,
            "desired_bytes": pretty_json_bytes(desired_doc, b"\r\n" if b"\r\n" in target_before_bytes else b"\n"),
        })

    if special_rows.keys() != set(SPECIAL_NORMAL_IDS):
        missing = sorted(set(SPECIAL_NORMAL_IDS) - special_rows.keys())
        raise MigrationError(f"special_normal placement set mismatch, missing={missing}")
    if totals != {"monster_spawn": EXPECTED_MONSTER_COUNT, "boss_spawn": EXPECTED_BOSS_COUNT}:
        raise MigrationError(f"source placement totals mismatch: {totals}")
    if sum(totals.values()) != EXPECTED_TOTAL_COUNT:
        raise MigrationError(f"source placement total mismatch: {sum(totals.values())}")
    if unknown_monsters or disabled_monsters:
        raise MigrationError("unknown/disabled monster placement encountered")
    if illegal_placements or missing_authority or missing_semantic or missing_group:
        raise MigrationError("illegal or incomplete placement identity encountered")
    if semantic_duplicates or group_duplicates:
        raise MigrationError("duplicate semantic_id or spawn_group_id generated")
    if nonidentity_diff or target_nonspawn_diff:
        raise MigrationError("non-identity or target non-spawn fingerprint changed")

    source_sandbox_path = document_path(source_root, SANDBOX_ID)
    target_sandbox_path = document_path(target_root, SANDBOX_ID)
    require_file(source_sandbox_path, "source sandbox_64 editor document")
    require_file(target_sandbox_path, "target sandbox_64 editor document")
    verify_source_file_manifest(source_sandbox_path, source_root, manifest_index)
    source_sandbox = read_json(source_sandbox_path)
    target_sandbox = read_json(target_sandbox_path)
    source_sandbox_counts = {
        layer: len(source_sandbox.get("layers", {}).get(layer, [])) for layer in LAYERS
    }
    target_sandbox_before_bytes = target_sandbox_path.read_bytes()
    target_sandbox_after_bytes = target_sandbox_path.read_bytes()
    if source_sandbox_counts != {"monster_spawn": 45, "boss_spawn": 0}:
        raise MigrationError(f"sandbox_64 source count mismatch: {source_sandbox_counts}")
    sandbox = {
        "map_id": SANDBOX_ID,
        "source_counts": source_sandbox_counts,
        "target_counts_after": {
            layer: len(target_sandbox.get("layers", {}).get(layer, [])) for layer in LAYERS
        },
        "migrated_count": 0,
        "target_document_sha256_before": sha256_bytes(target_sandbox_before_bytes),
        "target_document_sha256_after": sha256_bytes(target_sandbox_after_bytes),
        "target_unchanged": target_sandbox_before_bytes == target_sandbox_after_bytes,
    }
    if not sandbox["target_unchanged"]:
        raise MigrationError("sandbox_64 changed during migration planning")

    special_effective = []
    for monster_id in SPECIAL_NORMAL_IDS:
        legacy, formal, ordinal = special_rows[monster_id]
        special_effective.append({
            "monster_id": monster_id,
            "source_legacy_map_id": legacy,
            "target_formal_map_id": formal,
            "layer": "monster_spawn",
            "source_order_1_based": ordinal,
            "runtime_effective_spawn_classification": "special_normal",
            "runtime_effective_respawn_policy_id": "special_normal",
            "runtime_effective_respawn_seconds": 900,
            "source_row_count": 1,
            "source_row_max_alive": 1,
            "source_row_respawn_policy_preserved": True,
        })

    registry_sha = sha256_file(target_root / REGISTRY_REL)
    release_after = runtime_release_fingerprint(target_root)
    assert_release_baseline(release_after, "runtime release after migration")
    assert_release_fingerprint_equal(release_before, release_after)
    audit: dict[str, Any] = {
        "audit_id": AUDIT_ID,
        "schema_version": AUDIT_SCHEMA_VERSION,
        "baseline": {
            "target_git_head": BASELINE_TARGET_HEAD,
            "target_baseline_lineage_verified": True,
            "source_maps_head": SOURCE_MAPS_HEAD,
            "source_snapshot_manifest_sha256": source_manifest_sha,
            "source_snapshot_manifest_expected_sha256": SOURCE_MANIFEST_SHA256,
            "map_identity_registry_path": REGISTRY_REL.as_posix(),
            "map_identity_registry_sha256_before": registry_sha,
            "map_identity_registry_sha256_after": registry_sha,
        },
        "source_snapshot": {
            "root_label": source_root.parent.name + "/" + source_root.name,
            "manifest_path": source_manifest_meta["path"],
            "manifest_record_count": source_manifest_meta["record_count"],
            "manifest_sha256": source_manifest_sha,
            "source_documents_are_manifest_verified": True,
        },
        "identity_projection": {
            "allowed_mutations": ["authority_ref.map_id", "semantic_id", "spawn_group_id"],
            "authority_ref_missing_policy": "create_object_with_only_map_id",
            "semantic_id_rule": "mse.placement.v1.<formal_map_id>.<layer>.<source_order_1_based:06d>",
            "spawn_group_id_rule": "mse.group.v1.<formal_map_id>.<layer>.<source_order_1_based:06d>",
            "row_order": "source order preserved independently per layer",
            "non_identity_normalization": "canonical JSON; integral 1 and 1.0 equivalent; list order preserved",
        },
        "summary": {
            "formal_map_count": len(mappings),
            "monster_spawn": totals["monster_spawn"],
            "boss_spawn": totals["boss_spawn"],
            "total": sum(totals.values()),
            "target_before_monster_spawn": target_before_totals["monster_spawn"],
            "target_before_boss_spawn": target_before_totals["boss_spawn"],
            "target_after_monster_spawn": totals["monster_spawn"],
            "target_after_boss_spawn": totals["boss_spawn"],
            "target_after_total": sum(totals.values()),
        },
        "checks": {
            "formal_maps_expected": EXPECTED_FORMAL_MAP_COUNT,
            "formal_maps_actual": len(mappings),
            "formal_maps_ok": len(mappings) == EXPECTED_FORMAL_MAP_COUNT,
            "monster_spawn_expected": EXPECTED_MONSTER_COUNT,
            "monster_spawn_actual": totals["monster_spawn"],
            "boss_spawn_expected": EXPECTED_BOSS_COUNT,
            "boss_spawn_actual": totals["boss_spawn"],
            "total_expected": EXPECTED_TOTAL_COUNT,
            "total_actual": sum(totals.values()),
            "sandbox_migrated_count": 0,
            "unknown_monster_count": unknown_monsters,
            "disabled_monster_count": disabled_monsters,
            "illegal_layer_placement_count": illegal_placements,
            "missing_authority_count": missing_authority,
            "missing_semantic_count": missing_semantic,
            "missing_spawn_group_count": missing_group,
            "semantic_duplicate_count": semantic_duplicates,
            "spawn_group_duplicate_count": group_duplicates,
            "non_identity_diff_count": nonidentity_diff,
            "target_non_spawn_diff_count": target_nonspawn_diff,
            "release_registry_entry_count": release_before["entry_count"],
            "release_registry_entry_count_expected": EXPECTED_RELEASE_ENTRY_COUNT,
            "release_registry_unchanged": True,
        },
        "special_normal": {
            "canonical_ids": list(SPECIAL_NORMAL_IDS),
            "placement_count": len(special_effective),
            "effective_runtime_contract": special_effective,
        },
        "sandbox_excluded": sandbox,
        "release_freeze": release_before,
        "maps": records,
    }
    if existing is not None:
        # A rerun observes the already-populated target arrays.  Keep the
        # original migration-before counts from the first audit so the
        # manifest itself is byte/deterministically stable on repeat runs.
        prior_summary = existing.get("summary")
        if isinstance(prior_summary, dict):
            for field in ("target_before_monster_spawn", "target_before_boss_spawn"):
                if field in prior_summary:
                    audit["summary"][field] = copy.deepcopy(prior_summary[field])
    return audit, plans, {"special_rows": special_rows, "totals": totals}


def write_bytes_if_changed(path: Path, desired: bytes) -> bool:
    current = path.read_bytes() if path.exists() else None
    if current == desired:
        return False
    temporary = path.with_name(path.name + ".precise_migration_tmp")
    try:
        temporary.write_bytes(desired)
        os.replace(temporary, path)
    finally:
        if temporary.exists():
            temporary.unlink()
    return True


def compare_audit(expected: dict[str, Any], actual: dict[str, Any]) -> None:
    if canonical_json_bytes(expected) != canonical_json_bytes(actual):
        raise MigrationError("audit manifest does not match deterministic migration plan")


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-root", required=True, help="frozen snapshot payload root")
    parser.add_argument("--source-manifest", help="frozen snapshot file_manifest.json (default: source parent)")
    parser.add_argument("--target-root", help="target worktree root (default: repository root)")
    parser.add_argument("--audit-path", help="audit manifest path (default: formal map design path)")
    parser.add_argument("--check", action="store_true", help="validate only; do not write any file")
    return parser.parse_args(argv)


def run(args: argparse.Namespace) -> int:
    target_root = Path(args.target_root).resolve() if args.target_root else Path(__file__).resolve().parents[2]
    source_root = Path(args.source_root).resolve()
    if source_root == target_root:
        raise MigrationError("source root must be the frozen snapshot, not the target worktree")
    if not source_root.is_dir() or not target_root.is_dir():
        raise MigrationError("source-root and target-root must be directories")
    lineage_verified = verify_target_baseline_lineage(target_root)
    audit_path = Path(args.audit_path).resolve() if args.audit_path else target_root / AUDIT_REL
    relative_posix(audit_path, target_root)
    require_file(target_root / REGISTRY_REL, "map identity registry")
    require_file(target_root / CATALOG_REL, "canonical monster catalog")
    manifest_meta, manifest_sha, manifest_index = load_source_manifest(
        source_root, Path(args.source_manifest).resolve() if args.source_manifest else None
    )
    registry_path = target_root / REGISTRY_REL
    registry = read_json(registry_path)
    mappings = validate_registry(registry)
    catalog = validate_catalog(read_json(target_root / CATALOG_REL))
    release_before = runtime_release_fingerprint(target_root)
    assert_release_baseline(release_before, "runtime release before migration")
    existing = _existing_audit(audit_path)
    refresh_audit = audit_requires_refresh(existing)
    audit, plans, context = build_audit_and_plan(
        source_root,
        target_root,
        manifest_sha,
        manifest_meta,
        manifest_index,
        registry,
        mappings,
        catalog,
        release_before,
        lineage_verified,
        existing,
    )
    if existing is not None:
        # Keep the original before-snapshot claims while requiring all current
        # target content and source evidence to agree with the regenerated plan.
        if existing.get("baseline", {}).get("source_snapshot_manifest_sha256") != manifest_sha:
            raise MigrationError("existing audit source manifest hash mismatch")
        # A pre-lineage/release-baseline audit is refreshed by a write run;
        # --check remains strict and reports it as stale instead of writing.
        if not refresh_audit or args.check:
            compare_audit(audit, existing)

    if args.check:
        for plan in plans:
            if plan["target_path"].read_bytes() != plan["desired_bytes"]:
                raise MigrationError(f"--check found target diff: {plan['target_path']}")
        if not audit_path.is_file():
            raise MigrationError("--check requires the audit manifest produced by a write run")
        actual = read_json(audit_path)
        compare_audit(audit, actual)
        release_after = runtime_release_fingerprint(target_root)
        assert_release_baseline(release_after, "runtime release after migration check")
        assert_release_fingerprint_equal(release_before, release_after)
        print(
            "MAP_PRECISE_PLACEMENT_MIGRATION_CHECK_PASS "
            f"maps={audit['summary']['formal_map_count']} "
            f"monster_spawn={audit['summary']['monster_spawn']} "
            f"boss_spawn={audit['summary']['boss_spawn']} "
            f"total={audit['summary']['total']} sandbox_migrated=0"
        )
        return 0

    changed_targets = 0
    for plan in plans:
        if write_bytes_if_changed(plan["target_path"], plan["desired_bytes"]):
            changed_targets += 1
    # Re-read all changed targets and prove the requested postcondition before
    # publishing the audit manifest.  The audit itself is deterministic, so a
    # repeat run does not create a diff.
    for plan in plans:
        current_doc = read_json(plan["target_path"])
        if canonical_json_bytes(current_doc) != canonical_json_bytes(plan["desired_doc"]):
            raise MigrationError(f"target post-write content mismatch: {plan['target_path']}")
    release_after = runtime_release_fingerprint(target_root)
    assert_release_baseline(release_after, "runtime release after migration")
    assert_release_fingerprint_equal(release_before, release_after)
    audit_bytes = pretty_json_bytes(audit)
    write_bytes_if_changed(audit_path, audit_bytes)
    actual_audit = read_json(audit_path)
    compare_audit(audit, actual_audit)
    print(
        "MAP_PRECISE_PLACEMENT_MIGRATION_PASS "
        f"maps={audit['summary']['formal_map_count']} "
        f"monster_spawn={audit['summary']['monster_spawn']} "
        f"boss_spawn={audit['summary']['boss_spawn']} "
        f"total={audit['summary']['total']} sandbox_migrated=0 "
        f"target_files_changed={changed_targets}"
    )
    return 0


def main(argv: list[str] | None = None) -> int:
    try:
        return run(parse_args(argv or sys.argv[1:]))
    except MigrationError as exc:
        print(f"MAP_PRECISE_PLACEMENT_MIGRATION_FAIL {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
