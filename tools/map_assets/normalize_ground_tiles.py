#!/usr/bin/env python3
"""Normalize high-resolution 1x1 isometric ground diamonds to 64x32."""
from __future__ import annotations
import argparse, hashlib, json, shutil
from pathlib import Path
import cv2
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_SOURCE = Path.home() / "Desktop" / "sucai"
RAW_ROOT = ROOT / "assets/raw_import/map_assets/ground_sources"
ART_ROOT = ROOT / "assets/art/maps/_shared/terrain"
DATA_ROOT = ROOT / "assets/data/assets"
SETS = {
    "old_grass": ("grass_tiles_split_png_29_tiles", "tile_*.png", "古旧草地"),
    "dark_grass": ("dark_grass_tiles_split_png_29_tiles", "dark_grass_tile_*.png", "暗色草地"),
    "leaf_grass": ("leaf_grass_tiles_split_png_36_tiles", "leaf_grass_tile_*.png", "落叶草地"),
    "mud": ("mud_tiles_split_png_29_tiles", "mud_tile_*.png", "泥地"),
    "stone": ("stone_tiles_split_png_30_tiles", "stone_tile_*.png", "石地"),
}
DEST_CORNERS = np.float32([[32, 0], [63, 16], [32, 31], [0, 16]])

def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()

def diamond_tips(alpha: np.ndarray) -> np.ndarray:
    ys, xs = np.where(alpha > 0)
    if len(xs) < 32:
        raise ValueError("alpha foreground is empty")
    xmin, xmax, ymin, ymax = xs.min(), xs.max(), ys.min(), ys.max()
    def tip(mask): return [float(np.median(xs[mask])), float(np.median(ys[mask]))]
    return np.float32([tip(ys <= ymin + 2), tip(xs >= xmax - 2), tip(ys >= ymax - 2), tip(xs <= xmin + 2)])

def diamond_mask() -> np.ndarray:
    scale = 8
    mask = np.zeros((32 * scale, 64 * scale), np.uint8)
    points = np.array([[32*scale,0],[64*scale-1,16*scale],[32*scale,32*scale-1],[0,16*scale]],np.int32)
    cv2.fillConvexPoly(mask, points, 255, lineType=cv2.LINE_AA)
    return cv2.resize(mask, (64,32), interpolation=cv2.INTER_AREA)

MASK = diamond_mask()

def normalize(source: Path, output: Path) -> dict:
    rgba = cv2.imread(str(source), cv2.IMREAD_UNCHANGED)
    if rgba is None or rgba.ndim != 3 or rgba.shape[2] != 4:
        raise ValueError("source is not RGBA")
    tips = diamond_tips(rgba[:,:,3])
    matrix = cv2.getPerspectiveTransform(tips, DEST_CORNERS)
    warped = cv2.warpPerspective(rgba, matrix, (64,32), flags=cv2.INTER_AREA,
                                 borderMode=cv2.BORDER_CONSTANT, borderValue=(0,0,0,0))
    warped[:,:,3] = np.minimum(warped[:,:,3], MASK)
    inner = MASK >= 250
    holes = inner & (warped[:,:,3] < 240)
    if holes.any():
        rgb = warped[:,:,:3]
        for _ in range(3):
            dilated = cv2.dilate(rgb, np.ones((3,3),np.uint8))
            rgb[holes] = dilated[holes]
        warped[:,:,:3] = rgb
        warped[:,:,3][inner] = 255
    output.parent.mkdir(parents=True, exist_ok=True)
    if not cv2.imwrite(str(output), warped):
        raise ValueError("output write failed")
    coverage = float(np.count_nonzero(warped[:,:,3][inner] >= 250) / np.count_nonzero(inner))
    return {"source_tips_px":tips.round(3).tolist(), "diamond_inner_coverage":round(coverage,6), "output_size":[64,32]}

def main() -> int:
    parser=argparse.ArgumentParser(); parser.add_argument("--source-root",type=Path,default=DEFAULT_SOURCE)
    args=parser.parse_args(); sources=[]; imports=[]; assets=[]; problems=[]
    assets.append({
        "asset_id":"builtin.blank_old_grass","display_name":"程序空白旧草地","asset_type":"procedural_ground",
        "category":"ground","theme":"shared","image":None,"thumbnail":None,"canvas_size":[64,32],
        "logical_bounds_px":[0,0,64,32],"anchor_px":[32,16],"anchor_tile":[0,0],"anchor_mode":"tile_center",
        "footprint_tiles":[1,1],"tile_size":[64,32],"ground_brush_role":"base_tile","terrain_type":"old_grass",
        "paintable":True,"collision_policy":"none","navigation_policy":"ignore","content_layer":"personal_expansion",
        "placeable":True,"tags":["ground","builtin","old_grass"],"source_sha256":"builtin:v1",
        "output_sha256":"builtin:v1","calibration_status":"placeable","diamond_inner_coverage":1.0
    })
    # Object assets are independently prepared; this ground builder only merges them.
    object_catalog = DATA_ROOT / "map_object_asset_catalog.json"
    if object_catalog.exists():
        assets.extend(json.loads(object_catalog.read_text(encoding="utf-8")).get("assets", []))
    terrain_catalog = DATA_ROOT / "map_terrain_asset_catalog.json"
    if terrain_catalog.exists():
        assets.extend(json.loads(terrain_catalog.read_text(encoding="utf-8")).get("assets", []))
    v15_catalog = DATA_ROOT / "map_v15_batch_asset_catalog.json"
    if v15_catalog.exists():
        assets.extend(json.loads(v15_catalog.read_text(encoding="utf-8")).get("assets", []))
    direct_catalog = DATA_ROOT / "map_direct_folder_asset_catalog.json"
    if direct_catalog.exists():
        assets.extend(json.loads(direct_catalog.read_text(encoding="utf-8")).get("assets", []))
    for terrain,(folder,pattern,label) in SETS.items():
        source_dir=args.source_root/folder
        for index,src in enumerate(sorted(source_dir.glob(pattern)),1):
            asset_id=f"ground.{terrain}.{index:03d}"
            raw=RAW_ROOT/terrain/src.name; raw.parent.mkdir(parents=True,exist_ok=True); shutil.copy2(src,raw)
            output=ART_ROOT/terrain/f"{asset_id.replace('.','_')}.png"
            base={"asset_id":asset_id,"source_external_path":str(src),"raw_import_path":raw.relative_to(ROOT).as_posix(),"source_sha256":sha(src)}
            sources.append(base)
            try:
                audit=normalize(src,output); output_sha=sha(output); image=output.relative_to(ROOT).as_posix()
                imports.append({**base,"status":"calibrated","normalization":"alpha_tip_perspective_to_64x32","output_path":image,**audit})
                assets.append({
                    "asset_id":asset_id,"display_name":f"{label} {index:02d}","asset_type":"ground_brush","category":"ground",
                    "theme":"ancient_gothic","image":image,"thumbnail":image,"canvas_size":[64,32],
                    "logical_bounds_px":[0,0,64,32],"visible_bounds_px":[0,0,64,32],"anchor_px":[32,16],
                    "anchor_tile":[0,0],"anchor_mode":"tile_center","footprint_tiles":[1,1],"tile_size":[64,32],
                    "ground_brush_role":"base_tile","terrain_type":terrain,"paintable":True,"collision_policy":"none",
                    "navigation_policy":"ignore","content_layer":"personal_expansion","placeable":True,
                    "tags":["ground",terrain,"ancient_gothic","base_tile"],"source_sha256":base["source_sha256"],
                    "output_sha256":output_sha,"thumbnail_source_sha256":output_sha,"calibration_status":"placeable",
                    "diamond_inner_coverage":audit["diamond_inner_coverage"],"normalization":"alpha_tip_perspective_to_64x32"
                })
            except Exception as exc:
                problems.append({**base,"status":"rejected","problem":str(exc)})
    DATA_ROOT.mkdir(parents=True,exist_ok=True)
    outputs={
        "map_asset_source_catalog.json":{"asset_schema_version":2,"sources":sources},
        "map_asset_import_catalog.json":{"asset_schema_version":2,"imports":imports},
        "map_asset_catalog.json":{"asset_schema_version":2,"tile_size":[64,32],"assets":assets},
        "map_asset_problem_list.json":{"asset_schema_version":2,"problems":problems},
        "map_asset_import_report.json":{"asset_schema_version":2,"source_count":len(sources),"normalized_count":len(imports),"placeable_count":len(assets),"rejected_count":len(problems)}
    }
    for name,payload in outputs.items():
        (DATA_ROOT/name).write_text(json.dumps(payload,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print(f"sources={len(sources)} normalized={len(imports)} placeable={len(assets)} rejected={len(problems)}")
    return 1 if problems else 0
if __name__=="__main__": raise SystemExit(main())
