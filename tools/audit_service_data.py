from __future__ import annotations

import json
import re
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
WORKSPACE = ROOT.parents[1]
SETUP_PATH = WORKSPACE / "research/MIR2/GameOfMir/MirServer/Mir200/!Setup.txt"
M2SHARE_PATH = WORKSPACE / "research/MIR2/GameOfMir/M2Server/M2Share.pas"
DATA_PATH = ROOT / "assets/data/legend176_data.json"
REFERENCE_PATH = ROOT / "assets/data/service_reference.json"
REPORT_PATH = ROOT / "docs/MIR2-DATA-1_Server_Data_Calibration_Report.md"

REQUIRED_SERVER_TABLES = {
    "map_info": ["Envir/MapInfo.txt", "Mir200/Envir/MapInfo.txt"],
    "monster_spawns": ["Envir/MonGen.txt", "Mir200/Envir/MonGen.txt"],
    "monster_drops": ["Envir/MonItems", "Mir200/Envir/MonItems"],
    "npc_merchants": ["Envir/Merchant.txt", "Mir200/Envir/Merchant.txt"],
    "npc_scripts": ["Envir/Market_Def", "Mir200/Envir/Market_Def"],
    "monster_db": ["Monster.DB", "Monster.csv", "Mir200/Monster.DB", "DB/Monster.DB"],
    "item_db": ["StdItems.DB", "StdItems.csv", "Mir200/StdItems.DB", "DB/StdItems.DB"],
    "magic_db": ["Magic.DB", "Magic.csv", "Mir200/Magic.DB", "DB/Magic.DB"],
}
SERVICE_KEYS = [
    "HomeMap", "HomeX", "HomeY", "RedHomeMap", "RedHomeX", "RedHomeY", "MonGenRate",
    "HitIntervalTime", "MagicHitIntervalTime", "WalkIntervalTime", "RunIntervalTime",
    "ActionIntervalTime", "ControlActionInterval", "ControlWalkHit", "ControlRunLongHit",
    "ControlRunHit", "ControlRunMagic", "RunLongHitIntervalTime", "RunHitIntervalTime",
    "WalkHitIntervalTime", "RunMagicIntervalTime", "MagicAttackRage", "LevelValueOfWarrHP",
    "LevelValueOfWarrHPRate", "LevelValueOfWizardHP", "LevelValueOfWizardHPRate",
    "LevelValueOfTaosHP", "LevelValueOfTaosHPRate", "LevelValueOfTaosMP",
]


def parse_scalar(raw: str):
    if re.fullmatch(r"-?\d+", raw):
        return int(raw)
    if re.fullmatch(r"-?\d+\.\d+", raw):
        return float(raw)
    return raw


def read_setup() -> tuple[dict, dict]:
    text = SETUP_PATH.read_text(encoding="gb18030", errors="replace")
    values = {}
    for key in SERVICE_KEYS:
        match = re.search(rf"^{re.escape(key)}=(.*)$", text, re.MULTILINE)
        if match:
            values[key] = parse_scalar(match.group(1).strip())
    exp = {m.group(1): int(m.group(2)) for m in re.finditer(r"^Level(\d+)=(\d+)$", text, re.MULTILINE) if 1 <= int(m.group(1)) <= 60}
    return values, exp


def read_runtime_exp() -> dict:
    text = M2SHARE_PATH.read_text(encoding="gb18030", errors="replace")
    block = re.search(r"g_dwOldNeedExps:\s*TLevelNeedExp\s*=\s*\((.*?)\);", text, re.DOTALL)
    if not block:
        return {}
    numbers = re.findall(r"^\s*(\d+),?\s*//", block.group(1), re.MULTILINE)
    return {str(index): int(value) for index, value in enumerate(numbers[:60], start=1)}


def find_required_tables() -> dict:
    roots = [ROOT / "import_server_data", WORKSPACE / "research/MIR2/GameOfMir/MirServer", WORKSPACE / "research/MIR2/GameOfMir"]
    result = {}
    for table, candidates in REQUIRED_SERVER_TABLES.items():
        matches = []
        for root in roots:
            for candidate in candidates:
                path = root / candidate
                if path.exists():
                    matches.append(str(path.relative_to(WORKSPACE)))
        result[table] = {"status": "available" if matches else "missing", "expected": candidates, "matches": sorted(set(matches))}
    return result


def coverage(count: int, total: int) -> dict:
    return {"count": count, "total": total, "ratio": round(count / total, 4) if total else 0.0}


def audit_project() -> dict:
    data = json.loads(DATA_PATH.read_text(encoding="utf-8"))
    result = {}
    for table in ("maps", "monsters", "bosses", "items", "skills", "drops", "tasks"):
        rows = data.get(table, [])
        source_count = sum(bool(str(row.get("sourceUrl", "")).strip()) for row in rows)
        second_count = sum(bool(str(row.get("secondarySourceUrl", "")).strip()) for row in rows)
        verify_count = sum(bool(str(row.get("verification", "")).strip()) for row in rows)
        result[table] = {
            "rows": len(rows),
            "recordStatus": dict(Counter(str(row.get("recordStatus", "未标记")) for row in rows)),
            "confidence": dict(Counter(str(row.get("confidence", "未标记")) for row in rows)),
            "versionTag": dict(Counter(str(row.get("versionTag", "未标记")) for row in rows)),
            "sourceUrlCoverage": coverage(source_count, len(rows)),
            "secondarySourceUrlCoverage": coverage(second_count, len(rows)),
            "verificationCoverage": coverage(verify_count, len(rows)),
        }
    return result


def make_reference() -> dict:
    setup, configured_exp = read_setup()
    return {
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "baseline": "2003官服1.76基准优先；后期追加内容单独开关",
        "sourcePriority": ["完整服务端Envir/DB数据", "服务端!Setup.txt与M2Server源码", "客户端动作表与WIL/MAP资源", "项目结构化数据", "带来源与可信度的网络资料"],
        "serviceSetupPath": str(SETUP_PATH.relative_to(WORKSPACE)),
        "serviceSetup": setup,
        "serviceExpTableLevel1To60": configured_exp,
        "serviceRuntimeExpTableLevel1To60": read_runtime_exp(),
        "serviceRuntimeExpSource": str(M2SHARE_PATH.relative_to(WORKSPACE)),
        "requiredServerTables": find_required_tables(),
        "projectDataPath": str(DATA_PATH.relative_to(WORKSPACE)),
        "projectTables": audit_project(),
        "policyOverrides": {"normalAttackIntervalMs": {"serviceReference": setup.get("HitIntervalTime"), "currentMobileDesign": 850, "decision": "保留用户指定的手机续刀手感；服务端值仅作参考。"}},
    }


def render_report(ref: dict) -> str:
    lines = ["# MIR2-DATA-1 服务端数据校准报告", "", f"生成时间：`{ref['generatedAt']}`", "", "## 结论", "", "- 服务端配置与源码规则可直接读取。", "- 完整Envir/DB数据是否可用以本报告的缺口表为准。", "- 项目七张结构化表保留来源、可信度和版本标签。", "", "## 完整服务端数据包检查", "", "| 数据项 | 状态 | 命中路径 |", "|---|---|---|"]
    for table, info in ref["requiredServerTables"].items():
        paths = "<br/>".join(f"`{p}`" for p in info["matches"]) or "未找到"
        lines.append(f"| `{table}` | {info['status']} | {paths} |")
    lines.extend(["", "## 项目七张表审计", "", "| 表 | 行数 | 来源覆盖 | 验证说明覆盖 |", "|---|---:|---:|---:|"])
    for table, info in ref["projectTables"].items():
        source, verify = info["sourceUrlCoverage"], info["verificationCoverage"]
        lines.append(f"| `{table}` | {info['rows']} | {source['count']}/{source['total']} | {verify['count']}/{verify['total']} |")
    lines.extend(["", "## 设计覆盖", "", f"- 普攻间隔：服务端参考 `{ref['policyOverrides']['normalAttackIntervalMs']['serviceReference']}ms`，手机设计 `850ms`。", "- 完整数据包放入 `import_server_data` 后，使用 MIR2-DATA-3 导入器生成差异报告，再决定是否合并。", ""])
    return "\n".join(lines)


def main() -> None:
    ref = make_reference()
    REFERENCE_PATH.write_text(json.dumps(ref, ensure_ascii=False, indent=2), encoding="utf-8")
    REPORT_PATH.write_text(render_report(ref), encoding="utf-8")
    missing = [key for key, info in ref["requiredServerTables"].items() if info["status"] == "missing"]
    print(f"SERVICE_REFERENCE={REFERENCE_PATH.relative_to(ROOT)}")
    print(f"SERVICE_REPORT={REPORT_PATH.relative_to(ROOT)}")
    print(f"MISSING_REQUIRED_TABLES={len(missing)}:{','.join(missing)}")


if __name__ == "__main__":
    main()
