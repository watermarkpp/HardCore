#!/usr/bin/env python3
"""Normalize the portal metadata in the current map-editor workspaces.

The map identity registry and portal network are the only authorities used to
join documents.  ``legacy`` mode operates on the 67 documents whose map keys
are ``legacy_map_id``; ``formal`` mode operates on the 67 documents whose map
keys are ``map_id``.  A workspace may contain both sets (the repository does),
but only the selected set is read for mutation and validation.

This is deliberately a small, data-only boundary.  It never rewrites ground,
spawn, NPC, object, or any other authored layer.  Before a write, every
document is validated from the in-memory result and every staged replacement
is prepared.  Replacements are then made one file at a time with best-effort
rollback if a replacement or postcondition fails.
"""

from __future__ import annotations

import argparse
import copy
import json
import math
import os
import re
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Mapping, Sequence


IDENTITY_CONTRACT = "hardcore.formal_map_identity.v1"
NETWORK_CONTRACT = "hardcore.formal_map_portal_network.v1"
CONNECTION_POLICY = "map_connection_unified_bidirectional_v2"
PORTAL_CONTRACT = "unified_map_portal_endpoint_v1"
ARRIVAL_POLICY = "portal_arrival_guard_v2"
EXPECTED_MAP_COUNT = 67
EXPECTED_CONNECTION_COUNT = 66
EXPECTED_BIDIRECTIONAL_PAIRS = 51
EXPECTED_ONE_WAY_SOURCES = 15
EXPECTED_ENDPOINT_COUNT = 132
EXPECTED_BIDIRECTIONAL_ENDPOINTS = 102
EXPECTED_ARRIVAL_ENDPOINTS = 15
SANDBOX_ID = "sandbox_64"
BICH_LEGACY_ID = "bich_province"
BICH_PORTAL_ID = "map_exit_000005"
BICH_PORTAL_TILE = [69.0, 72.0]
BICH_PORTAL_NAME = "毒蛇山谷"

FORBIDDEN_PORTAL_WORDS = ("进入", "前往", "返回", "进去", "只可进入")
_PORTAL_ID_RE = re.compile(r"^map_exit_[0-9]{6}$")

# Fields owned by this normalizer.  Unknown visual/link fields deliberately
# remain untouched so a promotion cannot discard authored asset references.
_CONNECTION_FIELDS = (
    "connection_policy_id",
    "portal_contract_id",
    "portal_role",
    "semantic_role",
    "connection_mode",
    "one_way",
    "arrival_only",
    "arrival_reentry_policy_id",
    "arrival_locks_current_portal",
    "requires_leave_before_retrigger",
    "return_minimum_seconds",
    "return_unlock_distance_tiles",
    "return_requires_fresh_activation",
    "travel_request_single_flight",
    "trigger_on_enter",
    "blocks_movement",
    "runtime_export",
    "kind",
    "exit_id",
    "semantic_id",
    "target_configured",
    "target_map_id",
    "target_map_key",
    "target_portal_id",
    "target_entrance_id",
    "target_tile",
    "official_connection_id",
    "connection_pair_id",
    "connection_direction",
    "source_map_key",
    "reciprocal_exit_id",
    "reciprocal_map_key",
    "explicit_one_way_reason",
    "exit_policy",
)


class NormalizationError(ValueError):
    """An expected fail-closed input, plan, or postcondition error."""


@dataclass(frozen=True)
class IdentityRow:
    formal_map_id: str
    formal_runtime_map_id: int
    legacy_map_id: str
    legacy_runtime_map_id: int

    def selected_map_id(self, mode: str) -> str:
        return self.legacy_map_id if mode == "legacy" else self.formal_map_id

    def selected_runtime_map_id(self, mode: str) -> int:
        return (
            self.legacy_runtime_map_id
            if mode == "legacy"
            else self.formal_runtime_map_id
        )


@dataclass(frozen=True)
class EndpointRef:
    map_id: str
    portal_id: str


@dataclass(frozen=True)
class ConnectionRef:
    mode: str
    source: EndpointRef
    target: EndpointRef
    pair_id: str = ""


@dataclass
class NormalizationPlan:
    mode: str
    workspace_root: Path
    identity_path: Path
    network_path: Path
    rows: tuple[IdentityRow, ...]
    documents_before: dict[str, dict[str, Any]]
    documents_after: dict[str, dict[str, Any]]
    paths: dict[str, Path]
    raw_before: dict[str, bytes]
    connections: tuple[ConnectionRef, ...]
    changed_files: tuple[str, ...]
    changes: tuple[dict[str, Any], ...]
    validation: dict[str, Any]


def _fail(message: str) -> None:
    raise NormalizationError(message)


def _reject_json_constant(value: str) -> None:
    raise NormalizationError(f"non-finite-json-number:{value}")


def _resolve_existing(path: Path, label: str) -> Path:
    candidate = Path(path).expanduser()
    if not candidate.is_absolute():
        candidate = Path.cwd() / candidate
    try:
        resolved = candidate.resolve(strict=True)
    except OSError as exc:
        _fail(f"cannot-resolve-{label}:{candidate}:{exc}")
    return resolved


def _load_json(path: Path, label: str) -> tuple[dict[str, Any], bytes]:
    path = _resolve_existing(path, label)
    if not path.is_file():
        _fail(f"missing-{label}:{path}")
    try:
        raw = path.read_bytes()
        # BOM is accepted for compatibility with editor exports.  All newly
        # staged documents are written as normal UTF-8 without a BOM.
        value = json.loads(
            raw.decode("utf-8-sig"),
            parse_constant=_reject_json_constant,
        )
    except (OSError, UnicodeDecodeError, json.JSONDecodeError, NormalizationError) as exc:
        _fail(f"invalid-{label}:{path}:{exc}")
    if not isinstance(value, dict):
        _fail(f"{label}-must-be-object:{path}")
    return value, raw


def _as_int(value: Any, label: str, *, positive: bool = False) -> int:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        _fail(f"{label}-must-be-integer")
    try:
        number_as_float = float(value)
        number = int(value)
    except (OverflowError, ValueError):
        _fail(f"{label}-must-be-integer")
    if not math.isfinite(number_as_float):
        _fail(f"{label}-must-be-finite")
    if number_as_float != number:
        _fail(f"{label}-must-be-integer")
    if positive and number <= 0:
        _fail(f"{label}-must-be-positive")
    return number


def _as_nonempty_string(value: Any, label: str) -> str:
    if not isinstance(value, str) or not value.strip():
        _fail(f"{label}-must-be-nonempty-string")
    return value.strip()


def _safe_id(value: Any, label: str) -> str:
    text = _as_nonempty_string(value, label)
    if text in {".", ".."} or "/" in text or "\\" in text:
        _fail(f"{label}-path-invalid:{text}")
    return text


def load_identity_registry(path: Path) -> tuple[dict[str, Any], tuple[IdentityRow, ...], bytes]:
    registry, raw = _load_json(path, "identity-registry")
    if registry.get("contract_id") != IDENTITY_CONTRACT:
        _fail("identity-registry-contract-mismatch")
    declared = _as_int(registry.get("formal_map_count"), "identity-registry.formal_map_count")
    if declared != EXPECTED_MAP_COUNT:
        _fail(
            f"identity-registry-formal-map-count:{declared}:expected={EXPECTED_MAP_COUNT}"
        )
    entries = registry.get("maps")
    if not isinstance(entries, list) or len(entries) != EXPECTED_MAP_COUNT:
        _fail("identity-registry-maps-count")
    rows: list[IdentityRow] = []
    seen_formal: set[str] = set()
    seen_legacy: set[str] = set()
    seen_formal_runtime: set[int] = set()
    for index, item in enumerate(entries):
        if not isinstance(item, dict):
            _fail(f"identity-registry-entry-not-object:{index}")
        formal = _safe_id(item.get("map_id"), f"identity[{index}].map_id")
        legacy = _safe_id(item.get("legacy_map_id"), f"identity[{index}].legacy_map_id")
        formal_runtime = _as_int(
            item.get("runtime_map_id"),
            f"identity[{formal}].runtime_map_id",
            positive=True,
        )
        legacy_runtime = _as_int(
            item.get("legacy_runtime_map_id"),
            f"identity[{legacy}].legacy_runtime_map_id",
            positive=True,
        )
        if formal in seen_formal or legacy in seen_legacy:
            _fail(f"identity-registry-duplicate-map-id:{formal}:{legacy}")
        # Legacy runtime IDs are intentionally not required to be unique: the
        # historical source set reuses IDs for authored aliases (for example
        # 990100).  Formal runtime IDs remain the unique authoritative IDs.
        if formal_runtime in seen_formal_runtime:
            _fail(f"identity-registry-duplicate-runtime-id:{formal}:{legacy}")
        # The display name is part of the identity contract even though this
        # tool intentionally does not rewrite document-level display names.
        _as_nonempty_string(item.get("display_name"), f"identity[{formal}].display_name")
        seen_formal.add(formal)
        seen_legacy.add(legacy)
        seen_formal_runtime.add(formal_runtime)
        rows.append(IdentityRow(formal, formal_runtime, legacy, legacy_runtime))
    return registry, tuple(rows), raw


def _formal_ref(raw_map: Any, raw_portal: Any, label: str) -> EndpointRef:
    map_id = _safe_id(raw_map, f"{label}.map_id")
    portal_id = _safe_id(raw_portal, f"{label}.portal_id")
    if not _PORTAL_ID_RE.fullmatch(portal_id):
        _fail(f"{label}.portal_id-invalid:{portal_id}")
    return EndpointRef(map_id, portal_id)


def load_portal_network(
    path: Path,
    rows: Sequence[IdentityRow],
) -> tuple[dict[str, Any], tuple[ConnectionRef, ...], dict[tuple[str, str], str], bytes]:
    network, raw = _load_json(path, "portal-network")
    if network.get("contract_id") != NETWORK_CONTRACT:
        _fail("portal-network-contract-mismatch")
    if network.get("identity_contract_id") != IDENTITY_CONTRACT:
        _fail("portal-network-identity-contract-mismatch")
    if _as_int(network.get("formal_map_count"), "portal-network.formal_map_count") != EXPECTED_MAP_COUNT:
        _fail("portal-network-formal-map-count")
    if _as_int(network.get("logical_connection_count"), "portal-network.logical_connection_count") != EXPECTED_CONNECTION_COUNT:
        _fail("portal-network-logical-connection-count")
    if _as_int(network.get("formal_portal_endpoint_count"), "portal-network.formal_portal_endpoint_count") != EXPECTED_ENDPOINT_COUNT:
        _fail("portal-network-formal-endpoint-count")
    if _as_int(network.get("bidirectional_pair_count"), "portal-network.bidirectional_pair_count") != EXPECTED_BIDIRECTIONAL_PAIRS:
        _fail("portal-network-bidirectional-pair-count")
    if _as_int(network.get("one_way_connection_count"), "portal-network.one_way_connection_count") != EXPECTED_ONE_WAY_SOURCES:
        _fail("portal-network-one-way-count")

    formal_map_ids = {row.formal_map_id for row in rows}
    entries = network.get("connections")
    if not isinstance(entries, list) or len(entries) != EXPECTED_CONNECTION_COUNT:
        _fail("portal-network-connections-count")
    connections: list[ConnectionRef] = []
    used_endpoints: set[tuple[str, str]] = set()
    pair_ids: set[str] = set()

    def add_ref(ref: EndpointRef, label: str) -> None:
        if ref.map_id not in formal_map_ids:
            _fail(f"{label}.map_id-not-in-registry:{ref.map_id}")
        key = (ref.map_id, ref.portal_id)
        if key in used_endpoints:
            _fail(f"portal-network-endpoint-reused:{ref.map_id}:{ref.portal_id}")
        used_endpoints.add(key)

    for index, item in enumerate(entries):
        if not isinstance(item, dict):
            _fail(f"portal-network-connection-not-object:{index}")
        mode = _as_nonempty_string(item.get("mode"), f"connection[{index}].mode")
        if mode == "bidirectional":
            a = _formal_ref(item.get("a_map_id"), item.get("a_portal_id"), f"connection[{index}].a")
            b = _formal_ref(item.get("b_map_id"), item.get("b_portal_id"), f"connection[{index}].b")
            pair_id = _as_nonempty_string(item.get("pair_id"), f"connection[{index}].pair_id")
            if pair_id in pair_ids:
                _fail(f"portal-network-duplicate-pair-id:{pair_id}")
            pair_ids.add(pair_id)
            add_ref(a, f"connection[{index}].a")
            add_ref(b, f"connection[{index}].b")
            connections.append(ConnectionRef(mode, a, b, pair_id))
        elif mode == "one_way":
            source = _formal_ref(
                item.get("source_map_id"),
                item.get("source_portal_id"),
                f"connection[{index}].source",
            )
            target = _formal_ref(
                item.get("target_map_id"),
                item.get("target_portal_id"),
                f"connection[{index}].target",
            )
            add_ref(source, f"connection[{index}].source")
            add_ref(target, f"connection[{index}].target")
            connections.append(ConnectionRef(mode, source, target))
        else:
            _fail(f"portal-network-unsupported-mode:{mode}")
    if len(pair_ids) != EXPECTED_BIDIRECTIONAL_PAIRS:
        _fail(f"portal-network-pair-count:{len(pair_ids)}")
    if len(connections) != EXPECTED_CONNECTION_COUNT:
        _fail(f"portal-network-connection-count:{len(connections)}")
    if len(used_endpoints) != EXPECTED_ENDPOINT_COUNT:
        _fail(f"portal-network-endpoint-reference-count:{len(used_endpoints)}")

    override_items = network.get("display_label_overrides", [])
    if not isinstance(override_items, list):
        _fail("portal-network-display-label-overrides-not-array")
    overrides: dict[tuple[str, str], str] = {}
    for index, item in enumerate(override_items):
        if not isinstance(item, dict):
            _fail(f"portal-network-display-override-not-object:{index}")
        map_id = _safe_id(item.get("map_id"), f"display_override[{index}].map_id")
        portal_id = _safe_id(item.get("portal_id"), f"display_override[{index}].portal_id")
        display_name = _as_nonempty_string(
            item.get("display_name"), f"display_override[{index}].display_name"
        )
        if map_id not in formal_map_ids:
            _fail(f"display_override-map-not-in-registry:{map_id}")
        if not _PORTAL_ID_RE.fullmatch(portal_id):
            _fail(f"display_override-portal-id-invalid:{portal_id}")
        key = (map_id, portal_id)
        if key in overrides:
            _fail(f"display_override-duplicate:{map_id}:{portal_id}")
        target_map_id = _safe_id(item.get("target_map_id"), f"display_override[{index}].target_map_id")
        if target_map_id not in formal_map_ids:
            _fail(f"display_override-target-map-not-in-registry:{target_map_id}")
        ref = EndpointRef(map_id, portal_id)
        matching = [
            c
            for c in connections
            if c.source == ref or (c.mode == "bidirectional" and c.target == ref)
        ]
        if len(matching) != 1:
            _fail(f"display_override-source-not-in-network:{map_id}:{portal_id}")
        expected_target = (
            matching[0].target.map_id
            if matching[0].source == ref
            else matching[0].source.map_id
        )
        if expected_target != target_map_id:
            _fail(
                f"display_override-target-mismatch:{map_id}:{portal_id}:"
                f"{target_map_id}!={expected_target}"
            )
        overrides[key] = display_name
    return network, tuple(connections), overrides, raw


def _document_path(workspace_root: Path, map_id: str) -> Path:
    direct = workspace_root / map_id / f"{map_id}.editor.json"
    if direct.is_file():
        return direct
    # A small flat-root fallback is useful for isolated fixtures, while the
    # normal repository layout remains the only preferred location.
    flat = workspace_root / f"{map_id}.editor.json"
    if flat.is_file():
        return flat
    _fail(f"missing-workspace-document:{map_id}")
    raise AssertionError("unreachable")


def _without_portal_layers(document: Mapping[str, Any]) -> dict[str, Any]:
    projected = copy.deepcopy(dict(document))
    layers = projected.get("layers")
    if isinstance(layers, dict):
        layers.pop("map_exit_points", None)
        layers.pop("door_points", None)
    return projected


def _load_workspace_documents(
    workspace_root: Path,
    rows: Sequence[IdentityRow],
    mode: str,
) -> tuple[dict[str, dict[str, Any]], dict[str, Path], dict[str, bytes]]:
    workspace_root = _resolve_existing(workspace_root, "workspace-root")
    if not workspace_root.is_dir():
        _fail(f"workspace-root-not-directory:{workspace_root}")
    documents: dict[str, dict[str, Any]] = {}
    paths: dict[str, Path] = {}
    raw: dict[str, bytes] = {}
    resolved_paths: set[Path] = set()
    expected_ids = [row.selected_map_id(mode) for row in rows]
    if len(expected_ids) != EXPECTED_MAP_COUNT or len(set(expected_ids)) != EXPECTED_MAP_COUNT:
        _fail("selected-map-id-count")
    for map_id in expected_ids:
        path = _document_path(workspace_root, map_id)
        try:
            resolved = path.resolve(strict=True)
        except OSError as exc:
            _fail(f"cannot-resolve-workspace-document:{path}:{exc}")
        if resolved in resolved_paths:
            _fail(f"workspace-document-path-reused:{resolved}")
        resolved_paths.add(resolved)
        document, bytes_before = _load_json(path, f"workspace-document:{map_id}")
        if str(document.get("map_id", "")) != map_id:
            _fail(
                f"workspace-document-map-id-mismatch:{map_id}:"
                f"{document.get('map_id')!r}"
            )
        layers = document.get("layers")
        if not isinstance(layers, dict):
            _fail(f"workspace-document-layers-invalid:{map_id}")
        for layer_name in ("map_exit_points", "door_points"):
            layer = layers.get(layer_name, [])
            if not isinstance(layer, list):
                _fail(f"workspace-document-layer-invalid:{map_id}:{layer_name}")
            if any(not isinstance(item, dict) for item in layer):
                _fail(f"workspace-document-layer-entry-invalid:{map_id}:{layer_name}")
        documents[map_id] = document
        paths[map_id] = path
        raw[map_id] = bytes_before
    if len(documents) != EXPECTED_MAP_COUNT:
        _fail(f"workspace-document-count:{len(documents)}")

    # Authority is intentionally limited to the direct paths above.  A
    # workspace can contain delivery backups, snapshots, or the other
    # identity mode; none of those files are candidates for this run.  In
    # particular, do not recurse here: a backup with the same map_id must not
    # become a second authority document.
    return documents, paths, raw


def endpoint_id(endpoint: Mapping[str, Any]) -> str:
    semantic = endpoint.get("semantic_id")
    exit_id = endpoint.get("exit_id")
    if semantic not in (None, "") and exit_id not in (None, "") and str(semantic) != str(exit_id):
        _fail(f"endpoint-id-mismatch:{semantic!r}:{exit_id!r}")
    value = semantic if semantic not in (None, "") else exit_id
    if value in (None, ""):
        value = endpoint.get("door_id")
    return str(value or "")


def _tile(value: Any, label: str) -> list[Any]:
    if not isinstance(value, list) or len(value) != 2:
        _fail(f"{label}-must-be-two-element-array")
    for index, item in enumerate(value):
        if isinstance(item, bool) or not isinstance(item, (int, float)):
            _fail(f"{label}[{index}]-must-be-number")
        if not math.isfinite(float(item)):
            _fail(f"{label}[{index}]-must-be-finite")
    return copy.deepcopy(value)


def _tiles_equal(left: Any, right: Any) -> bool:
    try:
        return _tile(left, "left-tile") == _tile(right, "right-tile")
    except NormalizationError:
        return False


def _selected_maps(rows: Sequence[IdentityRow], mode: str) -> dict[str, IdentityRow]:
    return {row.selected_map_id(mode): row for row in rows}


def _find_identity(rows: Sequence[IdentityRow], legacy_map_id: str) -> IdentityRow:
    matches = [row for row in rows if row.legacy_map_id == legacy_map_id]
    if len(matches) != 1:
        _fail(f"identity-lookup-failed:{legacy_map_id}")
    return matches[0]


def _visual_source_fields(value: Mapping[str, Any]) -> dict[str, Any]:
    fields = (
        "tile",
        "linked_visual_instance_id",
        "portal_anchor_contract_id",
        "portal_visual_footprint_tiles",
        "portal_visual_origin_tile",
        "portal_trigger_policy_id",
    )
    return {field: copy.deepcopy(value.get(field)) for field in fields if field in value}


def _promote_bich_portal(
    documents: dict[str, dict[str, Any]],
    rows: Sequence[IdentityRow],
    mode: str,
) -> None:
    bich = _find_identity(rows, BICH_LEGACY_ID).selected_map_id(mode)
    document = documents[bich]
    layers = document["layers"]
    doors = layers.get("door_points", [])
    exits = layers.get("map_exit_points", [])
    candidates = [
        entry for entry in doors if str(entry.get("semantic_role", "")) == "map_portal"
    ]
    existing = [entry for entry in exits if endpoint_id(entry) == BICH_PORTAL_ID]
    if len(existing) > 1:
        _fail(f"bich-portal-duplicate:{bich}:{BICH_PORTAL_ID}")
    if len(candidates) > 1:
        _fail(f"bich-portal-door-count:{bich}:{len(candidates)}")
    if candidates:
        candidate = candidates[0]
        if not _tiles_equal(candidate.get("tile"), BICH_PORTAL_TILE):
            _fail(f"bich-portal-door-not-south:{candidate.get('tile')!r}")
        if existing:
            # A partially promoted document is safe only when the existing
            # endpoint still carries the exact visual/link source.  Remove the
            # duplicate door after proving equivalence; this keeps reruns
            # deterministic without silently discarding an unrelated door.
            if _visual_source_fields(existing[0]) != _visual_source_fields(candidate):
                _fail("bich-portal-existing-endpoint-does-not-match-door")
            layers["door_points"] = [entry for entry in doors if entry is not candidate]
            return
        promoted = copy.deepcopy(candidate)
        old_semantic = endpoint_id(candidate)
        promoted["legacy_door_id"] = str(candidate.get("door_id", old_semantic))
        promoted["legacy_semantic_id"] = old_semantic
        promoted.pop("door_id", None)
        promoted["semantic_id"] = BICH_PORTAL_ID
        promoted["exit_id"] = BICH_PORTAL_ID
        promoted["kind"] = "map_exit"
        promoted["semantic_role"] = "map_portal_endpoint"
        layers["door_points"] = [entry for entry in doors if entry is not candidate]
        layers.setdefault("map_exit_points", []).append(promoted)
        return
    if not existing:
        _fail(f"bich-portal-door-missing:{bich}")
    if not _tiles_equal(existing[0].get("tile"), BICH_PORTAL_TILE):
        _fail(f"bich-portal-existing-endpoint-not-south:{existing[0].get('tile')!r}")


def _normalize_display_name(value: Any) -> str:
    """Normalize a portal label without inventing a destination name.

    The operation is intentionally conservative: only leading navigation
    prompts, the explicit ``由 X 进入/进去`` form, the explicit one-way
    suffix, and a trailing ``出口`` are removed.  Existing qualified names
    therefore remain unchanged.
    """

    if not isinstance(value, str):
        _fail("portal-display-name-must-be-string")
    text = value.strip()
    while True:
        changed = False
        for prefix in ("进入", "前往", "返回"):
            if text.startswith(prefix):
                text = text[len(prefix) :].strip()
                changed = True
                break
        if not changed:
            break

    # Remove the explicit one-way annotation before stripping the destination
    # verb.  Both Chinese and ASCII comma/parenthesis variants occur in old
    # editor exports.
    # Repeat the suffix pass so combinations such as ``X进入出口`` and
    # ``X进入，单向只可进入出口`` are reduced completely while already clean
    # labels remain byte-for-byte stable.
    for _ in range(4):
        previous = text
        text = re.sub(
            r"(?:[，,;；、]\s*)?(?:(?:[（(]\s*)?单向(?:\s*[）)])?)?\s*只可进入\s*$",
            "",
            text,
        ).strip()
        if text.startswith("由"):
            text = text[1:].strip()
        text = re.sub(r"(?:进入|进去)\s*$", "", text).strip()
        text = re.sub(r"出口\s*$", "", text).strip()
        if text == previous:
            break
    if not text:
        _fail(f"portal-display-name-empty-after-normalization:{value!r}")
    return text


def _endpoint_index(documents: Mapping[str, Mapping[str, Any]]) -> dict[tuple[str, str], dict[str, Any]]:
    index: dict[tuple[str, str], dict[str, Any]] = {}
    for map_id, document in documents.items():
        layers = document.get("layers")
        if not isinstance(layers, dict):
            _fail(f"document-layers-invalid:{map_id}")
        doors = layers.get("door_points", [])
        for door in doors:
            if str(door.get("semantic_role", "")) == "map_portal":
                _fail(f"unpromoted-map-portal-door:{map_id}:{endpoint_id(door)}")
        exits = layers.get("map_exit_points", [])
        for endpoint in exits:
            portal_id = endpoint_id(endpoint)
            if not _PORTAL_ID_RE.fullmatch(portal_id):
                _fail(f"endpoint-id-invalid:{map_id}:{portal_id!r}")
            key = (map_id, portal_id)
            if key in index:
                _fail(f"endpoint-duplicate:{map_id}:{portal_id}")
            _tile(endpoint.get("tile"), f"endpoint-tile:{map_id}:{portal_id}")
            index[key] = endpoint
    return index


def _mode_ref(ref: EndpointRef, rows_by_formal: Mapping[str, IdentityRow], mode: str) -> EndpointRef:
    row = rows_by_formal.get(ref.map_id)
    if row is None:
        _fail(f"network-map-not-in-registry:{ref.map_id}")
    return EndpointRef(row.selected_map_id(mode), ref.portal_id)


def _clear_connection_fields(endpoint: dict[str, Any]) -> None:
    for field in _CONNECTION_FIELDS:
        endpoint.pop(field, None)


def _set_common(endpoint: dict[str, Any], portal_id: str, mode: str) -> None:
    endpoint["connection_policy_id"] = CONNECTION_POLICY
    endpoint["portal_contract_id"] = PORTAL_CONTRACT
    endpoint["arrival_reentry_policy_id"] = ARRIVAL_POLICY
    endpoint["arrival_locks_current_portal"] = True
    endpoint["requires_leave_before_retrigger"] = True
    endpoint["return_minimum_seconds"] = 3.0
    endpoint["return_unlock_distance_tiles"] = 1.5
    endpoint["return_requires_fresh_activation"] = True
    endpoint["travel_request_single_flight"] = True
    endpoint["blocks_movement"] = False
    endpoint["runtime_export"] = True
    endpoint["kind"] = "map_exit"
    endpoint["exit_id"] = portal_id
    endpoint["semantic_id"] = portal_id


def _set_bidirectional(
    source_map: str,
    source_id: str,
    target_map: str,
    target_id: str,
    source: dict[str, Any],
    target: dict[str, Any],
    pair_id: str,
    direction: str,
    runtime_by_map: Mapping[str, int],
) -> None:
    _clear_connection_fields(source)
    _set_common(source, source_id, "bidirectional")
    source["portal_role"] = "bidirectional_endpoint"
    source["semantic_role"] = "map_portal_endpoint"
    source["connection_mode"] = "bidirectional"
    source["one_way"] = False
    source["connection_direction"] = direction
    source["connection_pair_id"] = pair_id
    source["source_map_key"] = source_map
    source["target_configured"] = True
    source["target_map_key"] = target_map
    source["target_map_id"] = runtime_by_map[target_map]
    source["target_portal_id"] = target_id
    source["target_entrance_id"] = target_id
    source["target_tile"] = _tile(target.get("tile"), f"target-tile:{source_map}:{source_id}")
    source["official_connection_id"] = f"portal.{source_map}.{source_id}"
    source["reciprocal_exit_id"] = target_id
    source["reciprocal_map_key"] = target_map
    source["trigger_on_enter"] = True


def _set_one_way_source(
    source_map: str,
    source_id: str,
    target_map: str,
    target_id: str,
    source: dict[str, Any],
    target: dict[str, Any],
    runtime_by_map: Mapping[str, int],
) -> None:
    _clear_connection_fields(source)
    _set_common(source, source_id, "one_way")
    source["portal_role"] = "one_way_endpoint"
    source["semantic_role"] = "map_portal_endpoint"
    source["connection_mode"] = "one_way"
    source["one_way"] = True
    source["connection_direction"] = "forward"
    source["source_map_key"] = source_map
    source["target_configured"] = True
    source["target_map_key"] = target_map
    source["target_map_id"] = runtime_by_map[target_map]
    source["target_portal_id"] = target_id
    source["target_entrance_id"] = target_id
    source["target_tile"] = _tile(target.get("tile"), f"target-tile:{source_map}:{source_id}")
    source["official_connection_id"] = f"portal.{source_map}.{source_id}"
    source["explicit_one_way_reason"] = "terminal_dungeon_has_no_return_portal"
    source["trigger_on_enter"] = True


def _set_arrival(target_map: str, target_id: str, target: dict[str, Any]) -> None:
    _clear_connection_fields(target)
    _set_common(target, target_id, "arrival_only")
    target["portal_role"] = "arrival_only_endpoint"
    target["semantic_role"] = "map_portal_arrival_anchor"
    target["connection_mode"] = "arrival_only"
    target["one_way"] = False
    target["arrival_only"] = True
    target["trigger_on_enter"] = False
    target["target_configured"] = False
    target["target_map_id"] = -1
    target["explicit_one_way_reason"] = "terminal_dungeon_has_no_return_portal"
    target["exit_policy"] = "town_scroll_or_death_only"


def _apply_connection_metadata(
    documents: dict[str, dict[str, Any]],
    rows: Sequence[IdentityRow],
    connections: Sequence[ConnectionRef],
    overrides: Mapping[tuple[str, str], str],
    mode: str,
) -> None:
    rows_by_formal = {row.formal_map_id: row for row in rows}
    runtime_by_selected = {
        row.selected_map_id(mode): row.selected_runtime_map_id(mode) for row in rows
    }
    endpoint_index = _endpoint_index(documents)
    selected_connections = [
        ConnectionRef(
            connection.mode,
            _mode_ref(connection.source, rows_by_formal, mode),
            _mode_ref(connection.target, rows_by_formal, mode),
            connection.pair_id,
        )
        for connection in connections
    ]
    expected_refs = {
        (connection.source.map_id, connection.source.portal_id)
        for connection in selected_connections
    } | {
        (connection.target.map_id, connection.target.portal_id)
        for connection in selected_connections
    }
    actual_refs = set(endpoint_index)
    if actual_refs != expected_refs:
        missing = sorted(expected_refs - actual_refs)
        extra = sorted(actual_refs - expected_refs)
        _fail(f"network-endpoint-set-mismatch:missing={missing}:extra={extra}")

    for connection in selected_connections:
        source_key = (connection.source.map_id, connection.source.portal_id)
        target_key = (connection.target.map_id, connection.target.portal_id)
        source = endpoint_index[source_key]
        target = endpoint_index[target_key]
        if connection.mode == "bidirectional":
            _set_bidirectional(
                connection.source.map_id,
                connection.source.portal_id,
                connection.target.map_id,
                connection.target.portal_id,
                source,
                target,
                connection.pair_id,
                "forward",
                runtime_by_selected,
            )
            _set_bidirectional(
                connection.target.map_id,
                connection.target.portal_id,
                connection.source.map_id,
                connection.source.portal_id,
                target,
                source,
                connection.pair_id,
                "reverse",
                runtime_by_selected,
            )
        else:
            _set_one_way_source(
                connection.source.map_id,
                connection.source.portal_id,
                connection.target.map_id,
                connection.target.portal_id,
                source,
                target,
                runtime_by_selected,
            )
            _set_arrival(connection.target.map_id, connection.target.portal_id, target)

    for (formal_map_id, portal_id), display_name in overrides.items():
        selected_map = rows_by_formal[formal_map_id].selected_map_id(mode)
        key = (selected_map, portal_id)
        if key not in endpoint_index:
            _fail(f"display-override-endpoint-missing:{selected_map}:{portal_id}")
        endpoint_index[key]["display_name"] = _normalize_display_name(display_name)

    bich = _find_identity(rows, BICH_LEGACY_ID).selected_map_id(mode)
    bich_key = (bich, BICH_PORTAL_ID)
    if bich_key not in endpoint_index:
        _fail(f"bich-portal-endpoint-missing:{bich}:{BICH_PORTAL_ID}")
    endpoint_index[bich_key]["display_name"] = BICH_PORTAL_NAME

    # Every portal endpoint is player-facing portal metadata.  Do this last so
    # an old prefixed label cannot survive an override or a promotion.
    for key, endpoint in endpoint_index.items():
        if key == bich_key:
            continue
        endpoint["display_name"] = _normalize_display_name(endpoint.get("display_name"))


def _validate_final(
    documents: Mapping[str, Mapping[str, Any]],
    rows: Sequence[IdentityRow],
    connections: Sequence[ConnectionRef],
    overrides: Mapping[tuple[str, str], str],
    mode: str,
) -> dict[str, Any]:
    if len(documents) != EXPECTED_MAP_COUNT:
        _fail(f"final-document-count:{len(documents)}")
    selected_ids = {row.selected_map_id(mode) for row in rows}
    if set(documents) != selected_ids:
        _fail("final-document-identity-set-mismatch")
    index = _endpoint_index(documents)
    if len(index) != EXPECTED_ENDPOINT_COUNT:
        _fail(f"final-endpoint-count:{len(index)}")
    rows_by_formal = {row.formal_map_id: row for row in rows}
    runtime_by_selected = {
        row.selected_map_id(mode): row.selected_runtime_map_id(mode) for row in rows
    }
    refs: dict[tuple[str, str], tuple[ConnectionRef, bool]] = {}
    pair_ids: set[str] = set()
    for connection in connections:
        source = _mode_ref(connection.source, rows_by_formal, mode)
        target = _mode_ref(connection.target, rows_by_formal, mode)
        normalized = ConnectionRef(connection.mode, source, target, connection.pair_id)
        refs[(source.map_id, source.portal_id)] = (normalized, True)
        refs[(target.map_id, target.portal_id)] = (normalized, False)
        if connection.mode == "bidirectional":
            pair_ids.add(connection.pair_id)
    if set(refs) != set(index):
        _fail("final-network-endpoint-set-mismatch")
    bidirectional = one_way = arrival = 0
    for key, endpoint in index.items():
        map_id, portal_id = key
        connection, is_source = refs[key]
        mode_value = endpoint.get("connection_mode")
        if mode_value == "bidirectional":
            bidirectional += 1
        elif mode_value == "one_way":
            one_way += 1
        elif mode_value == "arrival_only":
            arrival += 1
        else:
            _fail(f"final-endpoint-unclassified:{map_id}:{portal_id}:{mode_value!r}")
        if endpoint.get("semantic_id") != portal_id or endpoint.get("exit_id") != portal_id:
            _fail(f"final-endpoint-id-fields:{map_id}:{portal_id}")
        _tile(endpoint.get("tile"), f"final-endpoint-tile:{map_id}:{portal_id}")
        name = endpoint.get("display_name")
        if not isinstance(name, str) or not name.strip():
            _fail(f"final-endpoint-display-name-missing:{map_id}:{portal_id}")
        if any(word in name for word in FORBIDDEN_PORTAL_WORDS):
            _fail(f"final-forbidden-portal-display-word:{map_id}:{portal_id}:{name}")
        if connection.mode == "bidirectional":
            if mode_value != "bidirectional":
                _fail(f"final-bidirectional-mode:{map_id}:{portal_id}")
            expected_target_ref = connection.target if is_source else connection.source
            target_key = (expected_target_ref.map_id, expected_target_ref.portal_id)
            target = index.get(target_key)
            if target is None:
                _fail(f"final-target-missing:{map_id}:{portal_id}")
            if endpoint.get("target_map_key") != expected_target_ref.map_id:
                _fail(f"final-target-map-key:{map_id}:{portal_id}")
            if _as_int(endpoint.get("target_map_id"), f"final-target-runtime:{map_id}:{portal_id}") != runtime_by_selected[expected_target_ref.map_id]:
                _fail(f"final-target-runtime:{map_id}:{portal_id}")
            if endpoint.get("target_portal_id") != expected_target_ref.portal_id:
                _fail(f"final-target-portal:{map_id}:{portal_id}")
            if endpoint.get("target_entrance_id") != expected_target_ref.portal_id:
                _fail(f"final-target-entrance:{map_id}:{portal_id}")
            if not _tiles_equal(endpoint.get("target_tile"), target.get("tile")):
                _fail(f"final-target-tile:{map_id}:{portal_id}")
            if endpoint.get("target_configured") is not True or endpoint.get("trigger_on_enter") is not True:
                _fail(f"final-active-contract:{map_id}:{portal_id}")
            if endpoint.get("one_way") is not False:
                _fail(f"final-bidirectional-one-way:{map_id}:{portal_id}")
            if endpoint.get("connection_pair_id") != connection.pair_id:
                _fail(f"final-pair-id:{map_id}:{portal_id}")
            if endpoint.get("reciprocal_map_key") != expected_target_ref.map_id or endpoint.get("reciprocal_exit_id") != expected_target_ref.portal_id:
                _fail(f"final-reciprocal-fields:{map_id}:{portal_id}")
            if target.get("target_map_key") != map_id or target.get("target_portal_id") != portal_id:
                _fail(f"final-reciprocal-target:{map_id}:{portal_id}")
            if target.get("connection_pair_id") != endpoint.get("connection_pair_id"):
                _fail(f"final-reciprocal-pair:{map_id}:{portal_id}")
        elif connection.mode == "one_way":
            if is_source:
                if mode_value != "one_way":
                    _fail(f"final-one-way-mode:{map_id}:{portal_id}")
                target_key = (connection.target.map_id, connection.target.portal_id)
                target = index.get(target_key)
                if target is None:
                    _fail(f"final-one-way-target-missing:{map_id}:{portal_id}")
                if endpoint.get("target_map_key") != connection.target.map_id or endpoint.get("target_portal_id") != connection.target.portal_id:
                    _fail(f"final-one-way-target:{map_id}:{portal_id}")
                if _as_int(endpoint.get("target_map_id"), f"final-one-way-runtime:{map_id}:{portal_id}") != runtime_by_selected[connection.target.map_id]:
                    _fail(f"final-one-way-runtime:{map_id}:{portal_id}")
                if not _tiles_equal(endpoint.get("target_tile"), target.get("tile")):
                    _fail(f"final-one-way-target-tile:{map_id}:{portal_id}")
                if endpoint.get("target_configured") is not True or endpoint.get("trigger_on_enter") is not True:
                    _fail(f"final-one-way-active-contract:{map_id}:{portal_id}")
                if endpoint.get("one_way") is not True:
                    _fail(f"final-one-way-flag:{map_id}:{portal_id}")
                if target.get("connection_mode") != "arrival_only":
                    _fail(f"final-one-way-arrival-mode:{map_id}:{portal_id}")
            else:
                if mode_value != "arrival_only":
                    _fail(f"final-arrival-mode:{map_id}:{portal_id}")
                if endpoint.get("trigger_on_enter") is not False or endpoint.get("target_configured") is not False:
                    _fail(f"final-arrival-trigger-contract:{map_id}:{portal_id}")
                if _as_int(endpoint.get("target_map_id"), f"final-arrival-runtime:{map_id}:{portal_id}") != -1:
                    _fail(f"final-arrival-runtime:{map_id}:{portal_id}")
                for field in (
                    "target_map_key",
                    "target_portal_id",
                    "target_entrance_id",
                    "target_tile",
                    "official_connection_id",
                    "source_map_key",
                    "connection_pair_id",
                    "connection_direction",
                    "reciprocal_map_key",
                    "reciprocal_exit_id",
                ):
                    if field in endpoint:
                        _fail(f"final-arrival-field-present:{map_id}:{portal_id}:{field}")
    if (bidirectional, one_way, arrival) != (
        EXPECTED_BIDIRECTIONAL_ENDPOINTS,
        EXPECTED_ONE_WAY_SOURCES,
        EXPECTED_ARRIVAL_ENDPOINTS,
    ):
        _fail(f"final-portal-counts:{bidirectional}:{one_way}:{arrival}")
    if len(pair_ids) != EXPECTED_BIDIRECTIONAL_PAIRS:
        _fail(f"final-pair-count:{len(pair_ids)}")
    return {
        "formal_docs": EXPECTED_MAP_COUNT,
        "portal_endpoints": EXPECTED_ENDPOINT_COUNT,
        "bidirectional_pairs": EXPECTED_BIDIRECTIONAL_PAIRS,
        "bidirectional_endpoints": bidirectional,
        "one_way_sources": one_way,
        "arrival_anchors": arrival,
    }


def _changed_portal_summary(
    before: Mapping[str, Any], after: Mapping[str, Any], path: Path, workspace_root: Path
) -> dict[str, Any] | None:
    before_layers = before.get("layers", {})
    after_layers = after.get("layers", {})
    if not isinstance(before_layers, dict) or not isinstance(after_layers, dict):
        _fail(f"changed-summary-layers-invalid:{path}")
    changed_layers = [
        layer
        for layer in ("map_exit_points", "door_points")
        if before_layers.get(layer, []) != after_layers.get(layer, [])
    ]
    if not changed_layers:
        return None
    before_ids = {
        endpoint_id(item): item for item in before_layers.get("map_exit_points", [])
    }
    after_ids = {
        endpoint_id(item): item for item in after_layers.get("map_exit_points", [])
    }
    changed_ids = sorted(
        key for key in set(before_ids) | set(after_ids) if before_ids.get(key) != after_ids.get(key)
    )
    return {
        "path": path.relative_to(workspace_root).as_posix(),
        "layers": changed_layers,
        "portal_ids": changed_ids,
    }


def build_plan(
    workspace_root: Path,
    identity_registry: Path,
    portal_network: Path,
    identity_mode: str,
) -> NormalizationPlan:
    if identity_mode not in {"legacy", "formal"}:
        _fail(f"identity-mode-invalid:{identity_mode}")
    workspace_root = _resolve_existing(workspace_root, "workspace-root")
    identity_path = _resolve_existing(identity_registry, "identity-registry")
    network_path = _resolve_existing(portal_network, "portal-network")
    _, rows, _ = load_identity_registry(identity_path)
    _, connections, overrides, _ = load_portal_network(network_path, rows)
    documents_before, paths, raw_before = _load_workspace_documents(
        workspace_root, rows, identity_mode
    )
    documents_after = copy.deepcopy(documents_before)
    _promote_bich_portal(documents_after, rows, identity_mode)
    _apply_connection_metadata(
        documents_after, rows, connections, overrides, identity_mode
    )
    for map_id in sorted(documents_before):
        if _without_portal_layers(documents_before[map_id]) != _without_portal_layers(documents_after[map_id]):
            _fail(f"nonportal-freeze-violated:{map_id}")
    validation = _validate_final(
        documents_after, rows, connections, overrides, identity_mode
    )
    changes: list[dict[str, Any]] = []
    for map_id in sorted(documents_before):
        summary = _changed_portal_summary(
            documents_before[map_id],
            documents_after[map_id],
            paths[map_id],
            workspace_root,
        )
        if summary is not None:
            changes.append(summary)
    changed_files = tuple(item["path"] for item in changes)
    return NormalizationPlan(
        identity_mode,
        workspace_root,
        identity_path,
        network_path,
        tuple(rows),
        documents_before,
        documents_after,
        paths,
        raw_before,
        tuple(connections),
        changed_files,
        tuple(changes),
        validation,
    )


def _encode_document(document: Mapping[str, Any]) -> bytes:
    try:
        return (
            json.dumps(
                document,
                ensure_ascii=False,
                indent=2,
                sort_keys=True,
                allow_nan=False,
            )
            + "\n"
        ).encode("utf-8")
    except (TypeError, ValueError) as exc:
        _fail(f"document-encode-failed:{exc}")
    raise AssertionError("unreachable")


def _stage_bytes(path: Path, payload: bytes) -> Path:
    try:
        fd, temp_name = tempfile.mkstemp(
            prefix=f".{path.name}.portal-normalize.",
            suffix=".tmp",
            dir=str(path.parent),
        )
        with os.fdopen(fd, "wb") as handle:
            handle.write(payload)
            handle.flush()
            os.fsync(handle.fileno())
        return Path(temp_name)
    except OSError as exc:
        _fail(f"stage-write-failed:{path}:{exc}")
    raise AssertionError("unreachable")


def _restore_bytes(path: Path, payload: bytes) -> None:
    temp = _stage_bytes(path, payload)
    try:
        os.replace(temp, path)
    finally:
        try:
            temp.unlink(missing_ok=True)
        except OSError:
            pass


def _apply_atomic(plan: NormalizationPlan) -> None:
    staged: list[tuple[Path, Path, bytes]] = []
    replaced: list[tuple[Path, bytes]] = []
    try:
        # Prepare every replacement before touching any source file.
        for map_id in sorted(plan.documents_before):
            before = plan.documents_before[map_id]
            after = plan.documents_after[map_id]
            if before == after:
                continue
            path = plan.paths[map_id]
            temp = _stage_bytes(path, _encode_document(after))
            staged.append((path, temp, plan.raw_before[map_id]))
        for path, temp, original in staged:
            os.replace(temp, path)
            replaced.append((path, original))
        for _, temp, _ in staged:
            try:
                temp.unlink(missing_ok=True)
            except OSError:
                pass
    except Exception as exc:
        for _, temp, _ in staged:
            try:
                temp.unlink(missing_ok=True)
            except OSError:
                pass
        rollback_errors: list[str] = []
        for path, original in reversed(replaced):
            try:
                _restore_bytes(path, original)
            except Exception as rollback_exc:  # pragma: no cover - OS failure path
                rollback_errors.append(f"{path}:{rollback_exc}")
        detail = f"atomic-apply-failed:{exc}"
        if rollback_errors:
            detail += ":rollback-failed=" + ",".join(rollback_errors)
        _fail(detail)


def _postcondition(plan: NormalizationPlan) -> None:
    documents, _, _ = _load_workspace_documents(
        plan.workspace_root, plan.rows, plan.mode
    )
    # Re-load and validate through the same identity/network plan.  A second
    # in-memory plan would stage nothing but gives the strongest postcondition
    # check without writing a byte.
    _, connections, overrides, _ = load_portal_network(plan.network_path, plan.rows)
    for map_id, document in documents.items():
        if _without_portal_layers(document) != _without_portal_layers(plan.documents_before[map_id]):
            _fail(f"postcondition-nonportal-freeze:{map_id}")
        if document != plan.documents_after[map_id]:
            _fail(f"postcondition-document-mismatch:{map_id}")
    _validate_final(documents, plan.rows, connections, overrides, plan.mode)


def run(
    workspace_root: Path,
    identity_registry: Path,
    portal_network: Path,
    identity_mode: str,
    *,
    apply: bool = False,
) -> dict[str, Any]:
    plan = build_plan(workspace_root, identity_registry, portal_network, identity_mode)
    result: dict[str, Any] = {
        "ok": True,
        "identity_mode": identity_mode,
        "dry_run": not apply,
        "applied": False,
        **plan.validation,
        "changed_files": list(plan.changed_files),
        "changes": list(plan.changes),
        "nonportal_unchanged": True,
    }
    if not apply:
        return result
    _apply_atomic(plan)
    try:
        _postcondition(plan)
    except Exception as exc:
        rollback_errors: list[str] = []
        for map_id in sorted(plan.documents_before):
            if plan.documents_before[map_id] == plan.documents_after[map_id]:
                continue
            try:
                _restore_bytes(plan.paths[map_id], plan.raw_before[map_id])
            except Exception as rollback_exc:  # pragma: no cover - OS failure path
                rollback_errors.append(f"{plan.paths[map_id]}:{rollback_exc}")
        detail = f"postcondition-failed:{exc}"
        if rollback_errors:
            detail += ":rollback-failed=" + ",".join(rollback_errors)
        _fail(detail)
    result["dry_run"] = False
    result["applied"] = True
    return result


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--workspace-root", type=Path, required=True)
    parser.add_argument("--identity-registry", type=Path, required=True)
    parser.add_argument("--portal-network", type=Path, required=True)
    parser.add_argument(
        "--identity-mode",
        choices=("legacy", "formal"),
        required=True,
    )
    parser.add_argument("--apply", action="store_true", help="write the validated plan")
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="validate and print the change list without writing (default)",
    )
    args = parser.parse_args(argv)
    if args.apply and args.dry_run:
        parser.error("--apply and --dry-run are mutually exclusive")
    try:
        result = run(
            args.workspace_root,
            args.identity_registry,
            args.portal_network,
            args.identity_mode,
            apply=bool(args.apply),
        )
    except NormalizationError as exc:
        print(f"MAP_PORTAL_NORMALIZATION_FAILED: {exc}", file=sys.stderr)
        return 2
    print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
