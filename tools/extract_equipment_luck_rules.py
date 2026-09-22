#!/usr/bin/env python3
from __future__ import annotations

import json
import argparse
import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE_ROOT = ROOT / "dev_art_sources/reference/original_gameofmir/M2Server"
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
        "end else if (m_UseItems[U_WEAPON].btValue[3] < g_Config.nWeaponMakeLuckPoint3",
    ]
    combined = base + share
    for token in tokens:
        if token not in combined:
            raise RuntimeError(f"幸运规则源码标记缺失：{token}")
    for token in ["Inc(AddAbility.btLuck, AC)", "Inc(AddAbility.btUnLuck, MAC)"]:
        if token not in item:
            raise RuntimeError(f"武器幸运属性源码标记缺失：{token}")
    payload = {
        "schemaVersion": 3,
        "contractId": "equipment.blessing_luck.v3",
        "baseline": "M2Server源码规则 + 用户授权R=0边界修订",
        "sourcePolicy": {"lane": "server_rules", "distribution": "source.original_gameofmir.server_suite", "tier": "primary", "order": 0},
        "sources": [
            {"originalPath": path.relative_to(ROOT).as_posix(), "sha256": hashlib.sha256(path.read_bytes()).hexdigest().upper(), "role": role, "confidence": "A"}
            for path, role in [(OBJ_BASE, "GetAttackPower、WeaptonMakeLuck、MakeWeaponUnlock"), (M2_SHARE, "祝福油默认配置"), (ITM_UNIT, "全部装备基础幸运/诅咒进入人物幸运")]
        ],
        "defaults": {"unluckyRate": 20, "luckPoints": [1, 3, 7], "point2Rate": 6, "point3Rate": 40, "maxCurse": 10},
        "probabilityFormula": {
            "spanFactorId": "blessing_span_factor_r_v2", "spanFactor": "R=max(1,floor(abs(DCmax-DCmin)/5))",
            "unlucky": {"denominator": 20, "successRoll": 1, "probability": "1/20"},
            "luck0": {"denominator": 1, "result": "improved"},
            "luck1To2": {"denominator": "R+6", "successRoll": 1, "onFailure": "independent upper-stage Random(R*40)==1", "unconditionalImproveProbability": "(19/20)*(1/(R+6)+(1-1/(R+6))/(R*40))"},
            "luck3To6": {"denominator": "R*40", "successRoll": 1},
            "luck7": {"denominator": 0, "result": "ineffective"},
        },
        "blessingOrder": ["1/20失败：有幸运则幸运-1，否则诅咒+1至10", "成功路径优先诅咒-1", "幸运低于1必定+1", "幸运1—2按R+6判定，失败后继续独立R×40判定", "幸运3—6按R×40判定", "其余无效"],
        "damageDistribution": {"positive": "按1/(10-min(9,luck))直接取上限，否则均匀", "negative": "先均匀，再按1/(10-max(0,-luck))强制取下限"},
        "totalLuckFormula": "sum(all_equipped_item.luck)-sum(all_equipped_item.curse)+weapon_instance.weapon_luck-weapon_instance.weapon_curse",
        "compatibility": {"nonWeaponCurseField": "curse", "existingCurseValuesInvented": False, "legacyDualWeaponFields": "preserve effective luck-minus-curse; normalize exclusively on next oil mutation", "display": "show one net luck or curse term; omit zero"},
        "runtime": "weapon_luck/weapon_curse保存在武器实例；所有装备支持基础luck/curse；零耐久时随其他属性一起失效，维修后恢复参与结算。",
    }
    parser = argparse.ArgumentParser()
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--write", action="store_true")
    mode.add_argument("--check", action="store_true")
    args = parser.parse_args()
    rendered = json.dumps(payload, ensure_ascii=False, indent=2) + "\n"
    if args.check:
        assert OUTPUT.read_text(encoding="utf-8") == rendered, "blessing rule contract drift"
    else:
        OUTPUT.write_text(rendered, encoding="utf-8", newline="\n")
    print("EQUIPMENT_LUCK_PRIMARY_RULES_PASS contract=v3 luck_cap=7 curse_cap=10")


if __name__ == "__main__":
    main()
