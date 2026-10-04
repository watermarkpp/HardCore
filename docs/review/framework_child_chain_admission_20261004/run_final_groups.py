from pathlib import Path
from datetime import datetime, timezone
import json, os, subprocess, uuid

root = Path.cwd()
assert root == Path(r'C:/Users/Administrator/.codex/worktrees/pluggable-framework-v2/HardCore')
owned = root / 'outputs/framework_v2/child_chain_admission_20261004'
groups = json.loads((owned / 'FINAL_TEST_GROUPS.json').read_text(encoding='utf-8-sig'))
records = []
for group in groups:
    account = root / '.godot/runtime_appdata' / (group['label'] + '_' + uuid.uuid4().hex)
    assert account.is_relative_to(root / '.godot/runtime_appdata')
    env = os.environ.copy()
    env['GIT_OPTIONAL_LOCKS'] = '0'
    env['GIT_INDEX_FILE'] = str(root / 'outputs/framework_v2/publication_closure_20261003/runner.index')
    env['HARDCORE_AUDIT_RUNTIME_APPDATA'] = str(account)
    command = ['py','-3.12','tools/source176_r3_validation.py',group['label'],
               '--tests',*group['tests'],'--timeout',str(group['timeout'])]
    launch = {'group':group['label'],'launcher_pid':os.getpid(),
              'requested_at_utc':datetime.now(timezone.utc).isoformat(),
              'requested_runtime_appdata':str(account),'command':command}
    (owned / (group['label'] + '_launch.json')).write_text(json.dumps(launch,indent=2),encoding='utf-8')
    result = subprocess.run(command,cwd=root,env=env,capture_output=True,text=True,encoding='utf-8')
    (owned / (group['label'] + '_outer.log')).write_text(result.stdout+result.stderr,encoding='utf-8')
    print(result.stdout.strip(),flush=True)
    assert result.returncode == 0, (group['label'],result.returncode,result.stderr)
    summary = json.loads(result.stdout.strip().splitlines()[-1])
    report = json.loads((Path(summary['evidence']) / 'runner_results.json').read_text(encoding='utf-8-sig'))
    handoff = json.loads((Path(summary['evidence']) / 'framework/native_handoffs.json').read_text(encoding='utf-8-sig'))
    assert Path(report['runtime_environment']['runtime_appdata']) == account
    assert report['runtime_environment'] == handoff['runtime_environment']
    assert report['invocation_id'] == handoff['invocation_id']
    receipts = []
    for row in report['results']:
        assert row['wrapper_process_id'] > 0 and row['wrapper_started_utc']
        assert Path(row['runtime_appdata']) == account
        if not row['test_path'].startswith('tests/framework/'): continue
        receipt_path = Path(summary['evidence']) / 'framework' / (row['test_name'] + '.result.json')
        receipt = json.loads(receipt_path.read_text(encoding='utf-8'))
        observed = receipt['runtime_environment']
        assert Path(observed['runtime_appdata']) == account
        assert Path(observed['project_root']) == root
        assert Path(observed['user_data_directory']).is_relative_to(account)
        assert observed['native_process_id'] > 0
        assert receipt['run_id'] == row['framework_run_id']
        assert receipt['invocation_id'] == report['invocation_id']
        receipts.append({'test_path':row['test_path'],'run_id':receipt['run_id'],
                         'native_process_id':observed['native_process_id'],
                         'user_data_directory':observed['user_data_directory']})
    records.append({**launch,'native_invocation_id':report['invocation_id'],
                    'runner_runtime_environment':report['runtime_environment'],
                    'evidence':summary['evidence'],'status':'PASS','framework_receipts':receipts})
    (owned / 'FINAL_RUN_ASSOCIATION.json').write_text(json.dumps(records,ensure_ascii=False,indent=2),encoding='utf-8')
assert len(set(row['requested_runtime_appdata'] for row in records)) == len(groups)
print(json.dumps({'status':'PASS','groups':len(records),'tests':sum(len(g['tests']) for g in groups),
                  'receipt_environment_associations':sum(len(r['framework_receipts']) for r in records)}),flush=True)
