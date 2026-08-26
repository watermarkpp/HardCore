#!/usr/bin/env python3
"""Fail-closed snapshot and candidate writer for map monster placement.

This module deliberately works on the user-authored editor workspace only.
It never edits a source map and it never publishes a runtime release.  A
snapshot is an immutable read-only witness for the 67 primary maps; a writer
can use that witness to emit an explicitly requested candidate document whose
only changed fields are ``layers.monster_spawn`` and ``layers.boss_spawn``.

The source editor documents currently use legacy map keys and legacy runtime
IDs.  The formal identity registry supplies their canonical map IDs and
canonical runtime IDs.  Both are retained in the snapshot so that identity
resolution is explicit and never inferred from a display name or a numeric
runtime ID (which is not unique in the legacy source set).
"""

from __future__ import annotations

import argparse
import copy
import datetime as _datetime
import hashlib
import json
import math
import os
import re
import sys
from pathlib import Path
from typing import Any, Iterable, Mapping, Sequence


SCRIPT_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_REGISTRY_PATH = SCRIPT_ROOT / "assets" / "data" / "map_design" / "map_identity_registry.json"
DEFAULT_PORTAL_OVERLAY_PATH = SCRIPT_ROOT / "assets" / "data" / "map_design" / "map_portal_network.json"
DEFAULT_AUTHORITY_PATH = SCRIPT_ROOT / "assets" / "data" / "map_design" / "map_monster_placement_authority_v2.json"
SNAPSHOT_ID = "map_authoring_snapshot_20260826"
SNAPSHOT_CONTRACT_ID = "hardcore.map_authoring_snapshot.v1"
AUTHORITY_CONTRACT_ID = "hardcore.map_monster_placement_authority.v2"

TARGET_LAYERS = ("monster_spawn", "boss_spawn")

# These are the formal policy IDs in scripts/monster_respawn_policy.gd.  The
# script is intentionally not loaded at runtime here: this utility must stay
# a pure Python, no-Godot validation boundary.
ORDINARY_RESPAWN_POLICIES = frozenset({"beginner_outdoor", "normal_cave", "special_normal"})
ELITE_OR_BOSS_RESPAWN_POLICIES = frozenset({"elite", "boss"})

# Actual editor layer names are retained verbatim.  Alias names make the
# manifest convenient for audits while the ``source_layers`` field prevents
# any ambiguity about how an aggregate was computed.
KNOWN_LAYER_NAMES = (
    "boss_spawn",
    "collision",
    "collision_erase",
    "door_points",
    "editor_guides",
    "ground_base",
    "ground_overlay",
    "interactables",
    "light",
    "map_entrance_points",
    "map_exit_points",
    "monster_spawn",
    "npc_points",
    "object_base",
    "object_front",
    "region_semantics",
    "region_trigger",
    "respawn_points",
    "safe_area",
    "shadow",
    "terrain_base",
    "terrain_front",
)

LAYER_ALIASES: dict[str, tuple[str, ...]] = {
    "ground": ("ground_base", "ground_overlay"),
    "instances": ("terrain_base", "terrain_front", "object_base", "object_front", "interactables"),
    "map_exits": ("map_exit_points",),
    "map_exit": ("map_exit_points",),
    "door": ("door_points",),
    "doors": ("door_points",),
    "safe": ("safe_area",),
    "respawn": ("respawn_points",),
    "npc": ("npc_points",),
}

_SAFE_PATH_PARTS = frozenset({".bak", "runtime", "map_editor_workspace"})
_ID_RE = re.compile(r"^[A-Za-z][A-Za-z0-9_.:-]*$")
_UUID_RE = re.compile(
    r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$",
    re.IGNORECASE,
)


class SafeWriterError(ValueError):
    """An expected fail-closed validation error."""


def _error(message: str) -> None:
    raise SafeWriterError(message)


def _canonical_bytes(value: Any) -> bytes:
    """Return deterministic UTF-8 JSON bytes for hashes and comparisons."""

    try:
        return json.dumps(
            value,
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
            allow_nan=False,
        ).encode("utf-8")
    except (TypeError, ValueError) as exc:
        _error(f"non-canonical-json-value: {exc}")
    raise AssertionError("unreachable")


def canonical_json_sha256(value: Any) -> str:
    return hashlib.sha256(_canonical_bytes(value)).hexdigest()


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def sha256_file(path: Path) -> str:
    try:
        digest = hashlib.sha256()
        with path.open("rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(chunk)
        return digest.hexdigest()
    except OSError as exc:
        _error(f"cannot-read-file: {path}: {exc}")
    raise AssertionError("unreachable")


def _reject_json_constant(value: str) -> None:
    raise ValueError(f"non-finite-json-number:{value}")


def _load_json(path: Path, *, label: str) -> tuple[dict[str, Any], bytes]:
    if not path.is_file():
        _error(f"missing-{label}: {path}")
    if path.name.lower().endswith(".bak") or ".bak." in path.name.lower():
        _error(f"backup-source-forbidden: {path}")
    try:
        raw = path.read_bytes()
        text = raw.decode("utf-8")
        value = json.loads(text, parse_constant=_reject_json_constant)
    except (OSError, UnicodeDecodeError, json.JSONDecodeError, ValueError) as exc:
        _error(f"invalid-{label}: {path}: {exc}")
    if not isinstance(value, dict):
        _error(f"{label}-must-be-object: {path}")
    return value, raw


def _resolve_existing(path: Path, *, label: str) -> Path:
    path = Path(path).expanduser()
    if not path.is_absolute():
        path = Path.cwd() / path
    try:
        path = path.resolve(strict=True)
    except OSError as exc:
        _error(f"cannot-resolve-{label}: {path}: {exc}")
    return path


def _resolve_nonexistent_or_existing(path: Path) -> Path:
    path = Path(path).expanduser()
    if not path.is_absolute():
        path = Path.cwd() / path
    try:
        return path.resolve(strict=False)
    except OSError as exc:
        _error(f"cannot-resolve-output: {path}: {exc}")
    raise AssertionError("unreachable")


def _is_within(path: Path, parent: Path) -> bool:
    try:
        path.relative_to(parent)
        return True
    except ValueError:
        return False


def _normalise_relative(path: Path, root: Path) -> str:
    try:
        return path.relative_to(root).as_posix()
    except ValueError:
        # Snapshot metadata must never leak a host-absolute path.  A custom
        # fixture may live outside the repository root, so represent it as a
        # relative traversal when the platform permits it; the raw SHA still
        # provides the stable identity.  Different-drive paths cannot be
        # relativized on Windows and use a deliberately opaque relative name.
        try:
            return Path(os.path.relpath(path, root)).as_posix()
        except ValueError:
            return f"external/{path.name}"


def _number(value: Any, *, label: str, positive: bool = False, nonnegative: bool = False) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        _error(f"{label}-must-be-number")
    result = float(value)
    if not math.isfinite(result):
        _error(f"{label}-must-be-finite")
    if positive and result <= 0:
        _error(f"{label}-must-be-positive")
    if nonnegative and result < 0:
        _error(f"{label}-must-be-nonnegative")
    return result


def _integer_number(value: Any, *, label: str, positive: bool = False, nonnegative: bool = False) -> int:
    result = _number(value, label=label, positive=positive, nonnegative=nonnegative)
    if not result.is_integer():
        _error(f"{label}-must-be-integer")
    return int(result)


def _pair(value: Any, *, label: str, positive: bool = False, nonnegative: bool = False) -> tuple[float, float]:
    if not isinstance(value, (list, tuple)) or len(value) != 2:
        _error(f"{label}-must-be-pair")
    return (
        _number(value[0], label=f"{label}[0]", positive=positive, nonnegative=nonnegative),
        _number(value[1], label=f"{label}[1]", positive=positive, nonnegative=nonnegative),
    )


def _tile(value: Any, *, label: str = "tile") -> tuple[int, int]:
    x, y = _pair(value, label=label)
    if not x.is_integer() or not y.is_integer():
        _error(f"{label}-must-use-integer-coordinates")
    return int(x), int(y)


def _iso_utc(timestamp_ns: int) -> str:
    value = _datetime.datetime.fromtimestamp(timestamp_ns / 1_000_000_000, tz=_datetime.timezone.utc)
    return value.isoformat().replace("+00:00", "Z")


def _registry_entries(
    registry: Mapping[str, Any],
    *,
    require_formal_count: bool = True,
) -> list[dict[str, Any]]:
    if registry.get("contract_id") != "hardcore.formal_map_identity.v1":
        _error("registry-contract-mismatch")
    entries = registry.get("maps")
    if not isinstance(entries, list):
        _error("registry-maps-must-be-array")
    formal_count = registry.get("formal_map_count")
    if isinstance(formal_count, bool) or not isinstance(formal_count, int) or formal_count <= 0:
        _error(f"registry-formal-map-count-invalid: declared={formal_count!r}")
    if len(entries) != formal_count:
        _error(f"registry-formal-map-count-mismatch: declared={formal_count} actual={len(entries)}")
    # Production snapshot/writer entry points are deliberately locked to the
    # formal 67-map registry.  The explicit opt-out is used only by the
    # self-contained unit fixture, so a small synthetic registry cannot be
    # mistaken for the production authority at the CLI boundary.
    if require_formal_count and formal_count != 67:
        _error(f"registry-formal-map-count-mismatch: expected=67 declared={formal_count} actual={len(entries)}")
    result: list[dict[str, Any]] = []
    seen_legacy: set[str] = set()
    seen_canonical: set[str] = set()
    for index, raw in enumerate(entries):
        if not isinstance(raw, dict):
            _error(f"registry-entry-not-object: index={index}")
        for field in ("legacy_map_id", "map_id", "runtime_map_id", "legacy_runtime_map_id", "display_name"):
            if field not in raw:
                _error(f"registry-entry-missing-{field}: index={index}")
        legacy = raw["legacy_map_id"]
        canonical = raw["map_id"]
        if not isinstance(legacy, str) or not legacy or legacy in seen_legacy:
            _error(f"registry-legacy-id-invalid-or-duplicate: {legacy!r}")
        if (
            legacy in {".", ".."}
            or Path(legacy).name != legacy
            or "/" in legacy
            or "\\" in legacy
        ):
            _error(f"registry-legacy-id-path-invalid: {legacy!r}")
        if not isinstance(canonical, str) or not canonical or canonical in seen_canonical:
            _error(f"registry-canonical-id-invalid-or-duplicate: {canonical!r}")
        _integer_number(raw["runtime_map_id"], label=f"registry[{legacy}].runtime_map_id", positive=True)
        _integer_number(raw["legacy_runtime_map_id"], label=f"registry[{legacy}].legacy_runtime_map_id", positive=True)
        if not isinstance(raw["display_name"], str) or not raw["display_name"].strip():
            _error(f"registry-display-name-invalid: {legacy}")
        seen_legacy.add(legacy)
        seen_canonical.add(canonical)
        result.append(dict(raw))
    return result


def load_registry(
    registry_path: Path = DEFAULT_REGISTRY_PATH,
    *,
    require_formal_count: bool = True,
) -> tuple[dict[str, Any], bytes, Path]:
    path = _resolve_existing(Path(registry_path), label="registry")
    registry, raw = _load_json(path, label="registry")
    _registry_entries(registry, require_formal_count=require_formal_count)
    return registry, raw, path


def resolve_map(
    registry: Mapping[str, Any],
    requested_map_id: str,
    *,
    require_formal_count: bool = True,
) -> dict[str, Any]:
    """Resolve exactly one canonical or legacy map ID; never use display names."""

    if not isinstance(requested_map_id, str) or not requested_map_id.strip():
        _error("map-id-required")
    requested = requested_map_id.strip()
    entries = _registry_entries(registry, require_formal_count=require_formal_count)
    matches = [
        entry
        for entry in entries
        if requested == entry.get("legacy_map_id") or requested == entry.get("map_id")
    ]
    if len(matches) != 1:
        _error(f"map-id-must-match-one-canonical-or-legacy-entry: {requested}")
    return matches[0]


def load_authority(
    authority_path: Path = DEFAULT_AUTHORITY_PATH,
    *,
    require_formal_count: bool = True,
) -> tuple[dict[str, Any], bytes, Path, dict[tuple[str, int, str, int], dict[str, Any]]]:
    """Load the placement authority and index its stable token references.

    The source manifest intentionally remains immutable.  The index is built
    in memory from ``maps[*].tokens`` using the four authored coordinates
    ``map_id + source_line + source_category_role + source_token_index``;
    no occurrence ID is added to or written back into the authority file.
    """

    path = _resolve_existing(Path(authority_path), label="authority-manifest")
    authority, raw = _load_json(path, label="authority-manifest")
    if authority.get("contract_id") != AUTHORITY_CONTRACT_ID:
        _error("authority-manifest-contract-mismatch")
    maps = authority.get("maps")
    if not isinstance(maps, list):
        _error("authority-manifest-maps-must-be-array")
    summary = authority.get("summary")
    if not isinstance(summary, dict):
        _error("authority-manifest-summary-missing")
    formal_count = summary.get("formal_map_count")
    if isinstance(formal_count, bool) or not isinstance(formal_count, int) or formal_count <= 0:
        _error(f"authority-manifest-formal-map-count-invalid: declared={formal_count!r}")
    if len(maps) != formal_count:
        _error(
            f"authority-manifest-formal-map-count-mismatch: declared={formal_count} actual={len(maps)}"
        )
    if require_formal_count and formal_count != 67:
        _error(
            f"authority-manifest-formal-map-count-mismatch: expected=67 declared={formal_count} actual={len(maps)}"
        )

    index: dict[tuple[str, int, str, int], dict[str, Any]] = {}
    seen_map_ids: set[str] = set()
    for map_index, map_record in enumerate(maps):
        if not isinstance(map_record, dict):
            _error(f"authority-manifest-map-not-object:index={map_index}")
        canonical_map_id = map_record.get("map_id")
        legacy_map_id = map_record.get("legacy_map_id")
        if not isinstance(canonical_map_id, str) or not canonical_map_id.strip():
            _error(f"authority-manifest-map-id-invalid:index={map_index}")
        if canonical_map_id in seen_map_ids:
            _error(f"authority-manifest-map-id-duplicate:{canonical_map_id}")
        if not isinstance(legacy_map_id, str) or not legacy_map_id.strip():
            _error(f"authority-manifest-legacy-map-id-invalid:index={map_index}")
        tokens = map_record.get("tokens")
        if not isinstance(tokens, list):
            _error(f"authority-manifest-map-tokens-must-be-array:{canonical_map_id}")
        seen_map_ids.add(canonical_map_id)
        for token_index, raw_token in enumerate(tokens):
            if not isinstance(raw_token, dict):
                _error(f"authority-manifest-token-not-object:{canonical_map_id}:index={token_index}")
            if raw_token.get("map_id") != canonical_map_id:
                _error(f"authority-manifest-token-map-id-mismatch:{canonical_map_id}:index={token_index}")
            if raw_token.get("legacy_map_id") != legacy_map_id:
                _error(f"authority-manifest-token-legacy-map-id-mismatch:{canonical_map_id}:index={token_index}")
            source_line = _integer_number(
                raw_token.get("source_line"),
                label=f"authority-manifest[{canonical_map_id}].tokens[{token_index}].source_line",
                positive=True,
            )
            source_token_index = _integer_number(
                raw_token.get("source_token_index"),
                label=f"authority-manifest[{canonical_map_id}].tokens[{token_index}].source_token_index",
                positive=True,
            )
            source_category_role = raw_token.get("source_category_role")
            if not isinstance(source_category_role, str) or not source_category_role.strip():
                _error(
                    f"authority-manifest-token-source-category-role-invalid:{canonical_map_id}:index={token_index}"
                )
            placement_kind = raw_token.get("placement_kind")
            if not isinstance(placement_kind, str) or not placement_kind.strip():
                _error(f"authority-manifest-token-placement-kind-invalid:{canonical_map_id}:index={token_index}")
            auto_allowed = raw_token.get("auto_placement_allowed")
            if not isinstance(auto_allowed, bool):
                _error(f"authority-manifest-token-auto-allowed-invalid:{canonical_map_id}:index={token_index}")
            resolved_ids = raw_token.get("resolved_monster_ids")
            if not isinstance(resolved_ids, list):
                _error(f"authority-manifest-token-resolved-ids-must-be-array:{canonical_map_id}:index={token_index}")
            normalized_ids: list[int] = []
            for resolved_index, resolved_id in enumerate(resolved_ids):
                normalized_ids.append(
                    _integer_number(
                        resolved_id,
                        label=(
                            f"authority-manifest[{canonical_map_id}].tokens[{token_index}]"
                            f".resolved_monster_ids[{resolved_index}]"
                        ),
                        positive=True,
                    )
                )
            if len(set(normalized_ids)) != len(normalized_ids):
                _error(f"authority-manifest-token-resolved-ids-duplicate:{canonical_map_id}:index={token_index}")
            resolved_monster_id = raw_token.get("resolved_monster_id")
            if resolved_monster_id is not None:
                normalized_resolved_monster_id = _integer_number(
                    resolved_monster_id,
                    label=(
                        f"authority-manifest[{canonical_map_id}].tokens[{token_index}]"
                        ".resolved_monster_id"
                    ),
                    positive=True,
                )
                if len(normalized_ids) != 1 or normalized_resolved_monster_id != normalized_ids[0]:
                    _error(
                        f"authority-manifest-token-resolved-id-mismatch:{canonical_map_id}:index={token_index}"
                    )
            key = (canonical_map_id, source_line, source_category_role.strip(), source_token_index)
            if key in index:
                _error(f"authority-manifest-token-reference-duplicate:{key}")
            normalized_token = dict(raw_token)
            normalized_token["source_line"] = source_line
            normalized_token["source_token_index"] = source_token_index
            normalized_token["source_category_role"] = source_category_role.strip()
            normalized_token["placement_kind"] = placement_kind.strip()
            normalized_token["resolved_monster_ids"] = normalized_ids
            index[key] = normalized_token
    return authority, raw, path, index


def _validate_document(entry: Mapping[str, Any], document: Mapping[str, Any], *, legacy_map_id: str) -> list[str]:
    errors: list[str] = []
    if document.get("map_id") != legacy_map_id:
        errors.append(f"document-map-id-mismatch:{document.get('map_id')!r}!={legacy_map_id}")
    try:
        document_runtime = _integer_number(
            document.get("runtime_map_id"),
            label=f"document[{legacy_map_id}].runtime_map_id",
            positive=True,
        )
        expected_runtime = _integer_number(
            entry.get("legacy_runtime_map_id"),
            label=f"registry[{legacy_map_id}].legacy_runtime_map_id",
            positive=True,
        )
        if document_runtime != expected_runtime:
            errors.append(f"document-runtime-map-id-mismatch:{document_runtime}!={expected_runtime}")
    except SafeWriterError as exc:
        errors.append(str(exc))
    if not isinstance(document.get("display_name"), str) or not document.get("display_name", "").strip():
        errors.append("document-display-name-missing")
    design = document.get("design")
    if not isinstance(design, dict):
        errors.append("document-design-missing")
    else:
        try:
            width, height = _pair(design.get("design_size"), label=f"document[{legacy_map_id}].design_size", positive=True)
            if not width.is_integer() or not height.is_integer():
                errors.append("document-design-size-must-use-integer-tiles")
        except SafeWriterError as exc:
            errors.append(str(exc))
    layers = document.get("layers")
    if not isinstance(layers, dict):
        errors.append("document-layers-missing")
    else:
        for name, value in layers.items():
            if not isinstance(value, list):
                errors.append(f"document-layer-must-be-array:{name}")
    return errors


def _document_size(document: Mapping[str, Any], *, legacy_map_id: str) -> tuple[int, int]:
    design = document.get("design")
    if not isinstance(design, dict):
        _error(f"document-design-missing:{legacy_map_id}")
    width, height = _pair(design.get("design_size"), label=f"document[{legacy_map_id}].design_size", positive=True)
    if not width.is_integer() or not height.is_integer():
        _error(f"document-design-size-must-use-integer-tiles:{legacy_map_id}")
    return int(width), int(height)


def _layer_value(layers: Mapping[str, Any], name: str) -> list[Any]:
    value = layers.get(name, [])
    if not isinstance(value, list):
        _error(f"layer-must-be-array:{name}")
    return value


def _layer_descriptor(layers: Mapping[str, Any], source_layers: Sequence[str]) -> dict[str, Any]:
    values = {name: _layer_value(layers, name) for name in source_layers}
    if len(source_layers) == 1:
        hashed_value: Any = values[source_layers[0]]
    else:
        hashed_value = values
    digest = canonical_json_sha256(hashed_value)
    return {
        "count": sum(len(value) for value in values.values()),
        "sha256": digest,
        "hash": digest,
        "source_layers": list(source_layers),
    }


def layer_inventory(document: Mapping[str, Any]) -> dict[str, Any]:
    layers = document.get("layers")
    if not isinstance(layers, dict):
        _error("document-layers-missing")
    names = set(KNOWN_LAYER_NAMES) | set(layers.keys())
    inventory: dict[str, Any] = {}
    for name in sorted(names):
        inventory[name] = _layer_descriptor(layers, (name,))
    for alias, sources in LAYER_ALIASES.items():
        inventory[alias] = _layer_descriptor(layers, sources)
    return inventory


def _portal_overlay_record(path: Path, *, root: Path) -> dict[str, Any]:
    overlay, raw = _load_json(path, label="portal-overlay")
    connections = overlay.get("connections")
    if not isinstance(connections, list):
        _error("portal-overlay-connections-must-be-array")
    mode_counts: dict[str, int] = {}
    endpoint_set: set[tuple[str, str]] = set()
    map_ids: set[str] = set()
    for index, connection in enumerate(connections):
        if not isinstance(connection, dict):
            _error(f"portal-overlay-connection-not-object:index={index}")
        mode = connection.get("mode")
        if not isinstance(mode, str) or not mode.strip():
            _error(f"portal-overlay-connection-field-invalid:index={index}:mode")
        # The overlay contains the original bidirectional pair shape for its
        # first 51 records and an explicit source/target shape for the 15
        # one-way records.  Both are formal records in the complete overlay;
        # neither is silently dropped or converted into map layers.
        if all(field in connection for field in ("a_map_id", "a_portal_id", "b_map_id", "b_portal_id")):
            endpoint_values = (
                connection.get("a_map_id"),
                connection.get("a_portal_id"),
                connection.get("b_map_id"),
                connection.get("b_portal_id"),
            )
            if any(not isinstance(value, str) or not value.strip() for value in endpoint_values):
                _error(f"portal-overlay-connection-endpoint-invalid:index={index}")
            a_map, a_portal, b_map, b_portal = endpoint_values
        elif all(field in connection for field in ("source_map_id", "source_portal_id", "target_map_id", "target_portal_id")):
            endpoint_values = (
                connection.get("source_map_id"),
                connection.get("source_portal_id"),
                connection.get("target_map_id"),
                connection.get("target_portal_id"),
            )
            if any(not isinstance(value, str) or not value.strip() for value in endpoint_values):
                _error(f"portal-overlay-connection-endpoint-invalid:index={index}")
            a_map, a_portal, b_map, b_portal = endpoint_values
        else:
            _error(f"portal-overlay-connection-endpoint-shape-unsupported:index={index}")
        mode_counts[mode] = mode_counts.get(mode, 0) + 1
        endpoint_set.add((a_map, a_portal))
        endpoint_set.add((b_map, b_portal))
        map_ids.add(a_map)
        map_ids.add(b_map)
    declared_pairs = overlay.get("bidirectional_pair_count")
    if declared_pairs is not None:
        declared_pairs = _integer_number(declared_pairs, label="portal-overlay.bidirectional_pair_count", nonnegative=True)
    return {
        "relative_path": _normalise_relative(path, root),
        "sha256": sha256_bytes(raw),
        "byte_size": len(raw),
        "statistics": {
            "connection_count": len(connections),
            "endpoint_count": len(endpoint_set),
            "map_count": len(map_ids),
            "mode_counts": dict(sorted(mode_counts.items())),
            "declared_bidirectional_pair_count": declared_pairs,
        },
    }


def _map_record(
    registry_entry: Mapping[str, Any],
    source_root: Path,
) -> dict[str, Any]:
    legacy = str(registry_entry["legacy_map_id"])
    if legacy == "sandbox_64" or legacy.lower().startswith("sandbox"):
        _error(f"sandbox-map-forbidden:{legacy}")
    source_path = source_root / legacy / f"{legacy}.editor.json"
    if not _is_within(source_path, source_root):
        _error(f"source-path-escapes-root:{legacy}")
    if source_path.name.lower().endswith(".bak") or not source_path.name == f"{legacy}.editor.json":
        _error(f"source-file-must-be-exact-primary-editor-json:{source_path}")
    try:
        resolved_source_path = source_path.resolve(strict=True)
    except OSError as exc:
        _error(f"cannot-resolve-primary-source:{source_path}:{exc}")
    if not _is_within(resolved_source_path, source_root):
        _error(f"source-path-escapes-root:{legacy}")
    if resolved_source_path != source_path:
        _error(f"primary-source-must-not-be-symlink:{source_path}")
    source_path = resolved_source_path
    document, raw = _load_json(source_path, label=f"map-document:{legacy}")
    errors = _validate_document(registry_entry, document, legacy_map_id=legacy)
    if errors:
        _error(";".join(errors))
    try:
        stat = source_path.stat()
    except OSError as exc:
        _error(f"cannot-stat-map-document:{source_path}:{exc}")
    inventory = layer_inventory(document)
    document_record = {
        "map_id": document["map_id"],
        "runtime_map_id": document["runtime_map_id"],
        "display_name": document["display_name"],
        "design_size": list(document["design"]["design_size"]),
    }
    return {
        "legacy_map_id": legacy,
        "map_id": registry_entry["map_id"],
        "runtime_map_id": registry_entry["runtime_map_id"],
        "legacy_runtime_map_id": registry_entry["legacy_runtime_map_id"],
        "source_relative_path": _normalise_relative(source_path, source_root),
        "source_sha256": sha256_bytes(raw),
        # ``sha256``/``mtime_ns`` aliases make the manifest easy to consume
        # without weakening the explicit source_* names.
        "sha256": sha256_bytes(raw),
        "source_byte_size": len(raw),
        "source_mtime_ns": stat.st_mtime_ns,
        "mtime_ns": stat.st_mtime_ns,
        "source_mtime_utc": _iso_utc(stat.st_mtime_ns),
        "document": document_record,
        "document_map_id": document_record["map_id"],
        "document_runtime_map_id": document_record["runtime_map_id"],
        "document_display_name": document_record["display_name"],
        "design_size": document_record["design_size"],
        "layer_counts": {name: descriptor["count"] for name, descriptor in inventory.items()},
        "layer_hashes": {name: descriptor["sha256"] for name, descriptor in inventory.items()},
        "layers": inventory,
    }


def build_snapshot_data(
    source_root: Path,
    *,
    registry_path: Path = DEFAULT_REGISTRY_PATH,
    portal_overlay_path: Path = DEFAULT_PORTAL_OVERLAY_PATH,
    require_formal_count: bool = True,
) -> dict[str, Any]:
    source_root = _resolve_existing(Path(source_root), label="source-root")
    registry, registry_raw, resolved_registry = load_registry(
        registry_path,
        require_formal_count=require_formal_count,
    )
    portal_path = _resolve_existing(Path(portal_overlay_path), label="portal-overlay")
    entries = _registry_entries(registry, require_formal_count=require_formal_count)
    records = [_map_record(entry, source_root) for entry in entries]
    repo_root = SCRIPT_ROOT
    return {
        "schema_version": 1,
        "contract_id": SNAPSHOT_CONTRACT_ID,
        "snapshot_contract_id": SNAPSHOT_CONTRACT_ID,
        "snapshot_id": SNAPSHOT_ID,
        "generated_at_utc": _datetime.datetime.now(_datetime.timezone.utc).isoformat().replace("+00:00", "Z"),
        "source_root_kind": "primary_map_editor_workspace",
        "formal_map_count": len(records),
        "registry": {
            "relative_path": _normalise_relative(resolved_registry, repo_root),
            "sha256": sha256_bytes(registry_raw),
            "contract_id": registry.get("contract_id"),
            "formal_map_count": registry.get("formal_map_count"),
        },
        # This is intentionally a sibling root field, not a map layer.  The
        # overlay is a complete external network witness.
        "portal_overlay": _portal_overlay_record(portal_path, root=repo_root),
        "maps": records,
    }


def build_snapshot(
    source_root: Path,
    snapshot_path: Path,
    *,
    registry_path: Path = DEFAULT_REGISTRY_PATH,
    portal_overlay_path: Path = DEFAULT_PORTAL_OVERLAY_PATH,
    require_formal_count: bool = True,
) -> dict[str, Any]:
    source_root_resolved = _resolve_existing(Path(source_root), label="source-root")
    output = _resolve_nonexistent_or_existing(Path(snapshot_path))
    if _is_within(output, source_root_resolved):
        _error(f"snapshot-output-must-not-be-inside-source-root:{output}")
    data = build_snapshot_data(
        source_root_resolved,
        registry_path=registry_path,
        portal_overlay_path=portal_overlay_path,
        require_formal_count=require_formal_count,
    )
    try:
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_bytes(json.dumps(data, ensure_ascii=False, indent=2).encode("utf-8") + b"\n")
    except OSError as exc:
        _error(f"cannot-write-snapshot:{output}:{exc}")
    return {
        "ok": True,
        "mode": "snapshot",
        "snapshot_path": output.as_posix(),
        "formal_map_count": data["formal_map_count"],
        "portal_connection_count": data["portal_overlay"]["statistics"]["connection_count"],
        "portal_endpoint_count": data["portal_overlay"]["statistics"]["endpoint_count"],
    }


def _first_difference(left: Any, right: Any, path: str = "$") -> str | None:
    if type(left) is not type(right):
        return f"{path}:type {type(left).__name__}!={type(right).__name__}"
    if isinstance(left, dict):
        left_keys = set(left)
        right_keys = set(right)
        if left_keys != right_keys:
            missing = sorted(left_keys - right_keys)
            extra = sorted(right_keys - left_keys)
            return f"{path}:keys missing={missing} extra={extra}"
        for key in sorted(left_keys):
            difference = _first_difference(left[key], right[key], f"{path}.{key}")
            if difference:
                return difference
        return None
    if isinstance(left, list):
        if len(left) != len(right):
            return f"{path}:length {len(left)}!={len(right)}"
        for index, (left_value, right_value) in enumerate(zip(left, right)):
            difference = _first_difference(left_value, right_value, f"{path}[{index}]")
            if difference:
                return difference
        return None
    if left != right:
        return f"{path}:value {left!r}!={right!r}"
    return None


def _snapshot_without_timestamp(value: Mapping[str, Any]) -> dict[str, Any]:
    result = copy.deepcopy(dict(value))
    result.pop("generated_at_utc", None)
    return result


def verify_snapshot(
    source_root: Path,
    snapshot_path: Path,
    *,
    registry_path: Path = DEFAULT_REGISTRY_PATH,
    portal_overlay_path: Path = DEFAULT_PORTAL_OVERLAY_PATH,
    require_formal_count: bool = True,
) -> dict[str, Any]:
    source_root_resolved = _resolve_existing(Path(source_root), label="source-root")
    snapshot_file = _resolve_existing(Path(snapshot_path), label="snapshot")
    saved, _ = _load_json(snapshot_file, label="snapshot")
    if saved.get("contract_id") != SNAPSHOT_CONTRACT_ID:
        _error("snapshot-contract-mismatch")
    current = build_snapshot_data(
        source_root_resolved,
        registry_path=registry_path,
        portal_overlay_path=portal_overlay_path,
        require_formal_count=require_formal_count,
    )
    difference = _first_difference(_snapshot_without_timestamp(saved), _snapshot_without_timestamp(current))
    if difference:
        _error(f"snapshot-drift-fail-closed:{difference}")
    return {
        "ok": True,
        "mode": "verify-snapshot",
        "snapshot_path": snapshot_file.as_posix(),
        "formal_map_count": current["formal_map_count"],
        "source_map_sha256_verified": current["formal_map_count"],
        "portal_overlay_sha256_verified": True,
    }


def _stable_id(value: Any, *, label: str) -> str:
    if not isinstance(value, str) or not value.strip():
        _error(f"{label}-required")
    result = value.strip()
    if not _ID_RE.fullmatch(result) or result.isdigit():
        _error(f"{label}-must-be-explicit-stable-id")
    if _UUID_RE.fullmatch(result) or "random" in result.lower() or result.lower().startswith("uuid"):
        _error(f"{label}-random-or-uuid-forbidden")
    return result


def _occupancy_footprint(entry: Mapping[str, Any], *, kind: str) -> tuple[int, int]:
    # Spawn entries normally occupy their tile.  An explicitly authored
    # footprint is honored, but unsupported geometry never gets guessed.
    for key in ("occupancy_footprint_tiles", "footprint_tiles"):
        if key in entry:
            width, height = _pair(entry[key], label=f"{kind}.{key}", positive=True)
            if not width.is_integer() or not height.is_integer():
                _error(f"{kind}.{key}-must-use-integer-tiles")
            return int(width), int(height)
    return 1, 1


def _rectangle_occupied(origin: tuple[int, int], extent: tuple[int, int], size: tuple[int, int]) -> set[tuple[int, int]]:
    result: set[tuple[int, int]] = set()
    for y in range(origin[1], origin[1] + extent[1]):
        for x in range(origin[0], origin[0] + extent[0]):
            if 0 <= x < size[0] and 0 <= y < size[1]:
                result.add((x, y))
    return result


def _point_on_segment(px: float, py: float, ax: float, ay: float, bx: float, by: float) -> bool:
    cross = (px - ax) * (by - ay) - (py - ay) * (bx - ax)
    if abs(cross) > 1e-9:
        return False
    return min(ax, bx) - 1e-9 <= px <= max(ax, bx) + 1e-9 and min(ay, by) - 1e-9 <= py <= max(ay, by) + 1e-9


def _point_in_polygon(point: tuple[float, float], points: Sequence[tuple[float, float]]) -> bool:
    x, y = point
    inside = False
    for index, (ax, ay) in enumerate(points):
        bx, by = points[(index + 1) % len(points)]
        if _point_on_segment(x, y, ax, ay, bx, by):
            return True
        if (ay > y) != (by > y):
            crossing_x = (bx - ax) * (y - ay) / (by - ay) + ax
            if x < crossing_x:
                inside = not inside
    return inside


def _polygon_points(value: Any, *, label: str) -> list[tuple[float, float]]:
    if not isinstance(value, list) or len(value) < 3:
        _error(f"{label}-requires-three-points")
    points: list[tuple[float, float]] = []
    for index, point in enumerate(value):
        x, y = _pair(point, label=f"{label}[{index}]")
        points.append((x, y))
    return points


def _shape_cells(shape: str, data: Mapping[str, Any], size: tuple[int, int], *, label: str) -> set[tuple[int, int]]:
    if shape == "rect":
        raw_rect = data.get("rect")
        if not isinstance(raw_rect, list) or len(raw_rect) != 4:
            _error(f"{label}.rect-invalid")
        x, y, width, height = (
            _number(raw_rect[0], label=f"{label}.rect.x"),
            _number(raw_rect[1], label=f"{label}.rect.y"),
            _number(raw_rect[2], label=f"{label}.rect.width", positive=True),
            _number(raw_rect[3], label=f"{label}.rect.height", positive=True),
        )
        result: set[tuple[int, int]] = set()
        for tile_y in range(max(0, math.floor(y)), min(size[1], math.ceil(y + height))):
            for tile_x in range(max(0, math.floor(x)), min(size[0], math.ceil(x + width))):
                center_x, center_y = tile_x + 0.5, tile_y + 0.5
                if x <= center_x <= x + width and y <= center_y <= y + height:
                    result.add((tile_x, tile_y))
        return result
    if shape == "ellipse":
        raw_rect = data.get("rect")
        if not isinstance(raw_rect, list) or len(raw_rect) != 4:
            _error(f"{label}.ellipse-rect-invalid")
        x, y, width, height = (
            _number(raw_rect[0], label=f"{label}.ellipse.x"),
            _number(raw_rect[1], label=f"{label}.ellipse.y"),
            _number(raw_rect[2], label=f"{label}.ellipse.width", positive=True),
            _number(raw_rect[3], label=f"{label}.ellipse.height", positive=True),
        )
        center_x, center_y = x + width * 0.5, y + height * 0.5
        result: set[tuple[int, int]] = set()
        for tile_y in range(max(0, math.floor(y)), min(size[1], math.ceil(y + height))):
            for tile_x in range(max(0, math.floor(x)), min(size[0], math.ceil(x + width))):
                normalized_x = (tile_x + 0.5 - center_x) / (width * 0.5)
                normalized_y = (tile_y + 0.5 - center_y) / (height * 0.5)
                if normalized_x * normalized_x + normalized_y * normalized_y <= 1.0:
                    result.add((tile_x, tile_y))
        return result
    if shape == "polygon":
        points = _polygon_points(data.get("points"), label=f"{label}.polygon")
        min_x = max(0, math.floor(min(point[0] for point in points)))
        max_x = min(size[0] - 1, math.ceil(max(point[0] for point in points)))
        min_y = max(0, math.floor(min(point[1] for point in points)))
        max_y = min(size[1] - 1, math.ceil(max(point[1] for point in points)))
        return {
            (tile_x, tile_y)
            for tile_y in range(min_y, max_y + 1)
            for tile_x in range(min_x, max_x + 1)
            if _point_in_polygon((tile_x + 0.5, tile_y + 0.5), points)
        }
    _error(f"{label}.unsupported-shape:{shape!r}")
    raise AssertionError("unreachable")


def _safe_area_cells(entry: Mapping[str, Any], size: tuple[int, int], *, label: str) -> set[tuple[int, int]]:
    center = _tile(entry.get("tile"), label=f"{label}.tile")
    shape = str(entry.get("shape", "circle"))
    if shape == "polygon":
        raw = entry.get("polygon_tiles", entry.get("polygon_ground_gu"))
        points = _polygon_points(raw, label=f"{label}.polygon")
        min_x = max(0, math.floor(min(point[0] for point in points)))
        max_x = min(size[0] - 1, math.ceil(max(point[0] for point in points)))
        min_y = max(0, math.floor(min(point[1] for point in points)))
        max_y = min(size[1] - 1, math.ceil(max(point[1] for point in points)))
        return {
            (tile_x, tile_y)
            for tile_y in range(min_y, max_y + 1)
            for tile_x in range(min_x, max_x + 1)
            if _point_in_polygon((tile_x + 0.5, tile_y + 0.5), points)
        }
    if shape != "circle":
        _error(f"{label}.unsupported-shape:{shape!r}")
    radius_value = entry.get("radius_tiles", entry.get("radius_gu", 0))
    radius = _number(radius_value, label=f"{label}.radius", nonnegative=True)
    if radius <= 0:
        return {center}
    result: set[tuple[int, int]] = set()
    for tile_y in range(max(0, math.floor(center[1] - radius)), min(size[1], math.ceil(center[1] + radius + 1))):
        for tile_x in range(max(0, math.floor(center[0] - radius)), min(size[0], math.ceil(center[0] + radius + 1))):
            if math.hypot((tile_x + 0.5) - (center[0] + 0.5), (tile_y + 0.5) - (center[1] + 0.5)) <= radius + 1e-9:
                result.add((tile_x, tile_y))
    return result


def _entry_tile_required(entry: Mapping[str, Any], *, label: str, size: tuple[int, int]) -> tuple[int, int]:
    tile = _tile(entry.get("tile"), label=f"{label}.tile")
    if not (0 <= tile[0] < size[0] and 0 <= tile[1] < size[1]):
        _error(f"{label}.tile-out-of-bounds:{tile}")
    return tile


def _collect_static_blocked(document: Mapping[str, Any], size: tuple[int, int]) -> set[tuple[int, int]]:
    layers = document.get("layers")
    if not isinstance(layers, dict):
        _error("document-layers-missing")
    blocked: set[tuple[int, int]] = set()

    for index, entry in enumerate(_layer_value(layers, "collision")):
        label = f"collision[{index}]"
        if not isinstance(entry, dict):
            _error(f"{label}-must-be-object")
        # Missing blocks_monster is treated conservatively as blocking.
        if entry.get("blocks_monster", True) is False:
            continue
        shape = entry.get("shape")
        data = entry.get("data")
        if not isinstance(shape, str) or not isinstance(data, dict):
            _error(f"{label}-geometry-unreadable")
        blocked.update(_shape_cells(shape, data, size, label=label))

    # collision_erase is part of the editor collision contract.  It is
    # applied after collision, matching MapEditorCollisionService.
    for index, entry in enumerate(_layer_value(layers, "collision_erase")):
        label = f"collision_erase[{index}]"
        if not isinstance(entry, dict):
            _error(f"{label}-must-be-object")
        tile = _entry_tile_required(entry, label=label, size=size)
        blocked.discard(tile)

    for layer_name in ("object_base", "object_front", "terrain_base", "terrain_front"):
        for index, entry in enumerate(_layer_value(layers, layer_name)):
            label = f"{layer_name}[{index}]"
            if not isinstance(entry, dict):
                _error(f"{label}-must-be-object")
            policy = entry.get("collision_policy")
            if not isinstance(policy, str):
                _error(f"{label}.collision_policy-unreadable")
            override = entry.get("map_collision_override", "default")
            if override == "disabled" or policy in ("none", "manual"):
                continue
            if policy == "custom_polygon":
                raw_polygon = entry.get("collision_polygon", entry.get("polygon_tiles"))
                points = _polygon_points(raw_polygon, label=f"{label}.collision_polygon")
                blocked.update(
                    {
                        (tile_x, tile_y)
                        for tile_y in range(size[1])
                        for tile_x in range(size[0])
                        if _point_in_polygon((tile_x + 0.5, tile_y + 0.5), points)
                    }
                )
                continue
            if policy not in {"preset", "solid_footprint", "terrain_stamp_generated", "wall_cells_generated"}:
                _error(f"{label}.collision_policy-unsupported:{policy!r}")
            if "tile" not in entry:
                _error(f"{label}.tile-required-for-solid-footprint")
            origin = _entry_tile_required(entry, label=label, size=size)
            collision_fp = entry.get("collision_footprint_tiles")
            if collision_fp is None:
                _error(f"{label}.collision_footprint_tiles-required")
            collision_width, collision_height = _pair(collision_fp, label=f"{label}.collision_footprint_tiles", nonnegative=True)
            if not collision_width.is_integer() or not collision_height.is_integer():
                _error(f"{label}.collision_footprint_tiles-must-use-integer-tiles")
            collision_size = (int(collision_width), int(collision_height))
            if collision_size[0] <= 0 or collision_size[1] <= 0:
                _error(f"{label}.collision_footprint_tiles-must-be-positive")
            visual_raw = entry.get("footprint_tiles", collision_size)
            visual_width, visual_height = _pair(visual_raw, label=f"{label}.footprint_tiles", positive=True)
            if not visual_width.is_integer() or not visual_height.is_integer():
                _error(f"{label}.footprint_tiles-must-use-integer-tiles")
            visual_size = (int(visual_width), int(visual_height))
            adjusted_origin = (
                origin[0] + max(0, (visual_size[0] - collision_size[0]) // 2),
                origin[1] + max(0, (visual_size[1] - collision_size[1]) // 2),
            )
            blocked.update(_rectangle_occupied(adjusted_origin, collision_size, size))

    for layer_name in ("door_points", "map_exit_points", "map_entrance_points"):
        for index, entry in enumerate(_layer_value(layers, layer_name)):
            label = f"{layer_name}[{index}]"
            if not isinstance(entry, dict):
                _error(f"{label}-must-be-object")
            tile = _entry_tile_required(entry, label=label, size=size)
            blocked.add(tile)
            # Some authored doorway assets include an explicit visual footprint
            # and origin.  Honor it only when both are present and valid; never
            # infer a footprint from a display sprite or array index.
            if "portal_visual_footprint_tiles" in entry or "portal_visual_origin_tile" in entry:
                if "portal_visual_footprint_tiles" not in entry or "portal_visual_origin_tile" not in entry:
                    _error(f"{label}.portal-visual-geometry-incomplete")
                width, height = _pair(entry["portal_visual_footprint_tiles"], label=f"{label}.portal_visual_footprint_tiles", positive=True)
                origin = _tile(entry["portal_visual_origin_tile"], label=f"{label}.portal_visual_origin_tile")
                if not width.is_integer() or not height.is_integer():
                    _error(f"{label}.portal_visual_footprint_tiles-must-use-integer-tiles")
                blocked.update(_rectangle_occupied(origin, (int(width), int(height)), size))

    for index, entry in enumerate(_layer_value(layers, "npc_points")):
        label = f"npc_points[{index}]"
        if not isinstance(entry, dict):
            _error(f"{label}-must-be-object")
        tile = _entry_tile_required(entry, label=label, size=size)
        blocked.add(tile)
        if "occupancy_footprint_tiles" in entry:
            width, height = _pair(entry["occupancy_footprint_tiles"], label=f"{label}.occupancy_footprint_tiles", positive=True)
            if not width.is_integer() or not height.is_integer():
                _error(f"{label}.occupancy_footprint_tiles-must-use-integer-tiles")
            blocked.update(_rectangle_occupied(tile, (int(width), int(height)), size))

    for index, entry in enumerate(_layer_value(layers, "safe_area")):
        label = f"safe_area[{index}]"
        if not isinstance(entry, dict):
            _error(f"{label}-must-be-object")
        blocked.update(_safe_area_cells(entry, size, label=label))

    return blocked


def _extract_placement_layers(value: Any) -> dict[str, list[dict[str, Any]]]:
    if not isinstance(value, dict):
        _error("placement-input-must-be-object")
    if "layers" in value:
        if set(value) != {"layers"}:
            _error("placement-input-layers-form-must-not-contain-map-fields")
        layers = value["layers"]
        if not isinstance(layers, dict):
            _error("placement-input-layers-must-be-object")
        unknown = sorted(set(layers) - set(TARGET_LAYERS))
        if unknown:
            _error(f"placement-input-non-target-layer-forbidden:{unknown}")
        payload = layers
    else:
        unknown = sorted(set(value) - set(TARGET_LAYERS))
        if unknown:
            _error(f"placement-input-unknown-field:{unknown}")
        payload = value
    if not payload:
        _error("placement-input-must-provide-monster-or-boss-layer")
    result: dict[str, list[dict[str, Any]]] = {}
    for layer_name, raw_entries in payload.items():
        if layer_name not in TARGET_LAYERS:
            _error(f"placement-input-non-target-layer-forbidden:{layer_name}")
        if not isinstance(raw_entries, list):
            _error(f"placement-input-layer-must-be-array:{layer_name}")
        result[layer_name] = copy.deepcopy(raw_entries)
    return result


def _parse_authority_ref(value: Any, *, label: str) -> dict[str, Any]:
    """Normalize the stable, four-field authority reference from an input."""

    if not isinstance(value, dict):
        _error(f"{label}-must-be-object")
    required = {"map_id", "source_line", "source_category_role", "source_token_index"}
    missing = sorted(required - set(value))
    if missing:
        _error(f"{label}-missing-fields:{missing}")
    unknown = sorted(set(value) - required)
    if unknown:
        _error(f"{label}-unknown-fields:{unknown}")
    map_id = value.get("map_id")
    if not isinstance(map_id, str) or not map_id.strip():
        _error(f"{label}.map_id-required")
    source_category_role = value.get("source_category_role")
    if not isinstance(source_category_role, str) or not source_category_role.strip():
        _error(f"{label}.source_category_role-required")
    return {
        "map_id": map_id.strip(),
        "source_line": _integer_number(value.get("source_line"), label=f"{label}.source_line", positive=True),
        "source_category_role": source_category_role.strip(),
        "source_token_index": _integer_number(
            value.get("source_token_index"),
            label=f"{label}.source_token_index",
            positive=True,
        ),
    }


def _validate_authority_binding(
    entry: dict[str, Any],
    *,
    layer_name: str,
    label: str,
    current_canonical_map_id: str,
    authority_index: Mapping[tuple[str, int, str, int], Mapping[str, Any]],
    authority_ref_policy: Mapping[tuple[str, int, str, int], Mapping[str, Any]] | None = None,
) -> None:
    ref_key = "authority_ref" if "authority_ref" in entry else "authority_reference"
    if ref_key not in entry:
        _error(f"{label}.authority_ref-required-for-new-placement")
    reference = _parse_authority_ref(entry[ref_key], label=f"{label}.authority_ref")
    if reference["map_id"] != current_canonical_map_id:
        _error(
            f"{label}.authority_ref-map-id-mismatch:{reference['map_id']}!={current_canonical_map_id}"
        )
    key = (
        reference["map_id"],
        reference["source_line"],
        reference["source_category_role"],
        reference["source_token_index"],
    )
    token = authority_index.get(key)
    if token is None:
        _error(f"{label}.authority_ref-not-found:{key}")
    policy = (authority_ref_policy or {}).get(key)
    if policy is not None and not isinstance(policy, Mapping):
        _error(f"{label}.authority_ref-policy-invalid:{key}")
    if token.get("placement_kind") != layer_name:
        _error(
            f"{label}.authority_ref-placement-kind-mismatch:"
            f"{token.get('placement_kind')!r}!={layer_name!r}"
        )
    role = token.get("source_category_role")
    expected_roles = {"ordinary"} if layer_name == "monster_spawn" else {"elite", "boss"}
    policy_roles = set(policy.get("allowed_source_category_roles", [])) if policy else set()
    if role not in expected_roles and role not in policy_roles:
        _error(f"{label}.authority_ref-category-role-mismatch:{role!r}")
    allowed_statuses = set(policy.get("allowed_statuses", [])) if policy else set()
    token_status = token.get("auto_placement_status")
    if policy is None:
        if (
            token.get("auto_placement_allowed") is not True
            or token_status != "AUTO_PLACEMENT_ALLOWED"
            or token.get("placement_allowed") is not True
        ):
            _error(f"{label}.authority_ref-auto-placement-forbidden:{key}")
    elif token_status not in allowed_statuses:
        _error(
            f"{label}.authority_ref-policy-status-forbidden:{token_status!r}:{key}"
        )
    if (
        policy is None
        and (token.get("status") != "resolved" or token.get("resolution_status") != "resolved")
    ) or (
        policy is not None
        and not bool(policy.get("allow_unresolved", False))
        and (token.get("status") != "resolved" or token.get("resolution_status") != "resolved")
    ):
        _error(f"{label}.authority_ref-unresolved-or-not-resolved:{key}")
    resolved_ids = token.get("resolved_monster_ids")
    selected_values = policy.get("selected_monster_ids") if policy else None
    if selected_values is not None:
        if not isinstance(selected_values, list) or not selected_values:
            _error(f"{label}.authority_ref-policy-selected-ids-invalid:{key}")
        allowed_selected_ids = {
            _integer_number(
                value,
                label=f"{label}.authority_ref.policy.selected_monster_ids",
                positive=True,
            )
            for value in selected_values
        }
        resolved_id = _integer_number(
            entry.get("monster_id"),
            label=f"{label}.monster_id",
            positive=True,
        )
        if resolved_id not in allowed_selected_ids:
            _error(f"{label}.authority_ref-policy-monster-id-forbidden:{resolved_id}:{key}")
        if not isinstance(resolved_ids, list):
            _error(f"{label}.authority_ref-resolved-ids-invalid:{key}")
        if resolved_id not in {
            _integer_number(
                value,
                label=f"{label}.authority_ref.resolved_monster_id",
                positive=True,
            )
            for value in resolved_ids
            if isinstance(value, (int, float)) and not isinstance(value, bool)
        } and not bool(policy.get("allow_unresolved", False)):
            _error(f"{label}.authority_ref-selected-id-not-in-authority:{key}")
    else:
        if not isinstance(resolved_ids, list) or len(resolved_ids) != 1:
            _error(f"{label}.authority_ref-monster-id-not-unique:{key}")
        resolved_id = _integer_number(
            resolved_ids[0],
            label=f"{label}.authority_ref.resolved_monster_id",
            positive=True,
        )
    if entry.get("monster_id") != resolved_id:
        _error(f"{label}.authority_ref-monster-id-mismatch:{entry.get('monster_id')}!={resolved_id}")
    entry.pop("authority_reference", None)
    entry["authority_ref"] = reference


def _validate_spawn_entry(
    entry: Any,
    *,
    layer_name: str,
    index: int,
    size: tuple[int, int],
    blocked: set[tuple[int, int]],
    existing_semantic_ids: set[str],
    used_semantic_ids: set[str],
    occupied_by_candidates: list[tuple[str, set[tuple[int, int]]]],
    authority_ref_required: bool,
    current_canonical_map_id: str,
    authority_index: Mapping[tuple[str, int, str, int], Mapping[str, Any]],
    authority_ref_policy: Mapping[tuple[str, int, str, int], Mapping[str, Any]] | None = None,
) -> dict[str, Any]:
    label = f"{layer_name}[{index}]"
    if not isinstance(entry, dict):
        _error(f"{label}-must-be-object")
    normalized = copy.deepcopy(entry)
    if "kind" in normalized and normalized["kind"] != layer_name:
        _error(f"{label}.kind-mismatch")
    normalized["kind"] = layer_name

    monster_id = normalized.get("monster_id")
    if isinstance(monster_id, bool) or not isinstance(monster_id, (int, float)):
        _error(f"{label}.monster_id-positive-integer-required")
    monster_id_value = _number(monster_id, label=f"{label}.monster_id", positive=True)
    if not monster_id_value.is_integer():
        _error(f"{label}.monster_id-positive-integer-required")
    normalized["monster_id"] = int(monster_id_value)

    if authority_ref_required:
        _validate_authority_binding(
            normalized,
            layer_name=layer_name,
            label=label,
            current_canonical_map_id=current_canonical_map_id,
            authority_index=authority_index,
            authority_ref_policy=authority_ref_policy,
        )

    spawn_group_id = _stable_id(normalized.get("spawn_group_id"), label=f"{label}.spawn_group_id")
    normalized["spawn_group_id"] = spawn_group_id
    semantic_id = _stable_id(normalized.get("semantic_id"), label=f"{label}.semantic_id")
    if semantic_id in existing_semantic_ids or semantic_id in used_semantic_ids:
        _error(f"{label}.semantic_id-must-be-unique:{semantic_id}")
    used_semantic_ids.add(semantic_id)
    normalized["semantic_id"] = semantic_id

    tile = _entry_tile_required(normalized, label=label, size=size)
    normalized["tile"] = [tile[0], tile[1]]

    if layer_name == "monster_spawn":
        policy = normalized.get("respawn_policy_id")
        if not isinstance(policy, str) or not policy.strip():
            _error(f"{label}.respawn_policy_id-required-for-ordinary-monster")
        policy = policy.strip()
        if policy not in ORDINARY_RESPAWN_POLICIES:
            _error(f"{label}.respawn_policy_id-invalid-for-ordinary-monster:{policy}")
        normalized["respawn_policy_id"] = policy
    else:
        # Canonical classification owns Elite/Boss timing.  An empty policy is
        # therefore the formal, explicit omission allowed for boss_spawn; if a
        # policy is provided it may only be the matching canonical tier.
        if "respawn_policy_id" in normalized:
            policy = normalized["respawn_policy_id"]
            if not isinstance(policy, str):
                _error(f"{label}.respawn_policy_id-must-be-string-or-empty")
            policy = policy.strip()
            if policy and policy not in ELITE_OR_BOSS_RESPAWN_POLICIES:
                _error(f"{label}.respawn_policy_id-invalid-for-boss-or-elite:{policy}")
            normalized["respawn_policy_id"] = policy

    for key in ("count", "max_alive"):
        if key in normalized:
            normalized[key] = _integer_number(normalized[key], label=f"{label}.{key}", positive=True)
    if "respawn_seconds" in normalized:
        normalized["respawn_seconds"] = _number(normalized["respawn_seconds"], label=f"{label}.respawn_seconds", positive=True)
    if "radius_gu" in normalized:
        normalized["radius_gu"] = _number(normalized["radius_gu"], label=f"{label}.radius_gu", nonnegative=True)
    for key in ("occupancy_footprint_tiles", "footprint_tiles"):
        if key in normalized:
            _occupancy_footprint(normalized, kind=label)
            break

    footprint = _occupancy_footprint(normalized, kind=label)
    if tile[0] + footprint[0] > size[0] or tile[1] + footprint[1] > size[1]:
        _error(f"{label}.geometry-out-of-bounds")
    occupied = _rectangle_occupied(tile, footprint, size)
    if not occupied:
        _error(f"{label}.geometry-out-of-bounds")
    for occupied_tile in sorted(occupied):
        if occupied_tile in blocked:
            _error(f"{label}.landing-blocked:{occupied_tile}")
    for other_label, other_occupied in occupied_by_candidates:
        overlap = occupied & other_occupied
        if overlap:
            _error(f"{label}.overlaps-candidate:{other_label}:{sorted(overlap)}")
    occupied_by_candidates.append((label, occupied))
    return normalized


def _non_target_document(document: Mapping[str, Any]) -> dict[str, Any]:
    result = copy.deepcopy(dict(document))
    layers = result.get("layers")
    if not isinstance(layers, dict):
        _error("document-layers-missing")
    for layer_name in TARGET_LAYERS:
        layers.pop(layer_name, None)
    return result


def _candidate_output_path(output: Path, *, source_root: Path, source_path: Path, legacy_map_id: str) -> Path:
    resolved = _resolve_nonexistent_or_existing(output)
    if resolved.exists() and resolved.is_symlink():
        _error(f"candidate-output-symlink-forbidden:{resolved}")
    if resolved.exists() and source_path.exists():
        try:
            if os.path.samefile(resolved, source_path):
                _error("candidate-output-aliases-source")
        except OSError:
            # A path that cannot be compared safely is not an acceptable
            # overwrite target.  The explicit output can be changed by the
            # caller to a normal, independent file.
            _error(f"candidate-output-cannot-be-compared-safely:{resolved}")
    if resolved.name.lower().endswith(".bak") or ".bak." in resolved.name.lower():
        _error(f"candidate-output-backup-forbidden:{resolved}")
    # Never allow a candidate to be mistaken for a source file or a runtime
    # release.  Keeping outputs outside the source root also proves that the
    # primary workspace remains byte-for-byte untouched.
    if _is_within(resolved, source_root):
        _error(f"candidate-output-must-be-outside-source-root:{resolved}")
    if any(part.lower() in _SAFE_PATH_PARTS for part in resolved.parts):
        _error(f"candidate-output-path-forbidden:{resolved}")
    if resolved.exists() and resolved.is_dir():
        resolved = resolved / f"{legacy_map_id}.candidate.editor.json"
    if resolved == source_path:
        _error("candidate-output-equals-source")
    return resolved


def write_candidate(
    source_root: Path,
    snapshot_path: Path,
    requested_map_id: str,
    placement_input: Path,
    candidate_output: Path,
    *,
    dry_run: bool = True,
    registry_path: Path = DEFAULT_REGISTRY_PATH,
    portal_overlay_path: Path = DEFAULT_PORTAL_OVERLAY_PATH,
    authority_path: Path = DEFAULT_AUTHORITY_PATH,
    require_formal_count: bool = True,
    authority_ref_policy: Mapping[tuple[str, int, str, int], Mapping[str, Any]] | None = None,
) -> dict[str, Any]:
    source_root_resolved = _resolve_existing(Path(source_root), label="source-root")
    snapshot_file = _resolve_existing(Path(snapshot_path), label="snapshot")
    input_file = _resolve_existing(Path(placement_input), label="placement-input")
    verify_result = verify_snapshot(
        source_root_resolved,
        snapshot_file,
        registry_path=registry_path,
        portal_overlay_path=portal_overlay_path,
        require_formal_count=require_formal_count,
    )
    registry, _, _ = load_registry(
        registry_path,
        require_formal_count=require_formal_count,
    )
    registry_entry = resolve_map(
        registry,
        requested_map_id,
        require_formal_count=require_formal_count,
    )
    _, authority_raw, authority_file, authority_index = load_authority(
        authority_path,
        require_formal_count=require_formal_count,
    )
    legacy = str(registry_entry["legacy_map_id"])
    source_path = source_root_resolved / legacy / f"{legacy}.editor.json"
    document, source_raw = _load_json(source_path, label=f"map-document:{legacy}")
    errors = _validate_document(registry_entry, document, legacy_map_id=legacy)
    if errors:
        _error(";".join(errors))
    input_value, _ = _load_json(input_file, label="placement-input")
    requested_layers = _extract_placement_layers(input_value)
    size = _document_size(document, legacy_map_id=legacy)
    blocked = _collect_static_blocked(document, size)

    layers = document.get("layers")
    if not isinstance(layers, dict):
        _error("document-layers-missing")
    existing_semantic_ids: set[str] = set()
    for layer_name, entries in layers.items():
        if layer_name in TARGET_LAYERS:
            continue
        if not isinstance(entries, list):
            _error(f"document-layer-must-be-array:{layer_name}")
        for index, entry in enumerate(entries):
            if isinstance(entry, dict) and isinstance(entry.get("semantic_id"), str) and entry["semantic_id"].strip():
                existing_semantic_ids.add(entry["semantic_id"].strip())

    normalized_layers: dict[str, list[dict[str, Any]]] = {
        layer_name: copy.deepcopy(_layer_value(layers, layer_name)) for layer_name in TARGET_LAYERS
    }
    used_semantic_ids: set[str] = set()
    occupied_by_candidates: list[tuple[str, set[tuple[int, int]]]] = []
    for layer_name in TARGET_LAYERS:
        # A missing input layer means "retain the source layer".  Retained
        # entries are still validated: every spawn in the resulting document
        # must satisfy the same identity, policy, geometry, and occupancy
        # contract as a newly authored entry.
        entries_to_validate = (
            requested_layers[layer_name]
            if layer_name in requested_layers
            else _layer_value(layers, layer_name)
        )
        normalized_layers[layer_name] = [
            _validate_spawn_entry(
                entry,
                layer_name=layer_name,
                index=index,
                size=size,
                blocked=blocked,
                existing_semantic_ids=existing_semantic_ids,
                used_semantic_ids=used_semantic_ids,
                occupied_by_candidates=occupied_by_candidates,
                authority_ref_required=layer_name in requested_layers,
                current_canonical_map_id=str(registry_entry["map_id"]),
                authority_index=authority_index,
                authority_ref_policy=authority_ref_policy,
            )
            for index, entry in enumerate(entries_to_validate)
        ]

    candidate = copy.deepcopy(document)
    candidate_layers = candidate.get("layers")
    if not isinstance(candidate_layers, dict):
        _error("document-layers-missing")
    for layer_name in TARGET_LAYERS:
        candidate_layers[layer_name] = normalized_layers[layer_name]

    source_non_target = _non_target_document(document)
    candidate_non_target = _non_target_document(candidate)
    if source_non_target != candidate_non_target:
        _error("candidate-non-target-fields-changed")
    source_non_target_sha = canonical_json_sha256(source_non_target)
    candidate_non_target_sha = canonical_json_sha256(candidate_non_target)
    if source_non_target_sha != candidate_non_target_sha:
        _error("candidate-non-target-canonical-hash-changed")

    output_path = _candidate_output_path(
        Path(candidate_output),
        source_root=source_root_resolved,
        source_path=source_path,
        legacy_map_id=legacy,
    )
    layer_changes = {}
    for layer_name in TARGET_LAYERS:
        before = _layer_value(layers, layer_name)
        after = _layer_value(candidate_layers, layer_name)
        layer_changes[layer_name] = {
            "before_count": len(before),
            "after_count": len(after),
            "before_sha256": canonical_json_sha256(before),
            "after_sha256": canonical_json_sha256(after),
            "changed": before != after,
        }

    if not dry_run:
        try:
            output_path.parent.mkdir(parents=True, exist_ok=True)
            output_path.write_bytes(json.dumps(candidate, ensure_ascii=False, indent=2).encode("utf-8") + b"\n")
        except OSError as exc:
            _error(f"cannot-write-candidate:{output_path}:{exc}")

    return {
        "ok": True,
        "mode": "dry-run" if dry_run else "candidate-written",
        "map_id": registry_entry["map_id"],
        "legacy_map_id": legacy,
        "runtime_map_id": registry_entry["runtime_map_id"],
        "source_relative_path": _normalise_relative(source_path, source_root_resolved),
        "source_sha256": sha256_bytes(source_raw),
        "authority_relative_path": _normalise_relative(authority_file, SCRIPT_ROOT),
        "authority_sha256": sha256_bytes(authority_raw),
        "candidate_output": output_path.as_posix(),
        "written": not dry_run,
        "verified_source_map_count": verify_result["source_map_sha256_verified"],
        "changed_layers": layer_changes,
        "non_target_fields_unchanged": True,
        "source_non_target_sha256": source_non_target_sha,
        "candidate_non_target_sha256": candidate_non_target_sha,
        "build_or_publish_performed": False,
    }


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-root", required=True, type=Path, help="primary map_editor_workspace root")
    parser.add_argument("--registry", type=Path, default=DEFAULT_REGISTRY_PATH)
    parser.add_argument("--portal-overlay", type=Path, default=DEFAULT_PORTAL_OVERLAY_PATH)
    parser.add_argument(
        "--authority-manifest",
        "--authority",
        dest="authority_path",
        type=Path,
        default=DEFAULT_AUTHORITY_PATH,
        help="map monster placement authority manifest for candidate writes",
    )
    parser.add_argument("--snapshot", type=Path, help="snapshot output (generation) or snapshot witness (writer)")
    parser.add_argument("--verify-snapshot", type=Path, help="verify this snapshot against the current source root")
    parser.add_argument("--map-id", help="canonical map_id or exact legacy_map_id")
    parser.add_argument("--placement-input", type=Path, help="JSON object containing monster_spawn and/or boss_spawn")
    parser.add_argument("--candidate-output", type=Path, help="explicit candidate file or output directory")
    parser.add_argument(
        "--write-candidate",
        "--write",
        dest="write_candidate",
        action="store_true",
        help="emit the validated candidate; without this flag the command is a dry run",
    )
    parser.add_argument("--dry-run", action="store_true", help="validate and report without writing a candidate (default)")
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = _parser()
    args = parser.parse_args(argv)
    try:
        if args.verify_snapshot is not None:
            if args.snapshot is not None or args.placement_input is not None or args.candidate_output is not None or args.map_id is not None:
                _error("verify-snapshot-cannot-be-combined-with-writer-options")
            if args.write_candidate or args.dry_run:
                _error("verify-snapshot-does-not-accept-write-or-dry-run-flags")
            report = verify_snapshot(
                args.source_root,
                args.verify_snapshot,
                registry_path=args.registry,
                portal_overlay_path=args.portal_overlay,
            )
        elif args.placement_input is not None or args.map_id is not None or args.candidate_output is not None or args.write_candidate:
            if args.snapshot is None or args.map_id is None or args.placement_input is None or args.candidate_output is None:
                _error("writer-requires-source-root-snapshot-map-id-placement-input-candidate-output")
            if args.write_candidate and args.dry_run:
                _error("write-candidate-and-dry-run-are-mutually-exclusive")
            report = write_candidate(
                args.source_root,
                args.snapshot,
                args.map_id,
                args.placement_input,
                args.candidate_output,
                dry_run=not args.write_candidate,
                registry_path=args.registry,
                portal_overlay_path=args.portal_overlay,
                authority_path=args.authority_path,
            )
        else:
            if args.snapshot is None:
                _error("snapshot-path-required")
            if args.write_candidate or args.dry_run:
                _error("snapshot-generation-does-not-accept-writer-flags")
            report = build_snapshot(
                args.source_root,
                args.snapshot,
                registry_path=args.registry,
                portal_overlay_path=args.portal_overlay,
            )
        print(json.dumps(report, ensure_ascii=False, sort_keys=True))
        return 0
    except SafeWriterError as exc:
        print(f"{parser.prog}: ERROR: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
