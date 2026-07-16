#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE_ROOT = ROOT.parents[1] / "research" / "MIR2" / "GameOfMir" / "M2Server"
OBJ_BASE = SOURCE_ROOT / "ObjBase.pas"
M2_SHARE = SOURCE_ROOT / "M2Share.pas"
ITM_UNIT = SOURCE_ROOT / "ItmUnit.pas"
OUTPUT = ROOT / "assets" / "data" / "equipment_luck_rules.json"


def read(path: Path) -> str:
    return path.read_text(encoding="gbk", errors="replace")


def main() -> None:
    base, share, item = read(OBJ_BASE), read(M2_SHARE), read(ITM_UNIT)
    tokens = [
        "Random(10 - _MIN(9, m_nLuck))",
        "Random(10 - _MAX(0, -m_nLuck))",
        "nWeaponMakeUnLuckRate: 20",
        "nWeaponMakeLuckPoint1: 1",
        "nWeaponMakeLuckPoint2: 3",
        "nWeaponMakeLuckPoint3: 7",
        "nWeaponMakeLuckPoint2Rate: 6",
        "nWeaponMakeLuckPoint3Rate: 10 + 30",
    ]
    combined = base + share
    for token in tokens:
        if token not in combined:
            raise RuntimeError(f"幸运规则源码标记缺失：{token}")
    for token in ["Inc(AddAbility.btLuck, AC)", "Inc(AddAbility.btUnLuck, MAC)"]:
        if token not in item:
            raise RuntimeError(f"武器幸运属性源码标记缺失：{token}")
    payload = {
        "baseline": "M2Server源码规则",
        "sources": [
            {"path": "research/MIR2/GameOfMir/M2Server/ObjBase.pas", "role": "GetAttackPower、WeaptonMakeLuck、MakeWeaponUnlock", "confidence": "A"},
            {"path": "research/MIR2/GameOfMir/M2Server/M2Share.pas", "role": "祝福油默认配置", "confidence": "A"},
            {"path": "research/MIR2/GameOfMir/M2Server/ItmUnit.pas", "role": "武器基础幸运/诅咒进入人物幸运", "confidence": "A"},
        ],
        "defaults": {"unluckyRate": 20, "luckPoints": [1, 3, 7], "point2Rate": 6, "point3Rate": 40, "maxCurse": 10},
        "blessingOrder": ["1/20失败：有幸运则幸运-1，否则诅咒+1至10", "成功路径优先诅咒-1", "幸运低于1必定+1", "幸运1—2按跨度因子+6判定", "幸运3—6按跨度因子×40判定", "其余无效"],
        "damageDistribution": {"positive": "按1/(10-min(9,luck))直接取上限，否则均匀", "negative": "先均匀，再按1/(10-max(0,-luck))强制取下限"},
        "runtime": "weapon_luck/weapon_curse保存在武器实例；零耐久时随其他属性一起失效，维修后恢复参与结算。",
    }
    OUTPUT.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"output": str(OUTPUT), "luckCap": 7, "curseCap": 10}, ensure_ascii=False))


if __name__ == "__main__":
    main()
