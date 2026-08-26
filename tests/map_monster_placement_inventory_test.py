#!/usr/bin/env python3
"""Static contract tests for the Phase 2 map placement inventory."""

from __future__ import annotations

import copy
import hashlib
import importlib.util
import json
import re
from collections import Counter
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
SCRIPT_PATH = ROOT / "tools/map_editor/build_map_monster_placement_inventory.py"
INVENTORY_PATH = ROOT / "assets/data/map_design/map_monster_placement_inventory_v1.json"
IDENTITY_PATH = ROOT / "assets/data/map_design/map_identity_registry.json"
AUTHORITY_PATH = ROOT / "assets/data/map_design/map_monster_placement_authority_v2.json"
BACKFILL_PATH = ROOT / "assets/data/map_design/map_monster_spawn_backfill_inventory_v1.json"
RELEASE_PATH = ROOT / "assets/data/runtime/map_editor/map_runtime_release_registry.json"
SNAPSHOT_PATH = ROOT / "assets/data/map_design/map_authoring_snapshot_20260826.json"
DESIGN_CATALOG_PATH = ROOT / "assets/data/map_design/map_design_catalog.json"
BLANK_TEMPLATES_PATH = ROOT / "assets/data/map_design/map_blank_templates.json"

SPEC = importlib.util.spec_from_file_location(
    "map_monster_placement_inventory_generator", SCRIPT_PATH
)
assert SPEC is not None and SPEC.loader is not None
GENERATOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(GENERATOR)

HEX64_RE = re.compile(r"^[0-9A-F]{64}$")
TRANSITION_KEYS = set(GENERATOR.TRANSITION_DEBT_MAP_KEYS)
STRUCTURE_KEYS = set(GENERATOR.STRUCTURE_ONLY_MAP_KEYS)


def load(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8-sig"))
    assert isinstance(value, dict), path
    return value


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def assert_no_host_paths(value: Any, path: str = "inventory") -> None:
    if isinstance(value, dict):
        for key, child in value.items():
            assert_no_host_paths(child, f"{path}.{key}")
    elif isinstance(value, list):
        for index, child in enumerate(value):
            assert_no_host_paths(child, f"{path}[{index}]")
    elif isinstance(value, str):
        assert not re.match(r"^(?:[A-Za-z]:[\\/]|/|\\\\)", value), (
            path,
            value,
        )


def main() -> None:
    inventory = load(INVENTORY_PATH)
    identity = load(IDENTITY_PATH)
    authority = load(AUTHORITY_PATH)
    backfill = load(BACKFILL_PATH)
    release = load(RELEASE_PATH)

    assert inventory["schema_version"] == 1
    assert inventory["inventory_id"] == "hardcore.map_monster_placement_inventory.v1"
    assert inventory["contract_id"] == inventory["inventory_id"]
    assert inventory["generated_by"] == (
        "tools/map_editor/build_map_monster_placement_inventory.py"
    )
    assert_no_host_paths(inventory)
    assert inventory["policy"]["runtime_spawn_counts_role"] == (
        "published_runtime_observation_not_authoring_input"
    )
    assert inventory["policy"][
        "published_runtime_release_does_not_request_redeployment"
    ] is True

    expected_inputs = {
        "authoring_snapshot": SNAPSHOT_PATH,
        "placement_authority": AUTHORITY_PATH,
        "transition_backfill_inventory": BACKFILL_PATH,
        "map_identity_registry": IDENTITY_PATH,
        "runtime_release_registry": RELEASE_PATH,
        "map_design_catalog": DESIGN_CATALOG_PATH,
        "map_blank_templates": BLANK_TEMPLATES_PATH,
    }
    inputs = inventory["inputs"]
    assert isinstance(inputs, dict)
    for key, path in expected_inputs.items():
        row = inputs[key]
        assert row["path"] == path.relative_to(ROOT).as_posix()
        assert row["sha256"] == sha256(path)
        assert row["byte_size"] == path.stat().st_size
        assert row["hash_normalization"] == "raw_bytes"
        assert not str(row["path"]).startswith(("C:\\", "/", "\\\\"))

    identity_rows = identity["maps"]
    assert identity["formal_map_count"] == 67
    assert len(identity_rows) == 67
    identity_by_key = {row["legacy_map_id"]: row for row in identity_rows}
    assert len(identity_by_key) == 67

    release_rows = release["maps"]
    release_by_registry_key = {row["map_key"]: row for row in release_rows}
    assert len(release_by_registry_key) == 12
    identity_by_map_id = {row["map_id"]: row for row in identity_rows}
    release_by_key = {}
    for release_row in release_rows:
        registry_key = release_row["map_key"]
        ident = identity_by_key.get(registry_key) or identity_by_map_id.get(registry_key)
        assert ident is not None, registry_key
        normalized_key = ident["legacy_map_id"]
        assert normalized_key not in release_by_key, normalized_key
        release_by_key[normalized_key] = release_row
    runtime_file_refs = inputs["runtime_release_files"]
    assert set(runtime_file_refs) == set(release_by_key)
    for map_key, release_row in release_by_key.items():
        registry_key = release_row["map_key"]
        runtime_path = ROOT / Path(runtime_row_path(release_row, registry_key))
        ref = runtime_file_refs[map_key]
        assert ref["path"] == runtime_path.relative_to(ROOT).as_posix()
        assert ref["file_sha256"] == sha256(runtime_path)
        runtime = load(runtime_path)
        assert ref["build_sha256"] == runtime["build_sha256"].upper()
        assert ref["approved_build_sha256"] == release_row["approved_build_sha256"].upper()
        assert ref["hash_match"] is True

    canonical_release = release_by_registry_key["fengmo_purgatory_corridor"]
    canonical_identity = identity_by_map_id["fengmo_purgatory_corridor"]
    assert canonical_release["runtime_map_id"] == canonical_identity["runtime_map_id"]
    canonical_inventory_row = next(
        row for row in inventory["maps"] if row["map_key"] == "gmhl_purgatory_corridor"
    )
    assert canonical_inventory_row["runtime_exists"] is True
    assert canonical_inventory_row["formal_playable"] is True
    assert canonical_inventory_row["runtime"]["registry_map_key"] == (
        "fengmo_purgatory_corridor"
    )
    assert canonical_inventory_row["runtime"]["registry_key_kind"] == "formal_canonical"
    assert canonical_inventory_row["runtime"]["normalized_map_key"] == (
        "gmhl_purgatory_corridor"
    )
    assert canonical_inventory_row["runtime"]["runtime_map_id"] == 914007
    assert canonical_inventory_row["runtime"]["redeployment_required"] is False
    assert canonical_inventory_row["runtime"]["spawn_counts_role"] == (
        "published_runtime_observation_not_authoring_input"
    )
    assert canonical_inventory_row["placement_state"] == "PRESERVE"
    assert canonical_inventory_row["requires_geometry_validation"] is False
    assert canonical_inventory_row["placement_reasons"] == [
        "approved_formal_runtime_contains_published_monster_layer",
        "published_runtime_layer_requires_no_redeployment",
    ]

    def expect_inventory_error(callback: Any) -> None:
        try:
            callback()
        except GENERATOR.InventoryError:
            return
        raise AssertionError("expected InventoryError")

    wrong_id_release = copy.deepcopy(release)
    next(
        row
        for row in wrong_id_release["maps"]
        if row["map_key"] == "fengmo_purgatory_corridor"
    )["runtime_map_id"] = 914006
    expect_inventory_error(
        lambda: GENERATOR._validate_release_registry(
            wrong_id_release, identity_by_key
        )
    )

    unknown_key_release = copy.deepcopy(release)
    unknown_key_release["maps"].append(
        {
            "approval_revision": 1,
            "approval_source": "test",
            "approved_build_sha256": "0" * 64,
            "display_name": "unknown",
            "map_key": "unknown_map_key",
            "release_state": "implemented_playable",
            "runtime_map_id": 123456,
            "runtime_path": "res://assets/data/runtime/map_editor/unknown_map_key.runtime.json",
        }
    )
    expect_inventory_error(
        lambda: GENERATOR._validate_release_registry(
            unknown_key_release, identity_by_key
        )
    )

    ambiguous_release = copy.deepcopy(release)
    ambiguous_release["maps"].append(
        {
            "approval_revision": 1,
            "approval_source": "test",
            "approved_build_sha256": "0" * 64,
            "display_name": "duplicate normalized binding",
            "map_key": "world_bich_province",
            "release_state": "implemented_playable",
            "runtime_map_id": 910001,
            "runtime_path": "res://assets/data/runtime/map_editor/world_bich_province.runtime.json",
        }
    )
    expect_inventory_error(
        lambda: GENERATOR._validate_release_registry(
            ambiguous_release, identity_by_key
        )
    )

    maps = inventory["maps"]
    assert isinstance(maps, list) and len(maps) == 67
    assert {row["map_key"] for row in maps} == set(identity_by_key)
    assert {row["map_id"] for row in maps} == {
        row["map_id"] for row in identity_rows
    }

    authority_by_map = Counter()
    for record in authority["token_records"]:
        authority_by_map[record["map_id"]] += 1
    assert sum(authority_by_map.values()) == 401

    for row in maps:
        map_key = row["map_key"]
        ident = identity_by_key[map_key]
        assert row["map_id"] == ident["map_id"]
        assert row["display_name"] == ident["display_name"]
        assert row["runtime_id"] == ident["runtime_map_id"]
        assert row["legacy_runtime_id"] == ident["legacy_runtime_map_id"]
        assert isinstance(row["map_type"], str) and row["map_type"]
        assert row["map_type_evidence"]["state"] in {
            "AUTHORITATIVE",
            "EXPLICIT_FALLBACK_POLICY",
        }

        for key in (
            "editor_exists",
            "runtime_exists",
            "formal_playable",
        ):
            assert isinstance(row[key], bool), (map_key, key)
        assert row["editor_exists"] is True
        assert row["editor"]["exists"] is True
        assert row["editor"]["path"] == (
            f"map_editor_workspace/{map_key}/{map_key}.editor.json"
        )
        assert HEX64_RE.fullmatch(row["editor"]["source_sha256"])
        assert row["editor_spawn_counts"] == row["editor"]["spawn_counts"]
        assert set(row["editor_spawn_counts"]) == {
            "monster_spawn",
            "boss_spawn",
            "total",
        }
        assert row["editor_spawn_counts"]["total"] == (
            row["editor_spawn_counts"]["monster_spawn"]
            + row["editor_spawn_counts"]["boss_spawn"]
        )

        runtime_counts = row["runtime_spawn_counts"]
        assert set(runtime_counts) == {
            "state",
            "monster_spawn",
            "boss_spawn",
            "total",
        }
        if map_key in release_by_key:
            assert row["runtime_exists"] is True
            assert row["formal_playable"] is True
            assert runtime_counts["monster_spawn"] is not None
            assert runtime_counts["boss_spawn"] is not None
            assert runtime_counts["total"] == (
                runtime_counts["monster_spawn"] + runtime_counts["boss_spawn"]
            )
            assert row["runtime"]["hash_match"] is True
            assert row["runtime"]["registry_map_key"] == release_by_key[map_key]["map_key"]
            assert row["runtime"]["normalized_map_key"] == map_key
            assert row["runtime"]["redeployment_required"] is False
            assert row["runtime"]["spawn_counts_role"] == (
                "published_runtime_observation_not_authoring_input"
            )
            if runtime_counts["total"] == 0:
                # A published runtime with no monster/boss layer must not be
                # mistaken for completed monster placement.
                assert row["placement_state"] != "PRESERVE"
        else:
            assert row["runtime_exists"] is False
            assert row["formal_playable"] is False
            assert runtime_counts["monster_spawn"] is None
            assert runtime_counts["boss_spawn"] is None
            assert runtime_counts["total"] is None
            assert row["runtime"]["state"] == "NOT_IN_RELEASE_REGISTRY"

        assert row["authoring_state"] in {
            "NORMAL_EDITOR_AUTHORITY",
            "TRANSITION_DEBT",
            "STRUCTURE_ONLY",
            "NOT_READY",
        }
        assert row["placement_state"] in {
            "READY_FOR_AUTO_PLACEMENT",
            "READY_FOR_PLANNER_VALIDATION",
            "SOURCE_REQUIRED",
            "PLACEMENT_BLOCKED",
            "PRESERVE",
        }

        counts = row["authority_counts"]
        assert counts["token_occurrences"] == authority_by_map[row["map_id"]]
        assert counts["resolved"] + counts["excluded"] + counts["blocked"] + counts[
            "not_a_monster"
        ] == counts["token_occurrences"]
        assert counts["allowed"] + counts["explicit"] + counts["special"] + counts[
            "excluded"
        ] == counts["token_occurrences"]
        assert counts["allowed"] >= 0
        assert counts["explicit"] >= 0
        assert counts["special"] >= 0
        assert counts["blocked"] >= 0

        deferred = row["deferred_authority_counts"]
        assert deferred == {
            "explicit": counts["explicit"],
            "special": counts["special"],
            "blocked": counts["blocked"],
        }

        walkable = row["walkable_evidence"]
        assert walkable["state"] == "UNKNOWN"
        assert walkable["evidence"] == "collision_contract_available"
        assert walkable["evidence_code"] == "collision_contract_available"
        assert walkable["calculation_state"] == "unknown"
        assert walkable["safe_to_auto_place"] is False
        assert "collision" in walkable["collision_evidence"]["available_layers"]
        assert HEX64_RE.fullmatch(walkable["collision_evidence"]["collision_sha256"])

        if map_key in TRANSITION_KEYS:
            assert row["authoring_state"] == "TRANSITION_DEBT"
            assert row["placement_state"] == "PLACEMENT_BLOCKED"
            assert row["requires_geometry_validation"] is False
            assert row["transition_backfill"]["status"] == "BLOCKED"
            assert row["transition_backfill"]["proof"]["candidate_binding_matches"] is False
            assert set(
                row["transition_backfill"]["blocker_codes"]
            ) >= {
                "ground_manifest_sha256_mismatch",
                "ground_state_sha256_mismatch",
                "candidate_binding_document_sha256_mismatch",
            }
        elif (
            row["runtime_exists"]
            and row["formal_playable"]
            and row["runtime_spawn_counts"]["total"] > 0
        ):
            # An approved formal runtime with an existing monster layer is
            # evidence of completed/published placement, never a new route.
            assert row["placement_state"] == "PRESERVE"
            assert row["requires_geometry_validation"] is False
            assert (
                "approved_formal_runtime_contains_published_monster_layer"
                in row["placement_reasons"]
            )
            assert (
                "published_runtime_layer_requires_no_redeployment"
                in row["placement_reasons"]
            )
        elif map_key in STRUCTURE_KEYS:
            assert row["authoring_state"] == "STRUCTURE_ONLY"
            assert row["editor_spawn_counts"]["total"] == 0
            assert row["runtime_spawn_counts"]["total"] == 0
            if counts["allowed"]:
                assert row["placement_state"] == "READY_FOR_AUTO_PLACEMENT"
            else:
                assert row["placement_state"] == "READY_FOR_PLANNER_VALIDATION"
            assert row["requires_geometry_validation"] is True
        else:
            assert row["authoring_state"] == "NORMAL_EDITOR_AUTHORITY"
            if counts["allowed"]:
                assert row["placement_state"] == "READY_FOR_AUTO_PLACEMENT"
                assert row["requires_geometry_validation"] is True
            elif counts["explicit"]:
                assert row["placement_state"] == "READY_FOR_PLANNER_VALIDATION"
                assert row["requires_geometry_validation"] is True
            elif counts["blocked"]:
                assert row["placement_state"] == "PLACEMENT_BLOCKED"
                assert row["requires_geometry_validation"] is False
            else:
                assert row["placement_state"] == "SOURCE_REQUIRED"
                assert row["requires_geometry_validation"] is False
            # A missing formal runtime is not an editor-authoring blocker.
            # quest_1 is the deliberate exception because its authority has
            # unresolved blocked tokens, independently of runtime existence.
            if not row["runtime_exists"] and counts["blocked"] == 0:
                assert row["placement_state"] != "PLACEMENT_BLOCKED"

    summary = inventory["summary"]
    assert summary["formal_map_count"] == 67
    assert summary["source_map_count"] == 67
    assert summary["editor_exists_count"] == 67
    assert summary["runtime_exists_count"] == 12
    assert summary["formal_playable_count"] == 12
    assert summary["transition_debt_count"] == 5
    assert summary["structure_only_count"] == 6
    assert summary["ready_for_auto_placement_count"] == 52
    assert summary["ready_for_planner_validation_count"] == 7
    assert summary["source_required_count"] == 1
    assert summary["placement_blocked_count"] == 6
    assert summary["preserve_count"] == 1
    assert summary["authoring_state_counts"] == {
        "NORMAL_EDITOR_AUTHORITY": 56,
        "STRUCTURE_ONLY": 6,
        "TRANSITION_DEBT": 5,
    }
    assert summary["placement_state_counts"] == {
        "PLACEMENT_BLOCKED": 6,
        "PRESERVE": 1,
        "READY_FOR_AUTO_PLACEMENT": 52,
        "READY_FOR_PLANNER_VALIDATION": 7,
        "SOURCE_REQUIRED": 1,
    }
    assert sum(row["placement_state"] == "PRESERVE" for row in maps) == 1
    assert summary["walkable_state_counts"] == {"UNKNOWN": 67}
    assert summary["editor_spawn_counts"] == {
        "monster_spawn": 0,
        "boss_spawn": 0,
        "total": 0,
    }
    assert summary["runtime_spawn_counts"] == {
        "monster_spawn": 115,
        "boss_spawn": 3,
        "total": 118,
    }
    assert summary["authority_counts"] == {
        "allowed": 299,
        "blocked": 5,
        "excluded": 4,
        "explicit": 53,
        "not_a_monster": 1,
        "resolved": 391,
        "special": 45,
        "token_occurrences": 401,
    }

    rebuilt = GENERATOR.build_inventory(repo=ROOT)
    assert rebuilt == inventory

    print(
        "MAP_MONSTER_PLACEMENT_INVENTORY_PASS "
        "maps=67 editor=67 runtime=12 playable=12 "
        "transition_debt=5 structure_only=6 ready=52 "
        "planner_validation=7 source_required=1 preserve=1 placement_blocked=6 "
        "runtime_spawns=118"
    )


def runtime_row_path(row: dict[str, Any], map_key: str) -> str:
    path = row["runtime_path"]
    assert path == f"res://assets/data/runtime/map_editor/{map_key}.runtime.json"
    return path.removeprefix("res://")


if __name__ == "__main__":
    main()
