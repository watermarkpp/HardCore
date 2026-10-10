import hashlib, importlib.util, json, subprocess, sys, tempfile
from pathlib import Path
root=Path.cwd(); evidence=root/'outputs/wake_drop_v108_review_followup_20261009/b07a_guard_output_catalog'
sha='684824ac7bb59ac903054b26b3435441b8a2f152'
old_source=subprocess.run(['git','show',f'{sha}:tools/source_priority_guard.py'],check=True,capture_output=True,text=True).stdout
(old_file:=evidence/'source_priority_guard_684.py').write_text(old_source,encoding='utf-8')
with tempfile.TemporaryDirectory() as td:
    t=Path(td); catalog=t/'catalog.json'; catalog.write_text(json.dumps({'distributions':[]}),encoding='utf-8')
    policy=root/'assets/data/source_priority_policy.json'
    out=root/'b07a_old_blob_output.json'
    if out.exists(): out.unlink()
    spec=importlib.util.spec_from_file_location('old_guard',old_file); mod=importlib.util.module_from_spec(spec); spec.loader.exec_module(mod); mod.ROOT=root
    def run(*args):
        old=sys.argv; sys.argv=['source_priority_guard_684.py',*args]
        try: return mod.main()
        finally: sys.argv=old
    primary_no_catalog=run('--policy',str(policy),'--catalog',str(t/'missing.json'),'authorize','--lane','item_categories','--candidate','hardcore.identity.categories')
    first=run('--policy',str(policy),'--catalog',str(catalog),'authorize','--lane','item_categories','--candidate','hardcore.identity.categories','--output',str(out))
    first_sha=hashlib.sha256(out.read_bytes()).hexdigest() if out.exists() else None
    second=run('--policy',str(policy),'--catalog',str(catalog),'authorize','--lane','framework_fixture_items','--candidate','hardcore.framework.fixture','--output',str(out))
    second_sha=hashlib.sha256(out.read_bytes()).hexdigest() if out.exists() else None
    out.unlink(missing_ok=True)
print(json.dumps({'git_source_sha':hashlib.sha256(old_source.encode()).hexdigest(),'git_commit':sha,'primary_without_catalog_exit':primary_no_catalog,'old_main_first_output_exit':first,'old_main_second_different_output_exit':second,'first_output_sha':first_sha,'second_output_sha':second_sha,'overwrite_changed_bytes':first_sha != second_sha,'old_source_evidence':str(old_file.relative_to(root))},ensure_ascii=False,indent=2))
