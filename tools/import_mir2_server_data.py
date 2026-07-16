from __future__ import annotations

import argparse
import csv
import json
import re
import shutil
import struct
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SOURCE = ROOT / "import_server_data"
PROJECT_DATA = ROOT / "assets/data/legend176_data.json"
OUTPUT_DATA = ROOT / "assets/data/server_import_candidate.json"
OUTPUT_REPORT = ROOT / "assets/data/server_import_report.json"
REPORT_MD = ROOT / "docs/MIR2-DATA-3_服务端导入差异报告.md"
BASELINE = "2003官服1.76基准版"
LATE_CONTENT = "1.76后期追加内容"
UNKNOWN_VERSION = "未确认版本"
TABLES = ("maps", "monsters", "bosses", "items", "skills", "drops", "tasks")


def read_text(path: Path) -> str:
    raw = path.read_bytes()
    for encoding in ("utf-8-sig", "gb18030", "big5"):
        try:
            return raw.decode(encoding)
        except UnicodeDecodeError:
            pass
    return raw.decode("latin-1", errors="replace")


def clean_lines(path: Path) -> list[str]:
    result: list[str] = []
    for raw in read_text(path).splitlines():
        line = re.split(r";|//", raw, maxsplit=1)[0].strip()
        if line:
            result.append(line)
    return result


def scalar(value: Any, default: Any = None) -> Any:
    if value is None or str(value).strip() == "":
        return default
    text = str(value).strip()
    try:
        return int(float(text))
    except ValueError:
        return text


def normalized_name(value: Any) -> str:
    return re.sub(r"[\s·・_\-（）()]+", "", str(value or "")).casefold()


def find_ci(root: Path, relative: str) -> Path | None:
    current = root
    for part in Path(relative).parts:
        if not current.is_dir():
            return None
        match = next((p for p in current.iterdir() if p.name.casefold() == part.casefold()), None)
        if match is None:
            return None
        current = match
    return current


def source_version(path: Path, source: Path, manifest: dict[str, Any]) -> str:
    rel = path.relative_to(source).as_posix()
    configured = manifest.get("files", {}).get(rel, {}).get("versionTag")
    if configured in (BASELINE, LATE_CONTENT):
        return configured
    if re.search(r"幻境|圣域|追加|后期", rel, re.I):
        return LATE_CONTENT
    default = manifest.get("defaultVersionTag", UNKNOWN_VERSION)
    return default if default in (BASELINE, LATE_CONTENT) else UNKNOWN_VERSION


def provenance(path: Path, source: Path, manifest: dict[str, Any]) -> dict[str, Any]:
    version = source_version(path, source, manifest)
    manifest_provided = bool(manifest.get("_manifestProvided", False))
    return {
        "versionTag": version,
        "availabilityDefault": version == BASELINE,
        "recordStatus": "服务端原始数据导入",
        "serviceSourcePath": path.relative_to(source).as_posix(),
        "sourceDate": datetime.now().date().isoformat(),
        "confidence": "A",
        "versionConfidence": "A" if manifest_provided else "C",
        "verification": "本地传统服务端数据直接解析；版本已由import_manifest显式标记" if manifest_provided else "本地传统服务端数据直接解析；版本未确认，禁止直接覆盖基准库",
    }


def parse_map_info(path: Path, source: Path, manifest: dict[str, Any]) -> tuple[list[dict], list[dict]]:
    maps: dict[str, dict] = {}
    portals: list[dict] = []
    meta = provenance(path, source, manifest)
    for line in clean_lines(path):
        match = re.match(r"^\[([^\]\s]+)\s+([^\]]+?)(?:\s+\d+)?\](.*)$", line)
        if match:
            map_code, name, flags = match.groups()
            maps[map_code] = {
                "mapCode": map_code,
                "name": name.strip(),
                "mapFlags": flags.strip().split(),
                **meta,
            }
            continue
        door = re.match(
            r"^(\S+)\s+(\d+)\s+(\d+)\s+(?:->|TO)\s*(\S+)\s+(\d+)\s+(\d+)", line, re.I
        )
        if door:
            a, ax, ay, b, bx, by = door.groups()
            portals.append({
                "fromMapCode": a, "fromX": int(ax), "fromY": int(ay),
                "toMapCode": b, "toX": int(bx), "toY": int(by), **meta,
            })
    for code, row in maps.items():
        row["doorCount"] = sum(1 for p in portals if p["fromMapCode"] == code)
    return list(maps.values()), portals


def parse_mon_gen(path: Path, source: Path, manifest: dict[str, Any]) -> list[dict]:
    rows: list[dict] = []
    meta = provenance(path, source, manifest)
    for line in clean_lines(path):
        parts = line.split()
        if len(parts) < 7:
            continue
        rows.append({
            "mapCode": parts[0], "x": scalar(parts[1]), "y": scalar(parts[2]),
            "monsterName": parts[3], "range": scalar(parts[4]), "count": scalar(parts[5]),
            "respawnMinutes": scalar(parts[6]), **meta,
        })
    return rows


def parse_mon_items(folder: Path, source: Path, manifest: dict[str, Any]) -> list[dict]:
    rows: list[dict] = []
    for path in sorted(folder.rglob("*.txt")):
        meta = provenance(path, source, manifest)
        boss_name = path.stem
        for slot, line in enumerate(clean_lines(path), start=1):
            parts = line.split()
            if len(parts) < 2:
                continue
            rate = re.match(r"(\d+)\s*/\s*(\d+)", parts[0])
            if not rate:
                continue
            numerator, denominator = map(int, rate.groups())
            rows.append({
                "dropId": f"srv:{boss_name}:{slot:03d}", "bossName": boss_name,
                "itemName": parts[1], "numerator": numerator, "denominator": denominator,
                "probability": numerator / denominator if denominator else 0.0,
                "duplicateSlot": slot, "amountMin": scalar(parts[2]) if len(parts) > 2 else 1,
                "amountMax": scalar(parts[3]) if len(parts) > 3 else scalar(parts[2], 1) if len(parts) > 2 else 1,
                **meta,
            })
    return rows


def parse_merchants(path: Path, source: Path, manifest: dict[str, Any]) -> list[dict]:
    rows = []
    meta = provenance(path, source, manifest)
    for line in clean_lines(path):
        parts = line.split()
        if len(parts) >= 4:
            rows.append({"npcName": parts[0], "mapCode": parts[1], "x": scalar(parts[2]), "y": scalar(parts[3]), "raw": line, **meta})
    return rows


def parse_task_scripts(folder: Path, source: Path, manifest: dict[str, Any]) -> list[dict]:
    rows = []
    quest_tokens = re.compile(r"CHECKITEM|TAKE|GIVE|CHECKLEVEL|任务|奖励", re.I)
    for path in sorted(folder.rglob("*.txt")):
        text = read_text(path)
        if not quest_tokens.search(text):
            continue
        labels = re.findall(r"^\s*\[@([^\]]+)\]", text, re.MULTILINE | re.I)
        rows.append({
            "taskId": "srv:" + path.relative_to(folder).with_suffix("").as_posix(),
            "name": path.stem, "taskType": "服务端NPC脚本候选",
            "prerequisite": "需解析#IF条件", "objectiveSummary": "需按脚本标签与物品条件结构化",
            "rewardSummary": "需解析GIVE/奖励指令", "repeatable": "需核验",
            "scriptLabels": labels, **provenance(path, source, manifest),
        })
    return rows


def parse_dbf(path: Path) -> list[dict[str, Any]]:
    raw = path.read_bytes()
    if len(raw) < 32 or raw[0] not in {0x02, 0x03, 0x04, 0x30, 0x31, 0x32, 0x43, 0x63, 0x83, 0x8B, 0xCB, 0xF5}:
        raise ValueError("不是受支持的 dBase/DBF 文件；可能是 Borland Paradox .DB，请导出 CSV")
    count = struct.unpack_from("<I", raw, 4)[0]
    header_len, record_len = struct.unpack_from("<HH", raw, 8)
    fields: list[tuple[str, str, int, int]] = []
    offset = 32
    while offset + 32 <= header_len and raw[offset] != 0x0D:
        desc = raw[offset:offset + 32]
        name = desc[:11].split(b"\0", 1)[0].decode("ascii", errors="replace")
        fields.append((name, chr(desc[11]), desc[16], desc[17]))
        offset += 32
    result: list[dict[str, Any]] = []
    for index in range(count):
        record = raw[header_len + index * record_len:header_len + (index + 1) * record_len]
        if len(record) != record_len or record[:1] == b"*":
            continue
        pos, row = 1, {}
        for name, kind, width, decimals in fields:
            text = record[pos:pos + width].decode("gb18030", errors="replace").strip().strip("\0")
            pos += width
            if kind in "NF" and text:
                row[name] = float(text) if decimals else int(float(text))
            elif kind == "L":
                row[name] = text.upper() in ("Y", "T")
            else:
                row[name] = text
        result.append(row)
    return result


def read_table(source: Path, stem: str) -> tuple[list[dict], Path | None, str | None]:
    candidates = [f"{stem}.csv", f"{stem}.json", f"{stem}.DB", f"DB/{stem}.csv", f"DB/{stem}.json", f"DB/{stem}.DB"]
    path = next((found for name in candidates if (found := find_ci(source, name)) and found.is_file()), None)
    if path is None:
        return [], None, "缺失"
    try:
        if path.suffix.casefold() == ".csv":
            return list(csv.DictReader(read_text(path).splitlines())), path, None
        if path.suffix.casefold() == ".json":
            value = json.loads(read_text(path))
            return value if isinstance(value, list) else value.get("rows", []), path, None
        return parse_dbf(path), path, None
    except Exception as exc:  # report malformed/proprietary DB without stopping other imports
        return [], path, str(exc)


def field(row: dict, *names: str, default: Any = None) -> Any:
    by_key = {str(k).casefold(): v for k, v in row.items()}
    return next((by_key[name.casefold()] for name in names if name.casefold() in by_key), default)


def transform_monsters(rows: list[dict], path: Path | None, source: Path, manifest: dict) -> list[dict]:
    if not path:
        return []
    meta = provenance(path, source, manifest)
    result = []
    for row in rows:
        result.append({
            "monsterId": scalar(field(row, "Idx", "Id")), "name": field(row, "Name", "MonName"),
            "level": scalar(field(row, "Lvl", "Level")), "exp": scalar(field(row, "Exp")),
            "hp": scalar(field(row, "HP")), "defense": scalar(field(row, "AC")),
            "magicDefense": scalar(field(row, "MAC")), "attackMin": scalar(field(row, "DC")),
            "attackMax": scalar(field(row, "DcMax", "DC2")), "race": scalar(field(row, "Race")),
            "appearance": scalar(field(row, "Appr", "Looks")), **meta,
        })
    return [row for row in result if row.get("name")]


def transform_items(rows: list[dict], path: Path | None, source: Path, manifest: dict) -> list[dict]:
    if not path:
        return []
    meta = provenance(path, source, manifest)
    result = []
    for row in rows:
        result.append({
            "itemId": scalar(field(row, "Idx", "Id")), "name": field(row, "Name"),
            "stdMode": scalar(field(row, "StdMode")), "shape": scalar(field(row, "Shape")),
            "weight": scalar(field(row, "Weight")), "durability": scalar(field(row, "DuraMax")),
            "defenseMin": scalar(field(row, "AC")), "defenseMax": scalar(field(row, "AC2")),
            "mdefMin": scalar(field(row, "MAC")), "mdefMax": scalar(field(row, "MAC2")),
            "attackMin": scalar(field(row, "DC")), "attackMax": scalar(field(row, "DC2")),
            "magicMin": scalar(field(row, "MC")), "magicMax": scalar(field(row, "MC2")),
            "taoMin": scalar(field(row, "SC")), "taoMax": scalar(field(row, "SC2")),
            "requirementType": scalar(field(row, "Need")), "reqLevel": scalar(field(row, "NeedLevel")),
            "price": scalar(field(row, "Price")), **meta,
        })
    return [row for row in result if row.get("name")]


def transform_magic(rows: list[dict], path: Path | None, source: Path, manifest: dict) -> list[dict]:
    if not path:
        return []
    meta = provenance(path, source, manifest)
    jobs = {0: "战士", 1: "法师", 2: "道士"}
    result = []
    for row in rows:
        name, job = field(row, "MagName", "Name"), scalar(field(row, "Job"), -1)
        for level in range(4):
            result.append({
                "magicId": scalar(field(row, "MagId", "Id")), "skillName": name,
                "profession": jobs.get(job, "通用"), "skillLevel": level,
                "requiredCharacterLevel": scalar(field(row, f"NeedL{level}"), 0) if level else scalar(field(row, "NeedL1"), 0),
                "trainingPoints": scalar(field(row, f"L{level}Train"), 0) if level else 0,
                "delay": scalar(field(row, "Delay"), 0), "power": scalar(field(row, "Power"), 0),
                "maxPower": scalar(field(row, "MaxPower"), 0), **meta,
            })
    return [row for row in result if row.get("skillName")]


def merge_key(table: str, row: dict) -> str:
    if table == "skills":
        return f"{normalized_name(row.get('skillName'))}:{row.get('skillLevel', 0)}"
    if table == "drops":
        return f"{normalized_name(row.get('bossName'))}:{row.get('duplicateSlot', 0)}"
    return normalized_name(row.get("name"))


def compare(project: dict, imported: dict) -> dict:
    summary: dict[str, Any] = {}
    for table in TABLES:
        existing = project.get(table, [])
        incoming = imported.get(table, [])
        existing_by_key = {merge_key(table, row): row for row in existing if merge_key(table, row)}
        matched, added, conflicts = 0, 0, 0
        examples = []
        for row in incoming:
            key = merge_key(table, row)
            old = existing_by_key.get(key)
            if old is None:
                added += 1
                continue
            matched += 1
            changed = [k for k, value in row.items() if k not in {"sourceDate", "verification", "recordStatus"} and value is not None and old.get(k) not in (None, value)]
            if changed:
                conflicts += 1
                if len(examples) < 8:
                    examples.append({"key": key, "fields": changed})
        summary[table] = {
            "projectRows": len(existing), "importRows": len(incoming), "matched": matched,
            "newCandidates": added, "conflicts": conflicts, "conflictExamples": examples,
        }
    return summary


def safe_merge(project: dict, imported: dict) -> dict:
    merged = json.loads(json.dumps(project, ensure_ascii=False))
    for table in TABLES:
        rows = merged.setdefault(table, [])
        by_key = {merge_key(table, row): row for row in rows if merge_key(table, row)}
        for incoming in imported.get(table, []):
            key = merge_key(table, incoming)
            if not key:
                continue
            if key not in by_key:
                rows.append(incoming)
                by_key[key] = incoming
                continue
            target = by_key[key]
            for field_name, value in incoming.items():
                if value is not None and field_name not in {"sourceUrl", "secondarySourceUrl"}:
                    target[field_name] = value
    return merged


def load_manifest(source: Path) -> dict:
    path = find_ci(source, "import_manifest.json")
    if path:
        manifest = json.loads(read_text(path))
        manifest["_manifestProvided"] = True
        return manifest
    return {"defaultVersionTag": UNKNOWN_VERSION, "files": {}, "_manifestProvided": False}


def detect_data_root(source: Path) -> tuple[Path, list[dict[str, Any]]]:
    """Find a traditional Envir/DB root without treating test/build folders as data."""
    source = source.resolve()
    candidates = [
        source,
        source / "Mir200",
        source / "MirServer" / "Mir200",
        source / "Server" / "Mir200",
    ]
    for child in source.iterdir() if source.is_dir() else []:
        if child.is_dir() and child.name.casefold() in {"mir200", "mirserver", "server"}:
            candidates.extend([child, child / "Mir200"])
    unique: list[Path] = []
    for candidate in candidates:
        resolved = candidate.resolve()
        if resolved not in unique and resolved.is_dir():
            unique.append(resolved)
    inventory: list[dict[str, Any]] = []
    for candidate in unique:
        signals = {
            "mapInfo": bool(find_ci(candidate, "Envir/MapInfo.txt")),
            "monGen": bool(find_ci(candidate, "Envir/MonGen.txt")),
            "monItems": bool(find_ci(candidate, "Envir/MonItems")),
            "merchant": bool(find_ci(candidate, "Envir/Merchant.txt")),
            "marketDef": bool(find_ci(candidate, "Envir/Market_Def")),
            "monsterTable": any(find_ci(candidate, name) for name in ("Monster.csv", "Monster.json", "Monster.DB", "DB/Monster.csv", "DB/Monster.DB")),
            "itemTable": any(find_ci(candidate, name) for name in ("StdItems.csv", "StdItems.json", "StdItems.DB", "DB/StdItems.csv", "DB/StdItems.DB")),
            "magicTable": any(find_ci(candidate, name) for name in ("Magic.csv", "Magic.json", "Magic.DB", "DB/Magic.csv", "DB/Magic.DB")),
        }
        inventory.append({
            "path": candidate.relative_to(source).as_posix() if candidate != source else ".",
            "score": sum(signals.values()),
            "signals": signals,
        })
    inventory.sort(key=lambda row: (-int(row["score"]), str(row["path"])))
    selected = source if not inventory else source / inventory[0]["path"]
    return selected.resolve(), inventory


def run_import(source: Path, apply: bool = False) -> dict:
    source = source.resolve()
    manifest = load_manifest(source)
    if apply and not manifest.get("_manifestProvided", False):
        raise ValueError("缺少 import_manifest.json：版本未确认，拒绝覆盖运行数据库")
    data_root, discovery = detect_data_root(source)
    missing: list[str] = []
    errors: dict[str, str] = {}
    imported = {table: [] for table in TABLES}
    map_path = find_ci(data_root, "Envir/MapInfo.txt")
    mon_gen_path = find_ci(data_root, "Envir/MonGen.txt")
    mon_items_path = find_ci(data_root, "Envir/MonItems")
    merchant_path = find_ci(data_root, "Envir/Merchant.txt")
    scripts_path = find_ci(data_root, "Envir/Market_Def")
    portals, spawns = [], []
    merchants = []
    if map_path:
        imported["maps"], portals = parse_map_info(map_path, source, manifest)
    else:
        missing.append("Envir/MapInfo.txt")
    if mon_gen_path:
        spawns = parse_mon_gen(mon_gen_path, source, manifest)
    else:
        missing.append("Envir/MonGen.txt")
    if mon_items_path and mon_items_path.is_dir():
        imported["drops"] = parse_mon_items(mon_items_path, source, manifest)
    else:
        missing.append("Envir/MonItems/*.txt")
    if merchant_path:
        merchants = parse_merchants(merchant_path, source, manifest)
    else:
        missing.append("Envir/Merchant.txt")
    if scripts_path and scripts_path.is_dir():
        imported["tasks"] = parse_task_scripts(scripts_path, source, manifest)
    else:
        missing.append("Envir/Market_Def/*.txt")
    monster_rows, monster_path, monster_error = read_table(data_root, "Monster")
    item_rows, item_path, item_error = read_table(data_root, "StdItems")
    magic_rows, magic_path, magic_error = read_table(data_root, "Magic")
    for name, path, error in (("Monster.DB/CSV/JSON", monster_path, monster_error), ("StdItems.DB/CSV/JSON", item_path, item_error), ("Magic.DB/CSV/JSON", magic_path, magic_error)):
        if path is None:
            missing.append(name)
        elif error:
            errors[path.relative_to(source).as_posix()] = error
    all_monsters = transform_monsters(monster_rows, monster_path, source, manifest)
    project = json.loads(PROJECT_DATA.read_text(encoding="utf-8"))
    boss_names = {normalized_name(row.get("name")) for row in project.get("bosses", [])}
    imported["bosses"] = [row for row in all_monsters if normalized_name(row.get("name")) in boss_names]
    imported["monsters"] = [row for row in all_monsters if normalized_name(row.get("name")) not in boss_names]
    imported["items"] = transform_items(item_rows, item_path, source, manifest)
    imported["skills"] = transform_magic(magic_rows, magic_path, source, manifest)
    imported["serverPortals"] = portals
    imported["serverSpawns"] = spawns
    imported["serverMerchants"] = merchants
    diff = compare(project, imported)
    report = {
        "generatedAt": datetime.now(timezone.utc).isoformat(), "sourceRoot": str(source),
        "detectedDataRoot": data_root.relative_to(source).as_posix() if data_root != source else ".",
        "sourceDiscovery": discovery,
        "manifestProvided": bool(manifest.get("_manifestProvided", False)),
        "mode": "applied" if apply else "dry-run", "missing": missing, "errors": errors,
        "parsed": {**{table: len(imported[table]) for table in TABLES}, "serverPortals": len(portals), "serverSpawns": len(spawns), "serverMerchants": len(merchants)},
        "diff": diff,
        "mergePolicy": {
            "identity": "地图/怪物/装备按规范化名称；技能按名称+技能等级；掉落按怪物名+槽位",
            "precedence": "服务端非空字段优先；现有网络来源 URL 保留；新增记录追加",
            "safety": "默认 dry-run；仅 --apply 写入运行数据，写入前备份",
        },
    }
    OUTPUT_DATA.write_text(json.dumps(imported, ensure_ascii=False, indent=2), encoding="utf-8")
    OUTPUT_REPORT.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    REPORT_MD.write_text(render_report(report), encoding="utf-8")
    if apply:
        backup = PROJECT_DATA.with_suffix(f".before_server_import_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json")
        shutil.copy2(PROJECT_DATA, backup)
        merged = safe_merge(project, imported)
        PROJECT_DATA.write_text(json.dumps(merged, ensure_ascii=False, indent=2), encoding="utf-8")
        report["backup"] = str(backup)
    return report


def render_report(report: dict) -> str:
    lines = [
        "# MIR2-DATA-3 服务端导入差异报告", "",
        f"- 模式：`{report['mode']}`", f"- 数据源：`{report['sourceRoot']}`",
        f"- 自动识别数据根：`{report['detectedDataRoot']}`", f"- 版本清单：{'已提供' if report['manifestProvided'] else '缺失（禁止正式合并）'}",
        f"- 缺失项：{len(report['missing'])}", f"- 解析错误：{len(report['errors'])}", "",
        "## 解析数量", "", "| 数据表 | 数量 |", "|---|---:|",
    ]
    for table, count in report["parsed"].items():
        lines.append(f"| `{table}` | {count} |")
    lines.extend(["", "## 与当前项目数据的差异", "", "| 表 | 当前 | 导入 | 匹配 | 新候选 | 字段冲突 |", "|---|---:|---:|---:|---:|---:|"])
    for table, info in report["diff"].items():
        lines.append(f"| `{table}` | {info['projectRows']} | {info['importRows']} | {info['matched']} | {info['newCandidates']} | {info['conflicts']} |")
    lines.extend(["", "## 缺口与错误", ""])
    lines.extend([f"- 缺失：`{name}`" for name in report["missing"]] or ["- 无缺失。"])
    lines.extend([f"- `{name}`：{error}" for name, error in report["errors"].items()])
    lines.extend(["", "## 合并规则", ""])
    lines.extend([f"- {key}：{value}" for key, value in report["mergePolicy"].items()])
    lines.extend(["", "> 候选文件不会自动进入运行时。先审阅本报告，确认数据包版本后再使用 `--apply`。", ""])
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser(description="MIR2 Envir/DB 数据导入与差异报告")
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE)
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    report = run_import(args.source, args.apply)
    print("MIR2_SERVER_IMPORT=OK")
    print("MODE=" + report["mode"])
    print("PARSED=" + json.dumps(report["parsed"], ensure_ascii=False, separators=(",", ":")))
    print("MISSING=" + str(len(report["missing"])))
    print("ERRORS=" + str(len(report["errors"])))


if __name__ == "__main__":
    main()
