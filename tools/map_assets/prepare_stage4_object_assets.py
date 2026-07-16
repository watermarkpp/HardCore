#!/usr/bin/env python3
"""Prepare a small, explicitly declared Stage-4 object palette from local keyed PNGs."""
from __future__ import annotations
import hashlib, json, shutil
from pathlib import Path
import cv2
import numpy as np

ROOT=Path(__file__).resolve().parents[2]
SOURCE=Path.home()/"Desktop"/"sucai"/"green_screen_assets_split_only"
RAW=ROOT/"assets/raw_import/map_assets/object_sources"
ART=ROOT/"assets/art/maps/_shared"
OUT=ROOT/"assets/data/assets/map_object_asset_catalog.json"
SAMPLES=[
    {"id":"prop.campfire_stone_01","name":"石环篝火","source":"01_camp_props/01_camp_props_01_r01_c01.png","bucket":"props","target_width":128,"footprint":[2,2],"category":"campfire","type":"large_prop","role":"decoration","collision":"none","navigation":"ignore","occlusion":False},
    {"id":"prop.storage_chest_01","name":"木制宝箱","source":"03_storage_props/03_storage_props_01_r01_c01.png","bucket":"props","target_width":64,"footprint":[1,1],"category":"chest","type":"small_prop","role":"interactable","collision":"preset","navigation":"block_player_and_monster","occlusion":False},
    {"id":"building.gothic_tent_01","name":"哥特营帐","source":"02_tents/02_tents_01_r01_c01.png","bucket":"buildings","target_width":160,"footprint":[3,2],"category":"tent","type":"building","role":"building","collision":"solid_footprint","navigation":"block_player_and_monster","occlusion":True},
    {"id":"building.blacksmith_forge_01","name":"铁匠炉","source":"04_blacksmith_props/04_blacksmith_props_01_r01_c01.png","bucket":"buildings","target_width":160,"footprint":[3,2],"category":"forge","type":"building","role":"building","collision":"solid_footprint","navigation":"block_player_and_monster","occlusion":True}
]

def sha(p:Path): return hashlib.sha256(p.read_bytes()).hexdigest()
def remove_keyed_green(image:np.ndarray)->np.ndarray:
    bgr=image[:,:,:3].astype(np.float32); hsv=cv2.cvtColor(bgr.astype(np.uint8),cv2.COLOR_BGR2HSV)
    # Key background: saturated green; retain natural dark/low-saturation details.
    key=(hsv[:,:,0]>=35)&(hsv[:,:,0]<=90)&(hsv[:,:,1]>=80)&(hsv[:,:,2]>=45)&(hsv[:,:,1].astype(np.int16)>hsv[:,:,2].astype(np.int16)*0.42)
    alpha=np.where(key,0,255).astype(np.uint8)
    alpha=cv2.GaussianBlur(alpha,(3,3),0)
    result=np.dstack([image[:,:,:3],alpha])
    # Remove green spill where alpha becomes translucent.
    spill=(alpha<250)&(result[:,:,1]>result[:,:,0]*1.15)&(result[:,:,1]>result[:,:,2]*1.15)
    result[:,:,1][spill]=np.maximum(result[:,:,0][spill],result[:,:,2][spill])
    return result
def crop_and_resize(rgba:np.ndarray,width:int)->np.ndarray:
    ys,xs=np.where(rgba[:,:,3]>12)
    if len(xs)==0: raise ValueError("green key removed all foreground")
    pad=3; x0=max(0,xs.min()-pad); x1=min(rgba.shape[1],xs.max()+pad+1); y0=max(0,ys.min()-pad); y1=min(rgba.shape[0],ys.max()+pad+1)
    crop=rgba[y0:y1,x0:x1]; height=max(1,round(crop.shape[0]*width/crop.shape[1]))
    return cv2.resize(crop,(width,height),interpolation=cv2.INTER_AREA)
def main():
    assets=[]; problems=[]
    for spec in SAMPLES:
        src=SOURCE/spec["source"]
        raw=RAW/spec["source"]; raw.parent.mkdir(parents=True,exist_ok=True); shutil.copy2(src,raw)
        try:
            image=cv2.imread(str(src),cv2.IMREAD_UNCHANGED)
            if image is None: raise ValueError("image load failed")
            if image.shape[2]==3: image=cv2.cvtColor(image,cv2.COLOR_BGR2BGRA)
            processed=crop_and_resize(remove_keyed_green(image),spec["target_width"])
            name=spec["id"].replace(".","_")+".png"; target=ART/spec["bucket"]/name; target.parent.mkdir(parents=True,exist_ok=True)
            if not cv2.imwrite(str(target),processed): raise ValueError("output write failed")
            h,w=processed.shape[:2]; alpha=processed[:,:,3]; ys,xs=np.where(alpha>12)
            image_path=target.relative_to(ROOT).as_posix(); source_hash=sha(src); output_hash=sha(target)
            assets.append({
                "asset_id":spec["id"],"display_name":spec["name"],"asset_type":spec["type"],"category":spec["category"],"theme":"ancient_gothic",
                "image":image_path,"thumbnail":image_path,"canvas_size":[w,h],"image_size":[w,h],"visible_bounds_px":[int(xs.min()),int(ys.min()),int(xs.max()-xs.min()+1),int(ys.max()-ys.min()+1)],
                "anchor_px":[w//2,int(ys.max())],"anchor_tile":[0,0],"anchor_mode":"foot_tile","footprint_tiles":spec["footprint"],"tile_size":[64,32],
                "default_layer":"object_base","default_object_role":spec["role"],"collision_policy":spec["collision"],"navigation_policy":spec["navigation"],"occlusion":spec["occlusion"],
                "content_layer":"personal_expansion","placeable":True,"calibration_status":"placeable","tags":[spec["category"],"gothic","stage4"],
                "source_sha256":source_hash,"output_sha256":output_hash,"thumbnail_source_sha256":output_hash,"raw_import_path":raw.relative_to(ROOT).as_posix(),"processing":"green_key_remove_crop_proportional_resize"
            })
        except Exception as exc: problems.append({"asset_id":spec["id"],"problem":str(exc)})
    OUT.parent.mkdir(parents=True,exist_ok=True); OUT.write_text(json.dumps({"asset_schema_version":2,"assets":assets,"problems":problems},ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print(f"objects={len(assets)} problems={len(problems)}")
    return 1 if problems else 0
if __name__=="__main__": raise SystemExit(main())
