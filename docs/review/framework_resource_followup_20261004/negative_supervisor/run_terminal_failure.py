"""Own the one imported-cache fault; preserve raw runner FAIL and restore bytes."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[3]
OWNED = Path(__file__).resolve().parent
CACHE = ROOT / '.godot/imported/Items_00014.png-1c66ca0142223b1fe999bb38a562b0d9.ctex'
if not CACHE.resolve().is_relative_to((ROOT / '.godot/imported').resolve()):
    raise SystemExit('cache path escaped this worktree')
if CACHE.is_symlink() or (ROOT / '.godot').is_symlink() or (ROOT / '.godot/imported').is_symlink():
    raise SystemExit('refuse shared imported-cache linkage')
original = CACHE.read_bytes()
stamp = datetime.now(timezone.utc).strftime('%H%M%S_%f')
backup = OWNED / ('cache_before_' + stamp + '.bin')
backup.write_bytes(original)
record = {'cache':str(CACHE),'backup':str(backup),'size':len(original),
          'before_sha256':hashlib.sha256(original).hexdigest(),
          'time_utc':datetime.now(timezone.utc).isoformat()}
try:
    command = [sys.executable, str(ROOT / 'tools/source176_r3_validation.py'),
               'feature_resource_terminal_failure_negative', '--tests',
               'tests/framework/feature_resource_terminal_failure_test.tscn','--timeout','30']
    record['command'] = command
    native = subprocess.run(command, cwd=ROOT, env=os.environ.copy(),capture_output=True,text=True,encoding='utf-8',errors='replace')
    print(native.stdout)
    print(native.stderr)
    record['wrapper_exit'] = native.returncode
    for line in native.stdout.splitlines():
        try:
            result = json.loads(line)
        except json.JSONDecodeError:
            continue
        if 'evidence' in result:
            record['runner_evidence'] = result['evidence']
finally:
    record['after_native_sha256'] = hashlib.sha256(CACHE.read_bytes()).hexdigest()
    CACHE.write_bytes(original)
    record['restored_sha256'] = hashlib.sha256(CACHE.read_bytes()).hexdigest()
    record['restored'] = record['restored_sha256'] == record['before_sha256']
    (OWNED / ('cache_restore_' + stamp + '.json')).write_text(json.dumps(record,indent=2),encoding='utf-8')
if 'runner_evidence' in record:
    evidence = Path(record['runner_evidence'])
    def read(name): return json.loads((evidence/name).read_text(encoding='utf-8-sig'))
    validation, report = read('validation.json'), read('runner_results.json')
    receipt = read('framework/feature_resource_terminal_failure_test.result.json')
    before, after = read('before.json'), read('after.json')
    row = report['results'][0]
    expected = [
        'ERROR: Compressed texture file is corrupt (Bad header).',
        'ERROR: Failed loading resource: res://.godot/imported/Items_00014.png-1c66ca0142223b1fe999bb38a562b0d9.ctex.',
        'ERROR: Failed loading resource: res://assets/art/items/service/inventory/client.classic_raw_complete/Items_00014.png.'
    ]
    logs_valid = True
    observed = {}
    for suffix in ('stderr','godot'):
        data=(evidence/'raw'/('feature_resource_terminal_failure_test.'+suffix+'.log')).read_bytes()
        text=data.decode('utf-16') if data[:2] in (b'\xff\xfe',b'\xfe\xff') else data.decode('utf-8-sig',errors='replace')
        errors=[line for line in text.splitlines() if line.startswith('ERROR:')]
        observed[suffix] = errors
        logs_valid &= errors == expected and 'SCRIPT ERROR:' not in text and 'Parse Error:' not in text
    valid = logs_valid and len(report['results']) == 1 and report['failed'] == 1 and row['result'] == 'FAIL'
    valid &= not row['timeout'] and row['process_exited'] and row['effective_exit_code'] == 0 and row['wrapper_exit_code'] == 0
    valid &= row['reason'] == 'stderr_failures_3;engine_log_failures_3' and row['framework_receipt_valid']
    valid &= receipt['status'] == 'PASS' and receipt['failed'] == 0 and receipt['count'] == 15 and all(c['passed'] for c in receipt['checks'])
    valid &= receipt['run_id'] == row['framework_run_id'] and receipt['invocation_id'] == report['invocation_id']
    valid &= receipt['source_content_sha256'] == before['content_set_sha256'] and before['files'] == after['files']
    valid &= validation['source_stable_during_run'] and record['restored'] and record['after_native_sha256'] == record['before_sha256']
    gate = {'status':'PASS' if valid else 'FAIL','runner_status':'FAIL','expected_engine_error_negative':True,
            'source_content_sha256':before['content_set_sha256'],'run_id':receipt['run_id'],
            'invocation_id':report['invocation_id'],'business_checks':receipt['count'],'observed_errors':observed,
            'cache_restore':record,'scope':'Expected corrupt-import negative only; original runner FAIL preserved unchanged.'}
    (OWNED/('terminal_failure_gate_'+stamp+'.json')).write_text(json.dumps(gate,indent=2),encoding='utf-8')
    print(json.dumps({'expected_error_gate':gate['status'],'runner_status':'FAIL','business_checks':receipt['count'],'evidence':str(evidence)}))
print(json.dumps(record))
raise SystemExit(native.returncode)
