#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "dev_art_sources" / "reference" / "original_gameofmir" / "M2Server" / "ObjBase.pas"
DATA = ROOT / "assets" / "data" / "legend176_data.json"
STD_ITEMS = ROOT / "assets" / "data" / "equipment_stditems_176.json"
OUTPUT = ROOT / "assets" / "data" / "equipment_special_rules.json"

RUNTIME = {
    "隐身戒指": (111, "stealth"), "麻痹戒指": (113, "paralysis"), "复活戒指": (114, "revival"),
    "护身戒指": (118, "magic_shield"), "超负载戒指": (119, "double_weight"),
    "传送戒指": (112, "teleport"), "火焰戒指": (115, "flame_skill"), "防御戒指": (116, "recovery_skill"),
}
REGISTERED = {}
DEFERRED_PREFIXES = ["记忆", "祈祷"]


def main() -> None:
    source = SOURCE.read_text(encoding="gbk", errors="replace")
    for code in range(111, 120):
        if f"AniCount = {code}" not in source and f"Shape = {code}" not in source:
            raise RuntimeError(f"特殊装备源码编号缺失：{code}")
    for token in ["nDamage * 1.5", "dwRevivalTime {60 * 1000}", "nAttackPosionRate {5}", "Inc(m_WAbil.MaxWearWeight, m_WAbil.MaxWearWeight)"]:
        if token not in source:
            raise RuntimeError(f"特殊效果源码标记缺失：{token}")
    items = json.loads(DATA.read_text(encoding="utf-8")).get("items", [])
    names = {item.get("name") for item in items}
    std_rows = json.loads(STD_ITEMS.read_text(encoding="utf-8")).get("records", [])
    std_by_name = {str(row.get("Name", "")): row for row in std_rows}
    payload = {
        "baseline": "2003官服1.76基准优先",
        "source": {"path": "dev_art_sources/reference/original_gameofmir/M2Server/ObjBase.pas", "role": "AniCount/Shape效果与运行公式", "confidence": "A"},
        "stdItemsSource": "res://assets/data/equipment_stditems_176.json",
        "runtimeEffects": {
            name: {
                "sourceCode": code,
                "effect": effect,
                "stdItemsAniCount": int(std_by_name.get(name, {}).get("Anicount", -1)),
                "mappingConfidence": "A" if int(std_by_name.get(name, {}).get("Anicount", -1)) == code else "B",
            }
            for name, (code, effect) in RUNTIME.items() if name in names
        },
        "registeredOnly": {name: {"sourceCode": code, "effect": effect, "reason": "手机交互或技能授予尚未完成"} for name, (code, effect) in REGISTERED.items() if name in names},
        "deferredSets": sorted(name for name in names if any(str(name).startswith(prefix) for prefix in DEFERRED_PREFIXES)),
        "setCandidates": {
            "magicBlood": {"pieces": {"项链": 25, "手镯": 25, "戒指": 25}, "fullSetBonus": 50, "effect": "MP转HP", "confidence": "A", "valueSource": "StdItems.AniCount"},
            "rainbowDemon": {"pieces": {"项链": 5, "手镯": 5, "戒指": 5}, "fullSetBonus": "accuracy+2", "effect": "近战吸血百分比", "confidence": "A", "valueSource": "StdItems.AniCount"},
        },
        "activeActionCandidates": {
            "teleport": {"distance": 180, "rule": "沿朝向做连续碰撞检测，失败逐级缩短", "confidence": "project-mobile"},
            "flame_skill": {"manaCost": 5, "range": 360, "confidence": "project-mobile"},
            "recovery_skill": {"manaCost": 5, "formula": "max(12, level/2+taoMax*2)", "confidence": "project-mobile"},
        },
        "catalogCorrections": ["魔血/虹魔三件按套装规则作为通用组件；逐件Need与AniCount已由锁定StdItems复核"],
        "rules": {"zeroDurability": "所有特殊效果立即失效", "revivalCooldownMs": 60000, "paralysisBaseDenominator": 5, "magicShieldMpPerDamage": 1.5, "doubleWeight": 2},
        "mappingPolicy": "运行公式来自服务端源码(A)；名称到AniCount及套装逐件power对锁定社区1.76 StdItems为A，对官服等价性保持B。",
    }
    OUTPUT.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"runtime": len(payload["runtimeEffects"]), "registered": len(payload["registeredOnly"]), "deferred": len(payload["deferredSets"]), "output": str(OUTPUT)}, ensure_ascii=False))


if __name__ == "__main__":
    main()
