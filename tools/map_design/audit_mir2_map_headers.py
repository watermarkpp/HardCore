#!/usr/bin/env python3
"""Audit only MAP files declared by map_scale_overrides.json."""
from __future__ import annotations
import argparse, json, struct
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OVERRIDES = ROOT / "assets/data/map_design/map_scale_overrides.json"
DEFAULT_OUTPUT = ROOT / "assets/data/map_design/source_map_audit.json"
DEFAULT_REPORT = ROOT / "docs/map_design/原始地图尺寸审计报告.md"

def resolve_source(project_root: Path, value: str) -> Path:
    direct = project_root / value
    if direct.exists(): return direct
    return project_root.parent.parent / value

def inspect(path: Path) -> dict:
    data = path.read_bytes()
    if len(data) < 4: return {"status":"invalid_header", "file_size":len(data)}
    width, height = struct.unpack("<HH", data[:4])
    size = len(data)
    estimates = {"old_12": 52 + width * height * 12, "new_14": 52 + width * height * 14}
    fmt = next((k for k,v in estimates.items() if v == size), "unknown")
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
