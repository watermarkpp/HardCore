"""Copy baked editor chunks into exportable runtime assets and write a manifest."""
import json, shutil
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
WORKSPACE=ROOT/'map_editor_workspace/bich_province'
WORK=WORKSPACE/'ground'
DEST=ROOT/'assets/art/maps/bich/editor_runtime_chunks'
OUT=ROOT/'assets/data/runtime/map_editor/bich_province.visual.json'
manifest=json.loads((WORK/'ground_manifest.json').read_text(encoding='utf-8'))
if DEST.exists(): shutil.rmtree(DEST)
DEST.mkdir(parents=True,exist_ok=True); chunks=[]
for chunk in manifest['chunks']:
    preview=chunk.get('preview_png')
    if not preview: continue
    src=WORKSPACE/preview; dst=DEST/src.name; shutil.copy2(src,dst)
    chunks.append({'chunk_id':chunk['chunk_id'],'rect_px':chunk['rect_px'],'image':dst.relative_to(ROOT).as_posix()})
design_size=manifest['design_size']
ground_size=manifest['ground_pixel_size']
payload={'schema_version':1,'map_id':'bich_province','runtime_map_id':4,'design_size':design_size,
         'ground_pixel_center':[ground_size[0]/2,ground_size[1]/2],'base_color':'#465827','chunks':chunks}
OUT.write_text(json.dumps(payload,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(f'BICH_RUNTIME_VISUAL_PACKAGE_PASS chunks={len(chunks)}')
