#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE_ROOT = ROOT.parents[1] / "research" / "MIR2" / "GameOfMir" / "M2Server"
OBJ_BASE = SOURCE_ROOT / "ObjBase.pas"
OBJ_NPC = SOURCE_ROOT / "ObjNpc.pas"
OUTPUT = ROOT / "assets" / "data" / "equipment_durability_rules.json"


def read(path: Path) -> str:
    return path.read_text(encoding="gbk", errors="replace")


def main() -> None:
    base = read(OBJ_BASE)
    npc = read(OBJ_NPC)
    required = [
        "Round(nPrice div 3 / UserItem.DuraMax * (UserItem.DuraMax - UserItem.Dura))",
        "UserItem.Dura := UserItem.DuraMax",
        "Dec(UserItem.DuraMax, (UserItem.DuraMax - UserItem.Dura) div g_Config.nRepairItemDecDura",
    ]
    for token in required:
        if token not in npc:
            raise RuntimeError(f"修理源码标记缺失：{token}")
    if "m_UseItems[U_WEAPON].wIndex := 0" not in base or "m_UseItems[U_DRESS].wIndex := 0" not in base:
        raise RuntimeError("耐久归零删除源码标记缺失")
    payload = {
        "baseline": "服务端公式优先，用户单机设计明确覆盖破损与修理方式",
        "sources": [
            {"path": "research/MIR2/GameOfMir/M2Server/ObjNpc.pas", "role": "询价与修理价格", "confidence": "A"},
            {"path": "research/MIR2/GameOfMir/M2Server/ObjBase.pas", "role": "武器、衣服与其他装备耐久损耗", "confidence": "A"},
        ],
        "adopted": {
            "costFormula": "round((referencePrice div 3) / maxDurability * missingDurability)",
            "zeroDurability": "装备保留在原槽，属性失效",
            "repair": "唯一维修方式；恢复到原maxDurability，最大耐久不下降",
            "specialRepair": False,
        },
        "explicitOverrides": [
            {"server": "耐久归零清除wIndex/删除装备", "adopted": "耐久归零保留实例", "reason": "用户明确指定"},
            {"server": "普通修理按RepairItemDecDura降低最大耐久", "adopted": "最大耐久保持不变", "reason": "用户明确指定"},
            {"server": "存在SUPERREPAIR并乘价格倍率", "adopted": "不提供特殊修理", "reason": "用户明确指定"},
        ],
        "priceStatus": "StdItems.Price缺失；优先servicePrice，否则使用已标注的项目价格候选",
    }
    OUTPUT.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"output": str(OUTPUT), "specialRepair": False}, ensure_ascii=False))


if __name__ == "__main__":
    main()
