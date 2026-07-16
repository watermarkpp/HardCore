#!/usr/bin/env python3
"""Prepare explicitly declared terrain-stamp assets from local keyed source PNGs."""
from __future__ import annotations
import hashlib, json, shutil
from pathlib import Path
import cv2
import numpy as np

ROOT=Path(__file__).resolve().parents[2]; SOURCE=Path.home()/"Desktop"/"sucai"/"green_screen_assets_split_only"
RAW=ROOT/"assets/raw_import/map_assets/terrain_sources"; ART=ROOT/"assets/art/maps/_shared/terrain_stamps"; OUT=ROOT/"assets/data/assets/map_terrain_asset_catalog.json"
SAMPLES=[
 {"id":"terrain.mud_decal_01","name":"碎石泥地印章 01","source":"09_ground_decals/09_ground_decals_01_r01_c01.png","width":128,"footprint":[2,2],"terrain":"mud","collision":"none","navigation":"ignore"},
 {"id":"terrain.mud_decal_02","name":"碎石泥地印章 02","source":"09_ground_decals/09_ground_decals_02_r01_c02.png","width":128,"footprint":[2,2],"terrain":"mud","collision":"none","navigation":"ignore"},
 {"id":"terrain.palisade_wall_01","name":"尖桩木栅栏地貌","source":"07_fence_signs/07_fence_signs_01_r01_c01.png","width":192,"footprint":[3,1],"terrain":"palisade","collision":"terrain_stamp_generated","navigation":"block_player_and_monster"}
]
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def key_green(img):
 hsv=cv2.cvtColor(img[:,:,:3],cv2.COLOR_BGR2HSV); key=(hsv[:,:,0]>=35)&(hsv[:,:,0]<=90)&(hsv[:,:,1]>=80)&(hsv[:,:,2]>=45)
 alpha=np.where(key,0,255).astype(np.uint8); alpha=cv2.GaussianBlur(alpha,(3,3),0); return np.dstack([img[:,:,:3],alpha])
def crop_resize(img,width):
 ys,xs=np.where(img[:,:,3]>12)
 if len(xs)==0: raise ValueError("no foreground after key removal")
 pad=3; crop=img[max(0,ys.min()-pad):min(img.shape[0],ys.max()+pad+1),max(0,xs.min()-pad):min(img.shape[1],xs.max()+pad+1)]
 return cv2.resize(crop,(width,max(1,round(crop.shape[0]*width/crop.shape[1]))),interpolation=cv2.INTER_AREA)
def main():
 assets=[]; problems=[]
 for spec in SAMPLES:
  src=SOURCE/spec["source"]; raw=RAW/spec["source"]; raw.parent.mkdir(parents=True,exist_ok=True); shutil.copy2(src,raw)
  try:
   img=cv2.imread(str(src),cv2.IMREAD_UNCHANGED)
   if img is None: raise ValueError("load failed")
   if img.shape[2]==3: img=cv2.cvtColor(img,cv2.COLOR_BGR2BGRA)
   output_img=crop_resize(key_green(img),spec["width"]); name=spec["id"].replace(".","_")+".png"; target=ART/name; target.parent.mkdir(parents=True,exist_ok=True)
   if not cv2.imwrite(str(target),output_img): raise ValueError("write failed")
   h,w=output_img.shape[:2]; ys,xs=np.where(output_img[:,:,3]>12); image=target.relative_to(ROOT).as_posix(); source_hash=sha(src); output_hash=sha(target)
   assets.append({"asset_id":spec["id"],"display_name":spec["name"],"asset_type":"terrain_stamp","category":"terrain","theme":"ancient_gothic","image":image,"thumbnail":image,"canvas_size":[w,h],"image_size":[w,h],"visible_bounds_px":[int(xs.min()),int(ys.min()),int(xs.max()-xs.min()+1),int(ys.max()-ys.min()+1)],"anchor_px":[w//2,int(ys.max())],"anchor_tile":[0,0],"anchor_mode":"foot_tile","footprint_tiles":spec["footprint"],"tile_size":[64,32],"terrain_type":spec["terrain"],"default_layer":"terrain_base","default_object_role":"terrain","collision_policy":spec["collision"],"navigation_policy":spec["navigation"],"occlusion":spec["collision"]!="none","content_layer":"personal_expansion","placeable":True,"calibration_status":"placeable","tags":["terrain",spec["terrain"],"stage5"],"source_sha256":source_hash,"output_sha256":output_hash,"thumbnail_source_sha256":output_hash,"raw_import_path":raw.relative_to(ROOT).as_posix(),"processing":"green_key_remove_crop_proportional_resize"})
  except Exception as exc: problems.append({"asset_id":spec["id"],"problem":str(exc)})
 OUT.parent.mkdir(parents=True,exist_ok=True); OUT.write_text(json.dumps({"asset_schema_version":2,"assets":assets,"problems":problems},ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
 print(f"terrain={len(assets)} problems={len(problems)}"); return 1 if problems else 0
if __name__=="__main__": raise SystemExit(main())
