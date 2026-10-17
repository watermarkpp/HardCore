"""Static protocol projection only. No Git, Godot, Host or fake ACK execution."""
from pathlib import Path
import hashlib, json, re, sys

OUT = Path(__file__).resolve().parent
ROOT = OUT.parents[2]
REL = Path('scripts/gameplay/world/world_map_loading_transport.gd')
INDEX = Path('C:/Users/Administrator/Documents/HardCore/.git/worktrees/HardCore1/index')
EXPECTED_INDEX = '3180f91855b8bc8d7a22848592ff9f95f2d19574a73f7a3eea90e962f7151b22'
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
checks = []
def check(label, condition):
    checks.append({'label':label,'status':'PASS' if condition else 'FAIL'})
    return condition

index_before = sha(INDEX)
source_before = sha(ROOT / REL)
candidate = (OUT/'candidate'/REL).read_text(encoding='utf-8')
preimage = (OUT/'preimage'/REL).read_text(encoding='utf-8')
subs = json.loads((OUT/'SUBSTITUTIONS.json').read_text(encoding='utf-8'))
marker = '# All trace state is scalar, short text, or bounded counters.'

def project_original(value):
    value = value.split(marker)[0].rstrip()+'\n'
    for row in reversed(subs):
        if value.count(row['after']) != 1:
            return None
        value = value.replace(row['after'],row['before'])
    return value

projected = project_original(candidate)
check('exact original code projection after removing declared diagnostic hunks',projected == preimage)
check('production source still equals captured preimage', source_before == sha(OUT/'preimage'/REL))
check('actual parent index has expected protected bytes',index_before == EXPECTED_INDEX)
# Confirm the projection check actually detects edits to the production protocol.
mutations = {
 'reserve invocation change':('_host.reserve_original_map_loading_event(ticket,event)','_host.reserve_original_map_loading_event(ticket,{})'),
 'added extra accept call':('var accepted: Dictionary = _host.accept_original_map_loading_event(', '_host.accept_original_map_loading_event(_job.identity,_job.event,_job.prefix)\n\t\tvar accepted: Dictionary = _host.accept_original_map_loading_event('),
 'P retry removed':('\t\tawait _next_source_p()\n\treturn {"status":"INVALID","error":"unreachable_map_reply_loop_exit"}', '\t\tpass\n\treturn {"status":"INVALID","error":"unreachable_map_reply_loop_exit"}'),
 'settlement failure softened':('"error":"actual_map_budget_settlement"','"error":"changed_contract"'),
 'budget lane changed':('_budget.LANE_NECESSARY','_budget.LANE_BACKGROUND'),
 'prefix acceptance branch changed':('if accepted.get("status") == "READY":','if accepted.get("status") != "INVALID":'),
}
for label,(old,new) in mutations.items():
    check('negative: '+label+' detected',old in candidate and project_original(candidate.replace(old,new,1)) != preimage)

helpers = candidate.split(marker)[1]
original_calls = re.findall(r'(?:_host|_session|_budget|journal|Graph)\.[A-Za-z_]+\(',preimage)
projected_calls = re.findall(r'(?:_host|_session|_budget|journal|Graph)\.[A-Za-z_]+\(',projected or '')
check('all original Native/Session/Budget/Journal/Graph calls retain exact lexical order and counts',original_calls == projected_calls)
check('all original await expressions retain exact lexical order and count', re.findall(r'await[^\n]+',preimage) == re.findall(r'await[^\n]+',projected or ''))
check('diagnostic helpers have no await/timer/queue/signal/physics work', not re.search(r'\bawait\b|create_timer\(|\.emit\(|\.append\(|\.push_|\.reserve_|\.accept_|\.settle_|\.retire_|\.publish_|\.poll_',helpers))
check('trace defaults disabled', 'var _trace_enabled := false' in candidate)
check('trace uses existing published source clock setting', 'world.clock_ports.get_setting("hardcore/diagnostics/main_boot_trace", false)' in candidate)
check('single diagnostic job dictionary cleared on exchange return','_trace_job = {}' in helpers and '_trace_finish(result)\n\t_exchange_running = false' in candidate)
check('only one request size encoding site', candidate.count('var_to_bytes(request)') == 1)
check('request size encoding only on first successful event graph copy', 'if trace_event_started != 0:' in candidate and 'if frozen_event.ok:' in candidate)
check('request size encoding time separate from original graph copy time','request_variant_encoding_usec' in candidate and 'first_event_graph_copy_usec' in candidate)
check('request size accurately labeled non-Native wire bytes', 'not Native mailbox wire bytes' in candidate)
check('Native status only in infrequent emitter',helpers.count('_host.status()') == 1 and '_host.status()' in helpers.split('func _trace_emit')[1])
check('bounded statuses and OTHER bucket', 'else "OTHER"' in helpers and '"count_" + stage + "_" + bounded_status' in helpers)
check('5-second emit gate and unconditional completion summary', '>= 5000000: _trace_emit(false, "")' in helpers and '_trace_emit(true,' in helpers)
check('actual polling/Main costs captured once','_trace_job.has("native_received_usec")' in helpers and 'actual_Main_CPU_usec' in helpers and 'actual_queue_residence_usec' in helpers and 'actual_dispatch_wait_usec' in helpers)
check('no diagnostic copying of original request/event/prefix/reply graphs',not re.search(r'Graph\.copy|\.duplicate\(true\)|_trace_job\[.*\]\s*=\s*(?:reply|polled|_job)\s*$',helpers,re.M))
check('all diagnostic stages have literal fixed names', all(m.group(1) in ['budget_gate','budget_reserve','reserve','cancel','register','accept','poll','settle_gate','budget_settle','settle','retire'] for m in re.finditer(r'_trace_step\("([^\"]+)"',candidate)))
check('Native retire boolean evaluated exactly once',candidate.count('_host.retire_original_map_loading_event(') == 1 and 'if actual_retired:' in candidate)
check('no trailing whitespace added',not any(line.rstrip()!=line for line in candidate.splitlines()))

check('parent source unchanged after static validation',sha(ROOT/REL)==source_before)
check('parent index unchanged after static validation',sha(INDEX)==index_before)
report = {
 'scope':'STATIC_PROTOCOL_PROJECTION_ONLY',
 'status':'PASS' if all(r['status']=='PASS' for r in checks) else 'FAIL',
 'checks':len(checks),'failed':sum(r['status']=='FAIL' for r in checks),
 'details':checks,'source_before_sha256':source_before,'source_after_sha256':sha(ROOT/REL),
 'index_before_sha256':index_before,'index_after_sha256':sha(INDEX),
 'candidate_sha256':sha(OUT/'candidate'/REL),'preimage_sha256':sha(OUT/'preimage'/REL),
 'Godot_parser':'NOT_RUN','actual_World_trace':'NOT_RUN','performance_cause':'NOT_PROVEN',
 'command':sys.executable+' '+str(Path(__file__).resolve()),
}
(OUT/'STATIC_VALIDATION.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'status':report['status'],'checks':report['checks'],'failed':report['failed']}))
for row in checks:
    if row['status']=='FAIL': print(row['label'])
raise SystemExit(0 if report['status']=='PASS' else 1)
