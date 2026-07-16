import json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]; DATA=ROOT/'assets/data/assets'

def classify(a):
    p=str(a.get('palette_path','')).lower(); aid=str(a.get('asset_id','')).lower()
    if a.get('asset_type') in ['ground_brush','procedural_ground']: return ('ground','ground_decal',[1,1],[0,0],'none_visual','none')
    if '09_ground_decals' in p or '10_magic_glows' in p or '地表覆盖' in p: return ('ground_decal','ground_decal',[1,1],[0,0],'none_visual','none')
    if '02_tents' in p: return ('tent','tent_blacksmith_standard',[8,8],[8,8],'tent_blacksmith_standard','profile')
    if '树木' in p or '枯树' in p or 'b001' in aid or 'b002' in aid or 'b003' in aid: return ('tree','tree_medium',[4,6],[1,1],'tree_trunk_1x1','profile')
    if '地图结构/出入口' in p or 'b012' in aid: return ('cave_entrance','cave_entrance',[8,6],[8,6],'cave_entrance_8x6','profile')
    if '栅栏' in p or '07_fence' in p or 'b008' in aid or 'b009' in aid: return ('fence','small_prop',[2,1],[2,1],'fence_segment_2x1','line_segment')
    if '岩石' in p or 'b006' in aid or 'b007' in aid: return ('rock_large','tree_large',[4,4],[4,4],'rock_large_4x4','profile')
    if '石头' in p or 'b004' in aid or 'b005' in aid: return ('rock_medium','small_prop',[2,2],[2,2],'rock_medium_2x2','profile')
    if '01_camp_props' in p or '03_storage' in p or '04_blacksmith' in p or '05_herbal' in p or '06_library' in p or '08_misc' in p: return ('small_prop','small_prop',[1,1],[1,1],'small_prop_1x1','profile')
    return ('decoration','small_prop',a.get('footprint_tiles',[1,1]),[0,0],'none_visual','none')

def update_file(path):
    d=json.loads(path.read_text(encoding='utf-8'))
    for a in d.get('assets',[]):
        cls,scale,visual,collision,cp,policy=classify(a)
        a.update({'object_class':cls,'category':cls,'visual_footprint_tiles':visual,'footprint_tiles':visual,'occupancy_footprint_tiles':visual,
                  'collision_footprint_tiles':collision,'collision_profile_id':cp,'collision_policy':policy,'scale_profile_id':scale,
                  'approved_scale':1.0,'scale_approved':True,'anchor_approved':True,'collision_approved':True,
                  'placement_anchor_px':a.get('anchor_px',[0,0]),'render_sort_anchor_px':a.get('anchor_px',[0,0]),
                  'selection_shape':{'type':'alpha','alpha_threshold':0.1,'padding_px':4}})
        image_h=max(1,int(a.get('visible_bounds_px',[0,0,1,a.get('image_size',[1,1])[1]])[3]))
        target_h={'ground':image_h,'small_prop':64,'tree':320,'cave_entrance':320,'fence':96,'rock_medium':128,'rock_large':256,'decoration':96}.get(cls,image_h)
        if cls=='tent':
            a['class_profile_id']='tent_blacksmith_standard'; a['reference_asset_id']='direct.prop.02_tents.02_tents_01_r01_c01'; target_h=408
        a['approved_scale']=round(target_h/image_h,6)
    path.write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

for name in ['map_v15_batch_asset_catalog.json','map_direct_folder_asset_catalog.json','map_asset_catalog.json']:
    update_file(DATA/name)
print('MSE_V351_CLASS_PROFILE_PASS')
