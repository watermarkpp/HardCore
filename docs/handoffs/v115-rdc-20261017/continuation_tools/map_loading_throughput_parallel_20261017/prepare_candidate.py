from pathlib import Path
import hashlib, difflib, json

OUT = Path(__file__).resolve().parent
ROOT = OUT.parents[2]
REL = Path('scripts/gameplay/world/world_map_loading_transport.gd')
source = (ROOT / REL).read_bytes()
assert hashlib.sha256(source).hexdigest() == '3d3eee21b41983fbabd309433556838b604ef16d03223607f986d2a79497f959'
before = source.decode('utf-8').replace('\r\n', '\n')
text = before
substitutions = []
def replace(old, new):
    global text
    assert text.count(old) == 1, (old, text.count(old))
    text = text.replace(old, new)
    substitutions.append({'before':old,'after':new})

replace('var _close_service_sequence := -1\n', '''var _close_service_sequence := -1
# Source-only observations. No timer, queue, publication or gameplay authority.
var _trace_enabled := false
var _trace_job: Dictionary = {}
''')
replace('\t_budget = session.original_frame_budget(); _descriptor = descriptor.duplicate(true); _reservation_usec = reservation_usec\n', '''\t_budget = session.original_frame_budget(); _descriptor = descriptor.duplicate(true); _reservation_usec = reservation_usec
\t_trace_enabled = bool(world.clock_ports.get_setting("hardcore/diagnostics/main_boot_trace", false))
''')
replace('\t_exchange_running = true\n\tvar result: Dictionary = await _exchange_original_map_leaf(operation,arguments)\n\t_exchange_running = false\n', '''\t_exchange_running = true
\t_trace_begin(operation)
\tvar result: Dictionary = await _exchange_original_map_leaf(operation,arguments)
\t_trace_finish(result)
\t_exchange_running = false
''')
replace('\tvar copied: Dictionary = Graph.copy_and_seal(arguments)\n', '''\tvar trace_copy_started: int = Time.get_ticks_usec() if _trace_enabled else 0
\tvar copied: Dictionary = Graph.copy_and_seal(arguments)
\tif _trace_enabled: _trace_job.argument_graph_copy_usec = Time.get_ticks_usec() - trace_copy_started
''')
replace('\twhile int(_budget.snapshot().open_scopes) != 0: await _next_source_p()\n', '''\twhile int(_budget.snapshot().open_scopes) != 0:
\t\t_trace_step("budget_gate", "WAIT_OPEN_SCOPE")
\t\tawait _next_source_p()
\t_trace_step("budget_gate", "READY")
''')
replace('\tvar reservation: Dictionary = _budget.reserve_live("map_loading:" + operation, _budget.LANE_NECESSARY, _reservation_usec)\n', '''\tvar reservation: Dictionary = _budget.reserve_live("map_loading:" + operation, _budget.LANE_NECESSARY, _reservation_usec)
\t_trace_step("budget_reserve", "INVALID" if reservation.is_empty() else "READY")
''')
replace('\t\tvar frozen_event: Dictionary = Graph.copy_and_seal(event)\n', '''\t\tvar trace_event_started: int = Time.get_ticks_usec() if _trace_enabled and not _trace_job.has("first_event_graph_copy_usec") else 0
\t\tvar frozen_event: Dictionary = Graph.copy_and_seal(event)
\t\tif trace_event_started != 0:
\t\t\t_trace_job.first_event_graph_copy_usec = Time.get_ticks_usec() - trace_event_started
\t\t\tif frozen_event.ok:
\t\t\t\t# Once only. Godot Variant encoding size, not Native mailbox wire bytes.
\t\t\t\tvar trace_encoding_started: int = Time.get_ticks_usec()
\t\t\t\t_trace_job.request_variant_bytes = var_to_bytes(request).size()
\t\t\t\t_trace_job.request_variant_encoding_usec = Time.get_ticks_usec() - trace_encoding_started
''')
replace('\t\tvar reserved: Dictionary = _host.reserve_original_map_loading_event(ticket,event)\n', '''\t\tvar reserved: Dictionary = _host.reserve_original_map_loading_event(ticket,event)
\t\t_trace_step("reserve", str(reserved.get("status", "MISSING")))
''')
replace('\t\t\t\t\tvar cancelled: Dictionary = _host.cancel_unaccepted_original_map_loading_event(ticket)\n', '''\t\t\t\t\tvar cancelled: Dictionary = _host.cancel_unaccepted_original_map_loading_event(ticket)
\t\t\t\t\t_trace_step("cancel", str(cancelled.get("status", "MISSING")))
''')
replace('\t\t\tvar registered: Dictionary = _session.try_publish_original_event_prefix(_job.event)\n', '''\t\t\tvar registered: Dictionary = _session.try_publish_original_event_prefix(_job.event)
\t\t\t_trace_step("register", str(registered.get("status", "MISSING")))
''')
replace('\t\tvar accepted: Dictionary = _host.accept_original_map_loading_event(_job.identity,_job.event,_job.prefix)\n', '''\t\tvar accepted: Dictionary = _host.accept_original_map_loading_event(_job.identity,_job.event,_job.prefix)
\t\t_trace_step("accept", str(accepted.get("status", "MISSING")))
''')
replace('\t\tvar polled: Dictionary = _host.poll_original_map_loading_event(_job.identity)\n', '''\t\tvar polled: Dictionary = _host.poll_original_map_loading_event(_job.identity)
\t\t_trace_poll(polled)
\t\t_trace_step("poll", str(polled.get("status", "MISSING")))
''')
replace('\t\t\t\tawait _next_source_p()\n\t\t\t\tcontinue\n\t\t\tif int(_budget.snapshot().open_scopes) != 0:\n', '''\t\t\t\t_trace_step("settle_gate", "WAIT_PHASE")
\t\t\t\tawait _next_source_p()
\t\t\t\tcontinue
\t\t\tif int(_budget.snapshot().open_scopes) != 0:
''')
replace('\t\t\tif int(_budget.snapshot().open_scopes) != 0:\n\t\t\t\tawait _next_source_p()\n', '''\t\t\tif int(_budget.snapshot().open_scopes) != 0:
\t\t\t\t_trace_step("settle_gate", "WAIT_OPEN_SCOPE")
\t\t\t\tawait _next_source_p()
''')
replace('\t\t\t# Frozen actual native observation and actual Main elapsed, not time at retry.\n', '''\t\t\t_trace_step("settle_gate", "READY")
\t\t\t# Frozen actual native observation and actual Main elapsed, not time at retry.
''')
replace('\t\t\t\tif charged.is_empty(): return {"status":"INVALID","error":"actual_map_budget_settlement"}\n', '''\t\t\t\t_trace_step("budget_settle", "INVALID" if charged.is_empty() else "READY")
\t\t\t\tif charged.is_empty(): return {"status":"INVALID","error":"actual_map_budget_settlement"}
''')
replace('\t\t\tvar committed: Dictionary = _host.settle_original_map_loading_event_status(_job.identity,_job.settlement)\n', '''\t\t\tvar committed: Dictionary = _host.settle_original_map_loading_event_status(_job.identity,_job.settlement)
\t\t\t_trace_step("settle", str(committed.get("status", "MISSING")))
''')
replace('\t\t\tif _host.retire_original_map_loading_event(_job.identity, _job.reply):\n', '''\t\t\tvar actual_retired: bool = _host.retire_original_map_loading_event(_job.identity, _job.reply)
\t\t\t_trace_step("retire", "READY" if actual_retired else "PENDING_OR_REJECTED")
\t\t\tif actual_retired:
''')

text += '''
# All trace state is scalar, short text, or bounded counters. It never owns a
# request/event/prefix/reply graph, and is discarded at this exchange's return.
func _trace_begin(operation: String) -> void:
\tif not _trace_enabled: return
\tvar now: int = Time.get_ticks_usec()
\tvar frame: Dictionary = _world.current_clock_frame()
\t_trace_job = {"operation":operation,"request_sequence":_serial + 1,
\t\t"started_usec":now,"last_emit_usec":now,"start_epoch":int(frame.get("epoch",-1)),
\t\t"stage":"begin","stage_started_usec":now,"stage_start_epoch":int(frame.get("epoch",-1))}
\t_trace_job.map_id = int(_scope.get("map_id",-1))
\t_trace_job.coordinator_generation = int(_scope.get("coordinator_generation",-1))

func _trace_step(stage: String, status: String) -> void:
\tif not _trace_enabled or _trace_job.is_empty(): return
\tvar now: int = Time.get_ticks_usec()
\t# Even an unexpected Native status cannot create unbounded diagnostic keys.
\tvar bounded_status: String = status if status in ["READY","PENDING","INVALID","MISSING","BACKPRESSURE","SETTLED","WAIT_OPEN_SCOPE","WAIT_PHASE","PENDING_OR_REJECTED"] else "OTHER"
\tvar key: String = "count_" + stage + "_" + bounded_status
\t_trace_job[key] = int(_trace_job.get(key,0)) + 1
\tif not _trace_job.has("first_" + stage + "_epoch"):
\t\t_trace_job["first_" + stage + "_epoch"] = int(_world.current_clock_frame().get("epoch",-1))
\tif _trace_job.stage != stage:
\t\t_trace_job["elapsed_" + str(_trace_job.stage) + "_usec"] = int(_trace_job.get("elapsed_" + str(_trace_job.stage) + "_usec",0)) + now - int(_trace_job.stage_started_usec)
\t\t_trace_job.stage = stage
\t\t_trace_job.stage_started_usec = now
\t\t_trace_job.stage_start_epoch = int(_world.current_clock_frame().get("epoch",-1))
\t_trace_job.last_status = status.left(32)
\tif now - int(_trace_job.last_emit_usec) >= 5000000: _trace_emit(false, "")

func _trace_poll(polled: Dictionary) -> void:
\tif not _trace_enabled or _trace_job.is_empty() or polled.get("status") != "READY" or _trace_job.has("native_received_usec"): return
\t# These are the actual Native/Main observations, sampled once per reply.
\t_trace_job.event_ordinal = int(_job.get("identity",{}).get("event_ordinal",-1))
\t_trace_job.fixed_prefix_through = int(_job.get("prefix",{}).get("through_ordinal",-1))
\tfor field: String in ["actual_queue_residence_usec","actual_dispatch_wait_usec","native_received_usec","native_s_poll_epoch","late_result_count"]:
\t\tif polled.get(field) is int: _trace_job[field] = polled[field]
\tif polled.get("deadline_status") is String: _trace_job.deadline_status = str(polled.deadline_status).left(32)
\tvar reply: Dictionary = polled.get("reply",{})
\tfor field: String in ["started_usec","finished_usec","actual_Main_CPU_usec"]:
\t\tif reply.get(field) is int: _trace_job["main_" + field] = reply[field]
\tif reply.get("started_usec") is int and reply.get("finished_usec") is int:
\t\t_trace_job.actual_Main_elapsed_usec = int(reply.finished_usec) - int(reply.started_usec)
\tif reply.get("finished_usec") is int and polled.get("native_received_usec") is int:
\t\t_trace_job.reply_observation_delay_usec = int(polled.native_received_usec) - int(reply.finished_usec)

func _trace_finish(result: Dictionary) -> void:
\tif not _trace_enabled or _trace_job.is_empty(): return
\t_trace_emit(true, str(result.get("status", "READY" if result.get("ok") == true else "RESULT_NOT_OK")))
\t_trace_job = {}

func _trace_emit(completed: bool, result_status: String) -> void:
\tvar now: int = Time.get_ticks_usec()
\t_trace_job.last_emit_usec = now
\tvar observation: Dictionary = _trace_job.duplicate(false)
\tvar frame: Dictionary = _world.current_clock_frame()
\tobservation.completed = completed
\tobservation.result_status = result_status.left(32)
\tobservation.elapsed_usec = now - int(_trace_job.started_usec)
\tobservation.epoch = int(frame.get("epoch",-1))
\tobservation.epoch_delta = observation.epoch - int(_trace_job.start_epoch)
\tobservation.phase = str(frame.get("phase", "")).left(32)
\tobservation.current_stage_elapsed_usec = now - int(_trace_job.stage_started_usec)
\tobservation.current_stage_epoch_delta = observation.epoch - int(_trace_job.stage_start_epoch)
\tobservation.open_scopes = int(_budget.snapshot().get("open_scopes",-1))
\tif not _job.is_empty():
\t\tobservation.event_ordinal = int(_job.get("identity",{}).get("event_ordinal",-1))
\t\tobservation.fixed_prefix_through = int(_job.get("prefix",{}).get("through_ordinal",-1))
\t\tobservation.native_sealed = _job.get("native_sealed",false) == true
\t\tobservation.settled = _job.get("settled",false) == true
\t# status() is sampled only at the existing 5s/return boundary, never per P.
\tvar native: Dictionary = _host.status()
\tfor field: String in ["serviced_epoch","pending_epochs","unsettled_original_published_prefixes","original_main_applied_prefix","input_queue_size","deadline_misses","clock_overruns","late_starts"]:
\t\tif native.get(field) is int: observation["native_" + field] = native[field]
\tprint("HC_SOURCE_MAP_EXCHANGE ",JSON.stringify(observation))
'''
pre = OUT / 'preimage' / REL
candidate = OUT / 'candidate' / REL
pre.parent.mkdir(parents=True, exist_ok=True)
candidate.parent.mkdir(parents=True, exist_ok=True)
if pre.exists():
    assert pre.read_bytes() == source, 'Do not rewrite preimage'
else:
    pre.write_bytes(source)
candidate.write_bytes(text.replace('\n', '\r\n').encode('utf-8'))
patch = ''.join(difflib.unified_diff(before.splitlines(True), text.splitlines(True), fromfile='a/'+REL.as_posix(), tofile='b/'+REL.as_posix()))
(OUT / 'map_loading_trace.patch').write_text(patch, encoding='utf-8', newline='\n')
(OUT / 'SUBSTITUTIONS.json').write_text(json.dumps(substitutions,indent=2)+'\n',encoding='utf-8')
(OUT / 'CANDIDATE_BINDING.json').write_text(json.dumps({'production_path':REL.as_posix(), 'preimage_sha256':hashlib.sha256(source).hexdigest(),'candidate_sha256':hashlib.sha256(candidate.read_bytes()).hexdigest(),'patch_sha256':hashlib.sha256(patch.encode()).hexdigest(),'native_aggregate':'58a1b306f62b5d805bd2ff282ab37367cc807e7dd2672c0fb265c2e2289de5f8','runtime_validation':'NOT_RUN','root_cause':'NOT_PROVEN; trace-only candidate'}, indent=2)+'\n',encoding='utf-8')
print(json.dumps(json.loads((OUT / 'CANDIDATE_BINDING.json').read_text()),indent=2))
