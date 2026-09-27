"""Exact approved authoring repair; runtime files are published by Godot."""
import json, pathlib, hashlib
ROOT = pathlib.Path(__file__).resolve().parents[5]
TARGETS = ['chiyue_choice_land', 'chiyue_valley_secret_passage_a', 'chiyue_valley_secret_passage_b']
OUT = pathlib.Path(__file__).parent
assert not (OUT/'before_publication.json').exists(), 'one-shot repair: preserve the original snapshot; never rerun over newer authoring'
snapshot = {'sources': {}, 'runtime': {}, 'registry': {}}
registry = json.loads((ROOT/'assets/data/runtime/map_editor/map_runtime_release_registry.json').read_text(encoding='utf-8-sig'))
snapshot['registry'] = registry
for key in TARGETS:
    source = ROOT/f'map_editor_workspace/{key}/{key}.editor.json'
    document = json.loads(source.read_text(encoding='utf-8-sig'))
    snapshot['sources'][key] = document
    for suffix in ['runtime', 'visual']:
        path = ROOT/f'assets/data/runtime/map_editor/{key}.{suffix}.json'
        snapshot['runtime'][f'{key}.{suffix}'] = json.loads(path.read_text(encoding='utf-8-sig'))
(OUT/'before_publication.json').write_text(json.dumps(snapshot, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
for key, original in snapshot['sources'].items():
    document = json.loads(json.dumps(original))
    endpoints = document['layers']['map_exit_points']
    assert len(endpoints) == (3 if key == TARGETS[0] else 2)
    for endpoint in endpoints:
        assert endpoint['target_map_id'] > 0 and endpoint['target_map_key'] and endpoint['target_portal_id']
        assert 'target_configured' not in endpoint
        endpoint['target_configured'] = True
        if endpoint['connection_mode'] == 'one_way':
            endpoint['one_way'] = True
            endpoint['explicit_one_way_reason'] = 'terminal_dungeon_has_no_return_portal'
    document['editor_meta']['revision'] += 1
    source = ROOT/f'map_editor_workspace/{key}/{key}.editor.json'
    source.write_text(json.dumps(document, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
print('PORTAL_AUTHORING_REPAIR seven configured endpoints, two one-way flags; exact three sources')
