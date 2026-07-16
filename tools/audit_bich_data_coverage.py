#!/usr/bin/env python3
"""Audit BICH-DATA-1 without promoting late/unverified data into runtime."""

from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RUNTIME = ROOT / "assets/data/legend176_data.json"
CROSSCHECK = ROOT / "assets/data/bich_public_database_crosscheck.json"
SERVICE_REFERENCE = ROOT / "assets/data/service_reference.json"
IMPORT_REPORT = ROOT / "assets/data/server_import_report.json"
OUTPUT = ROOT / "docs/BICH-DATA-1_数据来源与覆盖审计.md"
TARGETS = ["稻草人", "钉耙猫", "半兽人", "森林雪人", "食人花", "骷髅", "掷斧骷髅", "骷髅战士", "骷髅战将", "骷髅精灵", "僵尸1", "尸王", "洞蛆", "蝎子", "山洞蝙蝠"]
FIELDS = ["level", "hp", "exp", "defense", "magicDefense", "attackMin", "attackMax"]


def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def main() -> None:
    runtime = load(RUNTIME)
    crosscheck = load(CROSSCHECK)
    service = load(SERVICE_REFERENCE)
    import_report = load(IMPORT_REPORT)
    runtime_by_name = {}
    for row in [*runtime.get("monsters", []), *runtime.get("bosses", [])]:
        if row.get("name") in TARGETS:
            runtime_by_name[row["name"]] = row
    public_by_name = {row["name"]: row for row in crosscheck.get("monsters", [])}
    public_field_map = {
        "level": lambda row: row.get("level"), "hp": lambda row: row.get("hp"),
        "exp": lambda row: row.get("experience"), "defense": lambda row: (row.get("defense") or [None])[-1],
        "magicDefense": lambda row: (row.get("magicDefense") or [None])[-1],
        "attackMin": lambda row: (row.get("attack") or [None, None])[0],
        "attackMax": lambda row: (row.get("attack") or [None, None])[-1],
    }
    comparisons = []
    exact_cells = 0
    compared_cells = 0
    for name in TARGETS:
        current, public = runtime_by_name.get(name), public_by_name.get(name)
        exact = []
        different = []
        if current and public:
            for field in FIELDS:
                a, b = current.get(field), public_field_map[field](public)
                compared_cells += 1
                if a == b:
                    exact.append(field)
                    exact_cells += 1
                else:
                    different.append(f"{field}:{a}→{b}")
        comparisons.append((name, current, public, exact, different))
    required = service.get("requiredServerTables", {})
    available = [name for name, info in required.items() if info.get("status") == "available"]
    lines = [
        "# BICH-DATA-1：数据来源与覆盖审计", "",
        "## 结论", "",
        f"- 比奇目标怪物运行条目：{len(runtime_by_name)}/{len(TARGETS)}；当前均为带来源的B级候选。",
        f"- 正式传统服务端表：{len(available)}/{len(required)}可用；`import_server_data` dry-run缺失{len(import_report.get('missing', []))}类输入。",
        f"- 公开后期数据库交叉命中：{len(public_by_name)}/{len(TARGETS)}；可比字段完全一致{exact_cells}/{compared_cells}。",
        "- 公开库含刺客、坐骑、暴击等现代Crystal字段，地图0也不是比奇省，因此全部保持后期候选，未覆盖2003运行库。",
        "- 骷髅精灵2000/1200ms与尸王2800/1500ms攻击/移动间隔在网页候选和公开数据库中一致，可继续保持B级双源候选。",
        "", "## 比奇怪物字段交叉结果", "",
        "| 怪物 | 运行候选 | 后期库 | 一致字段 | 差异字段（运行→后期） |", "|---|---|---|---|---|",
    ]
    for name, current, public, exact, different in comparisons:
        lines.append(f"| {name} | {'有' if current else '缺'} | {'有' if public else '缺'} | {', '.join(exact) or '—'} | {'；'.join(different) or '—'} |")
    lines += [
        "", "## 地图与刷新交叉结果", "",
        f"- 后期库命中目标地图{crosscheck['summary']['mapMatches']}张、目标刷新{crosscheck['summary']['spawnMatches']}行。",
        "- D001/D002/D003名称仍对应半兽古墓一至三层，可用于确认地图语义；坐标、数量和刷新周期不直接采用。",
        "- 地图0在后期库名为飞天县，与当前2003比奇省基准冲突，已明确拒绝映射。",
        "- D011/D012/Q004没有在该后期导出中形成目标地图命中，继续等待传统MapInfo/MonGen。",
        "", "## 导入安全链", "",
        "- 自动识别根目录、`Mir200`、`MirServer/Mir200`、`Server/Mir200`。",
        "- 无 `import_manifest.json` 时记录标为未确认版本，允许dry-run但拒绝`--apply`。",
        "- 基准与后期文件可逐文件标记；合并前生成差异报告和运行库备份。",
        "", "## 尚未完成", "",
        "- 缺同版本Monster、StdItems、Magic、MapInfo、MonGen、MonItems、Merchant及Market_Def正式文件。",
        "- 因正式数据缺失，本审计没有提高运行内容的数据还原分数；不以公开后期库冒充官服数据。", "",
    ]
    OUTPUT.write_text("\n".join(lines), encoding="utf-8")
    print(json.dumps({"report": str(OUTPUT), "runtimeTargets": len(runtime_by_name), "publicMatches": len(public_by_name), "exactCells": exact_cells, "comparedCells": compared_cells}, ensure_ascii=False))


if __name__ == "__main__":
    main()
