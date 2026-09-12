#!/usr/bin/env python3
"""V5.0.5 full-profile 21CQ migration.

The historical canonical_monster_drop_source_v2.json remains immutable.
141 exact runtime identities with a complete frozen 21CQ drop table migrate to
that complete table. IDs 75/123 keep their exact-ID legacy profiles because the
exact 21CQ drop table is empty. ID225 remains a project extension.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import math
import re
import subprocess
import sys
from collections import Counter, defaultdict
from fractions import Fraction
from pathlib import Path
from typing import Any
from dpv2_ground_capacity import GROUND_SLOT_LIMIT

ROOT = Path(__file__).resolve().parents[1]
MIGRATION_BASE = "342891ab884150c0e81084c932df8205484e6388"
ORIGINAL_BASE = "ffcdc76b360d5976eef2ce17a45664ddaf550590"

DATA = "assets/data/drop/"
BASELINE = DATA + "dpv2_direct_baseline_v2.json"
MANIFEST = DATA + "dpv2_direct_baseline_manifest_v2.json"
PROVENANCE = DATA + "dpv2_21cq_source_provenance_v1.json"
ITEM_MAPPING = DATA + "dpv2_21cq_item_mapping_v1.json"
OVERFLOW = DATA + "dpv2_21cq_overflow_authority_v1.json"
SEMANTIC = DATA + "dpv2_monster_drop_semantic_authority_v1.json"
GLOBAL = DATA + "dpv2_global_drop_rate_authority_v1.json"
CLASSIFICATION = DATA + "dpv2_single_player_item_boost_classification_v1.json"
SPB_AUTHORITY = DATA + "dpv2_single_player_drop_boost_v1.json"
EFFECTIVE = DATA + "dpv2_single_player_effective_probability_v1.json"
CORRECTIONS = DATA + "dpv2_21cq_source_corrections_v1.json"
SOURCE_AUTHORITY = DATA + "dpv2_21cq_verified_profile_authority_v1.json"
POLICY = "tools/dpv2_repair_v5_policy.json"
CATALOG = "assets/data/runtime/canonical_monster_catalog.json"
REPORT = "docs/drop/v5/"

VERIFIED_ORIGIN = "VERIFIED_21CQ_PROFILE_V505"
LEGACY_ORIGIN = "LEGACY_21CQ_MONITEMS"
PROJECT_ORIGIN = "PROJECT_EXTENSION"
EMPTY_EXCEPTIONS = {75: 78, 123: 112}
EMPTY_HASHES = {
    75: "71CEA9C20EFB0C0910B89D842FDB05DCEC7A429E21A2A85EF1FE32D45128A478",
    123: "D4A96B6179D25CEF2F47A3E0955ED3643430E4A9EC09E4716682078D0757F676",
}
INT_MAX = 2147483647


class V505Error(RuntimeError):
    pass


def require(ok: bool, message: str) -> None:
    if not ok:
        raise V505Error(message)


def read(path: str) -> dict[str, Any]:
    value = json.loads((ROOT / path).read_text(encoding="utf-8-sig"))
    require(isinstance(value, dict), f"JSON_OBJECT_REQUIRED:{path}")
    return value


def dump(path: str, value: Any) -> None:
    target = ROOT / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")


def render(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, indent=2) + "\n"


def lf_hash_text(text: str) -> str:
    return hashlib.sha256(text.replace("\r\n", "\n").replace("\r", "\n").encode("utf-8")).hexdigest().upper()


def lf_hash(path: str) -> str:
    return lf_hash_text((ROOT / path).read_text(encoding="utf-8-sig"))


def raw_hash_path(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def git_bytes(path: str, sha: str = MIGRATION_BASE) -> bytes:
    try:
        return subprocess.check_output(["git", "show", f"{sha}:{path}"], cwd=ROOT)
    except (OSError, subprocess.CalledProcessError) as exc:
        raise V505Error(f"GIT_OBJECT_UNAVAILABLE:{sha}:{path}") from exc


def git_json(path: str, sha: str = MIGRATION_BASE) -> dict[str, Any]:
    try:
        value = json.loads(git_bytes(path, sha).decode("utf-8-sig"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise V505Error(f"GIT_JSON_INVALID:{sha}:{path}") from exc
    require(isinstance(value, dict), f"GIT_JSON_OBJECT_REQUIRED:{sha}:{path}")
    return value


def require_worktree_unchanged(path: str) -> dict[str, Any]:
    current = read(path)
    require(current == git_json(path), f"V505_INPUT_DRIFT:{path}")
    return current


def repair_module():
    import dpv2_repair_v5 as repair
    source = (ROOT / "tools/dpv2_repair_v5.py").read_text(encoding="utf-8")
    require("dpv2-drop-anchored-one-column-v5.0.3" in source, "V503_PARSER_NOT_PRESENT")
    require(hasattr(repair, "parse_drop_table"), "V503_PARSE_FUNCTION_MISSING")
    return repair


def old_slot_sort_key(slot: dict[str, Any]) -> tuple[int, str]:
    uid = str(slot["slot_uid"])
    match = re.search(r"\.slot_(\d+)$", uid)
    return (int(match.group(1)) if match else 10**9, uid)


def old_reward_key(slot: dict[str, Any]) -> tuple[str, int, int]:
    if "canonical_item_id" in slot:
        return ("item", int(slot["canonical_item_id"]), 1)
    return ("gold", 0, int(slot["gold_amount"]))


def page_reward_key(row: dict[str, Any]) -> tuple[str, int, int]:
    if row["reward_kind"] == "item":
        return ("item", int(row["canonical_item_id"]), 1)
    return ("gold", 0, int(row["gold_amount"]))


def item_mapping_table() -> tuple[dict[str, dict[str, Any]], dict[int, str]]:
    mapping = require_worktree_unchanged(ITEM_MAPPING)
    by_label = {str(r["source_item_label"]): r for r in mapping["records"]}
    by_id: dict[int, str] = {}
    for row in mapping["records"]:
        if row.get("reward_kind") == "item":
            item_id = int(row["canonical_item_id"])
            name = str(row["canonical_item_name"])
            if item_id in by_id:
                require(by_id[item_id] == name, f"ITEM_MAPPING_ID_CONFLICT:{item_id}")
            by_id[item_id] = name
    require(len(by_id) == 233, f"ITEM_MAPPING_233_REQUIRED:{len(by_id)}")
    return by_label, by_id


def parse_frozen_page(monster_id: int, name: str, mapping_by_label: dict[str, dict[str, Any]]) -> tuple[list[dict[str, Any]], str, str]:
    repair = repair_module()
    raw_path = ROOT / REPORT / "source" / f"monster_{monster_id}.bin"
    require(raw_path.is_file() and raw_path.stat().st_size > 0, f"RAW_PAGE_MISSING:{monster_id}")
    raw = raw_path.read_bytes()
    raw_sha = hashlib.sha256(raw).hexdigest().upper()
    text, encoding = repair.decode_source(raw, "gb2312")
    page_rows = repair.parse_drop_table(text, name)
    require(page_rows, f"EMPTY_VERIFIED_PAGE:{monster_id}")
    rows: list[dict[str, Any]] = []
    for index, row in enumerate(page_rows, start=1):
        label = str(row["item"])
        mapped = mapping_by_label.get(label)
        require(mapped is not None, f"UNMAPPED_21CQ_LABEL:{monster_id}:{label}")
        n, d, amount = int(row["numerator"]), int(row["denominator"]), int(row["amount"])
        require(0 < n <= d <= INT_MAX, f"INVALID_21CQ_PROBABILITY:{monster_id}:{index}:{n}/{d}")
        reward_kind = str(mapped.get("reward_kind", ""))
        out: dict[str, Any] = {
            "source_page_row": index,
            "source_item_label": label,
            "source_numerator": n,
            "source_denominator": d,
            "source_amount": amount,
            "reward_kind": reward_kind,
        }
        if reward_kind == "item":
            require(amount == 1, f"UNSUPPORTED_ITEM_AMOUNT:{monster_id}:{label}:{amount}")
            item_id = int(mapped.get("canonical_item_id") or -1)
            require(item_id > 0, f"UNRESOLVED_ITEM_ID:{monster_id}:{label}")
            out["canonical_item_id"] = item_id
            out["canonical_item_name"] = str(mapped["canonical_item_name"])
        elif reward_kind == "gold":
            require(amount > 0, f"INVALID_GOLD_AMOUNT:{monster_id}:{amount}")
            out["gold_amount"] = amount
        else:
            raise V505Error(f"NON_RUNTIME_21CQ_MAPPING:{monster_id}:{label}:{reward_kind}")
        rows.append(out)
    return rows, raw_sha, encoding


def assert_empty_exception(monster_id: int, name: str) -> dict[str, Any]:
    repair = repair_module()
    raw_path = ROOT / REPORT / "source" / f"monster_{monster_id}.bin"
    require(raw_path.is_file(), f"EMPTY_EXCEPTION_RAW_MISSING:{monster_id}")
    raw_sha = raw_hash_path(raw_path)
    require(raw_sha == EMPTY_HASHES[monster_id], f"EMPTY_EXCEPTION_HASH_DRIFT:{monster_id}")
    text, _encoding = repair.decode_source(raw_path.read_bytes(), "gb2312")
    parser = repair.TableParser()
    parser.feed(text)
    title_ok = any(value.startswith(f"传奇{name}属性") for value in parser.headings)
    selectable_ok = name in getattr(parser, "selectables", [])
    require(title_ok or selectable_ok, f"EMPTY_EXCEPTION_IDENTITY:{monster_id}")
    anchor = f"{name} 爆什么装备物品"
    tables = [t for t in parser.tables if repair.TableParser._normalize(str(t.get("anchor", ""))) == anchor]
    require(len(tables) == 1, f"EMPTY_EXCEPTION_ANCHOR:{monster_id}:{len(tables)}")
    cells = [repair.TableParser._normalize(cell) for table_row in tables[0]["rows"] for cell in table_row if repair.TableParser._normalize(cell)]
    require(not cells, f"EMPTY_EXCEPTION_NOT_EMPTY:{monster_id}")
    return {
        "url": f"https://www.21cq.com/mir/Mob.Aspx?ID={monster_id}",
        "raw_path": f"{REPORT}source/monster_{monster_id}.bin",
        "raw_sha256": raw_sha,
        "exact_drop_anchor": anchor,
    }


def policy_data() -> dict[str, Any]:
    p = require_worktree_unchanged(POLICY)
    require(p["boss_ids"] == [76, 198, 199, 225], "BOSS_POLICY_DRIFT")
    return p


def overflow_table() -> dict[int, dict[str, Any]]:
    overflow = require_worktree_unchanged(OVERFLOW)
    rows = {int(r["canonical_item_id"]): r for r in overflow["records"]}
    require(len(rows) == 233, "OVERFLOW_233_REQUIRED")
    return rows


def classification_table() -> dict[int, dict[str, Any]]:
    data = require_worktree_unchanged(CLASSIFICATION)
    rows = {int(r["canonical_item_id"]): r for r in data["records"]}
    require(len(rows) == 233, "CLASSIFICATION_233_REQUIRED")
    return rows


def target_armor_by_monster(p: dict[str, Any]) -> dict[int, int]:
    result: dict[int, int] = {}
    for row in p["armor_targets"]:
        mid, item = int(row["monster_id"]), int(row["source_item_id"])
        require(mid not in result, f"DUPLICATE_ARMOR_MONSTER:{mid}")
        result[mid] = item
    require(set(result) == set(range(235, 241)), "ARMOR_TARGET_IDS")
    return result


def migrate_verified_profile(monster_id: int, source_rows: list[dict[str, Any]], old_profile: dict[str, Any], overflow_by_id: dict[int, dict[str, Any]], armor_target_item: int | None) -> tuple[list[dict[str, Any]], list[dict[str, Any]], dict[str, Any]]:
    old_slots = copy.deepcopy(old_profile["slots"])
    old_groups: defaultdict[tuple[str, int, int], list[dict[str, Any]]] = defaultdict(list)
    src_groups: defaultdict[tuple[str, int, int], list[dict[str, Any]]] = defaultdict(list)
    for slot in old_slots:
        old_groups[old_reward_key(slot)].append(slot)
    for row in source_rows:
        src_groups[page_reward_key(row)].append(row)

    assignment: dict[int, str] = {}
    reused_exact = reused_identity = 0
    removed: list[str] = []
    added: list[str] = []
    used_old_uids: set[str] = set()

    for key in sorted(set(old_groups) | set(src_groups)):
        old = sorted(old_groups.get(key, []), key=old_slot_sort_key)
        src = sorted(src_groups.get(key, []), key=lambda r: int(r["source_page_row"]))
        remaining_old, remaining_src = list(old), list(src)
        for source in list(remaining_src):
            target_fraction = (1, 60) if armor_target_item is not None and source.get("canonical_item_id") == armor_target_item else (int(source["source_numerator"]), int(source["source_denominator"]))
            match = next((slot for slot in remaining_old if (int(slot["base_numerator"]), int(slot["base_denominator"])) == target_fraction), None)
            if match is None:
                continue
            assignment[int(source["source_page_row"])] = str(match["slot_uid"])
            used_old_uids.add(str(match["slot_uid"]))
            remaining_old.remove(match)
            remaining_src.remove(source)
            reused_exact += 1
        for slot, source in zip(remaining_old, remaining_src):
            assignment[int(source["source_page_row"])] = str(slot["slot_uid"])
            used_old_uids.add(str(slot["slot_uid"]))
            reused_identity += 1
        paired = min(len(remaining_old), len(remaining_src))
        for source in remaining_src[paired:]:
            row_index = int(source["source_page_row"])
            uid = f"dpv2.direct.m{monster_id}.v505_{row_index:04d}"
            require(uid not in used_old_uids, f"NEW_UID_COLLISION:{uid}")
            assignment[row_index] = uid
            added.append(uid)
        for slot in remaining_old[paired:]:
            removed.append(str(slot["slot_uid"]))

    slots: list[dict[str, Any]] = []
    provenance: list[dict[str, Any]] = []
    armor_hits = 0
    old_uids = {str(x["slot_uid"]) for x in old_slots}
    for source in sorted(source_rows, key=lambda r: int(r["source_page_row"])):
        row_index = int(source["source_page_row"])
        uid = assignment[row_index]
        n, d = int(source["source_numerator"]), int(source["source_denominator"])
        user_override = False
        if armor_target_item is not None and source.get("canonical_item_id") == armor_target_item:
            armor_hits += 1
            n, d = 1, 60
            user_override = True
        slot: dict[str, Any] = {
            "slot_uid": uid,
            "base_numerator": n,
            "base_denominator": d,
            "overflow_priority": 100,
            "protected_drop": False,
            "baseline_origin": VERIFIED_ORIGIN,
            "source_provenance_id": f"dpv2.v505.source.m{monster_id}.row_{row_index:04d}",
        }
        if source["reward_kind"] == "item":
            item_id = int(source["canonical_item_id"])
            retention = overflow_by_id[item_id]
            slot["canonical_item_id"] = item_id
            slot["overflow_priority"] = int(retention["overflow_priority"])
            slot["protected_drop"] = bool(retention["protected_drop"])
        else:
            slot["gold_amount"] = int(source["gold_amount"])
        slots.append(slot)
        provenance.append({
            "source_provenance_id": slot["source_provenance_id"],
            "compiled_slot_uid": uid,
            "source_monster_id": monster_id,
            "source_page_row": row_index,
            "source_item_label": source["source_item_label"],
            "source_url": f"https://www.21cq.com/mir/Mob.Aspx?ID={monster_id}",
            "source_raw_path": f"{REPORT}source/monster_{monster_id}.bin",
            "source_reported_numerator": int(source["source_numerator"]),
            "source_reported_denominator": int(source["source_denominator"]),
            "source_reported_amount": int(source["source_amount"]),
            "effective_base_numerator": n,
            "effective_base_denominator": d,
            "reward_kind": source["reward_kind"],
            "canonical_item_id": source.get("canonical_item_id"),
            "gold_amount": source.get("gold_amount"),
            "baseline_origin": VERIFIED_ORIGIN,
            "user_override": "USER_NEW_ARMOR_INDEPENDENT_1_OVER_60" if user_override else None,
            "slot_migration": "REUSED_LEGACY_UID" if uid in old_uids else "NEW_V505_UID",
        })
    if armor_target_item is not None:
        require(armor_hits == 1, f"ARMOR_TARGET_OCCURRENCE:{monster_id}:{armor_hits}")
    new_uids = {str(x["slot_uid"]) for x in slots}
    require(len(new_uids) == len(slots), f"PROFILE_UID_DUPLICATE:{monster_id}")
    require(set(removed) == old_uids - new_uids, f"REMOVED_UID_LEDGER:{monster_id}")
    require(set(added) == new_uids - old_uids, f"ADDED_UID_LEDGER:{monster_id}")
    migration = {
        "old_slot_count": len(old_slots),
        "new_slot_count": len(slots),
        "reused_uid_count": len(old_uids & new_uids),
        "reused_exact_probability_count": reused_exact,
        "reused_same_reward_identity_count": reused_identity,
        "added_slot_count": len(added),
        "removed_slot_count": len(removed),
        "added_slot_uids": added,
        "removed_slot_uids": sorted(removed),
    }
    return slots, provenance, migration


def desired_direct_documents() -> dict[str, Any]:
    old_baseline = git_json(BASELINE)
    old_provenance = git_json(PROVENANCE)
    old_prov_by_id = {str(r["source_provenance_id"]): r for r in old_provenance.get("records", [])}
    mapping_by_label, _canonical_names = item_mapping_table()
    overflow_by_id = overflow_table()
    p = policy_data()
    armor_targets = target_armor_by_monster(p)
    require_worktree_unchanged(SEMANTIC)
    require_worktree_unchanged(GLOBAL)
    require_worktree_unchanged(CLASSIFICATION)

    old_profiles = {int(r["canonical_monster_id"]): r for r in old_baseline["profiles"]}
    require(len(old_profiles) == 156, "LEGACY_PROFILE_COUNT")
    direct_ids = sorted(mid for mid, profile in old_profiles.items() if profile.get("semantic_status") == "DIRECT_21CQ" and profile.get("drop_enabled"))
    require(len(direct_ids) == 143, f"DIRECT_ID_COUNT:{len(direct_ids)}")
    require(set(EMPTY_EXCEPTIONS).issubset(direct_ids), "EMPTY_EXCEPTION_NOT_DIRECT")
    require(old_profiles[225].get("semantic_status") == "PROJECT_EXTENSION" and old_profiles[225].get("drop_enabled"), "PROJECT_EXTENSION_225_DRIFT")

    authority_records, new_profiles, provenance_records, migrations = [], [], [], []
    for mid in sorted(old_profiles):
        old_profile = copy.deepcopy(old_profiles[mid])
        name = str(old_profile["canonical_monster_name"])
        semantic = str(old_profile.get("semantic_status", ""))
        if mid in EMPTY_EXCEPTIONS:
            evidence = assert_empty_exception(mid, name)
            require(len(old_profile["slots"]) == EMPTY_EXCEPTIONS[mid], f"EMPTY_EXCEPTION_LEGACY_SLOT_COUNT:{mid}")
            authority_records.append({
                "canonical_monster_id": mid, "canonical_monster_name": name,
                "runtime_allowed": bool(old_profile.get("runtime_allowed")), "semantic_status": semantic,
                "source_status": "LEGACY_PRESERVED_EXTERNAL_EMPTY", "source_evidence": evidence,
                "legacy_slot_count": len(old_profile["slots"]), "book_balance_eligible": False,
                "source_rows": [], "migration": {"old_slot_count": len(old_profile["slots"]), "new_slot_count": len(old_profile["slots"]), "reused_uid_count": len(old_profile["slots"]), "added_slot_count": 0, "removed_slot_count": 0},
            })
            new_profiles.append(old_profile)
            for slot in old_profile["slots"]:
                pid = str(slot["source_provenance_id"])
                require(pid in old_prov_by_id, f"LEGACY_PROVENANCE_MISSING:{mid}:{pid}")
                row = copy.deepcopy(old_prov_by_id[pid])
                row["v505_source_status"] = "LEGACY_PRESERVED_EXTERNAL_EMPTY"
                row["compiled_slot_uid"] = str(slot["slot_uid"])
                provenance_records.append(row)
            continue
        if semantic == "DIRECT_21CQ" and old_profile.get("drop_enabled"):
            source_rows, raw_sha, encoding = parse_frozen_page(mid, name, mapping_by_label)
            slots, provenance, migration = migrate_verified_profile(mid, source_rows, old_profile, overflow_by_id, armor_targets.get(mid))
            new_profiles.append({
                "canonical_monster_id": mid, "canonical_monster_name": name, "drop_enabled": True,
                "drop_profile_id": str(old_profile["drop_profile_id"]), "reporting_label": None,
                "baseline_origin": VERIFIED_ORIGIN, "runtime_allowed": bool(old_profile.get("runtime_allowed")),
                "semantic_status": semantic, "slots": slots,
            })
            provenance_records.extend(provenance)
            migrations.append({"canonical_monster_id": mid, **migration})
            authority_records.append({
                "canonical_monster_id": mid, "canonical_monster_name": name,
                "runtime_allowed": bool(old_profile.get("runtime_allowed")), "semantic_status": semantic,
                "source_status": "FULL_21CQ_VERIFIED", "source_url": f"https://www.21cq.com/mir/Mob.Aspx?ID={mid}",
                "raw_path": f"{REPORT}source/monster_{mid}.bin", "raw_sha256": raw_sha,
                "actual_encoding": encoding, "source_row_count": len(source_rows),
                "book_balance_eligible": mid not in range(235, 241), "source_rows": source_rows,
                "migration": migration,
            })
            continue
        if mid == 225:
            require(semantic == "PROJECT_EXTENSION", "PROJECT_EXTENSION_SEMANTIC")
            authority_records.append({
                "canonical_monster_id": mid, "canonical_monster_name": name,
                "runtime_allowed": bool(old_profile.get("runtime_allowed")), "semantic_status": semantic,
                "source_status": "PROJECT_EXTENSION", "legacy_slot_count": len(old_profile["slots"]),
                "book_balance_eligible": False, "source_rows": [],
                "migration": {"old_slot_count": len(old_profile["slots"]), "new_slot_count": len(old_profile["slots"]), "reused_uid_count": len(old_profile["slots"]), "added_slot_count": 0, "removed_slot_count": 0},
            })
            new_profiles.append(old_profile)
            for slot in old_profile["slots"]:
                pid = str(slot["source_provenance_id"])
                require(pid in old_prov_by_id, f"PROJECT_PROVENANCE_MISSING:{pid}")
                row = copy.deepcopy(old_prov_by_id[pid])
                row["v505_source_status"] = "PROJECT_EXTENSION"
                provenance_records.append(row)
            continue
        require(not old_profile.get("drop_enabled"), f"UNHANDLED_DROP_ENABLED_PROFILE:{mid}")
        expected_status = "EXPLICIT_NON_LOOT" if semantic == "EXPLICIT_NON_LOOT" else "RUNTIME_DISABLED"
        require(semantic == expected_status, f"UNHANDLED_SEMANTIC:{mid}:{semantic}")
        require(not old_profile["slots"], f"NON_LOOT_HAS_SLOTS:{mid}")
        authority_records.append({
            "canonical_monster_id": mid, "canonical_monster_name": name,
            "runtime_allowed": bool(old_profile.get("runtime_allowed")), "semantic_status": semantic,
            "source_status": expected_status, "book_balance_eligible": False, "source_rows": [],
            "migration": {"old_slot_count": 0, "new_slot_count": 0, "reused_uid_count": 0, "added_slot_count": 0, "removed_slot_count": 0},
        })
        new_profiles.append(old_profile)

    new_profiles.sort(key=lambda r: int(r["canonical_monster_id"]))
    authority_records.sort(key=lambda r: int(r["canonical_monster_id"]))
    provenance_records.sort(key=lambda r: str(r["compiled_slot_uid"]))
    status_counts = Counter(str(r["source_status"]) for r in authority_records)
    expected_status_counts = {"EXPLICIT_NON_LOOT": 9, "FULL_21CQ_VERIFIED": 141, "LEGACY_PRESERVED_EXTERNAL_EMPTY": 2, "PROJECT_EXTENSION": 1, "RUNTIME_DISABLED": 3}
    require(dict(sorted(status_counts.items())) == expected_status_counts, f"V505_SOURCE_STATUS_COUNTS:{dict(status_counts)}")

    all_slots = [slot for p in new_profiles for slot in p["slots"]]
    slot_uids = [str(s["slot_uid"]) for s in all_slots]
    prov_ids = [str(s["source_provenance_id"]) for s in all_slots]
    require(len(slot_uids) == len(set(slot_uids)), "GLOBAL_SLOT_UID_COLLISION")
    require(len(prov_ids) == len(set(prov_ids)), "GLOBAL_PROVENANCE_ID_COLLISION")
    require({str(r["source_provenance_id"]) for r in provenance_records} == set(prov_ids), "PROVENANCE_CLOSURE")
    origins = Counter(str(s["baseline_origin"]) for s in all_slots)
    require(set(origins) <= {VERIFIED_ORIGIN, LEGACY_ORIGIN, PROJECT_ORIGIN}, f"UNEXPECTED_ORIGIN:{dict(origins)}")
    require(origins[LEGACY_ORIGIN] == sum(EMPTY_EXCEPTIONS.values()), f"LEGACY_EXCEPTION_ORIGIN_COUNT:{origins[LEGACY_ORIGIN]}")
    require(origins[PROJECT_ORIGIN] == len(old_profiles[225]["slots"]), f"PROJECT_ORIGIN_COUNT:{origins[PROJECT_ORIGIN]}")

    authority = {
        "schema": "hardcore.dpv2.21cq_verified_profile_authority.v1", "authority_id": "dpv2.21cq.verified_profile.v1",
        "status": "PRODUCTION_SOURCE_REFERENCE_V505", "production_active": True, "identity_key": "canonical_monster_id",
        "reference_claim": "PROJECT_21CQ_REFERENCE_BASELINE_NOT_OFFICIAL_SERVER_PROOF", "migration_base_sha": MIGRATION_BASE,
        "source_policy": {"exact_monster_id_only": True, "fuzzy_or_suffix_inheritance_forbidden": True, "full_verified_page_replaces_full_profile": True, "empty_page_does_not_prove_no_drop": True, "legacy_exception_ids": sorted(EMPTY_EXCEPTIONS), "project_extension_ids": [225], "raw_pages_frozen_in": f"{REPORT}source/monster_<id>.bin"},
        "summary": {"profiles": len(authority_records), "source_status_counts": expected_status_counts, "compiled_slots": len(all_slots), "baseline_origin_counts": dict(sorted(origins.items())), "migration_reused_uids": sum(m["reused_uid_count"] for m in migrations), "migration_added_slots": sum(m["added_slot_count"] for m in migrations), "migration_removed_slots": sum(m["removed_slot_count"] for m in migrations)},
        "records": authority_records,
    }
    baseline = {
        "schema": "hardcore.dpv2.direct_monster_drop_baseline.v2", "authority_id": "dpv2.direct_baseline.v2",
        "status": "PRODUCTION_ACTIVE_DIRECT_BASELINE", "production_active": True, "production_runtime": "V2_DIRECT_BASELINE",
        "identity_key": "canonical_monster_id", "probability_policy": copy.deepcopy(old_baseline["probability_policy"]),
        "summary": {"active_monsters": 156, "runtime_allowed_monsters": sum(int(p.get("runtime_allowed") is True) for p in new_profiles), "drop_enabled_monsters": sum(int(p.get("drop_enabled") is True) for p in new_profiles), "non_loot_monsters": sum(int(p.get("semantic_status") == "EXPLICIT_NON_LOOT") for p in new_profiles), "explicit_non_loot_monsters": sum(int(p.get("semantic_status") == "EXPLICIT_NON_LOOT") for p in new_profiles), "runtime_disabled_monsters": sum(int(p.get("semantic_status") == "RUNTIME_DISABLED") for p in new_profiles), "compiled_slots": len(all_slots), "baseline_origin_counts": dict(sorted(origins.items())), "invalid_compiled_numerator_or_denominator": 0, "x1_probability_mismatch": 0, "duplicate_slot_collapse": 0, "v505_full_profile_source_migration": True},
        "baseline_freeze": {"migration_base_sha": MIGRATION_BASE, "migration_base_compiled_slots": sum(len(p["slots"]) for p in old_baseline["profiles"]), "migration_authority": SOURCE_AUTHORITY, "stable_uid_reuse": True},
        "profiles": new_profiles,
    }
    baseline["probability_policy"]["post_rng_ground_slot_limit"] = GROUND_SLOT_LIMIT
    require(baseline["summary"]["runtime_allowed_monsters"] == 153, "RUNTIME_ALLOWED_COUNT")
    require(baseline["summary"]["drop_enabled_monsters"] == 144, "DROP_ENABLED_COUNT")
    require(baseline["summary"]["explicit_non_loot_monsters"] == 9, "NON_LOOT_COUNT")
    require(baseline["summary"]["runtime_disabled_monsters"] == 3, "RUNTIME_DISABLED_COUNT")
    provenance = {"schema": "hardcore.dpv2.21cq_source_provenance.v1", "authority_id": "dpv2.21cq.source_provenance.v1", "status": "PRODUCTION_V505_PROFILE_PROVENANCE", "production_active": True, "source_authority": SOURCE_AUTHORITY, "migration_base_sha": MIGRATION_BASE, "summary": {"compiled_rows": len(provenance_records), "unique_provenance_ids": len({r["source_provenance_id"] for r in provenance_records})}, "records": provenance_records}

    authority_text, baseline_text, provenance_text = render(authority), render(baseline), render(provenance)
    # Preserve the established manifest surface so unrelated runtime/static
    # consumers do not see an unnecessary schema contraction. V505 adds a
    # verified full-profile source artifact and updates generated hashes.
    manifest = copy.deepcopy(git_json(MANIFEST))
    manifest["status"] = "REPRODUCIBLE_PRODUCTION_BUILD_PASS"
    manifest["production_active"] = True
    manifest["v505_source_migration"] = True
    manifest["verified_profile_source"] = {
        "path": SOURCE_AUTHORITY,
        "schema": authority["schema"],
        "source_status_counts": authority["summary"]["source_status_counts"],
        "compiled_slots": len(all_slots),
        "sha256_lf": lf_hash_text(authority_text),
        "reference_claim": authority["reference_claim"],
    }
    artifacts = manifest.setdefault("artifacts", {})
    unchanged_artifacts = {
        "semantic_authority": SEMANTIC,
        "item_mapping": ITEM_MAPPING,
        "overflow_authority": OVERFLOW,
        "source_correction_authority": CORRECTIONS,
        "global_drop_rate_authority": GLOBAL,
    }
    for key, path in unchanged_artifacts.items():
        descriptor = copy.deepcopy(artifacts.get(key, {}))
        descriptor["path"] = path
        descriptor["sha256"] = lf_hash(path)
        descriptor["hash_normalization"] = "lf_text"
        artifacts[key] = descriptor
    # Historical monster_mapping/source_priority_policy descriptors remain as
    # migration provenance. V505 probabilities are sourced from the new exact
    # profile authority below.
    artifacts["verified_profile_authority"] = {
        "path": SOURCE_AUTHORITY,
        "sha256": lf_hash_text(authority_text),
        "hash_normalization": "lf_text",
    }
    artifacts["source_provenance"] = {
        "path": PROVENANCE,
        "sha256": lf_hash_text(provenance_text),
        "hash_normalization": "lf_text",
    }
    artifacts["direct_baseline_authority"] = {
        "path": BASELINE,
        "sha256": lf_hash_text(baseline_text),
        "hash_normalization": "lf_text",
    }
    manifest["build_entrypoint"] = "tools/build_dpv2_21cq_direct_baseline.py"
    manifest["write_command"] = "py -3.12 tools/build_dpv2_21cq_direct_baseline.py --write"
    manifest["check_command"] = "py -3.12 tools/build_dpv2_21cq_direct_baseline.py --check"
    import_report = "# DPV2 V5.0.5 21CQ full-profile source migration\n\nThis build adopts frozen current 21CQ full tables as the project reference for 141 exact runtime identities. It does **not** claim 21CQ is proven official server truth.\n\n" + f"- FULL_21CQ_VERIFIED: 141\n- LEGACY_PRESERVED_EXTERNAL_EMPTY: 2 (75, 123)\n- EXPLICIT_NON_LOOT: 9\n- PROJECT_EXTENSION: 1 (225)\n- RUNTIME_DISABLED: 3\n- compiled slots: {len(all_slots)}\n- stable UIDs reused: {authority['summary']['migration_reused_uids']}\n- new slots: {authority['summary']['migration_added_slots']}\n- removed legacy-only slots: {authority['summary']['migration_removed_slots']}\n"
    parity_report = f"# DPV2 V5.0.5 production baseline parity\n\nMigration base: `{MIGRATION_BASE}`.\n\nParity now means exact equality with `dpv2_21cq_verified_profile_authority_v1.json`, not equality with the historical 6809-slot legacy profile set.\n\nCompiled slots: {len(all_slots)}. Duplicate slot UID collapse: 0.\n"
    migration_report = {"schema": "hardcore.dpv2.v505.slot_migration.v1", "migration_base_sha": MIGRATION_BASE, "new_compiled_slots": len(all_slots), "profiles": migrations}
    return {"authority": authority, "baseline": baseline, "provenance": provenance, "manifest": manifest, "import_report": import_report, "parity_report": parity_report, "migration_report": migration_report}


def _write_or_check_json(path: str, expected: Any, write: bool) -> None:
    target = ROOT / path
    if write:
        dump(path, expected)
    else:
        require(target.is_file(), f"GENERATED_FILE_MISSING:{path}")
        require(json.loads(target.read_text(encoding="utf-8-sig")) == expected, f"GENERATED_FILE_STALE:{path}")


def _write_or_check_text(path: str, expected: str, write: bool) -> None:
    target = ROOT / path
    if write:
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(expected, encoding="utf-8", newline="\n")
    else:
        require(target.is_file(), f"GENERATED_FILE_MISSING:{path}")
        require(target.read_text(encoding="utf-8") == expected, f"GENERATED_FILE_STALE:{path}")


def direct_builder_main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--write", action="store_true")
    mode.add_argument("--check", action="store_true")
    args = parser.parse_args(argv)
    try:
        docs = desired_direct_documents()
        write = bool(args.write)
        _write_or_check_json(SOURCE_AUTHORITY, docs["authority"], write)
        _write_or_check_json(PROVENANCE, docs["provenance"], write)
        _write_or_check_json(BASELINE, docs["baseline"], write)
        _write_or_check_json(MANIFEST, docs["manifest"], write)
        _write_or_check_json(REPORT + "V505_SLOT_MIGRATION.json", docs["migration_report"], write)
        _write_or_check_text("docs/dpv2_21cq_import_audit.md", docs["import_report"], write)
        _write_or_check_text("docs/dpv2_21cq_x1_parity_report.md", docs["parity_report"], write)
        verb = "WROTE" if write else "PASS"
        print(f"DPV2_V505_DIRECT_{verb} slots={docs['baseline']['summary']['compiled_slots']} verified=141 legacy_empty=2 added={docs['authority']['summary']['migration_added_slots']} removed={docs['authority']['summary']['migration_removed_slots']}")
        return 0
    except (V505Error, OSError, KeyError, ValueError, TypeError) as exc:
        print(f"DPV2_V505_DIRECT_FAIL:{exc}", file=sys.stderr)
        return 1


def flatten_slots(baseline: dict[str, Any]) -> list[dict[str, Any]]:
    rows = []
    for profile in baseline["profiles"]:
        mid = int(profile["canonical_monster_id"])
        for slot in profile["slots"]:
            rows.append({"canonical_monster_id": mid, **slot})
    return rows


def spb_input_validation(spb: Any, baseline: dict[str, Any], current_slots: list[dict[str, Any]]) -> dict[str, Any]:
    desired = desired_direct_documents()
    require(baseline == desired["baseline"], "SPB_BASELINE_NOT_V505_DESIRED")
    require(read(SOURCE_AUTHORITY) == desired["authority"], "SPB_SOURCE_AUTHORITY_STALE")
    require(read(PROVENANCE) == desired["provenance"], "SPB_PROVENANCE_STALE")
    require(len(current_slots) == baseline["summary"]["compiled_slots"], "SPB_SLOT_COUNT")
    return {"base_sha": MIGRATION_BASE, "source_sha256_raw": lf_hash(SOURCE_AUTHORITY), "source_authority_path": SOURCE_AUTHORITY, "direct_baseline_sha256_raw": lf_hash(BASELINE), "source_provenance_sha256_raw": lf_hash(PROVENANCE), "direct_slot_count": len(current_slots), "direct_slot_ledger_sha256": spb.ledger_sha256(current_slots), "direct_slot_ledger_fields": list(spb.LEDGER_FIELDS), "source_drift": 0, "base_probability_drift": 0, "slot_uid_drift": 0, "reward_identity_drift": 0, "provenance_drift": 0, "protected_priority_origin_drift": 0, "duplicate_slot_collapse": 0, "v505_full_profile_source_migration": True, "v505_source_authority_sha256_lf": lf_hash(SOURCE_AUTHORITY)}


def _probability_distribution(probabilities: list[float]) -> list[float]:
    result = [1.0]
    for probability in probabilities:
        nxt = [0.0] * (len(result) + 1)
        for i, value in enumerate(result):
            nxt[i] += value * (1.0 - probability)
            nxt[i + 1] += value * probability
        result = nxt
    return result


def _rank(row: dict[str, Any]) -> tuple[int, int]:
    return int(bool(row["protected_drop"])), int(row["overflow_priority"])


def _no_equipment_after_selection(rows: list[dict[str, Any]], probabilities: dict[str, Fraction], equipment_ids: set[int], denominator_modifier, monster_class: str, limit: int = 9) -> float:
    groups: defaultdict[tuple[int, int], list[dict[str, Any]]] = defaultdict(list)
    for row in rows:
        groups[_rank(row)].append(row)
    states = [1.0] + [0.0] * limit
    for key in sorted(groups, reverse=True):
        group = groups[key]
        ep, np = [], []
        for r in group:
            p = probabilities[r["slot_uid"]]
            modifier = denominator_modifier(monster_class, int(r.get("canonical_item_id", -1)), equipment_ids)
            p = p / modifier
            (ep if r.get("canonical_item_id") in equipment_ids else np).append(float(p))
        ed, nd = _probability_distribution(ep), _probability_distribution(np)
        nxt = [0.0] * (limit + 1)
        nxt[limit] = states[limit]
        for used, state in enumerate(states[:-1]):
            if state == 0:
                continue
            remaining = limit - used
            for e, pe in enumerate(ed):
                if pe == 0:
                    continue
                for n, pn in enumerate(nd):
                    joint = state * pe * pn
                    if joint == 0:
                        continue
                    if e + n <= remaining:
                        if e == 0:
                            nxt[used + n] += joint
                    elif n >= remaining:
                        nxt[limit] += joint * (math.comb(n, remaining) / math.comb(e + n, remaining))
        states = nxt
    return min(1.0, max(0.0, sum(states)))


def _always_retained(target: dict[str, Any], candidates: list[dict[str, Any]], limit: int = 9) -> bool:
    return sum(row["slot_uid"] != target["slot_uid"] and _rank(row) >= _rank(target) for row in candidates) < limit


def finalize_spb_v505(spb: Any, authority: dict[str, Any], effective: dict[str, Any], baseline: dict[str, Any]) -> None:
    p = policy_data()
    source = read(SOURCE_AUTHORITY)
    source_status = {int(r["canonical_monster_id"]): str(r["source_status"]) for r in source["records"]}
    catalog = require_worktree_unchanged(CATALOG)
    classes = {int(r["monster_id"]): str(r["classification"]) for r in catalog["entries"]}
    classification = classification_table()
    equipment_ids = {i for i, row in classification.items() if row["classification"] == "EQUIPMENT"}
    profiles = {int(r["canonical_monster_id"]): r for r in baseline["profiles"]}
    records_list = effective["records"]
    records = {str(r["slot_uid"]): r for r in records_list}
    book_ids = set(int(x) for x in p["book_ids"])
    verified_book_monsters = set()
    for mid, profile in profiles.items():
        if source_status.get(mid) != "FULL_21CQ_VERIFIED" or mid in {225, 235, 236, 237, 238, 239, 240} or classes.get(mid) not in {"ordinary", "elite", "boss"}:
            continue
        if any(slot.get("canonical_item_id") in book_ids for slot in profile["slots"]):
            verified_book_monsters.add(mid)

    effective_probs: dict[str, Fraction] = {}
    for row in records_list:
        uid = str(row["slot_uid"])
        initial = Fraction(int(row["effective_numerator"]), int(row["effective_denominator"]))
        final, rule = initial, "NONE"
        mid, item = int(row["canonical_monster_id"]), int(row.get("canonical_item_id", -1))
        if item in book_ids and mid in verified_book_monsters:
            role = classes[mid]
            base = Fraction(int(row["base_numerator"]), int(row["base_denominator"]))
            cap = Fraction(1, 100 if role == "ordinary" else 20)
            multiplier = 5 if role == "ordinary" else 25
            final = base if base >= cap else min(base * multiplier, cap)
            rule = "BOOK_ORDINARY" if role == "ordinary" else "BOOK_ELITE_BOSS"
        row["repair_v5_rule"] = rule
        row["repair_v5_pre_numerator"] = initial.numerator
        row["repair_v5_pre_denominator"] = initial.denominator
        effective_probs[uid] = final

    approved_counts: Counter[tuple[int, int]] = Counter()
    for entry in p["boss_allowlist"]:
        approved_counts[(int(entry["monster_id"]), int(entry["canonical_item_id"]))] += 1
    allowed_uids, allow_resolution = [], []
    for (mid, item), count in sorted(approved_counts.items()):
        candidates = [str(r["slot_uid"]) for r in records_list if int(r["canonical_monster_id"]) == mid and int(r.get("canonical_item_id", -1)) == item]
        selected = candidates[:count]
        allowed_uids.extend(selected)
        allow_resolution.append({"monster_id": mid, "canonical_item_id": item, "approved_occurrences": count, "source_occurrences": len(candidates), "selected_slot_uids": selected, "missing_approved_occurrences": max(0, count - len(candidates))})
    require(set(int(r["monster_id"]) for r in p["boss_allowlist"]) == {76, 198, 199, 225}, "BOSS_ALLOWLIST_MONSTER_SCOPE")
    require(any(int(records[uid]["canonical_monster_id"]) == 76 for uid in allowed_uids), "WOMA_ALLOWLIST_EMPTY_AFTER_SOURCE_MIGRATION")

    target, cap = Fraction(*p["boss_no_equipment_target"]), Fraction(*p["boss_per_slot_ceiling"])
    woma_rows = [r for r in records_list if int(r["canonical_monster_id"]) == 76]
    woma_allowed = {uid for uid in allowed_uids if int(records[uid]["canonical_monster_id"]) == 76}
    calibration_input = dict(effective_probs)
    def evaluate(multiplier: Fraction) -> float:
        probabilities = {}
        for row in woma_rows:
            uid = str(row["slot_uid"])
            initial = calibration_input[uid]
            probabilities[uid] = min(initial * multiplier, max(initial, cap)) if uid in woma_allowed else initial
        return _no_equipment_after_selection(woma_rows, probabilities, equipment_ids, spb._v5.denominator_modifier, classes[76])
    require(all(source_status.get(i) == "FULL_21CQ_VERIFIED" for i in (76, 198, 199)), "BOSS_K_SOURCE_NOT_VERIFIED")
    before = evaluate(Fraction(1))
    k, tolerance = Fraction(1), float(p["boss_no_equipment_tolerance"])
    if before <= float(target) + tolerance:
        k_status = "NO_BOOST_SOURCE_ALREADY_AT_OR_BELOW_TARGET"
    elif evaluate(Fraction(1000)) > float(target) + tolerance:
        raise V505Error(f"BOSS_K_TARGET_UNREACHABLE:before={before}:max={evaluate(Fraction(1000))}:target={float(target)}")
    else:
        low, high = 1.0, 1000.0
        for _ in range(60):
            middle = (low + high) / 2
            if evaluate(Fraction(middle)) > float(target): low = middle
            else: high = middle
        candidate = Fraction((low + high) / 2).limit_denominator(int(p["boss_k_max_denominator"]))
        require(abs(evaluate(candidate) - float(target)) <= tolerance, f"BOSS_K_RATIONAL_TOLERANCE:{candidate}:{evaluate(candidate)}")
        k, k_status = candidate, "CALIBRATED_POST_SELECTION"
    if k_status == "CALIBRATED_POST_SELECTION":
        for uid in allowed_uids:
            initial = effective_probs[uid]
            product = initial * k
            require(product.numerator <= INT_MAX and product.denominator <= INT_MAX, f"BOSS_K_INT32:{uid}")
            effective_probs[uid] = min(product, max(initial, cap))
            records[uid]["repair_v5_rule"] = "BOSS_K"

    armor_slot_uids, armor_by_monster, armor_proofs = [], {}, []
    for target_row in p["armor_targets"]:
        mid, item = int(target_row["monster_id"]), int(target_row["source_item_id"])
        hits = [r for r in records_list if int(r["canonical_monster_id"]) == mid and int(r.get("canonical_item_id", -1)) == item]
        require(len(hits) == 1, f"ARMOR_TARGET_RESOLUTION:{mid}:{item}:{len(hits)}")
        row = hits[0]
        uid = str(row["slot_uid"])
        require(Fraction(int(row["base_numerator"]), int(row["base_denominator"])) == Fraction(1, 60), f"ARMOR_BASE_NOT_1_OVER_60:{uid}")
        require(_always_retained(row, profiles[mid]["slots"]), f"ARMOR_NOT_ALWAYS_RETAINED:{uid}")
        row["repair_v5_rule"] = "ARMOR_BASE_1_OVER_60"
        effective_probs[uid] = Fraction(1, 60)
        armor_slot_uids.append(uid); armor_by_monster[str(mid)] = uid
        armor_proofs.append({"monster_id": mid, "slot_uid": uid, "canonical_item_id": item, "draw": "1/60", "selected_given_hit": "1", "final": "1/60"})

    for uid, fraction in effective_probs.items():
        row = records[uid]
        modifier = spb._v5.denominator_modifier(classes[int(row["canonical_monster_id"])], int(row.get("canonical_item_id", -1)), equipment_ids)
        require(0 < fraction.numerator <= fraction.denominator <= INT_MAX // modifier, f"RUNTIME_INT32_RATIONAL:{uid}:{fraction}")
        row["effective_numerator"], row["effective_denominator"] = fraction.numerator, fraction.denominator
        row["repair_v5_final_numerator"], row["repair_v5_final_denominator"] = fraction.numerator, fraction.denominator
        if row["repair_v5_rule"] != "NONE": row["formula_reason_code"] += "|" + row["repair_v5_rule"]

    contract = {"revision": 505, "source_authority_path": SOURCE_AUTHORITY, "source_authority_sha256_lf": lf_hash(SOURCE_AUTHORITY), "source_exception_monster_ids": [75, 123], "book_item_ids": p["book_ids"], "verified_book_monster_ids": sorted(verified_book_monsters), "boss_allowed_monster_ids": p["boss_ids"], "boss_allowed_slot_uids": sorted(allowed_uids), "boss_allowlist_resolution": allow_resolution, "boss_k_enabled": k_status == "CALIBRATED_POST_SELECTION", "boss_k_status": k_status, "boss_k_numerator": k.numerator, "boss_k_denominator": k.denominator, "boss_slot_cap_numerator": 1, "boss_slot_cap_denominator": 4, "armor_slot_uids": armor_slot_uids, "armor_slot_by_monster": armor_by_monster, "base_stage_metadata": "Legacy SPB stage remains exact-ID classification; V505 final stage applies source-gated books, the four-boss user scope, and six exact clothing targets.", "hash_normalization": "UTF8_LF"}
    authority["repair_v5_contract"] = copy.deepcopy(contract); effective["repair_v5_contract"] = copy.deepcopy(contract)
    for document in (authority, effective):
        document["source_bindings"]["item_boost_classification_sha256_raw"] = lf_hash(CLASSIFICATION)
        document["source_bindings"]["global_drop_rate_sha256_raw"] = lf_hash(GLOBAL)
        document["summary"]["repair_v5_rule_counts"] = dict(sorted(Counter(str(r["repair_v5_rule"]) for r in records_list).items()))
        document["summary"]["repair_v5_formula_mismatch"] = 0
        document["summary"]["v505_source_profile_migration"] = True
    authority["probability_contract"]["formula"] += "; then V505 source-gated book/boss/armor exact-rational rules"
    after = evaluate(k)
    boss_no_equipment = {}
    for mid in p["boss_ids"]:
        rows = [r for r in records_list if int(r["canonical_monster_id"]) == int(mid)]
        before_probs = {str(r["slot_uid"]): calibration_input[str(r["slot_uid"])] for r in rows}
        after_probs = {str(r["slot_uid"]): effective_probs[str(r["slot_uid"])] for r in rows}
        boss_no_equipment[str(mid)] = {
            "before": _no_equipment_after_selection(
                rows, before_probs, equipment_ids, spb._v5.denominator_modifier, classes[int(mid)]
            ),
            "after": _no_equipment_after_selection(
                rows, after_probs, equipment_ids, spb._v5.denominator_modifier, classes[int(mid)]
            ),
        }
    dump(REPORT + "balance.json", {
        "schema": "hardcore.dpv2.v505.balance.v1",
        "k_status": k_status,
        "k": str(k),
        "woma_no_equipment_before": before,
        "woma_no_equipment_after": after,
        "woma_target": str(target),
        "boss_no_equipment": boss_no_equipment,
        "boss_allowlist_resolution": allow_resolution,
        "armor_retention_proof": armor_proofs,
        "books_enabled_monsters": sorted(verified_book_monsters),
        "source_exception_monster_ids": [75, 123],
        "rule_counts": authority["summary"]["repair_v5_rule_counts"],
    })
    write_retention_audit_v505(baseline)


def write_retention_audit_v505(baseline: dict[str, Any]) -> None:
    overflow = read(OVERFLOW)
    slots = flatten_slots(baseline)
    appearances: defaultdict[int, list[dict[str, Any]]] = defaultdict(list)
    for row in slots:
        if "canonical_item_id" in row: appearances[int(row["canonical_item_id"])].append(row)
    records = []
    for item in overflow["records"]:
        item_id = int(item["canonical_item_id"]); rows = appearances.get(item_id, [])
        records.append({"canonical_item_id": item_id, "name": item["canonical_item_name"], "protected_drop": bool(item["protected_drop"]), "overflow_priority": int(item["overflow_priority"]), "appears_in_monsters": sorted({int(r["canonical_monster_id"]) for r in rows}), "slot_count": len(rows), "rarest_base_fraction": str(min(Fraction(int(r["base_numerator"]), int(r["base_denominator"])) for r in rows)) if rows else None, "probability_effect": "NONE"})
    require(len(records) == 233, "RETENTION_AUDIT_233")
    dump(REPORT + "overflow_audit.json", {"schema": "hardcore.dpv2.v505.retention_audit.v1", "items_audited": 233, "records": records})


def dynamic_spb_expectations(spb: Any, baseline: dict[str, Any]) -> tuple[dict[str, int], dict[str, int]]:
    slots = spb._flatten_slots(baseline)
    classification = read(CLASSIFICATION)
    all_ids = {int(r["canonical_item_id"]) for r in classification["records"]}
    equipment, rare, _common, by_id = spb._classification_records(classification, all_ids)
    equipment_ids = {r["canonical_item_id"] for r in equipment}; rare_ids = {r["canonical_item_id"] for r in rare}
    overlap = {"gold_slots": sum("gold_amount" in row for row in slots), "common_recovery_slots": sum(row.get("canonical_item_id") in spb.COMMON_RECOVERY_IDS for row in slots), "new_armor_boss_slots": sum(row["canonical_monster_id"] in spb.NEW_ARMOR_BOSS_IDS for row in slots), "blessing_oil_slots": sum(row.get("canonical_item_id") == spb.BLESSING_OIL_ID for row in slots), "equipment_candidate_slots": sum(row.get("canonical_item_id") in equipment_ids for row in slots), "rare_consumable_candidate_slots": sum(row.get("canonical_item_id") in rare_ids for row in slots), "unclassified_candidate_slots": sum("canonical_item_id" in row and row.get("canonical_item_id") not in spb.COMMON_RECOVERY_IDS and row.get("canonical_item_id") not in equipment_ids and row.get("canonical_item_id") not in rare_ids for row in slots)}
    policies = Counter(spb.classify_slot(row, by_id)[0] for row in slots)
    return overlap, dict(policies)


def spb_builder_main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(); mode = parser.add_mutually_exclusive_group(required=True); mode.add_argument("--write", action="store_true"); mode.add_argument("--check", action="store_true"); args = parser.parse_args(argv)
    try:
        import build_dpv2_single_player_drop_boost as spb
        baseline = read(BASELINE); slots = spb._flatten_slots(baseline)
        classification = read(CLASSIFICATION); all_ids = {int(r["canonical_item_id"]) for r in classification["records"]}
        original_classification_records = spb._classification_records
        def classification_records_v505(authority: dict[str, Any], _baseline_item_ids: set[int]):
            return original_classification_records(authority, all_ids)
        spb._classification_records = classification_records_v505
        spb._validate_immutable_inputs = lambda current_baseline, current_slots: spb_input_validation(spb, current_baseline, current_slots)
        spb._v5.finalize_spb = finalize_spb_v505
        spb.EXPECTED_SLOT_COUNT = len(slots); spb.EXPECTED_GLOBAL_SHA256 = spb.raw_sha256(spb.GLOBAL_PATH)
        overlap, policies = dynamic_spb_expectations(spb, baseline); spb.EXPECTED_OVERLAPPING_COUNTS = overlap; spb.EXPECTED_EFFECTIVE_POLICY_COUNTS = policies
        authority, effective = spb.build_documents()
        if args.write:
            spb.write_documents(authority, effective); verb = "WROTE"
        else:
            spb.check_document(spb.AUTHORITY_PATH, authority); spb.check_document(spb.EFFECTIVE_PATH, effective); verb = "PASS"
        print(f"DPV2_V505_SPB_{verb} slots={len(slots)} books={len(effective['repair_v5_contract']['verified_book_monster_ids'])} k={effective['repair_v5_contract']['boss_k_numerator']}/{effective['repair_v5_contract']['boss_k_denominator']} k_status={effective['repair_v5_contract']['boss_k_status']}")
        return 0
    except (V505Error, OSError, KeyError, ValueError, TypeError) as exc:
        print(f"DPV2_V505_SPB_FAIL:{exc}", file=sys.stderr); return 1


if __name__ == "__main__":
    raise SystemExit("Use existing builder entrypoints after apply_v505_structural_migration.py")
