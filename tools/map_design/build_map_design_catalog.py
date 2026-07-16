#!/usr/bin/env python3
"""Deterministically merge templates, overrides and source audit."""
from __future__ import annotations
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
DATA=ROOT/"assets/data/map_design"
def read(name): return json.loads((DATA/name).read_text(encoding="utf-8"))
def main():
    templates=read("map_size_templates.json"); overrides=read("map_scale_overrides.json")
    audit_path=DATA/"source_map_audit.json"; audit=read("source_map_audit.json") if audit_path.exists() else {"records":[]}
    by_type={r["id"]:r for r in templates["templates"]}; by_map={r["map_id"]:r for r in audit["records"]}
    maps=[]
    for raw in overrides["overrides"]:
        row=dict(raw); template=by_type[row["map_type"]]; source=by_map.get(row["map_id"],{"status":"not_audited"})
        row.update({"template_default_size":template["default_size"],"template_max_size":template["max_size"],
                    "coordinate_systems":templates["coordinate_system"],"source_size":[source.get("width"),source.get("height")],
                    "source_audit_status":source.get("status","not_audited"),"source_size_is_design_size":False,
                    "editable_layer":"expansion"})
        maps.append(row)
    payload={"schema_version":1,"policy":"single_player_compact_design","maps":maps}
    (DATA/"map_design_catalog.json").write_text(json.dumps(payload,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print(f"catalog_maps={len(maps)}")
if __name__=="__main__": main()
