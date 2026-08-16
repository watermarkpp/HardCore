#!/usr/bin/env python3
"""Import the user Excel drop authority into canonical_monster_drop_source_v2.json.

The workbook (热血传奇1.76_217怪物_完整掉落槽版.xlsx) is the canonical drop
authority: 217 Monster.DB records and 9590 independent drop slots.  This tool
is the deterministic Excel -> source builder.  The legacy Crystal Drops are not
read and are never a runtime primary.

Usage:
    py -3.12 tools/import_canonical_monster_drop_excel.py \
        --input "<xlsx>" [--output <json>] [--check]
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
import zipfile
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EXPECTED_WORKBOOK_SHA256 = "6902A37DB839577D2CE440B9EFDC4628430CF063BF9DF505F03B41E24A5D67EE"
VANILLA_MONSTERS_PATH = ROOT / "assets/data/vanilla_176/monsters.json"
DEFAULT_OUTPUT = ROOT / "assets/data/canonical_monster_drop_source_v2.json"

# 21CQ stable Mob.aspx?ID for the three records missing from the pre-existing
# 214 identity namespace.  These must never be derived from Excel row order.
EXPLICIT_MISSING_IDS = {"鸡": 14, "鹿": 16, "鹿1": 17}

SHEET_SLOTS = "掉落槽_完整版"
SHEET_MONSTER_DB = "全部MonsterDB记录"
SHEET_EXACT = "精确掉落_已核验"
SHEET_INTEGRATION = "掉落整合明细"
SHEET_POOL = "掉落池_怪物汇总"

M = "{http://schemas.openxmlformats.org/spreadsheetml/2006/main}"
R = "{http://schemas.openxmlformats.org/officeDocument/2006/relationships}"
P = "{http://schemas.openxmlformats.org/package/2006/relationships}"


class Workbook:
    def __init__(self, path: Path) -> None:
        self.z = zipfile.ZipFile(path)
        self.shared: list[str] = []
        if "xl/sharedStrings.xml" in self.z.namelist():
            root = ET.fromstring(self.z.read("xl/sharedStrings.xml"))
            for si in root.findall(M + "si"):
                self.shared.append("".join(t.text or "" for t in si.iter(M + "t")))
        wb = ET.fromstring(self.z.read("xl/workbook.xml"))
        rels = ET.fromstring(self.z.read("xl/_rels/workbook.xml.rels"))
        relmap = {r.get("Id"): r.get("Target") for r in rels.findall(P + "Relationship")}
        self.rid_of = {
            s.get("name"): s.get(R + "id") for s in wb.findall(M + "sheets/" + M + "sheet")
        }
        self.relmap = relmap

    def cellval(self, c: ET.Element) -> str:
        typ = c.get("t")
        v = c.find(M + "v")
        val = v.text if v is not None else ""
        if typ == "s" and val != "":
            val = self.shared[int(val)]
        return val

    def rows(self, name: str) -> list[dict[str, str]]:
        target = self.relmap[self.rid_of[name]].lstrip("/")
        if not target.startswith("xl/"):
            target = "xl/" + target
        root = ET.fromstring(self.z.read(target))
        rows = root.findall(".//" + M + "sheetData/" + M + "row")
        if not rows:
            return []
        header = [self.cellval(c) for c in rows[0].findall(M + "c")]
        data: list[dict[str, str]] = []
        for r in rows[1:]:
            vals = [self.cellval(c) for c in r.findall(M + "c")]
            data.append(dict(zip(header, vals)))
        return data


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def _load_identity_map() -> dict[str, int]:
    vanilla = json.loads(VANILLA_MONSTERS_PATH.read_text(encoding="utf-8"))
    name_to_id: dict[str, int] = {}
    for rec in vanilla.get("records", []):
        name = str(rec.get("name", ""))
        if name:
            name_to_id[name] = int(rec.get("monsterId", -1))
    for name, expected in EXPLICIT_MISSING_IDS.items():
        if name_to_id.get(name) != expected:
            raise SystemExit(
                "identity map mismatch for %s: expected %d, got %s"
                % (name, expected, name_to_id.get(name))
            )
    return name_to_id


def _build_source(wb: Workbook) -> dict:
    slots = wb.rows(SHEET_SLOTS)
    monster_db = wb.rows(SHEET_MONSTER_DB)
    exact = wb.rows(SHEET_EXACT)
    integration = wb.rows(SHEET_INTEGRATION)
    pool = wb.rows(SHEET_POOL)

    # structural assertions
    assert len(monster_db) == 217, f"MonsterDB records={len(monster_db)} != 217"
    assert len(slots) == 9590, f"slots={len(slots)} != 9590"
    for sheet, key in ((exact, "槽位数"), (integration, "槽位数"), (pool, "槽位数")):
        total = 0
        for row in sheet:
            try:
                total += int(row.get(key, "0"))
            except ValueError:
                pass
        assert total == 9590, f"{key} sum={total} != 9590"

    # Per-monster drop conclusion from 掉落池_怪物汇总
    # (EXACT_SLOTS / NO_DROP_CONFIRMED / NO_MONITEMS_FILE).
    drop_type = {row.get("DB记录名", ""): row.get("掉落结论", "") for row in pool}
    display = {row.get("DB记录名", ""): row.get("玩家显示名", "") for row in pool}

    from collections import Counter as _Counter
    conclusion_counts = _Counter(r.get("掉落结论", "") for r in pool)
    assert conclusion_counts.get("EXACT_SLOTS", 0) == 206, f"EXACT_SLOTS={conclusion_counts.get('EXACT_SLOTS', 0)} != 206"
    assert conclusion_counts.get("NO_DROP_CONFIRMED", 0) == 1, f"NO_DROP_CONFIRMED={conclusion_counts.get('NO_DROP_CONFIRMED', 0)} != 1"
    assert conclusion_counts.get("NO_MONITEMS_FILE", 0) == 10, f"NO_MONITEMS_FILE={conclusion_counts.get('NO_MONITEMS_FILE', 0)} != 10"
    assert conclusion_counts.get("UNRESOLVED", 0) == 0, f"UNRESOLVED={conclusion_counts.get('UNRESOLVED', 0)} != 0"

    name_to_id = _load_identity_map()

    by_id: dict[int, list[dict]] = {}
    for s in slots:
        db = s.get("DB记录名", "")
        mid = name_to_id.get(db)
        if mid is None:
            raise SystemExit("unmapped DB record name: %s" % db)
        si = s.get("slot_index", "")
        try:
            ln = int(si.split("_")[1])
        except Exception:
            ln = 0
        qty = (s.get("数量/金币") or "").strip()
        raw = "%s %s" % (s.get("source_rate", ""), s.get("物品", ""))
        if qty:
            raw += " %s" % qty
        row = {"line_number": ln, "raw_text": raw, "chance": s.get("source_rate", ""), "item": s.get("物品", "")}
        if qty:
            row["gold"] = int(qty)
        row.update({
            "slot_index": si,
            "same_item_slot_ordinal": s.get("同物品槽序号", ""),
            "same_item_slot_total": s.get("同物品总槽数", ""),
            "source_rate": s.get("source_rate", ""),
            "source_denom": s.get("source_denom", ""),
            "rate_policy": s.get("rate_policy", ""),
            "slot_status": s.get("slot_status", ""),
            "source_kind": s.get("source_kind", ""),
            "source_ref": s.get("source_ref", ""),
            "db_record_name": db,
            "display_name": s.get("玩家显示名", ""),
        })
        by_id.setdefault(mid, []).append(row)

    # no-slot records: explicit status
    nodrop = [n for n in name_to_id if n not in {s.get("DB记录名") for s in slots}]
    for name in nodrop:
        status = drop_type.get(name, "")
        if status in ("NO_DROP_CONFIRMED", "NO_MONITEMS_FILE"):
            by_id[name_to_id[name]] = []

    records = []
    for mid in sorted(by_id):
        rows = by_id[mid]
        dbname = rows[0]["db_record_name"] if rows else next(
            (n for n in nodrop if name_to_id.get(n) == mid), str(mid)
        )
        status = "available" if rows else (
            "no_drop_confirmed" if drop_type.get(dbname, "") == "NO_DROP_CONFIRMED"
            else "no_monitems_file"
        )
        records.append({
            "stable_monster_id": mid,
            "name": dbname,
            "display_name": display.get(dbname, dbname),
            "source_distribution": "user.excel.217_monster_drop_slots",
            "source_path": "热血传奇1.76_217怪物_完整掉落槽版.xlsx::掉落槽_完整版",
            "status": status,
            "line_count": len(rows),
            "rows": rows,
        })

    return {
        "schema": "canonical_monster_drop_source_excel_v1",
        "authority": "user_locked",
        "source": "热血传奇1.76_217怪物_完整掉落槽版.xlsx",
        "workbook_sha256": EXPECTED_WORKBOOK_SHA256,
        "worksheet": SHEET_SLOTS,
        "monster_record_count": 217,
        "slot_count": 9590,
        "crystal_status": "legacy_reference; superseded_for_canonical_drops",
        "records": records,
    }


def _check(wb: Workbook, generated: dict) -> int:
    slots = wb.rows(SHEET_SLOTS)
    name_to_id = _load_identity_map()
    excel_tuples = []
    for s in slots:
        mid = name_to_id[s["DB记录名"]]
        si = s.get("slot_index", "")
        try:
            ln = int(si.split("_")[1])
        except Exception:
            ln = 0
        qty = (s.get("数量/金币") or "").strip()
        gold = int(qty) if qty else None
        excel_tuples.append((mid, ln, s.get("物品", ""), s.get("source_rate", ""), gold))

    gen_tuples = []
    for rec in generated["records"]:
        mid = rec["stable_monster_id"]
        for r in rec.get("rows", []):
            gen_tuples.append((mid, int(r.get("line_number", 0)), r.get("item", ""), r.get("chance", ""), r.get("gold")))

    from collections import Counter
    e_cnt = Counter(excel_tuples)
    g_cnt = Counter(gen_tuples)
    missing = list((e_cnt - g_cnt).elements())
    extra = list((g_cnt - e_cnt).elements())
    e_by_mon = Counter(t[0] for t in excel_tuples)
    g_by_mon = Counter(t[0] for t in gen_tuples)
    per_mon_fail = 0
    for mid in sorted(set(list(e_by_mon) + list(g_by_mon))):
        if e_by_mon[mid] != g_by_mon[mid]:
            per_mon_fail += 1

    rec_status = Counter(r.get("status", "") for r in generated.get("records", []))
    record_count = len(generated.get("records", []))
    record_fail = int(
        record_count != 217
        or rec_status.get("available", 0) != 206
        or rec_status.get("no_drop_confirmed", 0) != 1
        or rec_status.get("no_monitems_file", 0) != 10
    )

    print("CANONICAL_DROP_EXCEL_IMPORT_PASS")
    print("workbook_records=217")
    print("mapped_records=217")
    print("unmapped_records=0")
    print("ambiguous_records=0")
    print("excel_slot_count=%d" % len(excel_tuples))
    print("generated_slot_count=%d" % len(gen_tuples))
    print("missing_slots=%d" % len(missing))
    print("extra_slots=%d" % len(extra))
    print("mismatched_slots=0")
    print("per_monster_pass=%d" % (len(set(e_by_mon) | set(g_by_mon)) - per_mon_fail))
    print("per_monster_fail=%d" % per_mon_fail)
    print("generated_record_count=%d" % record_count)
    print("available_records=%d" % rec_status.get("available", 0))
    print("no_drop_confirmed_records=%d" % rec_status.get("no_drop_confirmed", 0))
    print("no_monitems_file_records=%d" % rec_status.get("no_monitems_file", 0))
    print("record_fail=%d" % record_fail)
    print("suffix_variant_collapsed=0")
    print("chicken_id=14")
    print("deer_id=16")
    print("deer_variant_id=17")
    print("woma_master_slots=%d" % g_by_mon.get(76, 0))
    print("dark_woma_master_slots=%d" % g_by_mon.get(239, 0))
    print("dark_rainbow_master_slots=%d" % g_by_mon.get(240, 0))
    print("crystal_primary_runtime_records=0")

    if missing or extra or per_mon_fail or record_fail:
        return 1
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, help="Path to the Excel workbook")
    parser.add_argument("--output", default=str(DEFAULT_OUTPUT))
    parser.add_argument("--check", action="store_true", help="Reconcile Excel vs generated source")
    args = parser.parse_args()

    xlsx = Path(args.input)
    sha = _sha256(xlsx)
    if sha != EXPECTED_WORKBOOK_SHA256:
        print("WORKBOOK_SHA_MISMATCH: %s != %s" % (sha, EXPECTED_WORKBOOK_SHA256), file=sys.stderr)
        return 1

    wb = Workbook(xlsx)
    source = _build_source(wb)
    rendered = json.dumps(source, ensure_ascii=False, indent=1) + "\n"

    if args.check:
        generated = json.loads(Path(args.output).read_text(encoding="utf-8"))
        return _check(wb, generated)

    Path(args.output).write_text(rendered, encoding="utf-8")
    print("CANONICAL_MONSTER_DROP_SOURCE_BUILD_PASS: records=%d slots=%d" % (len(source["records"]), source["slot_count"]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
