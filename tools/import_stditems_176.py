#!/usr/bin/env python3
"""Import the pinned 1.76 community StdItems.DB as an auditable overlay.

The vanilla table remains immutable.  Exact values for this distribution are
written to equipment_customization.json, which GameData already merges after
the vanilla records.  A complete JSON snapshot keeps every imported value
reviewable without requiring Paradox tooling at runtime.
"""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE_ROOT = ROOT / "dev_art_sources/reference/mir2_database_candidates/mylgd_mir2server_176"
SOURCE_DB = SOURCE_ROOT / "Mud2/DB/StdItems.DB"
VANILLA_ITEMS = ROOT / "assets/data/vanilla_176/items.json"
CUSTOMIZATION = ROOT / "assets/data/equipment_customization.json"
SNAPSHOT = ROOT / "assets/data/equipment_stditems_176.json"
SOURCE_REPOSITORY = "https://gitee.com/mylgd/mir2server"
SOURCE_COMMIT = "3952c536c6de04cae12b0c8ce42a6f53ec08d428"
SOURCE_SHA256 = "7978a8164b950a96b47ae15c0414f2925fa2418661dc74a1ac4d0427b1c0372b"

FIELDS = [
    "Idx", "Name", "Stdmode", "Shape", "Weight", "Anicount", "Source", "Reserved",
    "Looks", "DuraMax", "Ac", "Ac2", "Mac", "Mac2", "Dc", "Dc2", "Mc", "Mc2",
    "Sc", "Sc2", "Need", "NeedLevel", "Price", "Stock", "Color", "OverLap", "HP",
    "MP", "Light", "Horse", "Element", "Expand1", "Expand2", "Expand3", "Expand4",
    "Expand5", "InsuranceCurrency", "InsuranceGold",
]


def _decode_alpha(value: object) -> str:
    raw = str(value).rstrip("\x00")
    try:
        return raw.encode("latin1").decode("gbk")
    except (UnicodeEncodeError, UnicodeDecodeError):
        return raw


def _load_rows() -> list[dict]:
    try:
        import pypxlib  # type: ignore
    except ImportError as exc:
        raise RuntimeError(
            "缺少 pypxlib；请在隔离环境安装 pypxlib==2.5 后用该解释器运行本工具"
        ) from exc
    if hashlib.sha256(SOURCE_DB.read_bytes()).hexdigest() != SOURCE_SHA256:
        raise RuntimeError("StdItems.DB SHA-256 与锁定来源不一致")
    # pypxlib 2.5 encodes the path as ASCII internally.  Running from the
    # workspace and passing a relative path keeps Windows workspaces with
    # Chinese directory names usable.
    previous_cwd = Path.cwd()
    os.chdir(ROOT)
    try:
        table = pypxlib.Table(str(SOURCE_DB.relative_to(ROOT)), encoding="latin1")
    finally:
        os.chdir(previous_cwd)
    rows: list[dict] = []
    for source_row in table:
        row = {field: source_row[field] for field in FIELDS}
        row["Name"] = _decode_alpha(row["Name"])
        rows.append(row)
    return rows


def _calibrated_fields(row: dict) -> dict:
    need = int(row["Need"])
    need_level = int(row["NeedLevel"])
    result = {
        "weight": int(row["Weight"]),
        "durability": int(row["DuraMax"]) // 1000,
        "attackMin": int(row["Dc"]), "attackMax": int(row["Dc2"]),
        "magicMin": int(row["Mc"]), "magicMax": int(row["Mc2"]),
        "taoMin": int(row["Sc"]), "taoMax": int(row["Sc2"]),
        "defenseMin": int(row["Ac"]), "defenseMax": int(row["Ac2"]),
        "mdefMin": int(row["Mac"]), "mdefMax": int(row["Mac2"]),
        "reqLevel": need_level if need == 0 else 0,
        "reqAttack": need_level if need == 1 else None,
        "reqMagic": need_level if need == 2 else None,
        "reqTao": need_level if need == 3 else None,
        "price": int(row["Price"]),
        "serviceIndex": int(row["Idx"]),
        "serviceStdMode": int(row["Stdmode"]),
        "serviceShape": int(row["Shape"]),
        "serviceWeight": int(row["Weight"]),
        "serviceAniCount": int(row["Anicount"]),
        "serviceDropSource": int(row["Source"]),
        "serviceLooks": int(row["Looks"]),
        "serviceDuraMax": int(row["DuraMax"]),
        "serviceAC": [int(row["Ac"]), int(row["Ac2"])],
        "serviceMAC": [int(row["Mac"]), int(row["Mac2"])],
        "serviceDC": [int(row["Dc"]), int(row["Dc2"])],
        "serviceMC": [int(row["Mc"]), int(row["Mc2"])],
        "serviceSC": [int(row["Sc"]), int(row["Sc2"])],
        "serviceNeed": need,
        "serviceNeedLevel": need_level,
        "servicePrice": int(row["Price"]),
        "stdItemsCalibration": {
            "distribution": "community.mylgd.mir2server.176",
            "sourceCommit": SOURCE_COMMIT,
            "sourceIndex": int(row["Idx"]),
            "exactForDistribution": True,
            "officialBaseline": False,
        },
    }
    return result


def main() -> None:
    rows = _load_rows()
    if len(rows) != 369:
        raise RuntimeError(f"StdItems记录数异常：{len(rows)}")
    by_name = {str(row["Name"]): row for row in rows if str(row["Name"])}
    vanilla = json.loads(VANILLA_ITEMS.read_text(encoding="utf-8"))["records"]
    customization = json.loads(CUSTOMIZATION.read_text(encoding="utf-8"))
    overrides = customization.setdefault("overrides", {})
    matched: list[str] = []
    missing: list[str] = []
    for item in vanilla:
        name = str(item["name"])
        row = by_name.get(name)
        if row is None:
            missing.append(name)
            continue
        entry = overrides.setdefault(name, {})
        fields = entry.setdefault("fields", {})
        fields.update(_calibrated_fields(row))
        special = fields.get("specialEffect")
        if isinstance(special, dict) and int(special.get("source_code", -1)) == int(row["Anicount"]):
            special["confidence"] = "A"
            special["mapping_source"] = "community.mylgd.mir2server.176 StdItems.AniCount"
        set_piece = fields.get("setPiece")
        if isinstance(set_piece, dict) and int(row["Anicount"]) > 0:
            set_piece["power"] = int(row["Anicount"])
            set_piece["confidence"] = "A"
        matched.append(name)

    customization["stdItemsCalibration"] = {
        "distribution": "community.mylgd.mir2server.176",
        "sourceSnapshot": "res://assets/data/equipment_stditems_176.json",
        "matchedVanillaRecords": len(matched),
        "missingVanillaRecords": missing,
        "policy": "精确值仅代表锁定社区1.76发行版；保留来源，不冒充2003官服原库。",
    }
    snapshot = {
        "schemaVersion": 1,
        "distributionId": "community.mylgd.mir2server.176",
        "versionClaim": "1.76布衣传说复古金小极品版",
        "source": {
            "repository": SOURCE_REPOSITORY,
            "commit": SOURCE_COMMIT,
            "path": "Mud2/DB/StdItems.DB",
            "sha256": SOURCE_SHA256,
            "format": "Paradox 7",
        },
        "confidence": {
            "recordValues": "A（对该锁定发行版逐字段精确）",
            "official2003Equivalence": "B（社区1.76版本，不声明等同官服原库）",
        },
        "recordCount": len(rows),
        "matchedVanillaRecords": len(matched),
        "missingVanillaRecords": missing,
        "records": rows,
    }
    SNAPSHOT.write_text(json.dumps(snapshot, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    CUSTOMIZATION.write_text(json.dumps(customization, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"STD_ITEMS_ROWS={len(rows)} MATCHED={len(matched)} MISSING={len(missing)}")


if __name__ == "__main__":
    main()
