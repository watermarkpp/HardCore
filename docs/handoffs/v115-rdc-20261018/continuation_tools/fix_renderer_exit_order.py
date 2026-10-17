from pathlib import Path
import json,hashlib,sys
D=Path(__file__).resolve().parent;R=D.parents[3]
p=R/'scripts/gameplay/world/world_main_service_support.gd';b=p.read_bytes();s=p.read_text(encoding='utf-8')
old='''\tfunc request_original_renderer_destruction(service_id: int) -> bool:
\t\tif not _renderer_actors.has(service_id): return false
\t\treturn release_presented_actor_at_original_free(int(_renderer_actors[service_id].runtime_id)).get("status") == "READY"'''
new='''\tfunc request_original_renderer_destruction(service_id: int) -> Dictionary:
\t\tif not _renderer_actors.has(service_id): return {"status":"INVALID","error":"actual_captured_renderer_service_required"}
\t\tvar actor_id: int = int(_renderer_actors[service_id].runtime_id)
\t\tvar scope: RefCounted = _core.get_ref().get("_actor_scopes").get(actor_id)
\t\t# Closing SERVICE may run before Root's original subtree exit. Do not
\t\t# invoke the strict Node-retirement port early and latch its INVALID.
\t\t# The original callback dispatcher alone completes this same scope.
\t\tif scope != null and not scope.exit_callbacks_complete: return {"status":"PENDING","error":"actual_original_actor_exit_pending","service_id":service_id}
\t\treturn release_presented_actor_at_original_free(actor_id)'''
assert s.count(old)==1;s=s.replace(old,new)
old='\t\tvar receipt: Dictionary = _actor_free[id].receipt'
assert s.count(old)==1;s=s.replace(old,'\t\tif not _actor_free[id].failure.is_empty(): return _actor_free[id].failure\n'+old)
q=R/'scripts/gameplay/world/world_live_close_phase.gd';qb=q.read_bytes();qs=q.read_text(encoding='utf-8')
old='\t\t\t\tif not _renderer.request_original_renderer_destruction(id): return _observe_pending_renderer("actor_free_call",id)'
new='''\t\t\t\tvar destruction: Dictionary = _renderer.request_original_renderer_destruction(id)
\t\t\t\tif destruction.get("status") in ["PENDING","BUSY","BACKPRESSURE"]: return _observe_pending_renderer(str(destruction.get("error","actor_free_call")),id)
\t\t\t\t# A genuine canonical/physical failure remains a failure, never a
\t\t\t\t# false boolean silently retried forever as pending close progress.
\t\t\t\tif destruction.get("status") != "READY": return {"status":"INVALID","error":"actual_renderer_destruction_failed","phase":_phase,"service_id":id,"actual_failure":destruction}'''
assert qs.count(old)==1;qs=qs.replace(old,new)
sys.path.insert(0,str(R/'outputs/v115_multicore/actor_runtime_ports_20261014/parser_runtime'))
from gdtoolkit.parser import parser
parser.parse(s,gather_metadata=True);parser.parse(qs,gather_metadata=True)
if '--preview' in sys.argv:
    (D/'world_main_service_support.exit_order_candidate.gd').write_text(s,encoding='utf-8')
    (D/'world_live_close_phase.exit_order_candidate.gd').write_text(qs,encoding='utf-8')
    print('AST PASS, actual request+sole caller migrated together; strict ViewTransport guard unchanged; R unchanged');raise SystemExit(0)
proof=json.loads((R/'outputs/v115_multicore/invocations/codex_full_world_exact_pending_20261018_38/PROTECTION.json').read_text(encoding='utf-8-sig'));assert proof['source_unchanged'] and proof['real_index_preserved']
rows=[]
for f,before,after in [(p,b,s),(q,qb,qs)]:
    (D/(f.stem+'.before_renderer_exit_order.gd')).write_bytes(before);f.write_text(after,encoding='utf-8',newline='\n')
    rows.append({'path':f.relative_to(R).as_posix(),'before':hashlib.sha256(before).hexdigest(),'after':hashlib.sha256(f.read_bytes()).hexdigest()})
m=R/'outputs/v115_multicore/root_integration_20261014/SEMANTIC_SOURCE_INPUTS.json';j=json.loads(m.read_text(encoding='utf-8-sig'))
for item in rows:
    targets=[x for x in j['targets'] if x['path']==item['path']];assert len(targets)==1;targets[0]['sha256']=item['after']
m.write_text(json.dumps(j,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
(D/'RENDERER_EXIT_ORDER_FIX_REVIEW.json').write_text(json.dumps({'status':'NOT_RUN','RED':'WORLD38_RENDERER_INVALID_RED.json; original early INVALID123232109us before Root_after_children123419549us','scope':'defer actual producer until same original Source scope exit callbacks complete; preserve strict port rejection and genuine INVALID; no timers, callback replay, death/XP/drop or Native changes','files':rows},indent=2)+'\n',encoding='utf-8');print('Renderer producer exit-order fix applied; actual World regression required')
