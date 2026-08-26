#!/usr/bin/env python3
"""Plan one fail-closed pilot for automatic map monster placement.

The planner never edits an editor document and never builds or publishes a
runtime.  It consumes only AUTO_PLACEMENT_ALLOWED authority records with one
stable monster_id, reconstructs current editor walkability, and emits a safe
writer compatible two-layer placement input plus detailed audit evidence.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import math
import os
import shutil
import sys
import tempfile
from collections import Counter, deque
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable, Mapping, Sequence


CONTRACT_ID = "hardcore.map_monster_auto_placement_plan.v1"
MANIFEST_ID = "map_monster_placement_plans_v1"
AUTHORITY_CONTRACT = "hardcore.map_monster_placement_authority.v2"
IDENTITY_CONTRACT = "hardcore.formal_map_identity.v1"
ALLOWED_STATUS = "AUTO_PLACEMENT_ALLOWED"
TRANSITION_DEBT = frozenset(
    {
        "bich_province",
        "wooma_forest",
        "wooma_temple_1",
        "wooma_temple_2",
        "wooma_temple_3",
    }
)
PORTAL_LAYERS = ("door_points", "map_exit_points", "map_entrance_points")
INSTANCE_LAYERS = (
    "terrain_base",
    "terrain_front",
    "object_base",
    "object_front",
    "interactables",
)
TARGET_LAYERS = ("monster_spawn", "boss_spawn")
PORTAL_BUFFER = 3
RESPAWN_BUFFER = 3
NPC_BUFFER = 2
SAFE_BUFFER = 1
EDGE_BUFFER = 1
MIN_COMPONENT_SIZE = 9
MIN_SPAWN_MANHATTAN = 4


class PlannerError(ValueError):
    """Expected fail-closed planner rejection."""


def _error(message: str) -> None:
    raise PlannerError(message)


def canonical_bytes(value: Any) -> bytes:
    try:
        return (
            json.dumps(
                value,
                ensure_ascii=False,
                sort_keys=True,
                indent=2,
                allow_nan=False,
            )
            + "\n"
        ).encode("utf-8")
    except (TypeError, ValueError) as exc:
        _error(f"non_canonical_json:{exc}")
    raise AssertionError("unreachable")


def sha256_bytes(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def sha256_file(path: Path) -> str:
    try:
        return sha256_bytes(path.read_bytes())
    except OSError as exc:
        _error(f"unreadable_file:{path.name}:{exc}")
    raise AssertionError("unreachable")


def _parse_json(path: Path, raw: bytes) -> dict[str, Any]:
    try:
        value = json.loads(raw.decode("utf-8"), parse_constant=lambda x: (_ for _ in ()).throw(ValueError(x)))
    except (UnicodeError, ValueError, json.JSONDecodeError) as exc:
        _error(f"invalid_json:{path.name}:{exc}")
    if not isinstance(value, dict):
        _error(f"json_root_not_object:{path.name}")
    return value


def _load(path: Path) -> tuple[dict[str, Any], bytes]:
    if not path.is_file():
        _error(f"missing_file:{path.name}")
    try:
        raw = path.read_bytes()
    except OSError as exc:
        _error(f"unreadable_file:{path.name}:{exc}")
    return _parse_json(path, raw), raw


def _inside(path: Path, root: Path) -> bool:
    try:
        path.resolve().relative_to(root.resolve())
        return True
    except ValueError:
        return False


def _repo_root(path: Path) -> Path:
    for parent in (path.resolve(), *path.resolve().parents):
        if (parent / ".git").exists():
            return parent
    _error(f"repo_root_not_found:{path.name}")
    raise AssertionError("unreachable")


def _repo_key(path: Path, repo: Path) -> str:
    if not _inside(path, repo):
        _error(f"tracked_input_outside_repo:{path.name}")
    return "repo:" + path.resolve().relative_to(repo.resolve()).as_posix()


def _source_key(path: Path, source_root: Path) -> str:
    if not _inside(path, source_root):
        _error(f"source_input_outside_root:{path.name}")
    return "source_editor_root:" + path.resolve().relative_to(source_root.resolve()).as_posix()


def _number(value: Any, label: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        _error(f"{label}_not_number")
    result = float(value)
    if not math.isfinite(result):
        _error(f"{label}_not_finite")
    return result


def _integer(value: Any, label: str, *, positive: bool = False) -> int:
    result = _number(value, label)
    if not result.is_integer() or (positive and result <= 0):
        _error(f"{label}_not_valid_integer")
    return int(result)


def _pair(value: Any, label: str, *, positive: bool = False) -> tuple[int, int]:
    if not isinstance(value, list) or len(value) != 2:
        _error(f"{label}_not_pair")
    result = (_integer(value[0], f"{label}[0]"), _integer(value[1], f"{label}[1]"))
    if positive and (result[0] <= 0 or result[1] <= 0):
        _error(f"{label}_not_positive")
    return result


def _tile(entry: Mapping[str, Any], size: tuple[int, int], label: str) -> tuple[int, int]:
    result = _pair(entry.get("tile"), f"{label}.tile")
    if not (0 <= result[0] < size[0] and 0 <= result[1] < size[1]):
        _error(f"{label}.tile_out_of_bounds:{result}")
    return result


def _layers(document: Mapping[str, Any]) -> Mapping[str, Any]:
    layers = document.get("layers")
    if not isinstance(layers, dict):
        _error("document_layers_missing")
    return layers


def _entries(document: Mapping[str, Any], layer: str) -> list[Any]:
    value = _layers(document).get(layer, [])
    if not isinstance(value, list):
        _error(f"layer_not_array:{layer}")
    return value


def _rect_cells(
    origin: tuple[int, int], extent: tuple[int, int], size: tuple[int, int]
) -> set[tuple[int, int]]:
    return {
        (x, y)
        for y in range(origin[1], origin[1] + extent[1])
        for x in range(origin[0], origin[0] + extent[0])
        if 0 <= x < size[0] and 0 <= y < size[1]
    }


def _point_in_polygon(point: tuple[float, float], points: Sequence[tuple[float, float]]) -> bool:
    inside = False
    previous = points[-1]
    for current in points:
        x1, y1 = previous
        x2, y2 = current
        if (y1 > point[1]) != (y2 > point[1]):
            crossing = (x2 - x1) * (point[1] - y1) / (y2 - y1) + x1
            if point[0] < crossing:
                inside = not inside
        previous = current
    return inside


def _manual_shape_cells(
    entry: Mapping[str, Any], size: tuple[int, int], label: str
) -> set[tuple[int, int]]:
    shape = entry.get("shape")
    data = entry.get("data")
    if not isinstance(shape, str) or not isinstance(data, dict):
        _error(f"{label}_geometry_unreadable")
    if shape == "rect":
        raw = data.get("rect")
        if not isinstance(raw, list) or len(raw) != 4:
            _error(f"{label}_rect_invalid")
        origin = (_integer(raw[0], label), _integer(raw[1], label))
        extent = (_integer(raw[2], label, positive=True), _integer(raw[3], label, positive=True))
        return _rect_cells(origin, extent, size)
    if shape == "ellipse":
        raw = data.get("rect")
        if not isinstance(raw, list) or len(raw) != 4:
            _error(f"{label}_ellipse_invalid")
        ox, oy = _integer(raw[0], label), _integer(raw[1], label)
        width, height = _integer(raw[2], label, positive=True), _integer(raw[3], label, positive=True)
        center = (ox + width * 0.5, oy + height * 0.5)
        result: set[tuple[int, int]] = set()
        for y in range(oy, oy + height):
            for x in range(ox, ox + width):
                qx = ((x + 0.5) - center[0]) / (width * 0.5)
                qy = ((y + 0.5) - center[1]) / (height * 0.5)
                if qx * qx + qy * qy <= 1.0 and 0 <= x < size[0] and 0 <= y < size[1]:
                    result.add((x, y))
        return result
    if shape == "polygon":
        raw_points = data.get("points")
        if not isinstance(raw_points, list) or len(raw_points) < 3:
            _error(f"{label}_polygon_invalid")
        points = [tuple(map(float, _pair(point, f"{label}.point"))) for point in raw_points]
        return {
            (x, y)
            for y in range(size[1])
            for x in range(size[0])
            if _point_in_polygon((x + 0.5, y + 0.5), points)
        }
    _error(f"{label}_shape_unsupported:{shape}")
    raise AssertionError("unreachable")


def _all_instances(document: Mapping[str, Any]) -> Iterable[tuple[str, int, Mapping[str, Any]]]:
    for layer, values in _layers(document).items():
        if not isinstance(values, list):
            _error(f"layer_not_array:{layer}")
        for index, value in enumerate(values):
            if isinstance(value, dict) and "instance_id" in value:
                yield layer, index, value


def _scaled_wall_cells(
    instance: Mapping[str, Any], size: tuple[int, int], label: str
) -> set[tuple[int, int]]:
    origin = _tile(instance, size, label)
    current = _pair(instance.get("footprint_tiles", [1, 1]), f"{label}.footprint", positive=True)
    base = _pair(
        instance.get(
            "instance_base_footprint_tiles",
            instance.get("base_footprint_tiles", instance.get("footprint_tiles", [1, 1])),
        ),
        f"{label}.base_footprint",
        positive=True,
    )
    raw_cells = instance.get("collision_cells")
    if not isinstance(raw_cells, list):
        _error(f"{label}.collision_cells_not_array")
    source_cells = {_pair(cell, f"{label}.collision_cell") for cell in raw_cells}
    result: set[tuple[int, int]] = set()
    for y in range(current[1]):
        for x in range(current[0]):
            sx = min(base[0] - 1, max(0, math.floor((x + 0.5) * base[0] / current[0])))
            sy = min(base[1] - 1, max(0, math.floor((y + 0.5) * base[1] / current[1])))
            tile = (origin[0] + x, origin[1] + y)
            if (sx, sy) in source_cells and 0 <= tile[0] < size[0] and 0 <= tile[1] < size[1]:
                result.add(tile)
    return result


def build_collision(document: Mapping[str, Any]) -> dict[str, Any]:
    design = document.get("design")
    if not isinstance(design, dict):
        _error("document_design_missing")
    size = _pair(design.get("design_size"), "design_size", positive=True)
    blocked: set[tuple[int, int]] = set()
    source_rows: list[dict[str, Any]] = []
    solid_cells: set[tuple[int, int]] = set()
    for layer, index, instance in _all_instances(document):
        label = f"{layer}[{index}]"
        policy = instance.get("collision_policy", "none")
        if not isinstance(policy, str):
            _error(f"{label}.collision_policy_unreadable")
        if policy == "none" or instance.get("map_collision_override", "default") == "disabled":
            continue
        raw_cells = instance.get("collision_cells", [])
        if policy == "wall_cells_generated" and isinstance(raw_cells, list) and raw_cells:
            cells = _scaled_wall_cells(instance, size, label)
            shape = "explicit_scaled_cells"
        else:
            origin = _tile(instance, size, label)
            visual = _pair(instance.get("footprint_tiles", [1, 1]), f"{label}.footprint", positive=True)
            collision = _pair(
                instance.get("collision_footprint_tiles", visual),
                f"{label}.collision_footprint",
            )
            if collision[0] <= 0 or collision[1] <= 0:
                continue
            adjusted = (
                origin[0] + max(0, (visual[0] - collision[0]) // 2),
                origin[1] + max(0, (visual[1] - collision[1]) // 2),
            )
            cells = _rect_cells(adjusted, collision, size)
            shape = "collision_footprint"
        blocked.update(cells)
        solid_cells.update(cells)
        source_rows.append(
            {
                "kind": "instance",
                "layer": layer,
                "instance_id": str(instance.get("instance_id", "")),
                "collision_policy": policy,
                "shape": shape,
                "blocked_cell_count": len(cells),
            }
        )
    for index, value in enumerate(_entries(document, "collision")):
        if not isinstance(value, dict):
            _error(f"collision[{index}]_not_object")
        if value.get("blocks_monster", True) is False:
            continue
        cells = _manual_shape_cells(value, size, f"collision[{index}]")
        blocked.update(cells)
        source_rows.append(
            {
                "kind": "manual",
                "collision_id": str(value.get("collision_id", "")),
                "shape": str(value.get("shape", "")),
                "blocked_cell_count": len(cells),
            }
        )
    erased: set[tuple[int, int]] = set()
    for index, value in enumerate(_entries(document, "collision_erase")):
        if not isinstance(value, dict):
            _error(f"collision_erase[{index}]_not_object")
        erased.add(_tile(value, size, f"collision_erase[{index}]"))
    blocked.difference_update(erased)
    solid_cells.difference_update(erased)
    return {
        "size": size,
        "blocked": blocked,
        "solid": solid_cells,
        "erased": erased,
        "sources": source_rows,
    }


def _circle_cells(
    center: tuple[int, int], radius: float, size: tuple[int, int]
) -> set[tuple[int, int]]:
    result: set[tuple[int, int]] = set()
    for y in range(max(0, math.floor(center[1] - radius)), min(size[1], math.ceil(center[1] + radius + 1))):
        for x in range(max(0, math.floor(center[0] - radius)), min(size[0], math.ceil(center[0] + radius + 1))):
            if math.hypot(x - center[0], y - center[1]) <= radius + 1e-9:
                result.add((x, y))
    return result


def _safe_cells(entry: Mapping[str, Any], size: tuple[int, int], label: str) -> set[tuple[int, int]]:
    center = _tile(entry, size, label)
    shape = str(entry.get("shape", "circle"))
    if shape == "circle":
        radius = _number(entry.get("radius_gu", entry.get("radius_tiles", 0)), f"{label}.radius")
        if radius < 0:
            _error(f"{label}.radius_negative")
        return _circle_cells(center, radius, size)
    if shape == "polygon":
        raw = entry.get("polygon_ground_gu", entry.get("polygon_tiles"))
        if not isinstance(raw, list) or len(raw) < 3:
            _error(f"{label}.polygon_invalid")
        points = [tuple(map(float, _pair(point, f"{label}.point"))) for point in raw]
        return {
            (x, y)
            for y in range(size[1])
            for x in range(size[0])
            if _point_in_polygon((x + 0.5, y + 0.5), points)
        }
    _error(f"{label}.safe_shape_unsupported:{shape}")
    raise AssertionError("unreachable")


def _buffer(cells: Iterable[tuple[int, int]], radius: int, size: tuple[int, int]) -> set[tuple[int, int]]:
    return {
        (x + dx, y + dy)
        for x, y in cells
        for dy in range(-radius, radius + 1)
        for dx in range(-radius, radius + 1)
        if 0 <= x + dx < size[0] and 0 <= y + dy < size[1]
    }


def build_reservations(document: Mapping[str, Any], collision: Mapping[str, Any]) -> dict[str, Any]:
    size = collision["size"]
    portal_tiles: set[tuple[int, int]] = set()
    portal_visual: set[tuple[int, int]] = set()
    portal_counts: dict[str, int] = {}
    for layer in PORTAL_LAYERS:
        values = _entries(document, layer)
        portal_counts[layer] = len(values)
        for index, value in enumerate(values):
            if not isinstance(value, dict):
                _error(f"{layer}[{index}]_not_object")
            portal_tiles.add(_tile(value, size, f"{layer}[{index}]"))
            if "portal_visual_origin_tile" in value or "portal_visual_footprint_tiles" in value:
                if "portal_visual_origin_tile" not in value or "portal_visual_footprint_tiles" not in value:
                    _error(f"{layer}[{index}].portal_visual_geometry_incomplete")
                origin = _pair(value["portal_visual_origin_tile"], f"{layer}[{index}].portal_origin")
                extent = _pair(value["portal_visual_footprint_tiles"], f"{layer}[{index}].portal_footprint", positive=True)
                portal_visual.update(_rect_cells(origin, extent, size))
    respawn_tiles: set[tuple[int, int]] = set()
    for index, value in enumerate(_entries(document, "respawn_points")):
        if not isinstance(value, dict):
            _error(f"respawn_points[{index}]_not_object")
        respawn_tiles.add(_tile(value, size, f"respawn_points[{index}]"))
    npc_cells: set[tuple[int, int]] = set()
    for index, value in enumerate(_entries(document, "npc_points")):
        if not isinstance(value, dict):
            _error(f"npc_points[{index}]_not_object")
        origin = _tile(value, size, f"npc_points[{index}]")
        extent = _pair(value.get("occupancy_footprint_tiles", [1, 1]), f"npc_points[{index}].occupancy", positive=True)
        npc_cells.update(_rect_cells(origin, extent, size))
    safe_cells: set[tuple[int, int]] = set()
    for index, value in enumerate(_entries(document, "safe_area")):
        if not isinstance(value, dict):
            _error(f"safe_area[{index}]_not_object")
        safe_cells.update(_safe_cells(value, size, f"safe_area[{index}]"))
    edge_cells = {
        (x, y)
        for y in range(size[1])
        for x in range(size[0])
        if x < EDGE_BUFFER
        or y < EDGE_BUFFER
        or x >= size[0] - EDGE_BUFFER
        or y >= size[1] - EDGE_BUFFER
    }
    portal_reserved = _buffer(portal_tiles | portal_visual, PORTAL_BUFFER, size)
    respawn_reserved = _buffer(respawn_tiles, RESPAWN_BUFFER, size)
    npc_reserved = _buffer(npc_cells, NPC_BUFFER, size)
    safe_reserved = _buffer(safe_cells, SAFE_BUFFER, size)
    reserved = portal_reserved | respawn_reserved | npc_reserved | safe_reserved | edge_cells
    return {
        "portal_tiles": portal_tiles,
        "portal_visual": portal_visual,
        "portal_reserved": portal_reserved,
        "portal_counts": portal_counts,
        "respawn_tiles": respawn_tiles,
        "respawn_reserved": respawn_reserved,
        "npc_cells": npc_cells,
        "npc_reserved": npc_reserved,
        "safe_cells": safe_cells,
        "safe_reserved": safe_reserved,
        "edge_cells": edge_cells,
        "reserved": reserved,
    }


def connected_components(cells: set[tuple[int, int]]) -> list[list[tuple[int, int]]]:
    remaining = set(cells)
    result: list[list[tuple[int, int]]] = []
    while remaining:
        start = min(remaining, key=lambda tile: (tile[1], tile[0]))
        remaining.remove(start)
        queue = deque([start])
        component: list[tuple[int, int]] = []
        while queue:
            current = queue.popleft()
            component.append(current)
            for neighbour in (
                (current[0] - 1, current[1]),
                (current[0] + 1, current[1]),
                (current[0], current[1] - 1),
                (current[0], current[1] + 1),
            ):
                if neighbour in remaining:
                    remaining.remove(neighbour)
                    queue.append(neighbour)
        result.append(sorted(component, key=lambda tile: (tile[1], tile[0])))
    result.sort(key=lambda component: (-len(component), component[0][1], component[0][0]))
    return result


def authority_identities(map_record: Mapping[str, Any]) -> tuple[list[dict[str, Any]], dict[str, int], list[str]]:
    tokens = map_record.get("tokens")
    if not isinstance(tokens, list):
        _error("authority_map_tokens_missing")
    skipped = Counter()
    by_id: dict[int, list[dict[str, Any]]] = {}
    blockers: list[str] = []
    for index, token in enumerate(tokens):
        if not isinstance(token, dict):
            blockers.append(f"authority_token_not_object:{index}")
            continue
        status = str(token.get("auto_placement_status", ""))
        if status != ALLOWED_STATUS:
            skipped[status or "MISSING_STATUS"] += 1
            continue
        resolved_ids = token.get("resolved_monster_ids")
        resolved_id = token.get("resolved_monster_id")
        if isinstance(resolved_ids, list) and len(resolved_ids) > 1:
            skipped["AUTO_PLACEMENT_ALLOWED_NON_UNIQUE_MONSTER_ID"] += 1
            continue
        if (
            token.get("auto_placement_allowed") is not True
            or token.get("placement_allowed") is not True
            or token.get("status") != "resolved"
            or token.get("resolution_status") != "resolved"
            or not isinstance(resolved_ids, list)
            or isinstance(resolved_id, bool)
            or not isinstance(resolved_id, int)
            or resolved_ids[0] != resolved_id
            or resolved_id <= 0
        ):
            blockers.append(f"allowed_identity_not_unique:{index}")
            continue
        classification = str(token.get("classification", ""))
        if classification not in {"ordinary", "elite", "boss"}:
            blockers.append(f"allowed_classification_invalid:{index}:{classification}")
            continue
        expected_kind = "monster_spawn" if classification == "ordinary" else "boss_spawn"
        if str(token.get("placement_kind", "")) != expected_kind:
            blockers.append(f"allowed_placement_kind_mismatch:{index}")
            continue
        expected_roles = {"ordinary"} if expected_kind == "monster_spawn" else {"elite", "boss"}
        if token.get("source_category_role") not in expected_roles:
            blockers.append(f"allowed_source_category_role_mismatch:{index}")
            continue
        if token.get("map_id") != map_record.get("map_id"):
            blockers.append(f"allowed_authority_map_id_mismatch:{index}")
            continue
        by_id.setdefault(resolved_id, []).append(token)
    identities: list[dict[str, Any]] = []
    for monster_id, records in sorted(by_id.items()):
        classifications = {str(record.get("classification", "")) for record in records}
        if len(classifications) != 1:
            blockers.append(f"monster_id_classification_ambiguous:{monster_id}")
            continue
        ordered_records = sorted(
            records,
            key=lambda record: (
                int(record.get("source_line", 0)),
                str(record.get("source_category_role", "")),
                int(record.get("source_token_index", 0)),
            ),
        )
        reference = {
            "map_id": str(ordered_records[0].get("map_id", "")),
            "source_line": _integer(
                ordered_records[0].get("source_line"), "source_line", positive=True
            ),
            "source_category_role": str(
                ordered_records[0].get("source_category_role", "")
            ),
            "source_token_index": _integer(
                ordered_records[0].get("source_token_index"),
                "source_token_index",
                positive=True,
            ),
        }
        raw_names = ordered_records[0].get("resolved_canonical_names")
        if not isinstance(raw_names, list) or len(raw_names) != 1 or not isinstance(raw_names[0], str):
            blockers.append(f"monster_id_canonical_name_not_unique:{monster_id}")
            continue
        identities.append(
            {
                "monster_id": monster_id,
                "classification": next(iter(classifications)),
                "canonical_name": raw_names[0],
                "authority_ref": reference,
                "authority_duplicate_token_count": len(ordered_records),
            }
        )
    return identities, dict(sorted(skipped.items())), blockers


def _distance_to_set(tile: tuple[int, int], values: set[tuple[int, int]], fallback: int) -> int:
    if not values:
        return fallback
    return min(abs(tile[0] - value[0]) + abs(tile[1] - value[1]) for value in values)


def choose_tiles(
    components: list[list[tuple[int, int]]],
    identities: Sequence[Mapping[str, Any]],
    hazard_tiles: set[tuple[int, int]],
    size: tuple[int, int],
) -> list[dict[str, Any]]:
    if not identities:
        _error("no_auto_placement_allowed_identities")
    largest = len(components[0]) if components else 0
    eligible = [
        component
        for component in components
        if len(component) >= MIN_COMPONENT_SIZE and len(component) * 20 >= largest
    ]
    if not eligible:
        _error("no_eligible_walkable_component")
    component_by_tile = {
        tile: index for index, component in enumerate(eligible) for tile in component
    }
    candidates = set(component_by_tile)
    ordered_identities = sorted(
        identities,
        key=lambda record: (
            {"boss": 0, "elite": 1, "ordinary": 2}[str(record["classification"])],
            int(record["monster_id"]),
        ),
    )
    chosen: list[tuple[int, int]] = []
    result: list[dict[str, Any]] = []
    for identity in ordered_identities:
        allowed = [
            tile
            for tile in candidates
            if all(
                abs(tile[0] - other[0]) + abs(tile[1] - other[1]) >= MIN_SPAWN_MANHATTAN
                for other in chosen
            )
        ]
        if not allowed:
            _error(f"insufficient_separated_tiles_for_monster:{identity['monster_id']}")
        def score(tile: tuple[int, int]) -> tuple[int, int, int, int, int, int, int]:
            separation = (
                min(abs(tile[0] - other[0]) + abs(tile[1] - other[1]) for other in chosen)
                if chosen
                else size[0] + size[1]
            )
            edge = min(tile[0], tile[1], size[0] - 1 - tile[0], size[1] - 1 - tile[1])
            component_id = component_by_tile[tile]
            component_unused = int(
                not any(component_by_tile[other] == component_id for other in chosen)
            )
            hazard_distance = _distance_to_set(
                tile, hazard_tiles, size[0] + size[1]
            )
            return (
                component_unused if chosen else 1,
                separation if chosen else hazard_distance,
                hazard_distance if chosen else edge,
                edge,
                len(eligible[component_id]),
                -tile[1],
                -tile[0],
            )
        selected = max(allowed, key=score)
        selected_score = score(selected)
        chosen.append(selected)
        candidates.remove(selected)
        result.append(
            {
                **copy.deepcopy(dict(identity)),
                "tile": selected,
                "component_id": component_by_tile[selected],
                "selection_score": list(selected_score),
            }
        )
    return result


def _respawn_policy(map_record: Mapping[str, Any]) -> str:
    series = str(map_record.get("series", ""))
    if series == "world":
        return "beginner_outdoor"
    if series == "hidden_boss":
        return "special_normal"
    return "normal_cave"


def _spawn_entry(map_record: Mapping[str, Any], placement: Mapping[str, Any]) -> dict[str, Any]:
    monster_id = int(placement["monster_id"])
    classification = str(placement["classification"])
    layer = "monster_spawn" if classification == "ordinary" else "boss_spawn"
    entry = {
        "kind": layer,
        "monster_id": monster_id,
        "classification": classification,
        "display_name": str(placement.get("canonical_name", "")),
        "tile": list(placement["tile"]),
        "count": 1,
        "max_alive": 1,
        "radius_gu": 0.0,
        "spawn_rule": "single_anchor_user_copy_template",
        "runtime_export": True,
        "content_layer": "personal_expansion",
        "occupancy_footprint_tiles": [1, 1],
        "semantic_id": (
            f"{layer}.auto.v1.{map_record['map_id']}.{monster_id:06d}"
        ),
        "spawn_group_id": (
            f"auto:v1:{map_record['map_id']}:{classification}:{monster_id:06d}"
        ),
        "auto_placement_status": (
            "AUTO_POSITIONED" if classification == "ordinary" else "AUTO_POSITIONED_BOSS"
        ),
        "authority_ref": copy.deepcopy(placement["authority_ref"]),
        "placement_evidence": {
            "planner_contract_id": CONTRACT_ID,
            "component_id": int(placement["component_id"]),
            "selection_score": copy.deepcopy(placement["selection_score"]),
        },
    }
    if classification == "ordinary":
        entry["respawn_policy_id"] = _respawn_policy(map_record)
    return entry


def evaluate_map(
    map_record: Mapping[str, Any],
    document: Mapping[str, Any],
    source_sha: str,
    authority_sha: str,
) -> dict[str, Any]:
    legacy_map_id = str(map_record.get("legacy_map_id", ""))
    if document.get("map_id") != legacy_map_id:
        _error(f"document_legacy_map_id_mismatch:{legacy_map_id}")
    if _integer(document.get("runtime_map_id"), "runtime_map_id", positive=True) != _integer(
        map_record.get("legacy_runtime_id"), "legacy_runtime_id", positive=True
    ):
        _error(f"document_legacy_runtime_id_mismatch:{legacy_map_id}")
    identities, skipped, authority_blockers = authority_identities(map_record)
    collision = build_collision(document)
    reservations = build_reservations(document, collision)
    size = collision["size"]
    design = document.get("design")
    editor_meta = document.get("editor_meta", {})
    ground = document.get("ground", {})
    if not isinstance(design, dict):
        _error("document_design_missing")
    if not isinstance(editor_meta, dict) or not isinstance(ground, dict):
        _error("document_completeness_metadata_unreadable")
    map_type = str(design.get("map_type", ""))
    workspace_status = str(editor_meta.get("workspace_status", ""))
    complete_dungeon = map_type == "dungeon_floor" and workspace_status == "ready"
    all_cells = {(x, y) for y in range(size[1]) for x in range(size[0])}
    safe_candidates = all_cells - collision["blocked"] - reservations["reserved"]
    components = connected_components(safe_candidates)
    blockers = list(authority_blockers)
    if legacy_map_id in TRANSITION_DEBT:
        blockers.append("TRANSITION_DEBT")
    if not identities:
        blockers.append("no_AUTO_PLACEMENT_ALLOWED_unique_monster_id")
    existing = {
        layer: len(_entries(document, layer)) for layer in TARGET_LAYERS
    }
    if any(existing.values()):
        blockers.append("source_spawn_layers_not_empty")
    if not collision["sources"] or not collision["blocked"]:
        blockers.append("collision_incomplete_or_empty")
    if len(collision["blocked"]) >= size[0] * size[1]:
        blockers.append("collision_blocks_entire_grid")
    placements: list[dict[str, Any]] = []
    if not blockers:
        try:
            placements = choose_tiles(
                components,
                identities,
                reservations["portal_tiles"] | reservations["respawn_tiles"] | reservations["npc_cells"] | reservations["safe_cells"],
                size,
            )
        except PlannerError as exc:
            blockers.append(str(exc))
    entries = [_spawn_entry(map_record, placement) for placement in placements]
    monster_entries = [entry for entry in entries if entry["kind"] == "monster_spawn"]
    boss_entries = [entry for entry in entries if entry["kind"] == "boss_spawn"]
    return {
        "map_id": str(map_record.get("map_id", "")),
        "legacy_map_id": legacy_map_id,
        "runtime_map_id": _integer(map_record.get("runtime_map_id"), "runtime_map_id", positive=True),
        "legacy_runtime_id": _integer(map_record.get("legacy_runtime_id"), "legacy_runtime_id", positive=True),
        "display_name": str(map_record.get("display_name", "")),
        "series": str(map_record.get("series", "")),
        "map_completeness": {
            "map_type": map_type,
            "workspace_status": workspace_status,
            "ground_mode": str(ground.get("ground_mode", "")),
            "ground_visual_only": ground.get("visual_only"),
            "collision_from_ground": ground.get("collision_from_ground"),
            "all_collision_geometry_parsed": True,
            "all_collision_erase_entries_parsed": True,
            "all_instance_layers_scanned": list(INSTANCE_LAYERS),
            "complete_dungeon": complete_dungeon,
        },
        "status": "READY" if not blockers else "BLOCKED",
        "blockers": blockers,
        "source_editor": {
            "path": f"source_editor_root:{legacy_map_id}/{legacy_map_id}.editor.json",
            "sha256": source_sha,
        },
        "authority": {
            "contract_id": AUTHORITY_CONTRACT,
            "manifest_sha256": authority_sha,
            "auto_allowed_token_count": sum(
                1
                for token in map_record.get("tokens", [])
                if isinstance(token, dict) and token.get("auto_placement_status") == ALLOWED_STATUS
            ),
            "unique_monster_id_count": len(identities),
            "skipped_status_counts": skipped,
            "not_emitted_auto_allowed_token_count": max(
                0,
                sum(
                    1
                    for token in map_record.get("tokens", [])
                    if isinstance(token, dict) and token.get("auto_placement_status") == ALLOWED_STATUS
                )
                - len(identities),
            ),
        },
        "walkability": {
            "design_size": list(size),
            "grid_cell_count": size[0] * size[1],
            "collision_source_count": len(collision["sources"]),
            "collision_sources": collision["sources"],
            "collision_blocked_cell_count": len(collision["blocked"]),
            "collision_erase_cell_count": len(collision["erased"]),
            "solid_footprint_cell_count": len(collision["solid"]),
            "portal_counts": reservations["portal_counts"],
            "portal_tile_count": len(reservations["portal_tiles"]),
            "portal_visual_cell_count": len(reservations["portal_visual"]),
            "portal_buffer_radius": PORTAL_BUFFER,
            "portal_reserved_cell_count": len(reservations["portal_reserved"]),
            "respawn_point_count": len(reservations["respawn_tiles"]),
            "respawn_buffer_radius": RESPAWN_BUFFER,
            "respawn_reserved_cell_count": len(reservations["respawn_reserved"]),
            "npc_cell_count": len(reservations["npc_cells"]),
            "npc_buffer_radius": NPC_BUFFER,
            "npc_reserved_cell_count": len(reservations["npc_reserved"]),
            "safe_area_cell_count": len(reservations["safe_cells"]),
            "safe_buffer_radius": SAFE_BUFFER,
            "safe_reserved_cell_count": len(reservations["safe_reserved"]),
            "edge_buffer_radius": EDGE_BUFFER,
            "safe_candidate_cell_count": len(safe_candidates),
            "component_count": len(components),
            "component_sizes": [len(component) for component in components],
        },
        "existing_spawn_layer_counts": existing,
        "placements": entries,
        "placement_summary": {
            "monster_spawn_count": len(monster_entries),
            "boss_spawn_count": len(boss_entries),
            "AUTO_POSITIONED_BOSS": len(boss_entries),
            "each_unique_monster_id_count": 1,
        },
        "placement_input": {
            "layers": {
                "monster_spawn": monster_entries,
                "boss_spawn": boss_entries,
            }
        },
    }


@dataclass(frozen=True)
class PlannerPaths:
    source_editor_root: Path
    authority: Path
    identity_registry: Path
    output_root: Path

    def resolved(self) -> "PlannerPaths":
        return PlannerPaths(*(path.resolve() for path in self.__dict__.values()))


def plan(paths: PlannerPaths) -> tuple[dict[str, Any], dict[str, bytes], dict[str, Path]]:
    paths = paths.resolved()
    if not paths.source_editor_root.is_dir():
        _error("source_editor_root_missing")
    if _inside(paths.output_root, paths.source_editor_root):
        _error("output_root_inside_source_editor_root")
    repo = _repo_root(paths.authority)
    if not _inside(paths.output_root, repo):
        _error("output_root_must_be_inside_repo")
    authority, authority_raw = _load(paths.authority)
    identity, identity_raw = _load(paths.identity_registry)
    if authority.get("contract_id") != AUTHORITY_CONTRACT:
        _error("authority_contract_mismatch")
    if identity.get("contract_id") != IDENTITY_CONTRACT:
        _error("identity_contract_mismatch")
    maps = authority.get("maps")
    identity_maps = identity.get("maps")
    if not isinstance(maps, list) or len(maps) != 67:
        _error("authority_must_contain_67_maps")
    if not isinstance(identity_maps, list) or len(identity_maps) != 67:
        _error("identity_registry_must_contain_67_maps")
    identity_by_map = {
        str(entry.get("map_id", "")): entry for entry in identity_maps if isinstance(entry, dict)
    }
    authority_sha = sha256_bytes(authority_raw)
    protected: dict[str, Path] = {
        _repo_key(paths.authority, repo): paths.authority,
        _repo_key(paths.identity_registry, repo): paths.identity_registry,
    }
    before = {
        _repo_key(paths.authority, repo): authority_sha,
        _repo_key(paths.identity_registry, repo): sha256_bytes(identity_raw),
    }
    evaluations: list[dict[str, Any]] = []
    for map_record in maps:
        if not isinstance(map_record, dict):
            _error("authority_map_not_object")
        map_id = str(map_record.get("map_id", ""))
        if map_id not in identity_by_map:
            _error(f"authority_map_missing_identity:{map_id}")
        legacy = str(map_record.get("legacy_map_id", ""))
        document_path = paths.source_editor_root / legacy / f"{legacy}.editor.json"
        document, raw = _load(document_path)
        source_key = _source_key(document_path, paths.source_editor_root)
        protected[source_key] = document_path
        before[source_key] = sha256_bytes(raw)
        try:
            evaluation = evaluate_map(map_record, document, before[source_key], authority_sha)
        except PlannerError as exc:
            evaluation = {
                "map_id": map_id,
                "legacy_map_id": legacy,
                "display_name": str(map_record.get("display_name", "")),
                "series": str(map_record.get("series", "")),
                "status": "BLOCKED",
                "blockers": [f"walkability_unverifiable:{exc}"],
                "source_editor": {"path": source_key, "sha256": before[source_key]},
            }
        evaluations.append(evaluation)
    after_analysis = {key: sha256_file(path) for key, path in protected.items()}
    if before != after_analysis:
        _error("source_inputs_changed_during_analysis")
    ready = [evaluation for evaluation in evaluations if evaluation.get("status") == "READY"]
    if ready:
        ready.sort(
            key=lambda row: (
                not bool(row.get("map_completeness", {}).get("complete_dungeon")),
                str(row.get("series", "")) == "world",
                -int(row.get("placement_summary", {}).get("AUTO_POSITIONED_BOSS", 0) > 0),
                -int(row.get("authority", {}).get("unique_monster_id_count", 0)),
                -int((row.get("walkability", {}).get("component_sizes") or [0])[0]),
                str(row.get("map_id", "")),
            )
        )
        pilot = ready[0]
        pilot_status = "READY"
    else:
        pilot = None
        pilot_status = "BLOCKED"
    artifacts: dict[str, bytes] = {}
    if pilot is not None:
        map_id = str(pilot["map_id"])
        artifacts[f"{map_id}/placement_input.json"] = canonical_bytes(pilot["placement_input"])
        report = copy.deepcopy(pilot)
        report.pop("placement_input", None)
        report["selection_reason"] = {
            "rule": "ready_complete_dungeon_then_non_world_then_boss_then_unique_monster_count_then_largest_component_v1",
            "complete_dungeon": bool(
                pilot.get("map_completeness", {}).get("complete_dungeon")
            ),
            "preferred_complete_dungeon_over_world_city": str(pilot.get("series")) != "world",
            "selected_from_ready_map_count": len(ready),
            "unique_monster_id_count": int(
                pilot.get("authority", {}).get("unique_monster_id_count", 0)
            ),
            "AUTO_POSITIONED_BOSS": int(
                pilot.get("placement_summary", {}).get("AUTO_POSITIONED_BOSS", 0)
            ),
            "largest_walkable_component_size": int(
                (pilot.get("walkability", {}).get("component_sizes") or [0])[0]
            ),
        }
        artifacts[f"{map_id}/placement_report.json"] = canonical_bytes(report)
    compact_evaluations = [
        {
            "map_id": row.get("map_id"),
            "legacy_map_id": row.get("legacy_map_id"),
            "series": row.get("series"),
            "complete_dungeon": row.get("map_completeness", {}).get("complete_dungeon", False),
            "status": row.get("status"),
            "blockers": row.get("blockers", []),
            "unique_monster_id_count": row.get("authority", {}).get("unique_monster_id_count", 0),
            "collision_blocked_cell_count": row.get("walkability", {}).get("collision_blocked_cell_count", 0),
            "largest_component_size": (row.get("walkability", {}).get("component_sizes") or [0])[0],
            "AUTO_POSITIONED_BOSS": row.get("placement_summary", {}).get("AUTO_POSITIONED_BOSS", 0),
        }
        for row in evaluations
    ]
    manifest = {
        "schema_version": 1,
        "manifest_id": MANIFEST_ID,
        "contract_id": CONTRACT_ID,
        "generated_by": "tools/map_editor/plan_map_monster_auto_placement.py",
        "status": pilot_status,
        "policy": {
            "one_entry_per_unique_monster_id": True,
            "user_copies_entries_after_pilot": True,
            "authority_allowed_status": ALLOWED_STATUS,
            "transition_debt_skipped": sorted(TRANSITION_DEBT),
            "special_explicit_unresolved_excluded_skipped": True,
            "boss_and_elite_layer": "boss_spawn",
            "ordinary_respawn_contract": "monster.respawn.policy.hardcore.v1",
            "coordinate_guessing_forbidden": True,
            "build_and_publish_forbidden": True,
        },
        "inputs": {
            "source_editor_root": {"root_kind": "explicit_read_only_source_editor_root"},
            "authority": {
                "path": _repo_key(paths.authority, repo),
                "sha256": authority_sha,
            },
            "identity_registry": {
                "path": _repo_key(paths.identity_registry, repo),
                "sha256": sha256_bytes(identity_raw),
            },
        },
        "source_map_count": 67,
        "ready_map_count": len(ready),
        "pilot_map_id": pilot.get("map_id") if pilot else None,
        "pilot_legacy_map_id": pilot.get("legacy_map_id") if pilot else None,
        "artifact_paths": sorted(artifacts),
        "map_evaluations": compact_evaluations,
        "source_hash_proof": {
            "before": dict(sorted(before.items())),
            "after": dict(sorted(after_analysis.items())),
            "all_67_source_editors_unchanged": before == after_analysis,
            "source_editor_count": sum(key.startswith("source_editor_root:") for key in before),
        },
    }
    artifacts["manifest.json"] = canonical_bytes(manifest)
    return manifest, artifacts, protected


def write_atomic(paths: PlannerPaths, artifacts: Mapping[str, bytes]) -> None:
    output = paths.output_root.resolve()
    if output.exists():
        _error("output_root_already_exists")
    output.parent.mkdir(parents=True, exist_ok=True)
    stage = Path(tempfile.mkdtemp(prefix=f".{output.name}.stage-", dir=output.parent))
    try:
        for relative, raw in sorted(artifacts.items()):
            target = stage / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(raw)
        os.replace(stage, output)
    except Exception:
        shutil.rmtree(stage, ignore_errors=True)
        raise


def run(paths: PlannerPaths, *, write: bool) -> dict[str, Any]:
    resolved = paths.resolved()
    manifest, artifacts, protected = plan(resolved)
    before = manifest["source_hash_proof"]["before"]
    if write:
        if manifest["status"] != "READY":
            _error("pilot_write_blocked")
        write_atomic(resolved, artifacts)
    after = {key: sha256_file(path) for key, path in protected.items()}
    if before != after:
        if write and resolved.output_root.exists():
            shutil.rmtree(resolved.output_root)
        _error("source_inputs_changed_during_output")
    return manifest


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-editor-root", type=Path, required=True)
    parser.add_argument("--authority", type=Path, required=True)
    parser.add_argument("--identity-registry", type=Path, required=True)
    parser.add_argument("--output-root", type=Path, required=True)
    parser.add_argument("--write", action="store_true")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    try:
        manifest = run(
            PlannerPaths(
                args.source_editor_root,
                args.authority,
                args.identity_registry,
                args.output_root,
            ),
            write=args.write,
        )
    except PlannerError as exc:
        print(f"BLOCKED: {exc}", file=sys.stderr)
        return 2
    print(json.dumps(manifest, ensure_ascii=False, indent=2))
    return 0 if manifest["status"] == "READY" else 2


if __name__ == "__main__":
    raise SystemExit(main())
