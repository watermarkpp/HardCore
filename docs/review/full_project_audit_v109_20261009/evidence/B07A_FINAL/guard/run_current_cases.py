import hashlib, json, subprocess, sys
from pathlib import Path
root=Path.cwd(); evidence=root/'outputs/wake_drop_v108_review_followup_20261009/b07a_guard_output_catalog'
policy=root/'assets/data/source_priority_policy.json'; catalog=evidence/'empty_catalog.json'; catalog.write_text(json.dumps({'distributions':[]}),encoding='utf-8')
def run(args):
 p=subprocess.run([sys.executable,'tools/source_priority_guard.py',*args],cwd=root,text=True,capture_output=True)
 return {'exit':p.returncode,'stdout':p.stdout,'stderr':p.stderr}
outside=root/'b07a_current_outside.json'; outside.unlink(missing_ok=True)
outside_result=run(['--policy',str(policy),'--catalog',str(catalog),'authorize','--lane','item_categories','--candidate','hardcore.identity.categories','--output',str(outside)])
inside=evidence/'current_owned.json'; inside.unlink(missing_ok=True)
first=run(['--policy',str(policy),'--catalog',str(catalog),'authorize','--lane','item_categories','--candidate','hardcore.identity.categories','--output',str(inside)])
first_sha=hashlib.sha256(inside.read_bytes()).hexdigest()
second=run(['--policy',str(policy),'--catalog',str(catalog),'authorize','--lane','item_categories','--candidate','hardcore.identity.categories','--output',str(inside)])
third=run(['--policy',str(policy),'--catalog',str(catalog),'authorize','--lane','framework_fixture_items','--candidate','hardcore.framework.fixture','--output',str(inside)])
print(json.dumps({'outside_output':outside_result,'owned_first':first,'owned_first_sha':first_sha,'owned_same_reuse':second,'owned_different_reject':third,'owned_final_sha':hashlib.sha256(inside.read_bytes()).hexdigest()},ensure_ascii=False,indent=2))
outside.unlink(missing_ok=True)
