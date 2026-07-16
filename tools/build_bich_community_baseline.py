#!/usr/bin/env python3
"""Build a conservative Bich runtime overlay from community MIR2 databases."""

from __future__ import annotations

import csv
import json
import re
from collections import Counter
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
WORKSPACE = ROOT.parents[1]
COMMUNITY = WORKSPACE / "research/mir2_database_candidates/angelk727_full"
CRYSTAL = WORKSPACE / "research/mir2_database_candidates/suprcode_crystal_database"
BASE_DATA = ROOT / "assets/data/legend176_data.json"
OUTPUT = ROOT / "assets/data/bich_community_baseline.json"

MONSTER_NAMES = [
    "稻草人", "钉耙猫", "多钩猫", "半兽人", "半兽战士", "森林雪人", "食人花", "毒蜘蛛",
    "骷髅", "掷斧骷髅", "骷髅战士", "骷髅战将", "骷髅精灵", "洞蛆", "山洞蝙蝠", "蝎子",
    "僵尸1", "僵尸2", "僵尸3", "僵尸4", "僵尸5", "尸王",
]
MAP_IDS = {"D001": 217, "D002": 218, "D003": 221}
CORE_FIELDS = {
    "level": "MonsterLevel", "exp": "MonsterExperience", "hp": "StatHP",
    "defense": "StatMaxAC", "magicDefense": "StatMaxMAC",
    "attackMin": "StatMinDC", "attackMax": "StatMaxDC",
}


def integer(value: str) -> int:
    return int(value or 0)


def active_drop_rows(path: Path) -> list[dict]:
    rows = []
    if not path.exists():
        return rows
    for raw in path.read_text(encoding="utf-8-sig", errors="replace").splitlines():
        line = raw.strip()
        if not line or line.startswith(";"):
            continue
        match = re.match(r"^(\d+)/(\d+)\s+(.+?)\s*$", line)
        if not match:
            continue
        rows.append({"numerator": int(match.group(1)), "denominator": int(match.group(2)), "item": match.group(3)})
    return rows


def main() -> None:
    if not COMMUNITY.exists() or not CRYSTAL.exists():
        raise SystemExit("社区数据库尚未下载")
    base = json.loads(BASE_DATA.read_text(encoding="utf-8"))
    base_monsters = {row["name"]: row for row in base["monsters"]}
    item_names = {row["name"] for row in base["items"]}
    skill_names = {row["skillName"] for row in base["skills"]}
    runtime_whitelist = item_names | skill_names
    exports = COMMUNITY / "Exports"
    monster_csv = next(exports.glob("3_*.csv"))
    with monster_csv.open(encoding="utf-8-sig", newline="") as handle:
        community_rows = {row["MonsterName"]: row for row in csv.DictReader(handle)}

    overrides = {}
    missing = []
    for name in MONSTER_NAMES:
        source = community_rows.get(name)
        current = base_monsters.get(name)
        if source is None or current is None:
            missing.append(name)
            continue
        agreements, conflicts = {}, {}
        for target_field, source_field in CORE_FIELDS.items():
            community_value = integer(source[source_field])
            current_value = int(current.get(target_field, 0))
            if community_value == current_value:
                agreements[target_field] = community_value
            else:
                conflicts[target_field] = {"current": current_value, "community": community_value, "adopted": "current"}
        overrides[name] = {
            "fields": {
                "agility": integer(source.get("Stat敏捷", "15")),
                "accuracy": integer(source.get("Stat准确", "5")),
                "attackIntervalMs": integer(source["MonsterAttackSpeed"]),
                "moveIntervalMs": integer(source["MonsterMoveSpeed"]),
                "communityConfidence": "B+" if len(agreements) >= 3 else "B",
                "communityVerification": "Crystal社区数据库与1.76资料交叉；冲突核心字段保持原值",
            },
            "agreements": agreements,
            "conflicts": conflicts,
            "source": "angelk727/Mir2ServerDatabases@16c49ad5/Exports/3_怪物数据.csv",
        }

    spawn_lines = next(exports.glob("6_*.txt")).read_text(encoding="utf-8-sig").splitlines()
    spawn_profiles: dict[str, dict] = {}
    allowed_spawn_names = set(MONSTER_NAMES) - {"毒蜘蛛", "僵尸1", "僵尸2", "僵尸3", "僵尸4", "僵尸5", "尸王"}
    for source_map, runtime_id in MAP_IDS.items():
        groups = []
        for raw in spawn_lines:
            parts = [part.strip() for part in raw.split(",")]
            if len(parts) < 8 or parts[0] != source_map or parts[3] not in allowed_spawn_names:
                continue
            groups.append({
                "name": parts[3], "center": [int(parts[1]), int(parts[2])], "spread": int(parts[4]),
                "sourceCount": int(parts[5]), "respawnMinutes": int(parts[6]), "direction": int(parts[7]),
            })
        spawn_profiles[str(runtime_id)] = {
            "sourceMap": source_map, "groups": groups, "sourceGroupCount": len(groups),
            "runtimePolicy": "画像参考；不按sourceCount全量生成，保留当前手机代表点阵容",
            "confidence": "B",
        }

    drops_dir = COMMUNITY / "Envir/Drops"
    drop_audit = {}
    for name in MONSTER_NAMES:
        rows = active_drop_rows(drops_dir / f"{name}.txt")
        accepted, rejected = [], []
        for row in rows:
            item_name = re.sub(r"\s+\d+$", "", row["item"])
            reason = ""
            if item_name == "Gold":
                reason = "金币命名/数量需单独映射"
            elif item_name not in runtime_whitelist:
                reason = "不在当前175件装备/经典技能书白名单"
            elif row["denominator"] < (3 if name in {"骷髅精灵", "尸王"} else 20):
                reason = "概率高于保守阈值，疑似私服放大"
            if reason:
                rejected.append({**row, "reason": reason})
            else:
                accepted.append({**row, "item": item_name})
        drop_audit[name] = {
            "acceptedCandidates": accepted, "rejected": rejected,
            "runtimeApplied": False, "source": f"angelk727/Mir2ServerDatabases@16c49ad5/Envir/Drops/{name}.txt",
        }

    def slot(name: str, denominator: int, basis: str) -> dict:
        return {"name": name, "denominator": denominator, "source": basis, "confidence": "B"}

    # Surface monsters previously fell through to a 55% generic placeholder. These compact tables use
    # community items but conservative probabilities; cave/mine ordinary monsters retain their existing
    # authored tables until their own cross-check is complete.
    runtime_drops = {
        "稻草人": [slot("金币 50", 10, "community"), slot("金创药(小量)", 20, "mobile_mapping"), slot("匕首", 40, "community_clamped"), slot("布衣(男)", 70, "community_clamped"), slot("乌木剑", 500, "community")],
        "钉耙猫": [slot("金币 100", 20, "community"), slot("金创药(小量)", 18, "mobile_mapping"), slot("匕首", 50, "community_clamped"), slot("布衣(男)", 80, "community_clamped"), slot("古铜戒指", 100, "community_clamped")],
        "多钩猫": [slot("金币 100", 20, "community"), slot("魔法药(小量)", 18, "mobile_mapping"), slot("匕首", 50, "community_clamped"), slot("布衣(女)", 80, "community_clamped"), slot("玻璃戒指", 100, "community_clamped")],
        "半兽人": [slot("金币 100", 20, "community"), slot("金创药(小量)", 16, "mobile_mapping"), slot("乌木剑", 180, "community_conservative")],
        "半兽战士": [slot("金币 300", 10, "community"), slot("金创药(小量)", 14, "mobile_mapping"), slot("青铜剑", 120, "community_clamped"), slot("铁剑", 150, "community_clamped"), slot("轻型盔甲(男)", 100, "community_clamped")],
        "森林雪人": [slot("金币 100", 10, "community"), slot("魔法药(小量)", 15, "mobile_mapping"), slot("凌风", 120, "community_clamped"), slot("轻型盔甲(男)", 120, "community_clamped"), slot("坚固手套", 160, "community_clamped")],
        "食人花": [slot("金币 100", 10, "community"), slot("金创药(小量)", 18, "mobile_mapping")],
        "毒蜘蛛": [slot("金币 100", 12, "community_conservative"), slot("魔法药(小量)", 20, "mobile_mapping")],
        "骷髅精灵": [
            slot("金币 1200", 1, "21cq_and_community"), slot("强效太阳水", 4, "21cq_conservative"),
            slot("八荒", 100, "community_clamped"), slot("海魂", 100, "community_clamped"),
            slot("半月", 100, "community_clamped"), slot("凌风", 120, "community_clamped"),
        ],
        "尸王": [
            slot("金币 2500", 1, "21cq_and_community"), slot("强效太阳水", 4, "21cq_conservative"),
            slot("攻杀剑术", 80, "community_clamped"), slot("雷电术", 80, "community_clamped"),
            slot("召唤骷髅", 80, "community_clamped"), slot("大火球", 100, "community_clamped"),
        ],
    }

    payload = {
        "baseline": "社区经典基准选择性导入",
        "sources": {
            "crystalDatabase": {"commit": "a19f6dca8f5e238d4ed79801820777abbf0a9ca4", "role": "社区数据库母库"},
            "readableExport": {"commit": "16c49ad53f3bc2ff6f9f584117e61b5b9fe4970f", "role": "中文可读导出"},
        },
        "policy": "只应用怪物时序、准确和敏捷；核心数值冲突保持当前中国1.76资料值；刷新仅导入画像；掉落仅按经典白名单和移动端保守概率进入运行表。",
        "runtimeMonsterOverrides": overrides,
        "spawnProfiles": spawn_profiles,
        "dropAudit": drop_audit,
        "runtimeDrops": runtime_drops,
        "missingRuntimeMatches": missing,
        "summary": {
            "monsterOverrides": len(overrides),
            "spawnGroups": sum(row["sourceGroupCount"] for row in spawn_profiles.values()),
            "dropAcceptedCandidates": sum(len(row["acceptedCandidates"]) for row in drop_audit.values()),
            "dropRejected": sum(len(row["rejected"]) for row in drop_audit.values()),
            "runtimeDropMonsters": len(runtime_drops),
            "runtimeDropSlots": sum(len(rows) for rows in runtime_drops.values()),
            "conflictFields": sum(len(row["conflicts"]) for row in overrides.values()),
            "agreementFields": sum(len(row["agreements"]) for row in overrides.values()),
            "missingNames": Counter(missing),
        },
    }
    OUTPUT.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(payload["summary"], ensure_ascii=False, default=dict))


if __name__ == "__main__":
    main()
