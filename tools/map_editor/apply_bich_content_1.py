"""Apply the BICH-CONTENT-1 safe/home semantics to editor workspaces."""
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
for map_id,file_name in [("bich_province","bich_province.editor.json"),("sandbox_64","sandbox_64.editor.json")]:
    path=ROOT/f"map_editor_workspace/{map_id}/{file_name}"
    if not path.exists(): continue
    doc=json.loads(path.read_text(encoding="utf-8"))
    offset=8 if map_id=="bich_province" and [int(v) for v in doc["design"]["design_size"]]==[80,80] else 0
    def shifted(point): return [point[0]+offset,point[1]+offset]
    doc["layers"]["safe_area"]=[{
        "semantic_id":"safe_area_000001","kind":"safe_area","area_id":"safe.bich_city",
        "display_name":"比奇城五边形安全区","tile":shifted([32,32]),"return_tile":shifted([25,29]),"radius_tiles":5,
        "shape":"polygon","polygon_tiles":[shifted(p) for p in [[11,32],[15,17],[34,16],[35,42],[24,44]]],
        "npc_hull_tiles":[shifted(p) for p in [[16,31],[18,21],[31,20],[32,38],[24,39]]],
        "expansion_tiles":5,"minimum_monster_clearance_tiles":3,"measured_monster_clearance_tiles":5.14,
        "blocks_pvp":True,"blocks_monster_damage":True,"blocks_monster_entry":True,
        "return_anchor":True,"logout_return_anchor":True,"death_return_anchor":True,
        "content_layer":"personal_expansion","runtime_export":True
    }]
    doc["editor_meta"]["milestone"]="BICH-CONTENT-1"
    doc["editor_meta"]["runtime_approved"]=False
    path.write_text(json.dumps(doc,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print("BICH_SAFE_AREA_APPLIED",path)
