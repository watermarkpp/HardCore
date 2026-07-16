#!/usr/bin/env python3
"""Generate the actionable Bich gap registry from the closure audit."""

from __future__ import annotations

import json
from datetime import date
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
AUDIT = ROOT / "assets/data/bich_closure_audit.json"
OUTPUT_JSON = ROOT / "assets/data/bich_gap_registry.json"
OUTPUT_MD = ROOT / "docs/BICH-GAP-CLOSE-1_缺口清理与阻塞清单.md"

CLIENT_ASSET_GAPS = {"客户端动作、特效与音效", "客户端装备图标与穿戴外观"}
MILESTONE_ONLY = {"比奇闭环里程碑APK", "骷髅精灵与尸王Boss机制"}
MIXED_VALIDATION = {"五项主动技能专属机制", "耐久损耗与修理", "幸运、诅咒与祝福油"}
COMMUNITY_NEXT = {"属性与掉落数据库"}

REQUIRED_INPUTS = {
    "比奇省0.map、服务端HomeMap与0100室内图归类": ["MapInfo", "MonGen"],
    "兽人古墓D001—D003原图接入": ["MapInfo", "MonGen"],
    "天然洞穴D011—D012原图接入": ["MapInfo", "MonGen"],
    "尸王殿Q004来源与Boss房": ["MapInfo", "MonGen"],
    "属性与掉落数据库": ["社区经典掉落交叉校准", "运行经济回归"],
    "骷髅精灵与尸王Boss机制": ["里程碑实战验证"],
    "原版伤害、范围与等级公式": ["Magic.DB"],
    "五项主动技能专属机制": ["Magic.DB", "里程碑实战验证"],
    "客户端动作、特效与音效": ["Wav/130.wav—137.wav", "野蛮冲撞对应客户端资源"],
    "穿戴要求与属性结算": ["StdItems.DB"],
    "耐久损耗与修理": ["StdItems.DB.Price", "里程碑实战验证"],
    "幸运、诅咒与祝福油": ["StdItems.DB", "里程碑存档验证"],
    "特殊装备效果": ["StdItems.DB.AniCount/Need"],
    "客户端装备图标与穿戴外观": ["StdItems.DB.Shape", "缺失的客户端外观块"],
    "比奇NPC商店与修理": ["Merchant", "Market_Def"],
    "比奇任务链": ["QuestDiary", "NPC脚本"],
    "掉落与经济的服务端一致性": ["MonItems", "Merchant", "Market_Def", "StdItems.DB.Price"],
    "比奇闭环里程碑APK": ["荣耀90里程碑验收"],
}


def classify(name: str) -> str:
    if name in COMMUNITY_NEXT:
        return "社区基准部分接入"
    if name in MILESTONE_ONLY:
        return "等待里程碑验证"
    if name in CLIENT_ASSET_GAPS:
        return "等待客户端资源"
    if name in MIXED_VALIDATION:
        return "正式数据与里程碑验证"
    return "等待正式服务端数据"


def main() -> None:
    audit = json.loads(AUDIT.read_text(encoding="utf-8"))
    gaps = []
    for check in audit["checks"]:
        if float(check["credit"]) >= 1.0:
            continue
        name = str(check["name"])
        gaps.append({
            "name": name,
            "category": check["category"],
            "completion": round(float(check["credit"]), 2),
            "status": classify(name),
            "requiredInputs": REQUIRED_INPUTS.get(name, []),
            "gap": check["gap"],
            "safeToGuess": False,
        })

    counts: dict[str, int] = {}
    for gap in gaps:
        counts[gap["status"]] = counts.get(gap["status"], 0) + 1
    payload = {
        "generatedAt": date.today().isoformat(),
        "policy": "服务端/客户端正式资料优先；允许采用可追溯社区经典基准，但必须白名单过滤、保留冲突且不得整库覆盖。",
        "closedFalseGaps": [
            "战士刺杀/半月开关、攻杀周期与烈火蓄力状态机已经完成，不再列为待实现。",
            "记忆组队传送和祈祷宠物叛变不适用于当前单机边界，不再列为代码缺陷。",
            "19张比奇地图的原MAP阻挡分块已经完成，不再列为地图缺口。",
        ],
        "remainingCount": len(gaps),
        "statusCounts": counts,
        "gaps": gaps,
    }
    OUTPUT_JSON.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    lines = [
        "# BICH-GAP-CLOSE-1：缺口清理与阻塞清单",
        "",
        f"> 生成日期：{payload['generatedAt']}  ",
        f"> 未满分审计项：{len(gaps)}项  ",
        "> 所有剩余项均禁止猜测填充。",
        "",
        "## 已清除的假缺口",
        "",
    ]
    lines += [f"- {item}" for item in payload["closedFalseGaps"]]
    lines += ["", "## 剩余缺口", "", "| 状态 | 项目 | 当前完成度 | 所需输入 |", "|---|---|---:|---|"]
    for gap in gaps:
        required = "、".join(gap["requiredInputs"]) or "来源复核"
        lines.append(f"| {gap['status']} | {gap['name']} | {gap['completion'] * 100:.0f}% | {required} |")
    lines += [
        "",
        "## 执行结论",
        "",
        "- 社区怪物基准已经选择性接入；当前可继续施工 `BICH-COMMUNITY-DATA-3`，对375条经典掉落候选逐条校准。",
        "- 正式数据请放入 `import_server_data/`；导入器会先进行版本检查、dry-run和差异审计，确认后才允许覆盖。",
        "- 掉落校准完成后再执行 `BICH-MILESTONE-1` 限量真机验收；里程碑不会提升数据来源可信度。",
        "",
    ]
    OUTPUT_MD.write_text("\n".join(lines), encoding="utf-8")
    print(json.dumps({"remaining": len(gaps), "counts": counts}, ensure_ascii=False))


if __name__ == "__main__":
    main()
