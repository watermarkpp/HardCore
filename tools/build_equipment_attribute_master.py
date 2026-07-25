#!/usr/bin/env python3
"""Build the user-authorized equipment attribute master and sync runtime items."""

from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ITEMS_PATH = ROOT / "assets/data/vanilla_176/items.json"
MASTER_PATH = ROOT / "assets/data/equipment_attribute_master.json"

CONTRACT_ID = "equipment.attribute.master.v1"
DISTRIBUTION = "project.hardcore.equipment_attribute_master.v1"
EVIDENCE_SHA256 = "8C87CD85F4E5FAF00E8D9F85E4394F021EB5EA26AC74CB453CC370BA10452F98"
ROLL_POLICY = "legacy_clamp_negative_span"

WEAPON_IDS = list(range(80, 116)) + [223]
ARMOR_IDS = [116, 118, 120, 122, 128, 140, 124, 130, 142, 126, 132, 144]
TARGET_IDS = set(WEAPON_IDS + ARMOR_IDS)

# item_id: (requirementType, requirementValue)
REQUIREMENTS = {
    80: ("level", 1), 81: ("level", 1), 82: ("level", 1),
    83: ("level", 5), 84: ("level", 10), 85: ("level", 10),
    86: ("level", 11), 87: ("level", 13), 88: ("level", 15),
    89: ("level", 15), 90: ("level", 15), 91: ("level", 15),
    92: ("level", 19), 93: ("level", 20), 94: ("level", 20),
    95: ("level", 20), 96: ("level", 20), 97: ("level", 22),
    98: ("level", 25), 99: ("level", 26), 100: ("level", 26),
    101: ("level", 26), 102: ("level", 28), 103: ("max_mc", 27),
    104: ("max_sc", 25), 105: ("level", 30), 106: ("level", 35),
    107: ("level", 35), 108: ("level", 34), 109: ("level", 35),
    110: ("level", 35), 111: ("level", 40), 112: ("level", 0),
    113: ("max_dc", 46), 114: ("max_mc", 28), 115: ("level", 35),
    223: ("level", 20),
    116: ("level", 1), 118: ("level", 11), 120: ("level", 16),
    122: ("level", 22), 128: ("max_dc", 46), 140: ("level", 40),
    124: ("level", 22), 130: ("max_mc", 28), 142: ("level", 40),
    126: ("level", 22), 132: ("max_sc", 27), 144: ("level", 40),
}

NEED_BY_TYPE = {"level": 0, "max_dc": 1, "max_mc": 2, "max_sc": 3}
PROFESSION_BY_AFFINITY = {
    "general": "通用",
    "warrior": "战士",
    "wizard": "法师",
    "taoist": "道士",
}


def affinity_for(record: dict) -> str:
    if record["itemId"] == 112:
        return "general"
    return {
        "通用": "general",
        "战士": "warrior",
        "法师": "wizard",
        "道士": "taoist",
    }[record["profession"]]


def range_record(record: dict, prefix: str) -> dict | None:
    minimum = record.get(f"{prefix}Min")
    maximum = record.get(f"{prefix}Max")
    if minimum is None and maximum is None:
        return None
    return {"min": minimum, "max": maximum, "rollPolicy": ROLL_POLICY}


def warnings_for(record: dict) -> list[dict]:
    warnings = []
    for field, prefix in (("dc", "attack"), ("mc", "magic"), ("sc", "tao")):
        minimum = record.get(f"{prefix}Min")
        maximum = record.get(f"{prefix}Max")
        if minimum is not None and maximum is not None and minimum > maximum:
            warnings.append(
                {
                    "warningCode": "legacy_reverse_range",
                    "field": field,
                    "min": minimum,
                    "max": maximum,
                    "runtimeBehavior": ROLL_POLICY,
                    "isError": False,
                }
            )
    return warnings


def sync_compatibility_fields(record: dict, requirement_type: str, value: int) -> None:
    record["reqLevel"] = value if requirement_type == "level" else 0
    record["reqAttack"] = value if requirement_type == "max_dc" else None
    record["reqMagic"] = value if requirement_type == "max_mc" else None
    record["reqTao"] = value if requirement_type == "max_sc" else None
    record["profession"] = PROFESSION_BY_AFFINITY[record["jobAffinity"]]


def master_record(record: dict) -> dict:
    requirement_type, requirement_value = REQUIREMENTS[record["itemId"]]
    ranges = {
        key: value
        for key, value in (
            ("dc", range_record(record, "attack")),
            ("mc", range_record(record, "magic")),
            ("sc", range_record(record, "tao")),
            ("ac", range_record(record, "defense")),
            ("mac", range_record(record, "mdef")),
        )
        if value is not None
    }
    result = {
        "itemId": record["itemId"],
        "name": record["name"],
        "category": record["category"],
        "jobAffinity": affinity_for(record),
        "jobLock": None,
        "requirementType": requirement_type,
        "requirementValue": requirement_value,
        "legacyNeed": NEED_BY_TYPE[requirement_type],
        "legacyNeedLevel": requirement_value,
        "genderRestriction": "male" if record["itemId"] in ARMOR_IDS else None,
        "weightRequirementType": "wear" if record["itemId"] in ARMOR_IDS else "hand",
        "weightRequirementValue": record["weight"],
        "weight": record["weight"],
        "durability": record["durability"],
        "rollPolicy": ROLL_POLICY,
        "stats": ranges,
        "warnings": warnings_for(record),
        "source": {
            "tier": "primary",
            "contractId": CONTRACT_ID,
            "distribution": DISTRIBUTION,
            "evidenceSha256": EVIDENCE_SHA256,
            "originalPath": "user_authorized_attachment/pasted-text.txt",
            "fallbackEvidence": [],
        },
        "supportingReferences": [
            {"url": record.get("sourceUrl", ""), "role": "supporting_reference"},
            {"url": record.get("secondarySourceUrl", ""), "role": "supporting_reference"},
        ],
    }
    if record["itemId"] == 111:
        result["contentLayer"] = "classic_legendary"
        result["historicalStatus"] = "official_existence_unverified"
    return result


def main() -> None:
    catalog = json.loads(ITEMS_PATH.read_text(encoding="utf-8"))
    selected = [row for row in catalog["records"] if row["itemId"] in TARGET_IDS]
    if len(selected) != 49 or {row["itemId"] for row in selected} != TARGET_IDS:
        raise RuntimeError("expected exactly the authorized 37 weapons and 12 male armors")

    master_records = [master_record(row) for row in selected]
    master_by_id = {row["itemId"]: row for row in master_records}
    for row in catalog["records"]:
        if row["itemId"] not in TARGET_IDS:
            continue
        master = master_by_id[row["itemId"]]
        for field in (
            "jobAffinity", "jobLock", "requirementType", "requirementValue",
            "legacyNeed", "legacyNeedLevel", "genderRestriction",
            "weightRequirementType", "weightRequirementValue", "rollPolicy",
        ):
            row[field] = master[field]
        row["attributeWarnings"] = master["warnings"]
        row["source"] = DISTRIBUTION
        row["attributeSource"] = master["source"]
        row["sourceUrlRole"] = "supporting_reference"
        row["secondarySourceUrlRole"] = "supporting_reference"
        if row["itemId"] == 111:
            row["contentLayer"] = "classic_legendary"
            row["historicalStatus"] = "official_existence_unverified"
        sync_compatibility_fields(row, row["requirementType"], row["requirementValue"])

    master = {
        "schemaVersion": 1,
        "contractId": CONTRACT_ID,
        "distribution": DISTRIBUTION,
        "evidenceSha256": EVIDENCE_SHA256,
        "sourceTier": "primary",
        "originalPath": "user_authorized_attachment/pasted-text.txt",
        "fallbackEvidence": [],
        "scope": {
            "weaponRecords": 37,
            "maleArmorRecords": 12,
            "totalRecords": 49,
        },
        "supportingReferencePolicy": {
            "21cq": "supporting_reference_only",
            "17173": "supporting_reference_only",
        },
        "records": master_records,
    }
    MASTER_PATH.write_text(
        json.dumps(master, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    ITEMS_PATH.write_text(
        json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )


if __name__ == "__main__":
    main()
