#!/usr/bin/env python3
"""Build the fail-closed Phase 2 map monster placement inventory.

The inventory is an audit/authoring artifact.  It joins the repository's
formal map identity registry, the tracked 67-map authoring snapshot, the
Phase 0 monster placement authority, the transition backfill inventory and
the approved runtime release registry.  It deliberately does not open the
``map_editor_workspace`` files: the snapshot is the authoring witness and
the approved runtime JSON files are the only runtime documents read.

No path supplied by a source document is copied into the result.  In
particular, the backfill inventory was produced on a Windows host and may
contain absolute workspace paths; those are treated as evidence only and are
represented by stable repository-relative references here.

The command requires an explicit ``--output``.  Without ``--check`` it writes
only that output; with ``--check`` it rebuilds the expected object and compares
it with the tracked JSON byte-for-byte at the object level.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any, Iterable


ROOT = Path(__file__).resolve().parents[2]

SNAPSHOT_REL = Path("assets/data/map_design/map_authoring_snapshot_20260826.json")
AUTHORITY_REL = Path("assets/data/map_design/map_monster_placement_authority_v2.json")
BACKFILL_REL = Path(
    "assets/data/map_design/map_monster_spawn_backfill_inventory_v1.json"
)
IDENTITY_REL = Path("assets/data/map_design/map_identity_registry.json")
RELEASE_REL = Path(
    "assets/data/runtime/map_editor/map_runtime_release_registry.json"
)
DESIGN_CATALOG_REL = Path("assets/data/map_design/map_design_catalog.json")
BLANK_TEMPLATES_REL = Path("assets/data/map_design/map_blank_templates.json")
RUNTIME_DIR_REL = Path("assets/data/runtime/map_editor")

SCHEMA_VERSION = 1
INVENTORY_ID = "hardcore.map_monster_placement_inventory.v1"
IDENTITY_CONTRACT = "hardcore.formal_map_identity.v1"
AUTHORITY_ID = "hardcore.map_monster_placement_authority.v2"
BACKFILL_ID = "hardcore.map_monster_spawn_backfill_inventory.v1"
RELEASE_CONTRACT = "mse.map.runtime.release.v1"

TRANSITION_DEBT_MAP_KEYS = (
    "bich_province",
    "wooma_forest",
    "wooma_temple_1",
    "wooma_temple_2",
    "wooma_temple_3",
)
STRUCTURE_ONLY_MAP_KEYS = (
    "orc_tomb_1",
    "orc_tomb_2",
    "orc_tomb_3",
    "bich_mine_1",
    "bich_mine_2",
    "corpse_king_hall",
)

HEX64_RE = re.compile(r"^[0-9a-fA-F]{64}$")
ABSOLUTE_PATH_RE = re.compile(r"^(?:[A-Za-z]:[\\/]|/|\\\\)")


class InventoryError(ValueError):
    """Raised when an input cannot support a safe inventory."""


def _as_int(value: Any, label: str) -> int:
    """Accept integral JSON numbers but reject bools, strings and fractions."""

    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise InventoryError(f"{label} must be an integer")
    if isinstance(value, float) and (not math.isfinite(value) or not value.is_integer()):
        raise InventoryError(f"{label} must be an integer")
    return int(value)


def _as_string(value: Any, label: str) -> str:
    if not isinstance(value, str) or not value:
        raise InventoryError(f"{label} must be a non-empty string")
    return value


def _hash_is_valid(value: Any, label: str) -> str:
    result = _as_string(value, label)
    if not HEX64_RE.fullmatch(result):
        raise InventoryError(f"{label} must be a SHA-256 hexadecimal digest")
    return result.upper()


def _repo_relative(path: Path, repo: Path, label: str) -> str:
    """Return a stable POSIX path and reject external/absolute inputs."""

    resolved_repo = repo.resolve()
    resolved = path.resolve()
    try:
        relative = resolved.relative_to(resolved_repo)
    except ValueError as exc:
        raise InventoryError(f"{label} must be inside the repository: {path}") from exc
    result = relative.as_posix()
    if not result or result.startswith("../") or ABSOLUTE_PATH_RE.match(result):
        raise InventoryError(f"{label} is not a stable repository-relative path")
    return result


def _read_json(path: Path, label: str) -> tuple[dict[str, Any], bytes]:
    try:
        raw = path.read_bytes()
    except OSError as exc:
        raise InventoryError(f"cannot read {label}: {path}: {exc}") from exc
    try:
        value = json.loads(raw.decode("utf-8-sig"), parse_constant=_reject_constant)
    except (UnicodeError, json.JSONDecodeError, ValueError) as exc:
        raise InventoryError(f"cannot parse {label}: {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise InventoryError(f"{label} must be a JSON object: {path}")
    return value, raw


def _reject_constant(value: str) -> Any:
    raise ValueError(f"non-finite JSON value {value}")


def _sha256(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest().upper()


def _input_ref(
    repo: Path, path: Path, raw: bytes, *, role: str, kind: str = "json"
) -> dict[str, Any]:
    relative = _repo_relative(path, repo, role)
    return {
        "path": relative,
        "sha256": _sha256(raw),
        "byte_size": len(raw),
        "hash_normalization": "raw_bytes",
        "role": role,
        "kind": kind,
    }


def _ensure_list(value: Any, label: str) -> list[Any]:
    if not isinstance(value, list):
        raise InventoryError(f"{label} must be a list")
    return value


def _ensure_dict(value: Any, label: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise InventoryError(f"{label} must be an object")
    return value


def _stable_source_path(value: Any, label: str) -> str:
    """Normalize a source-relative path without preserving host-specific data."""

    path = _as_string(value, label).replace("\\", "/")
    if ABSOLUTE_PATH_RE.match(path) or path.startswith("../") or "/../" in path:
        raise InventoryError(f"{label} must not be absolute or escape its root")
    return path.lstrip("./")


def _layer_row(
    snapshot_row: dict[str, Any], layer_name: str, *, label: str
) -> dict[str, Any]:
    layer_counts = _ensure_dict(snapshot_row.get("layer_counts"), f"{label}.layer_counts")
    layers = _ensure_dict(snapshot_row.get("layers"), f"{label}.layers")
    count = _as_int(layer_counts.get(layer_name, 0), f"{label}.layer_counts.{layer_name}")
    raw_layer = layers.get(layer_name)
    if raw_layer is None:
        # The authoring snapshot is allowed to omit an empty layer, but an
        # absent layer is still recorded explicitly as evidence.
        return {
            "state": "ABSENT",
            "count": count,
            "sha256": None,
            "source_layers": [],
            "source": "authoring_snapshot",
        }
    layer = _ensure_dict(raw_layer, f"{label}.layers.{layer_name}")
    recorded_count = _as_int(layer.get("count", count), f"{label}.layers.{layer_name}.count")
    if recorded_count != count:
        raise InventoryError(
            f"{label}.{layer_name} count mismatch: layer={recorded_count} counts={count}"
        )
    sha = _hash_is_valid(layer.get("sha256", layer.get("hash")), f"{label}.layers.{layer_name}.sha256")
    source_layers = layer.get("source_layers", [layer_name])
    source_layers = [
        _as_string(item, f"{label}.layers.{layer_name}.source_layers")
        for item in _ensure_list(source_layers, f"{label}.layers.{layer_name}.source_layers")
    ]
    return {
        "state": "PRESENT" if count else "ABSENT",
        "count": count,
        "sha256": sha,
        "source_layers": source_layers,
        "source": "authoring_snapshot",
    }


def _validate_identity(identity: dict[str, Any]) -> tuple[list[dict[str, Any]], dict[str, dict[str, Any]]]:
    if identity.get("contract_id") != IDENTITY_CONTRACT:
        raise InventoryError(f"unexpected identity contract: {identity.get('contract_id')!r}")
    if _as_int(identity.get("formal_map_count"), "identity.formal_map_count") != 67:
        raise InventoryError("identity registry must declare 67 maps")
    rows = _ensure_list(identity.get("maps"), "identity.maps")
    if len(rows) != 67:
        raise InventoryError(f"identity map count={len(rows)} expected 67")
    by_key: dict[str, dict[str, Any]] = {}
    by_id: set[str] = set()
    for index, raw in enumerate(rows):
        row = _ensure_dict(raw, f"identity.maps[{index}]")
        map_key = _as_string(row.get("legacy_map_id"), f"identity.maps[{index}].legacy_map_id")
        map_id = _as_string(row.get("map_id"), f"identity.maps[{index}].map_id")
        if map_key in by_key or map_id in by_id:
            raise InventoryError(f"duplicate identity map key/id: {map_key}/{map_id}")
        _as_string(row.get("display_name"), f"identity.maps[{index}].display_name")
        _as_int(row.get("legacy_runtime_map_id"), f"identity.maps[{index}].legacy_runtime_map_id")
        _as_int(row.get("runtime_map_id"), f"identity.maps[{index}].runtime_map_id")
        _as_string(row.get("series"), f"identity.maps[{index}].series")
        by_key[map_key] = row
        by_id.add(map_id)
    return rows, by_key


def _validate_snapshot(
    snapshot: dict[str, Any], identity_rows: list[dict[str, Any]], identity_by_key: dict[str, dict[str, Any]]
) -> dict[str, dict[str, Any]]:
    if _as_int(snapshot.get("formal_map_count"), "snapshot.formal_map_count") != 67:
        raise InventoryError("authoring snapshot must declare 67 maps")
    rows = _ensure_list(snapshot.get("maps"), "snapshot.maps")
    if len(rows) != 67:
        raise InventoryError(f"authoring snapshot map count={len(rows)} expected 67")
    result: dict[str, dict[str, Any]] = {}
    identity_ids = {str(row["map_id"]): row for row in identity_rows}
    for index, raw in enumerate(rows):
        row = _ensure_dict(raw, f"snapshot.maps[{index}]")
        map_key = _as_string(row.get("legacy_map_id"), f"snapshot.maps[{index}].legacy_map_id")
        if map_key in result:
            raise InventoryError(f"duplicate snapshot map key: {map_key}")
        identity = identity_by_key.get(map_key)
        if identity is None:
            raise InventoryError(f"snapshot map is absent from identity registry: {map_key}")
        map_id = _as_string(row.get("map_id"), f"snapshot.maps[{index}].map_id")
        if map_id != identity["map_id"]:
            raise InventoryError(f"snapshot {map_key} canonical map_id mismatch")
        if _as_int(row.get("runtime_map_id"), f"snapshot.maps[{index}].runtime_map_id") != int(identity["runtime_map_id"]):
            raise InventoryError(f"snapshot {map_key} formal runtime_map_id mismatch")
        if row.get("document_map_id") != map_key:
            raise InventoryError(f"snapshot {map_key} document_map_id mismatch")
        if _as_int(row.get("document_runtime_map_id"), f"snapshot.maps[{index}].document_runtime_map_id") != int(identity["legacy_runtime_map_id"]):
            raise InventoryError(f"snapshot {map_key} legacy runtime id mismatch")
        if row.get("document_display_name") != identity["display_name"]:
            raise InventoryError(f"snapshot {map_key} display name mismatch")
        _stable_source_path(row.get("source_relative_path"), f"snapshot.maps[{index}].source_relative_path")
        _hash_is_valid(row.get("source_sha256"), f"snapshot.maps[{index}].source_sha256")
        _as_int(row.get("source_byte_size"), f"snapshot.maps[{index}].source_byte_size")
        _ensure_dict(row.get("document"), f"snapshot.maps[{index}].document")
        design_size = _ensure_list(row.get("design_size"), f"snapshot.maps[{index}].design_size")
        if len(design_size) != 2:
            raise InventoryError(f"snapshot {map_key} design_size must have two values")
        for dim in design_size:
            _as_int(dim, f"snapshot.maps[{index}].design_size")
        result[map_key] = row
    if set(result) != set(identity_by_key):
        raise InventoryError("authoring snapshot does not cover exactly the identity registry")
    # Keep this explicit: a row keyed by the formal canonical ID must also be
    # unique, even though the map-key check above normally catches it.
    if set(str(row["map_id"]) for row in rows) != identity_ids.keys():
        raise InventoryError("authoring snapshot canonical map coverage mismatch")
    return result


def _validate_authority(
    authority: dict[str, Any], identity_by_key: dict[str, dict[str, Any]]
) -> tuple[dict[str, list[dict[str, Any]]], dict[str, Any]]:
    if authority.get("manifest_id") != AUTHORITY_ID:
        raise InventoryError(f"unexpected monster authority manifest: {authority.get('manifest_id')!r}")
    maps = _ensure_list(authority.get("maps"), "authority.maps")
    if len(maps) != 67:
        raise InventoryError(f"authority map count={len(maps)} expected 67")
    by_key: dict[str, dict[str, Any]] = {}
    by_canonical: dict[str, str] = {}
    for index, raw in enumerate(maps):
        row = _ensure_dict(raw, f"authority.maps[{index}]")
        map_key = _as_string(row.get("legacy_map_id"), f"authority.maps[{index}].legacy_map_id")
        identity = identity_by_key.get(map_key)
        if identity is None:
            raise InventoryError(f"authority map absent from identity registry: {map_key}")
        map_id = _as_string(row.get("map_id"), f"authority.maps[{index}].map_id")
        if map_id != identity["map_id"]:
            raise InventoryError(f"authority {map_key} canonical map_id mismatch")
        if _as_int(row.get("runtime_map_id"), f"authority.maps[{index}].runtime_map_id") != int(identity["runtime_map_id"]):
            raise InventoryError(f"authority {map_key} formal runtime id mismatch")
        if _as_int(row.get("legacy_runtime_id"), f"authority.maps[{index}].legacy_runtime_id") != int(identity["legacy_runtime_map_id"]):
            raise InventoryError(f"authority {map_key} legacy runtime id mismatch")
        if map_key in by_key or map_id in by_canonical:
            raise InventoryError(f"duplicate authority map: {map_key}")
        by_key[map_key] = row
        by_canonical[map_id] = map_key

    records = _ensure_list(authority.get("token_records"), "authority.token_records")
    grouped: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for index, raw in enumerate(records):
        row = _ensure_dict(raw, f"authority.token_records[{index}]")
        canonical = _as_string(row.get("map_id"), f"authority.token_records[{index}].map_id")
        map_key = by_canonical.get(canonical)
        if map_key is None:
            raise InventoryError(f"authority token references unknown map: {canonical}")
        # The prior authority generator's auto fields are the routing
        # authority.  Require them so a future schema cannot silently turn an
        # unresolved/system token into an ordinary placement.
        if not isinstance(row.get("auto_placement_allowed"), bool):
            raise InventoryError(f"authority token {index} has no boolean auto_placement_allowed")
        _as_string(row.get("auto_placement_status"), f"authority.token_records[{index}].auto_placement_status")
        _as_string(row.get("status"), f"authority.token_records[{index}].status")
        grouped[map_key].append(row)
    if set(by_key) != set(identity_by_key):
        raise InventoryError("authority map coverage mismatch")
    if sum(len(items) for items in grouped.values()) != len(records):
        raise InventoryError("authority token grouping dropped records")
    return dict(grouped), authority


def _validate_backfill(
    backfill: dict[str, Any], identity_by_key: dict[str, dict[str, Any]]
) -> dict[str, dict[str, Any]]:
    if backfill.get("inventory_id") != BACKFILL_ID:
        raise InventoryError(f"unexpected backfill inventory: {backfill.get('inventory_id')!r}")
    rows = _ensure_list(backfill.get("maps"), "backfill.maps")
    if set(TRANSITION_DEBT_MAP_KEYS) != {
        _as_string(_ensure_dict(row, "backfill map").get("legacy_map_id"), "backfill.legacy_map_id")
        for row in rows
    }:
        raise InventoryError("backfill inventory must cover exactly the five transition maps")
    result: dict[str, dict[str, Any]] = {}
    for index, raw in enumerate(rows):
        row = _ensure_dict(raw, f"backfill.maps[{index}]")
        map_key = _as_string(row.get("legacy_map_id"), f"backfill.maps[{index}].legacy_map_id")
        identity = identity_by_key[map_key]
        if row.get("formal_map_id") != identity["map_id"]:
            raise InventoryError(f"backfill {map_key} formal map id mismatch")
        if _as_int(row.get("legacy_runtime_map_id"), f"backfill.maps[{index}].legacy_runtime_map_id") != int(identity["legacy_runtime_map_id"]):
            raise InventoryError(f"backfill {map_key} legacy runtime id mismatch")
        if _as_int(row.get("formal_runtime_map_id"), f"backfill.maps[{index}].formal_runtime_map_id") != int(identity["runtime_map_id"]):
            raise InventoryError(f"backfill {map_key} formal runtime id mismatch")
        if row.get("status") != "BLOCKED":
            raise InventoryError(f"transition backfill {map_key} is not BLOCKED")
        blockers = _ensure_list(row.get("blockers"), f"backfill.maps[{index}].blockers")
        codes = {
            _as_string(_ensure_dict(blocker, "backfill blocker").get("code"), "backfill blocker.code")
            for blocker in blockers
        }
        required = {
            "ground_manifest_sha256_mismatch",
            "ground_state_sha256_mismatch",
            "candidate_binding_document_sha256_mismatch",
        }
        if not required.issubset(codes):
            raise InventoryError(f"backfill {map_key} lacks required binding mismatch evidence")
        proof = _ensure_dict(row.get("proof"), f"backfill.maps[{index}].proof")
        if proof.get("candidate_binding_matches") is not False:
            raise InventoryError(f"backfill {map_key} candidate binding is not proven mismatched")
        ground = _ensure_dict(row.get("ground_binding"), f"backfill.maps[{index}].ground_binding")
        for ground_key in ("workspace_manifest", "workspace_state"):
            ground_row = _ensure_dict(ground.get(ground_key), f"backfill.{ground_key}")
            if ground_row.get("matches") is not False:
                raise InventoryError(f"backfill {map_key} {ground_key} mismatch evidence is absent")
            _hash_is_valid(ground_row.get("approved_binding_sha256"), f"backfill.{ground_key}.approved_binding_sha256")
            _hash_is_valid(ground_row.get("current_sha256"), f"backfill.{ground_key}.current_sha256")
        source_editor = _ensure_dict(row.get("source_editor"), f"backfill.maps[{index}].source_editor")
        _hash_is_valid(source_editor.get("sha256"), f"backfill.{map_key}.source_editor.sha256")
        approved_runtime = _ensure_dict(row.get("approved_runtime"), f"backfill.maps[{index}].approved_runtime")
        _hash_is_valid(approved_runtime.get("file_sha256"), f"backfill.{map_key}.approved_runtime.file_sha256")
        _hash_is_valid(approved_runtime.get("computed_self_sha256"), f"backfill.{map_key}.approved_runtime.computed_self_sha256")
        spawn_layers = _ensure_list(row.get("spawn_layers"), f"backfill.maps[{index}].spawn_layers")
        result[map_key] = {
            "status": "BLOCKED",
            "blocker_codes": sorted(codes),
            "proof": {
                key: proof.get(key)
                for key in sorted(proof)
                if isinstance(proof.get(key), (bool, int, float, str))
            },
            "source_editor": {
                "path_kind": "workspace_state",
                "sha256": _hash_is_valid(source_editor.get("sha256"), f"backfill.{map_key}.source_editor.sha256"),
                "schema_version": source_editor.get("schema_version"),
                "revision": source_editor.get("revision"),
                "design_size": source_editor.get("design_size"),
                "monster_spawn_count": _as_int(source_editor.get("monster_spawn_count"), f"backfill.{map_key}.source_editor.monster_spawn_count"),
                "boss_spawn_count": _as_int(source_editor.get("boss_spawn_count"), f"backfill.{map_key}.source_editor.boss_spawn_count"),
            },
            "approved_runtime": {
                "file_sha256": _hash_is_valid(approved_runtime.get("file_sha256"), f"backfill.{map_key}.approved_runtime.file_sha256"),
                "computed_self_sha256": _hash_is_valid(approved_runtime.get("computed_self_sha256"), f"backfill.{map_key}.approved_runtime.computed_self_sha256"),
                "recorded_self_sha256": _hash_is_valid(approved_runtime.get("recorded_self_sha256"), f"backfill.{map_key}.approved_runtime.recorded_self_sha256"),
                "registry_build_sha256": _hash_is_valid(approved_runtime.get("registry_build_sha256"), f"backfill.{map_key}.approved_runtime.registry_build_sha256"),
                "hash_chain_matches": approved_runtime.get("hash_chain_matches"),
            },
            "spawn_layers": [
                {
                    "layer": _as_string(_ensure_dict(layer, "backfill spawn layer").get("layer"), "backfill.spawn_layers.layer"),
                    "entry_count": _as_int(_ensure_dict(layer, "backfill spawn layer").get("entry_count"), "backfill.spawn_layers.entry_count"),
                    "total_count": _as_int(_ensure_dict(layer, "backfill spawn layer").get("total_count"), "backfill.spawn_layers.total_count"),
                }
                for layer in spawn_layers
            ],
            "ground_binding": {
                key: {
                    "approved_binding_sha256": _hash_is_valid(
                        _ensure_dict(ground.get(key), f"backfill.{key}").get("approved_binding_sha256"),
                        f"backfill.{map_key}.{key}.approved_binding_sha256",
                    ),
                    "current_sha256": _hash_is_valid(
                        _ensure_dict(ground.get(key), f"backfill.{key}").get("current_sha256"),
                        f"backfill.{map_key}.{key}.current_sha256",
                    ),
                    "matches": False,
                }
                for key in ("workspace_manifest", "workspace_state")
            },
        }
    return result


def _runtime_path_from_registry(value: Any, registry_map_key: str) -> str:
    path = _as_string(value, f"release.{registry_map_key}.runtime_path").replace("\\", "/")
    if not path.startswith("res://") or path.startswith("res:///"):
        raise InventoryError(f"release {registry_map_key} runtime_path must be a res:// path")
    expected = f"res://assets/data/runtime/map_editor/{registry_map_key}.runtime.json"
    if path != expected:
        raise InventoryError(f"release {registry_map_key} runtime_path mismatch: {path}")
    return path


def _validate_release_registry(
    release: dict[str, Any], identity_by_key: dict[str, dict[str, Any]]
) -> dict[str, dict[str, Any]]:
    if release.get("registry_contract_id") != RELEASE_CONTRACT:
        raise InventoryError(f"unexpected release registry contract: {release.get('registry_contract_id')!r}")
    rows = _ensure_list(release.get("maps"), "release.maps")
    # Releases historically used the legacy authoring key, while newly
    # published formal releases use the canonical identity map_id.  Keep the
    # inventory join keyed by legacy_map_id, but retain the registry spelling
    # and key kind in a binding descriptor so the distinction is auditable.
    identity_by_map_id = {
        str(identity["map_id"]): identity for identity in identity_by_key.values()
    }
    result: dict[str, dict[str, Any]] = {}
    registry_keys: set[str] = set()
    for index, raw in enumerate(rows):
        row = _ensure_dict(raw, f"release.maps[{index}]")
        registry_map_key = _as_string(row.get("map_key"), f"release.maps[{index}].map_key")
        if registry_map_key in registry_keys:
            raise InventoryError(f"duplicate release map key: {registry_map_key}")
        registry_keys.add(registry_map_key)

        legacy_identity = identity_by_key.get(registry_map_key)
        canonical_identity = identity_by_map_id.get(registry_map_key)
        if legacy_identity is not None and canonical_identity is not None:
            raise InventoryError(
                "ambiguous release map key matches both legacy_map_id and map_id: "
                f"{registry_map_key}"
            )
        if legacy_identity is not None:
            identity = legacy_identity
            key_kind = "legacy"
            normalized_map_key = str(identity["legacy_map_id"])
            expected_runtime_id = _as_int(
                identity["legacy_runtime_map_id"],
                f"identity.{normalized_map_key}.legacy_runtime_map_id",
            )
            expected_source_map_id = normalized_map_key
        elif canonical_identity is not None:
            identity = canonical_identity
            key_kind = "formal_canonical"
            normalized_map_key = str(identity["legacy_map_id"])
            expected_runtime_id = _as_int(
                identity["runtime_map_id"],
                f"identity.{normalized_map_key}.runtime_map_id",
            )
            expected_source_map_id = registry_map_key
        else:
            raise InventoryError(
                f"release map absent from identity registry: {registry_map_key}"
            )

        runtime_map_id = _as_int(
            row.get("runtime_map_id"), f"release.maps[{index}].runtime_map_id"
        )
        if runtime_map_id != expected_runtime_id:
            raise InventoryError(
                f"release {registry_map_key} {key_kind} runtime id mismatch: "
                f"expected {expected_runtime_id}, got {runtime_map_id}"
            )
        _runtime_path_from_registry(row.get("runtime_path"), registry_map_key)
        _as_string(row.get("release_state"), f"release.maps[{index}].release_state")
        _hash_is_valid(row.get("approved_build_sha256"), f"release.maps[{index}].approved_build_sha256")
        if normalized_map_key in result:
            previous = result[normalized_map_key]
            raise InventoryError(
                "ambiguous release bindings for normalized legacy map key "
                f"{normalized_map_key}: {previous['registry_map_key']} and "
                f"{registry_map_key}"
            )
        result[normalized_map_key] = {
            "row": row,
            "registry_map_key": registry_map_key,
            "registry_key_kind": key_kind,
            "normalized_map_key": normalized_map_key,
            "expected_runtime_map_id": expected_runtime_id,
            "expected_source_map_id": expected_source_map_id,
        }
    return result


def _validate_design_sources(
    catalog: dict[str, Any], templates: dict[str, Any]
) -> tuple[dict[str, str], dict[str, str]]:
    catalog_rows = _ensure_list(catalog.get("maps"), "map_design_catalog.maps")
    catalog_by_id: dict[str, str] = {}
    for index, raw in enumerate(catalog_rows):
        row = _ensure_dict(raw, f"map_design_catalog.maps[{index}]")
        map_id = _as_string(row.get("map_id"), f"map_design_catalog.maps[{index}].map_id")
        map_type = _as_string(row.get("map_type"), f"map_design_catalog.maps[{index}].map_type")
        if map_id in catalog_by_id and catalog_by_id[map_id] != map_type:
            raise InventoryError(f"map design catalog has conflicting type: {map_id}")
        catalog_by_id[map_id] = map_type
    template_rows = _ensure_list(templates.get("templates"), "map_blank_templates.templates")
    template_by_key: dict[str, str] = {}
    for index, raw in enumerate(template_rows):
        row = _ensure_dict(raw, f"map_blank_templates.templates[{index}]")
        map_key = _as_string(row.get("map_id"), f"map_blank_templates.templates[{index}].map_id")
        map_type = _as_string(row.get("map_type"), f"map_blank_templates.templates[{index}].map_type")
        if map_key in template_by_key and template_by_key[map_key] != map_type:
            raise InventoryError(f"map blank templates has conflicting type: {map_key}")
        template_by_key[map_key] = map_type
    return catalog_by_id, template_by_key


# Twenty-two formal maps predate the current map design catalog/template
# coverage.  This is a closed, reviewable taxonomy policy, keyed only by the
# formal identity, and is intentionally emitted as evidence rather than
# masquerading as a catalog record.  It exists so every map has a map_type
# field while a missing design catalog cannot silently become a placement
# approval.
FALLBACK_MAP_TYPES: dict[str, str] = {
    "fmg_1": "outdoor_field",
    "brm_2": "outdoor_field",
    "cyd_1": "outdoor_field",
    "quest_1": "quest_room",
    "zumage_1": "maze_room",
    "zmjzzj_2": "boss_room",
    "swsg_2": "dungeon_floor",
    "sgcw_2": "quest_room",
    "hadd_2": "quest_room",
    "between_life_and_death": "quest_room",
    "terror_space": "quest_room",
    "thin_sky_passage": "corridor",
    "death_coffin": "boss_room",
    "ql_1": "corridor",
    "gmhl_1": "dungeon_floor",
    "gmhl_thunder_road": "dungeon_floor",
    "gmhl_bazhe_hall": "dungeon_floor",
    "gmhl_zonghengdao": "dungeon_floor",
    "gmhl_mohun_dian": "dungeon_floor",
    "gmhl_purgatory_corridor": "corridor",
    "gmhl_fengmo_dian": "boss_room",
    "cyxg_2": "outdoor_field",
    "cyxggc_2": "outdoor_field",
    "chiyue_choice_land": "quest_room",
    "chiyue_valley_secret_passage_a": "corridor",
    "chiyue_valley_secret_passage_b": "corridor",
    "emjt_2": "boss_room",
    "cymx_2": "boss_room",
    "boss_2": "boss_room",
    "dyly_2": "boss_room",
    "dlfc_2": "boss_room",
    "swsd_2": "boss_room",
    "symy_2": "boss_room",
    "qccx_2": "boss_room",
}


def _resolve_map_type(
    map_key: str,
    identity: dict[str, Any],
    runtime_row: dict[str, Any] | None,
    runtime_doc: dict[str, Any] | None,
    catalog_by_id: dict[str, str],
    template_by_key: dict[str, str],
) -> tuple[str, dict[str, Any]]:
    values: list[tuple[str, str]] = []
    if runtime_doc is not None:
        design = _ensure_dict(runtime_doc.get("design"), f"runtime.{map_key}.design")
        if design.get("map_type"):
            values.append(("formal_runtime_release.design.map_type", _as_string(design["map_type"], f"runtime.{map_key}.design.map_type")))
    canonical = str(identity["map_id"])
    if canonical in catalog_by_id:
        values.append(("map_design_catalog.maps.map_type", catalog_by_id[canonical]))
    if map_key in template_by_key:
        values.append(("map_blank_templates.templates.map_type", template_by_key[map_key]))
    if values and len({value for _, value in values}) != 1:
        raise InventoryError(f"map type authorities disagree for {map_key}: {values}")
    if values:
        source, map_type = values[0]
        return map_type, {
            "state": "AUTHORITATIVE",
            "source": source,
            "rule_id": None,
        }
    fallback = FALLBACK_MAP_TYPES.get(map_key)
    if fallback:
        return fallback, {
            "state": "EXPLICIT_FALLBACK_POLICY",
            "source": "formal_identity_map_type_policy.v1",
            "rule_id": f"formal_identity_map_type_policy.v1:{map_key}",
        }
    # This branch is fail-closed.  It is currently unreachable but prevents a
    # future 68th map from gaining an invented type.
    return "UNKNOWN", {
        "state": "UNRESOLVED",
        "source": None,
        "rule_id": None,
    }


def _safe_runtime_doc(
    repo: Path,
    map_key: str,
    release_binding: dict[str, Any] | None,
) -> tuple[dict[str, Any] | None, dict[str, Any]]:
    if release_binding is None:
        return None, {
            "state": "NOT_IN_RELEASE_REGISTRY",
            "exists": False,
            "path": None,
            "runtime_path": None,
            "file_sha256": None,
            "approved_build_sha256": None,
            "build_sha256": None,
            "hash_match": False,
            "registry_map_key": None,
            "registry_key_kind": None,
            "normalized_map_key": map_key,
            "runtime_map_id": None,
            "redeployment_required": False,
            "spawn_counts_role": "no_published_runtime",
        }
    release_row = _ensure_dict(release_binding.get("row"), f"release.{map_key}")
    registry_map_key = _as_string(
        release_binding.get("registry_map_key"), f"release.{map_key}.registry_map_key"
    )
    registry_key_kind = _as_string(
        release_binding.get("registry_key_kind"), f"release.{map_key}.registry_key_kind"
    )
    normalized_map_key = _as_string(
        release_binding.get("normalized_map_key"), f"release.{map_key}.normalized_map_key"
    )
    expected_runtime_id = _as_int(
        release_binding.get("expected_runtime_map_id"),
        f"release.{map_key}.expected_runtime_map_id",
    )
    expected_source_map_id = _as_string(
        release_binding.get("expected_source_map_id"),
        f"release.{map_key}.expected_source_map_id",
    )
    runtime_path = _runtime_path_from_registry(
        release_row.get("runtime_path"), registry_map_key
    )
    relative = Path(runtime_path.removeprefix("res://"))
    absolute = repo / relative
    if not absolute.is_file():
        return None, {
            "state": "RELEASE_FILE_MISSING",
            "exists": False,
            "path": relative.as_posix(),
            "runtime_path": runtime_path,
            "file_sha256": None,
            "approved_build_sha256": _hash_is_valid(
                release_row.get("approved_build_sha256"),
                f"release.{registry_map_key}.approved_build_sha256",
            ),
            "build_sha256": None,
            "hash_match": False,
            "release_state": release_row.get("release_state"),
            "registry_map_key": registry_map_key,
            "registry_key_kind": registry_key_kind,
            "normalized_map_key": normalized_map_key,
            "runtime_map_id": expected_runtime_id,
            "redeployment_required": False,
            "spawn_counts_role": "published_runtime_observation_not_authoring_input",
        }
    raw = absolute.read_bytes()
    try:
        doc = json.loads(raw.decode("utf-8-sig"), parse_constant=_reject_constant)
    except (UnicodeError, json.JSONDecodeError, ValueError) as exc:
        raise InventoryError(
            f"cannot parse approved runtime {registry_map_key}: {exc}"
        ) from exc
    if not isinstance(doc, dict):
        raise InventoryError(
            f"approved runtime {registry_map_key} must be an object"
        )
    source = _ensure_dict(doc.get("source"), f"runtime.{registry_map_key}.source")
    identity_map_key = _as_string(
        source.get("map_id"), f"runtime.{registry_map_key}.source.map_id"
    )
    if identity_map_key != expected_source_map_id:
        raise InventoryError(
            f"runtime {registry_map_key} source map_id mismatch: "
            f"expected {expected_source_map_id}, got {identity_map_key}"
        )
    source_runtime_id = _as_int(
        source.get("runtime_map_id"),
        f"runtime.{registry_map_key}.source.runtime_map_id",
    )
    if source_runtime_id != expected_runtime_id:
        raise InventoryError(
            f"runtime {registry_map_key} source runtime id mismatch: "
            f"expected {expected_runtime_id}, got {source_runtime_id}"
        )
    semantics = _ensure_dict(doc.get("semantics"), f"runtime.{registry_map_key}.semantics")
    monster_spawn = _ensure_list(
        semantics.get("monster_spawn"),
        f"runtime.{registry_map_key}.semantics.monster_spawn",
    )
    boss_spawn = _ensure_list(
        semantics.get("boss_spawn"),
        f"runtime.{registry_map_key}.semantics.boss_spawn",
    )
    approved = _hash_is_valid(
        release_row.get("approved_build_sha256"),
        f"release.{registry_map_key}.approved_build_sha256",
    )
    build_sha = _hash_is_valid(
        doc.get("build_sha256"), f"runtime.{registry_map_key}.build_sha256"
    )
    return doc, {
        "state": "APPROVED_RELEASE_FILE" if build_sha == approved else "RELEASE_HASH_MISMATCH",
        "exists": build_sha == approved,
        "path": relative.as_posix(),
        "runtime_path": runtime_path,
        "file_sha256": _sha256(raw),
        "approved_build_sha256": approved,
        "build_sha256": build_sha,
        "hash_match": build_sha == approved,
        "release_state": release_row.get("release_state"),
        "registry_map_key": registry_map_key,
        "registry_key_kind": registry_key_kind,
        "normalized_map_key": normalized_map_key,
        "runtime_map_id": expected_runtime_id,
        # A published runtime is an observation/evidence source.  Its spawn
        # counts must never be interpreted as a request to redeploy the user
        # authoring layer.
        "redeployment_required": False,
        "spawn_counts_role": "published_runtime_observation_not_authoring_input",
        "spawn_counts": {
            "monster_spawn": len(monster_spawn),
            "boss_spawn": len(boss_spawn),
            "total": len(monster_spawn) + len(boss_spawn),
        },
    }


def _authority_counts(records: Iterable[dict[str, Any]]) -> dict[str, int]:
    records = list(records)
    routing_counts = Counter()
    status_counts = Counter()
    for record in records:
        status = str(record["status"])
        auto_status = str(record["auto_placement_status"])
        status_counts[status] += 1
        if record["auto_placement_allowed"]:
            routing_counts["allowed"] += 1
        elif auto_status == "SPECIAL_SYSTEM_REQUIRED":
            routing_counts["special"] += 1
        elif auto_status == "UNRESOLVED_BLOCKED" or status == "blocked":
            routing_counts["blocked"] += 1
        elif auto_status == "INTENTIONALLY_EXCLUDED" or status == "excluded":
            routing_counts["excluded"] += 1
        elif auto_status == "EXPLICIT_PLACEMENT_REQUIRED":
            routing_counts["explicit"] += 1
        else:
            raise InventoryError(
                f"unsupported authority routing state: {status}/{auto_status}"
            )
    # Special is deliberately a routing bucket and includes unresolved/system
    # records.  Blocked/excluded are independent status counters; this makes
    # both the ordinary route and the source-quality status visible without
    # double-counting the ordinary/explicit buckets.
    return {
        "token_occurrences": len(records),
        "resolved": status_counts["resolved"],
        "excluded": status_counts["excluded"],
        "blocked": status_counts["blocked"],
        "not_a_monster": status_counts["not_a_monster"],
        "allowed": routing_counts["allowed"],
        "explicit": routing_counts["explicit"],
        "special": routing_counts["special"],
    }


def _walkable_evidence(snapshot_row: dict[str, Any], map_key: str) -> dict[str, Any]:
    layers = _ensure_dict(snapshot_row.get("layers"), f"snapshot.{map_key}.layers")
    layer_counts = _ensure_dict(snapshot_row.get("layer_counts"), f"snapshot.{map_key}.layer_counts")
    # A collision summary is not a walkable grid.  Do not infer walkability
    # from dimensions, collision counts, or the existence of a runtime file.
    if "walkable" not in layers and "walkable" not in layer_counts:
        collision = layers.get("collision")
        collision_erase = layers.get("collision_erase")
        collision_sha = None
        collision_erase_sha = None
        if isinstance(collision, dict) and collision.get("sha256"):
            collision_sha = _hash_is_valid(collision.get("sha256"), f"snapshot.{map_key}.layers.collision.sha256")
        if isinstance(collision_erase, dict) and collision_erase.get("sha256"):
            collision_erase_sha = _hash_is_valid(collision_erase.get("sha256"), f"snapshot.{map_key}.layers.collision_erase.sha256")
        return {
            "state": "UNKNOWN",
            "evidence": "collision_contract_available",
            "evidence_code": "collision_contract_available",
            "calculation_state": "unknown",
            "safe_to_auto_place": False,
            "source": "authoring_snapshot",
            "reason": "no authoritative walkable grid; collision summaries are not promoted to walkable",
            "collision_evidence": {
                "available_layers": sorted(str(key) for key in layers),
                "collision_count": _as_int(layer_counts.get("collision", 0), f"snapshot.{map_key}.layer_counts.collision"),
                "collision_sha256": collision_sha,
                "collision_erase_count": _as_int(layer_counts.get("collision_erase", 0), f"snapshot.{map_key}.layer_counts.collision_erase"),
                "collision_erase_sha256": collision_erase_sha,
            },
        }
    # Presence alone is not enough to prove safe coordinates because the
    # snapshot contract stores layer digests, not the walkable cells.  Record
    # the evidence and continue to fail closed.
    raw = layers.get("walkable")
    count = _as_int(layer_counts.get("walkable", 0), f"snapshot.{map_key}.layer_counts.walkable")
    digest = _hash_is_valid(_ensure_dict(raw, f"snapshot.{map_key}.layers.walkable").get("sha256"), f"snapshot.{map_key}.layers.walkable.sha256")
    return {
        "state": "UNKNOWN",
        "evidence": "collision_contract_available",
        "evidence_code": "collision_contract_available",
        "calculation_state": "unknown",
        "safe_to_auto_place": False,
        "source": "authoring_snapshot",
        "reason": "walkable digest is present but coordinate cells are not in the snapshot contract",
        "collision_evidence": {"walkable_layer_digest_count": count, "walkable_layer_sha256": digest},
    }


def _build_map_row(
    repo: Path,
    identity: dict[str, Any],
    snapshot_row: dict[str, Any],
    authority_records: list[dict[str, Any]],
    backfill_row: dict[str, Any] | None,
    release_binding: dict[str, Any] | None,
    runtime_doc: dict[str, Any] | None,
    runtime_evidence: dict[str, Any],
    catalog_by_id: dict[str, str],
    template_by_key: dict[str, str],
) -> dict[str, Any]:
    map_key = str(identity["legacy_map_id"])
    map_id = str(identity["map_id"])
    map_type, map_type_evidence = _resolve_map_type(
        map_key,
        identity,
        release_binding,
        runtime_doc,
        catalog_by_id,
        template_by_key,
    )
    if map_type == "UNKNOWN":
        authoring_state = "NOT_READY"
    elif map_key in TRANSITION_DEBT_MAP_KEYS:
        authoring_state = "TRANSITION_DEBT"
    elif map_key in STRUCTURE_ONLY_MAP_KEYS:
        authoring_state = "STRUCTURE_ONLY"
    else:
        authoring_state = "NORMAL_EDITOR_AUTHORITY"

    layer_counts = _ensure_dict(snapshot_row.get("layer_counts"), f"snapshot.{map_key}.layer_counts")
    editor_monster = _as_int(layer_counts.get("monster_spawn", 0), f"snapshot.{map_key}.layer_counts.monster_spawn")
    editor_boss = _as_int(layer_counts.get("boss_spawn", 0), f"snapshot.{map_key}.layer_counts.boss_spawn")
    safe_evidence = _layer_row(snapshot_row, "safe_area", label=f"snapshot.{map_key}")
    door_evidence = _layer_row(snapshot_row, "door_points", label=f"snapshot.{map_key}")
    walkable = _walkable_evidence(snapshot_row, map_key)
    authority_counts = _authority_counts(authority_records)

    runtime_counts = runtime_evidence.get("spawn_counts")
    runtime_exists = bool(runtime_evidence.get("exists"))
    formal_playable = bool(
        runtime_exists and runtime_row_is_playable(release_binding)
    )
    # A hash-valid, formally playable runtime that already contains a monster
    # or boss layer is a published result, not an instruction to repopulate the
    # user's authoring document.  It must be excluded from both ordinary and
    # planner placement selection.  Transition debt keeps its stronger
    # PLACEMENT_BLOCKED precedence below.
    published_runtime_has_spawn_layer = bool(
        formal_playable
        and runtime_evidence.get("state") == "APPROVED_RELEASE_FILE"
        and runtime_counts is not None
        and runtime_counts.get("total", 0) > 0
    )

    # Geometry is deliberately not promoted from the collision digest to a
    # walkable grid.  That uncertainty is a planner validation requirement,
    # not a reason to hide an otherwise valid ordinary authority.  A map with
    # at least one ordinary/boss/elite auto-placement token is therefore
    # ready for the planner, while its deferred routes remain explicit below.
    if authoring_state == "TRANSITION_DEBT":
        placement_state = "PLACEMENT_BLOCKED"
        placement_reasons = ["transition_backfill_binding_mismatch"]
    elif published_runtime_has_spawn_layer:
        placement_state = "PRESERVE"
        placement_reasons = [
            "approved_formal_runtime_contains_published_monster_layer",
            "published_runtime_layer_requires_no_redeployment",
        ]
    elif authoring_state == "NOT_READY":
        placement_state = "PLACEMENT_BLOCKED"
        placement_reasons = ["map_type_unresolved"]
    elif authority_counts["blocked"]:
        placement_state = "PLACEMENT_BLOCKED"
        placement_reasons = ["authority_contains_unresolved_blocked_token"]
    elif authority_counts["allowed"]:
        placement_state = "READY_FOR_AUTO_PLACEMENT"
        placement_reasons = ["walkable_evidence_requires_planner_validation"]
    elif authority_counts["explicit"]:
        placement_state = "READY_FOR_PLANNER_VALIDATION"
        placement_reasons = ["no_ordinary_auto_route; explicit_routes_require_planner_validation"]
    elif authority_counts["special"]:
        placement_state = "SOURCE_REQUIRED"
        placement_reasons = ["no_ordinary_or_explicit_authority"]
    else:
        placement_state = "SOURCE_REQUIRED"
        placement_reasons = ["no_ordinary_or_explicit_authority"]

    deferred_authority_counts = {
        "explicit": authority_counts["explicit"],
        "special": authority_counts["special"],
        "blocked": authority_counts["blocked"],
    }
    requires_geometry_validation = placement_state in {
        "READY_FOR_AUTO_PLACEMENT",
        "READY_FOR_PLANNER_VALIDATION",
    }

    editor_path = _stable_source_path(
        snapshot_row.get("source_relative_path"), f"snapshot.{map_key}.source_relative_path"
    )
    editor = {
        "exists": True,
        "evidence_state": "RECORDED_IN_AUTHORING_SNAPSHOT",
        "path": f"map_editor_workspace/{editor_path}",
        "source_sha256": _hash_is_valid(snapshot_row.get("source_sha256"), f"snapshot.{map_key}.source_sha256"),
        "source_byte_size": _as_int(snapshot_row.get("source_byte_size"), f"snapshot.{map_key}.source_byte_size"),
        "source_root_kind": "primary_map_editor_workspace",
        "document_map_id": snapshot_row.get("document_map_id"),
        "document_runtime_map_id": _as_int(snapshot_row.get("document_runtime_map_id"), f"snapshot.{map_key}.document_runtime_map_id"),
        "design_size": [
            _as_int(value, f"snapshot.{map_key}.design_size")
            for value in _ensure_list(snapshot_row.get("design_size"), f"snapshot.{map_key}.design_size")
        ],
        "spawn_counts": {
            "monster_spawn": editor_monster,
            "boss_spawn": editor_boss,
            "total": editor_monster + editor_boss,
        },
        "layer_evidence": {
            "safe_area": safe_evidence,
            "door_points": door_evidence,
        },
    }

    runtime_count_row = {
        "state": runtime_evidence["state"],
        "monster_spawn": runtime_counts["monster_spawn"] if runtime_counts else None,
        "boss_spawn": runtime_counts["boss_spawn"] if runtime_counts else None,
        "total": runtime_counts["total"] if runtime_counts else None,
    }

    transition = {
        "state": "BLOCKED" if backfill_row is not None else "NOT_APPLICABLE",
    }
    if backfill_row is not None:
        transition.update(backfill_row)

    return {
        "map_id": map_id,
        "map_key": map_key,
        "display_name": identity["display_name"],
        "map_type": map_type,
        "map_type_evidence": map_type_evidence,
        "series": identity["series"],
        "legacy_map_id": map_key,
        "runtime_id": _as_int(identity["runtime_map_id"], f"identity.{map_key}.runtime_map_id"),
        "legacy_runtime_id": _as_int(identity["legacy_runtime_map_id"], f"identity.{map_key}.legacy_runtime_map_id"),
        "editor_exists": True,
        "runtime_exists": runtime_exists,
        "formal_playable": formal_playable,
        "authoring_state": authoring_state,
        "placement_state": placement_state,
        "placement_reasons": placement_reasons,
        "requires_geometry_validation": requires_geometry_validation,
        "deferred_authority_counts": deferred_authority_counts,
        "editor_spawn_counts": editor["spawn_counts"],
        "runtime_spawn_counts": runtime_count_row,
        "editor": editor,
        "runtime": runtime_evidence,
        "safe_evidence": safe_evidence,
        "door_evidence": door_evidence,
        "walkable_evidence": walkable,
        "authority_counts": authority_counts,
        "transition_backfill": transition,
    }


def runtime_row_is_playable(binding: dict[str, Any] | None) -> bool:
    if binding is None:
        return False
    release_row = _ensure_dict(binding.get("row"), "release binding.row")
    return release_row.get("release_state") == "implemented_playable"


def _validate_no_host_paths(value: Any, path: str = "inventory") -> None:
    if isinstance(value, dict):
        for key, child in value.items():
            _validate_no_host_paths(child, f"{path}.{key}")
    elif isinstance(value, list):
        for index, child in enumerate(value):
            _validate_no_host_paths(child, f"{path}[{index}]")
    elif isinstance(value, str):
        # Host paths are forbidden in all generated fields.  res:// and
        # repository-relative paths are intentionally allowed.
        if ABSOLUTE_PATH_RE.match(value):
            raise InventoryError(f"generated inventory contains host path at {path}")


def build_inventory(
    *,
    repo: Path = ROOT,
    snapshot_path: Path | None = None,
    authority_path: Path | None = None,
    backfill_path: Path | None = None,
    identity_path: Path | None = None,
    release_path: Path | None = None,
    design_catalog_path: Path | None = None,
    blank_templates_path: Path | None = None,
) -> dict[str, Any]:
    repo = repo.resolve()
    snapshot_path = snapshot_path or repo / SNAPSHOT_REL
    authority_path = authority_path or repo / AUTHORITY_REL
    backfill_path = backfill_path or repo / BACKFILL_REL
    identity_path = identity_path or repo / IDENTITY_REL
    release_path = release_path or repo / RELEASE_REL
    design_catalog_path = design_catalog_path or repo / DESIGN_CATALOG_REL
    blank_templates_path = blank_templates_path or repo / BLANK_TEMPLATES_REL

    snapshot, snapshot_raw = _read_json(snapshot_path, "authoring snapshot")
    authority, authority_raw = _read_json(authority_path, "monster placement authority")
    backfill, backfill_raw = _read_json(backfill_path, "transition backfill inventory")
    identity, identity_raw = _read_json(identity_path, "map identity registry")
    release, release_raw = _read_json(release_path, "runtime release registry")
    design_catalog, design_catalog_raw = _read_json(design_catalog_path, "map design catalog")
    blank_templates, blank_templates_raw = _read_json(blank_templates_path, "map blank templates")

    identity_rows, identity_by_key = _validate_identity(identity)
    snapshot_by_key = _validate_snapshot(snapshot, identity_rows, identity_by_key)
    authority_by_key, authority_object = _validate_authority(authority, identity_by_key)
    backfill_by_key = _validate_backfill(backfill, identity_by_key)
    # The validator returns bindings keyed by normalized legacy authoring key;
    # a formal canonical release therefore joins the same stable 67-map row.
    release_by_key = _validate_release_registry(release, identity_by_key)
    catalog_by_id, template_by_key = _validate_design_sources(design_catalog, blank_templates)

    runtime_files: dict[str, dict[str, Any]] = {}
    runtime_docs: dict[str, dict[str, Any] | None] = {}
    for map_key, release_binding in sorted(release_by_key.items()):
        runtime_doc, evidence = _safe_runtime_doc(repo, map_key, release_binding)
        runtime_docs[map_key] = runtime_doc
        runtime_files[map_key] = {
            key: evidence[key]
            for key in (
                "path",
                "file_sha256",
                "approved_build_sha256",
                "build_sha256",
                "hash_match",
                "state",
                "exists",
                "registry_map_key",
                "registry_key_kind",
                "normalized_map_key",
                "runtime_map_id",
                "redeployment_required",
                "spawn_counts_role",
            )
            if key in evidence
        }
        if "spawn_counts" in evidence:
            runtime_files[map_key]["spawn_counts"] = evidence["spawn_counts"]

    maps: list[dict[str, Any]] = []
    for identity_row in identity_rows:
        map_key = str(identity_row["legacy_map_id"])
        runtime_evidence = {
            "state": "NOT_IN_RELEASE_REGISTRY",
            "exists": False,
            "path": None,
            "runtime_path": None,
            "file_sha256": None,
            "approved_build_sha256": None,
            "build_sha256": None,
            "hash_match": False,
            "registry_map_key": None,
            "registry_key_kind": None,
            "normalized_map_key": map_key,
            "runtime_map_id": None,
            "redeployment_required": False,
            "spawn_counts_role": "no_published_runtime",
        }
        release_binding = release_by_key.get(map_key)
        if release_binding is not None:
            _, runtime_evidence = _safe_runtime_doc(repo, map_key, release_binding)
        maps.append(
            _build_map_row(
                repo,
                identity_row,
                snapshot_by_key[map_key],
                authority_by_key.get(map_key, []),
                backfill_by_key.get(map_key),
                release_binding,
                runtime_docs.get(map_key),
                runtime_evidence,
                catalog_by_id,
                template_by_key,
            )
        )

    if len(maps) != 67:
        raise InventoryError(f"generated map count={len(maps)} expected 67")

    authority_totals = Counter()
    for row in maps:
        for key, value in row["authority_counts"].items():
            if key != "token_occurrences":
                authority_totals[key] += value
        authority_totals["token_occurrences"] += row["authority_counts"]["token_occurrences"]

    authoring_state_counts = Counter(str(row["authoring_state"]) for row in maps)
    placement_state_counts = Counter(str(row["placement_state"]) for row in maps)
    walkable_state_counts = Counter(str(row["walkable_evidence"]["state"]) for row in maps)
    safe_state_counts = Counter(str(row["safe_evidence"]["state"]) for row in maps)
    door_state_counts = Counter(str(row["door_evidence"]["state"]) for row in maps)

    editor_monster_total = sum(row["editor_spawn_counts"]["monster_spawn"] for row in maps)
    editor_boss_total = sum(row["editor_spawn_counts"]["boss_spawn"] for row in maps)
    runtime_monster_total = sum(
        row["runtime_spawn_counts"]["monster_spawn"] or 0 for row in maps
    )
    runtime_boss_total = sum(row["runtime_spawn_counts"]["boss_spawn"] or 0 for row in maps)

    inputs: dict[str, Any] = {
        "authoring_snapshot": _input_ref(
            repo, snapshot_path, snapshot_raw, role="67-map authoring snapshot"
        ),
        "placement_authority": _input_ref(
            repo, authority_path, authority_raw, role="Phase 0 placement authority"
        ),
        "transition_backfill_inventory": _input_ref(
            repo, backfill_path, backfill_raw, role="runtime-to-editor transition backfill inventory"
        ),
        "map_identity_registry": _input_ref(
            repo, identity_path, identity_raw, role="formal map identity authority"
        ),
        "runtime_release_registry": _input_ref(
            repo, release_path, release_raw, role="formal runtime release authority"
        ),
        "map_design_catalog": _input_ref(
            repo, design_catalog_path, design_catalog_raw, role="map type primary catalog"
        ),
        "map_blank_templates": _input_ref(
            repo, blank_templates_path, blank_templates_raw, role="map type auxiliary template catalog"
        ),
        "runtime_release_files": runtime_files,
    }

    inventory: dict[str, Any] = {
        "schema_version": SCHEMA_VERSION,
        "inventory_id": INVENTORY_ID,
        "contract_id": INVENTORY_ID,
        "generated_by": "tools/map_editor/build_map_monster_placement_inventory.py",
        "inputs": inputs,
        "policy": {
            "fail_closed": True,
            "no_runtime_does_not_block_editor_authoring": True,
            "editor_exists_means": "source record is present in the tracked authoring snapshot; permanent map files are not opened",
            "runtime_exists_means": "release registry entry, approved runtime file and build hash all agree",
            "formal_playable_means": "runtime_exists and release_state=implemented_playable",
            "runtime_spawn_counts_role": "published_runtime_observation_not_authoring_input",
            "published_runtime_release_does_not_request_redeployment": True,
            "published_runtime_with_spawn_placement_state": "PRESERVE",
            "walkable": {
                "state_when_unavailable": "UNKNOWN",
                "evidence_when_unavailable": "collision_contract_available",
                "calculation_state_when_unavailable": "unknown",
                "safe_to_auto_place_when_unavailable": False,
                "collision_is_not_walkable": True,
            },
            "transition_debt_map_keys": list(TRANSITION_DEBT_MAP_KEYS),
            "structure_only_map_keys": list(STRUCTURE_ONLY_MAP_KEYS),
            "placement_state_precedence": [
                "TRANSITION_DEBT -> PLACEMENT_BLOCKED",
                "approved formal runtime with published monster/boss layer -> PRESERVE",
                "unresolved authority token -> PLACEMENT_BLOCKED",
                "allowed authority + editor -> READY_FOR_AUTO_PLACEMENT",
                "explicit authority without allowed authority -> READY_FOR_PLANNER_VALIDATION",
                "no allowed or explicit authority -> SOURCE_REQUIRED",
            ],
            "map_type_fallback_policy": "formal_identity_map_type_policy.v1",
        },
        "summary": {
            "formal_map_count": len(maps),
            "source_map_count": len(snapshot_by_key),
            "editor_exists_count": sum(bool(row["editor_exists"]) for row in maps),
            "runtime_exists_count": sum(bool(row["runtime_exists"]) for row in maps),
            "formal_playable_count": sum(bool(row["formal_playable"]) for row in maps),
            "transition_debt_count": authoring_state_counts["TRANSITION_DEBT"],
            "structure_only_count": authoring_state_counts["STRUCTURE_ONLY"],
            "ready_for_auto_placement_count": placement_state_counts["READY_FOR_AUTO_PLACEMENT"],
            "ready_for_planner_validation_count": placement_state_counts[
                "READY_FOR_PLANNER_VALIDATION"
            ],
            "source_required_count": placement_state_counts["SOURCE_REQUIRED"],
            "placement_blocked_count": placement_state_counts["PLACEMENT_BLOCKED"],
            "preserve_count": placement_state_counts["PRESERVE"],
            "authoring_state_counts": dict(sorted(authoring_state_counts.items())),
            "placement_state_counts": dict(sorted(placement_state_counts.items())),
            "walkable_state_counts": dict(sorted(walkable_state_counts.items())),
            "safe_state_counts": dict(sorted(safe_state_counts.items())),
            "door_state_counts": dict(sorted(door_state_counts.items())),
            "editor_spawn_counts": {
                "monster_spawn": editor_monster_total,
                "boss_spawn": editor_boss_total,
                "total": editor_monster_total + editor_boss_total,
            },
            "runtime_spawn_counts": {
                "monster_spawn": runtime_monster_total,
                "boss_spawn": runtime_boss_total,
                "total": runtime_monster_total + runtime_boss_total,
            },
            "authority_counts": dict(sorted(authority_totals.items())),
        },
        "maps": maps,
    }
    _validate_no_host_paths(inventory)
    return inventory


def _write_json(path: Path, value: dict[str, Any]) -> None:
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(
            json.dumps(value, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
            newline="\n",
        )
    except OSError as exc:
        raise InventoryError(f"cannot write inventory {path}: {exc}") from exc


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output",
        type=Path,
        required=True,
        help="explicit inventory JSON path (required for both generate and --check)",
    )
    parser.add_argument("--check", action="store_true", help="rebuild and compare with --output")
    parser.add_argument("--snapshot", type=Path, default=None)
    parser.add_argument("--authority", type=Path, default=None)
    parser.add_argument("--backfill", type=Path, default=None)
    parser.add_argument("--identity", type=Path, default=None)
    parser.add_argument("--release", type=Path, default=None)
    parser.add_argument("--design-catalog", type=Path, default=None)
    parser.add_argument("--blank-templates", type=Path, default=None)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _build_parser().parse_args(argv)
    output = args.output.resolve()
    try:
        inventory = build_inventory(
            repo=ROOT,
            snapshot_path=args.snapshot,
            authority_path=args.authority,
            backfill_path=args.backfill,
            identity_path=args.identity,
            release_path=args.release,
            design_catalog_path=args.design_catalog,
            blank_templates_path=args.blank_templates,
        )
        if args.check:
            expected, _ = _read_json(output, "tracked inventory")
            if expected != inventory:
                print(f"MAP_MONSTER_PLACEMENT_INVENTORY_CHECK_FAIL output={output}", file=sys.stderr)
                return 1
            summary = inventory["summary"]
            print(
                "MAP_MONSTER_PLACEMENT_INVENTORY_CHECK_PASS "
                f"maps={summary['formal_map_count']} "
                f"editor={summary['editor_exists_count']} "
                f"runtime={summary['runtime_exists_count']} "
                f"playable={summary['formal_playable_count']} "
                f"ready={summary['ready_for_auto_placement_count']} "
                f"planner_validation={summary['ready_for_planner_validation_count']} "
                f"source_required={summary['source_required_count']} "
                f"preserve={summary['preserve_count']} "
                f"blocked={summary['placement_blocked_count']}"
            )
            return 0
        _write_json(output, inventory)
        summary = inventory["summary"]
        print(
            "MAP_MONSTER_PLACEMENT_INVENTORY_GENERATED "
            f"maps={summary['formal_map_count']} "
            f"editor={summary['editor_exists_count']} "
            f"runtime={summary['runtime_exists_count']} "
            f"playable={summary['formal_playable_count']} "
            f"ready={summary['ready_for_auto_placement_count']} "
            f"planner_validation={summary['ready_for_planner_validation_count']} "
            f"source_required={summary['source_required_count']} "
            f"preserve={summary['preserve_count']} "
            f"blocked={summary['placement_blocked_count']}"
        )
        return 0
    except InventoryError as exc:
        print(f"MAP_MONSTER_PLACEMENT_INVENTORY_FAIL {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
