#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE_ROOT = ROOT / "dev_art_sources" / "reference" / "original_gameofmir"
STRUCT_PATH = SOURCE_ROOT / "Common" / "Grobal2.pas"
RULE_PATH = SOURCE_ROOT / "M2Server" / "ObjBase.pas"
DATA_PATH = ROOT / "assets" / "data" / "legend176_data.json"
STD_ITEMS_PATH = ROOT / "assets" / "data" / "equipment_stditems_176.json"
OUTPUT_PATH = ROOT / "assets" / "data" / "equipment_service_rules.json"


def read_pas(path: Path) -> str:
    return path.read_text(encoding="gbk", errors="replace")


def main() -> None:
    struct = read_pas(STRUCT_PATH)
    rules = read_pas(RULE_PATH)
    required_struct_fields = ["StdMode", "Shape", "Weight", "Looks", "DuraMax", "AC", "MAC", "DC", "MC", "SC", "Need", "NeedLevel"]
    for field in required_struct_fields:
        if field not in struct:
            raise RuntimeError(f"TStdItem字段缺失：{field}")
    need_checks = {
        0: "m_Abil.Level >= StdItem.NeedLevel",
        1: "HiWord(m_WAbil.DC) >= StdItem.NeedLevel",
        2: "HiWord(m_WAbil.MC) >= StdItem.NeedLevel",
        3: "HiWord(m_WAbil.SC) >= StdItem.NeedLevel",
    }
    for need, token in need_checks.items():
        if token not in rules:
            raise RuntimeError(f"Need={need}判定源码缺失")
    for token in ["m_Abil.MaxWearWeight := 15", "m_Abil.MaxHandWeight := 12", "StdItem.Weight > m_WAbil.MaxHandWeight", "StdItem.Weight + GetUserItemWeitht"]:
        if token not in rules:
            raise RuntimeError(f"重量规则源码缺失：{token}")

    data = json.loads(DATA_PATH.read_text(encoding="utf-8"))
    std_items = json.loads(STD_ITEMS_PATH.read_text(encoding="utf-8"))
    items = data.get("items", [])
    concrete_count = int(std_items.get("matchedVanillaRecords", 0))
    payload = {
        "baseline": "2003官服1.76基准优先",
        "sources": [
            {"path": str(STRUCT_PATH.relative_to(ROOT)).replace("\\", "/"), "role": "TStdItem字段结构", "confidence": "A"},
            {"path": str(RULE_PATH.relative_to(ROOT)).replace("\\", "/"), "role": "CanUseItem穿戴判定与职业重量公式", "confidence": "A"},
            {"path": "assets/data/equipment_stditems_176.json", "role": "锁定社区1.76发行版逐件StdItems值", "confidence": "A（对该发行版）"},
        ],
        "fieldSemantics": {
            "StdMode": "物品类型；10男衣、11女衣，装备类还包含15/19/20/21/22/23/24/26",
            "Shape": "外形/功能子类型",
            "Weight": "武器比较MaxHandWeight，其余装备比较替换槽后的MaxWearWeight",
            "Looks": "Items.wil图像索引",
            "DuraMax": "服务端以千分单位保存最大持久",
            "AC_MAC_DC_MC_SC": "DWord低16位为下限、高16位为上限",
            "Need": {"0": "等级", "1": "攻击上限", "2": "魔法上限", "3": "道术上限"},
            "NeedLevel": "Need对应阈值",
        },
        "weightFormula": {
            "战士": {"wear": "15+round(level/20*level)", "hand": "12+round(level/13*level)"},
            "法师": {"wear": "15+round(level/100*level)", "hand": "12+round(level/90*level)"},
            "道士": {"wear": "15+round(level/50*level)", "hand": "12+round(level/42*level)"},
        },
        "catalogCoverage": {
            "equipmentRecords": len(items),
            "concreteStdItemsRecords": concrete_count,
            "candidateRecords": len(items) - concrete_count,
            "confidenceA": sum(1 for item in items if item.get("confidence") == "A"),
            "confidenceB": sum(1 for item in items if item.get("confidence") == "B"),
        },
        "missing": std_items.get("missingVanillaRecords", []),
        "policy": "源码字段语义按A采用；172件数值对锁定社区1.76发行版精确，不能冒充2003官服原库；缺名记录继续隔离。",
    }
    OUTPUT_PATH.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"equipmentRecords": len(items), "concreteStdItemsRecords": concrete_count, "output": str(OUTPUT_PATH)}, ensure_ascii=False))


if __name__ == "__main__":
    main()
