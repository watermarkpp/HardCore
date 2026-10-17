"""Prove mechanical extraction against pinned upstream, independently of shared-adapter runtime equality."""
from pathlib import Path
import argparse,subprocess,re,json,hashlib
ap=argparse.ArgumentParser();ap.add_argument('--engine',required=True);ap.add_argument('--output',required=True);a=ap.parse_args()
E=Path(a.engine); BASE='5b4e0cb0fd279832bbdd69fed5354d4e5ad26f88'
def orig(path):return subprocess.check_output(['git','show',BASE+':'+path],cwd=E).decode()
def func(s,signature):
 start=s.index(signature);i=s.index('{',start);begin=i;i+=1;depth=1
 while depth:
  if s[i]=='{':depth+=1
  elif s[i]=='}':depth-=1
  i+=1
 return s[begin:i]
def tokens(s):return re.findall(r'\w+|[^\s]',re.sub(r'//[^\n]*','',s))
c=orig('scene/2d/physics/character_body_2d.cpp');p=orig('scene/2d/physics/physics_body_2d.cpp');shared=(E/'scene/2d/physics/character_motion_2d.cpp').read_text(encoding='utf-8');checks=[]
names=['move_and_slide','_move_and_slide_grounded','_move_and_slide_floating','_apply_floor_snap','_snap_on_floor','_on_floor_if_snapped','_set_collision_direction','_set_platform_data']
for name in names:
 expected=func(c,'CharacterBody2D::'+name+'(')
 if name=='move_and_slide':expected=re.sub(r'\t// Hack[^\n]*\n\tdouble delta = [^;]*;\n\n','',expected)
 expected=expected.replace('PhysicsServer2D::get_singleton()->body_get_direct_state(', 'p_adapter.body_get_direct_state(').replace('get_global_transform()','p_adapter.get_transform()').replace('set_global_transform(','p_adapter.set_transform(')
 expected=expected.replace('get_position_delta()','(p_adapter.get_transform().columns[2] - previous_position)').replace('is_on_floor_only()','(on_floor && !on_wall && !on_ceiling)').replace('is_on_wall_only()','(on_wall && !on_floor && !on_ceiling)')
 expected=expected.replace('ObjectDB::get_instance<CharacterBody2D>(p_result.collider_id) == nullptr','!p_adapter.is_character(p_result.collider_id, p_result.collider)').replace('MOTION_MODE_GROUNDED','0').replace('PLATFORM_ON_LEAVE_DO_NOTHING','2').replace('PLATFORM_ON_LEAVE_ADD_UPWARD_VELOCITY','1')
 for other in names[1:]:expected=expected.replace(other+'(',other+'(p_adapter, ')
 expected=expected.replace('move_and_collide(','physics_motion_2d_move_and_collide(p_adapter, ')
 if name=='_set_platform_data':
  begin=expected.index('#ifndef DISABLE_DEPRECATED');end=expected.rindex('\n}');expected=expected[:begin]+'\tplatform_layer = p_adapter.get_collision_layer(bs, p_result.collider);\n'+expected[end:]
 actual=func(shared,'CharacterMotion2DState::'+name+'(')
 checks.append({'function':name,'status':'PASS' if tokens(expected)==tokens(actual) else 'FAIL','expected_sha256':hashlib.sha256(' '.join(tokens(expected)).encode()).hexdigest(),'actual_sha256':hashlib.sha256(' '.join(tokens(actual)).encode()).hexdigest()})
expected=func(p,'bool PhysicsBody2D::move_and_collide(').replace('is_only_update_transform_changes_enabled()','p_adapter.only_update_transform_changes()').replace('PhysicsServer2D::get_singleton()->body_test_motion(get_rid(), p_parameters, &r_result)','p_adapter.test_motion(p_parameters, r_result)').replace('set_global_transform(gt)','p_adapter.set_transform(gt)')
checks.append({'function':'PhysicsBody2D::move_and_collide','status':'PASS' if tokens(expected)==tokens(func(shared,'bool physics_motion_2d_move_and_collide(')) else 'FAIL'})
common=(E/'servers/server_wrap_mt_common.h').read_text(encoding='utf-8');generated=re.findall(r'\tvirtual [^\n]+ \{ \\\n([^\n]+)',common)
checks.append({'function':'every_generated_wrapper_entry_gated','count':len(generated),'status':'PASS' if generated and all('SERVER_ACCESS_GUARD' in x for x in generated) else 'FAIL'})
wrap=(E/'servers/physics_2d/physics_server_2d_wrap_mt.h').read_text(encoding='utf-8')
checks.append({'function':'ordinary_main_guards','status':'PASS' if wrap.count('!external_owner_mode && !Thread::is_main_thread()')==orig('servers/physics_2d/physics_server_2d_wrap_mt.h').count('!Thread::is_main_thread()') else 'FAIL'})
checks.append({'function':'no_old_motion_copy_or_Node_in_shared','status':'PASS' if '#if 0' not in (E/'scene/2d/physics/character_body_2d.cpp').read_text(encoding='utf-8') and not any(x in shared for x in ['Engine::','ObjectDB::','get_global_transform()','set_global_transform(']) else 'FAIL'})
result={'status':'PASS' if all(x['status']=='PASS' for x in checks) else 'FAIL','base':BASE,'checks':checks,'scope':'STATIC SOURCE EQUIVALENCE ONLY. Build/native/parity/owner/device NOT_RUN.'}
Path(a.output).write_text(json.dumps(result,indent=2));print(json.dumps(result,indent=2));raise SystemExit(0 if result['status']=='PASS' else 1)
