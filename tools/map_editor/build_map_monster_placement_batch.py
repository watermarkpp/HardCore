#!/usr/bin/env python3
"""Build fail-closed one-of-each monster placement candidates for formal maps."""

from __future__ import annotations

import argparse
import copy
import hashlib
import importlib.util
import json
import os
import shutil
import sys
import tempfile
from pathlib import Path
from typing import Any, Mapping


REPO = Path(__file__).resolve().parents[2]
CONTRACT_ID = "hardcore.map_monster_placement_batch.v1"
PLAN_CONTRACT_ID = "hardcore.map_monster_auto_placement_plan.v2"
TARGET_LAYERS = ("monster_spawn", "boss_spawn")


class BatchError(RuntimeError):
    pass


def _error(message: str) -> None:
    raise BatchError(message)


def _module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        _error(f"module_load_failed:{path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


PLANNER = _module("map_monster_auto_planner_batch", Path(__file__).with_name("plan_map_monster_auto_placement.py"))
WRITER = _module("map_monster_safe_writer_batch", Path(__file__).with_name("map_monster_placement_safe_writer.py"))


def _load(path: Path) -> tuple[dict[str, Any], bytes]:
    raw = path.read_bytes()
    value = json.loads(raw.decode("utf-8-sig"))
    if not isinstance(value, dict):
        _error(f"json_root_not_object:{path}")
    return value, raw


def _sha(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def _json_bytes(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, indent=2).encode("utf-8") + b"\n"


def _authority_ref(token: Mapping[str, Any]) -> dict[str, Any]:
    return {
        "map_id": str(token["map_id"]),
        "source_line": int(token["source_line"]),
        "source_category_role": str(token["source_category_role"]),
        "source_token_index": int(token["source_token_index"]),
    }


def _ref_key(reference: Mapping[str, Any]) -> tuple[str, int, str, int]:
    return (
        str(reference["map_id"]),
        int(reference["source_line"]),
        str(reference["source_category_role"]),
        int(reference["source_token_index"]),
    )


def _catalog_index(catalog: Mapping[str, Any], required_count: int) -> dict[int, dict[str, Any]]:
    entries = catalog.get("entries")
    if not isinstance(entries, list) or len(entries) != required_count:
        _error(f"current_monster_library_count_mismatch:{len(entries) if isinstance(entries, list) else -1}")
    result: dict[int, dict[str, Any]] = {}
    for entry in entries:
        if not isinstance(entry, dict):
            _error("current_monster_library_entry_invalid")
        monster_id = entry.get("monster_id")
        if isinstance(monster_id, bool) or not isinstance(monster_id, int) or monster_id <= 0:
            _error("current_monster_library_id_invalid")
        if monster_id in result:
            _error(f"current_monster_library_duplicate_id:{monster_id}")
        if entry.get("runtime_allowed") is True and entry.get("status") == "formal":
            result[monster_id] = entry
    return result


def _identity_for(
    token: Mapping[str, Any],
    monster_id: int,
    catalog_entry: Mapping[str, Any],
) -> dict[str, Any]:
    placement_kind = str(token.get("placement_kind", ""))
    if placement_kind not in TARGET_LAYERS:
        _error(f"placement_kind_invalid:{token.get('map_id')}:{token.get('raw_token')}")
    canonical_classification = str(catalog_entry.get("classification", ""))
    planner_classification = (
        "ordinary" if placement_kind == "monster_spawn" else
        (canonical_classification if canonical_classification in {"elite", "boss"} else "elite")
    )
    return {
        "monster_id": monster_id,
        "canonical_name": str(catalog_entry.get("canonical_name", "")),
        "canonical_classification": canonical_classification,
        "classification": planner_classification,
        "placement_kind": placement_kind,
        "authority_ref": _authority_ref(token),
        "raw_token": str(token.get("raw_token", "")),
    }


def select_identities(
    map_record: Mapping[str, Any],
    catalog_by_id: Mapping[int, Mapping[str, Any]],
    policy: Mapping[str, Any],
) -> tuple[list[dict[str, Any]], list[dict[str, Any]], dict[tuple[str, int, str, int], dict[str, Any]]]:
    map_id = str(map_record.get("map_id", ""))
    placement_policy = policy["placement"]
    denied = {int(value) for value in placement_policy["denied_monster_ids"]}
    zombie_forms = {int(value) for value in placement_policy["zombie_visual_forms_are_ordinary"]}
    special_systems = {str(value) for value in placement_policy["special_systems_skipped"]}
    unknown = policy["unknown_dark_palace"]
    unknown_ids = {int(value) for value in unknown["exact_current_library_ids"]}
    identities: list[dict[str, Any]] = []
    skipped: list[dict[str, Any]] = []
    overlay: dict[tuple[str, int, str, int], dict[str, Any]] = {}

    for token in map_record.get("tokens", []):
        if not isinstance(token, dict):
            _error(f"authority_token_invalid:{map_id}")
        raw_token = str(token.get("raw_token", ""))
        role = str(token.get("source_category_role", ""))
        status = str(token.get("auto_placement_status", ""))
        resolved = [
            int(value) for value in token.get("resolved_monster_ids", [])
            if isinstance(value, int) and not isinstance(value, bool)
        ]
        chosen: list[int] = []
        allow_unresolved = False
        reason = ""

        if map_id == str(unknown["map_id"]):
            chosen = [value for value in resolved if value in unknown_ids]
            if "沃玛卫士" in raw_token and 74 in unknown_ids:
                chosen = [74]
                allow_unresolved = True
            if not chosen:
                reason = "SKIP_DELETED_OR_NOT_IN_CURRENT_LIBRARY"
        elif raw_token in special_systems or any(raw_token.startswith(name) for name in special_systems):
            reason = "SKIP_SPECIAL_SYSTEM_USER_HANDLED"
        elif "僵尸（多种外观形态）" in raw_token:
            chosen = [value for value in resolved if value in zombie_forms]
        elif "祖玛卫士（极品变体）" in raw_token:
            chosen = [int(placement_policy["zuma_elite_guard_id"])]
        elif len(resolved) == 1:
            chosen = list(resolved)
        elif len(resolved) > 1:
            reason = "SKIP_NON_UNIQUE_VARIANT_GROUP"
        else:
            reason = "SKIP_DELETED_OR_NOT_IN_CURRENT_LIBRARY"

        chosen = [value for value in chosen if value not in denied and value in catalog_by_id]
        if not chosen:
            skipped.append({
                "raw_token": raw_token,
                "source_category_role": role,
                "reason": reason or "SKIP_DELETED_OR_NOT_IN_CURRENT_LIBRARY",
                "authority_status": status,
                "resolved_monster_ids": resolved,
            })
            continue
        if role not in {"ordinary", "elite", "boss", "special"}:
            skipped.append({
                "raw_token": raw_token,
                "source_category_role": role,
                "reason": "SKIP_NON_MONSTER_OR_SPECIAL_SYSTEM",
                "authority_status": status,
                "resolved_monster_ids": resolved,
            })
            continue
        reference = _authority_ref(token)
        key = _ref_key(reference)
        overlay[key] = {
            "allowed_statuses": [status],
            "allowed_source_category_roles": [role],
            "selected_monster_ids": sorted(set(chosen)),
            "allow_unresolved": allow_unresolved,
        }
        for monster_id in sorted(set(chosen)):
            identities.append(_identity_for(token, monster_id, catalog_by_id[monster_id]))

    by_id: dict[int, dict[str, Any]] = {}
    for identity in identities:
        monster_id = int(identity["monster_id"])
        previous = by_id.get(monster_id)
        if previous is not None and previous["placement_kind"] != identity["placement_kind"]:
            _error(f"monster_id_layer_ambiguous:{map_id}:{monster_id}")
        by_id.setdefault(monster_id, identity)
    return [by_id[key] for key in sorted(by_id)], skipped, overlay


def _inheritance_overrides(policy: Mapping[str, Any]) -> dict[str, dict[str, Any]]:
    """Return the explicit, fail-closed cross-map pool overrides by target ID."""

    raw = policy.get("pool_inheritance_overrides", [])
    if not isinstance(raw, list):
        _error("pool_inheritance_overrides_must_be_array")
    result: dict[str, dict[str, Any]] = {}
    for index, value in enumerate(raw):
        if not isinstance(value, dict):
            _error(f"pool_inheritance_override_invalid:{index}")
        map_id = value.get("map_id")
        if not isinstance(map_id, str) or not map_id.strip():
            _error(f"pool_inheritance_override_map_id_invalid:{index}")
        map_id = map_id.strip()
        if map_id in result:
            _error(f"pool_inheritance_override_duplicate:{map_id}")
        if value.get("mode") != "adjacent_pool_union":
            _error(f"pool_inheritance_override_mode_invalid:{map_id}")
        source_map_ids = value.get("source_map_ids")
        if (
            not isinstance(source_map_ids, list)
            or not source_map_ids
            or any(not isinstance(source_id, str) or not source_id.strip() for source_id in source_map_ids)
            or len(set(source_map_ids)) != len(source_map_ids)
        ):
            _error(f"pool_inheritance_override_sources_invalid:{map_id}")
        expected_ids = value.get("expected_monster_ids")
        if (
            not isinstance(expected_ids, list)
            or not expected_ids
            or any(isinstance(monster_id, bool) or not isinstance(monster_id, int) or monster_id <= 0 for monster_id in expected_ids)
            or len(set(expected_ids)) != len(expected_ids)
        ):
            _error(f"pool_inheritance_override_expected_ids_invalid:{map_id}")
        classifications = value.get("include_classifications")
        if (
            not isinstance(classifications, list)
            or not classifications
            or any(classification not in {"ordinary", "elite", "boss"} for classification in classifications)
        ):
            _error(f"pool_inheritance_override_classifications_invalid:{map_id}")
        if value.get("skip_special_systems") is not True:
            _error(f"pool_inheritance_override_must_skip_special_systems:{map_id}")
        target_ref = value.get("target_authority_ref")
        if not isinstance(target_ref, dict):
            _error(f"pool_inheritance_override_target_ref_invalid:{map_id}")
        required_ref = {"map_id", "source_line", "source_category_role", "source_token_index"}
        if set(target_ref) != required_ref:
            _error(f"pool_inheritance_override_target_ref_shape_invalid:{map_id}")
        if target_ref.get("map_id") != map_id:
            _error(f"pool_inheritance_override_target_ref_map_mismatch:{map_id}")
        result[map_id] = copy.deepcopy(value)
    return result


def select_inherited_identities(
    target_record: Mapping[str, Any],
    source_records: list[Mapping[str, Any]],
    catalog_by_id: Mapping[int, Mapping[str, Any]],
    policy: Mapping[str, Any],
    override: Mapping[str, Any],
) -> tuple[list[dict[str, Any]], list[dict[str, Any]], dict[tuple[str, int, str, int], dict[str, Any]], dict[str, Any]]:
    """Build target-bound identities from an explicit adjacent-map pool union.

    The target map deliberately has a source marker rather than a monster token.
    Every emitted identity is therefore bound to that target marker, while the
    source token references remain recorded in the policy overlay/evidence.  The
    checks here are intentionally strict: source map uniqueness, series, current
    library membership, classification and the policy's expected union must all
    agree before a candidate can be written.
    """

    target_map_id = str(target_record.get("map_id", ""))
    target_ref = copy.deepcopy(override["target_authority_ref"])
    if target_ref.get("map_id") != target_map_id:
        _error(f"pool_inheritance_target_map_mismatch:{target_map_id}")
    target_tokens = [
        token
        for token in target_record.get("tokens", [])
        if isinstance(token, dict) and _ref_key(target_ref) == _ref_key(_authority_ref(token))
    ]
    if len(target_tokens) != 1:
        _error(f"pool_inheritance_target_ref_not_unique:{target_map_id}:{len(target_tokens)}")
    target_token = target_tokens[0]
    if str(target_token.get("source_category_role", "")) != "special":
        _error(f"pool_inheritance_target_ref_not_special:{target_map_id}")
    if not bool(override.get("skip_special_systems")):
        _error(f"pool_inheritance_skip_special_systems_required:{target_map_id}")

    source_map_ids = [str(source_id) for source_id in override["source_map_ids"]]
    actual_source_ids = [str(record.get("map_id", "")) for record in source_records]
    if actual_source_ids != source_map_ids:
        _error(f"pool_inheritance_source_order_mismatch:{target_map_id}:{actual_source_ids}")
    expected_series = str(override.get("source_series", ""))
    if not expected_series:
        _error(f"pool_inheritance_source_series_missing:{target_map_id}")

    merged: dict[int, dict[str, Any]] = {}
    source_refs_by_id: dict[int, list[dict[str, Any]]] = {}
    skipped: list[dict[str, Any]] = []
    source_reports: list[dict[str, Any]] = []
    allowed_classifications = {str(value) for value in override["include_classifications"]}
    for source_record in source_records:
        source_id = str(source_record.get("map_id", ""))
        if str(source_record.get("series", "")) != expected_series:
            _error(f"pool_inheritance_source_series_mismatch:{target_map_id}:{source_id}")
        identities, source_skipped, _source_overlay = select_identities(source_record, catalog_by_id, policy)
        for item in source_skipped:
            skipped.append({"source_map_id": source_id, **item})
        selected_source_ids: list[int] = []
        for item in identities:
            monster_id = int(item["monster_id"])
            classification = str(item["canonical_classification"])
            if classification not in allowed_classifications:
                _error(f"pool_inheritance_classification_forbidden:{target_map_id}:{source_id}:{monster_id}")
            catalog_entry = catalog_by_id.get(monster_id)
            if catalog_entry is None or catalog_entry.get("runtime_allowed") is not True or catalog_entry.get("status") != "formal":
                _error(f"pool_inheritance_current_library_forbidden:{target_map_id}:{source_id}:{monster_id}")
            source_ref = copy.deepcopy(item["authority_ref"])
            source_refs_by_id.setdefault(monster_id, []).append(source_ref)
            selected_source_ids.append(monster_id)
            if monster_id not in merged:
                inherited = copy.deepcopy(item)
                inherited["authority_ref"] = copy.deepcopy(target_ref)
                inherited["raw_token"] = f"inherited:{source_id}:{item['raw_token']}"
                inherited["pool_inheritance"] = {
                    "mode": "adjacent_pool_union",
                    "target_map_id": target_map_id,
                    "source_map_id": source_id,
                    "source_authority_refs": [copy.deepcopy(source_ref)],
                }
                merged[monster_id] = inherited
            else:
                merged[monster_id]["pool_inheritance"]["source_authority_refs"].append(copy.deepcopy(source_ref))
        source_reports.append({
            "map_id": source_id,
            "selected_monster_ids": sorted(set(selected_source_ids)),
            "skipped_count": len(source_skipped),
        })

    selected_ids = sorted(merged)
    expected_ids = sorted(int(value) for value in override["expected_monster_ids"])
    if selected_ids != expected_ids:
        _error(f"pool_inheritance_union_mismatch:{target_map_id}:expected={expected_ids}:actual={selected_ids}")
    target_key = _ref_key(target_ref)
    overlay = {
        target_key: {
            "allowed_statuses": [str(target_token.get("auto_placement_status", ""))],
            "allowed_source_category_roles": ["special"],
            "allowed_placement_kinds": [str(target_token.get("placement_kind", ""))],
            "selected_monster_ids": selected_ids,
            "allow_unresolved": True,
            "inherited_source_refs": copy.deepcopy(source_refs_by_id),
        }
    }
    evidence = {
        "mode": "adjacent_pool_union",
        "target_map_id": target_map_id,
        "target_authority_ref": target_ref,
        "source_map_ids": source_map_ids,
        "source_reports": source_reports,
        "selected_monster_ids": selected_ids,
        "source_authority_refs_by_monster_id": copy.deepcopy(source_refs_by_id),
    }
    return [merged[monster_id] for monster_id in selected_ids], skipped, overlay, evidence


def _respawn_policy(series: str) -> str:
    if series == "world":
        return "beginner_outdoor"
    if series == "hidden_boss":
        return "special_normal"
    return "normal_cave"


def _spawn_entry(map_record: Mapping[str, Any], placement: Mapping[str, Any]) -> dict[str, Any]:
    monster_id = int(placement["monster_id"])
    layer = str(placement["placement_kind"])
    classification = str(placement["canonical_classification"])
    entry = {
        "kind": layer,
        "monster_id": monster_id,
        "classification": classification,
        "display_name": str(placement["canonical_name"]),
        "tile": list(placement["tile"]),
        "count": 1,
        "max_alive": 1,
        "radius_gu": 0.0,
        "spawn_rule": "single_anchor_user_copy_template",
        "runtime_export": True,
        "content_layer": "personal_expansion",
        "occupancy_footprint_tiles": [1, 1],
        "semantic_id": f"{layer}.auto.v2.{map_record['map_id']}.{monster_id:06d}",
        "spawn_group_id": f"auto:v2:{map_record['map_id']}:{classification}:{monster_id:06d}",
        "auto_placement_status": "AUTO_POSITIONED" if layer == "monster_spawn" else "AUTO_POSITIONED_BOSS",
        "authority_ref": copy.deepcopy(placement["authority_ref"]),
        "placement_evidence": {
            "planner_contract_id": PLAN_CONTRACT_ID,
            "component_id": int(placement["component_id"]),
            "selection_score": copy.deepcopy(placement["selection_score"]),
            "current_monster_library_only": True,
        },
    }
    if "pool_inheritance" in placement:
        entry["placement_evidence"]["pool_inheritance"] = copy.deepcopy(placement["pool_inheritance"])
    if layer == "monster_spawn":
        entry["respawn_policy_id"] = _respawn_policy(str(map_record.get("series", "")))
    return entry


def build(paths: argparse.Namespace) -> dict[str, Any]:
    source_root = paths.source_editor_root.resolve()
    authority, authority_raw = _load(paths.authority.resolve())
    identity, identity_raw = _load(paths.identity_registry.resolve())
    catalog, catalog_raw = _load(paths.catalog.resolve())
    policy, policy_raw = _load(paths.policy.resolve())
    snapshot = paths.snapshot.resolve()
    if authority.get("contract_id") != "hardcore.map_monster_placement_authority.v2":
        _error("authority_contract_mismatch")
    if identity.get("contract_id") != "hardcore.formal_map_identity.v1":
        _error("identity_contract_mismatch")
    if policy.get("contract_id") != "hardcore.map_monster_placement_execution_policy.v1":
        _error("execution_policy_contract_mismatch")
    library_policy = policy["current_monster_library"]
    if _sha(catalog_raw) != str(library_policy["sha256"]):
        _error("current_monster_library_hash_mismatch")
    catalog_by_id = _catalog_index(catalog, int(library_policy["required_entry_count"]))
    maps = authority.get("maps")
    identity_maps = identity.get("maps")
    if not isinstance(maps, list) or len(maps) != 67:
        _error("authority_map_count_mismatch")
    if not isinstance(identity_maps, list) or len(identity_maps) != 67:
        _error("identity_map_count_mismatch")
    identity_by_id = {str(row["map_id"]): row for row in identity_maps}
    if len(identity_by_id) != 67 or len({int(row["runtime_map_id"]) for row in identity_maps}) != 67:
        _error("identity_uniqueness_mismatch")
    frozen_by_id = {str(row["map_id"]): row for row in policy["frozen_maps"]}
    transition = {str(value) for value in policy.get("transition_backfill_maps", [])}
    no_fixed = {str(value) for value in policy.get("no_fixed_spawn_maps", [])}
    replace_existing = {str(value) for value in policy.get("replace_existing_spawn_maps", [])}
    inheritance = _inheritance_overrides(policy)
    rebuild_map_ids = replace_existing | set(inheritance)
    if transition or no_fixed:
        _error("legacy_transition_or_no_fixed_policy_not_retired")
    if len(rebuild_map_ids) != 6:
        _error(f"rebuild_map_count_mismatch:{len(rebuild_map_ids)}")
    if frozen_by_id.keys() & rebuild_map_ids:
        _error("rebuild_map_overlaps_frozen_map")
    base_manifest: dict[str, Any] | None = None
    base_manifest_rows: dict[str, dict[str, Any]] = {}
    if paths.base_manifest is not None:
        base_manifest, _base_manifest_raw = _load(paths.base_manifest.resolve())
        if base_manifest.get("contract_id") != CONTRACT_ID:
            _error("base_manifest_contract_mismatch")
        base_rows = base_manifest.get("maps")
        if not isinstance(base_rows, list) or len(base_rows) != 67:
            _error("base_manifest_map_count_mismatch")
        for row in base_rows:
            if not isinstance(row, dict) or not isinstance(row.get("map_id"), str):
                _error("base_manifest_row_invalid")
            if row["map_id"] in base_manifest_rows:
                _error(f"base_manifest_duplicate_map:{row['map_id']}")
            base_manifest_rows[row["map_id"]] = row
        if set(base_manifest_rows) != {str(row["map_id"]) for row in maps}:
            _error("base_manifest_map_identity_mismatch")
    plan_output = paths.plan_output.resolve()
    candidate_output = paths.candidate_output.resolve()
    if plan_output.exists() or candidate_output.exists():
        _error("output_already_exists")
    plan_output.parent.mkdir(parents=True, exist_ok=True)
    candidate_output.parent.mkdir(parents=True, exist_ok=True)
    plan_stage = Path(tempfile.mkdtemp(prefix=f".{plan_output.name}.stage-", dir=plan_output.parent))
    candidate_stage = Path(tempfile.mkdtemp(prefix=f".{candidate_output.name}.stage-", dir=candidate_output.parent))
    reports: list[dict[str, Any]] = []
    written_candidates = 0
    try:
        for map_record in maps:
            map_id = str(map_record["map_id"])
            identity_row = identity_by_id.get(map_id)
            if identity_row is None:
                _error(f"identity_missing:{map_id}")
            legacy = str(identity_row["legacy_map_id"])
            source_path = source_root / legacy / f"{legacy}.editor.json"
            document, source_raw = _load(source_path)
            if (
                str(document.get("map_id")) != legacy
                or int(document.get("runtime_map_id", -1))
                not in {
                    int(identity_row["legacy_runtime_map_id"]),
                    int(identity_row["runtime_map_id"]),
                }
            ):
                _error(f"source_identity_mismatch:{map_id}")
            base_report = {
                "map_id": map_id,
                "legacy_map_id": legacy,
                "runtime_map_id": int(identity_row["runtime_map_id"]),
                "display_name": str(identity_row["display_name"]),
                "source_sha256": _sha(source_raw),
            }
            if map_id in frozen_by_id:
                expected = str(frozen_by_id[map_id]["source_sha256"])
                if _sha(source_raw) != expected:
                    _error(f"frozen_source_hash_mismatch:{map_id}")
                reports.append({**base_report, "status": "PRESERVE_USER_ACCEPTED", "placement_count": sum(len(document.get("layers", {}).get(layer, [])) for layer in TARGET_LAYERS)})
                continue
            if map_id not in rebuild_map_ids:
                # Existing candidates are already authoritative output from the
                # previous batch.  Preserve their bytes and report verbatim;
                # only the six explicitly authorized maps may be regenerated.
                existing = base_manifest_rows.get(map_id)
                if existing is None or existing.get("status") != "CANDIDATE_WRITTEN":
                    _error(f"existing_candidate_missing_for_preserved_map:{map_id}")
                candidate_sha = str(existing.get("candidate_sha256", ""))
                if not candidate_sha or _sha(source_raw) != candidate_sha:
                    _error(f"preserved_candidate_changed:{map_id}")
                reports.append(copy.deepcopy(existing))
                written_candidates += 1
                continue
            layers = document.get("layers", {})
            if map_id in inheritance:
                source_ids = [str(value) for value in inheritance[map_id]["source_map_ids"]]
                source_records = []
                for source_id in source_ids:
                    matches = [record for record in maps if str(record.get("map_id", "")) == source_id]
                    if len(matches) != 1:
                        _error(f"pool_inheritance_source_map_not_unique:{map_id}:{source_id}:{len(matches)}")
                    source_records.append(matches[0])
                identities, skipped, overlay, inheritance_evidence = select_inherited_identities(
                    map_record,
                    source_records,
                    catalog_by_id,
                    policy,
                    inheritance[map_id],
                )
            else:
                identities, skipped, overlay = select_identities(map_record, catalog_by_id, policy)
                inheritance_evidence = None
            if not identities:
                _error(f"no_current_library_monsters_selected:{map_id}")
            collision = PLANNER.build_collision(document)
            collision["blocked"] = set(collision["blocked"]) | WRITER._collect_static_blocked(
                document, collision["size"]
            )
            reservations = PLANNER.build_reservations(document, collision)
            size = collision["size"]
            all_cells = {(x, y) for y in range(size[1]) for x in range(size[0])}
            safe = all_cells - collision["blocked"] - reservations["reserved"]
            components = PLANNER.connected_components(safe)
            placements = PLANNER.choose_tiles(
                components,
                identities,
                reservations["portal_tiles"] | reservations["respawn_tiles"] | reservations["npc_cells"] | reservations["safe_cells"],
                size,
            )
            entries = [_spawn_entry(map_record, row) for row in placements]
            placement_input = {"layers": {layer: [entry for entry in entries if entry["kind"] == layer] for layer in TARGET_LAYERS}}
            map_plan_dir = plan_stage / map_id
            map_plan_dir.mkdir(parents=True)
            input_path = map_plan_dir / "placement_input.json"
            input_path.write_bytes(_json_bytes(placement_input))
            candidate_file = candidate_stage / legacy / f"{legacy}.editor.json"
            candidate_file.parent.mkdir(parents=True)
            write_result = WRITER.write_candidate(
                source_root,
                snapshot,
                map_id,
                input_path,
                candidate_file,
                dry_run=False,
                registry_path=paths.identity_registry.resolve(),
                authority_path=paths.authority.resolve(),
                authority_ref_policy=overlay,
                allow_authorized_batch_drift=True,
            )
            report = {
                **base_report,
                "status": "CANDIDATE_WRITTEN",
                "walkable_tile_count": len(safe),
                "component_sizes": [len(component) for component in components],
                "monster_spawn_count": len(placement_input["layers"]["monster_spawn"]),
                "boss_spawn_count": len(placement_input["layers"]["boss_spawn"]),
                "placement_count": len(entries),
                "selected": [{"monster_id": row["monster_id"], "canonical_name": row["canonical_name"], "classification": row["canonical_classification"], "placement_kind": row["placement_kind"]} for row in identities],
                "skipped": skipped,
                "candidate_sha256": hashlib.sha256(candidate_file.read_bytes()).hexdigest(),
                "non_target_fields_unchanged": bool(write_result["non_target_fields_unchanged"]),
            }
            if inheritance_evidence is not None:
                report["pool_inheritance"] = inheritance_evidence
            report["replaced_source_spawn_count"] = sum(
                len(layers.get(layer, [])) for layer in TARGET_LAYERS
            )
            (map_plan_dir / "placement_report.json").write_bytes(_json_bytes(report))
            reports.append(report)
            written_candidates += 1
        manifest = {
            "schema_version": 1,
            "contract_id": CONTRACT_ID,
            "generated_by": "tools/map_editor/build_map_monster_placement_batch.py",
            "inputs": {
                "authority_sha256": _sha(authority_raw),
                "identity_registry_sha256": _sha(identity_raw),
                "current_monster_library_sha256": _sha(catalog_raw),
                "execution_policy_sha256": _sha(policy_raw),
            },
            "summary": {
                "formal_map_count": len(reports),
                "candidate_map_count": written_candidates,
                "preserved_map_count": sum(row["status"] == "PRESERVE_USER_ACCEPTED" for row in reports),
                "transition_backfill_map_count": sum(row["status"] == "TRANSITION_BACKFILL_REQUIRED" for row in reports),
                "no_fixed_spawn_map_count": sum(row["status"] == "NO_FIXED_SPAWN" for row in reports),
                "placement_entry_count": sum(int(row.get("placement_count", 0)) for row in reports),
                "skipped_token_count": sum(len(row.get("skipped", [])) for row in reports),
            },
            "maps": reports,
        }
        (plan_stage / "manifest.json").write_bytes(_json_bytes(manifest))
        if paths.write:
            os.replace(plan_stage, plan_output)
            os.replace(candidate_stage, candidate_output)
        else:
            shutil.rmtree(plan_stage)
            shutil.rmtree(candidate_stage)
        return manifest
    except Exception:
        shutil.rmtree(plan_stage, ignore_errors=True)
        shutil.rmtree(candidate_stage, ignore_errors=True)
        raise


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-editor-root", type=Path, required=True)
    parser.add_argument("--snapshot", type=Path, required=True)
    parser.add_argument("--authority", type=Path, required=True)
    parser.add_argument("--identity-registry", type=Path, required=True)
    parser.add_argument("--catalog", type=Path, required=True)
    parser.add_argument("--policy", type=Path, required=True)
    parser.add_argument("--plan-output", type=Path, required=True)
    parser.add_argument("--candidate-output", type=Path, required=True)
    parser.add_argument(
        "--base-manifest",
        type=Path,
        help="existing batch manifest whose 60 unchanged candidate rows are preserved verbatim",
    )
    parser.add_argument("--write", action="store_true")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    try:
        manifest = build(args)
    except (BatchError, OSError, ValueError, json.JSONDecodeError, WRITER.SafeWriterError, PLANNER.PlannerError) as exc:
        print(f"BLOCKED: {exc}")
        return 2
    print(json.dumps(manifest, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
