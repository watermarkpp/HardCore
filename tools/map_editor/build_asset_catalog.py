#!/usr/bin/env python3
"""Build a deterministic MSE asset catalog without importing textures."""
from __future__ import annotations
import hashlib, json, struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "assets/data/map_editor/asset_sources.json"
OUTPUT = ROOT / "assets/data/map_editor/asset_catalog.json"

def png_size(path: Path):
    with path.open("rb") as f:
        header = f.read(24)
    if len(header) >= 24 and header[:8] == b"\x89PNG\r\n\x1a\n":
        return list(struct.unpack(">II", header[16:24]))
    return None

def main() -> int:
    config = json.loads(SOURCE.read_text(encoding="utf-8")); assets=[]; seen=set()
    for raw in config["sources"]:
        row=dict(raw); asset_id=row["asset_id"]
        if asset_id in seen: raise SystemExit(f"duplicate asset_id: {asset_id}")
        seen.add(asset_id); rel=row.get("path")
        if rel:
            path=ROOT/rel
            row["source_status"]="ok" if path.is_file() else "missing"
            row["sha256"]=hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else None
            row["pixel_size"]=png_size(path) if path.is_file() else None
        else:
            row.update({"source_status":"builtin","sha256":"builtin:v1","pixel_size":None})
        row["editable_layer"]="presentation"
        assets.append(row)
    payload={"schema_version":1,"build_policy":"deterministic_source_registry","assets":sorted(assets,key=lambda x:x["asset_id"])}
    OUTPUT.write_text(json.dumps(payload,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print(f"assets={len(assets)} palette={sum(bool(a['palette_enabled']) for a in assets)} missing={sum(a['source_status']=='missing' for a in assets)}")
    return 0
if __name__ == "__main__": raise SystemExit(main())
