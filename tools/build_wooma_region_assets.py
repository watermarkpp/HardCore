from __future__ import annotations

import json, math, struct, sys
from collections import Counter
from pathlib import Path
from PIL import Image, ImageDraw, ImageEnhance

ROOT=Path(__file__).resolve().parents[1]; WORKSPACE=ROOT.parents[1]
CLIENT=WORKSPACE/"research/mir2_client_raw"; MAP_DIR=CLIENT/"Map"; DATA=CLIENT/"Data"
OUTPUT=ROOT/"assets/art/maps/wooma_region"; PROFILE=ROOT/"assets/data/wooma_region_source_profiles.json"
MAPS={268:("沃玛森林","1"),1506:("沃玛自然洞穴一","E001"),1507:("沃玛自然洞穴二","E002")}
sys.path.insert(0,str(WORKSPACE/"tools"))
from extract_wil import decode_sprite,read_library  # noqa:E402

def wil(lib,index):
    data,pal,offs,_=read_library(DATA/lib); image,_=decode_sprite(data,offs[index],pal); return image.convert("RGBA")

def parse_map(path):
    raw=path.read_bytes(); w,h=struct.unpack_from("<HH",raw,0); blocked=lights=doors=0; tiles=Counter(); objs=Counter(); areas=Counter(); mask=Image.new("L",(w,h),0); px=mask.load()
    if len(raw)!=52+w*h*12: raise ValueError(path.name)
    for i,off in enumerate(range(52,len(raw),12)):
        bk,mid,fr,di,do,af,at,ar,li=struct.unpack_from("<HHHBBBBBB",raw,off); x,y=divmod(i,h); stop=bool((bk|fr)&0x8000); px[x,y]=38 if stop else 225
        blocked+=int(stop); lights+=int(li>0); doors+=int((di&0x7f)>0); areas[ar]+=1
        if bk&0x7fff: tiles[bk&0x7fff]+=1
        if fr&0x7fff: objs[f"Objects{ar+1}:{fr&0x7fff}"]+=1
    return {"width":w,"height":h,"blockedRatio":round(blocked/(w*h),4),"lightCells":lights,"doorCells":doors,"topTileImageIds":[k for k,_ in tiles.most_common(10)],"topObjectImageIds":[k for k,_ in objs.most_common(14)],"areaCounts":{str(k):v for k,v in areas.items()}},mask

def tile(image,bright=0.8):
    out=ImageEnhance.Brightness(image.resize((64,32),Image.Resampling.LANCZOS)).enhance(bright); mask=Image.new("L",(64,32),0); d=ImageDraw.Draw(mask); d.polygon([(32,0),(63,15),(32,31),(0,15)],fill=255); out.putalpha(mask); ImageDraw.Draw(out).line([(32,0),(63,15),(32,31),(0,15),(32,0)],fill=(30,24,18,210),width=1); return out

def ground(name,indices):
    atlas=Image.new("RGBA",(512,32),(0,0,0,0))
    for slot,index in enumerate(indices): atlas.alpha_composite(tile(wil("Tiles.wil",index),0.75+slot*.025),(slot*64,0))
    atlas.save(OUTPUT/name)

def source_part(index,max_size=(82,112),bright=.9):
    im=ImageEnhance.Brightness(wil("Objects.wil",index)).enhance(bright); im.thumbnail(max_size,Image.Resampling.LANCZOS); return im

def forest_props():
    indices=[1376,1386,1392,1402,1408,1412,1380,1404]; atlas=Image.new("RGBA",(768,128),(0,0,0,0))
    for slot,index in enumerate(indices):
        im=source_part(index); atlas.alpha_composite(im,(slot*96+(96-im.width)//2,124-im.height))
    d=ImageDraw.Draw(atlas); trunk=(58,39,23,255); leaf=(45,94,37,255); stone=(92,83,65,255); dark=(35,31,27,255)
    # 古树、倒木、遗迹柱、碎碑、藤架、洞口、灌木、路标
    d.rectangle((40,54,56,124),fill=trunk); d.ellipse((8,15,87,78),fill=leaf,outline=(28,63,26,255)); d.line((116,109,176,67),fill=trunk,width=14)
    ox=192; d.polygon([(ox+25,119),(ox+70,119),(ox+64,34),(ox+33,34)],fill=stone,outline=dark); d.polygon([(ox+21,39),(ox+74,39),(ox+65,23),(ox+31,23)],fill=(122,108,80,255),outline=dark)
    ox=288; d.polygon([(ox+15,114),(ox+79,114),(ox+68,70),(ox+25,72)],fill=stone,outline=dark); d.line((ox+30,82,ox+65,102),fill=(53,48,39,255),width=3)
    ox=384; d.rectangle((ox+18,44,ox+29,123),fill=trunk); d.rectangle((ox+69,44,ox+80,123),fill=trunk); d.line((ox+20,49,ox+78,49),fill=trunk,width=11); d.arc((ox+11,18,ox+86,108),195,340,fill=(51,117,43,255),width=8)
    ox=480; d.ellipse((ox+13,58,ox+83,125),fill=(7,10,7,235)); d.arc((ox+8,20,ox+88,125),180,360,fill=stone,width=13)
    ox=576
    for cx,cy,r in [(23,107,18),(50,92,26),(75,109,17)]: d.ellipse((ox+cx-r,cy-r,ox+cx+r,cy+r),fill=leaf,outline=(27,62,25,255))
    ox=672; d.line((ox+48,122,ox+48,48),fill=trunk,width=8); d.polygon([(ox+48,55),(ox+85,67),(ox+48,79)],fill=(139,105,51,255),outline=dark)
    atlas.save(OUTPUT/"wooma_forest_props.png"); return indices

def cave_props():
    indices=[4439,4448,4452,4466,4480,4492,4510,4520]; atlas=Image.new("RGBA",(768,128),(0,0,0,0))
    for slot,index in enumerate(indices):
        im=source_part(index); atlas.alpha_composite(im,(slot*96+(96-im.width)//2,124-im.height))
    d=ImageDraw.Draw(atlas); rock=(82,69,55,255); dark=(32,28,25,255); moss=(58,82,42,255); bone=(154,139,103,255)
    # 岩柱、岩壁、石笋、菌簇、裂隙、骨堆、沃玛图腾、洞门
    d.polygon([(18,121),(79,121),(66,28),(33,23)],fill=rock,outline=dark); d.line((40,37,54,69,43,105),fill=(119,94,69,255),width=3)
    ox=96; d.polygon([(ox+4,122),(ox+8,45),(ox+28,18),(ox+70,26),(ox+90,53),(ox+91,122)],fill=(62,53,45,255),outline=dark)
    ox=192; d.polygon([(ox+13,121),(ox+36,62),(ox+48,105),(ox+65,38),(ox+85,121)],fill=rock,outline=dark)
    ox=288
    for cx,cy,r in [(25,108,12),(45,93,16),(67,108,13)]: d.ellipse((ox+cx-r,cy-r,ox+cx+r,cy+r),fill=moss,outline=dark)
    ox=384; d.polygon([(ox+12,122),(ox+25,36),(ox+48,70),(ox+67,25),(ox+85,122)],fill=(15,13,12,235),outline=rock)
    ox=480
    for cx,cy,r in [(23,105,10),(43,99,9),(64,108,11),(75,92,8)]: d.ellipse((ox+cx-r,cy-r,ox+cx+r,cy+r),fill=bone,outline=dark)
    ox=576; d.polygon([(ox+28,119),(ox+68,119),(ox+62,39),(ox+35,39)],fill=rock,outline=dark); d.line((ox+48,48,ox+39,66,ox+57,79,ox+43,103),fill=(174,79,33,255),width=3)
    ox=672; d.rectangle((ox+13,52,ox+29,123),fill=rock,outline=dark); d.rectangle((ox+67,52,ox+83,123),fill=rock,outline=dark); d.arc((ox+14,11,ox+82,82),180,360,fill=(109,87,64,255),width=16); d.ellipse((ox+28,49,ox+68,123),fill=(7,7,7,220))
    atlas.save(OUTPUT/"wooma_cave_props.png"); return indices

def glow():
    im=Image.new("RGBA",(128,128),(0,0,0,0)); p=im.load()
    for y in range(128):
        for x in range(128):
            dist=math.hypot(x-63.5,y-63.5)/64; p[x,y]=(118,184,72,int(145*max(0,1-dist)**2))
    im.save(OUTPUT/"wooma_cave_glow.png")

def build():
    OUTPUT.mkdir(parents=True,exist_ok=True); masks=OUTPUT/"source_masks"; masks.mkdir(exist_ok=True); profiles={}
    for mid,(name,code) in MAPS.items():
        info,mask=parse_map(MAP_DIR/f"{code}.map"); mask.thumbnail((240,240),Image.Resampling.NEAREST); mask.save(masks/f"{mid}_{code}.png"); profiles[str(mid)]={"name":name,"sourceMapCode":code,"sourceMapPath":f"research/mir2_client_raw/Map/{code}.map","sourceKind":"客户端原始MAP直接解析","confidence":"A",**info}
    forest_tiles=[1450,1451,1452,1453,1454,1850,1852,1854]; cave_tiles=[1900,1901,1902,1903,1904,1900,1902,1904]
    ground("wooma_forest_ground_tiles.png",forest_tiles); ground("wooma_cave_ground_tiles.png",cave_tiles); fobjs=forest_props(); cobjs=cave_props(); glow()
    PROFILE.write_text(json.dumps({"baseline":"2003官服1.76基准版","generatedFrom":"客户端1/E001/E002 MAP与WIL/WIX原始资源","mapProfiles":profiles,"assetSources":{"forestGround":{"library":"Data/Tiles.wil","indices":forest_tiles},"forestProps":{"library":"Data/Objects.wil","indices":fobjs},"caveGround":{"library":"Data/Tiles.wil","indices":cave_tiles},"caveProps":{"library":"Data/Objects.wil","indices":cobjs},"note":"原始纹理直接提取，大型树木、遗迹与洞穴物件按手机视野重组。"}},ensure_ascii=False,indent=2),encoding="utf-8")
    print(f"WOOMA_REGION_PROFILES={PROFILE}"); print(f"WOOMA_REGION_ASSETS={OUTPUT}")

if __name__=="__main__": build()
