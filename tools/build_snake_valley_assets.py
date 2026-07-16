from __future__ import annotations
import json,math,struct,sys
from collections import Counter
from pathlib import Path
from PIL import Image,ImageDraw,ImageEnhance

ROOT=Path(__file__).resolve().parents[1]; WORKSPACE=ROOT.parents[1]; CLIENT=WORKSPACE/"research/mir2_client_raw"; DATA=CLIENT/"Data"; MAPDIR=CLIENT/"Map"
OUT=ROOT/"assets/art/maps/snake_valley"; PROFILE=ROOT/"assets/data/snake_valley_source_profiles.json"; MAPS={338:("毒蛇山谷","2"),457:("山谷矿区一","D421"),458:("山谷矿区二","D422")}
sys.path.insert(0,str(WORKSPACE/"tools")); from extract_wil import decode_sprite,read_library  # noqa:E402

def wil(lib,index):
 d,p,o,_=read_library(DATA/lib); im,_=decode_sprite(d,o[index],p); return im.convert("RGBA")
def parse(path):
 b=path.read_bytes();w,h=struct.unpack_from("<HH",b,0);blocked=lights=doors=0;tiles=Counter();objs=Counter();areas=Counter();mask=Image.new("L",(w,h));px=mask.load()
 if len(b)!=52+w*h*12:raise ValueError(path.name)
 for i,off in enumerate(range(52,len(b),12)):
  bk,mid,fr,di,do,af,at,ar,li=struct.unpack_from("<HHHBBBBBB",b,off);x,y=divmod(i,h);stop=bool((bk|fr)&0x8000);px[x,y]=36 if stop else 225;blocked+=int(stop);lights+=int(li>0);doors+=int((di&127)>0);areas[ar]+=1
  if bk&32767:tiles[bk&32767]+=1
  if fr&32767:objs[f"Objects{ar+1}:{fr&32767}"]+=1
 return {"width":w,"height":h,"blockedRatio":round(blocked/(w*h),4),"lightCells":lights,"doorCells":doors,"topTileImageIds":[k for k,_ in tiles.most_common(10)],"topObjectImageIds":[k for k,_ in objs.most_common(14)],"areaCounts":{str(k):v for k,v in areas.items()}},mask
def diamond(im,bright):
 im=ImageEnhance.Brightness(im.resize((64,32),Image.Resampling.LANCZOS)).enhance(bright);m=Image.new("L",(64,32));d=ImageDraw.Draw(m);d.polygon([(32,0),(63,15),(32,31),(0,15)],fill=255);im.putalpha(m);ImageDraw.Draw(im).line([(32,0),(63,15),(32,31),(0,15),(32,0)],fill=(32,24,18,220));return im
def ground(name,indices):
 a=Image.new("RGBA",(512,32))
 for s,i in enumerate(indices):a.alpha_composite(diamond(wil("Tiles.wil",i),.73+s*.025),(s*64,0))
 a.save(OUT/name)
def part(lib,index):
 im=ImageEnhance.Brightness(wil(lib,index)).enhance(.88);im.thumbnail((82,112),Image.Resampling.LANCZOS);return im
def surface_props():
 ids=[1402,1377,1392,1408,1412,1386,1404,1416];a=Image.new("RGBA",(768,128))
 for s,i in enumerate(ids):im=part("Objects.wil",i);a.alpha_composite(im,(s*96+(96-im.width)//2,124-im.height))
 d=ImageDraw.Draw(a);earth=(102,76,46,255);rock=(104,91,67,255);dark=(43,35,28,255);leaf=(65,99,41,255);dead=(74,48,27,255)
 d.polygon([(8,119),(30,56),(53,30),(88,119)],fill=rock,outline=dark);d.line((30,79,57,58,70,101),fill=(139,112,75,255),width=3)
 ox=96;d.line((ox+48,122,ox+44,45),fill=dead,width=12);d.line((ox+45,63,ox+17,35),fill=dead,width=8);d.line((ox+45,72,ox+79,42),fill=dead,width=7)
 ox=192;d.polygon([(ox+16,118),(ox+80,118),(ox+68,67),(ox+27,69)],fill=rock,outline=dark);d.line((ox+29,82,ox+65,103),fill=(59,50,39,255),width=3)
 ox=288;d.rectangle((ox+18,48,ox+29,123),fill=dead);d.rectangle((ox+69,48,ox+80,123),fill=dead);d.line((ox+22,52,ox+77,52),fill=dead,width=10);d.arc((ox+12,17,ox+86,108),200,338,fill=leaf,width=7)
 ox=384
 for cx,cy,r in [(23,108,17),(50,91,25),(76,109,16)]:d.ellipse((ox+cx-r,cy-r,ox+cx+r,cy+r),fill=leaf,outline=dark)
 ox=480;d.polygon([(ox+12,121),(ox+25,48),(ox+48,79),(ox+68,35),(ox+85,121)],fill=(27,24,21,235),outline=rock)
 ox=576;d.line((ox+48,122,ox+48,47),fill=dead,width=8);d.polygon([(ox+48,54),(ox+86,67),(ox+48,80)],fill=earth,outline=dark);d.line((ox+58,64,ox+74,68),fill=(43,31,23,255),width=2)
 ox=672;d.ellipse((ox+12,63,ox+84,124),fill=(12,16,10,235));d.arc((ox+8,18,ox+88,125),180,360,fill=rock,width=14)
 a.save(OUT/"snake_valley_props.png");return ids
def mine_props():
 ids=[7101,7110,7323,7326,7439,7447,7451,7452];a=Image.new("RGBA",(768,128))
 for s,i in enumerate(ids):im=part("Objects2.wil",i);a.alpha_composite(im,(s*96+(96-im.width)//2,124-im.height))
 d=ImageDraw.Draw(a);rock=(69,67,57,255);wet=(43,66,59,255);wood=(92,62,35,255);dark=(28,28,25,255);glow=(96,175,111,255)
 d.polygon([(17,121),(80,121),(66,25),(33,20)],fill=rock,outline=dark);d.line((38,36,55,67,43,108),fill=wet,width=4)
 ox=96;d.polygon([(ox+4,122),(ox+9,48),(ox+29,20),(ox+70,27),(ox+90,55),(ox+91,122)],fill=(50,52,46,255),outline=dark);d.line((ox+25,65,ox+72,79),fill=wet,width=4)
 ox=192;d.rectangle((ox+18,44,ox+29,123),fill=wood);d.rectangle((ox+69,44,ox+80,123),fill=wood);d.line((ox+22,49,ox+77,49),fill=wood,width=10)
 ox=288;d.polygon([(ox+10,119),(ox+31,64),(ox+47,104),(ox+67,39),(ox+86,119)],fill=rock,outline=dark)
 ox=384
 for cx,cy,r in [(23,108,13),(48,94,19),(73,109,14)]:d.ellipse((ox+cx-r,cy-r,ox+cx+r,cy+r),fill=wet,outline=dark)
 ox=480;d.ellipse((ox+18,70,ox+80,124),fill=(9,18,16,230));d.arc((ox+10,23,ox+88,125),180,360,fill=rock,width=14)
 ox=576;d.line((ox+48,121,ox+48,51),fill=wood,width=7);d.line((ox+48,54,ox+75,54),fill=wood,width=6);d.ellipse((ox+64,55,ox+83,78),fill=glow,outline=dark,width=3)
 ox=672;d.polygon([(ox+27,119),(ox+69,119),(ox+63,39),(ox+34,39)],fill=rock,outline=dark);d.line((ox+48,50,ox+39,68,ox+58,81,ox+43,103),fill=glow,width=3)
 a.save(OUT/"snake_mine_props.png");return ids
def glow():
 im=Image.new("RGBA",(128,128));p=im.load()
 for y in range(128):
  for x in range(128):q=math.hypot(x-63.5,y-63.5)/64;p[x,y]=(103,207,139,int(155*max(0,1-q)**2))
 im.save(OUT/"snake_mine_glow.png")
def build():
 OUT.mkdir(parents=True,exist_ok=True);masks=OUT/"source_masks";masks.mkdir(exist_ok=True);profiles={}
 for mid,(name,code) in MAPS.items():
  info,mask=parse(MAPDIR/f"{code}.map");mask.thumbnail((240,240),Image.Resampling.NEAREST);mask.save(masks/f"{mid}_{code}.png");profiles[str(mid)]={"name":name,"sourceMapCode":code,"sourceMapPath":f"research/mir2_client_raw/Map/{code}.map","sourceKind":"客户端原始MAP直接解析","confidence":"A",**info}
 st=[350,351,352,353,354,1450,1452,1454];mt=[2150,2151,2152,2153,2154,2150,2152,2154];ground("snake_valley_ground_tiles.png",st);ground("snake_mine_ground_tiles.png",mt);so=surface_props();mo=mine_props();glow()
 PROFILE.write_text(json.dumps({"baseline":"2003官服1.76基准版","generatedFrom":"客户端2/D421/D422 MAP与WIL/WIX原始资源","mapProfiles":profiles,"assetSources":{"valleyGround":{"library":"Tiles.wil","indices":st},"valleyProps":{"library":"Objects.wil","indices":so},"mineGround":{"library":"Tiles.wil","indices":mt},"mineProps":{"library":"Objects2.wil","indices":mo}}},ensure_ascii=False,indent=2),encoding="utf-8");print(f"SNAKE_VALLEY_PROFILES={PROFILE}");print(f"SNAKE_VALLEY_ASSETS={OUT}")
if __name__=="__main__":build()
