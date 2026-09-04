#!/usr/bin/env python3
"""Validate the data-only DPV2 A0.6 item identity closure.

This module intentionally does not import or modify the Godot runtime.  The
authority file is an explicit migration/identity table: its service index is
checked only as legacy source provenance, while the allocated canonical ID is
the identity used by this validator's overlay.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from collections import defaultdict
from pathlib import Path
from typing import Any, Iterable


ROOT = Path(__file__).resolve().parents[1]
AUTHORITY_RELATIVE = (
    "assets/data/drop/dpv2_item_identity_authority_v1.json"
)
SNAPSHOT_RELATIVE = "outputs/monster_drop_p1a/runtime_snapshot.json"
CATALOG_RELATIVE = "assets/data/service_item_catalog.json"
EXPECTED_SCHEMA = "hardcore.dpv2.item_identity_authority.v1"
EXPECTED_ITEM_COUNT = 233
EXPECTED_MISSING_COUNT = 53
RESERVED_START = 920001
RESERVED_END = 920053
DECISION_DOCUMENT_RELATIVE = "docs/drop/DPV2_A06_AUTHORITY_DECISION.md"
DOWNSTREAM_TIER_AUTHORITY_RELATIVE = (
    "assets/data/drop/dpv2_item_tier_authority_v1.json"
)
DECISION_DOCUMENT_SHA256 = (
    "70f76cc3c7aca7ca3cdbd5186c06ae7b5a9ded173fc0dede12c0d422a7e969e4"
)

ALIASES = {
    "布衣": "布衣(男)",
    "金疮药(小量)": "金创药(小量)",
    "金疮药(中量)": "金创药(中量)",
    "金疮药(大量)": "金创药(大量)",
    "金疮药(特大)": "金创药(特大)",
    "超级金疮药": "超级金创药",
    "强效金创药": "超级金创药",
    "强效魔法药": "超级魔法药",
    "毒蜘蛛牙齿": "蜘蛛牙",
    "食人树叶": "食人花叶",
    "食人树的果实": "食人花果",
    "蝎子的尾巴": "蝎尾",
    "篮翡翠项链": "蓝翡翠项链",
    "铂金项链": "白金项链",
    "群体治愈术": "群体治疗术",
    "极速神水": "疾风药水",
    "道力神水": "精神神水",
}

# These are the formal identity fields that can represent a positive item
# identity in existing authorities.  serviceIndex is deliberately absent:
# it is a legacy source locator, never a canonical ID.
POSITIVE_ID_KEYS = {
    "itemId",
    "item_id",
    "stableItemId",
    "canonical_item_id",
    "canonicalItemId",
}
FORMAL_ID_KEYS = POSITIVE_ID_KEYS | {
    "runtime_map_id",
    "legacy_runtime_map_id",
    "canonical_monster_id",
    "monster_id",
    "monsterId",
    "skill_id",
    "skillId",
}


class AuthorityValidationError(ValueError):
    """Raised when an A0.6 authority or its closure evidence is invalid."""


def _load_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise AuthorityValidationError(f"missing JSON: {path}") from exc
    except json.JSONDecodeError as exc:
        raise AuthorityValidationError(f"invalid JSON: {path}: {exc}") from exc


def _sha256(path: Path) -> str:
    try:
        return hashlib.sha256(path.read_bytes()).hexdigest()
    except FileNotFoundError as exc:
        raise AuthorityValidationError(f"missing provenance file: {path}") from exc
    except OSError as exc:
        raise AuthorityValidationError(f"cannot read provenance file: {path}") from exc


def _as_positive_int(value: Any) -> int | None:
    if isinstance(value, bool):
        return None
    if isinstance(value, int):
        return value if value > 0 else None
    if isinstance(value, str) and value.strip().isdigit():
        parsed = int(value.strip())
        return parsed if parsed > 0 else None
    return None


def _canonical_name(name: str) -> str:
    current = name
    for _ in range(8):
        next_name = ALIASES.get(current, current)
        if next_name == current:
            return current
        current = next_name
    raise AuthorityValidationError(f"alias chain did not converge: {name!r}")


def _iter_json_files(root: Path) -> Iterable[Path]:
    for path in sorted((root / "assets" / "data").rglob("*.json")):
        yield path


def _walk_formal_ids(
    value: Any,
    *,
    path: Path,
    key_path: tuple[str, ...] = (),
) -> Iterable[tuple[Path, str, int]]:
    if isinstance(value, dict):
        for key, child in value.items():
            key_text = str(key)
            positive = None
            if key_text in FORMAL_ID_KEYS:
                positive = _as_positive_int(child)
            elif key_text.lower() == "id" and any(
                part in {"item", "items", "equipment", "equip"}
                for part in (part.lower() for part in path.parts)
            ):
                positive = _as_positive_int(child)
            if positive is not None:
                yield path, ".".join((*key_path, key_text)), positive
            yield from _walk_formal_ids(
                child,
                path=path,
                key_path=(*key_path, key_text),
            )
    elif isinstance(value, list):
        for index, child in enumerate(value):
            yield from _walk_formal_ids(
                child,
                path=path,
                key_path=(*key_path, str(index)),
            )


def _existing_formal_ids(root: Path, excluded: set[Path]) -> dict[str, list[int]]:
    values: dict[str, list[int]] = defaultdict(list)
    for path in _iter_json_files(root):
        if path.resolve() in excluded:
            continue
        try:
            document = _load_json(path)
        except AuthorityValidationError:
            # Non-authority JSON is still surfaced by normal project checks;
            # this audit only needs to avoid turning unrelated malformed data
            # into a false item-ID collision.
            continue
        label = str(path.resolve().relative_to(root.resolve()))
        for _source_path, _key_path, item_id in _walk_formal_ids(
            document,
            path=path,
        ):
            values[label].append(item_id)

    # The generated P1A snapshot is an explicit closure input, but is outside
    # assets/data and must also participate in the collision scan.
    snapshot_path = (root / SNAPSHOT_RELATIVE).resolve()
    if snapshot_path.exists() and snapshot_path not in excluded:
        document = _load_json(snapshot_path)
        label = SNAPSHOT_RELATIVE
        for _source_path, _key_path, item_id in _walk_formal_ids(
            document,
            path=snapshot_path,
        ):
            values[label].append(item_id)
    return values


def _candidate_text_files(root: Path) -> Iterable[Path]:
    roots = [
        root / "assets" / "data",
        root / "scripts",
        root / "tools",
        root / "tests",
        root / "docs",
    ]
    allowed_suffixes = {
        ".json",
        ".gd",
        ".py",
        ".md",
        ".ps1",
        ".txt",
        ".toml",
        ".ini",
    }
    for scan_root in roots:
        if not scan_root.exists():
            continue
        for path in scan_root.rglob("*"):
            if not path.is_file() or path.suffix.lower() not in allowed_suffixes:
                continue
            if "android-build" in path.parts or ".godot" in path.parts:
                continue
            yield path
    project_file = root / "project.godot"
    if project_file.exists():
        yield project_file


def _reserved_text_hits(
    root: Path,
    *,
    excluded: set[Path],
) -> list[str]:
    alternatives = "|".join(
        str(value) for value in range(RESERVED_START, RESERVED_END + 1)
    )
    pattern = re.compile(rf"\b(?:{alternatives})\b")
    hits: list[str] = []
    for path in _candidate_text_files(root):
        if path.resolve() in excluded:
            continue
        relative_parts = path.resolve().relative_to(root.resolve()).parts
        # A0.6 decision/package documents and generated outputs may quote the
        # reserved IDs as evidence.  They are provenance references, not
        # runtime/formal allocations; structured authority scanning remains
        # the collision boundary for those paths.
        if (
            len(relative_parts) >= 3
            and relative_parts[0] == "docs"
            and relative_parts[1] == "drop"
            and relative_parts[2].startswith(("DPV2_A06_", "DPV2_A07_"))
        ) or relative_parts[:1] == ("outputs",) or (
            relative_parts[:1] == ("tools",)
            and "dpv2_a07" in path.name.lower()
        ):
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        for line_number, line in enumerate(text.splitlines(), start=1):
            if pattern.search(line):
                relative = path.resolve().relative_to(root.resolve())
                hits.append(f"{relative}:{line_number}")
    return hits


def _production_references(root: Path, authority_name: str) -> list[str]:
    roots = [root / "scripts", root / "assets" / "data" / "runtime"]
    paths: list[Path] = []
    for scan_root in roots:
        if scan_root.exists():
            paths.extend(path for path in scan_root.rglob("*") if path.is_file())
    project_file = root / "project.godot"
    if project_file.exists():
        paths.append(project_file)
    hits: list[str] = []
    for path in paths:
        if path.suffix.lower() not in {".gd", ".json", ".cfg", ".godot"} and path.name != "project.godot":
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        if authority_name in text:
            hits.append(str(path.resolve().relative_to(root.resolve())))
    return sorted(set(hits))


def _snapshot_items(snapshot: dict[str, Any]) -> tuple[
    dict[str, list[dict[str, Any]]],
    dict[str, set[str]],
]:
    slots = snapshot.get("slots")
    if not isinstance(slots, list):
        raise AuthorityValidationError("P1A snapshot slots is not an array")
    by_name: dict[str, list[dict[str, Any]]] = defaultdict(list)
    raw_names: dict[str, set[str]] = defaultdict(set)
    for slot in slots:
        if not isinstance(slot, dict):
            raise AuthorityValidationError("P1A snapshot has non-object slot")
        probe = slot.get("reward_probe", {})
        if not isinstance(probe, dict) or probe.get("kind") != "item":
            continue
        name = str(probe.get("item_name", ""))
        if not name:
            raise AuthorityValidationError("item slot has empty reward_probe.item_name")
        by_name[name].append(slot)
        source_entry = slot.get("source_entry", {})
        if isinstance(source_entry, dict):
            raw = str(source_entry.get("item", ""))
            if raw:
                raw_names[name].add(raw)
    return by_name, raw_names


def validate_authority_documents(
    authority: dict[str, Any],
    snapshot: dict[str, Any],
    catalog: dict[str, Any],
    *,
    repo_root: Path,
    authority_path: Path,
) -> dict[str, Any]:
    if authority.get("schema") != EXPECTED_SCHEMA:
        raise AuthorityValidationError("unexpected authority schema")
    authority_meta = authority.get("authority")
    policy = authority.get("identity_policy")
    interval = authority.get("reserved_interval")
    provenance = authority.get("source_provenance")
    records = authority.get("records")
    if not isinstance(authority_meta, dict) or not isinstance(policy, dict):
        raise AuthorityValidationError("authority metadata/policy is missing")
    if not isinstance(interval, dict) or not isinstance(provenance, dict):
        raise AuthorityValidationError("interval/provenance is missing")
    if not isinstance(records, list):
        raise AuthorityValidationError("authority records is not an array")
    if authority_meta.get("production_active") is not False:
        raise AuthorityValidationError("A0.6 authority must not be production active")
    if authority_meta.get("kind") != "user_authoritative_override":
        raise AuthorityValidationError("A0.6 authority kind is not user_authoritative_override")
    if authority_meta.get("decision_document") != DECISION_DOCUMENT_RELATIVE:
        raise AuthorityValidationError("decision document provenance path is unexpected")
    if str(authority_meta.get("decision_document_sha256", "")).lower() != DECISION_DOCUMENT_SHA256:
        raise AuthorityValidationError("authority decision document SHA256 is unexpected")
    if authority_meta.get("runtime_consumer") is not None:
        raise AuthorityValidationError("A0.6 authority has a runtime consumer")
    if authority_meta.get("persistence_consumer") is not None:
        raise AuthorityValidationError("A0.6 authority has a persistence consumer")
    if policy.get("canonical_key") != "canonical_item_id":
        raise AuthorityValidationError("canonical key is not canonical_item_id")
    if policy.get("service_index_field") != "legacy_service_index":
        raise AuthorityValidationError("service index field is not legacy_service_index")
    if policy.get("service_index_role") != (
        "legacy_source_locator_plus_provenance_only"
    ):
        raise AuthorityValidationError("service index role is not locator-only")
    for key in (
        "service_index_is_canonical",
        "service_index_is_runtime_key",
        "service_index_is_persistence_key",
        "runtime_name_or_order_derivation_forbidden",
        "allocation_from_service_index_forbidden",
    ):
        expected = False if key.startswith("service_index_is_") else True
        if policy.get(key) is not expected:
            raise AuthorityValidationError(f"identity policy {key} is invalid")

    if (
        int(interval.get("start", -1)) != RESERVED_START
        or int(interval.get("end", -1)) != RESERVED_END
        or int(interval.get("count", -1)) != EXPECTED_MISSING_COUNT
    ):
        raise AuthorityValidationError("reserved interval does not match A0.6 closure")
    if interval.get("assignment_policy") != "explicit_records_only":
        raise AuthorityValidationError("reserved interval is not explicit-record-only")
    if provenance.get("p1a_snapshot") != SNAPSHOT_RELATIVE:
        raise AuthorityValidationError("P1A provenance path is unexpected")
    if provenance.get("service_catalog") != CATALOG_RELATIVE:
        raise AuthorityValidationError("service catalog provenance path is unexpected")
    if str(provenance.get("decision_document_sha256", "")).lower() != DECISION_DOCUMENT_SHA256:
        raise AuthorityValidationError("source decision document SHA256 is unexpected")
    decision_document_path = (repo_root / DECISION_DOCUMENT_RELATIVE).resolve()
    if _sha256(decision_document_path) != DECISION_DOCUMENT_SHA256:
        raise AuthorityValidationError("decision document SHA256 does not match current file")

    by_name, raw_names = _snapshot_items(snapshot)
    if len(by_name) != EXPECTED_ITEM_COUNT:
        raise AuthorityValidationError(
            f"P1A normalized item count {len(by_name)} != {EXPECTED_ITEM_COUNT}"
        )
    positive_by_name: dict[str, int] = {}
    missing_names: set[str] = set()
    for name, slots in by_name.items():
        ids = {
            int(slot.get("reward_probe", {}).get("item_id", -1))
            for slot in slots
        }
        positive = {item_id for item_id in ids if item_id > 0}
        if len(positive) > 1 or (positive and -1 in ids):
            raise AuthorityValidationError(f"mixed/colliding P1A IDs for {name}")
        if positive:
            positive_by_name[name] = next(iter(positive))
        else:
            missing_names.add(name)
    if len(positive_by_name) != EXPECTED_ITEM_COUNT - EXPECTED_MISSING_COUNT:
        raise AuthorityValidationError("P1A positive ID count is not 180")
    if len(missing_names) != EXPECTED_MISSING_COUNT:
        raise AuthorityValidationError("P1A missing ID count is not 53")

    runtime_items = catalog.get("runtimeItems")
    equipment_refs = catalog.get("serviceEquipmentReference")
    if not isinstance(runtime_items, list) or not isinstance(equipment_refs, list):
        raise AuthorityValidationError("service catalog runtime arrays are missing")
    runtime_by_sid: dict[int, list[dict[str, Any]]] = defaultdict(list)
    for record in runtime_items:
        if isinstance(record, dict):
            sid = _as_positive_int(record.get("serviceIndex"))
            if sid is not None:
                runtime_by_sid[sid].append(record)
    equipment_by_sid: dict[int, list[dict[str, Any]]] = defaultdict(list)
    for record in equipment_refs:
        if isinstance(record, dict):
            sid = _as_positive_int(record.get("serviceIndex"))
            if sid is not None:
                equipment_by_sid[sid].append(record)

    if sum(len(values) for values in runtime_by_sid.values()) != len(runtime_items):
        raise AuthorityValidationError("runtimeItems contains invalid serviceIndex")
    if any(len(values) != 1 for values in runtime_by_sid.values()):
        raise AuthorityValidationError("runtimeItems contains duplicate serviceIndex")
    if set(runtime_by_sid).intersection(equipment_by_sid):
        raise AuthorityValidationError("runtime/equipment serviceIndex namespace overlaps")

    if len(records) != EXPECTED_MISSING_COUNT:
        raise AuthorityValidationError("authority does not contain exactly 53 records")
    names: set[str] = set()
    canonical_ids: set[int] = set()
    service_indices: set[int] = set()
    record_by_name: dict[str, dict[str, Any]] = {}
    forbidden_record_keys = {
        "item_id",
        "itemId",
        "stableItemId",
        "service_index",
        "serviceIndex",
    }
    for record in records:
        if not isinstance(record, dict):
            raise AuthorityValidationError("authority record is not an object")
        if forbidden_record_keys.intersection(record):
            raise AuthorityValidationError(
                "authority record exposes a runtime/item/service key"
            )
        name = str(record.get("normalized_item_name", ""))
        canonical_id = _as_positive_int(record.get("canonical_item_id"))
        sid = _as_positive_int(record.get("legacy_service_index"))
        if not name or canonical_id is None or sid is None:
            raise AuthorityValidationError("authority record lacks explicit identity")
        if not RESERVED_START <= canonical_id <= RESERVED_END:
            raise AuthorityValidationError(f"canonical ID outside reserved interval: {name}")
        if name in names or canonical_id in canonical_ids or sid in service_indices:
            raise AuthorityValidationError(f"duplicate authority identity: {name}")
        if record.get("current_canonical_item_id") != -1:
            raise AuthorityValidationError(f"non-missing current ID for {name}")
        if record.get("allocation") != "new_reserved_interval":
            raise AuthorityValidationError(f"unexpected allocation for {name}")
        if record.get("source_item_keys") != [f"service:{sid}"]:
            raise AuthorityValidationError(f"source key is not explicit for {name}")
        legacy_names = record.get("legacy_names")
        if not isinstance(legacy_names, list) or not legacy_names:
            raise AuthorityValidationError(f"legacy names missing for {name}")
        if set(str(raw) for raw in legacy_names) != raw_names.get(name, set()):
            raise AuthorityValidationError(f"legacy names do not match P1A for {name}")
        if int(record.get("source_slot_count", -1)) != len(by_name.get(name, [])):
            raise AuthorityValidationError(f"slot count mismatch for {name}")
        source_monsters = {
            int(slot.get("monster_id", -1))
            for slot in by_name.get(name, [])
        }
        if int(record.get("source_monster_count", -1)) != len(source_monsters):
            raise AuthorityValidationError(f"monster count mismatch for {name}")
        if name not in missing_names:
            raise AuthorityValidationError(f"authority covers existing ID {name}")
        if sid not in runtime_by_sid or len(runtime_by_sid[sid]) != 1:
            raise AuthorityValidationError(f"service index not in runtime catalog: {sid}")
        service_record = runtime_by_sid[sid][0]
        if str(service_record.get("name", "")) != name:
            raise AuthorityValidationError(f"catalog canonical name mismatch for {name}")
        if sid in equipment_by_sid:
            raise AuthorityValidationError(f"service/equipment collision for {name}")
        names.add(name)
        canonical_ids.add(canonical_id)
        service_indices.add(sid)
        record_by_name[name] = record

    if names != missing_names:
        raise AuthorityValidationError("authority names do not equal P1A missing names")
    if len(canonical_ids) != EXPECTED_MISSING_COUNT:
        raise AuthorityValidationError("authority canonical IDs are not unique")
    if len(service_indices) != EXPECTED_MISSING_COUNT:
        raise AuthorityValidationError("authority service indices are not unique")

    # The A0.7 Tier Authority is an explicit downstream reference to this
    # allocation, not a second identity allocation. Its own validator checks
    # exact one-to-one parity with these records.
    downstream_tier_authority = (repo_root / DOWNSTREAM_TIER_AUTHORITY_RELATIVE).resolve()
    excluded = {authority_path.resolve()}
    if downstream_tier_authority.exists():
        excluded.add(downstream_tier_authority)
    existing_by_file = _existing_formal_ids(repo_root, excluded)
    existing_ids = {
        item_id
        for values in existing_by_file.values()
        for item_id in values
    }
    reserved_structured_collisions = sorted(existing_ids.intersection(canonical_ids))
    if reserved_structured_collisions:
        raise AuthorityValidationError(
            f"canonical IDs collide with existing authorities: {reserved_structured_collisions}"
        )
    reserved_text_hits = _reserved_text_hits(repo_root, excluded=excluded | {
        Path(__file__).resolve(),
    })
    # The focused test is allowed to mention the reserved interval as test
    # data.  Production and existing authorities are the collision boundary.
    reserved_text_hits = [
        hit for hit in reserved_text_hits
        if not hit.replace("\\", "/").startswith(
            "tools/tests/test_dpv2_a06_item_identity_validator.py:"
        )
    ]
    if reserved_text_hits:
        raise AuthorityValidationError(
            f"reserved interval appears outside the authority/test: {reserved_text_hits[:5]}"
        )

    overlaid: dict[str, int] = dict(positive_by_name)
    for name, record in record_by_name.items():
        if name in overlaid:
            raise AuthorityValidationError(f"overlay would overwrite positive ID: {name}")
        overlaid[name] = int(record["canonical_item_id"])
    if len(overlaid) != EXPECTED_ITEM_COUNT or len(set(overlaid.values())) != EXPECTED_ITEM_COUNT:
        raise AuthorityValidationError("authority overlay is not 233/233 positive unique")
    if any(item_id <= 0 for item_id in overlaid.values()):
        raise AuthorityValidationError("authority overlay contains non-positive ID")

    authority_name = authority_path.name
    production_refs = _production_references(repo_root, authority_name)
    if production_refs:
        raise AuthorityValidationError(
            f"A0.6 authority is referenced by production paths: {production_refs}"
        )

    namespace_file_count = len(existing_by_file)
    existing_formal_count = len(existing_ids)
    return {
        "status": "PASS",
        "schema": EXPECTED_SCHEMA,
        "authority_records": len(records),
        "p1a_normalized_items": len(by_name),
        "p1a_existing_positive_items": len(positive_by_name),
        "p1a_missing_items": len(missing_names),
        "overlay_positive_unique_items": len(overlaid),
        "existing_formal_id_count_scanned": existing_formal_count,
        "existing_formal_namespace_file_count": namespace_file_count,
        "existing_formal_bindings": 0,
        "new_allocated_count": len(canonical_ids),
        "reserved_interval": [RESERVED_START, RESERVED_END],
        "reserved_interval_collision_count": 0,
        "reserved_text_collision_count": 0,
        "runtime_production_consumption": False,
        "persistence_production_consumption": False,
        "service_index_role": "legacy_source_locator_plus_provenance_only",
        "service_index_target_count": len(service_indices),
        "service_index_unique": True,
        "service_index_runtime_key": False,
        "service_index_persistence_key": False,
        "user_authoritative_override_verified": True,
        "decision_document_sha256": DECISION_DOCUMENT_SHA256,
    }


def validate_authority(
    *,
    repo_root: Path = ROOT,
    authority_path: Path | None = None,
    snapshot_path: Path | None = None,
    catalog_path: Path | None = None,
) -> dict[str, Any]:
    root = repo_root.resolve()
    authority = (authority_path or root / AUTHORITY_RELATIVE).resolve()
    snapshot = (snapshot_path or root / SNAPSHOT_RELATIVE).resolve()
    catalog = (catalog_path or root / CATALOG_RELATIVE).resolve()
    authority_document = _load_json(authority)
    snapshot_document = _load_json(snapshot)
    catalog_document = _load_json(catalog)
    return validate_authority_documents(
        authority_document,
        snapshot_document,
        catalog_document,
        repo_root=root,
        authority_path=authority,
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--authority", type=Path, default=None)
    parser.add_argument("--snapshot", type=Path, default=None)
    parser.add_argument("--catalog", type=Path, default=None)
    args = parser.parse_args(argv)
    try:
        result = validate_authority(
            repo_root=args.root,
            authority_path=args.authority,
            snapshot_path=args.snapshot,
            catalog_path=args.catalog,
        )
    except AuthorityValidationError as exc:
        print(json.dumps({"status": "FAIL", "error": str(exc)}, ensure_ascii=False))
        return 1
    print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
