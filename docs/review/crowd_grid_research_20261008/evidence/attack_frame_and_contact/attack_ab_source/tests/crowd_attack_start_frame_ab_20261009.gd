extends "res://tests/crowd_formal_grid_comparison_20261008.gd"

## ATTACK_START_FRAME_AB: diagnostic comparison only.  A is immediate ordinary
## melee admission; B admits at most one new ordinary melee attempt per actual
## Engine process epoch.  The inherited formal fixture owns the 34/30/48/300
## workload and all existing production diagnostics.
const AttackProbe := preload("res://tests/support/attack_start_frame_probe_20261009.gd")
const OUTPUT_DIR := "res://outputs/crowd_attack_frame_ab_20261009"

var _ab_mode := ""
var _process_samples: Array[Dictionary] = []
var _last_process_usec := 0
var _last_process_physics := -1
var _ab_process_enemy_start: Dictionary = {}
var _ab_enemy_process_samples: Array[Dictionary] = []
var _ab_direct_contract_ok := false
var _binding_failures: Array[String] = []

class SampleBoundary extends Node:
	var fixture: Node
	func _physics_process(_delta: float) -> void:
		if fixture._scaling_sampling and not fixture._ab_window_started:
			fixture._start_ab_window()

var _ab_window_started := false
var _ab_verified_inputs: Dictionary = {}

func _ready() -> void:
	super()
	var boundary := SampleBoundary.new()
	boundary.fixture = self
	boundary.process_physics_priority = -1000001
	add_child(boundary)

func _start_ab_window() -> void:
	_ab_window_started = true
	EnemyActor.reset_attack_ab_diagnostics()
	for actor: EnemyActor in _scaling_enemies:
		actor._attack_ab_clear_pending()
	_process_samples.clear()
	_last_process_usec = 0
	_last_process_physics = Engine.get_physics_frames()

func _physics_process(delta: float) -> void:
	super(delta)
	if _scaling_sampling and not _scaling_tick_samples.is_empty():
		_scaling_tick_samples[-1]["process_epoch"] = Engine.get_process_frames()

func _process(delta: float) -> void:
	super(delta)
	if not _scaling_sampling:
		return
	var now := Time.get_ticks_usec()
	var physics := Engine.get_physics_frames()
	if _last_process_usec > 0:
		_process_samples.append({
			"interval_ms": float(now - _last_process_usec) / 1000.0,
			"physics_steps": maxi(0, physics - _last_process_physics),
			"process_frame": Engine.get_process_frames(),
		})
	_last_process_usec = now
	_last_process_physics = physics

func _run() -> void:
	_ab_mode = OS.get_environment("HARDCORE_ATTACK_AB_MODE").strip_edges().to_lower()
	if _ab_mode not in ["immediate", "queued"]:
		_binding_failures.append("missing_or_invalid_HARDCORE_ATTACK_AB_MODE")
		await _abort_ab_preload()
		return
	if OS.get_environment("HARDCORE_GRID_COMPARISON_MODE").strip_edges().to_lower() != "current":
		_binding_failures.append("HARDCORE_GRID_COMPARISON_MODE_must_be_current")
		await _abort_ab_preload()
		return
	if not _verify_input_manifest():
		await _abort_ab_preload()
		return
	_ab_direct_contract_ok = _direct_contract()
	if not _ab_direct_contract_ok:
		_binding_failures.append("direct_process_epoch_contract_failed")
		await _abort_ab_preload()
		return
	Engine.max_fps = 60
	EnemyActor.configure_attack_ab_mode(_ab_mode)
	EnemyActor.reset_attack_ab_diagnostics()
	await super._run()

func _direct_contract() -> bool:
	var probe := AttackProbe.new()
	probe.reset()
	var source := FileAccess.get_file_as_string("res://scripts/enemy.gd")
	var start := source.find("func _hc_try_start")
	var committed_guard := start >= 0 and source.find("\n\tif _attack_action_active:", start) >= 0 and source.find("\n\tif _attack_action_active:", start) < source.find("_attack_ab_admission_gate", start)
	return (
		probe.admit(100) == "STARTED"
		and probe.admit(100) == "DEFERRED"
		and probe.admit(100) == "DEFERRED"
		and probe.admit(101) == "STARTED"
		and int(probe.snapshot().get("admission_attempts", -1)) == 2
		and committed_guard
	)

func _verify_input_manifest() -> bool:
	var path := ProjectSettings.globalize_path("%s/current_run_inputs.json" % OUTPUT_DIR)
	if not FileAccess.file_exists(path):
		_binding_failures.append("current_run_inputs_missing")
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	if not parsed is Dictionary:
		_binding_failures.append("current_run_inputs_invalid_json")
		return false
	var manifest: Dictionary = parsed
	for key in ["producer_id", "stage", "source_sha256", "engine_sha256", "engine_console_sha256", "environment", "command"]:
		if not manifest.has(key):
			_binding_failures.append("manifest_missing:%s" % key)
	var sources: Dictionary = manifest.get("source_sha256", {})
	if sources.is_empty():
		_binding_failures.append("source_sha256_empty")
	for raw_path: Variant in sources.keys():
		var source_path := str(raw_path)
		var hash_path := source_path if source_path.begins_with("res://") or source_path.is_absolute_path() else "res://%s" % source_path
		var local_path := ProjectSettings.globalize_path(hash_path) if hash_path.begins_with("res://") else hash_path
		if not FileAccess.file_exists(local_path):
			_binding_failures.append("source_missing:%s" % source_path)
			continue
		var actual := FileAccess.get_sha256(hash_path)
		if str(sources[raw_path]).to_lower() != actual.to_lower():
			_binding_failures.append("source_sha256_mismatch:%s" % source_path)
	var environment: Dictionary = manifest.get("environment", {})
	var engine_path := str(manifest.get("engine_path", environment.get("engine_path", "")))
	var console_path := str(manifest.get("engine_console_path", environment.get("engine_console_path", "")))
	for pair in [["engine_sha256", engine_path], ["engine_console_sha256", console_path]]:
		var field := str(pair[0])
		var actual_path := str(pair[1])
		if actual_path.is_empty() or not FileAccess.file_exists(actual_path):
			_binding_failures.append("engine_path_missing:%s" % field)
			continue
		var actual_hash := FileAccess.get_sha256(actual_path)
		if str(manifest.get(field, "")).to_lower() != actual_hash.to_lower():
			_binding_failures.append("engine_sha256_mismatch:%s" % field)
	if str(manifest.get("producer_id", "")).is_empty() or str(manifest.get("stage", "")).is_empty():
		_binding_failures.append("manifest_producer_or_stage_empty")
	for key: String in environment:
		if key.begins_with("HARDCORE_") and OS.get_environment(key) != str(environment[key]):
			_binding_failures.append("environment_mismatch:%s" % key)
	_ab_verified_inputs = manifest
	var evidence_root := OS.get_environment("HARDCORE_ATTACK_AB_EVIDENCE_ROOT")
	if evidence_root.is_empty():
		_binding_failures.append("evidence_root_missing")
	else:
		var binding := FileAccess.open(evidence_root.path_join("PRELOAD_BINDING.json"), FileAccess.WRITE)
		if binding == null:
			_binding_failures.append("binding_write_failed")
		else:
			binding.store_string(JSON.stringify({"status": "PASS" if _binding_failures.is_empty() else "FAIL",
				"producer_id": manifest.get("producer_id"), "source_files_verified": sources.size(),
				"engine": Engine.get_version_info(), "mode": _ab_mode, "failures": _binding_failures}, "\t"))
			binding.close()
	return _binding_failures.is_empty()

func _append_scaling_result(result: Dictionary) -> void:
	var grouped := {}
	for row: Dictionary in _scaling_tick_samples:
		var epoch := int(row.get("process_epoch", -1))
		if not grouped.has(epoch):
			grouped[epoch] = {"process_frame": epoch, "physics_steps": 0, "enemy_physics_usec": 0, "enemy_physics_calls": 0, "new_attacks": 0}
		grouped[epoch]["physics_steps"] += 1
		grouped[epoch]["enemy_physics_usec"] += int(row.get("enemy_physics_usec_delta", 0))
		grouped[epoch]["enemy_physics_calls"] += int(row.get("enemy_physics_calls_delta", 0))
		grouped[epoch]["new_attacks"] += int(row.get("attack_starts_delta", 0))
	var summed_calls := 0
	var summed_usec := 0
	var catchup_epochs := 0
	_ab_enemy_process_samples.clear()
	for epoch: int in grouped:
		_ab_enemy_process_samples.append(grouped[epoch])
		summed_calls += int(grouped[epoch].enemy_physics_calls)
		summed_usec += int(grouped[epoch].enemy_physics_usec)
		if int(grouped[epoch].physics_steps) > 1:
			catchup_epochs += 1
	var ab := EnemyActor.attack_ab_diagnostics()
	var alignment_ok := _scaling_tick_samples.size() == SCALING_SAMPLE_TICKS and summed_calls == int(result.counters.enemy_physics_calls) and summed_usec == int(result.counters.enemy_physics_usec)
	if not alignment_ok:
		_scaling_failures.append("ab_process_physics_counter_alignment_failed")
		result["status"] = "FAIL"
	var potion_healing := 0
	for potion: Dictionary in _potion_inputs:
		potion_healing += maxi(0, int(potion.get("hp_after", 0)) - int(potion.get("hp_before", 0)))
	var intervals: Array[float] = []
	var over_16 := 0
	var over_33 := 0
	for row: Dictionary in _process_samples:
		var interval := float(row.get("interval_ms", 0.0))
		intervals.append(interval)
		if interval > 16.67:
			over_16 += 1
		if interval > 33.33:
			over_33 += 1
	var pending := 0
	var queue_pending := 0
	var queue_ages_usec: Array[int] = []
	var queue_ages_epochs: Array[int] = []
	var committed := 0
	for actor: EnemyActor in _scaling_enemies:
		if not is_instance_valid(actor):
			continue
		if actor._attack_action_active or actor._pending_attack_time >= 0.0:
			pending += 1
		if actor._attack_ab_pending_target != null:
			queue_pending += 1
			queue_ages_usec.append(maxi(0, Time.get_ticks_usec() - actor._attack_ab_pending_started_usec))
			queue_ages_epochs.append(maxi(0, Engine.get_process_frames() - actor._attack_ab_pending_requested_epoch))
		if actor._attack_action_active:
			committed += 1
	result["attack_start_frame_ab"] = {
			"mode": _ab_mode,
			"observed": {
				"admission": ab,
				"queue_end": queue_pending,
				"committed_pending_end": pending,
				"unserved_queue_age_usec": queue_ages_usec,
				"unserved_queue_age_epochs": queue_ages_epochs,
				"committed_end": committed,
				"process_intervals": _stats(intervals),
				"process_interval_over_16_67ms": over_16,
				"process_interval_over_33_33ms": over_33,
				"process_samples": _process_samples,
				"enemy_cpu_by_process": _ab_enemy_process_samples,
				"direct_contract": _ab_direct_contract_ok,
				"whole_physics_cpu": result.get("physics_cpu_ms", {}),
				"enemy_cpu_total_usec": result.counters.enemy_physics_usec,
				"potion_healing_observed_hp_gain": potion_healing,
				"process_counter_alignment": alignment_ok,
				"catchup_epochs": catchup_epochs,
				"inherited_process_cpu": result.get("process_cpu_ms", {}),
				"attacks": result.get("attacks", {}),
				"player_motion": result.get("player_motion", {}),
				"potion_inputs": result.get("potion_inputs", []),
			},
			"missing": ["per_reason_budget_wait_usec", "frame_boundary_partial_interval", "Android_GPU_fps"],
			"contract": {
				"same_process_epoch_max_new_attempts": 1,
				"shared_quota_direct_contract": _ab_direct_contract_ok,
				"formal_catchup_coverage": "PASS" if catchup_epochs > 0 else "NOT_RUN",
				"committed_guard_source_order": _ab_direct_contract_ok,
				"committed_runtime_regression": "NOT_RUN",
			},
		}
	result["attack_start_frame_ab"]["binding_failures"] = _binding_failures
	result["attack_start_frame_ab"]["producer_id"] = _ab_verified_inputs.get("producer_id")
	var evidence_root := OS.get_environment("HARDCORE_ATTACK_AB_EVIDENCE_ROOT")
	var output := FileAccess.open(evidence_root.path_join("raw_report.json"), FileAccess.WRITE)
	if output != null:
		output.store_string(JSON.stringify(result, "\t"))
		output.close()
	else:
		_scaling_failures.append("ab_raw_report_write_failed")
		result["status"] = "FAIL"
	super._append_scaling_result(result)

func _abort_ab_preload() -> void:
	var receipt := {"status": "FAIL", "fixture": "ATTACK_START_FRAME_AB", "failures": _binding_failures,
		"observed": {}, "missing": ["formal_run_not_started"]}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var file := FileAccess.open("%s/preload_failure_%s.json" % [OUTPUT_DIR, _ab_mode if not _ab_mode.is_empty() else "unknown"], FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(receipt, "\t"))
		file.close()
	print("ATTACK_START_FRAME_AB_PRELOAD_FAIL")
	get_tree().quit(1)
