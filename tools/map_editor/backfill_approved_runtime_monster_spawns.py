#!/usr/bin/env python3
"""Fail-closed audit/backfill for the five legacy monster-spawn editor debts.

The approved runtime remains immutable authority.  A candidate editor is only
eligible when reinserting the two runtime spawn layers exactly reconstructs the
runtime's approved editor binding and all bound ground inputs still match.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import os
import shutil
import sys
import tempfile
from dataclasses import dataclass
from decimal import Decimal
from pathlib import Path
from typing import Any


TARGET_MAPS = (
    "bich_province",
    "wooma_forest",
    "wooma_temple_1",
    "wooma_temple_2",
    "wooma_temple_3",
)
SPAWN_LAYERS = ("monster_spawn", "boss_spawn")
EDITOR_ONLY_RUNTIME_KEYS = {
    "placeholder_instance_id",
    "editor_visual_asset_id",
    "editor_visual_only",
    "selection_shape",
    "selectable",
    "movable",
}
RELEASE_CONTRACT = "mse.map.runtime.release.v1"
IDENTITY_CONTRACT = "hardcore.formal_map_identity.v1"
PORTAL_CONTRACT = "hardcore.formal_map_portal_network.v1"
CANDIDATE_BINDING_CONTRACT = "mse.map.runtime.candidate_binding.v1"


class AuditError(ValueError):
    """A deterministic input or safety contract violation."""


def _parse_json_bytes(path: Path, raw: bytes) -> dict[str, Any]:
    try:
        value = json.loads(raw.decode("utf-8"), parse_float=Decimal)
    except (UnicodeError, json.JSONDecodeError) as exc:
        raise AuditError(f"invalid_json:{path}:{exc}") from exc
    if not isinstance(value, dict):
        raise AuditError(f"json_root_not_object:{path}")
    return value


def _load_json(path: Path) -> dict[str, Any]:
    try:
        raw = path.read_bytes()
    except OSError as exc:
        raise AuditError(f"unreadable_file:{path}:{exc}") from exc
    return _parse_json_bytes(path, raw)


def _encode(value: Any, depth: int = 0) -> str:
    """Encode the canonical Godot JSON form while retaining numeric lexemes."""
    indent = "  " * depth
    if isinstance(value, dict):
        if not value:
            return "{}"
        rows = [
            "  " * (depth + 1)
            + json.dumps(str(key), ensure_ascii=False)
            + ": "
            + _encode(value[key], depth + 1)
            for key in sorted(value, key=str)
        ]
        return "{\n" + ",\n".join(rows) + "\n" + indent + "}"
    if isinstance(value, list):
        if not value:
            return "[]"
        rows = ["  " * (depth + 1) + _encode(item, depth + 1) for item in value]
        return "[\n" + ",\n".join(rows) + "\n" + indent + "]"
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, Decimal):
        return str(value)
    if isinstance(value, bool):
        return "true" if value else "false"
    if value is None:
        return "null"
    if isinstance(value, int):
        return str(value)
    raise AuditError(f"unsupported_json_value:{type(value).__name__}")


def canonical_bytes(value: dict[str, Any]) -> bytes:
    return (_encode(value) + "\n").encode("utf-8")


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    try:
        with path.open("rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(chunk)
    except OSError as exc:
        raise AuditError(f"unreadable_file:{path}:{exc}") from exc
    return digest.hexdigest()


def _integer(value: Any, label: str) -> int:
    if isinstance(value, bool) or not isinstance(value, (int, Decimal)):
        raise AuditError(f"invalid_integer:{label}")
    result = int(value)
    if Decimal(result) != Decimal(value):
        raise AuditError(f"non_integral_number:{label}")
    return result


def _decimal_string(value: Any) -> str:
    return str(value) if isinstance(value, Decimal) else str(int(value))


def _inside(path: Path, root: Path) -> bool:
    try:
        path.resolve().relative_to(root.resolve())
        return True
    except ValueError:
        return False


def _find_repo_root(path: Path) -> Path:
    for candidate in (path.resolve(), *path.resolve().parents):
        if (candidate / ".git").exists():
            return candidate
    raise AuditError(f"repo_root_not_found_for:{path.name}")


def _portable_repo_key(path: Path, repo_root: Path) -> str:
    if not _inside(path, repo_root):
        raise AuditError(f"repo_authority_outside_repo:{path.name}")
    return "repo:" + path.resolve().relative_to(repo_root.resolve()).as_posix()


def _portable_source_key(path: Path, source_root: Path) -> str:
    if not _inside(path, source_root):
        raise AuditError(f"source_authority_outside_root:{path.name}")
    return "source_editor_root:" + path.resolve().relative_to(source_root.resolve()).as_posix()


def _resolve_res_path(repo_root: Path, raw: Any, label: str) -> Path:
    value = str(raw)
    if not value.startswith("res://"):
        raise AuditError(f"non_res_path:{label}:{value}")
    resolved = (repo_root / value.removeprefix("res://")).resolve()
    if not _inside(resolved, repo_root):
        raise AuditError(f"res_path_escape:{label}:{value}")
    if not resolved.is_file():
        raise AuditError(f"res_path_missing:{label}:{value}")
    return resolved


def _block(blockers: list[dict[str, Any]], code: str, **evidence: Any) -> None:
    blockers.append({"code": code, **evidence})


def _validate_spawn_entry(
    entry: Any,
    layer: str,
    index: int,
    design_size: tuple[int, int],
    blockers: list[dict[str, Any]],
) -> None:
    label = f"{layer}[{index}]"
    if not isinstance(entry, dict):
        _block(blockers, "spawn_entry_not_object", entry=label)
        return
    required = {
        "kind",
        "semantic_id",
        "monster_id",
        "tile",
        "count",
        "max_alive",
        "radius_gu",
        "spawn_rule",
        "runtime_export",
    }
    if layer == "monster_spawn":
        required.add("respawn_policy_id")
    missing = sorted(required - set(entry))
    if missing:
        _block(blockers, "spawn_required_fields_missing", entry=label, fields=missing)
        return
    if str(entry.get("kind")) != layer:
        _block(
            blockers,
            "spawn_classification_layer_mismatch",
            entry=label,
            kind=str(entry.get("kind")),
        )
    try:
        monster_id = _integer(entry["monster_id"], f"{label}.monster_id")
        count = _integer(entry["count"], f"{label}.count")
        max_alive = _integer(entry["max_alive"], f"{label}.max_alive")
    except AuditError as exc:
        _block(blockers, "spawn_integer_invalid", entry=label, reason=str(exc))
        return
    if monster_id <= 0 or count <= 0 or max_alive <= 0:
        _block(blockers, "spawn_positive_integer_invalid", entry=label)
    tile = entry.get("tile")
    if not isinstance(tile, list) or len(tile) != 2:
        _block(blockers, "spawn_tile_invalid", entry=label)
    else:
        try:
            x = _integer(tile[0], f"{label}.tile[0]")
            y = _integer(tile[1], f"{label}.tile[1]")
        except AuditError as exc:
            _block(blockers, "spawn_tile_not_reversible", entry=label, reason=str(exc))
        else:
            if x < 0 or y < 0 or x >= design_size[0] or y >= design_size[1]:
                _block(
                    blockers,
                    "spawn_tile_out_of_bounds",
                    entry=label,
                    tile=[x, y],
                    design_size=list(design_size),
                )
    semantic_id = str(entry.get("semantic_id", ""))
    if not semantic_id:
        _block(blockers, "spawn_stable_id_missing", entry=label)
    if layer == "monster_spawn" and not str(entry.get("respawn_policy_id", "")):
        _block(blockers, "spawn_respawn_policy_missing", entry=label)
    for key in EDITOR_ONLY_RUNTIME_KEYS:
        if key in entry:
            _block(blockers, "runtime_contains_editor_only_field", entry=label, field=key)


def _spawn_summary(entries: list[dict[str, Any]], layer: str) -> dict[str, Any]:
    valid_rows = [row for row in entries if isinstance(row, dict)]
    monster_ids: list[int] = []
    total_count = 0
    for row in valid_rows:
        try:
            monster_ids.append(_integer(row.get("monster_id"), "monster_id"))
            total_count += _integer(row.get("count"), "count")
        except AuditError:
            continue
    return {
        "layer": layer,
        "classification_encoding": "semantic_layer_and_kind",
        "entry_count": len(entries),
        "total_count": total_count,
        "monster_ids": sorted(set(monster_ids)),
        "semantic_ids_sha256": sha256_bytes(
            "\n".join(str(row.get("semantic_id", "")) for row in valid_rows).encode("utf-8")
        ),
        "spawn_group_ids": sorted(
            {str(row["spawn_group_id"]) for row in valid_rows if row.get("spawn_group_id")}
        ),
        "tile_coordinate_contract": "integer_editor_tile_direct_reversible",
    }


def _project_without_spawn_layers(document: dict[str, Any]) -> dict[str, Any]:
    projected = copy.deepcopy(document)
    layers = projected.get("layers")
    if isinstance(layers, dict):
        for layer in SPAWN_LAYERS:
            layers.pop(layer, None)
    return projected


@dataclass(frozen=True)
class AuditPaths:
    source_editor_root: Path
    release_registry: Path
    runtime_root: Path
    identity_registry: Path
    portal_overlay: Path
    candidate_output: Path
    inventory_output: Path | None = None

    def resolved(self) -> "AuditPaths":
        return AuditPaths(
            *(path.resolve() if path is not None else None for path in self.__dict__.values())
        )


def _validate_paths(paths: AuditPaths) -> None:
    if not paths.source_editor_root.is_dir():
        raise AuditError(f"source_editor_root_missing:{paths.source_editor_root}")
    if not paths.runtime_root.is_dir():
        raise AuditError(f"runtime_root_missing:{paths.runtime_root}")
    for path in (paths.release_registry, paths.identity_registry, paths.portal_overlay):
        if not path.is_file():
            raise AuditError(f"authority_file_missing:{path}")
    protected_roots = (paths.source_editor_root, paths.runtime_root)
    if any(_inside(paths.candidate_output, root) or _inside(root, paths.candidate_output) for root in protected_roots):
        raise AuditError("candidate_output_overlaps_protected_root")
    for authority in (paths.release_registry, paths.identity_registry, paths.portal_overlay):
        if paths.candidate_output == authority or _inside(authority, paths.candidate_output):
            raise AuditError("candidate_output_overlaps_authority")
    if paths.inventory_output is not None:
        if any(paths.inventory_output == authority for authority in (
            paths.release_registry,
            paths.identity_registry,
            paths.portal_overlay,
        )):
            raise AuditError("inventory_output_overwrites_authority")
        if any(_inside(paths.inventory_output, root) for root in protected_roots):
            raise AuditError("inventory_output_inside_protected_root")


def audit(
    paths: AuditPaths,
    *,
    allow_authoring_evolution: bool = False,
) -> tuple[dict[str, Any], dict[str, bytes], dict[str, Path]]:
    paths = paths.resolved()
    _validate_paths(paths)
    repo_root = _find_repo_root(paths.release_registry)
    authority_blobs = {
        paths.release_registry: paths.release_registry.read_bytes(),
        paths.identity_registry: paths.identity_registry.read_bytes(),
        paths.portal_overlay: paths.portal_overlay.read_bytes(),
    }
    protected_paths = {
        _portable_repo_key(path, repo_root): path for path in authority_blobs
    }
    observed_protected = {
        key: sha256_bytes(authority_blobs[path]) for key, path in protected_paths.items()
    }
    release = _parse_json_bytes(paths.release_registry, authority_blobs[paths.release_registry])
    identity = _parse_json_bytes(paths.identity_registry, authority_blobs[paths.identity_registry])
    portal = _parse_json_bytes(paths.portal_overlay, authority_blobs[paths.portal_overlay])
    if str(release.get("registry_contract_id", "")) != RELEASE_CONTRACT:
        raise AuditError("release_registry_contract_mismatch")
    if str(identity.get("contract_id", "")) != IDENTITY_CONTRACT:
        raise AuditError("identity_registry_contract_mismatch")
    if str(portal.get("contract_id", "")) != PORTAL_CONTRACT:
        raise AuditError("portal_overlay_contract_mismatch")
    if str(portal.get("identity_contract_id", "")) != IDENTITY_CONTRACT:
        raise AuditError("portal_overlay_identity_contract_mismatch")

    release_entries = release.get("maps")
    identity_entries = identity.get("maps")
    if not isinstance(release_entries, list) or not isinstance(identity_entries, list):
        raise AuditError("registry_maps_not_array")
    release_by_key: dict[str, list[dict[str, Any]]] = {}
    identity_by_legacy: dict[str, list[dict[str, Any]]] = {}
    for entry in release_entries:
        if isinstance(entry, dict):
            release_by_key.setdefault(str(entry.get("map_key", "")), []).append(entry)
    for entry in identity_entries:
        if isinstance(entry, dict):
            identity_by_legacy.setdefault(str(entry.get("legacy_map_id", "")), []).append(entry)

    candidates: dict[str, bytes] = {}
    map_rows: list[dict[str, Any]] = []
    source_repo = paths.source_editor_root.parent

    for legacy_map_id in TARGET_MAPS:
        blockers: list[dict[str, Any]] = []
        releases = release_by_key.get(legacy_map_id, [])
        identities = identity_by_legacy.get(legacy_map_id, [])
        if len(releases) != 1:
            _block(blockers, "approved_release_entry_not_unique", count=len(releases))
        if len(identities) != 1:
            _block(blockers, "formal_identity_entry_not_unique", count=len(identities))
        if blockers:
            map_rows.append({"legacy_map_id": legacy_map_id, "status": "BLOCKED", "blockers": blockers})
            continue
        release_entry = releases[0]
        identity_entry = identities[0]
        source_path = paths.source_editor_root / legacy_map_id / f"{legacy_map_id}.editor.json"
        runtime_path = paths.runtime_root / f"{legacy_map_id}.runtime.json"
        if not source_path.is_file() or not runtime_path.is_file():
            if not source_path.is_file():
                _block(
                    blockers,
                    "source_editor_missing",
                    path=f"source_editor_root:{legacy_map_id}/{legacy_map_id}.editor.json",
                )
            if not runtime_path.is_file():
                _block(
                    blockers,
                    "approved_runtime_missing",
                    path=f"repo:assets/data/runtime/map_editor/{legacy_map_id}.runtime.json",
                )
            map_rows.append({"legacy_map_id": legacy_map_id, "status": "BLOCKED", "blockers": blockers})
            continue
        source_bytes = source_path.read_bytes()
        runtime_bytes = runtime_path.read_bytes()
        source_key = _portable_source_key(source_path, paths.source_editor_root)
        runtime_key = _portable_repo_key(runtime_path, repo_root)
        protected_paths[source_key] = source_path
        protected_paths[runtime_key] = runtime_path
        observed_protected[source_key] = sha256_bytes(source_bytes)
        observed_protected[runtime_key] = sha256_bytes(runtime_bytes)
        for backup in sorted(source_path.parent.glob(f"{source_path.name}.bak*")):
            if backup.is_file():
                backup_key = _portable_source_key(backup, paths.source_editor_root)
                protected_paths[backup_key] = backup
                observed_protected[backup_key] = sha256_file(backup)

        source = _parse_json_bytes(source_path, source_bytes)
        runtime = _parse_json_bytes(runtime_path, runtime_bytes)
        if canonical_bytes(source) != source_bytes:
            _block(blockers, "source_editor_not_canonical_godot_json")

        source_layers = source.get("layers")
        semantics = runtime.get("semantics")
        if not isinstance(source_layers, dict) or not isinstance(semantics, dict):
            _block(blockers, "editor_or_runtime_layers_missing")
            source_layers = {} if not isinstance(source_layers, dict) else source_layers
            semantics = {} if not isinstance(semantics, dict) else semantics
        for layer in SPAWN_LAYERS:
            if not isinstance(source_layers.get(layer), list):
                _block(blockers, "source_spawn_layer_missing", layer=layer)
            elif source_layers[layer]:
                _block(blockers, "source_spawn_layer_not_empty", layer=layer, count=len(source_layers[layer]))
            if not isinstance(semantics.get(layer), list):
                _block(blockers, "runtime_spawn_layer_missing", layer=layer)

        runtime_hash = str(runtime.get("build_sha256", ""))
        runtime_hash_input = copy.deepcopy(runtime)
        runtime_hash_input["build_sha256"] = ""
        computed_runtime_hash = sha256_bytes(canonical_bytes(runtime_hash_input))
        approved_hash = str(release_entry.get("approved_build_sha256", ""))
        if runtime_hash != computed_runtime_hash:
            _block(
                blockers,
                "runtime_self_hash_mismatch",
                recorded=runtime_hash,
                computed=computed_runtime_hash,
            )
        if approved_hash != runtime_hash:
            _block(
                blockers,
                "approved_registry_hash_mismatch",
                registry=approved_hash,
                runtime=runtime_hash,
            )
        if str(release_entry.get("release_state", "")) != "implemented_playable":
            _block(blockers, "runtime_not_implemented_playable")
        expected_runtime_path = f"res://assets/data/runtime/map_editor/{legacy_map_id}.runtime.json"
        if str(release_entry.get("runtime_path", "")) != expected_runtime_path:
            _block(blockers, "registry_runtime_path_mismatch", expected=expected_runtime_path)

        runtime_source = runtime.get("source", {})
        binding = runtime_source.get("candidate_binding", {}) if isinstance(runtime_source, dict) else {}
        legacy_runtime_id = _integer(identity_entry.get("legacy_runtime_map_id"), "legacy_runtime_map_id")
        for actual, expected, code in (
            (source.get("map_id"), legacy_map_id, "source_legacy_map_id_mismatch"),
            (runtime_source.get("map_id"), legacy_map_id, "runtime_legacy_map_id_mismatch"),
            (_integer(source.get("runtime_map_id"), "source.runtime_map_id"), legacy_runtime_id, "source_legacy_runtime_id_mismatch"),
            (_integer(runtime_source.get("runtime_map_id"), "runtime.source.runtime_map_id"), legacy_runtime_id, "runtime_legacy_runtime_id_mismatch"),
            (_integer(release_entry.get("runtime_map_id"), "release.runtime_map_id"), legacy_runtime_id, "release_legacy_runtime_id_mismatch"),
        ):
            if actual != expected:
                _block(blockers, code, actual=actual, expected=expected)
        if str(binding.get("contract_id", "")) != CANDIDATE_BINDING_CONTRACT:
            _block(blockers, "candidate_binding_contract_mismatch")

        try:
            source_size = tuple(_integer(x, "source.design_size") for x in source["design"]["design_size"])
            runtime_size = tuple(_integer(x, "runtime.design_size") for x in runtime["design"]["design_size"])
        except (KeyError, TypeError, AuditError) as exc:
            _block(blockers, "design_size_invalid", reason=str(exc))
            source_size = (0, 0)
            runtime_size = (-1, -1)
        if len(source_size) != 2 or len(runtime_size) != 2 or source_size != runtime_size:
            _block(blockers, "runtime_editor_design_size_mismatch", source=list(source_size), runtime=list(runtime_size))
        validated_source_size = source_size if len(source_size) == 2 else (0, 0)

        spawn_entries: dict[str, list[dict[str, Any]]] = {}
        for layer in SPAWN_LAYERS:
            values = semantics.get(layer, [])
            if not isinstance(values, list):
                values = []
            spawn_entries[layer] = values
            seen_ids: set[str] = set()
            for index, entry in enumerate(values):
                _validate_spawn_entry(entry, layer, index, validated_source_size, blockers)
                if isinstance(entry, dict):
                    semantic_id = str(entry.get("semantic_id", ""))
                    if semantic_id in seen_ids:
                        _block(blockers, "spawn_stable_id_duplicate", layer=layer, semantic_id=semantic_id)
                    seen_ids.add(semantic_id)

        ground_evidence: dict[str, Any] = {}
        ground = source.get("ground", {})
        if not isinstance(ground, dict):
            _block(blockers, "source_ground_missing")
            ground = {}
        for ground_source_field, binding_key in (
            ("workspace_manifest", "ground_manifest_sha256"),
            ("workspace_state", "ground_state_sha256"),
        ):
            try:
                ground_path = _resolve_res_path(
                    source_repo,
                    ground.get(ground_source_field),
                    ground_source_field,
                )
                actual_hash = sha256_file(ground_path)
                ground_key = _portable_source_key(ground_path, paths.source_editor_root)
                protected_paths[ground_key] = ground_path
                observed_protected[ground_key] = actual_hash
                expected_hash = str(binding.get(binding_key, ""))
                ground_evidence[ground_source_field] = {
                    "path": ground_key,
                    "current_sha256": actual_hash,
                    "approved_binding_sha256": expected_hash,
                    "matches": actual_hash == expected_hash,
                }
                if actual_hash != expected_hash and not allow_authoring_evolution:
                    _block(
                        blockers,
                        f"{binding_key}_mismatch",
                        current=actual_hash,
                        approved_binding=expected_hash,
                    )
            except AuditError as exc:
                _block(
                    blockers,
                    "ground_binding_unverifiable",
                    field=ground_source_field,
                    reason=str(exc),
                )

        candidate = copy.deepcopy(source)
        candidate.setdefault("layers", {})["monster_spawn"] = copy.deepcopy(spawn_entries["monster_spawn"])
        candidate["layers"]["boss_spawn"] = copy.deepcopy(spawn_entries["boss_spawn"])
        candidate_bytes = canonical_bytes(candidate)
        candidate_hash = sha256_bytes(candidate_bytes)
        expected_document_hash = str(binding.get("document_sha256", ""))
        if candidate_hash != expected_document_hash and not allow_authoring_evolution:
            _block(
                blockers,
                "candidate_binding_document_sha256_mismatch",
                reconstructed_candidate=candidate_hash,
                approved_binding=expected_document_hash,
            )
        if _project_without_spawn_layers(candidate) != _project_without_spawn_layers(source):
            _block(blockers, "candidate_non_spawn_layers_changed")
        if candidate["layers"].get("monster_spawn") != semantics.get("monster_spawn"):
            _block(blockers, "candidate_monster_spawn_not_deep_equal_runtime")
        if candidate["layers"].get("boss_spawn") != semantics.get("boss_spawn"):
            _block(blockers, "candidate_boss_spawn_not_deep_equal_runtime")

        fingerprint = {
            "document_sha256": expected_document_hash,
            "ground_manifest_sha256": str(binding.get("ground_manifest_sha256", "")),
            "ground_state_sha256": str(binding.get("ground_state_sha256", "")),
        }
        computed_authoring_hash = sha256_bytes(canonical_bytes(fingerprint))
        if computed_authoring_hash != str(binding.get("authoring_sha256", "")):
            _block(blockers, "candidate_binding_authoring_sha256_invalid")

        status = "READY" if not blockers else "BLOCKED"
        if status == "READY":
            candidates[legacy_map_id] = candidate_bytes
        map_rows.append(
            {
                "legacy_map_id": legacy_map_id,
                "legacy_runtime_map_id": legacy_runtime_id,
                "formal_map_id": str(identity_entry.get("map_id", "")),
                "formal_runtime_map_id": _integer(identity_entry.get("runtime_map_id"), "formal_runtime_map_id"),
                "status": status,
                "source_editor": {
                    "path": source_key,
                    "sha256": sha256_bytes(source_bytes),
                    "schema_version": _decimal_string(source.get("schema_version", "")),
                    "revision": _decimal_string(source.get("editor_meta", {}).get("revision", "")),
                    "design_size": list(source_size),
                    "monster_spawn_count": len(source_layers.get("monster_spawn", [])),
                    "boss_spawn_count": len(source_layers.get("boss_spawn", [])),
                },
                "approved_runtime": {
                    "path": runtime_key,
                    "file_sha256": sha256_bytes(runtime_bytes),
                    "registry_build_sha256": approved_hash,
                    "recorded_self_sha256": runtime_hash,
                    "computed_self_sha256": computed_runtime_hash,
                    "hash_chain_matches": approved_hash == runtime_hash == computed_runtime_hash,
                    "candidate_binding_document_sha256": expected_document_hash,
                    "reconstructed_candidate_document_sha256": candidate_hash,
                },
                "spawn_layers": [
                    _spawn_summary(spawn_entries[layer], layer) for layer in SPAWN_LAYERS
                ],
                "ground_binding": ground_evidence,
                "proof": {
                    "candidate_non_spawn_layers_deep_equal_source": (
                        _project_without_spawn_layers(candidate)
                        == _project_without_spawn_layers(source)
                    ),
                    "candidate_monster_spawn_deep_equal_runtime": (
                        candidate["layers"].get("monster_spawn")
                        == semantics.get("monster_spawn")
                    ),
                    "candidate_boss_spawn_deep_equal_runtime": (
                        candidate["layers"].get("boss_spawn")
                        == semantics.get("boss_spawn")
                    ),
                    "candidate_binding_matches": candidate_hash == expected_document_hash,
                    "current_authoring_evolution_preserved": (
                        allow_authoring_evolution
                        and candidate_hash != expected_document_hash
                        and _project_without_spawn_layers(candidate)
                        == _project_without_spawn_layers(source)
                    ),
                },
                "blockers": blockers,
            }
        )

    before = dict(sorted(observed_protected.items()))
    after_audit = {key: sha256_file(protected_paths[key]) for key in before}
    inputs_stable_during_audit = before == after_audit
    if not inputs_stable_during_audit:
        candidates.clear()
        for row in map_rows:
            row["status"] = "BLOCKED"
            row.setdefault("blockers", []).append({
                "code": "protected_input_changed_during_audit",
            })
    inventory = {
        "schema_version": 1,
        "inventory_id": "hardcore.map_monster_spawn_backfill_inventory.v1",
        "generated_by": "tools/map_editor/backfill_approved_runtime_monster_spawns.py",
        "scope": list(TARGET_MAPS),
        "mode": "dry_run",
        "overall_status": "READY" if all(row["status"] == "READY" for row in map_rows) else "BLOCKED",
        "policy": {
            "approved_runtime_is_read_only_authority": True,
            "candidate_changes_only_layers": list(SPAWN_LAYERS),
            "candidate_binding_must_reconstruct_exactly": not allow_authoring_evolution,
            "ground_binding_hashes_must_match": not allow_authoring_evolution,
            "current_authoring_evolution_preserved": allow_authoring_evolution,
            "approved_runtime_spawn_layers_must_match_exactly": True,
            "coordinate_guessing_forbidden": True,
            "partial_candidate_write_forbidden": True,
            "source_editor_bak_runtime_registry_mutation_forbidden": True,
        },
        "inputs": {
            "source_editor_root": {"root_kind": "explicit_read_only_source_editor_root"},
            "release_registry": {
                "path": _portable_repo_key(paths.release_registry, repo_root),
                "sha256": before[_portable_repo_key(paths.release_registry, repo_root)],
            },
            "runtime_root": {"root_kind": "explicit_read_only_runtime_root"},
            "identity_registry": {
                "path": _portable_repo_key(paths.identity_registry, repo_root),
                "sha256": before[_portable_repo_key(paths.identity_registry, repo_root)],
            },
            "portal_overlay": {
                "path": _portable_repo_key(paths.portal_overlay, repo_root),
                "sha256": before[_portable_repo_key(paths.portal_overlay, repo_root)],
            },
            "candidate_output": {"root_kind": "explicit_candidate_output"},
        },
        "summary": {
            "target_map_count": len(TARGET_MAPS),
            "ready_map_count": sum(row["status"] == "READY" for row in map_rows),
            "blocked_map_count": sum(row["status"] == "BLOCKED" for row in map_rows),
            "approved_monster_spawn_count": sum(
                row.get("spawn_layers", [{"entry_count": 0}])[0]["entry_count"] for row in map_rows
            ),
            "approved_boss_spawn_count": sum(
                row.get("spawn_layers", [{}, {"entry_count": 0}])[1].get("entry_count", 0)
                for row in map_rows
            ),
        },
        "maps": map_rows,
        "protected_input_proof": {
            "before": before,
            "after": after_audit,
            "all_unchanged": inputs_stable_during_audit,
        },
    }
    return inventory, candidates, protected_paths


def _write_candidates_atomic(output: Path, candidates: dict[str, bytes]) -> None:
    if output.exists():
        raise AuditError(f"candidate_output_already_exists:{output}")
    output.parent.mkdir(parents=True, exist_ok=True)
    stage = Path(tempfile.mkdtemp(prefix=f".{output.name}.stage-", dir=output.parent))
    try:
        for map_id in TARGET_MAPS:
            target = stage / map_id / f"{map_id}.editor.json"
            target.parent.mkdir(parents=True, exist_ok=False)
            target.write_bytes(candidates[map_id])
        os.replace(stage, output)
    except Exception:
        shutil.rmtree(stage, ignore_errors=True)
        raise


def _write_inventory_atomic(path: Path, inventory: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = canonical_bytes(inventory)
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_bytes(payload)
    if _load_json(temporary).get("inventory_id") != inventory.get("inventory_id"):
        temporary.unlink(missing_ok=True)
        raise AuditError("inventory_temp_verify_failed")
    os.replace(temporary, path)


def run(
    paths: AuditPaths,
    *,
    write_candidates: bool,
    write_inventory: bool,
    allow_authoring_evolution: bool = False,
) -> dict[str, Any]:
    paths = paths.resolved()
    inventory, candidates, protected_paths = audit(
        paths,
        allow_authoring_evolution=allow_authoring_evolution,
    )
    protected_before = inventory["protected_input_proof"]["before"]
    if write_candidates:
        if inventory["overall_status"] != "READY":
            raise AuditError("candidate_write_blocked_by_inventory")
        if set(candidates) != set(TARGET_MAPS):
            raise AuditError("candidate_write_requires_complete_ready_set")
        _write_candidates_atomic(paths.candidate_output, candidates)
        inventory["mode"] = "candidate_write"
    if write_inventory and paths.inventory_output is None:
        raise AuditError("inventory_output_required_for_write")
    protected_after = {
        key: sha256_file(protected_paths[key]) for key in protected_before
    }
    inventory["protected_input_proof"]["after"] = protected_after
    inventory["protected_input_proof"]["all_unchanged"] = protected_before == protected_after
    if protected_before != protected_after:
        raise AuditError("protected_input_mutated")
    if write_inventory:
        _write_inventory_atomic(paths.inventory_output, inventory)
    return inventory


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-editor-root", type=Path, required=True)
    parser.add_argument("--release-registry", type=Path, required=True)
    parser.add_argument("--runtime-root", type=Path, required=True)
    parser.add_argument("--identity-registry", type=Path, required=True)
    parser.add_argument("--portal-overlay", type=Path, required=True)
    parser.add_argument("--candidate-output", type=Path, required=True)
    parser.add_argument("--inventory-output", type=Path)
    parser.add_argument("--write-candidates", action="store_true")
    parser.add_argument("--write-inventory", action="store_true")
    parser.add_argument(
        "--allow-current-authoring-evolution",
        action="store_true",
        help=(
            "preserve current non-spawn authoring while copying only approved "
            "runtime spawn layers; exact spawn equality remains required"
        ),
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    try:
        inventory = run(
            AuditPaths(
                args.source_editor_root,
                args.release_registry,
                args.runtime_root,
                args.identity_registry,
                args.portal_overlay,
                args.candidate_output,
                args.inventory_output,
            ),
            write_candidates=args.write_candidates,
            write_inventory=args.write_inventory,
            allow_authoring_evolution=args.allow_current_authoring_evolution,
        )
    except AuditError as exc:
        print(f"BLOCKED: {exc}", file=sys.stderr)
        return 2
    print(json.dumps(inventory, ensure_ascii=False, indent=2, default=str))
    return 0 if inventory["overall_status"] == "READY" else 2


if __name__ == "__main__":
    raise SystemExit(main())
