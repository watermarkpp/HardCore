import hashlib
import json
from pathlib import Path
import subprocess
import sys

root = Path.cwd()
work = root / 'outputs/wake_drop_v108_review_followup_20261009'
dest = root / 'docs/review/full_project_audit_v109_20261009/evidence/B08_NATIVE'
dest.mkdir(parents=True, exist_ok=True)

def digest(data):
    return hashlib.sha256(data).hexdigest()

def read_json(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))

def keep(data, target):
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists():
        assert target.read_bytes() == data, str(target)
    else:
        target.write_bytes(data)
    return {'path': target.relative_to(root).as_posix(), 'sha256': digest(data), 'bytes': len(data)}

ledger = {'scope': 'B08 native evidence; component scope only, no aggregate APK/device acceptance',
          'stages': [], 'retained_files': [],
          'whole_project_audit': 'MISSING', 'APK109': 'NOT_RUN', 'DEVICE TEST': 'NOT_RUN'}
last = int(sys.argv[1]) if len(sys.argv) > 1 else 62
assert 62 <= last <= 70
for number in range(57, last + 1):
    freeze_path = work / f'B08_NATIVE_FREEZE_{number}.json'
    freeze = read_json(freeze_path)
    stage = root / f'outputs/test_logs/v109_direct{number}_mode_transaction'
    runners = list((stage / 'logs').glob('runner_results_*.json'))
    assert len(runners) == 1, (number, runners)
    runner = read_json(runners[0])
    stage_dest = dest / f'native{number}'
    artifacts = []
    for path in [freeze_path, work / f'B08_NATIVE_SPEC_{number}.json',
                 work / f'B08_NATIVE_FREEZE_{number}_POSTVERIFY.json',
                 work / f'B08_NATIVE{number}_DRIVER.txt']:
        artifacts.append(keep(path.read_bytes(), stage_dest / path.name))
    for path in sorted(stage.rglob('*')):
        if path.is_file():
            artifacts.append(keep(path.read_bytes(), stage_dest / path.relative_to(stage)))
    sources = []
    for path in freeze['changed_paths']:
        # Retain the exact immutable Git blob used by the private source tree.
        # Raw working bytes remain separately bound by the pre/post freeze list.
        data = subprocess.check_output(['git', 'show', freeze['candidate_tree'] + ':' + path])
        sources.append(keep(data, stage_dest / 'source_git_blobs' / path))
    receipts = []
    for result in runner['results']:
        assert result['source_content_sha256'] == digest(freeze_path.read_bytes())
        receipt_path = stage / 'raw' / result['framework_run_id'] / (result['test_name'] + '.result.json')
        item = {'scene': result['test_path'], 'run_id': result['framework_run_id'],
                'receipt': 'MISSING', 'count': 0, 'passed': 0, 'failed': 0}
        if not result['framework_run_id']:
            item['receipt_scope'] = ('Legacy native scene has no framework receipt; '
                                     'retain runner, native exits and complete logs only. '
                                     'No assertion count is inferred.')
        if receipt_path.exists():
            receipt = read_json(receipt_path)
            assert receipt['source_content_sha256'] == digest(freeze_path.read_bytes())
            assert receipt['invocation_id'] == runner['invocation_id']
            assert receipt['run_id'] == result['framework_run_id']
            assert receipt['scene_id'] == result['test_name']
            item.update({k: receipt.get(k) for k in ['status', 'count', 'passed', 'failed']})
            item['receipt'] = receipt_path.relative_to(root).as_posix()
            item['failed_checks'] = [c for c in receipt.get('checks', []) if not c.get('passed', False)]
        trace_sources = []
        run_id = result['framework_run_id']
        if run_id:
            trace_sources = [root / 'outputs/test_logs/framework' /
                             (result['test_name'] + '.' + run_id + '.trace.json'),
                             root / 'outputs/b08_profile_admission_test_20261010/runs' /
                             (run_id + '_' + runner['invocation_id']) / 'PROFILE_ADMISSION_TRACE.json']
        item['producer_traces'] = []
        for trace_path in trace_sources:
            if not trace_path.exists():
                continue
            trace = read_json(trace_path)
            assert trace['run_id'] == run_id
            assert trace['invocation_id'] == runner['invocation_id']
            assert trace['source_content_sha256'] == digest(freeze_path.read_bytes())
            retained = keep(trace_path.read_bytes(), stage_dest / 'producer_traces' /
                            trace_path.parent.name / trace_path.name)
            artifacts.append(retained)
            item['producer_traces'].append(retained)
        receipts.append(item)
    post = read_json(work / f'B08_NATIVE_FREEZE_{number}_POSTVERIFY.json')
    assert post['status'] == 'PASS' and not post['changed_inputs']
    ledger['stages'].append({
        'number': number, 'candidate_tree': freeze['candidate_tree'],
        'actual_input_fingerprint': digest(freeze_path.read_bytes()),
        'input_count': len(freeze['files']), 'engine': freeze['engine'],
        'main_index_sha256': freeze['main_index_sha256'], 'postverification': post['status'],
        'actual_command': {'script': 'tools/run_godot_tests.ps1', 'TestPaths': freeze['scenes'],
                           'TimeoutSeconds': 30, 'Verbose': True},
        'environment': {'GIT_INDEX_FILE': freeze['private_index'],
                        'HARDCORE_R3_CONTENT_SHA256': digest(freeze_path.read_bytes()),
                        'HARDCORE_AUDIT_LOG_ROOT': str(stage / 'logs'),
                        'HARDCORE_AUDIT_EVIDENCE_ROOT': str(stage / 'raw'),
                        'HARDCORE_AUDIT_RUNTIME_APPDATA': str(root / f'.godot/runtime_appdata/v109_direct{number}_mode_transaction')},
        'rerun_reason': read_json(work / f'B08_NATIVE_SPEC_{number}.json')['rerun_reason'],
        'invocation_id': runner['invocation_id'], 'runtime_environment': runner['runtime_environment'],
        'runner': {'total': runner['total'], 'passed': runner['passed'],
                   'failed': runner.get('failed', 0), 'engine_log_errors': runner['engine_log_errors']},
        'native_results': runner['results'], 'receipts': receipts,
        'source_blob_artifacts': sources,
    })
    ledger['retained_files'].extend(artifacts)

target = dest / ('EVIDENCE_LEDGER.json' if last == 62 else f'NATIVE57_{last}_EVIDENCE_LEDGER.json')
assert not target.exists()
target.write_text(json.dumps(ledger, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
print(json.dumps({'path': target.relative_to(root).as_posix(),
                  'stages': [{'number': s['number'], 'runner': s['runner'],
                              'receipts': [{k: r.get(k) for k in ['scene', 'status', 'count', 'passed', 'failed', 'receipt']}
                                           for r in s['receipts']]} for s in ledger['stages']]}, indent=2))
