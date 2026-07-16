"""Rebuild keyed V1.5 sheets with ImageMagick and import folder palettes."""
from __future__ import annotations

import hashlib, json, math, shutil, subprocess
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
MAGICK = Path(r"C:\Program Files\ImageMagick-7.1.2-Q16-HDRI\magick.exe")
SOURCE = Path(r"C:\Users\Administrator\Desktop\sucai\fangansucai")
GROUND = Path(r"C:\Users\Administrator\Desktop\sucai\ground")
PROPS = Path(r"C:\Users\Administrator\Desktop\sucai\装饰物")
FORMAL = ROOT / "assets/art/maps/_shared/v1_5"
DIRECT = ROOT / "assets/art/maps/_shared/direct"
DATA = ROOT / "assets/data/assets"

# id: count, columns, rows, canvas, role, Chinese palette folder
BATCHES = {
 "a001":(8,8,1,(64,32),"base_tile","地面/草地"), "a002":(8,8,1,(64,32),"base_tile","地面/草地"),
 "a003":(4,4,1,(64,32),"base_tile","地面/深草地"), "a004":(6,3,2,(64,32),"base_tile","地面/泥地"),
 "a005":(6,3,2,(64,32),"base_tile","地面/泥地"), "a006":(8,4,2,(64,32),"road_tile","地面/土路"),
 "a007":(4,2,2,(64,32),"road_tile","地面/土路"), "a008":(8,4,2,(64,32),"road_tile","地面/石板路"),
 "a009":(4,2,2,(64,32),"road_tile","地面/石板路"), "a010":(4,2,2,(64,32),"base_tile","地面/水面"),
 "a011":(8,4,2,(64,32),"transition_tile","地面/水岸"), "a012":(8,4,2,(64,32),"transition_tile","地面/水岸"),
 "a013":(8,4,2,(64,32),"base_tile","地面/石地"), "a014":(8,4,2,(64,32),"base_tile","地面/裂石"),
 "a015":(8,4,2,(64,32),"base_tile","地面/矿区岩地"), "a022":(8,4,2,(64,64),"overlay_detail","装饰物/地表覆盖"),
 "a023":(8,4,2,(64,64),"overlay_detail","装饰物/地表覆盖"), "b001":(6,3,2,(96,128),"decoration","装饰物/树木"),
 "b002":(6,3,2,(96,128),"decoration","装饰物/树木"), "b003":(4,2,2,(96,128),"decoration","装饰物/枯树"),
 "b004":(6,3,2,(64,64),"decoration","装饰物/石头"), "b005":(2,2,1,(64,64),"decoration","装饰物/石头"),
 "b006":(6,3,2,(96,128),"obstacle","装饰物/岩石"), "b007":(4,2,2,(128,160),"obstacle","装饰物/岩石"),
 "b008":(6,3,2,(96,64),"terrain","建筑与城墙/栅栏"), "b009":(2,2,1,(96,64),"terrain","建筑与城墙/栅栏"),
 "b010":(6,3,2,(64,96),"decoration","装饰物/野外小物"), "b011":(6,3,2,(128,160),"terrain","建筑与城墙/边界"),
 "b012":(4,2,2,(192,160),"terrain","地图结构/出入口"),
}

def sha(p:Path)->str: return hashlib.sha256(p.read_bytes()).hexdigest()
def run(*args:str)->None:
    subprocess.run([str(MAGICK), *args], check=True, stdout=subprocess.DEVNULL)

def v15_semantics(code, role, canvas):
    ground=role in {"base_tile","road_tile","transition_tile"}
    terrain=role=="terrain" or role=="overlay_detail"
    fp={"b001":[2,2],"b002":[2,2],"b003":[2,2],"b004":[1,1],"b005":[1,1],"b006":[2,2],"b007":[3,3],"b008":[2,1],"b009":[2,1],"b010":[1,1],"b011":[3,2],"b012":[3,2]}.get(code,[1,1])
    return ground, terrain, fp, [canvas[0]//2,canvas[1]//2 if ground else canvas[1]-2]

def rebuild_v15():
    old=json.loads((DATA/"map_v15_batch_asset_catalog.json").read_text(encoding="utf-8"))
    old_by_id={a["asset_id"]:a for a in old["assets"]}; assets=[]
    for code,(count,cols,rows,canvas,role,palette) in BATCHES.items():
        src=SOURCE/f"{code}.png"; w,h=Image.open(src).size
        with Image.open(src) as im: key=im.convert("RGB").getpixel((0,0))
        key_hex="#%02x%02x%02x"%key; batch=f"{code[0].upper()}-{int(code[1:]):03d}"; outdir=FORMAL/batch; outdir.mkdir(parents=True,exist_ok=True)
        # Generated keys are not perfectly flat.  Use a high-saturation channel
        # gate rather than colour distance: it removes magenta/cyan compression
        # variation but cannot eat the dark purple-grey material itself.
        alpha_fx = "(r>0.70&&b>0.70&&g<0.35)?0:1" if key[0] > key[1] else "(g>0.70&&b>0.70&&r<0.35)?0:1"
        ground,terrain,fp,anchor=v15_semantics(code,role,canvas)
        for i in range(count):
            col,row=i%cols,i//cols; x0=round(col*w/cols); x1=round((col+1)*w/cols); y0=round(row*h/rows); y1=round((row+1)*h/rows)
            out=outdir/f"{code}_{i+1:02d}.png"; cw,ch=x1-x0,y1-y0
            # Key removal, anti-key fringe cleanup and geometry normalization are all ImageMagick operations.
            args=[str(src),"-crop",f"{cw}x{ch}+{x0}+{y0}","+repage","-alpha","set","-channel","A","-fx",alpha_fx,"+channel","-trim","+repage"]
            tw,th=canvas; margin=0 if ground else max(1,round(min(tw,th)*.04))
            # Ground texture extends two pixels beneath every mask edge so the
            # bilinear boundary cannot expose keyed/neutral pixels as a grid.
            box=f"{tw+4}x{th+2}!" if ground else f"{max(1,tw-2*margin)}x{max(1,th-2*margin)}"
            args += ["-resize",box, "-gravity",("center" if ground or role=="overlay_detail" else "south"),"-background","none","-extent",f"{tw}x{th}"]
            if ground:
                # Replace (rather than multiply) alpha with the logical diamond.
                # This prevents chroma-key remnants from becoming seams inside a tile.
                # Flatten only the keyed exterior to a neutral edge colour
                # before imposing the logical mask.  Otherwise transparent
                # pixels retain neon RGB and resampling reveals a pink fringe.
                args += ["-background","#202020","-alpha","remove","-alpha","off","(","-size",f"{tw}x{th}","xc:none","-fill","white","-draw",f"polygon {tw//2},0 {tw-1},{th//2} {tw//2},{th-1} 0,{th//2}",")","-compose","CopyOpacity","-composite"]
            args.append(str(out)); run(*args)
            aid=f"v1_5.{code}_{i+1:02d}"; rec=dict(old_by_id.get(aid,{})); rec.update({"asset_id":aid,"image":out.relative_to(ROOT).as_posix(),"thumbnail":out.relative_to(ROOT).as_posix(),"canvas_size":list(canvas),"image_size":list(canvas),"anchor_px":anchor,"footprint_tiles":fp,"palette_path":palette,"source_sha256":sha(src),"output_sha256":sha(out),"thumbnail_source_sha256":sha(out),"processing":"imagemagick_7_fuzz_key_trim_resize_extent_v2"})
            rec["processing"] = "imagemagick_7_channel_gate_overscan_diamond_v6"
            assets.append(rec)
    (DATA/"map_v15_batch_asset_catalog.json").write_text(json.dumps({"asset_schema_version":2,"assets":assets},ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    return len(assets)

def import_direct():
    assets=[]
    # Ground is already calibrated to the editor's strict 64x32 diamond contract
    # by normalize_ground_tiles.py; patch_main attaches its original folder names.
    # Props are transparent, pre-cut files and may be imported byte-for-byte.
    for root,top,kind in [(PROPS,"装饰物","prop")]:
        for src in sorted(root.rglob("*.png")):
            rel=src.relative_to(root); dst=DIRECT/top/rel; dst.parent.mkdir(parents=True,exist_ok=True); shutil.copy2(src,dst)
            with Image.open(src) as im: w,h=im.size
            stem=".".join(rel.with_suffix("").parts); aid=f"direct.{kind}.{stem}".lower().replace(" ","_")
            is_ground=kind=="ground"; fp=[1,1] if is_ground else [max(1,math.ceil(w/64)),max(1,math.ceil(h/64))]
            assets.append({"asset_id":aid,"display_name":src.stem,"asset_type":"ground_brush" if is_ground else "large_prop","category":"ground" if is_ground else "prop","theme":"ancient_gothic","image":dst.relative_to(ROOT).as_posix(),"thumbnail":dst.relative_to(ROOT).as_posix(),"canvas_size":[w,h],"image_size":[w,h],"visible_bounds_px":[0,0,w,h],"anchor_px":[w//2,h//2 if is_ground else h-2],"anchor_tile":[0,0],"anchor_mode":"tile_center" if is_ground else "foot_tile","footprint_tiles":fp,"tile_size":[64,32],"default_layer":"ground_base" if is_ground else "object_base","default_object_role":"decoration","collision_policy":"none","navigation_policy":"ignore","occlusion":False,"content_layer":"personal_expansion","placeable":True,"calibration_status":"placeable","palette_path":f"{top}/{rel.parent.as_posix()}","tags":["direct_import",kind],"source_external_path":str(src),"source_sha256":sha(src),"output_sha256":sha(dst),"thumbnail_source_sha256":sha(dst),"processing":"direct_folder_import"})
    (DATA/"map_direct_folder_asset_catalog.json").write_text(json.dumps({"asset_schema_version":2,"assets":assets},ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    return len(assets)

def patch_main():
    p=DATA/"map_asset_catalog.json"; d=json.loads(p.read_text(encoding="utf-8")); v15=json.loads((DATA/"map_v15_batch_asset_catalog.json").read_text(encoding="utf-8"))["assets"]; direct=json.loads((DATA/"map_direct_folder_asset_catalog.json").read_text(encoding="utf-8"))["assets"]
    replacements={a["asset_id"]:a for a in v15}; base=[]
    ground_paths={"old_grass":"地面/草地","dark_grass":"地面/暗色草地","leaf_grass":"地面/落叶草地","mud":"地面/泥地","stone":"地面/石地"}
    for a in d["assets"]:
        if a["asset_id"].startswith("direct."): continue
        a=replacements.pop(a["asset_id"],a)
        if a["asset_id"].startswith("ground."): a["palette_path"]=ground_paths.get(a.get("terrain_type"),"地面/其他")
        elif not a.get("palette_path"): a["palette_path"]="内置素材/其他"
        base.append(a)
    base.extend(replacements.values()); base.extend(direct); d["assets"]=base; p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+"\n",encoding="utf-8"); return len(base)

if __name__=="__main__":
    if not MAGICK.exists(): raise SystemExit("ImageMagick not found")
    print(f"v15={rebuild_v15()} direct={import_direct()} total={patch_main()}")
