from pathlib import Path
import json,hashlib,shutil

root=Path.cwd()
old=root/'docs/review/framework_child_chain_admission_20261004'
dest=root/'docs/review/framework_periodic_retirement_20261004'
owned=root/'outputs/framework_v2/chain_state_pool_20261004'
def read(path): return json.loads(path.read_text(encoding='utf-8-sig'))
a=read(old/'native/child_chain_admission_final_world_145130_775640/framework/feature_resource_natural_test.result.json')
b=read(dest/'native/chain_state_pool_final_world_153938_120599/framework/feature_resource_natural_test.result.json')
path='tests/framework/natural_effect_lifecycle_test.gd'
first=read(old/'SOURCE_MANIFEST.json')['files'][path]
second=read(dest/'SOURCE_MANIFEST.json')['files'][path]
assert first==second==hashlib.sha256((root/path).read_bytes()).hexdigest()
deaths=lambda r: sum(c['label'].startswith('world death signal is unique:') for c in r['checks'])
reward=lambda r: [c['label'] for c in r['checks'] if c['label'].startswith('canonical rewards equal the exact sum')]
assert a['count']-b['count']==2*(deaths(a)-deaths(b))==2
detail={'unchanged_test_path':path,'unchanged_test_sha256':first,
    'old_checks':a['count'],'current_checks':b['count'],'old_unique_world_and_fixture_deaths':deaths(a),
    'current_unique_world_and_fixture_deaths':deaths(b),'old_reward_check':reward(a),
    'current_reward_check':reward(b),'explanation':'Each actually observed unique death adds uniqueness and bounded-observation checks; world victims outside the fixed thirty may differ. The thirty fixture identity/source and 360 delivery gates are unchanged. No assertion was removed or weakened.'}
(dest/'FINAL_CHECK_COUNT_CHANGE.json').write_text(json.dumps(detail,indent=2)+'\n',encoding='utf-8')
note=(f'\n\n检查数量补充：旧resource natural回执{a["count"]}项，本轮{b["count"]}项，脚本SHA完全相同。除指定30测试怪外的自然世界死亡数使本次总观测由{deaths(a)}变为{deaths(b)}，每一真实死亡追加唯一性与有界观察两项，故检查少2；奖励分别按真实唯一死亡逐项核对。指定30 ActorRef各3source、360实际投递及全部固定门禁未删减，详见FINAL_CHECK_COUNT_CHANGE.json。最终1420为本轮实际完整回执总数，不写成理论加算1422。\n')
for path in (dest/'README.md',root/'docs/source176_r3/PERIODIC_RETIREMENT_WORKLOG_20261004.md'):
    with path.open('a',encoding='utf-8') as f: f.write(note)
shutil.copy2(owned/'explain_final_counts.py',dest/'explain_final_counts.py')
print(json.dumps(detail))
