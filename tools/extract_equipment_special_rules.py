#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT.parents[1] / "research" / "MIR2" / "GameOfMir" / "M2Server" / "ObjBase.pas"
DATA = ROOT / "assets" / "data" / "legend176_data.json"
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
    payload = {
        "baseline": "2003官服1.76基准优先",
        "source": {"path": "research/MIR2/GameOfMir/M2Server/ObjBase.pas", "role": "AniCount/Shape效果与运行公式", "confidence": "A"},
        "runtimeEffects": {name: {"sourceCode": code, "effect": effect, "mappingConfidence": "B"} for name, (code, effect) in RUNTIME.items() if name in names},
        "registeredOnly": {name: {"sourceCode": code, "effect": effect, "reason": "手机交互或技能授予尚未完成"} for name, (code, effect) in REGISTERED.items() if name in names},
        "deferredSets": sorted(name for name in names if any(str(name).startswith(prefix) for prefix in DEFERRED_PREFIXES)),
        "setCandidates": {
            "magicBlood": {"pieces": {"项链": 25, "手镯": 25, "戒指": 25}, "fullSetBonus": 50, "effect": "MP转HP", "confidence": "B"},
            "rainbowDemon": {"pieces": {"项链": 4, "手镯": 3, "戒指": 2}, "fullSetBonus": "accuracy+2", "effect": "近战吸血百分比", "confidence": "B"},
        },
        "activeActionCandidates": {
            "teleport": {"distance": 180, "rule": "沿朝向做连续碰撞检测，失败逐级缩短", "confidence": "project-mobile"},
            "flame_skill": {"manaCost": 5, "range": 360, "confidence": "project-mobile"},
            "recovery_skill": {"manaCost": 5, "formula": "max(12, level/2+taoMax*2)", "confidence": "project-mobile"},
        },
        "catalogCorrections": ["魔血/虹魔三件被现有候选目录错误拆成三个职业；运行时按通用套装处理，待StdItems.Need复核"],
        "rules": {"zeroDurability": "所有特殊效果立即失效", "revivalCooldownMs": 60000, "paralysisBaseDenominator": 5, "magicShieldMpPerDamage": 1.5, "doubleWeight": 2},
        "mappingPolicy": "运行公式来自服务端源码(A)；实际StdItems缺失时，名称到AniCount及套装逐件power保持B，不冒充逐件数据库原值。",
    }
    OUTPUT.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"runtime": len(payload["runtimeEffects"]), "registered": len(payload["registeredOnly"]), "deferred": len(payload["deferredSets"]), "output": str(OUTPUT)}, ensure_ascii=False))


if __name__ == "__main__":
    main()
