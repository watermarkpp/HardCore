extends Node

# TEMPORARY diagnostic (ignored path, not part of the test suite).
# Measures the real production READY timeline for the two failing startup
# fixtures. Read-only observation: no production file is modified and no
# deadline/assertion of any existing test is changed.

var _t0_ms := 0
var _game: Node = null
var _last_stage := -1
var _stage_times := {}
var _ready_ms := -1
var _transition_closed_ms := -1


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	_t0_ms = Time.get_ticks_msec()
	_game = load("res://scenes/main.tscn").instantiate()
	add_child(_game)


func _process(_delta: float) -> void:
	if _game == null:
		return
	var elapsed := Time.get_ticks_msec() - _t0_ms
	var coord: Variant = _game.get("_world_bootstrap_coordinator")
	var stage := -1
	if coord != null:
		stage = int(coord.get("stage"))
	if stage != _last_stage:
		_stage_times[str(stage)] = elapsed
		print("DIAG stage=%d at=%dms" % [stage, elapsed])
		_last_stage = stage
	var transition: bool = bool(_game.get("_map_transition_in_progress"))
	if not transition and _transition_closed_ms < 0:
		_transition_closed_ms = elapsed
		print("DIAG transition_closed at=%dms" % elapsed)
	var enabled: bool = _game.gameplay_input_is_enabled()
	if enabled and _ready_ms < 0:
		_ready_ms = elapsed
		print("DIAG READY_INPUT_ENABLED at=%dms stage=%d" % [_ready_ms, stage])
	if _ready_ms >= 0 and elapsed > _ready_ms + 2000:
		_finish()
	elif elapsed > 60000:
		print("DIAG TIMEOUT stage=%d transition=%s enabled=%s" % [stage, str(transition), str(enabled)])
		if coord != null:
			print("DIAG last_failure=" + JSON.stringify(coord.get("last_failure")))
			print("DIAG diagnostic=" + JSON.stringify(coord.get("diagnostic")))
		get_tree().quit(1)


func _finish() -> void:
	print("DIAG_STAGE_TIMES " + JSON.stringify(_stage_times))
	print("DIAG_RESULT ready_ms=%d transition_closed_ms=%d" % [_ready_ms, _transition_closed_ms])
	get_tree().quit(0)
