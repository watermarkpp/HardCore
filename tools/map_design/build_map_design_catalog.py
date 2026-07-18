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
    scale_policy=overrides.get("scale_policy", {})
    maps=[]; blank_templates=[]
    for raw in overrides["overrides"]:
        row=dict(raw); template=by_type[row["map_type"]]; source=by_map.get(row["map_id"],{"status":"not_audited"})
        row.update({"template_default_size":template["default_size"],"template_max_size":template["max_size"],
                    "coordinate_systems":templates["coordinate_system"],"source_size":[source.get("width"),source.get("height")],
                    "source_audit_status":source.get("status","not_audited"),"source_size_is_design_size":False,
                    "editable_layer":"expansion","scale_factor":scale_policy.get("factor"),
                    "scale_rounding":scale_policy.get("rounding")})
        maps.append(row)
        blank_template={
            "template_id":f"blank.{row['map_id']}","template_kind":"empty_map","map_id":row["map_id"],
            "runtime_map_id":row["runtime_map_id"],"display_name":row["name"],"map_type":row["map_type"],
            "design_size":row["design_size"],"pre_scale_design_size":row.get("pre_scale_design_size"),
            "strategy":row["strategy"],"content_policy":"empty_layers","ground_policy":"virtual_blank_until_dirty",
            "editable_layer":"expansion",
        }
        for key in ("size_status", "size_decision_source", "clone_source_map_id"):
            if key in row:
                blank_template[key] = row[key]
        if row["map_id"] == "bich_province":
            blank_template.update({
                "template_kind":"existing_map_or_empty_template",
                "display_name":f"{row['name']}（当前地图）",
                "content_policy":"open_existing_workspace_first",
            })
        blank_templates.append(blank_template)
    payload={"schema_version":1,"policy":"single_player_compact_design","scale_policy":scale_policy,"maps":maps}
    (DATA/"map_design_catalog.json").write_text(json.dumps(payload,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    blank_payload={"schema_version":1,"scale_policy":scale_policy,"templates":blank_templates}
    (DATA/"map_blank_templates.json").write_text(json.dumps(blank_payload,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print(f"catalog_maps={len(maps)} blank_templates={len(blank_templates)}")
if __name__=="__main__": main()
