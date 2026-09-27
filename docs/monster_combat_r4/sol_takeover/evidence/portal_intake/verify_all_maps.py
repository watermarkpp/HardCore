"""Read-only formal network audit and exact publication protection checks."""
import json, pathlib
ROOT = pathlib.Path(__file__).resolve().parents[5]
OUT = pathlib.Path(__file__).parent
def read(path): return json.loads(path.read_text(encoding='utf-8-sig'))
identity = read(ROOT/'assets/data/map_design/map_identity_registry.json')['maps']
before = read(OUT/'before_publication.json')
targets = set(before['sources'])
failures, sources, runtimes, endpoints = [], {}, {}, {}
for entry in identity:
    key = entry['map_id']
    source = read(ROOT/f'map_editor_workspace/{key}/{key}.editor.json')
    runtime = read(ROOT/f'assets/data/runtime/map_editor/{key}.runtime.json')
    sources[key], runtimes[key] = source, runtime
    for endpoint in runtime['semantics']['map_exit_points']:
        ident = key + '::' + endpoint['semantic_id']
        assert ident not in endpoints
        endpoints[ident] = endpoint
counts = {'maps':len(identity), 'endpoints':len(endpoints), 'active':0,'arrival_only':0,'source_linked_unconfigured':0}
for ident, endpoint in endpoints.items():
    if endpoint.get('arrival_only',False):
        counts['arrival_only'] += 1
        if endpoint.get('target_configured',True) or endpoint.get('trigger_on_enter',True): failures.append(ident+':arrival_trigger')
        continue
    counts['active'] += 1
    target_key = endpoint.get('target_map_key','')
    target = endpoints.get(target_key+'::'+endpoint.get('target_portal_id',''))
    if not endpoint.get('target_configured',False): failures.append(ident+':runtime_unconfigured')
    if not target: failures.append(ident+':target_missing'); continue
    if endpoint.get('target_tile') != target.get('tile'): failures.append(ident+':target_tile')
    if endpoint.get('target_map_id') != runtimes[target_key]['source']['runtime_map_id']: failures.append(ident+':target_map_identity')
    if endpoint.get('one_way',False):
        if not target.get('arrival_only',False): failures.append(ident+':one_way_target')
    else:
        key, portal_id = ident.split('::')
        if target.get('target_map_key') != key or target.get('target_portal_id') != portal_id: failures.append(ident+':reciprocal')
    for field, value in [('arrival_reentry_policy_id','portal_arrival_guard_v2'),('travel_request_single_flight',True),('return_minimum_seconds',3.0),('return_unlock_distance_gu',1.5)]:
        if endpoint.get(field) != value: failures.append(ident+':'+field)
for key, source in sources.items():
    for endpoint in source['layers'].get('map_exit_points',[]):
        if not endpoint.get('arrival_only',False) and endpoint.get('target_map_key') and endpoint.get('target_portal_id') and endpoint.get('target_map_id',-1)>0 and not endpoint.get('target_configured',False):
            counts['source_linked_unconfigured'] += 1
            failures.append(key+'::'+endpoint['semantic_id']+':authoring_unconfigured')
for key in targets:
    old, new = before['sources'][key], sources[key]
    for field in old:
        if field not in ('layers','editor_meta') and old[field] != new[field]: failures.append(key+':source_changed:'+field)
    for lane in old['layers']:
        if lane != 'map_exit_points' and old['layers'][lane] != new['layers'][lane]: failures.append(key+':source_lane_changed:'+lane)
    for field in old['editor_meta']:
        if field != 'revision' and old['editor_meta'][field] != new['editor_meta'][field]: failures.append(key+':source_meta_changed:'+field)
    oldrt, newrt = before['runtime'][key+'.runtime'], runtimes[key]
    for field in ['design','ground','instances']:
        if oldrt[field] != newrt[field]: failures.append(key+':runtime_changed:'+field)
    a,b = json.loads(json.dumps(oldrt['collision'])), json.loads(json.dumps(newrt['collision']))
    a.get('navigation',{}).pop('canonical_catalog_sha256',None)
    b.get('navigation',{}).pop('canonical_catalog_sha256',None)
    if a!=b: failures.append(key+':collision_geometry_changed')
    for lane in oldrt['semantics']:
        if lane != 'map_exit_points' and oldrt['semantics'][lane] != newrt['semantics'][lane]: failures.append(key+':runtime_lane_changed:'+lane)
old_registry={entry['map_key']:entry for entry in before['registry']['maps']}
new_registry={entry['map_key']:entry for entry in read(ROOT/'assets/data/runtime/map_editor/map_runtime_release_registry.json')['maps']}
for key in old_registry:
    if key not in targets and old_registry[key]!=new_registry[key]: failures.append(key+':sibling_registry_changed')
result={'status':'PASS' if not failures else 'FAIL','counts':counts,'failures':failures,'publication_targets':sorted(targets),'protected_sibling_registry_entries':len(old_registry)-len(targets)}
(OUT/'all_map_audit_and_protection.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps(result,ensure_ascii=False))
raise SystemExit(bool(failures))
