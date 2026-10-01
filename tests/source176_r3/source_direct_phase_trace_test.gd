extends Node2D
const F := preload("res://tests/source176_r3/helpers/runtime_fixture.gd")
const Oracle := preload("res://tests/helpers/source_cadence_reference.gd")
var actor: EnemyActor
var oracle := Oracle.new()
var collecting := false
var next_event := 0
var roll := 0
var start_clock := 0.0
var errors: Array[String] = []
var rows: Array = []
var checks := 0
const TIMES := [.6,1.2,1.5,2.0]
func _ready() -> void:
	process_physics_priority = 10000
	run.call_deferred()
func _physics_process(_delta: float) -> void:
	if not collecting:
		return
	var now := int(actor._combat_action_time_s*1000.0)
	oracle.evaluate(now)
	if next_event<TIMES.size() and actor._combat_action_time_s-start_clock>=TIMES[next_event]:
		# A declared source-message input at real game time. Owner clock and
		# physics remain native; no cadence/cache/position assignment.
		actor.apply_source_direct_magic_walk_delay(roll)
		oracle.postpone(800+roll)
		rows.append({"tick":Engine.get_physics_frames(),"game_s":actor._combat_action_time_s,"roll":roll,"event_time":TIMES[next_event],"walk_tick":actor._movement_cadence.walk_tick_ms,"oracle_tick":oracle.walk_tick_ms})
		next_event += 1
	checks += 1
	if actor._movement_cadence.walk_tick_ms!=oracle.walk_tick_ms and errors.size()<8:
		errors.append("native phase differs from frozen source oracle")
func run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	for sample: int in [0,550,999]:
		roll = sample
		next_event = 0
		var victim := F.player(self,Vector2(25,20))
		actor = F.enemy(self,64,Vector2(20,20),victim)
		actor.level = 49
		oracle.configure(actor._movement_cadence.walk_interval_ms,actor._movement_cadence.walk_step,actor._movement_cadence.walk_wait_ms,0)
		start_clock = actor._combat_action_time_s
		collecting = true
		actor.set_physics_process(true)
		for n in range(210):
			await get_tree().physics_frame
		collecting = false
		actor.set_physics_process(false)
		if next_event!=4:
			errors.append("all declared direct inputs must execute")
		F.dispose(actor,victim)
	F.write_evidence("source_direct_phase_trace",{"checks":checks,"errors":errors,"events":rows,"scope":"native physics with explicit source-message rolls; independent cadence oracle"})
	print(("R3_DIRECT_PHASE_PASS" if errors.is_empty() else "R3_DIRECT_PHASE_FAIL")+" checks="+str(checks)+" errors="+str(errors))
	get_tree().quit(0 if errors.is_empty() else 1)
