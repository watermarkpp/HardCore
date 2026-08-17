#!/usr/bin/env python3
"""Audit only MAP files declared by map_scale_overrides.json."""
from __future__ import annotations
import argparse, json, struct
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OVERRIDES = ROOT / "assets/data/map_design/map_scale_overrides.json"
DEFAULT_OUTPUT = ROOT / "assets/data/map_design/source_map_audit.json"
DEFAULT_REPORT = ROOT / "docs/map_design/Original_Map_Size_Audit_Report.md"

def resolve_source(project_root: Path, value: str) -> Path:
    normalized = value.replace("\\", "/")
    if normalized.startswith("res://"):
        direct = project_root / normalized.removeprefix("res://")
        if direct.exists(): return direct
    direct = project_root / normalized
    if direct.exists(): return direct
    legacy_client_prefix = "research/mir2_client_raw/"
    if normalized.startswith(legacy_client_prefix):
        primary_client = (
            project_root / "dev_art_sources/reference/mir2_client_raw"
            / normalized.removeprefix(legacy_client_prefix)
        )
        if primary_client.exists(): return primary_client
    return project_root.parent.parent / normalized

def inspect(path: Path) -> dict:
    data = path.read_bytes()
    if len(data) < 4: return {"status":"invalid_header", "file_size":len(data)}
    size = len(data)
    if (len(data) >= 27 and data[0] == 0x10 and data[2] == 0x61
            and data[7] == 0x31 and data[14] == 0x31):
        width_raw, xor_key, height_raw = struct.unpack_from("<hhh", data, 21)
        width, height = width_raw ^ xor_key, height_raw ^ xor_key
        estimates = {"wemade_2010_15": 54 + width * height * 15}
    else:
        width, height = struct.unpack("<HH", data[:4])
        estimates = {"old_12": 52 + width * height * 12, "new_14": 52 + width * height * 14}
    fmt = next((k for k,v in estimates.items() if v == size), "unknown")
    if width <= 0 or height <= 0 or fmt == "unknown":
        return {
            "status":"invalid_header", "width":width, "height":height,
            "file_size":size, "estimated_format":fmt,
            "expected_file_sizes":estimates,
        }
    return {"status":"ok", "width":width, "height":height, "file_size":size,
            "estimated_format":fmt, "expected_file_sizes":estimates}

def main() -> int:
    p=argparse.ArgumentParser(); p.add_argument("--overrides",type=Path,default=DEFAULT_OVERRIDES)
    p.add_argument("--output",type=Path,default=DEFAULT_OUTPUT); p.add_argument("--report",type=Path,default=DEFAULT_REPORT)
    a=p.parse_args(); source=json.loads(a.overrides.read_text(encoding="utf-8"))
    records=[]
    for row in source["overrides"]:
        rel=row.get("source_map_path")
        base={"map_id":row["map_id"],"runtime_map_id":row["runtime_map_id"],"name":row["name"],"source_map_path":rel}
        if not rel: base.update({"status":"unresolved"})
        elif row.get("source_kind") == "workspace_clone":
            source_size = row.get("source_size", [None, None])
            base.update({
                "status":"workspace_clone",
                "width":source_size[0],
                "height":source_size[1],
                "estimated_format":"editor_workspace_json",
            })
        else:
            path=resolve_source(ROOT,rel)
            base.update(inspect(path) if path.exists() else {"status":"missing"})
        records.append(base)
    payload={"schema_version":1,"generated_at":datetime.now(timezone.utc).isoformat(),"records":records}
    a.output.parent.mkdir(parents=True,exist_ok=True); a.output.write_text(json.dumps(payload,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    lines=["# 原始地图尺寸审计报告","","原始尺寸仅用于审计，不等于单机 `design_size`。","", "| 地图 | 运行ID | 源文件 | 原尺寸 | 状态 |","|---|---:|---|---:|---|"]
    for r in records:
        size=f'{r.get("width","-")}×{r.get("height","-")}'
        lines.append(f'| {r["name"]} | {r["runtime_map_id"]} | {r.get("source_map_path") or "待确认"} | {size} | {r["status"]} |')
    a.report.parent.mkdir(parents=True,exist_ok=True); a.report.write_text("\n".join(lines)+"\n",encoding="utf-8")
    print(f"audited={len(records)} ok={sum(r['status']=='ok' for r in records)} unresolved={sum(r['status']=='unresolved' for r in records)}")
    return 0
if __name__=="__main__": raise SystemExit(main())
