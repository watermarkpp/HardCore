#!/usr/bin/env python3
"""Static checks for the explicit-user equipment attribute master v2."""

from __future__ import annotations

import json
from collections import Counter
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MASTER = json.loads(
    (ROOT / "assets/data/equipment_attribute_master.json").read_text(
        encoding="utf-8"
    )
)
ITEMS = json.loads(
    (ROOT / "assets/data/vanilla_176/items.json").read_text(encoding="utf-8")
)
SCHEMA = json.loads(
    (
        ROOT / "assets/data/rules/equipment_attribute_master_schema.json"
    ).read_text(encoding="utf-8")
)

CONTRACT = "equipment.attribute.master.v2"
DISTRIBUTION = "project.hardcore.equipment_attribute_master.v2"
WORKBOOK_SHA256 = (
    "CEEB2E68D07E2FFA112C46A954D04AAB68A95A576634199E05AB98FF23ABF83D"
)
LEGACY_SHA256 = (
    "8C87CD85F4E5FAF00E8D9F85E4394F021EB5EA26AC74CB453CC370BA10452F98"
)
WEAPON_IDS = set(range(80, 116)) | {223}
ARMOR_IDS = {116, 118, 120, 122, 124, 126, 128, 130, 132, 140, 142, 144}
LEGACY_IDS = WEAPON_IDS | ARMOR_IDS
ACCESSORY_CATEGORIES = {"头盔", "项链", "手镯", "戒指"}
ACCESSORY_IDS = {
    row["itemId"]
    for row in ITEMS["records"]
    if row["category"] in ACCESSORY_CATEGORIES
}
NEED = {"level": 0, "max_dc": 1, "max_mc": 2, "max_sc": 3}


def item_by_id() -> dict[int, dict]:
    return {row["itemId"]: row for row in ITEMS["records"]}


def main() -> None:
    assert MASTER["schemaVersion"] == 2
    assert MASTER["schemaRef"].endswith(
        "equipment_attribute_master_schema.json"
    )
    assert MASTER["contractId"] == CONTRACT
    assert MASTER["distribution"] == DISTRIBUTION
    assert MASTER["evidenceSha256"] == WORKBOOK_SHA256
    assert MASTER["sourceTier"] == "primary"
    assert MASTER["sourceKind"] == "explicit_user_primary_override"
    assert MASTER["fallbackEvidence"] == []
    assert MASTER["blankOverridePolicy"] == "preserve_existing_value"
    assert MASTER["scope"] == {
        "weaponRecords": 37,
        "maleArmorRecords": 12,
        "helmetRecords": 12,
        "necklaceRecords": 32,
        "braceletRecords": 31,
        "ringRecords": 39,
        "workbookOverrideRecords": 114,
        "totalRecords": 163,
    }
    assert MASTER["units"]["magicEvasionPercentPerPoint"] == 10
    assert SCHEMA["$id"] == "equipment.attribute.master.schema.v2"
    assert SCHEMA["properties"]["contractId"]["const"] == CONTRACT
    assert SCHEMA["properties"]["records"]["minItems"] == 163

    records = {row["itemId"]: row for row in MASTER["records"]}
    assert len(records) == 163
    assert set(records) == LEGACY_IDS | ACCESSORY_IDS
    assert len(ACCESSORY_IDS) == 114
    synced = item_by_id()

    for item_id, master in records.items():
        item = synced[item_id]
        assert master["source"]["contractId"] == CONTRACT
        assert master["source"]["distribution"] == DISTRIBUTION
        assert master["source"]["tier"] == "primary"
        assert master["source"]["fallbackEvidence"] == []
        assert item["source"] == DISTRIBUTION
        assert item["attributeSource"] == master["source"]
        assert item["jobAffinity"] == master["jobAffinity"]
        assert item["jobLock"] == master["jobLock"]
        assert item["requirementType"] == master["requirementType"]
        assert item["requirementValue"] == master["requirementValue"]
        assert item["legacyNeed"] == NEED[master["requirementType"]]
        assert item["legacyNeedLevel"] == master["requirementValue"]
        assert item["weight"] == master["weight"]
        assert item["durability"] == master["durability"]
        assert item["attributeWarnings"] == master["warnings"]
        assert item["reqLevel"] == (
            master["requirementValue"]
            if master["requirementType"] == "level"
            else 0
        )
        assert item["reqAttack"] == (
            master["requirementValue"]
            if master["requirementType"] == "max_dc"
            else None
        )
        assert item["reqMagic"] == (
            master["requirementValue"]
            if master["requirementType"] == "max_mc"
            else None
        )
        assert item["reqTao"] == (
            master["requirementValue"]
            if master["requirementType"] == "max_sc"
            else None
        )

    for item_id in LEGACY_IDS:
        record = records[item_id]
        assert (
            record["source"]["sourceKind"]
            == "explicit_user_primary_revision"
        )
        assert record["source"]["evidenceSha256"] == LEGACY_SHA256
        assert record["source"]["previousContractId"] == (
            "equipment.attribute.master.v1"
        )

    for item_id in ACCESSORY_IDS:
        record = records[item_id]
        item = synced[item_id]
        assert record["source"]["sourceKind"] == (
            "explicit_user_primary_override"
        )
        assert record["source"]["evidenceSha256"] == WORKBOOK_SHA256
        assert record["source"]["originalPath"].endswith(
            "HardCore_装备系统核对清单_审核修正版_2026-07-25.xlsx"
        )
        assert record["source"]["recordKey"].startswith("修正后装备主表!A")
        assert record["source"]["reviewStatus"] == record["review"]["status"]
        assert record["source"]["evidenceGrade"] == record["review"]["grade"]
        assert record["review"]["blankOverridePolicy"] == (
            "preserve_existing_value"
        )
        assert record["jobLock"] is None
        assert record["weightRequirementType"] == "wear"
        assert record["weightRequirementValue"] == record["weight"]
        assert item["attributeReview"] == record["review"]

    review_counts = Counter(
        records[item_id]["review"]["status"] for item_id in ACCESSORY_IDS
    )
    assert review_counts == Counter(
        {
            "已确认": 57,
            "已修正": 51,
            "特殊机制确认": 3,
            "已补齐特效": 2,
            "低置信待确认": 1,
        }
    )
    requirement_counts = Counter(
        records[item_id]["requirementType"] for item_id in ACCESSORY_IDS
    )
    assert requirement_counts == Counter(
        {"level": 79, "max_dc": 11, "max_mc": 12, "max_sc": 12}
    )

    assert sum("accuracy" in records[item_id] for item_id in ACCESSORY_IDS) == 9
    assert sum("agility" in records[item_id] for item_id in ACCESSORY_IDS) == 4
    assert sum("luck" in records[item_id] for item_id in ACCESSORY_IDS) == 0
    assert sum("curse" in records[item_id] for item_id in ACCESSORY_IDS) == 0
    assert (
        sum(
            "magicEvasionPercent" in records[item_id]
            for item_id in ACCESSORY_IDS
        )
        == 2
    )
    assert (
        sum("attackSpeedTier" in records[item_id] for item_id in ACCESSORY_IDS)
        == 2
    )
    assert sum("setId" in records[item_id] for item_id in ACCESSORY_IDS) == 17
    assert (
        sum("specialEffectId" in records[item_id] for item_id in ACCESSORY_IDS)
        == 28
    )

    for item_id in ACCESSORY_IDS:
        record = records[item_id]
        if "magicEvasionPercent" not in record:
            continue
        assert record["magicEvasionPercentPerPoint"] == 10
        assert record["magicEvasionPercent"] == (
            record["magicEvasionPoints"]
            * record["magicEvasionPercentPerPoint"]
        )
        item = synced[item_id]
        assert item["magicEvasionPercent"] == record["magicEvasionPercent"]
        assert item["magicEvasionPoints"] == record["magicEvasionPoints"]

    assert records[159]["name"] == "白色虎齿项链"
    assert records[159]["magicEvasionPercent"] == 20
    assert records[159]["magicEvasionPoints"] == 2
    assert records[164]["magicEvasionPercent"] == 10
    assert records[164]["magicEvasionPoints"] == 1
    assert records[221]["attackSpeedTier"] == 2
    assert records[222]["attackSpeedTier"] == 1
    assert records[169]["requirementType"] == "max_mc"
    assert records[169]["requirementValue"] == 25
    assert records[169]["accuracy"] == 1
    assert records[160]["requirementType"] == "max_sc"
    assert records[160]["agility"] == 3
    assert records[225]["jobAffinity"] == "general"
    assert records[225]["jobAffinityLabel"] == "通用（祈祷套装）"
    assert records[225]["setId"] == "prayer_set"
    assert records[225]["specialEffectId"] == "prayer_pet_rebellion"
    assert records[252]["specialEffectId"] == "melee_paralysis"

    reverse_keys = {
        (record["itemId"], warning["field"])
        for record in MASTER["records"]
        for warning in record["warnings"]
        if warning["warningCode"] == "legacy_reverse_range"
    }
    assert reverse_keys == {
        (88, "dc"),
        (111, "dc"),
        (112, "dc"),
        (112, "mc"),
        (112, "sc"),
        (156, "dc"),
        (157, "mc"),
        (158, "sc"),
        (161, "dc"),
        (162, "mc"),
        (164, "dc"),
        (202, "dc"),
        (244, "sc"),
    }
    black_iron_glove = records[196]
    assert black_iron_glove["review"]["status"] == "低置信待确认"
    assert black_iron_glove["review"]["grade"] == "C"
    assert any(
        warning["warningCode"] == "low_confidence_user_override"
        and warning["isError"] is False
        for warning in black_iron_glove["warnings"]
    )

    assert records[111]["contentLayer"] == "classic_legendary"
    assert records[111]["historicalStatus"] == "official_existence_unverified"
    print(
        "EQUIPMENT_ATTRIBUTE_MASTER_STATIC_PASS: "
        "163 unique records, 114 explicit workbook overrides, units verified"
    )


if __name__ == "__main__":
    main()
