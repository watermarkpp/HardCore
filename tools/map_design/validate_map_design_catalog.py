#!/usr/bin/env python3
from __future__ import annotations
import json, sys
from decimal import Decimal, ROUND_HALF_UP
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]; DATA=ROOT/"assets/data/map_design"
ALLOWED={"remake_compact","shrink_and_recompose","preserve_function","preserve_route","reduce_duplicates","preserve_arena","exact_clone_of_orc_tomb_1","exact_clone_of_wooma_temple_1","exact_clone_of_stone_tomb_1","exact_clone_of_zuma_temple_1"}
def main():
    catalog=json.loads((DATA/"map_design_catalog.json").read_text(encoding="utf-8")); errors=[]; warnings=[]
    blank=json.loads((DATA/"map_blank_templates.json").read_text(encoding="utf-8"))
    maps=catalog.get("maps",[]); blank_templates=blank.get("templates",[]); seen=set()
    factor=Decimal(str(catalog.get("scale_policy",{}).get("factor",0)))
    for m in maps:
        mid=m.get("map_id"); size=m.get("design_size",[]); maxs=m.get("template_max_size",[])
        if not mid or mid in seen: errors.append(f"duplicate/missing map_id: {mid}")
        seen.add(mid)
        for key in ("runtime_map_id","name","map_type","source_map_path","strategy","coordinate_systems"):
            if key not in m: errors.append(f"{mid}: missing {key}")
        if len(size)!=2 or min(size)<=0: errors.append(f"{mid}: invalid design_size")
        elif len(maxs)==2 and (size[0]>maxs[0] or size[1]>maxs[1]): errors.append(f"{mid}: exceeds template max")
        if m.get("strategy") not in ALLOWED: errors.append(f"{mid}: invalid strategy")
        if m.get("map_type")=="boss_room" and min(size)<18: errors.append(f"{mid}: scaled boss room below 18")
        if m.get("map_type")=="shop_interior" and max(size)>40: warnings.append(f"{mid}: shop above 40")
        if m.get("map_type")=="outdoor_province" and max(size)>320: errors.append(f"{mid}: province above 320")
        if m.get("map_type")=="maze_room" and max(size)>80: warnings.append(f"{mid}: maze above 80")
        if m.get("source_size_is_design_size") is not False: errors.append(f"{mid}: source/design separation missing")
        if m.get("source_audit_status") in ("unresolved","missing"): warnings.append(f"{mid}: source {m['source_audit_status']}")
        original=m.get("pre_scale_design_size",[])
        if len(original)!=2: errors.append(f"{mid}: missing pre-scale size")
        else:
            scaled=[int((Decimal(int(value))*factor).quantize(Decimal("1"),rounding=ROUND_HALF_UP)) for value in original]
            size_is_user_confirmed = str(m.get("size_status", "")).startswith("user_confirmed_")
            if not str(m.get("strategy", "")).startswith("exact_clone_of_") and not size_is_user_confirmed and size!=scaled: errors.append(f"{mid}: scale mismatch {size} != {scaled}")
    expected={"bich_province":[80,80],"mengzhong_province":[88,88],"orc_tomb_2":[38,38],"orc_tomb_3":[38,38],"corpse_king_hall":[30,30],"stone_tomb_1":[50,50],"stone_tomb_2":[50,50],"stone_tomb_3":[50,50],"stone_tomb_4":[50,50],"stone_tomb_array":[18,18]}
    lookup={m["map_id"]:m for m in maps}
    for mid,size in expected.items():
        if lookup.get(mid,{}).get("design_size")!=size: errors.append(f"acceptance: {mid} != {size}")
    if lookup.get("corpse_king_hall",{}).get("map_type")!="boss_room": errors.append("acceptance: corpse king type")
    if lookup.get("stone_tomb_1",{}).get("source_audit_status")!="ok": errors.append("acceptance: stone tomb 1 primary source audit")
    if lookup.get("stone_tomb_1",{}).get("source_distribution")!="server.crystal.cjlaaa": errors.append("acceptance: stone tomb 1 source distribution")
    if lookup.get("stone_tomb_array",{}).get("strategy")!="reduce_duplicates": errors.append("acceptance: stone tomb strategy")
    for mid in ("orc_tomb_2", "orc_tomb_3"):
        clone=lookup.get(mid,{})
        if clone.get("clone_source_map_id")!="orc_tomb_1": errors.append(f"acceptance: {mid} clone source")
        if clone.get("size_status")!="user_confirmed_exact_clone": errors.append(f"acceptance: {mid} clone size status")
        if clone.get("design_size")!=lookup.get("orc_tomb_1",{}).get("design_size"): errors.append(f"acceptance: {mid} clone size differs from floor 1")
    for mid in ("stone_tomb_2", "stone_tomb_3", "stone_tomb_4"):
        clone=lookup.get(mid,{})
        if clone.get("clone_source_map_id")!="stone_tomb_1": errors.append(f"acceptance: {mid} clone source")
        if clone.get("size_status")!="user_confirmed_exact_clone": errors.append(f"acceptance: {mid} clone size status")
        if clone.get("source_audit_status")!="workspace_clone": errors.append(f"acceptance: {mid} clone audit status")
        if clone.get("design_size")!=lookup.get("stone_tomb_1",{}).get("design_size"): errors.append(f"acceptance: {mid} clone size differs from floor 1")
    for mid in ("zuma_temple_2", "zuma_temple_3", "zuma_temple_4"):
        clone=lookup.get(mid,{})
        if clone.get("clone_source_map_id")!="zuma_temple_1": errors.append(f"acceptance: {mid} clone source")
        if clone.get("size_status")!="user_confirmed_exact_clone": errors.append(f"acceptance: {mid} clone size status")
        if clone.get("source_audit_status")!="workspace_clone": errors.append(f"acceptance: {mid} clone audit status")
        if clone.get("design_size")!=lookup.get("zuma_temple_1",{}).get("design_size"): errors.append(f"acceptance: {mid} clone size differs from floor 1")
    if lookup.get("bich_province",{}).get("size_status")!="user_confirmed_final": errors.append("acceptance: bich final size status")
    if factor!=Decimal("0.3125"): errors.append("acceptance: global scale factor")
    if len(blank_templates)!=len(maps): errors.append("acceptance: template count")
    blank_ids={str(t.get("template_id","")) for t in blank_templates}
    for mid in seen:
        if f"blank.{mid}" not in blank_ids: errors.append(f"{mid}: template missing")
    bich_template=next((t for t in blank_templates if t.get("template_id")=="blank.bich_province"),{})
    if bich_template.get("template_kind")!="existing_map_or_empty_template": errors.append("acceptance: bich template kind")
    if bich_template.get("content_policy")!="open_existing_workspace_first": errors.append("acceptance: bich open policy")
    print(f"maps={len(maps)} blank_templates={len(blank_templates)} errors={len(errors)} warnings={len(warnings)}")
    for x in errors: print("ERROR",x)
    for x in warnings: print("WARN",x)
    return 1 if errors else 0
if __name__=="__main__": raise SystemExit(main())
