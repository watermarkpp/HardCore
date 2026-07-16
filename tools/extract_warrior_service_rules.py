#!/usr/bin/env python3
"""Extract and verify warrior combat rules from the bundled server/client source."""

from __future__ import annotations

import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
WORKSPACE = ROOT.parents[1]
MIR = WORKSPACE / "research/MIR2/GameOfMir"
OBJ = MIR / "M2Server/ObjBase.pas"
SHARE = MIR / "M2Server/M2Share.pas"
COMMON = MIR / "Common/Grobal2.pas"
CLIENT_ACTOR = MIR / "Client/Actor.pas"
CLIENT_MAIN = MIR / "Client/ClMain.pas"
SETUP = MIR / "MirServer/Mir200/!Setup.txt"
OUTPUT = ROOT / "assets/data/warrior_service_rules.json"


def read_legacy(path: Path) -> str:
    return path.read_text(encoding="gbk", errors="replace")


def require(source: str, pattern: str, label: str) -> None:
    if re.search(pattern, source, re.MULTILINE) is None:
        raise RuntimeError(f"服务端/客户端源码证据缺失：{label}")


def setup_value(text: str, key: str) -> int:
    match = re.search(rf"^{re.escape(key)}=(\d+)$", text, re.MULTILINE)
    if match is None:
        raise RuntimeError(f"!Setup缺少{key}")
    return int(match.group(1))


def main() -> None:
    obj = read_legacy(OBJ)
    share = read_legacy(SHARE)
    common = read_legacy(COMMON)
    actor = read_legacy(CLIENT_ACTOR)
    client = read_legacy(CLIENT_MAIN)
    setup = read_legacy(SETUP)

    evidence = {
        "basicAccuracy": r"Round\(9 / 3 \* UserMagic\.btLevel\)",
        "slayingAccuracy": r"Round\(3 / 3 \* UserMagic\.btLevel\)",
        "slayingBonus": r"m_nHitPlus := DEFHIT \+ UserMagic\.btLevel",
        "slayingCycle": r"m_btAttackSkillCount := 7 - UserMagic\.btLevel",
        "fireLevelScale": r"m_nHitDouble := 4 \+ UserMagic\.btLevel \* 4",
        "fireDamage": r"nPower := nPower \+ Round\(nPower / 100 \* \(m_nHitDouble \* 10\)\)",
        "thrustDamage": r"nPower / \(m_MagicErgumSkill\.MagicInfo\.btTrainLv \+ 2\) \* \(m_MagicErgumSkill\.btLevel \+ 2\)",
        "halfMoonDamage": r"nPower / \(m_MagicBanwolSkill\.MagicInfo\.btTrainLv \+ 10\) \* \(m_MagicBanwolSkill\.btLevel \+ 2\)",
        "hitGate": r"m_btHitPoint < Random\(AttackTarget\.m_btSpeedPoint\)",
        "wildRushGate": r"Random\(20\) < \(\(nMagicLevel \* 4\) \+ 6 \+ nC\)",
        "wildRushCooldown": r"GetTickCount - m_dwDoMotaeboTick\) > 3 \* 1000",
    }
    for label, pattern in evidence.items():
        require(obj, pattern, label)
    require(share, r"DEFHIT = 5", "DEFHIT")
    require(share, r"DEFSPEED = 15", "DEFSPEED")
    require(share, r"WideAttack: \(7, 1, 2\)", "WideAttack")
    require(common, r"SKILL_ONESWORD\s*= 3", "SKILL_ONESWORD")
    require(common, r"SKILL_YEDO\s*= 7", "SKILL_YEDO")
    require(common, r"SKILL_ERGUM\s*= 12", "SKILL_ERGUM")
    require(common, r"SKILL_BANWOL\s*= 25", "SKILL_BANWOL")
    require(common, r"SKILL_FIRESWORD\s*= 26", "SKILL_FIRESWORD")
    require(common, r"SKILL_MOOTEBO\s*= 27", "SKILL_MOOTEBO")
    require(actor, r"ActHit:\s*\(start: 200;\s*frame: 6;\s*skip: 2;\s*ftime: 85", "客户端攻击动作")
    require(actor, r"SM_(?:POWERHIT|LONGHIT|WIDEHIT|FIREHIT):[\s\S]{0,120}if frame = 2", "客户端技能效果帧")
    require(client, r"TargetInSwordLongAttackRange[\s\S]{0,500}GetFrontPosition \(nx, ny", "客户端刺杀第二格")

    payload = {
        "baseline": "2003官服1.76基准优先",
        "generatedFrom": "本地M2Server与经典客户端Delphi源码直接提取",
        "sourcePriority": "服务端规则/数值优先，客户端动作/表现优先",
        "sources": {
            "serverCombat": "research/MIR2/GameOfMir/M2Server/ObjBase.pas",
            "serverConfig": "research/MIR2/GameOfMir/M2Server/M2Share.pas",
            "serverConstants": "research/MIR2/GameOfMir/Common/Grobal2.pas",
            "clientAction": "research/MIR2/GameOfMir/Client/Actor.pas",
            "clientInput": "research/MIR2/GameOfMir/Client/ClMain.pas",
            "serverSetup": "research/MIR2/GameOfMir/MirServer/Mir200/!Setup.txt",
        },
        "global": {
            "baseAccuracy": 5,
            "baseAgility": 15,
            "serverHitIntervalMs": setup_value(setup, "HitIntervalTime"),
            "projectAttackIntervalMs": 850,
            "projectIntervalReason": "用户明确指定850ms，覆盖该服务端包的600ms动作防刷阈值",
            "clientAttackFrames": 6,
            "clientFrameMs": 85,
            "clientAttackDurationMs": 510,
            "clientEffectFrameZeroBased": 2,
            "clientEffectTimeMs": 170,
            "hitRule": "若 attackerAccuracy < Random(targetAgility) 则未命中",
            "damageRoll": "DC下限 + Random(DC上限-DC下限+1)，再应用幸运/诅咒",
            "confidence": "A",
        },
        "skills": {
            "基本剑术": {"magicId": 3, "mode": "passive", "accuracyByLevel": [0, 3, 6, 9], "confidence": "A"},
            "攻杀剑术": {"magicId": 7, "mode": "automatic_proc", "accuracyByLevel": [0, 1, 2, 3], "procCycleByLevel": [7, 6, 5, 4], "flatDamageBonusByLevel": [5, 6, 7, 8], "confidence": "A"},
            "刺杀剑术": {"magicId": 12, "mode": "toggle", "targetCell": 2, "secondaryDamageRatioByLevel": [0.4, 0.6, 0.8, 1.0], "swordLongPowerRate": 100, "confidence": "A"},
            "半月弯刀": {"magicId": 25, "mode": "toggle", "directionOffsets": [7, 1, 2], "secondaryDamageRatioByLevel": [2 / 13, 3 / 13, 4 / 13, 5 / 13], "confidence": "A"},
            "烈火剑法": {"magicId": 26, "mode": "arm_next_hit", "damageMultiplierByLevel": [1.4, 1.8, 2.2, 2.6], "armCooldownMs": 10000, "armedExpireMs": 20000, "confidence": "A"},
            "野蛮冲撞": {"magicId": 27, "mode": "rush", "cooldownMs": 3000, "requiresHigherCharacterLevel": True, "successThreshold": "skillLevel*4+6+(playerLevel-targetLevel), Random(20)低于阈值成功", "maxCellsByLevel": [3, 3, 4, 5], "confidence": "A"},
        },
        "knownMissing": [
            "完整服务端Magic.DB尚未取得，wSpell/btDefSpell/训练点等逐技能字段不能从源码单独恢复",
            "当前项目技能学习等级来自结构库候选数据；需完整Magic.DB到位后覆盖",
            "逐技能原始WAV文件与Magic.wil效果编号尚未完成客户端资源映射",
        ],
        "runtimeIntegration": {
            "slaying": "4—7刀周期内随机一个触发点",
            "thrusting": "开关；主目标加正前第二格独立命中",
            "halfMoon": "开关；主目标加方向偏移[7,1,2]三个侧向格",
            "fireSword": "10秒可蓄力、20秒过期、下一刀或空刀消耗",
            "wildRush": "等级差、Random(20)、阻挡、推怪、剩余步数伤害已接入",
        },
    }
    OUTPUT.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"WARRIOR_SERVICE_RULES={OUTPUT}")


if __name__ == "__main__":
    main()
