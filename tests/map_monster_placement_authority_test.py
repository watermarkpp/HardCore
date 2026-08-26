#!/usr/bin/env python3
"""Static contract tests for the Phase 0 map monster authority manifest."""

from __future__ import annotations

import hashlib
import importlib.util
import json
from collections import Counter
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT_PATH = ROOT / "tools/map_editor/build_map_monster_placement_authority.py"
MANIFEST_PATH = ROOT / "assets/data/map_design/map_monster_placement_authority_v2.json"
SOURCE_PATH = ROOT / "docs/map_design/HardCore_当前67张地图_怪物分布表_V2_按新结构.txt"
ORIGINAL_USER_SOURCE = (
    r"C:\Users\Administrator\Desktop\HardCore_当前67张地图_怪物分布表_V2_按新结构.txt"
)
CATALOG_PATH = ROOT / "assets/data/runtime/canonical_monster_catalog.json"
IDENTITY_PATH = ROOT / "assets/data/map_design/map_identity_registry.json"

SPEC = importlib.util.spec_from_file_location(
    "map_monster_placement_authority_generator", SCRIPT_PATH
)
assert SPEC is not None and SPEC.loader is not None
GENERATOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(GENERATOR)


def load(path: Path) -> dict[str, object]:
    value = json.loads(path.read_text(encoding="utf-8-sig"))
    assert isinstance(value, dict), path
    return value


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def main() -> None:
    assert SOURCE_PATH.is_file(), SOURCE_PATH
    manifest = load(MANIFEST_PATH)
    catalog = load(CATALOG_PATH)
    identity = load(IDENTITY_PATH)

    assert manifest["schema_version"] == 2
    assert manifest["manifest_id"] == "hardcore.map_monster_placement_authority.v2"
    assert manifest["contract_id"] == "hardcore.map_monster_placement_authority.v2"
    assert manifest["source_sha256"] == sha256(SOURCE_PATH)
    assert manifest["source_sha256"] == "F3B8593DF24BE54B8C9781E5F625E6B6FF3776066C818A77568D0CE9357BEB9B"
    assert manifest["source_file"] == SOURCE_PATH.name
    assert manifest["provenance"]["original_user_path"] == ORIGINAL_USER_SOURCE
    assert manifest["provenance"]["relocated_source_path"] == SOURCE_PATH.relative_to(ROOT).as_posix()

    source_files = manifest["source_files"]
    assert isinstance(source_files, dict)
    for key, path in (
        ("placement_source", SOURCE_PATH),
        ("map_identity_registry", IDENTITY_PATH),
        ("canonical_monster_catalog", CATALOG_PATH),
    ):
        row = source_files[key]
        assert isinstance(row, dict), key
        assert row["sha256"] == sha256(path), (key, row["sha256"], sha256(path))
        assert not str(row["path"]).startswith(("C:\\", "/")), row["path"]
    assert source_files["placement_source"]["path"] == SOURCE_PATH.relative_to(ROOT).as_posix()

    maps = manifest["maps"]
    records = manifest["token_records"]
    unresolved = manifest["unresolved_blocked"]
    assert isinstance(maps, list) and len(maps) == 67
    assert isinstance(records, list) and len(records) == 401
    assert isinstance(unresolved, list) and len(unresolved) == 5
    assert manifest["summary"] == {
        **manifest["summary"],
        "formal_map_count": 67,
        "source_map_count": 67,
        "token_occurrence_count": 401,
        "monster_token_occurrence_count": 400,
        "unique_token_count": 120,
        "unique_monster_token_count": 119,
        "unresolved_blocked_occurrence_count": 5,
        "unresolved_blocked_unique_token_count": 5,
        "auto_placement_allowed_occurrence_count": 299,
        "auto_placement_blocked_occurrence_count": 102,
    }

    identity_by_map = {str(row["map_id"]): row for row in identity["maps"]}
    catalog_by_id = {
        int(row["monster_id"]): row for row in catalog["entries"]
    }
    assert len(identity_by_map) == 67
    assert len(catalog_by_id) == 156

    required_kinds = {
        "unique_exact_monster_id",
        "canonical_variant_group",
        "special_npc_system",
        "intentionally_retired_excluded",
        "intentionally_editor_excluded",
        "unresolved_blocked",
    }
    status_counts = Counter()
    kind_counts = Counter()
    seen_occurrences = []
    for map_row in maps:
        map_id = str(map_row["map_id"])
        assert map_id in identity_by_map, map_id
        identity_row = identity_by_map[map_id]
        assert map_row["runtime_id"] == identity_row["runtime_map_id"]
        assert map_row["runtime_map_id"] == map_row["runtime_id"]
        assert map_row["legacy_map_id"] == identity_row["legacy_map_id"]
        assert map_row["legacy_runtime_id"] == identity_row["legacy_runtime_map_id"]
        map_tokens = map_row["tokens"]
        assert isinstance(map_tokens, list)
        assert len(map_tokens) == len(map_row["monster_tokens"]) + sum(
            1 for token in map_tokens if token["status"] == "not_a_monster"
        )
        for token in map_tokens:
            assert token["map_id"] == map_id
            assert token["runtime_id"] == map_row["runtime_id"]
            assert token["raw_token"] == token["normalized_token"]
            assert token["resolution_kind"] in required_kinds
            assert isinstance(token["resolved_monster_ids"], list)
            assert isinstance(token["resolved_variant_codes"], list)
            assert isinstance(token["auto_placement_allowed"], bool)
            assert isinstance(token["auto_placement_status"], str)
            status_counts[str(token["status"])] += 1
            kind_counts[str(token["resolution_kind"])] += 1
            seen_occurrences.append(
                (map_id, token["source_line"], token["raw_token"])
            )
            for monster_id in token["resolved_monster_ids"]:
                # Exact and explicit-variant resolutions may only point at
                # the active canonical runtime universe.
                assert monster_id not in {33, 183, 241}, token
                assert monster_id not in {59, 78, 157, 161}, token
                assert monster_id in catalog_by_id, monster_id
                assert catalog_by_id[monster_id]["runtime_allowed"] is True
                assert catalog_by_id[monster_id]["editor_placement"]["allowed"] is True
            if token["status"] == "resolved":
                assert token["placement_allowed"] is True
            elif token["status"] in {"excluded", "blocked"}:
                assert token["placement_allowed"] is False

            has_special_route = bool(token.get("system_code")) or token.get(
                "classification"
            ) in {"special", "non_hostile"}
            if has_special_route:
                assert token["auto_placement_allowed"] is False, token
                assert token["auto_placement_status"] == "SPECIAL_SYSTEM_REQUIRED", token
            elif token["status"] == "excluded":
                assert token["auto_placement_allowed"] is False
                assert token["auto_placement_status"] == "INTENTIONALLY_EXCLUDED"
            elif token["status"] == "blocked":
                assert token["auto_placement_allowed"] is False
                assert token["auto_placement_status"] == "UNRESOLVED_BLOCKED"
            elif token["resolution_kind"] == "unique_exact_monster_id" and token[
                "classification"
            ] == "ordinary":
                assert token["auto_placement_allowed"] is True
                assert token["auto_placement_status"] == "AUTO_PLACEMENT_ALLOWED"
            elif token["resolution_kind"] == "canonical_variant_group" and token[
                "classification"
            ] in {"ordinary", "elite", "boss"}:
                assert token["auto_placement_allowed"] is True
                assert token["auto_placement_status"] == "AUTO_PLACEMENT_ALLOWED"
            else:
                assert token["auto_placement_allowed"] is False
                assert token["auto_placement_status"] == "EXPLICIT_PLACEMENT_REQUIRED"

    assert len(seen_occurrences) == len(records)
    assert status_counts == Counter(
        {"resolved": 391, "excluded": 4, "blocked": 5, "not_a_monster": 1}
    )
    assert kind_counts == Counter(
        {
            "unique_exact_monster_id": 352,
            "canonical_variant_group": 32,
            "special_npc_system": 8,
            "intentionally_retired_excluded": 4,
            "unresolved_blocked": 5,
        }
    )
    auto_status_counts = Counter(
        str(token["auto_placement_status"]) for token in records
    )
    assert auto_status_counts == Counter(
        {
            "AUTO_PLACEMENT_ALLOWED": 299,
            "EXPLICIT_PLACEMENT_REQUIRED": 53,
            "INTENTIONALLY_EXCLUDED": 4,
            "SPECIAL_SYSTEM_REQUIRED": 45,
        }
    )

    leak_validation = manifest["leak_validation"]
    assert leak_validation == {
        "editor_placement_forbidden_ids": [59, 78, 157, 161],
        "resolved_monster_id_leaks": [],
        "auto_placement_id_leaks": [],
        "passed": True,
    }
    assert not set(leak_validation["editor_placement_forbidden_ids"]).intersection(
        manifest["summary"]["resolved_monster_ids"]
    )

    by_raw = {
        str(token["raw_token"]): token
        for token in records
        if token["raw_token"] not in {"尸王"}
    }
    assert by_raw["鸡"]["resolution_kind"] == "intentionally_retired_excluded"
    assert by_raw["鹿"]["resolution_kind"] == "intentionally_retired_excluded"
    assert by_raw["弓箭护卫"]["system_code"] == "npc_guard.archer_guard"
    assert by_raw["弓箭护卫"]["auto_placement_allowed"] is False
    assert by_raw["弓箭护卫"]["auto_placement_status"] == "SPECIAL_SYSTEM_REQUIRED"
    assert by_raw["恶魔弓箭手"]["resolved_monster_ids"] == [194]
    assert by_raw["恶魔弓箭手"]["auto_placement_allowed"] is False
    assert by_raw["恶魔弓箭手"]["auto_placement_status"] == "SPECIAL_SYSTEM_REQUIRED"
    assert by_raw["僵尸（多种外观形态）"]["resolved_monster_ids"] == [
        79,
        81,
        83,
        85,
        87,
    ]
    assert by_raw["祖玛弓箭手（极品变体）"]["resolved_monster_ids"] == [152]
    assert by_raw["祖玛雕像（极品变体）"]["resolved_monster_ids"] == [155]
    assert by_raw["祖玛卫士（极品变体）"]["resolved_monster_ids"] == [
        158,
        159,
    ]
    assert by_raw["宝箱怪"]["resolved_monster_ids"] == list(range(226, 235))
    assert by_raw["宝箱怪"]["auto_placement_allowed"] is False
    assert by_raw["宝箱怪"]["auto_placement_status"] == "SPECIAL_SYSTEM_REQUIRED"
    assert by_raw["半兽勇士（未知暗殿变体）"]["resolved_monster_ids"] == [39]
    assert by_raw["骷髅精灵（未知暗殿变体）"]["resolved_monster_ids"] == [57]
    assert by_raw["尸王（未知暗殿变体）"]["resolved_monster_ids"] == [90]
    assert by_raw["邪恶钳虫（未知暗殿变体）"]["resolved_monster_ids"] == [121]
    assert by_raw["白野猪（未知暗殿变体）"]["resolved_monster_ids"] == [137]
    assert by_raw["邪恶毒蛇（未知暗殿变体）"]["resolved_monster_ids"] == [142]
    assert by_raw["沃玛教主（未知暗殿变体）"]["resolved_monster_ids"] == [77]
    for raw in (
        "鸡（未知暗殿变体）",
        "鹿（未知暗殿变体）",
        "稻草人（未知暗殿变体）",
        "巨型多角虫（未知暗殿变体）",
        "沃玛卫士（未知暗殿变体）",
    ):
        assert by_raw[raw]["resolution_kind"] == "unresolved_blocked", raw
        assert by_raw[raw]["auto_placement_allowed"] is False, raw
        assert by_raw[raw]["auto_placement_status"] == "SPECIAL_SYSTEM_REQUIRED", raw
    for token in records:
        if str(token["raw_token"]).endswith("（未知暗殿变体）"):
            assert token["auto_placement_allowed"] is False, token
            assert token["auto_placement_status"] == "SPECIAL_SYSTEM_REQUIRED", token

    # Exact canonical names for editor-disabled identities fail closed too,
    # even when runtime_allowed remains true for the internal subtype.
    source_refs = {
        "path": "canonical_monster_catalog.json",
        "sha256": "catalog",
    }
    for forbidden_id in (59, 78, 157, 161):
        exact_name = str(catalog_by_id[forbidden_id]["canonical_name"])
        exact = GENERATOR.resolve_token(
            {
                "raw_token": exact_name,
                "normalized_token": exact_name,
                "source_line": 1,
                "source_category": "普通刷新",
                "source_category_role": "ordinary",
                "source_token_index": 1,
            },
            by_name=GENERATOR.canonical_name_index(catalog),
            by_base=GENERATOR.variant_index(GENERATOR.canonical_name_index(catalog)),
            retired_by_name={},
            catalog_ref=source_refs,
            classification_ref=source_refs,
            vanilla_ref=source_refs,
        )
        assert exact["status"] == "excluded", exact
        assert exact["resolved_monster_ids"] == [], exact
        assert exact["auto_placement_allowed"] is False, exact

    # Rebuilding from the same authorities must exactly reproduce the tracked
    # structure.  This is the same operation used by the CLI --check.
    rebuilt = GENERATOR.build_manifest(
        repo=ROOT,
        source_path=SOURCE_PATH,
        identity_path=IDENTITY_PATH,
        catalog_path=CATALOG_PATH,
        classification_path=ROOT / "assets/data/canonical_monster_classification_v1.json",
        vanilla_path=ROOT / "assets/data/vanilla_176/monsters.json",
        policy_path=ROOT / "assets/data/canonical_monster_catalog_policy_v1.json",
    )
    assert rebuilt == manifest

    print(
        "MAP_MONSTER_PLACEMENT_AUTHORITY_PASS "
        "maps=67 tokens=401 monster_tokens=400 exact=352 "
        "variant_groups=32 special_system=8 excluded=4 blocked=5 editor_quarantine=4"
    )


if __name__ == "__main__":
    main()
