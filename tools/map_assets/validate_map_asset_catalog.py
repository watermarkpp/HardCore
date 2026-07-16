#!/usr/bin/env python3
from __future__ import annotations
import hashlib, json, sys
from pathlib import Path
from PIL import Image
import numpy as np

ROOT=Path(__file__).resolve().parents[2]
DATA=ROOT/"assets/data/assets"
CATALOG=DATA/"map_asset_catalog.json"
REQUIRED={"asset_id","display_name","asset_type","category","theme","image","anchor_px","anchor_tile","anchor_mode",
          "footprint_tiles","tile_size","collision_policy","navigation_policy","content_layer","placeable","tags",
          "source_sha256","output_sha256","calibration_status"}

def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def inner_mask():
    yy,xx=np.mgrid[0:32,0:64]
    return (np.abs((xx+0.5)-32)/32 + np.abs((yy+0.5)-16)/16) <= 0.94

def main():
    payload=json.loads(CATALOG.read_text(encoding="utf-8")); errors=[]; warnings=[]; seen=set(); assets=payload.get("assets",[])
    for asset in assets:
        aid=asset.get("asset_id",""); missing=REQUIRED-set(asset)
        if not aid or aid in seen: errors.append(f"duplicate/missing asset_id:{aid}")
        seen.add(aid)
        if missing: errors.append(f"{aid}:missing {sorted(missing)}")
        if asset.get("placeable") and asset.get("calibration_status")!="placeable": errors.append(f"{aid}:uncalibrated placeable")
        if asset.get("content_layer")=="vanilla": errors.append(f"{aid}:new asset cannot write vanilla")
        fp=asset.get("footprint_tiles",[])
        if len(fp)!=2 or min(fp)<=0: errors.append(f"{aid}:invalid footprint")
        image=asset.get("image")
        if image is not None:
            path=ROOT/image
            if not path.is_file(): errors.append(f"{aid}:image missing"); continue
            if sha(path)!=asset.get("output_sha256"): errors.append(f"{aid}:output hash mismatch")
        if asset.get("asset_type")!="ground_brush": continue
        if asset.get("ground_brush_role")=="base_tile" and max(fp)>4: errors.append(f"{aid}:base tile above 4x4")
        if image is None: continue
        im=Image.open(path).convert("RGBA")
        if fp==[1,1] and im.size!=(64,32): errors.append(f"{aid}:1x1 base tile is not 64x32")
        alpha=np.array(im)[:,:,3]
        coverage=float(np.count_nonzero(alpha[inner_mask()]>=250)/np.count_nonzero(inner_mask()))
        if coverage<0.995: errors.append(f"{aid}:inner diamond coverage {coverage:.4f}")
        recorded=float(asset.get("diamond_inner_coverage",0))
        if recorded<0.995: errors.append(f"{aid}:recorded coverage {recorded:.4f}")
        if asset.get("thumbnail_source_sha256") not in (None,asset.get("output_sha256")): errors.append(f"{aid}:thumbnail mismatch")
    report=json.loads((DATA/"map_asset_import_report.json").read_text(encoding="utf-8"))
    if report.get("source_count")!=153 or report.get("normalized_count")!=153 or report.get("rejected_count")!=0:
        errors.append("ground normalization acceptance count mismatch")
    print(f"assets={len(assets)} errors={len(errors)} warnings={len(warnings)}")
    for e in errors: print("ERROR",e)
    for w in warnings: print("WARN",w)
    return 1 if errors else 0
if __name__=="__main__": raise SystemExit(main())
