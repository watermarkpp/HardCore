extends RefCounted
## COMPONENT ONLY: genuine Host.start/native world + real Main close producer.
## No Actor/ProfileModel/save authority or production SourceFrames substitute.
const Budget := preload("res://scripts/gameplay/enemy/enemy_owner_streaming_budget.gd")
const ProfileRuntime := preload("res://scripts/gameplay/profile/profile_runtime_port.gd")
var _host: Object
var _world: Object
var _owner := OS.get_thread_caller_id()
var _budget: RefCounted
var _runtime: RefCounted
var _settings: Dictionary
var _checks: Array[Dictionary] = []
var _baseline: Dictionary = {}
var _signal: Dictionary = {}
var _normal_last_p := -1
var _signals := 0
var _services := 0
var _closing := false
var _healthy := true
var _probe_stage := 0
var _probe_watermarks: Array[int] = []
var _probe_releases: Array[int] = []
var _published_done := false
func _check(value: bool, label: String) -> void:
	_checks.append({"pass":value,"label":label})
	_healthy=_healthy and value
func _init(host: Object, boot: Dictionary) -> void:
	_host=host; _settings=boot.settings
	_host.set_simulation_paused(bool(boot.actual_tree_paused))
	_host.set_simulation_time_scale(float(boot.actual_time_scale))
	_world=ClassDB.instantiate("HardCoreSimulationWorld2D")
	_check(_owner!=OS.get_main_thread_id() and _world.initialize(boot.area),"actual S owner initializes real production native world")
	_budget=Budget.new()
	_check(_budget.configure_owner({"Engine":self,"Time":self,"ProjectSettings":self,"phase":self},self),"unique real FrameBudget configured from actual Host counter and published project settings")
	_runtime=ProfileRuntime.new(self)
func owner_thread_id() -> int: return _owner
func get_process_frames() -> int: return int(_host.current_clock_frame().source_process_frame)
func get_ticks_usec() -> int: return Time.get_ticks_usec()
func get_setting(key: String, default_value: Variant=null) -> Variant: return _settings.get(key,default_value)
func tree_is_paused() -> bool: return _host.current_host_paused()
func profile_world_paused() -> bool: return tree_is_paused()
func original_close_process_signal_highwater() -> int: return _host.original_close_process_signal_highwater()
func fault(code: String, details: Dictionary) -> void: _check(false,code+str(details))
func on_inputs(_domain: String, _packets: Array) -> bool:
	_check(not _closing,"ordinary input never dispatched after actual close request")
	return _healthy
func on_phase(phase: String, frame: Dictionary) -> bool:
	_check(not _closing,"ordinary phase never dispatched during closing")
	if phase=="P_GROUP":
		_normal_last_p=int(frame.source_process_frame)
		if not _runtime.service_process_frame(_normal_last_p): return false
	if phase=="PUBLISH": return _host.publish_snapshot({"ready":true,"done":false},[])
	return _healthy
func _probe_original_resource_wait() -> void:
	_probe_watermarks.append(_host.original_close_process_signal_highwater())
	await _runtime.next_service()
	_probe_releases.append(int(_host.current_clock_frame().actual_main_process_frame))
	_probe_stage=1
	_probe_watermarks.append(_host.original_close_process_signal_highwater())
	await _runtime.next_service()
	_probe_releases.append(int(_host.current_clock_frame().actual_main_process_frame))
	_probe_stage=2
func on_original_close_process_phase(frame: Dictionary) -> bool:
	_check(_closing and frame==_host.current_clock_frame() and frame.closing_session,"closing hook receives immutable actual Host frame on S")
	var p: Dictionary = frame.closing_process_publication
	for key: String in ["epoch","source_physics_frame","h_ordinal","simulation_elapsed"]:
		_check(frame[key]==_baseline[key],"closing leaves actual "+key+" unchanged")
	_check(p.tree_paused==true and p.time_scale==0.5,"always listener captures actual paused Main and original Engine time_scale")
	var token: int = _budget.begin("actual_closing_component",true)
	_check(token>0,"same original budget admits necessary actual phase")
	var state: Dictionary = _budget.snapshot()
	_check(state.epoch==frame.source_process_frame,"budget epoch is real Source P, separate from unchanged Host H epoch")
	if p.phase=="PROCESS_SIGNAL":
		_check(_signal.is_empty(),"pair SIGNAL precedes SERVICE exactly once")
		_check(int(frame.source_process_frame)==_normal_last_p+1+_signals,"normal last P to first closing P and each pair are consecutive")
		_signal={"publication":p,"source_process_frame":frame.source_process_frame,"budget_epoch":state.epoch}
		_signals+=1
		if not _runtime.service_original_close_process_signal(int(frame.source_process_frame),int(frame.actual_main_process_frame),int(frame.published_signal_highwater)): return false
		if _signals==1: _probe_original_resource_wait()
	else:
		_check(p.phase=="NODE_PROCESS_SERVICE" and not _signal.is_empty(),"actual Node SERVICE has a captured SIGNAL")
		_check(_signal.get("source_process_frame")==frame.source_process_frame and _signal.get("budget_epoch")==state.epoch,"same Main pair has one Source P and one shared budget epoch")
		_check(_signal.get("publication",{}).get("main_process_frame")==p.main_process_frame,"SERVICE retains original real Main frame identity")
		_signal={}; _services+=1
	_budget.end(token)
	_check(_budget.snapshot().open_scopes==0,"scope closes synchronously before original await/GC boundary returns")
	if _services>=3 and _probe_stage==2:
		return _publish_final()
	return _healthy
func _publish_final() -> bool:
	for index: int in range(_probe_releases.size()):
		_check(_probe_releases[index]>_probe_watermarks[index],"registered resource await resumes only above actual published SIGNAL watermark")
	var result := {"ready":true,"done":true,"scope":"actual Native closing-P component only; full SourceSession MISSING","checks":_checks,"signals":_signals,"services":_services,"waiters":_runtime.original_resource_service_waiter_count(),"normal_last_p":_normal_last_p}
	_published_done=_host.publish_snapshot(result,[])
	return _healthy and _published_done
func close_session() -> bool:
	if not _closing:
		_closing=true
		_baseline=_host.current_clock_frame()
		_check(int(_baseline.source_process_frame)==_normal_last_p+1,"normal PUBLISH advanced to exactly next-P slot before close")
	if _services<3 or _probe_stage!=2 or not _signal.is_empty() or _runtime.original_resource_service_waiter_count()!=0 or not _published_done: return false
	if _world!=null:
		if not _world.close(): return false
		_world=null
	return _healthy
