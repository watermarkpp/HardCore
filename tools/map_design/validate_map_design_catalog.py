#!/usr/bin/env python3
from __future__ import annotations
import json, sys
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]; DATA=ROOT/"assets/data/map_design"
ALLOWED={"remake_compact","shrink_and_recompose","preserve_function","preserve_route","reduce_duplicates","preserve_arena"}
def main():
    catalog=json.loads((DATA/"map_design_catalog.json").read_text(encoding="utf-8")); errors=[]; warnings=[]
    maps=catalog.get("maps",[]); seen=set()
    for m in maps:
        mid=m.get("map_id"); size=m.get("design_size",[]); maxs=m.get("template_max_size",[])
        if not mid or mid in seen: errors.append(f"duplicate/missing map_id: {mid}")
        seen.add(mid)
        for key in ("runtime_map_id","name","map_type","source_map_path","strategy","coordinate_systems"):
            if key not in m: errors.append(f"{mid}: missing {key}")
        if len(size)!=2 or min(size)<=0: errors.append(f"{mid}: invalid design_size")
        elif len(maxs)==2 and (size[0]>maxs[0] or size[1]>maxs[1]): errors.append(f"{mid}: exceeds template max")
        if m.get("strategy") not in ALLOWED: errors.append(f"{mid}: invalid strategy")
        if m.get("map_type")=="boss_room" and min(size)<64: errors.append(f"{mid}: boss room below 64")
        if m.get("map_type")=="shop_interior" and max(size)>40: warnings.append(f"{mid}: shop above 40")
        if m.get("map_type")=="outdoor_province" and max(size)>320: errors.append(f"{mid}: province above 320")
        if m.get("map_type")=="maze_room" and max(size)>80: warnings.append(f"{mid}: maze above 80")
        if m.get("source_size_is_design_size") is not False: errors.append(f"{mid}: source/design separation missing")
        if m.get("source_audit_status") in ("unresolved","missing"): warnings.append(f"{mid}: source {m['source_audit_status']}")
    expected={"bich_province":[64,64],"mengzhong_province":[280,280],"corpse_king_hall":[96,96],"stone_tomb_array":[56,56]}
    lookup={m["map_id"]:m for m in maps}
    for mid,size in expected.items():
        if lookup.get(mid,{}).get("design_size")!=size: errors.append(f"acceptance: {mid} != {size}")
    if lookup.get("corpse_king_hall",{}).get("map_type")!="boss_room": errors.append("acceptance: corpse king type")
    if lookup.get("stone_tomb_array",{}).get("strategy")!="reduce_duplicates": errors.append("acceptance: stone tomb strategy")
    if lookup.get("bich_province",{}).get("size_status")!="user_confirmed_final": errors.append("acceptance: bich final size status")
    print(f"maps={len(maps)} errors={len(errors)} warnings={len(warnings)}")
    for x in errors: print("ERROR",x)
    for x in warnings: print("WARN",x)
    return 1 if errors else 0
if __name__=="__main__": raise SystemExit(main())
