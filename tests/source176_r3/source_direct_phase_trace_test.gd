extends Node2D
const F := preload("res://tests/source176_r3/helpers/runtime_fixture.gd")
const Oracle := preload("res://tests/helpers/source_cadence_reference.gd")
const CombatRuntime := preload("res://scripts/layers/runtime/combat_runtime_service.gd")
var actor: EnemyActor
var combat_runtime: CombatRuntime
var oracle := Oracle.new()
var collecting := false
var next_event := 0
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
		# A declared source-message input at real game time. Exercise the real
		# combat service; the compatibility RNG draw is an internal side effect
		# of positive DIRECT resolution, never the test event itself.
		var hp_before := actor.current_hp
		var direct_result := combat_runtime.apply_enemy_direct_spell_damage(
			actor,
			"wizard.lightning",
			1000,
			null,
			null,
			Callable(),
			0,
			{},
			CombatRuntime.EnemyMagicDeliveryKind.AUTO,
		)
		if not bool(direct_result.get("success", false)):
			errors.append("positive direct input rejected")
		if actor.current_hp >= hp_before:
			errors.append("positive direct input did not reduce HP")
		rows.append({"tick":Engine.get_physics_frames(),"game_s":actor._combat_action_time_s,"event_time":TIMES[next_event],"walk_tick":actor._movement_cadence.walk_tick_ms,"oracle_tick":oracle.walk_tick_ms,"hp_delta":hp_before-actor.current_hp})
		next_event += 1
	checks += 1
	if actor._movement_cadence.walk_tick_ms!=oracle.walk_tick_ms and errors.size()<8:
		errors.append("native phase differs from frozen source oracle")
func run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	combat_runtime = CombatRuntime.new()
	add_child(combat_runtime)
	for sample: int in [0,550,999]:
		next_event = 0
		var victim := F.player(self,Vector2(25,20))
		actor = F.enemy(self,64,Vector2(20,20),victim)
		actor.level = 49
		actor._rng.seed = sample
		actor.max_hp = 1000000
		actor.current_hp = actor.max_hp
		actor.direct_spell_anti_magic_points = 0
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
	F.write_evidence("source_direct_phase_trace",{"checks":checks,"errors":errors,"events":rows,"scope":"native physics with positive direct damage and three actor RNG seeds; independent cadence oracle"})
	print(("R3_DIRECT_PHASE_PASS" if errors.is_empty() else "R3_DIRECT_PHASE_FAIL")+" checks="+str(checks)+" errors="+str(errors))
	get_tree().quit(0 if errors.is_empty() else 1)
