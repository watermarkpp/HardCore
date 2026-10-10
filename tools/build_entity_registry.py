"""Generate the typed identity index from explicit, existing authority lanes.

This index owns identity translation only; it never copies gameplay attributes.
Names are display metadata, never keys or a source of newly invented identities.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/data/identity/entity_registry_source.json"
OUTPUT = ROOT / "assets/data/runtime/entity_registry_v1.json"
CONTRACT = "hardcore.entity_identity.v1"
KINDS = {"skill", "item", "service_item", "monster", "map", "profession", "slot", "currency", "item_category"}
NUMERIC = {"item", "service_item", "monster", "map"}
ASCII_ID = re.compile(r"[a-z][a-z0-9_]*(?:\.[a-z0-9_]+)*\Z")
EQUIPMENT_GRANTED_SKILL_IDS = {
    'hc.skill.equipment.ring_teleport',
    'hc.skill.equipment.ring_healing',
    'hc.skill.equipment.ring_fireball',
}


def read(path: Path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def digest(path: Path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def keys(value, required, optional=()):
    if not isinstance(value, dict) or not set(required) <= value.keys() or value.keys() - set(required) - set(optional):
        raise ValueError("unexpected or missing schema field")


def identity(kind, legacy):
    if kind not in KINDS:
        raise ValueError(f"unknown identity kind: {kind}")
    if kind in NUMERIC:
        if type(legacy) is not int or not 0 <= legacy <= 2147483647:
            raise ValueError(f"invalid exact numeric identity: {legacy!r}")
        suffix = f"{legacy:06d}"
    else:
        if not isinstance(legacy, str) or not ASCII_ID.fullmatch(legacy):
            raise ValueError(f"invalid exact symbolic identity: {legacy!r}")
        suffix = legacy
    return f"hc.{kind}.{suffix}"


def validate_skill_book_bindings(authority, catalog, records):
    """Validate declared endpoints only; display names cannot create a relation."""
    overrides = authority.get('policies', {}).get('serviceOverridesByIndex', {})
    if not isinstance(overrides, dict):
        raise ValueError('invalid skill book relation')
    services = {row['serviceIndex']: row for row in catalog['runtimeItems']}
    relations = {}
    targets = set()
    for old, value in overrides.items():
        if not isinstance(value, dict):
            raise ValueError('invalid skill book relation')
        if 'learnSkillId' not in value:
            continue
        target = value['learnSkillId']
        if not isinstance(old, str) or not re.fullmatch(r'0|[1-9][0-9]*', old):
            raise ValueError('invalid skill book relation')
        alias = records.get(identity('service_item', int(old)), {})
        if not isinstance(target, str) or records.get(target, {}).get('kind') != 'skill' \
                or alias.get('kind') != 'service_item' or services.get(int(old), {}).get('kind') != 'skill_book':
            raise ValueError('invalid skill book relation')
        book = alias.get('canonical_id', identity('service_item', int(old)))
        if book in relations or target in targets:
            raise ValueError('duplicate skill book relation')
        relations[book] = target
        targets.add(target)
    # Equipment-granted skills are deliberately not skill-book targets. Their
    # entitlement comes from the linked positive-durability item instance.
    vanilla_skill_ids = {
        key for key, row in records.items()
        if row['kind'] == 'skill' and key not in EQUIPMENT_GRANTED_SKILL_IDS
    }
    if targets != vanilla_skill_ids:
        raise ValueError('incomplete skill book relations')
    return relations


def validate_equipment_granted_bindings(root, records):
    source_path = root / 'assets/data/equipment_granted_skills.source.json'
    master_path = root / 'assets/data/equipment_attribute_master.json'
    source = read(source_path)
    master = read(master_path)
    if source.get('contract_id') != 'equipment.granted_skills.source.v1' or not isinstance(source.get('records'), list):
        raise ValueError('invalid equipment-granted skill source')
    master_by_id = {row.get('itemId'): row for row in master.get('records', []) if isinstance(row, dict)}
    seen_skill_ids = set()
    seen_item_ids = set()
    for row in source['records']:
        skill_id = row.get('skill_id')
        item_id = row.get('item_id')
        if not isinstance(skill_id, str) or not skill_id.startswith('hc.skill.equipment.'):
            raise ValueError('invalid equipment-granted skill identity')
        if records.get(skill_id, {}).get('kind') != 'skill':
            raise ValueError(f'unregistered equipment-granted skill: {skill_id}')
        if type(item_id) is not int or item_id in seen_item_ids or item_id not in master_by_id:
            raise ValueError(f'invalid equipment-granted item binding: {item_id}')
        if skill_id in seen_skill_ids:
            raise ValueError(f'duplicate equipment-granted skill: {skill_id}')
        seen_skill_ids.add(skill_id)
        seen_item_ids.add(item_id)
    if seen_skill_ids != EQUIPMENT_GRANTED_SKILL_IDS or seen_item_ids != {254, 255, 259}:
        raise ValueError('equipment-granted skill closure mismatch')
    return {'skill_count': len(seen_skill_ids), 'item_ids': sorted(seen_item_ids)}


def validate_relic_bindings(authority, skill_source, records):
    pools = authority.get('skill_pools')
    professions = {key for key, value in records.items() if value['kind'] == 'profession'}
    if not isinstance(pools, dict) or set(pools) != professions:
        raise ValueError('incomplete relic profession pools')
    source_skills = {identity('skill', row['skill_id']): row for row in skill_source['skills']}
    count = 0
    for profession, targets in pools.items():
        if not isinstance(targets, list) or not targets:
            raise ValueError('invalid relic skill relation')
        seen = set()
        for target in targets:
            if not isinstance(target, str) or records.get(target, {}).get('kind') != 'skill' or target not in source_skills:
                raise ValueError('invalid relic skill relation')
            if target in seen:
                raise ValueError('duplicate relic skill relation')
            if source_skills[target]['class'] != profession.removeprefix('hc.profession.'):
                raise ValueError('cross-class relic skill relation')
            seen.add(target)
            count += 1
    for row in authority['items']:
        if type(row.get('item_id')) is not int or records.get(identity('item', row['item_id']), {}).get('kind') != 'item':
            raise ValueError('invalid relic item relation')
        if row['item_id'] in (950201, 950202, 950203):
            target = row.get('skill_profession_id')
            if not isinstance(target, str) or records.get(target, {}).get('kind') != 'profession' or target not in pools:
                raise ValueError('invalid relic badge profession relation')
    return {'pool_skill_count': count}


def validate_item_categories(document, records):
    """One closed source owns category identity and exact legacy enum ingress."""
    keys(document, ['schema_version', 'contract_id', 'records'])
    if type(document['schema_version']) is not int or document['schema_version'] != 1 \
            or document['contract_id'] != 'hardcore.item_categories.v1' or not isinstance(document['records'], list):
        raise ValueError('unsupported category source')
    physical_slots = {f'hc.slot.{symbol}' for symbol in ('weapon', 'armor', 'helmet', 'necklace',
        'bracelet_left', 'bracelet_right', 'ring_left', 'ring_right', 'relic', 'badge')}
    aliases = {}
    categories = set()
    for row in document['records']:
        keys(row, ['category_id', 'display_name', 'legacy_categories', 'equipment_slots'])
        category = identity('item_category', row['category_id'])
        if records.get(category, {}).get('kind') != 'item_category' or category in categories \
                or not isinstance(row['display_name'], str) or not row['display_name'] \
                or not isinstance(row['legacy_categories'], list) or not row['legacy_categories']:
            raise ValueError('invalid category source record')
        categories.add(category)
        for old in row['legacy_categories']:
            if not isinstance(old, str) or not old or old.startswith('hc.'):
                raise ValueError('invalid category legacy enum')
            if old in aliases:
                raise ValueError('duplicate category legacy enum')
            aliases[old] = category
        slots = row['equipment_slots']
        if not isinstance(slots, list) or any(not isinstance(slot, str) or slot not in physical_slots
                or records.get(slot, {}).get('kind') != 'slot' for slot in slots) or len(set(slots)) != len(slots):
            raise ValueError('invalid category slot relation')
    if categories != {key for key, row in records.items() if row['kind'] == 'item_category'}:
        raise ValueError('incomplete category source')
    return aliases


def build(source=SOURCE, root=ROOT):
    policy = read(source)
    keys(policy, ["schema_version", "contract_id", "sources", "explicit"], ["aliases"])
    if policy["schema_version"] != 1 or policy["contract_id"] != CONTRACT or not isinstance(policy["sources"], list) or not isinstance(policy["explicit"], list):
        raise ValueError("invalid identity policy")
    provenance = {}
    records = {}
    legacy_index = {}

    def add(kind, legacy, name, path, pointer, formal=None):
        if kind not in KINDS:
            raise ValueError(f"unknown identity kind: {kind}")
        uid = identity(kind, legacy) if formal is None else formal
        if not isinstance(uid, str) or not ASCII_ID.fullmatch(uid) or not uid.startswith(f"hc.{kind}."):
            raise ValueError(f"invalid formal ID: {uid!r}")
        if kind in NUMERIC or kind == "skill":
            if uid != identity(kind, legacy):
                raise ValueError(f"formal/legacy identity mismatch: {uid}")
        elif not isinstance(legacy, str) or not legacy:
            raise ValueError(f"invalid explicit symbolic mapping: {uid}")
        if not isinstance(name, str) or not name:
            raise ValueError(f"missing display metadata: {uid}")
        key = (kind, json.dumps(legacy, ensure_ascii=True))
        if key in legacy_index and legacy_index[key] != uid:
            raise ValueError(f"conflicting legacy mapping: {key}")
        legacy_index[key] = uid
        evidence = {"path": "res://" + path, "pointer": pointer}
        if uid in records:
            previous = records[uid]
            if previous["kind"] != kind or previous["legacy_id"] != legacy or previous["display_name"] != name:
                raise ValueError(f"conflicting registration: {uid}")
            if evidence in previous["evidence"]:
                raise ValueError(f"duplicate source record: {uid}:{pointer}")
            previous["evidence"].append(evidence)
            return
        records[uid] = {"id": uid, "kind": kind, "legacy_id": legacy, "display_name": name, "evidence": [evidence]}

    for lane in policy["sources"]:
        keys(lane, ["kind", "path", "records", "id_field", "display_field"], ["filter", "mode", "allow_repeated_identity"])
        if type(lane.get("allow_repeated_identity", False)) is not bool:
            raise ValueError("invalid identity multiplicity policy")
        if lane.get("mode") not in [None, "purity_range", "legacy_map_runtime_id"]:
            raise ValueError("unknown identity transformation")
        relative = lane["path"]
        if not isinstance(relative, str) or not relative.startswith("assets/data/") or ".." in Path(relative).parts:
            raise ValueError("source path outside authoring data")
        path = root / relative
        document = read(path)
        provenance["res://" + relative] = digest(path)
        rows = document if lane["records"] == "" else document[lane["records"]]
        if lane.get("mode") == "purity_range":
            if not isinstance(rows, dict):
                raise ValueError("invalid purity authority")
            for purity in range(rows["min_purity"], rows["max_purity"] + 1):
                add(lane["kind"], rows[lane["id_field"]] + purity, rows[lane["display_field"]], relative, f"/purity/{purity}")
            continue
        if lane["records"] == "":
            rows = [rows]
        if not isinstance(rows, list):
            raise ValueError("identity source records must be an array")
        filter_fields = lane.get("filter", {})
        seen_in_lane = set()
        if not isinstance(filter_fields, dict):
            raise ValueError("invalid explicit lane filter")
        for index, row in enumerate(rows):
            if not isinstance(row, dict):
                raise ValueError("invalid source record")
            if any(row.get(k) != v for k, v in filter_fields.items()):
                continue
            old_id = row[lane["id_field"]]
            if lane.get("mode") == "legacy_map_runtime_id" and isinstance(old_id, str):
                # Exact existing GameData._normalize_map_ids contract, never names.
                if not re.fullmatch(r"LATE-[0-9]{3}", old_id):
                    raise ValueError(f"unknown legacy map identity: {old_id!r}")
                old_id = 900000 + int(old_id.removeprefix("LATE-"))
            key = json.dumps(old_id, ensure_ascii=True)
            if key in seen_in_lane and not lane.get("allow_repeated_identity", False):
                raise ValueError(f"duplicate primary identity in source: {relative}:{old_id}")
            seen_in_lane.add(key)
            add(lane["kind"], old_id, row[lane["display_field"]], relative, f"/{lane['records']}/{index}")
    policy_path = source.relative_to(root).as_posix()
    provenance["res://" + policy_path] = digest(source)
    for index, entry in enumerate(policy["explicit"]):
        keys(entry, ["id", "kind", "legacy_id", "display_name"])
        add(entry["kind"], entry["legacy_id"], entry["display_name"], policy_path, f"/explicit/{index}", entry["id"])
    seen_aliases = set()
    seen_targets = set()
    for index, entry in enumerate(policy.get("aliases", [])):
        keys(entry, ["alias_id", "canonical_id", "evidence"])
        alias = records.get(entry["alias_id"], {})
        target = records.get(entry["canonical_id"], {})
        if alias.get("kind") != "service_item" or target.get("kind") != "item" or entry["alias_id"] in seen_aliases or entry['canonical_id'] in seen_targets:
            raise ValueError("invalid or duplicate explicit item alias")
        if not isinstance(entry['evidence'], list) or not entry['evidence']:
            raise ValueError('missing item alias evidence')
        for evidence in entry['evidence']:
            keys(evidence, ['path', 'pointer'])
            if evidence['path'] not in provenance or not isinstance(evidence['pointer'], str) or not evidence['pointer'].startswith('/'):
                raise ValueError('invalid item alias evidence')
        seen_aliases.add(entry['alias_id'])
        seen_targets.add(entry['canonical_id'])
        alias['canonical_id'] = entry['canonical_id']
        alias['evidence'].append({'path': 'res://' + policy_path, 'pointer': f'/aliases/{index}'})
    item_authority = 'assets/data/item_runtime_authority_v1.json'
    if 'res://' + item_authority in provenance:
        validate_skill_book_bindings(read(root/item_authority),
            read(root/'assets/data/service_item_catalog.json'), records)
    relic_authority = 'assets/data/relic_synthesis_v1.json'
    if 'res://' + relic_authority in provenance:
        validate_relic_bindings(read(root/relic_authority),
            read(root/'assets/data/vanilla_176/skills_source_of_truth_v1.json'), records)
    equipment_grant_source = root / 'assets/data/equipment_granted_skills.source.json'
    provenance['res://assets/data/equipment_granted_skills.source.json'] = digest(equipment_grant_source)
    validate_equipment_granted_bindings(root, records)
    category_authority = 'assets/data/identity/item_categories_v1.json'
    if 'res://' + category_authority in provenance:
        validate_item_categories(read(root/category_authority), records)
    return {"schema_version": 1, "contract_id": CONTRACT, "source_hashes": dict(sorted(provenance.items())),
            "records": [records[uid] for uid in sorted(records)], "counts": dict(sorted(Counter(r["kind"] for r in records.values()).items()))}


def encode(document):
    return (json.dumps(document, ensure_ascii=False, indent=2) + "\n").encode("utf-8")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    document = build()
    content = encode(document)
    if args.check:
        if not OUTPUT.is_file() or OUTPUT.read_bytes() != content:
            raise SystemExit("FAIL: entity registry differs from explicit authoring sources")
    else:
        OUTPUT.parent.mkdir(parents=True, exist_ok=True)
        OUTPUT.write_bytes(content)
    print(json.dumps({"status": "PASS", "mode": "check" if args.check else "generate", "counts": document["counts"], "sha256": hashlib.sha256(content).hexdigest()}))


if __name__ == "__main__":
    main()
