#!/usr/bin/env python3
"""Build the equipment attribute master from explicit user primary evidence.

The first 49 weapon/male-armor records retain their original explicit-user
evidence. Twelve female armor counterparts are restored by the explicit
2026-08-10 correction contract after the exact IDs were proven absent from the
primary master. The 114 accessory/headwear records are imported from the
user-authorized review workbook. Crystal server_data is never consulted for
equipment attributes.
XLSX is parsed with the standard ZIP/XML format so the audit has no third-party
dependency and reads every worksheet cell before accepting data.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import xml.etree.ElementTree as ET
import zipfile
from collections import Counter
from copy import deepcopy
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
ITEMS_PATH = ROOT / "assets/data/vanilla_176/items.json"
MASTER_PATH = ROOT / "assets/data/equipment_attribute_master.json"
FEMALE_ARMOR_EVIDENCE_PATH = (
    ROOT / "assets/data/equipment_female_armor_attribute_evidence.json"
)

CONTRACT_ID = "equipment.attribute.master.v2"
DISTRIBUTION = "project.hardcore.equipment_attribute_master.v2"
LEGACY_CONTRACT_ID = "equipment.attribute.master.v1"
LEGACY_DISTRIBUTION = "project.hardcore.equipment_attribute_master.v1"
LEGACY_EVIDENCE_SHA256 = (
    "8C87CD85F4E5FAF00E8D9F85E4394F021EB5EA26AC74CB453CC370BA10452F98"
)
WORKBOOK_EVIDENCE_SHA256 = (
    "CEEB2E68D07E2FFA112C46A954D04AAB68A95A576634199E05AB98FF23ABF83D"
)
WORKBOOK_BASENAME = "HardCore_装备系统核对清单_审核修正版_2026-07-25.xlsx"
WORKBOOK_SOURCE_PATH = f"user_authorized_attachment/{WORKBOOK_BASENAME}"
WORKBOOK_SHEET = "修正后装备主表"
FEMALE_ARMOR_CORRECTION_SOURCE_PATH = (
    "user_authorized_task/2026-08-10-equipment-foundation-audit"
)
FEMALE_ARMOR_CORRECTION_EVIDENCE_SHA256 = (
    "59FCA9C1F220041E3C6D144FC58AFA6CDE9FC02A785EE7FF8381E9136E5E0DA9"
)
ROLL_POLICY = "legacy_clamp_negative_span"
MAGIC_EVASION_PERCENT_PER_POINT = 10

WEAPON_IDS = set(range(80, 116)) | {223}
ARMOR_IDS = {116, 118, 120, 122, 124, 126, 128, 130, 132, 140, 142, 144}
LEGACY_TARGET_IDS = WEAPON_IDS | ARMOR_IDS
FEMALE_ARMOR_PAIRS = {
    117: 116,
    119: 118,
    121: 120,
    123: 122,
    125: 124,
    127: 126,
    129: 128,
    131: 130,
    133: 132,
    141: 140,
    143: 142,
    145: 144,
}
ACCESSORY_CATEGORIES = {"头盔", "项链", "手镯", "戒指"}
NEED_BY_TYPE = {"level": 0, "max_dc": 1, "max_mc": 2, "max_sc": 3}
PROFESSION_TO_AFFINITY = {
    "通用": "general",
    "战士": "warrior",
    "法师": "wizard",
    "道士": "taoist",
}
AFFINITY_TO_PROFESSION = {
    "general": "通用",
    "warrior": "战士",
    "wizard": "法师",
    "taoist": "道士",
}
GENDER_TO_RESTRICTION = {"通用": None, "男": "male", "女": "female"}

EXPECTED_SHEETS = [
    "总览",
    "属性核对",
    "来源证据",
    "套装特效",
    "视觉映射",
    "分发维修",
    "全装备视觉例外",
    "来源清单",
    "审核修正汇总",
    WORKBOOK_SHEET,
]
EXPECTED_MAIN_HEADERS = [
    "itemId", "名称", "分类", "职业定位", "职业硬锁", "需求类型",
    "需求数值", "性别", "物品重量", "耐久", "DC下限", "DC上限",
    "MC下限", "MC上限", "SC下限", "SC上限", "AC下限", "AC上限",
    "MAC下限", "MAC上限", "准确", "敏捷", "幸运", "诅咒",
    "魔法躲避%", "攻击速度", "套装ID", "特殊效果ID", "特殊效果",
    "审核结论", "证据等级", "修正/缺失说明", "备注", "来源1",
    "来源2", "审核日期",
]
ALLOWED_REVIEW_STATUSES = {
    "已确认", "已修正", "特殊机制确认", "已补齐特效", "低置信待确认",
}
RANGE_COLUMNS = {
    "dc": ("DC下限", "DC上限", "attackMin", "attackMax"),
    "mc": ("MC下限", "MC上限", "magicMin", "magicMax"),
    "sc": ("SC下限", "SC上限", "taoMin", "taoMax"),
    "ac": ("AC下限", "AC上限", "defenseMin", "defenseMax"),
    "mac": ("MAC下限", "MAC上限", "mdefMin", "mdefMax"),
}
SCALAR_COLUMNS = {
    "accuracy": ("准确", "accuracy"),
    "agility": ("敏捷", "agility"),
    "luck": ("幸运", "luck"),
    "curse": ("诅咒", "curse"),
}

NS_MAIN = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
NS_REL = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest().upper()


def column_number(cell_reference: str) -> int:
    match = re.match(r"([A-Z]+)", cell_reference)
    if match is None:
        raise ValueError(f"invalid XLSX cell reference: {cell_reference}")
    value = 0
    for character in match.group(1):
        value = value * 26 + ord(character) - ord("A") + 1
    return value


def normalized_zip_target(target: str) -> str:
    normalized = target.lstrip("/")
    return normalized if normalized.startswith("xl/") else f"xl/{normalized}"


def read_xlsx_workbook(path: Path) -> dict[str, Any]:
    """Read all workbook sheets/cells/formulas/styles for auditable ingestion."""
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        shared_strings: list[str] = []
        if "xl/sharedStrings.xml" in names:
            shared_root = ET.fromstring(archive.read("xl/sharedStrings.xml"))
            for string_item in shared_root.findall(f"{{{NS_MAIN}}}si"):
                shared_strings.append(
                    "".join(
                        text.text or ""
                        for text in string_item.iter(f"{{{NS_MAIN}}}t")
                    )
                )

        workbook_root = ET.fromstring(archive.read("xl/workbook.xml"))
        relationship_root = ET.fromstring(
            archive.read("xl/_rels/workbook.xml.rels")
        )
        targets = {
            relationship.attrib["Id"]: relationship.attrib["Target"]
            for relationship in relationship_root
        }

        sheets: list[dict[str, Any]] = []
        cell_count = 0
        formula_count = 0
        style_ids: set[int] = set()
        for sheet_node in workbook_root.find(f"{{{NS_MAIN}}}sheets") or []:
            relationship_id = sheet_node.attrib[f"{{{NS_REL}}}id"]
            target = normalized_zip_target(targets[relationship_id])
            sheet_root = ET.fromstring(archive.read(target))
            rows: list[dict[str, Any]] = []
            for row_node in sheet_root.findall(f".//{{{NS_MAIN}}}row"):
                values: dict[int, Any] = {}
                formulas: dict[int, str] = {}
                styles: dict[int, int] = {}
                for cell in row_node.findall(f"{{{NS_MAIN}}}c"):
                    reference = cell.attrib["r"]
                    column = column_number(reference)
                    cell_type = cell.attrib.get("t", "")
                    value_node = cell.find(f"{{{NS_MAIN}}}v")
                    inline_node = cell.find(f"{{{NS_MAIN}}}is")
                    formula_node = cell.find(f"{{{NS_MAIN}}}f")
                    value: Any = ""
                    if cell_type == "s" and value_node is not None:
                        value = shared_strings[int(value_node.text or "0")]
                    elif cell_type == "inlineStr" and inline_node is not None:
                        value = "".join(
                            text.text or ""
                            for text in inline_node.iter(f"{{{NS_MAIN}}}t")
                        )
                    elif cell_type == "b" and value_node is not None:
                        value = value_node.text == "1"
                    elif value_node is not None:
                        value = value_node.text or ""
                    values[column] = value
                    if formula_node is not None:
                        formulas[column] = formula_node.text or ""
                        formula_count += 1
                    style_id = int(cell.attrib.get("s", "0"))
                    styles[column] = style_id
                    style_ids.add(style_id)
                    cell_count += 1
                maximum_column = max(values, default=0)
                rows.append(
                    {
                        "rowNumber": int(row_node.attrib["r"]),
                        "values": [
                            values.get(column, "")
                            for column in range(1, maximum_column + 1)
                        ],
                        "formulas": formulas,
                        "styles": styles,
                    }
                )
            sheets.append(
                {
                    "name": sheet_node.attrib["name"],
                    "state": sheet_node.attrib.get("state", "visible"),
                    "target": target,
                    "rows": rows,
                }
            )

        return {
            "sheets": sheets,
            "cellCount": cell_count,
            "formulaCount": formula_count,
            "styleIds": sorted(style_ids),
            "tableParts": sorted(
                name for name in names if name.startswith("xl/tables/")
            ),
            "commentParts": sorted(
                name for name in names if "comment" in name.lower()
            ),
            "drawingParts": sorted(
                name
                for name in names
                if name.startswith("xl/drawings/") and name.endswith(".xml")
            ),
            "archiveEntryCount": len(names),
        }


def main_sheet_records(workbook: dict[str, Any]) -> list[dict[str, Any]]:
    by_name = {sheet["name"]: sheet for sheet in workbook["sheets"]}
    if list(by_name) != EXPECTED_SHEETS:
        raise RuntimeError(
            f"unexpected workbook sheets: expected {EXPECTED_SHEETS}, got {list(by_name)}"
        )
    sheet = by_name[WORKBOOK_SHEET]
    if sheet["state"] != "visible" or len(sheet["rows"]) != 115:
        raise RuntimeError("review master must be a visible 115-row worksheet")
    headers = sheet["rows"][0]["values"]
    if headers != EXPECTED_MAIN_HEADERS:
        raise RuntimeError("review master headers changed")
    records: list[dict[str, Any]] = []
    for row in sheet["rows"][1:]:
        values = row["values"] + [""] * (len(headers) - len(row["values"]))
        record = dict(zip(headers, values))
        record["_workbookRow"] = row["rowNumber"]
        record["_styleIds"] = sorted(set(row["styles"].values()))
        records.append(record)
    return records


def is_blank(value: Any) -> bool:
    return value is None or (isinstance(value, str) and value.strip() == "")


def integer(value: Any, label: str) -> int:
    if isinstance(value, bool) or is_blank(value):
        raise ValueError(f"{label} must contain an integer")
    number = float(str(value))
    if not number.is_integer():
        raise ValueError(f"{label} must be an integer: {value!r}")
    return int(number)


def validate_review_workbook(
    workbook_path: Path,
) -> tuple[dict[str, Any], list[dict[str, Any]], dict[str, Any]]:
    actual_sha256 = sha256_file(workbook_path)
    if actual_sha256 != WORKBOOK_EVIDENCE_SHA256:
        raise RuntimeError(
            f"review workbook SHA256 mismatch: {actual_sha256} "
            f"!= {WORKBOOK_EVIDENCE_SHA256}"
        )
    workbook = read_xlsx_workbook(workbook_path)
    records = main_sheet_records(workbook)
    ids = [integer(record["itemId"], "itemId") for record in records]
    if len(ids) != 114 or len(set(ids)) != 114:
        raise RuntimeError("review master must contain 114 unique itemIds")
    categories = Counter(record["分类"] for record in records)
    if categories != Counter({"头盔": 12, "项链": 32, "手镯": 31, "戒指": 39}):
        raise RuntimeError(f"unexpected accessory categories: {categories}")
    statuses = Counter(record["审核结论"] for record in records)
    if set(statuses) != ALLOWED_REVIEW_STATUSES:
        raise RuntimeError(f"unexpected review statuses: {statuses}")
    if statuses != Counter(
        {
            "已确认": 57,
            "已修正": 51,
            "特殊机制确认": 3,
            "已补齐特效": 2,
            "低置信待确认": 1,
        }
    ):
        raise RuntimeError(f"review status counts changed: {statuses}")
    if workbook["cellCount"] != 23087 or workbook["formulaCount"] != 8:
        raise RuntimeError("workbook complete-read cell/formula counts changed")
    if len(workbook["tableParts"]) != 7 or workbook["commentParts"]:
        raise RuntimeError("workbook table/comment structure changed")
    audit = {
        "workbookPath": WORKBOOK_SOURCE_PATH,
        "workbookSha256": actual_sha256,
        "sourceKind": "explicit_user_primary_override",
        "archiveEntryCount": workbook["archiveEntryCount"],
        "sheetCount": len(workbook["sheets"]),
        "sheetNames": [sheet["name"] for sheet in workbook["sheets"]],
        "cellCount": workbook["cellCount"],
        "formulaCount": workbook["formulaCount"],
        "styleIdsRead": workbook["styleIds"],
        "tablePartCount": len(workbook["tableParts"]),
        "drawingPartCount": len(workbook["drawingParts"]),
        "commentPartCount": len(workbook["commentParts"]),
        "reviewRecordCount": len(records),
        "uniqueItemIdCount": len(set(ids)),
        "categoryCounts": dict(categories),
        "reviewStatusCounts": dict(statuses),
    }
    return workbook, records, audit


def warning_records(record: dict[str, Any]) -> list[dict[str, Any]]:
    warnings: list[dict[str, Any]] = []
    for field, (_, _, minimum_key, maximum_key) in RANGE_COLUMNS.items():
        minimum = record.get(minimum_key)
        maximum = record.get(maximum_key)
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


def source_record(
    *,
    evidence_sha256: str,
    original_path: str,
    source_kind: str,
    record_key: str,
    previous_contract_id: str | None = None,
    review: dict[str, Any] | None = None,
) -> dict[str, Any]:
    result: dict[str, Any] = {
        "tier": "primary",
        "sourceKind": source_kind,
        "contractId": CONTRACT_ID,
        "distribution": DISTRIBUTION,
        "evidenceSha256": evidence_sha256,
        "originalPath": original_path,
        "recordKey": record_key,
        "fallbackEvidence": [],
    }
    if previous_contract_id:
        result["previousContractId"] = previous_contract_id
    if review:
        result["reviewStatus"] = review["status"]
        result["evidenceGrade"] = review["grade"]
        result["reviewDate"] = review["date"]
    return result


def migrate_legacy_record(record: dict[str, Any]) -> dict[str, Any]:
    result = deepcopy(record)
    old_source = record.get("source", {})
    result["source"] = source_record(
        evidence_sha256=str(
            old_source.get("evidenceSha256", LEGACY_EVIDENCE_SHA256)
        ),
        original_path=str(
            old_source.get("originalPath", "user_authorized_attachment/pasted-text.txt")
        ),
        source_kind="explicit_user_primary_revision",
        record_key=f"legacy-v1:itemId={record['itemId']}",
        previous_contract_id=LEGACY_CONTRACT_ID,
    )
    return result


def corrected_female_armor_record(
    female_item_id: int,
    male_master: dict[str, Any],
    runtime_identity: dict[str, Any],
    evidence_record: dict[str, Any],
) -> dict[str, Any]:
    """Restore one user-authorized female counterpart without guessing values.

    Numeric attributes and requirements are copied only from the paired primary
    record and are independently corroborated by the exact supporting page.
    Runtime items.json supplies identity compatibility only. The evidence
    contract records the pre-correction primary miss and that no auxiliary is
    eligible in the lane.
    """
    result = deepcopy(male_master)
    result["itemId"] = female_item_id
    result["name"] = str(runtime_identity["name"])
    result["genderRestriction"] = "female"
    result["source"] = source_record(
        evidence_sha256=FEMALE_ARMOR_CORRECTION_EVIDENCE_SHA256,
        original_path=FEMALE_ARMOR_CORRECTION_SOURCE_PATH,
        source_kind="explicit_user_task_correction",
        record_key=f"authorized-female-armor:itemId={female_item_id}",
    )
    result["source"].update(
        {
            "evidenceContract": (
                "res://assets/data/equipment_female_armor_attribute_evidence.json"
                f"#/records/{female_item_id}"
            ),
            "pairedPrimaryItemId": int(male_master["itemId"]),
            "pairedPrimaryEvidenceSha256": str(
                male_master["source"]["evidenceSha256"]
            ),
            "supportingReferenceUrl": str(evidence_record["supportingReference"]["url"]),
            "supportingReferenceContentSha256": str(
                evidence_record["supportingReference"]["contentSha256"]
            ),
            "primaryMissingEvidence": deepcopy(
                evidence_record["primaryMissingEvidence"]
            ),
            "auxiliarySearchEvidence": deepcopy(
                evidence_record["auxiliarySearchEvidence"]
            ),
            "fieldEvidence": deepcopy(evidence_record["fieldEvidence"]),
        }
    )
    result["supportingReferences"] = [
        {
            "url": str(evidence_record["supportingReference"]["url"]),
            "role": "supporting_reference",
            "contentSha256": str(
                evidence_record["supportingReference"]["contentSha256"]
            ),
        },
        {
            "url": str(runtime_identity.get("secondarySourceUrl", "")),
            "role": "supporting_reference",
        },
    ]
    return result


def build_female_armor_records(
    previous_master: dict[str, Any],
    catalog_by_id: dict[int, dict[str, Any]],
) -> list[dict[str, Any]]:
    evidence = json.loads(FEMALE_ARMOR_EVIDENCE_PATH.read_text(encoding="utf-8"))
    evidence_by_id = {
        int(item_id): record for item_id, record in evidence["records"].items()
    }
    master_by_id = {
        int(record["itemId"]): record for record in previous_master["records"]
    }
    if set(evidence_by_id) != set(FEMALE_ARMOR_PAIRS):
        raise RuntimeError("female armor evidence must cover the exact 12 target IDs")
    restored: list[dict[str, Any]] = []
    for female_item_id, male_item_id in FEMALE_ARMOR_PAIRS.items():
        male_master = master_by_id.get(male_item_id)
        runtime_identity = catalog_by_id.get(female_item_id)
        if male_master is None or runtime_identity is None:
            raise RuntimeError(
                f"female armor pair {male_item_id}/{female_item_id} is incomplete"
            )
        restored.append(
            corrected_female_armor_record(
                female_item_id,
                male_master,
                runtime_identity,
                evidence_by_id[female_item_id],
            )
        )
    return restored


def preserved_value(
    workbook_record: dict[str, Any],
    workbook_column: str,
    existing_value: Any,
    audit: dict[str, Any],
) -> Any:
    value = workbook_record[workbook_column]
    if is_blank(value):
        audit["blankCellsIgnored"] += 1
        if existing_value is not None:
            audit["existingValuesPreservedFromBlank"] += 1
        return existing_value
    audit["nonBlankWorkbookValuesApplied"] += 1
    return integer(value, workbook_column)


def reviewed_master_record(
    workbook_record: dict[str, Any],
    catalog_record: dict[str, Any],
    import_audit: dict[str, Any],
) -> dict[str, Any]:
    item_id = integer(workbook_record["itemId"], "itemId")
    if workbook_record["名称"] != catalog_record["name"]:
        raise RuntimeError(f"itemId {item_id} name mismatch")
    if workbook_record["分类"] != catalog_record["category"]:
        raise RuntimeError(f"itemId {item_id} category mismatch")
    if workbook_record["分类"] not in ACCESSORY_CATEGORIES:
        raise RuntimeError(f"itemId {item_id} is outside accessory scope")

    job_affinity_label = str(workbook_record["职业定位"])
    job_affinity_key = next(
        (
            display
            for display in PROFESSION_TO_AFFINITY
            if job_affinity_label == display
            or job_affinity_label.startswith(f"{display}（")
        ),
        None,
    )
    if job_affinity_key is None:
        raise RuntimeError(
            f"itemId {item_id} unsupported job affinity: {job_affinity_label}"
        )
    job_affinity = PROFESSION_TO_AFFINITY[job_affinity_key]
    job_lock = catalog_record.get("jobLock")
    if not is_blank(workbook_record["职业硬锁"]):
        job_lock = PROFESSION_TO_AFFINITY.get(
            str(workbook_record["职业硬锁"]),
            str(workbook_record["职业硬锁"]),
        )
    requirement_type = str(workbook_record["需求类型"])
    if requirement_type not in NEED_BY_TYPE:
        raise RuntimeError(f"itemId {item_id} unsupported requirement type")
    requirement_value = integer(workbook_record["需求数值"], "需求数值")
    gender = GENDER_TO_RESTRICTION[workbook_record["性别"]]
    weight = integer(workbook_record["物品重量"], "物品重量")
    durability = integer(workbook_record["耐久"], "耐久")

    ranges: dict[str, Any] = {}
    for field, (
        minimum_column,
        maximum_column,
        minimum_key,
        maximum_key,
    ) in RANGE_COLUMNS.items():
        minimum = preserved_value(
            workbook_record,
            minimum_column,
            catalog_record.get(minimum_key),
            import_audit,
        )
        maximum = preserved_value(
            workbook_record,
            maximum_column,
            catalog_record.get(maximum_key),
            import_audit,
        )
        if minimum is None and maximum is None:
            continue
        ranges[field] = {
            "min": minimum,
            "max": maximum,
            "rollPolicy": ROLL_POLICY,
        }

    scalar_values: dict[str, int] = {}
    for output_field, (workbook_column, catalog_field) in SCALAR_COLUMNS.items():
        value = preserved_value(
            workbook_record,
            workbook_column,
            catalog_record.get(catalog_field),
            import_audit,
        )
        if value is not None:
            scalar_values[output_field] = value

    review = {
        "status": str(workbook_record["审核结论"]),
        "grade": str(workbook_record["证据等级"]),
        "explanation": str(workbook_record["修正/缺失说明"]),
        "note": str(workbook_record["备注"]),
        "date": str(workbook_record["审核日期"]),
        "workbookRow": int(workbook_record["_workbookRow"]),
        "styleIds": workbook_record["_styleIds"],
        "blankOverridePolicy": "preserve_existing_value",
    }
    result: dict[str, Any] = {
        "itemId": item_id,
        "name": catalog_record["name"],
        "category": catalog_record["category"],
        "jobAffinity": job_affinity,
        "jobAffinityLabel": job_affinity_label,
        "jobLock": job_lock,
        "requirementType": requirement_type,
        "requirementValue": requirement_value,
        "legacyNeed": NEED_BY_TYPE[requirement_type],
        "legacyNeedLevel": requirement_value,
        "genderRestriction": gender,
        "weightRequirementType": "wear",
        "weightRequirementValue": weight,
        "weight": weight,
        "durability": durability,
        "rollPolicy": ROLL_POLICY,
        "stats": ranges,
        **scalar_values,
        "warnings": warning_records(
            {
                **{
                    minimum_key: ranges.get(field, {}).get("min")
                    for field, (
                        _,
                        _,
                        minimum_key,
                        _,
                    ) in RANGE_COLUMNS.items()
                },
                **{
                    maximum_key: ranges.get(field, {}).get("max")
                    for field, (
                        _,
                        _,
                        _,
                        maximum_key,
                    ) in RANGE_COLUMNS.items()
                },
            }
        ),
        "review": review,
        "source": source_record(
            evidence_sha256=WORKBOOK_EVIDENCE_SHA256,
            original_path=WORKBOOK_SOURCE_PATH,
            source_kind="explicit_user_primary_override",
            record_key=f"{WORKBOOK_SHEET}!A{review['workbookRow']}:AJ{review['workbookRow']}",
            review=review,
        ),
        "supportingReferences": [
            {
                "url": str(workbook_record[column]),
                "role": "workbook_supporting_reference",
            }
            for column in ("来源1", "来源2")
            if not is_blank(workbook_record[column])
        ],
    }

    magic_evasion_percent = preserved_value(
        workbook_record,
        "魔法躲避%",
        catalog_record.get("magicEvasionPercent"),
        import_audit,
    )
    if magic_evasion_percent is not None:
        if magic_evasion_percent % MAGIC_EVASION_PERCENT_PER_POINT != 0:
            raise RuntimeError(
                f"itemId {item_id} magic evasion must be a 10% multiple"
            )
        result["magicEvasionPercent"] = magic_evasion_percent
        result["magicEvasionPoints"] = (
            magic_evasion_percent // MAGIC_EVASION_PERCENT_PER_POINT
        )
        result["magicEvasionPercentPerPoint"] = MAGIC_EVASION_PERCENT_PER_POINT

    attack_speed_tier = preserved_value(
        workbook_record,
        "攻击速度",
        catalog_record.get("attackSpeedTier"),
        import_audit,
    )
    if attack_speed_tier is not None:
        result["attackSpeedTier"] = attack_speed_tier

    for workbook_column, output_field in (
        ("套装ID", "setId"),
        ("特殊效果ID", "specialEffectId"),
        ("特殊效果", "specialEffectDescription"),
    ):
        value = workbook_record[workbook_column]
        if is_blank(value):
            existing = catalog_record.get(output_field)
            import_audit["blankCellsIgnored"] += 1
            if existing is not None:
                import_audit["existingValuesPreservedFromBlank"] += 1
                result[output_field] = existing
        else:
            import_audit["nonBlankWorkbookValuesApplied"] += 1
            result[output_field] = str(value)

    if review["status"] == "低置信待确认":
        result["warnings"].append(
            {
                "warningCode": "low_confidence_user_override",
                "field": "record",
                "evidenceGrade": review["grade"],
                "reviewStatus": review["status"],
                "message": review["explanation"],
                "isError": False,
            }
        )
    return result


def sync_runtime_record(catalog_record: dict[str, Any], master: dict[str, Any]) -> None:
    compatibility_fields = (
        "jobAffinity",
        "jobAffinityLabel",
        "jobLock",
        "requirementType",
        "requirementValue",
        "legacyNeed",
        "legacyNeedLevel",
        "genderRestriction",
        "weightRequirementType",
        "weightRequirementValue",
        "rollPolicy",
        "accuracy",
        "agility",
        "luck",
        "curse",
        "magicEvasionPercent",
        "magicEvasionPoints",
        "magicEvasionPercentPerPoint",
        "attackSpeedTier",
        "setId",
        "specialEffectId",
        "specialEffectDescription",
    )
    for field in compatibility_fields:
        if field in master:
            catalog_record[field] = deepcopy(master[field])
    catalog_record["weight"] = master["weight"]
    catalog_record["durability"] = master["durability"]
    for field, (
        _,
        _,
        minimum_key,
        maximum_key,
    ) in RANGE_COLUMNS.items():
        if field not in master["stats"]:
            continue
        catalog_record[minimum_key] = master["stats"][field]["min"]
        catalog_record[maximum_key] = master["stats"][field]["max"]
    catalog_record["reqLevel"] = (
        master["requirementValue"]
        if master["requirementType"] == "level"
        else 0
    )
    catalog_record["reqAttack"] = (
        master["requirementValue"]
        if master["requirementType"] == "max_dc"
        else None
    )
    catalog_record["reqMagic"] = (
        master["requirementValue"]
        if master["requirementType"] == "max_mc"
        else None
    )
    catalog_record["reqTao"] = (
        master["requirementValue"]
        if master["requirementType"] == "max_sc"
        else None
    )
    catalog_record["profession"] = AFFINITY_TO_PROFESSION[master["jobAffinity"]]
    catalog_record["attributeWarnings"] = deepcopy(master["warnings"])
    catalog_record["attributeReview"] = deepcopy(master.get("review", {}))
    catalog_record["source"] = DISTRIBUTION
    catalog_record["attributeSource"] = deepcopy(master["source"])
    catalog_record["sourceUrlRole"] = "supporting_reference"
    catalog_record["secondarySourceUrlRole"] = "supporting_reference"


def build(
    workbook_path: Path,
    *,
    write_outputs: bool,
    audit_output: Path | None,
) -> dict[str, Any]:
    _, workbook_records, audit = validate_review_workbook(workbook_path)
    catalog = json.loads(ITEMS_PATH.read_text(encoding="utf-8"))
    previous_master = json.loads(MASTER_PATH.read_text(encoding="utf-8"))
    legacy_records = [
        migrate_legacy_record(record)
        for record in previous_master["records"]
        if int(record["itemId"]) in LEGACY_TARGET_IDS
    ]
    if len(legacy_records) != 49:
        raise RuntimeError("expected the existing 49 weapon/armor master records")

    catalog_by_id = {int(record["itemId"]): record for record in catalog["records"]}
    female_armor_records = build_female_armor_records(previous_master, catalog_by_id)
    import_counters = {
        "blankCellsIgnored": 0,
        "existingValuesPreservedFromBlank": 0,
        "nonBlankWorkbookValuesApplied": 0,
    }
    reviewed_records: list[dict[str, Any]] = []
    for workbook_record in workbook_records:
        item_id = integer(workbook_record["itemId"], "itemId")
        catalog_record = catalog_by_id.get(item_id)
        if catalog_record is None:
            raise RuntimeError(f"workbook itemId {item_id} is absent from runtime catalog")
        reviewed_records.append(
            reviewed_master_record(workbook_record, catalog_record, import_counters)
        )

    master_records = legacy_records + female_armor_records + reviewed_records
    ids = [int(record["itemId"]) for record in master_records]
    if len(ids) != 175 or len(set(ids)) != 175:
        raise RuntimeError("master output must contain 175 unique itemIds")
    master_by_id = {int(record["itemId"]): record for record in master_records}
    for catalog_record in catalog["records"]:
        master_record = master_by_id.get(int(catalog_record["itemId"]))
        if master_record is not None:
            sync_runtime_record(catalog_record, master_record)

    review_status_counts = Counter(
        record["review"]["status"] for record in reviewed_records
    )
    accessory_warning_counts = Counter(
        warning["warningCode"]
        for record in reviewed_records
        for warning in record["warnings"]
    )
    audit.update(import_counters)
    audit.update(
        {
            "masterRecordCount": len(master_records),
            "legacyWeaponArmorCount": len(legacy_records),
            "femaleArmorCorrectionCount": len(female_armor_records),
            "explicitWorkbookOverrideCount": len(reviewed_records),
            "reviewStatusCounts": dict(review_status_counts),
            "accessoryWarningCounts": dict(accessory_warning_counts),
            "nonZeroFieldCounts": {
                "accuracy": sum("accuracy" in record for record in reviewed_records),
                "agility": sum("agility" in record for record in reviewed_records),
                "luck": sum("luck" in record for record in reviewed_records),
                "curse": sum("curse" in record for record in reviewed_records),
                "magicEvasionPercent": sum(
                    "magicEvasionPercent" in record for record in reviewed_records
                ),
                "magicEvasionPoints": sum(
                    "magicEvasionPoints" in record for record in reviewed_records
                ),
                "attackSpeedTier": sum(
                    "attackSpeedTier" in record for record in reviewed_records
                ),
                "setId": sum("setId" in record for record in reviewed_records),
                "specialEffectId": sum(
                    "specialEffectId" in record for record in reviewed_records
                ),
            },
            "lowConfidenceAcceptedByExplicitUserOverride": [
                {
                    "itemId": record["itemId"],
                    "name": record["name"],
                    "review": record["review"],
                    "warnings": record["warnings"],
                }
                for record in reviewed_records
                if record["review"]["status"] == "低置信待确认"
            ],
        }
    )

    master = {
        "schemaVersion": 2,
        "schemaRef": "res://assets/data/rules/equipment_attribute_master_schema.json",
        "contractId": CONTRACT_ID,
        "distribution": DISTRIBUTION,
        "evidenceSha256": WORKBOOK_EVIDENCE_SHA256,
        "sourceTier": "primary",
        "sourceKind": "explicit_user_primary_override",
        "originalPath": WORKBOOK_SOURCE_PATH,
        "fallbackEvidence": [],
        "blankOverridePolicy": "preserve_existing_value",
        "units": {
            "rangeStats": "integer_points",
            "accuracy": "integer_points",
            "agility": "integer_points",
            "luck": "integer_points",
            "curse": "integer_points",
            "magicEvasionPercent": "display_percent",
            "magicEvasionPoints": "internal_points",
            "magicEvasionPercentPerPoint": MAGIC_EVASION_PERCENT_PER_POINT,
            "attackSpeedTier": "integer_tier",
        },
        "sources": [
            {
                "sourceKind": "explicit_user_primary_revision",
                "evidenceSha256": LEGACY_EVIDENCE_SHA256,
                "originalPath": "user_authorized_attachment/pasted-text.txt",
                "recordCount": 49,
                "previousContractId": LEGACY_CONTRACT_ID,
                "previousDistribution": LEGACY_DISTRIBUTION,
            },
            {
                "sourceKind": "explicit_user_task_correction",
                "evidenceSha256": FEMALE_ARMOR_CORRECTION_EVIDENCE_SHA256,
                "originalPath": FEMALE_ARMOR_CORRECTION_SOURCE_PATH,
                "recordCount": 12,
                "evidenceContract": (
                    "res://assets/data/equipment_female_armor_attribute_evidence.json"
                ),
                "rule": (
                    "female gender is directly authorized; all other attribute "
                    "fields copy the paired primary record and are corroborated "
                    "by the exact item supporting page"
                ),
            },
            {
                "sourceKind": "explicit_user_primary_override",
                "evidenceSha256": WORKBOOK_EVIDENCE_SHA256,
                "originalPath": WORKBOOK_SOURCE_PATH,
                "sheet": WORKBOOK_SHEET,
                "recordCount": 114,
                "blankOverridePolicy": "preserve_existing_value",
            },
            {
                "sourceKind": "primary_server_rule_conversion",
                "distribution": "source.original_gameofmir.server_suite",
                "originalPaths": [
                    "dev_art_sources/reference/original_gameofmir/M2Server/ItmUnit.pas",
                    "dev_art_sources/reference/original_gameofmir/MirClient/FState.pas",
                ],
                "evidenceSha256": [
                    "CE0F5233E5F1E1D995BC0CA64764BF86017B4CF881A4DD8EA1821C2EBBAE6B6C",
                    "D2AD68723041CB102B80B0B23AABF0859E7F08113431C6FF29D8FF5ED163FEA4",
                ],
                "rule": "magicEvasionPercent = magicEvasionPoints * 10",
            },
        ],
        "scope": {
            "weaponRecords": 37,
            "maleArmorRecords": 12,
            "femaleArmorRecords": 12,
            "helmetRecords": 12,
            "necklaceRecords": 32,
            "braceletRecords": 31,
            "ringRecords": 39,
            "workbookOverrideRecords": 114,
            "totalRecords": 175,
        },
        "supportingReferencePolicy": {
            "workbook": "explicit_user_primary_override",
            "21cq": "workbook_supporting_reference",
            "17173": "workbook_supporting_reference",
            "otherWorkbookUrls": "workbook_supporting_reference",
        },
        "records": master_records,
    }
    if write_outputs:
        MASTER_PATH.write_text(
            json.dumps(master, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        ITEMS_PATH.write_text(
            json.dumps(catalog, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
    if audit_output is not None:
        audit_output.parent.mkdir(parents=True, exist_ok=True)
        audit_output.write_text(
            json.dumps(audit, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
    return audit


def apply_female_armor_correction_only() -> dict[str, Any]:
    """Apply the bounded 12-record correction without rebuilding the workbook."""
    master = json.loads(MASTER_PATH.read_text(encoding="utf-8"))
    catalog = json.loads(ITEMS_PATH.read_text(encoding="utf-8"))
    existing_ids = {int(record["itemId"]) for record in master["records"]}
    target_ids = set(FEMALE_ARMOR_PAIRS)
    existing_targets = existing_ids & target_ids
    if existing_targets and existing_targets != target_ids:
        raise RuntimeError("female armor correction is partially applied")
    catalog_by_id = {int(record["itemId"]): record for record in catalog["records"]}
    female_records = build_female_armor_records(master, catalog_by_id)
    legacy_records = [
        record
        for record in master["records"]
        if int(record["itemId"]) in LEGACY_TARGET_IDS
    ]
    other_records = [
        record
        for record in master["records"]
        if int(record["itemId"]) not in LEGACY_TARGET_IDS
        and int(record["itemId"]) not in target_ids
    ]
    master["records"] = legacy_records + female_records + other_records
    if len(master["records"]) != 175:
        raise RuntimeError("bounded correction must produce exactly 175 records")
    correction_source = {
        "sourceKind": "explicit_user_task_correction",
        "evidenceSha256": FEMALE_ARMOR_CORRECTION_EVIDENCE_SHA256,
        "originalPath": FEMALE_ARMOR_CORRECTION_SOURCE_PATH,
        "recordCount": 12,
        "evidenceContract": (
            "res://assets/data/equipment_female_armor_attribute_evidence.json"
        ),
        "rule": (
            "female gender is directly authorized; all other attribute fields "
            "copy the paired primary record and are corroborated by the exact "
            "item supporting page"
        ),
    }
    master["sources"] = [
        source
        for source in master["sources"]
        if source.get("sourceKind") != "explicit_user_task_correction"
    ]
    master["sources"].insert(1, correction_source)
    master["scope"]["femaleArmorRecords"] = 12
    master["scope"]["totalRecords"] = 175
    for female_record in female_records:
        sync_runtime_record(
            catalog_by_id[int(female_record["itemId"])], female_record
        )
    MASTER_PATH.write_text(
        json.dumps(master, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    ITEMS_PATH.write_text(
        json.dumps(catalog, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    return {
        "femaleArmorCorrectionCount": len(female_records),
        "masterRecordCount": len(master["records"]),
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--workbook",
        type=Path,
        required=False,
        help="User-authorized reviewed XLSX source",
    )
    parser.add_argument(
        "--female-armor-correction-only",
        action="store_true",
        help="Apply only the bounded 12-record female armor correction",
    )
    parser.add_argument(
        "--check-only",
        action="store_true",
        help="Read and validate the complete workbook without writing contracts",
    )
    parser.add_argument(
        "--audit-output",
        type=Path,
        help="Optional JSON audit output path",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    if args.female_armor_correction_only:
        audit = apply_female_armor_correction_only()
        print(
            "EQUIPMENT_FEMALE_ARMOR_CORRECTION_PASS: "
            f"{audit['femaleArmorCorrectionCount']} restored records, "
            f"{audit['masterRecordCount']} total records"
        )
        return
    if args.workbook is None:
        raise RuntimeError("--workbook is required unless correction-only is selected")
    audit = build(
        args.workbook.resolve(),
        write_outputs=not args.check_only,
        audit_output=args.audit_output.resolve() if args.audit_output else None,
    )
    print(
        "EQUIPMENT_ATTRIBUTE_IMPORT_PASS: "
        f"{audit['explicitWorkbookOverrideCount']} workbook overrides, "
        f"{audit['masterRecordCount']} total records, "
        f"{audit['cellCount']} XLSX cells read"
    )


if __name__ == "__main__":
    main()
