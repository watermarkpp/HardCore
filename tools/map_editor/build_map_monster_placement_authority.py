#!/usr/bin/env python3
"""Build the fail-closed monster-placement authority manifest.

This is a Phase 0 authoring/audit tool.  It reads the user-authored map
distribution table and the repository's map/monster authorities, then writes
one deterministic JSON manifest to the explicitly requested ``--output``.
It never edits the source table, map workspaces, runtime releases, or monster
production data.

Monster names are not used as a runtime fallback.  Exact canonical names are
accepted only when the canonical catalog says ``runtime_allowed``.  The few
non-exact forms in the user table are handled only by explicit, auditable
variant/group rules below; every other form remains ``unresolved_blocked``.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any, Iterable


ROOT = Path(__file__).resolve().parents[2]
SOURCE_REL = Path("docs/map_design/HardCore_当前67张地图_怪物分布表_V2_按新结构.txt")
ORIGINAL_USER_SOURCE = (
    r"C:\Users\Administrator\Desktop\HardCore_当前67张地图_怪物分布表_V2_按新结构.txt"
)
DEFAULT_SOURCE = SOURCE_REL
IDENTITY_REL = Path("assets/data/map_design/map_identity_registry.json")
CATALOG_REL = Path("assets/data/runtime/canonical_monster_catalog.json")
CLASSIFICATION_REL = Path("assets/data/canonical_monster_classification_v1.json")
VANILLA_REL = Path("assets/data/vanilla_176/monsters.json")
POLICY_REL = Path("assets/data/canonical_monster_catalog_policy_v1.json")

SCHEMA_VERSION = 2
MANIFEST_ID = "hardcore.map_monster_placement_authority.v2"
IDENTITY_CONTRACT = "hardcore.formal_map_identity.v1"
FORBIDDEN_RESOLVED_IDS = {33, 183, 241}

HEADING_RE = re.compile(
    r"\[(?P<width>\d+)\s*[×xX]\s*(?P<height>\d+)\s*格\s*\|\s*"
    r"(?P<map_id>[^|]+?)\s*\|\s*(?P<runtime_id>\d+)\s*\]"
)
CATEGORY_LABELS = (
    "普通刷新：",
    "精英刷新：",
    "BOSS刷新：",
    "特殊/守卫：",
    "怪物刷新：",
)
CATEGORY_ROLE = {
    "普通刷新": "ordinary",
    "精英刷新": "elite",
    "BOSS刷新": "boss",
    "特殊/守卫": "special",
    "怪物刷新": "special",
}

# Every non-exact mapping is deliberately named.  These rules are not a
# fuzzy matcher: a raw source token must match one of these keys byte-for-byte
# after surrounding whitespace is removed.
GROUP_RULES: dict[str, dict[str, Any]] = {
    "僵尸（多种外观形态）": {
        "rule_id": "canonical_group.zombie_appearance_forms.v1",
        "group_code": "zombie_appearance_forms",
        "base_name": "僵尸",
        "variant_codes": ["1", "2", "3", "4", "5"],
        "classification": "ordinary",
        "reason": "用户明确要求保留矿区/通道僵尸的多种正式外观形态。",
    },
    "祖玛弓箭手（极品变体）": {
        "rule_id": "canonical_group.zuma_archer_elite_variants.v1",
        "group_code": "zuma_archer_elite_variants",
        "base_name": "祖玛弓箭手",
        "variant_codes": ["3"],
        "classification": "elite",
        "reason": "用户表明确标注极品变体；仅展开正式 canonical variant code=3。",
    },
    "祖玛雕像（极品变体）": {
        "rule_id": "canonical_group.zuma_statue_elite_variants.v1",
        "group_code": "zuma_statue_elite_variants",
        "base_name": "祖玛雕像",
        "variant_codes": ["3"],
        "classification": "elite",
        "reason": "用户表明确标注极品变体；仅展开正式 canonical variant code=3。",
    },
    "祖玛卫士（极品变体）": {
        "rule_id": "canonical_group.zuma_guard_elite_variants.v1",
        "group_code": "zuma_guard_elite_variants",
        "base_name": "祖玛卫士",
        "variant_codes": ["0", "3", "00"],
        "classification": "elite",
        "reason": "用户表明确标注极品变体；展开正式 canonical 0/3/00 变体组。",
    },
    "宝箱怪": {
        "rule_id": "canonical_group.treasure_chest_forms.v1",
        "group_code": "treasure_chest_forms",
        "base_name": "宝箱",
        "variant_codes": ["", "1", "2", "3", "4", "5", "6", "7", "8"],
        "classification": "special",
        "system_code": "special_script_entity.treasure_chest",
        "reason": "正式合同将宝箱系列作为独立多形态特殊/脚本实体。",
    },
}

UNKNOWN_DARK_SUFFIX = "（未知暗殿变体）"
UNKNOWN_DARK_SPECIAL_BASES = {
    "半兽勇士": "unknown_dark_palace.beast_warrior_variant_1",
    "骷髅精灵": "unknown_dark_palace.skeleton_essence_variant_1",
    "尸王": "unknown_dark_palace.corpse_king_variant_1",
    "邪恶钳虫": "unknown_dark_palace.evil_pincer_variant_1",
    "白野猪": "unknown_dark_palace.white_boar_variant_1",
    "邪恶毒蛇": "unknown_dark_palace.evil_snake_variant_1",
    "沃玛教主": "unknown_dark_palace.wooma_taurus_variant_1",
}

NPC_SYSTEM_RULES: dict[str, dict[str, str]] = {
    "弓箭护卫": {
        "system_code": "npc_guard.archer_guard",
        "classification": "non_hostile",
        "reason": "正式地图分类将弓箭护卫作为独立非敌对守卫/NPC系统实体。",
    },
    "无固定刷新": {
        "system_code": "source_marker.no_fixed_spawn",
        "classification": "non_hostile",
        "reason": "这是源表的无固定刷新标记，不是可生成的怪物 token。",
    },
}


def load_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8-sig"))
    except FileNotFoundError as exc:
        raise ValueError(f"missing authority file: {path}") from exc
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise ValueError(f"cannot read JSON authority {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise ValueError(f"JSON authority must be an object: {path}")
    return value


def sha256_file(path: Path) -> str:
    try:
        digest = hashlib.sha256()
        with path.open("rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(chunk)
        return digest.hexdigest().upper()
    except OSError as exc:
        raise ValueError(f"cannot hash source file {path}: {exc}") from exc


def source_ref(
    path: Path,
    *,
    role: str,
    repo: Path | None = None,
    stable_path: str | None = None,
    kind: str = "json",
) -> dict[str, Any]:
    if not path.is_file():
        raise ValueError(f"source file does not exist: {path}")
    resolved = path.resolve()
    display_path = stable_path or str(resolved)
    if stable_path is None and repo is not None:
        try:
            display_path = resolved.relative_to(repo.resolve()).as_posix()
        except ValueError:
            # External inputs are represented by their stable caller-provided
            # path, never by a host-specific absolute path in the manifest.
            display_path = resolved.name
    return {
        "path": display_path,
        "file_name": resolved.name,
        "sha256": sha256_file(resolved),
        "hash_normalization": "raw_bytes",
        "role": role,
        "kind": kind,
    }


def clean_display_name(raw: str) -> str:
    # The table prefixes headings with an ASCII/Unicode tree drawing.  Only
    # those presentation characters are removed; the identity itself is
    # matched from map_id/runtime_id below.
    return re.sub(r"^[\s│┃┆┊├└┌┬┝┕┗┍┎┞┟┼─━╴╶╾╼]+", "", raw).strip()


def parse_table(path: Path) -> tuple[list[dict[str, Any]], list[str]]:
    try:
        lines = path.read_text(encoding="utf-8-sig").splitlines()
    except (OSError, UnicodeError) as exc:
        raise ValueError(f"cannot read placement source {path}: {exc}") from exc

    maps: list[dict[str, Any]] = []
    current: dict[str, Any] | None = None
    for line_number, line in enumerate(lines, 1):
        match = HEADING_RE.search(line)
        if match:
            if current is not None:
                maps.append(current)
            current = {
                "source_line": line_number,
                "source_heading": line,
                "display_name": clean_display_name(line[: match.start()]),
                "design_size": [int(match.group("width")), int(match.group("height"))],
                "map_id": match.group("map_id").strip(),
                "runtime_id": int(match.group("runtime_id")),
                "tokens": [],
            }
            continue
        if current is None:
            continue
        label = next((item for item in CATEGORY_LABELS if item in line), None)
        if label is None:
            continue
        value = line.split(label, 1)[1].strip()
        if not value:
            raise ValueError(f"empty token list at source line {line_number}")
        category = label[:-1]
        for token_index, raw_token in enumerate(value.split("、"), 1):
            token = raw_token.strip()
            if not token:
                raise ValueError(f"empty token at source line {line_number}")
            current["tokens"].append(
                {
                    "raw_token": token,
                    "normalized_token": token,
                    "source_line": line_number,
                    "source_category": category,
                    "source_category_role": CATEGORY_ROLE[category],
                    "source_token_index": token_index,
                }
            )
    if current is not None:
        maps.append(current)
    if not maps:
        raise ValueError("placement source contains no map headings")
    return maps, lines


def build_identity_index(identity: dict[str, Any]) -> dict[str, dict[str, Any]]:
    if identity.get("contract_id") != IDENTITY_CONTRACT:
        raise ValueError(
            f"unexpected map identity contract: {identity.get('contract_id')!r}"
        )
    maps = identity.get("maps")
    if identity.get("formal_map_count") != 67 or not isinstance(maps, list):
        raise ValueError("map identity registry must declare 67 maps")
    if len(maps) != 67:
        raise ValueError(f"map identity registry map count={len(maps)} expected 67")
    result: dict[str, dict[str, Any]] = {}
    runtime_seen: set[int] = set()
    for row in maps:
        if not isinstance(row, dict):
            raise ValueError("map identity row is not an object")
        map_id = str(row.get("map_id", ""))
        if not map_id or map_id in result:
            raise ValueError(f"duplicate/empty map identity: {map_id!r}")
        runtime_id = row.get("runtime_map_id")
        if not isinstance(runtime_id, int) or isinstance(runtime_id, bool):
            raise ValueError(f"typed runtime_map_id required: {map_id}")
        if runtime_id in runtime_seen:
            raise ValueError(f"duplicate runtime_map_id: {runtime_id}")
        runtime_seen.add(runtime_id)
        result[map_id] = row
    return result


def canonical_name_index(catalog: dict[str, Any]) -> dict[str, dict[str, Any]]:
    entries = catalog.get("entries")
    if not isinstance(entries, list) or len(entries) != 156:
        raise ValueError("canonical monster catalog must contain 156 entries")
    result: dict[str, dict[str, Any]] = {}
    for entry in entries:
        if not isinstance(entry, dict):
            raise ValueError("canonical monster entry is not an object")
        name = str(entry.get("canonical_name", ""))
        monster_id = entry.get("monster_id")
        if not name or not isinstance(monster_id, int) or isinstance(monster_id, bool):
            raise ValueError(f"invalid canonical monster entry: {entry!r}")
        if name in result:
            raise ValueError(f"duplicate canonical name is unsafe: {name!r}")
        result[name] = entry
    # The manifest must never accidentally publish the three known excluded
    # identities.  They may exist in the catalog, but only as non-allowed
    # evidence; no placement resolution is allowed to contain them.
    for entry in entries:
        if int(entry["monster_id"]) in FORBIDDEN_RESOLVED_IDS and bool(
            entry.get("runtime_allowed", False)
        ):
            raise ValueError(
                f"forbidden excluded monster became runtime_allowed: {entry['monster_id']}"
            )
    return result


def base_name(entry: dict[str, Any]) -> str:
    name = str(entry.get("canonical_name", ""))
    variant_code = str(entry.get("variant_code", ""))
    if variant_code and name.endswith(variant_code):
        return name[: -len(variant_code)]
    return name


def variant_index(
    by_name: dict[str, dict[str, Any]],
) -> dict[str, list[dict[str, Any]]]:
    result: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for entry in by_name.values():
        result[base_name(entry)].append(entry)
    for values in result.values():
        values.sort(key=lambda item: (str(item.get("variant_code", "")), int(item["monster_id"])))
    return result


def retired_name_index(vanilla: dict[str, Any]) -> dict[str, list[dict[str, Any]]]:
    result: dict[str, list[dict[str, Any]]] = defaultdict(list)
    records = vanilla.get("records")
    if not isinstance(records, list):
        raise ValueError("vanilla monster authority has no records list")
    for row in records:
        if not isinstance(row, dict) or row.get("recordStatus") != "retired":
            continue
        name = str(row.get("name", ""))
        if name:
            result[name].append(row)
    return result


def canonical_entry_summary(entry: dict[str, Any]) -> dict[str, Any]:
    return {
        "canonical_name": str(entry["canonical_name"]),
        "variant_code": str(entry.get("variant_code", "")),
        "classification": str(entry.get("classification", "")),
        "monster_id": int(entry["monster_id"]),
        "runtime_allowed": bool(entry.get("runtime_allowed", False)),
        "status": str(entry.get("status", "")),
    }


def source_placement_kind(source_role: str) -> str:
    if source_role in {"elite", "boss"}:
        return "boss_spawn"
    return "monster_spawn"


def _assert_allowed(entries: Iterable[dict[str, Any]], context: str) -> None:
    values = list(entries)
    if not values:
        raise ValueError(f"explicit resolution produced no canonical entries: {context}")
    forbidden = [
        int(entry["monster_id"])
        for entry in values
        if int(entry["monster_id"]) in FORBIDDEN_RESOLVED_IDS
    ]
    if forbidden:
        raise ValueError(f"forbidden monster IDs in resolution {context}: {forbidden}")
    not_allowed = [
        int(entry["monster_id"])
        for entry in values
        if not bool(entry.get("runtime_allowed", False))
    ]
    if not_allowed:
        raise ValueError(f"non-runtime monster IDs in resolution {context}: {not_allowed}")


AUTO_PLACEMENT_ALLOWED = "AUTO_PLACEMENT_ALLOWED"
SPECIAL_SYSTEM_REQUIRED = "SPECIAL_SYSTEM_REQUIRED"
EXPLICIT_PLACEMENT_REQUIRED = "EXPLICIT_PLACEMENT_REQUIRED"
INTENTIONALLY_EXCLUDED = "INTENTIONALLY_EXCLUDED"
UNRESOLVED_BLOCKED = "UNRESOLVED_BLOCKED"
SOURCE_MARKER = "SOURCE_MARKER"


def auto_placement_decision(
    *,
    resolution_kind: str,
    status: str,
    classification: str | None,
    system_code: str | None,
) -> tuple[str, bool]:
    """Return the separate automatic-placement route decision.

    Identity resolution and automatic placement are intentionally different
    authorities.  Script/NPC entities and all ``special`` classifications
    require a dedicated route even when their canonical identity is valid.
    Only ordinary exact identities and explicit ordinary/Boss/Elite canonical
    groups can enter the automatic placement path; ambiguous exact Elite/Boss
    names remain explicit-route-only.
    """

    if system_code or classification in {"special", "non_hostile"}:
        return SPECIAL_SYSTEM_REQUIRED, False
    if resolution_kind == "special_npc_system":
        return SPECIAL_SYSTEM_REQUIRED, False
    if status == "excluded":
        return INTENTIONALLY_EXCLUDED, False
    if status == "blocked":
        return UNRESOLVED_BLOCKED, False
    if status == "not_a_monster":
        return SOURCE_MARKER, False
    if status != "resolved":
        return UNRESOLVED_BLOCKED, False
    if resolution_kind == "unique_exact_monster_id" and classification == "ordinary":
        return AUTO_PLACEMENT_ALLOWED, True
    if resolution_kind == "canonical_variant_group" and classification in {
        "ordinary",
        "elite",
        "boss",
    }:
        return AUTO_PLACEMENT_ALLOWED, True
    return EXPLICIT_PLACEMENT_REQUIRED, False


def resolved_record(
    token: dict[str, Any],
    *,
    resolution_kind: str,
    status: str,
    classification: str | None,
    placement_kind: str,
    entries: list[dict[str, Any]],
    evidence: dict[str, Any],
    system_code: str | None = None,
    variant_group: dict[str, Any] | None = None,
) -> dict[str, Any]:
    record = dict(token)
    auto_placement_status, auto_placement_allowed = auto_placement_decision(
        resolution_kind=resolution_kind,
        status=status,
        classification=classification,
        system_code=system_code,
    )
    record.update(
        {
            "resolution_kind": resolution_kind,
            "classification": classification,
            "placement_kind": placement_kind,
            "placement_allowed": status == "resolved",
            "auto_placement_status": auto_placement_status,
            "auto_placement_allowed": auto_placement_allowed,
            "status": status,
            "resolution_status": {
                "resolved": "resolved",
                "excluded": "intentionally_excluded",
                "blocked": "unresolved_blocked",
                "not_a_monster": "source_marker",
            }.get(status, status),
            "resolved_monster_ids": [int(entry["monster_id"]) for entry in entries],
            "resolved_variant_codes": [
                str(entry.get("variant_code", "")) for entry in entries
            ],
            "resolved_canonical_names": [
                str(entry["canonical_name"]) for entry in entries
            ],
            "resolution_evidence": evidence,
        }
    )
    if len(entries) == 1:
        record["resolved_monster_id"] = int(entries[0]["monster_id"])
        record["resolved_variant_code"] = str(entries[0].get("variant_code", ""))
    else:
        record["resolved_monster_id"] = None
        record["resolved_variant_code"] = None
    if system_code:
        record["system_code"] = system_code
    if variant_group is not None:
        record["variant_group"] = variant_group
    return record


def resolve_token(
    token: dict[str, Any],
    *,
    by_name: dict[str, dict[str, Any]],
    by_base: dict[str, list[dict[str, Any]]],
    retired_by_name: dict[str, list[dict[str, Any]]],
    catalog_ref: dict[str, Any],
    classification_ref: dict[str, Any],
    vanilla_ref: dict[str, Any],
) -> dict[str, Any]:
    raw = str(token["normalized_token"])
    source_role = str(token["source_category_role"])
    placement_kind = source_placement_kind(source_role)

    marker = NPC_SYSTEM_RULES.get(raw)
    if marker and raw == "无固定刷新":
        return resolved_record(
            token,
            resolution_kind="special_npc_system",
            status="not_a_monster",
            classification=marker["classification"],
            placement_kind="none",
            entries=[],
            system_code=marker["system_code"],
            evidence={
                "method": "explicit_source_marker",
                "rule_id": "source_marker.no_fixed_spawn.v1",
                "reason": marker["reason"],
                "source_path": catalog_ref["path"],
                "source_sha256": catalog_ref["sha256"],
            },
        )

    # Exact canonical name is the only direct name lookup permitted by this
    # offline authoring audit.  It is never a runtime fallback.
    exact = by_name.get(raw)
    if exact is not None:
        if not bool(exact.get("runtime_allowed", False)):
            return resolved_record(
                token,
                resolution_kind="intentionally_retired_excluded",
                status="excluded",
                classification=str(exact.get("classification", "")) or None,
                placement_kind=placement_kind,
                entries=[],
                evidence={
                    "method": "exact_canonical_name_runtime_reject",
                    "authority": "canonical_monster_catalog",
                    "matched_canonical_name": str(exact["canonical_name"]),
                    "runtime_allowed": False,
                    "catalog_status": str(exact.get("status", "")),
                    "reason": "exact canonical identity exists but is not runtime_allowed; no ID is emitted",
                    "source_path": catalog_ref["path"],
                    "source_sha256": catalog_ref["sha256"],
                },
            )
        _assert_allowed([exact], raw)
        if str(exact.get("classification", "")) == "non_hostile":
            return resolved_record(
                token,
                resolution_kind="special_npc_system",
                status="resolved",
                classification="non_hostile",
                placement_kind=placement_kind,
                entries=[exact],
                system_code="npc_guard.demon_archer_guard",
                evidence={
                    "method": "exact_canonical_name_special_system",
                    "authority": "canonical_monster_catalog",
                    "matched": canonical_entry_summary(exact),
                    "reason": "canonical non_hostile classification routes this identity through the guard/NPC system",
                    "source_path": catalog_ref["path"],
                    "source_sha256": catalog_ref["sha256"],
                },
            )
        return resolved_record(
            token,
            resolution_kind="unique_exact_monster_id",
            status="resolved",
            classification=str(exact.get("classification", "")) or None,
            placement_kind=placement_kind,
            entries=[exact],
            evidence={
                "method": "exact_canonical_name",
                "authority": "canonical_monster_catalog",
                "matched": canonical_entry_summary(exact),
                "source_path": catalog_ref["path"],
                "source_sha256": catalog_ref["sha256"],
            },
        )

    # Explicit group rules are applied before descriptor-specific handling.
    rule = GROUP_RULES.get(raw)
    if rule is not None:
        candidates = [
            entry
            for entry in by_base.get(str(rule["base_name"]), [])
            if str(entry.get("variant_code", "")) in list(rule["variant_codes"])
        ]
        candidates.sort(key=lambda item: list(rule["variant_codes"]).index(str(item.get("variant_code", ""))))
        if len(candidates) != len(rule["variant_codes"]):
            found = sorted(str(entry.get("variant_code", "")) for entry in candidates)
            raise ValueError(
                f"explicit group {rule['rule_id']} is incomplete: expected {rule['variant_codes']}, found {found}"
            )
        _assert_allowed(candidates, raw)
        group = {
            "group_code": str(rule["group_code"]),
            "rule_id": str(rule["rule_id"]),
            "base_name": str(rule["base_name"]),
            "variant_codes": [str(entry.get("variant_code", "")) for entry in candidates],
            "monster_ids": [int(entry["monster_id"]) for entry in candidates],
            "canonical_names": [str(entry["canonical_name"]) for entry in candidates],
        }
        evidence = {
            "method": "explicit_canonical_variant_group",
            "authority": "canonical_monster_catalog",
            "rule_id": str(rule["rule_id"]),
            "reason": str(rule["reason"]),
            "matched": [canonical_entry_summary(entry) for entry in candidates],
            "source_path": catalog_ref["path"],
            "source_sha256": catalog_ref["sha256"],
        }
        return resolved_record(
            token,
            resolution_kind="canonical_variant_group",
            status="resolved",
            classification=str(rule["classification"]),
            placement_kind=placement_kind,
            entries=candidates,
            evidence=evidence,
            system_code=rule.get("system_code"),
            variant_group=group,
        )

    # A guard/NPC token is deliberately not inferred from a similar name.
    # This exact source spelling is an explicit system contract.
    if raw == "弓箭护卫" or raw.startswith("弓箭护卫（"):
        return resolved_record(
            token,
            resolution_kind="special_npc_system",
            status="resolved",
            classification="non_hostile",
            placement_kind=placement_kind,
            entries=[],
            system_code=NPC_SYSTEM_RULES["弓箭护卫"]["system_code"],
            evidence={
                "method": "explicit_npc_system_rule",
                "rule_id": "npc_guard.archer_guard.v1",
                "reason": NPC_SYSTEM_RULES["弓箭护卫"]["reason"],
                "optional": "可选" in raw,
                "source_path": classification_ref["path"],
                "source_sha256": classification_ref["sha256"],
            },
        )

    # Unknown Dark Palace names are resolved only for the seven variants that
    # have an explicit special variant in the canonical contract.  Chicken,
    # deer, strawman, giant multi-horn, and Wooma guard intentionally remain
    # blocked because no formal variant identity is present.
    if raw.endswith(UNKNOWN_DARK_SUFFIX):
        base = raw[: -len(UNKNOWN_DARK_SUFFIX)]
        if base in UNKNOWN_DARK_SPECIAL_BASES:
            candidates = [
                entry
                for entry in by_base.get(base, [])
                if str(entry.get("variant_code", "")) == "1"
                and str(entry.get("classification", "")) == "special"
            ]
            if len(candidates) != 1:
                raise ValueError(
                    f"unknown-dark explicit variant contract is not unique for {base!r}"
                )
            _assert_allowed(candidates, raw)
            entry = candidates[0]
            group = {
                "group_code": UNKNOWN_DARK_SPECIAL_BASES[base],
                "rule_id": f"canonical_variant.unknown_dark_palace.{base}.v1",
                "base_name": base,
                "variant_codes": ["1"],
                "monster_ids": [int(entry["monster_id"])],
                "canonical_names": [str(entry["canonical_name"])],
            }
            return resolved_record(
                token,
                resolution_kind="canonical_variant_group",
                status="resolved",
                classification="special",
                placement_kind=placement_kind,
                entries=candidates,
                variant_group=group,
                evidence={
                    "method": "explicit_unknown_dark_palace_variant",
                    "authority": "canonical_monster_catalog",
                    "rule_id": group["rule_id"],
                    "reason": "canonical special variant code=1 is explicitly contracted for this Unknown Dark Palace token",
                    "matched": canonical_entry_summary(entry),
                    "source_path": catalog_ref["path"],
                    "source_sha256": catalog_ref["sha256"],
                },
                system_code="special_script_entity.unknown_dark_palace",
            )

        base_candidates = by_base.get(base, [])
        retired_candidates = retired_by_name.get(base, [])
        classification = (
            str(base_candidates[0].get("classification", ""))
            if len(base_candidates) == 1
            else "special"
        )
        return resolved_record(
            token,
            resolution_kind="unresolved_blocked",
            status="blocked",
            classification=classification or "unresolved",
            placement_kind=placement_kind,
            entries=[],
            system_code="special_script_entity.unknown_dark_palace",
            evidence={
                "method": "explicit_variant_required_but_missing",
                "authority": "canonical_monster_catalog",
                "reason": "Unknown Dark Palace requires a stable canonical variant; no unique explicit variant contract exists for this token",
                "base_token": base,
                "candidate_canonical_names": [
                    str(entry["canonical_name"]) for entry in base_candidates
                ],
                "candidate_variant_codes": [
                    str(entry.get("variant_code", "")) for entry in base_candidates
                ],
                "retired_base_source_match": bool(retired_candidates),
                "source_path": catalog_ref["path"],
                "source_sha256": catalog_ref["sha256"],
            },
        )

    # Plain chicken/deer are present in the user distribution table but their
    # source records are retired and absent from the active canonical catalog.
    # Keep the table token visible without emitting the retired IDs.
    retired = retired_by_name.get(raw, [])
    if retired:
        return resolved_record(
            token,
            resolution_kind="intentionally_retired_excluded",
            status="excluded",
            classification="ordinary",
            placement_kind=placement_kind,
            entries=[],
            evidence={
                "method": "exact_retired_source_name",
                "authority": "vanilla_176_monsters_source",
                "source_record_status": "retired",
                "retired_source_match_count": len(retired),
                "reason": "source record is retired and absent from active canonical runtime; no ID is emitted",
                "source_path": vanilla_ref["path"],
                "source_sha256": vanilla_ref["sha256"],
            },
        )

    # Any remaining descriptor or spelling is a hard block.  In particular,
    # do not strip suffixes, use aliases, or pick the first same-base record.
    return resolved_record(
        token,
        resolution_kind="unresolved_blocked",
        status="blocked",
        classification="unresolved",
        placement_kind=placement_kind,
        entries=[],
        evidence={
            "method": "no_exact_or_explicit_rule",
            "authority": "canonical_monster_catalog",
            "reason": "no unique exact canonical identity or explicit variant/system contract; fuzzy/alias matching is forbidden",
            "source_path": catalog_ref["path"],
            "source_sha256": catalog_ref["sha256"],
        },
    )


def build_manifest(
    *,
    repo: Path,
    source_path: Path,
    identity_path: Path,
    catalog_path: Path,
    classification_path: Path,
    vanilla_path: Path,
    policy_path: Path,
) -> dict[str, Any]:
    identity = load_json(identity_path)
    catalog = load_json(catalog_path)
    classification = load_json(classification_path)
    vanilla = load_json(vanilla_path)
    policy = load_json(policy_path)
    identity_by_map = build_identity_index(identity)
    by_name = canonical_name_index(catalog)
    by_base = variant_index(by_name)
    retired_by_name = retired_name_index(vanilla)
    source_maps, source_lines = parse_table(source_path)

    table_ref = source_ref(
        source_path,
        role="user_authoritative_map_monster_distribution",
        repo=repo,
        stable_path=SOURCE_REL.as_posix(),
        kind="text",
    )
    identity_ref = source_ref(
        identity_path, role="formal_map_identity_authority", repo=repo
    )
    catalog_ref = source_ref(
        catalog_path, role="canonical_monster_runtime_authority", repo=repo
    )
    classification_ref = source_ref(
        classification_path,
        role="canonical_monster_classification_authority",
        repo=repo,
    )
    vanilla_ref = source_ref(
        vanilla_path, role="retired_source_evidence", repo=repo
    )
    policy_ref = source_ref(policy_path, role="canonical_monster_policy", repo=repo)

    if len(source_maps) != 67:
        raise ValueError(f"placement source map count={len(source_maps)} expected 67")
    source_ids = {str(row["map_id"]) for row in source_maps}
    identity_ids = set(identity_by_map)
    if source_ids != identity_ids:
        raise ValueError(
            f"map identity mismatch: missing={sorted(identity_ids - source_ids)} extra={sorted(source_ids - identity_ids)}"
        )

    all_tokens: list[dict[str, Any]] = []
    maps: list[dict[str, Any]] = []
    for source_map in source_maps:
        map_id = str(source_map["map_id"])
        identity_row = identity_by_map[map_id]
        runtime_id = int(identity_row["runtime_map_id"])
        if int(source_map["runtime_id"]) != runtime_id:
            raise ValueError(
                f"runtime identity mismatch map={map_id}: source={source_map['runtime_id']} registry={runtime_id}"
            )
        if str(identity_row.get("map_id", "")) != map_id:
            raise ValueError(f"identity map_id mismatch: {map_id}")
        map_tokens: list[dict[str, Any]] = []
        for token in source_map["tokens"]:
            resolved = resolve_token(
                token,
                by_name=by_name,
                by_base=by_base,
                retired_by_name=retired_by_name,
                catalog_ref=catalog_ref,
                classification_ref=classification_ref,
                vanilla_ref=vanilla_ref,
            )
            resolved["map_id"] = map_id
            resolved["runtime_id"] = runtime_id
            resolved["runtime_map_id"] = runtime_id
            resolved["legacy_map_id"] = str(identity_row.get("legacy_map_id", ""))
            resolved["legacy_runtime_id"] = identity_row.get("legacy_runtime_map_id")
            map_tokens.append(resolved)
            all_tokens.append(resolved)
        map_row = {
            "map_id": map_id,
            "runtime_id": runtime_id,
            "runtime_map_id": runtime_id,
            "legacy_map_id": str(identity_row.get("legacy_map_id", "")),
            "legacy_runtime_id": identity_row.get("legacy_runtime_map_id"),
            "display_name": str(identity_row.get("display_name", "")),
            "source_display_name": str(source_map.get("display_name", "")),
            "series": str(identity_row.get("series", "")),
            "design_size": list(source_map["design_size"]),
            "source_heading_line": int(source_map["source_line"]),
            "tokens": map_tokens,
            "monster_tokens": [
                token for token in map_tokens if token["status"] != "not_a_monster"
            ],
        }
        maps.append(map_row)

    # Stable order is source order for maps/tokens; authority key order is
    # fixed below.  Make sure no accidental duplicate occurrence was dropped.
    expected_occurrences = sum(len(row["tokens"]) for row in source_maps)
    if len(all_tokens) != expected_occurrences:
        raise ValueError(
            f"token occurrence loss: parsed={expected_occurrences} emitted={len(all_tokens)}"
        )
    statuses = Counter(str(token["status"]) for token in all_tokens)
    kinds = Counter(str(token["resolution_kind"]) for token in all_tokens)
    auto_statuses = Counter(
        str(token["auto_placement_status"]) for token in all_tokens
    )
    unique_tokens = {str(token["raw_token"]) for token in all_tokens}
    unique_monster_tokens = {
        str(token["raw_token"])
        for token in all_tokens
        if token["status"] != "not_a_monster"
    }
    unresolved = [
        {
            "map_id": token["map_id"],
            "runtime_id": token["runtime_id"],
            "raw_token": token["raw_token"],
            "source_line": token["source_line"],
            "reason": token["resolution_evidence"].get("reason", ""),
            "base_token": token["resolution_evidence"].get("base_token"),
        }
        for token in all_tokens
        if token["status"] == "blocked"
    ]
    resolved_ids = sorted(
        {
            int(monster_id)
            for token in all_tokens
            for monster_id in token.get("resolved_monster_ids", [])
        }
    )
    if FORBIDDEN_RESOLVED_IDS.intersection(resolved_ids):
        raise ValueError("forbidden excluded ID leaked into resolved manifest")

    authority = {
        "placement_source": table_ref,
        "map_identity_registry": identity_ref,
        "canonical_monster_catalog": catalog_ref,
        "canonical_monster_classification": classification_ref,
        "vanilla_monster_source": vanilla_ref,
        "canonical_monster_policy": policy_ref,
    }
    manifest: dict[str, Any] = {
        "schema_version": SCHEMA_VERSION,
        "manifest_id": MANIFEST_ID,
        "contract_id": "hardcore.map_monster_placement_authority.v2",
        "generated_by": "tools/map_editor/build_map_monster_placement_authority.py",
        "source_sha256": table_ref["sha256"],
        "source_file": table_ref["file_name"],
        "provenance": {
            "original_user_path": ORIGINAL_USER_SOURCE,
            "relocated_source_path": SOURCE_REL.as_posix(),
            "relocated_source_sha256": table_ref["sha256"],
            "note": "The formal V2 attachment is vendored byte-for-byte under docs/map_design; original_user_path is provenance text only.",
        },
        "source_files": authority,
        "authorities": authority,
        "policy": {
            "identity_key": "monster_id",
            "name_lookup": "offline_exact_or_explicit_rule_only",
            "runtime_resolution": "id_only_fail_closed",
            "auto_placement": {
                "allowed_status": AUTO_PLACEMENT_ALLOWED,
                "special_system_status": SPECIAL_SYSTEM_REQUIRED,
                "rules": {
                    "unique_exact_monster_id": ["ordinary"],
                    "canonical_variant_group": ["ordinary", "elite", "boss"],
                    "system_code": "special_system_required",
                    "special_classification": "special_system_required",
                    "other_resolved_identity": "explicit_placement_required",
                },
            },
            "fuzzy_match": False,
            "alias_fallback": False,
            "suffix_trim_fallback": False,
            "create_monster_id": False,
            "restore_retired_monster": False,
            "allowed_resolution_kinds": [
                "unique_exact_monster_id",
                "canonical_variant_group",
                "special_npc_system",
                "intentionally_retired_excluded",
                "unresolved_blocked",
            ],
        },
        "summary": {
            "formal_map_count": len(maps),
            "source_map_count": len(source_maps),
            "source_line_count": len(source_lines),
            "token_occurrence_count": len(all_tokens),
            "monster_token_occurrence_count": sum(
                1 for token in all_tokens if token["status"] != "not_a_monster"
            ),
            "unique_token_count": len(unique_tokens),
            "unique_monster_token_count": len(unique_monster_tokens),
            "resolved_monster_id_count": len(resolved_ids),
            "status_counts": dict(sorted(statuses.items())),
            "resolution_kind_counts": dict(sorted(kinds.items())),
            "auto_placement_status_counts": dict(sorted(auto_statuses.items())),
            "auto_placement_allowed_occurrence_count": auto_statuses[
                AUTO_PLACEMENT_ALLOWED
            ],
            "auto_placement_blocked_occurrence_count": len(all_tokens)
            - auto_statuses[AUTO_PLACEMENT_ALLOWED],
            "resolved_exact_occurrence_count": kinds["unique_exact_monster_id"],
            "resolved_variant_group_occurrence_count": kinds["canonical_variant_group"],
            "resolved_special_system_occurrence_count": kinds["special_npc_system"],
            "intentionally_retired_excluded_occurrence_count": kinds[
                "intentionally_retired_excluded"
            ],
            "unresolved_blocked_occurrence_count": kinds["unresolved_blocked"],
            "source_marker_occurrence_count": statuses["not_a_monster"],
            "unresolved_blocked_unique_token_count": len(
                {str(row["raw_token"]) for row in unresolved}
            ),
            "unresolved_blocked": bool(unresolved),
            "resolved_monster_ids": resolved_ids,
        },
        "maps": maps,
        "token_records": all_tokens,
        "unresolved_blocked": unresolved,
    }
    return manifest


def write_json(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    try:
        path.write_text(
            json.dumps(value, ensure_ascii=False, indent=2, sort_keys=False) + "\n",
            encoding="utf-8",
            newline="\n",
        )
    except OSError as exc:
        raise ValueError(f"cannot write manifest {path}: {exc}") from exc


def verify_manifest(expected: dict[str, Any], output_path: Path) -> None:
    try:
        actual = json.loads(output_path.read_text(encoding="utf-8-sig"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise ValueError(f"cannot read tracked placement manifest {output_path}: {exc}") from exc
    if actual != expected:
        # Keep the CLI diagnostic compact; callers can use a JSON diff for
        # details without this command dumping the 401-token manifest.
        expected_keys = set(expected) if isinstance(expected, dict) else set()
        actual_keys = set(actual) if isinstance(actual, dict) else set()
        raise ValueError(
            "tracked manifest is not reproducible "
            f"(missing_keys={sorted(expected_keys - actual_keys)} "
            f"extra_keys={sorted(actual_keys - expected_keys)})"
        )


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=ROOT)
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE)
    parser.add_argument("--identity", type=Path)
    parser.add_argument("--catalog", type=Path)
    parser.add_argument("--classification", type=Path)
    parser.add_argument("--vanilla", type=Path)
    parser.add_argument("--policy", type=Path)
    parser.add_argument(
        "--output",
        type=Path,
        required=True,
        help="explicit JSON output path; generation/check never writes elsewhere",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="rebuild in memory and compare byte-independent JSON structure to --output",
    )
    parser.add_argument(
        "--generate",
        action="store_true",
        help="write the deterministic manifest to --output (default mode)",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    repo = args.repo.resolve()

    def authority_path(value: Path | None, relative: Path) -> Path:
        return (value if value is not None else repo / relative).resolve()

    source_path = (
        args.source if args.source.is_absolute() else repo / args.source
    ).resolve()
    output_path = args.output.resolve()
    expected = build_manifest(
        repo=repo,
        source_path=source_path,
        identity_path=authority_path(args.identity, IDENTITY_REL),
        catalog_path=authority_path(args.catalog, CATALOG_REL),
        classification_path=authority_path(args.classification, CLASSIFICATION_REL),
        vanilla_path=authority_path(args.vanilla, VANILLA_REL),
        policy_path=authority_path(args.policy, POLICY_REL),
    )
    if args.check:
        verify_manifest(expected, output_path)
        print(
            "MAP_MONSTER_PLACEMENT_AUTHORITY_CHECK_PASS "
            f"maps={expected['summary']['formal_map_count']} "
            f"tokens={expected['summary']['token_occurrence_count']} "
            f"unresolved={expected['summary']['unresolved_blocked_occurrence_count']}"
        )
        return 0
    write_json(output_path, expected)
    print(
        "MAP_MONSTER_PLACEMENT_AUTHORITY_GENERATE_PASS "
        f"output={output_path} maps={expected['summary']['formal_map_count']} "
        f"tokens={expected['summary']['token_occurrence_count']} "
        f"unresolved={expected['summary']['unresolved_blocked_occurrence_count']}"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"MAP_MONSTER_PLACEMENT_AUTHORITY_FAILED: {exc}", file=sys.stderr)
        raise SystemExit(1)
