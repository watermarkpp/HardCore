import hashlib
import json
import re
import shutil
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path.cwd()
OUT = ROOT / 'outputs/framework_v2/cue_lifecycle_integration_20261005'
BASE = ROOT / 'outputs/r3_takeover/20260930/validation'
BATCHES = ['periodic_cue_final_world_013906_604728',
           'periodic_cue_final_mixed_service_014147_190573',
           'periodic_cue_final_related_014327_801663']
SOURCE = '04d29b688db3419bd9e19a7161f9d9a36b32d37f5fcad4fffedaec4fdaae577a'

def load(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

rows, scene_ids, runs, warning_scenes = [], set(), set(), set()
shutdown_resource_diagnostics = []
source_files = None
for name in BATCHES:
    batch = BASE / name
    before, after = load(batch / 'before.json'), load(batch / 'after.json')
    validation, runner = load(batch / 'validation.json'), load(batch / 'runner_results.json')
    handoff = load(batch / 'framework/native_handoffs.json')
    assert before['content_set_sha256'] == after['content_set_sha256'] == SOURCE
    assert before['files'] == after['files']
    if source_files is None:
        source_files = before['files']
    assert before['files'] == source_files
    assert before['engine_sha256'] == 'd8055fb8c7e7f5010d7439ec69be051554055dae55a265f8647bd7301c34161c'
    assert validation['status'] == 'PASS' and validation['exit_code'] == 0
    assert validation['source_stable_during_run'] and validation['failed'] == 0
    assert handoff['source_content_sha256'] == SOURCE and handoff['invocation_id'] == runner['invocation_id']
    for native in runner['results']:
        scene = native['test_name']
        assert scene not in scene_ids
        scene_ids.add(scene)
        assert native['result'] == 'PASS' and native['effective_exit_code'] == 0
        assert native['process_exited'] and not native['timeout'] and native['framework_receipt_valid']
        assert all(native[key] == 0 for key in ('stdout_failure_count', 'stderr_failure_count', 'engine_log_failure_count'))
        receipt_path = batch / 'framework' / (scene + '.result.json')
        receipt = load(receipt_path)
        assert receipt['status'] == 'PASS' and receipt['failed'] == 0
        assert receipt['count'] == len(receipt['checks']) and all(x['passed'] for x in receipt['checks'])
        assert [x['id'] for x in receipt['checks']] == list(range(1, receipt['count'] + 1))
        assert receipt['source_content_sha256'] == SOURCE and receipt['invocation_id'] == runner['invocation_id']
        assert receipt['run_id'] == native['framework_run_id'] and receipt['run_id'] not in runs
        runs.add(receipt['run_id'])
        environment = receipt['runtime_environment']
        assert Path(environment['runtime_appdata']).resolve() == Path(native['runtime_appdata']).resolve()
        assert Path(environment['project_root']).resolve() == ROOT.resolve()
        assert Path(environment['user_data_directory']).resolve().is_relative_to((ROOT / '.godot/runtime_appdata').resolve())
        native_proof = handoff['producers'][scene]
        assert native_proof['run_id'] == receipt['run_id'] and native_proof['receipt_sha256'] == sha(receipt_path)
        assert native_proof['effective_exit_code'] == 0 and native_proof['process_exited'] and native_proof['result'] == 'PASS'
        logs = []
        for path in sorted((batch / 'raw').glob(scene + '.*.log')):
            text = path.read_text(encoding='utf-8-sig')
            assert 'SCRIPT ERROR:' not in text
            for line_number, line in enumerate(text.splitlines(), 1):
                if 'ERROR:' in line:
                    # Preserve the runner's existing, cause-specific shutdown
                    # diagnostic; it is not proof that resource lifetime is closed.
                    assert re.fullmatch(r'ERROR: \d+ resources still in use at exit \(run with --verbose for details\)\.', line.strip()), (scene, line)
                    shutdown_resource_diagnostics.append({'scene': scene, 'path': str(path.relative_to(ROOT)),
                                                          'line': line_number, 'text': line})
            if path.name.endswith('.stderr.log') and 'WARNING:' in text:
                warning_scenes.add(scene)
            logs.append({'path': str(path.relative_to(ROOT)), 'sha256': sha(path), 'bytes': path.stat().st_size})
        assert len(logs) == 3
        rows.append({'scene': scene, 'checks': receipt['count'], 'run_id': receipt['run_id'],
                     'invocation_id': receipt['invocation_id'], 'native_exit': 0,
                     'batch': name, 'receipt_sha256': sha(receipt_path), 'runtime_environment': environment, 'logs': logs})

for relative, digest in source_files.items():
    assert sha(ROOT / relative) == digest, relative
# The current natural live receipt has 137 checks, rather than the older
# 135-check phase count. This changes evidence bookkeeping, not assertions.
assert len(rows) == 39 and sum(row['checks'] for row in rows) == 2138

by_scene = {row['scene']: row for row in rows}
archives = []
trace_names = {'combined_effect_lifecycle_test': 'combined_effect_lifecycle_trace.json',
               'natural_effect_lifecycle_test': 'natural_effect_lifecycle_trace.json',
               'feature_resource_natural_test': 'feature_resource_natural_trace.json',
               'feature_mixed_delivery_test': 'feature_mixed_delivery_test.trace.json',
               'feature_mixed_child_resource_test': 'feature_mixed_child_resource_test.trace.json',
               'periodic_refresh_service_boundary_test': 'periodic_refresh_service_boundary_test.trace.json'}
for scene, filename in trace_names.items():
    path = ROOT / 'outputs/test_logs/framework' / filename
    value = load(path)
    assert value['run_id'] == by_scene[scene]['run_id'] and value['source_content_sha256'] == SOURCE
    destination = BASE / by_scene[scene]['batch'] / filename
    shutil.copyfile(path, destination)
    archives.append({'scene': scene, 'path': str(destination.relative_to(ROOT)), 'sha256': sha(destination)})

pairs = []
for live in ['combined_effect_lifecycle_test', 'periodic_credit_safe_logout_test',
             'natural_effect_lifecycle_test', 'feature_resource_natural_test']:
    cold = live.removesuffix('_test') + '_cold_test'
    expected_path = ROOT / 'outputs/test_logs/framework' / (live.removesuffix('_test') + '_expected.json')
    expected = load(expected_path)
    assert expected['producer_run_id'] == by_scene[live]['run_id']
    assert expected['source_content_sha256'] == SOURCE and expected['invocation_id'] == by_scene[live]['invocation_id']
    assert by_scene[cold]['invocation_id'] == by_scene[live]['invocation_id'] and by_scene[cold]['run_id'] != by_scene[live]['run_id']
    destination = BASE / by_scene[live]['batch'] / expected_path.name
    shutil.copyfile(expected_path, destination)
    pairs.append({'live_scene': live, 'producer_run_id': expected['producer_run_id'],
                  'cold_scene': cold, 'cold_run_id': by_scene[cold]['run_id'],
                  'expected_sha256': sha(destination), 'expected_path': str(destination.relative_to(ROOT))})

result = {'status': 'PASS', 'read_utc': datetime.now(timezone.utc).isoformat(),
          'scope': 'Current-source 39 selected native scenes only; broader P6/R3, GPU/Android and exact original v97 B remain open.',
          'source_content_sha256': SOURCE, 'source_file_count': len(source_files),
          'all_current_runtime_files_rehashed': True, 'scene_count': len(rows),
          'complete_checks': sum(row['checks'] for row in rows), 'failed_checks': 0,
          'stderr_warning_scenes': sorted(warning_scenes),
          'shutdown_resource_diagnostics': shutdown_resource_diagnostics,
          'diagnostic_scope_note': 'The exact shutdown resource ERROR is retained under the existing runner rule. Resource/exit lifetime remains open; other ERROR lines and every SCRIPT ERROR are rejected.',
          'artifact_scope_note': 'Only explicit scene rows and matching run/source traces are adopted. Wrapper-copied historical traces are excluded.',
          'producer_cold_pairs': pairs, 'traces': archives, 'rows': rows}
(OUT / 'FINAL_ASSOCIATIONS.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(json.dumps({'status': 'PASS', 'scenes': len(rows), 'checks': result['complete_checks'],
                  'source': SOURCE, 'warnings': result['stderr_warning_scenes'],
                  'shutdown_resource_diagnostics': shutdown_resource_diagnostics, 'cold_pairs': len(pairs)}))
