import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path.cwd()
PEER = Path('C:/Users/Administrator/Documents/Codex/2026-10-04/task/HC-cue')
AREA = ROOT / 'outputs/framework_v2/periodic_dispatch_20261004/accepted_binding_snapshot'
PEER_AREA = PEER / 'outputs/cue_actor_retirement_20261004'

def load(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def verify_batch(name, successful):
    batch = PEER_AREA / name
    before, after = load(batch / 'before.json'), load(batch / 'after.json')
    summary, runner = load(batch / 'summary.json'), load(batch / 'runner_results.json')
    assert before['files'] == after['files'] and summary['source_stable']
    assert summary['exit_code'] == (0 if successful else 1)
    assert before['engine_sha256'] == 'd8055fb8c7e7f5010d7439ec69be051554055dae55a265f8647bd7301c34161c'
    rows = []
    for scene, count in [('feature_cue_actor_retirement_test', 23), ('feature_cue_actor_retirement_reentry_test', 19)]:
        failures = 0 if successful or scene.endswith('retirement_test') else 4
        receipt_path = batch / 'framework' / (scene + '.result.json')
        receipt = load(receipt_path)
        native = next(row for row in runner['results'] if row['test_name'] == scene)
        assert receipt['count'] == len(receipt['checks']) == count
        assert receipt['failed'] == sum(not row['passed'] for row in receipt['checks']) == failures
        assert [row['id'] for row in receipt['checks']] == list(range(1, count + 1))
        assert receipt['run_id'] == native['framework_run_id']
        assert receipt['invocation_id'] == summary['invocation_id'] == runner['invocation_id']
        assert receipt['source_content_sha256'] == before['content_set_sha256']
        assert native['process_exited'] and not native['timeout']
        assert native['effective_exit_code'] == (1 if failures else 0)
        assert native['result'] == receipt['status'] == ('FAIL' if failures else 'PASS')
        if failures:
            assert not native['framework_receipt_valid'] and 'framework_checks_failed' in native['reason']
        else:
            assert native['framework_receipt_valid']
        assert '/.godot/runtime_appdata/' in native['runtime_appdata'].replace('\\', '/')
        logs = []
        for path in sorted((batch / 'raw').glob(scene + '.*.log')):
            text = path.read_text(encoding='utf-8-sig')
            assert 'ERROR:' not in text and 'SCRIPT ERROR:' not in text
            logs.append({'path': str(path), 'sha256': sha(path), 'warning': 'WARNING:' in text})
        assert len(logs) == 3
        rows.append({'scene': scene, 'checks': count, 'failed_checks': failures,
                     'native_exit': native['effective_exit_code'], 'run_id': receipt['run_id'],
                     'receipt_sha256': sha(receipt_path), 'logs': logs,
                     'failed_records': [row for row in receipt['checks'] if not row['passed']]})
    return {'path': str(batch), 'source': before['content_set_sha256'],
            'source_file_count': len(before['files']), 'invocation_id': summary['invocation_id'],
            'summary_sha256': sha(batch / 'summary.json'), 'rows': rows}

red = verify_batch('red_20261004T171345Z_ef588a64', False)
green = verify_batch('green_20261004T172103Z_2cab5ea9', True)
record = load(PEER_AREA / 'presentation_port.gd.patch_record_20261004T172035Z.json')
original = Path(record['backup_path'])
current = ROOT / record['file_relative_path']
candidate = PEER / record['file_relative_path']
assert sha(original) == record['before_sha256'] and sha(candidate) == record['after_sha256']
assert current.read_text(encoding='utf-8-sig') == original.read_text(encoding='utf-8-sig')
old = '\tactor.add_child(cue)\n\t_nodes[handle] = weakref(cue)'
new = '\n'.join(['\t# Tree-entry notifications may synchronously retire or replace this onset.',
                 '\t# Publish ownership before attaching, then qualify it again before audio.',
                 '\t_nodes[handle] = weakref(cue)', '\tactor.add_child(cue)',
                 '\tif not is_instance_valid(cue) or not _nodes.has(handle) ' + chr(92),
                 '\t\tor not is_same(_nodes[handle].get_ref(), cue) or cue.is_queued_for_deletion():',
                 '\t\treturn true'])
text = current.read_text(encoding='utf-8-sig')
assert text.count(old) == 1 and text.replace(old, new) == candidate.read_text(encoding='utf-8-sig')
red_files = load(Path(red['path']) / 'before.json')['files']
green_files = load(Path(green['path']) / 'before.json')['files']
assert red_files.keys() == green_files.keys()
assert [path for path in red_files if red_files[path] != green_files[path]] == [record['file_relative_path']]
for path, digest in green_files.items():
    assert sha(PEER / path) == digest, path
result = {'status': 'PASS', 'read_utc': datetime.now(timezone.utc).isoformat(),
          'classification': 'Primary verified peer native RED/GREEN and exact minimal candidate; root integration NOT_RUN',
          'primary_port_before_sha256': sha(current), 'peer_port_before_sha256': sha(original),
          'peer_port_after_sha256': sha(candidate), 'newline_note': 'Root LF versus peer CRLF; normalized source is identical before the exact seven-line transformation. Raw SHA values remain distinct.',
          'runner_note': 'Business RED correctly has framework_receipt_valid=false; full raw receipt independently verified, original suite remains FAIL.',
          'primary_production_file_unchanged': True, 'red': red, 'green': green}
(AREA / 'CUE_PEER_RED_GREEN_CHECK.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(json.dumps({'status': 'PASS', 'red': [(r['scene'], r['checks'], r['failed_checks']) for r in red['rows']],
                  'green': [(r['scene'], r['checks'], r['failed_checks']) for r in green['rows']],
                  'primary_port_unchanged': True}))
