extends Node2D
const F := preload("res://tests/source176_r3/helpers/runtime_fixture.gd")
const Oracle := preload("res://tests/helpers/source_cadence_reference.gd")
class IdleEnemy:
	extends EnemyActor
	var idle_fixture := true
	# Structural idle/background fixture: no target acquisition; real Timer,
	# owner physics, cadence, pause and wake code remain enabled.
	func _can_use_background_ai() -> bool:
		return idle_fixture
	func _retarget(_delta: float = 0.0, _ignored: Node2D = null) -> void:
		pass
var errors: Array[String] = []
var rows: Array = []
var checks := 0
var actor: EnemyActor
var oracle := Oracle.new()
var sampling := false
var elapsed := 0.0
var mismatch := false
@export var idle_seconds := 30.0
func _ready() -> void:
	process_physics_priority = 10000
	run.call_deferred()
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		errors.append(label)
func _physics_process(delta: float) -> void:
	if not sampling:
		return
	elapsed += delta
	var ms := int(actor._combat_action_time_s*1000.0)
	oracle.evaluate(ms)
	if absf(actor._combat_action_time_s-elapsed)>.0001 or actor._movement_cadence.walk_tick_ms!=oracle.walk_tick_ms:
		mismatch = true
	if Engine.get_physics_frames()%30==0:
		rows.append({"tick":Engine.get_physics_frames(),"clock":actor._combat_action_time_s,
			"elapsed":elapsed,"walk_tick":actor._movement_cadence.walk_tick_ms,
			"oracle_walk_tick":oracle.walk_tick_ms,"background":actor._background_deep_sleeping})
func run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	actor = IdleEnemy.new()
	actor.setup(GameData.get_monster_by_id(64),null,false)
	actor.global_position = F.to_screen(Vector2(20,20))
	actor.set_meta("spawn_position",actor.global_position)
	actor.set_meta("safe_zones",[])
	actor.set_meta("zone_generation",1)
	actor.configure_runtime_map_projection(1,Callable(F.GU,"ground_delta_gu_to_screen_delta_px"),Callable(F.GU,"screen_delta_px_to_ground_delta_gu"))
	actor.configure_terrain_navigation_context(F.open_context())
	add_child(actor)
	oracle.configure(actor._movement_cadence.walk_interval_ms,actor._movement_cadence.walk_step,actor._movement_cadence.walk_wait_ms,0)
	sampling = true
	for seconds: float in [3.0,10.0,30.0]:
		if seconds>idle_seconds:
			continue
		while elapsed<seconds:
			await get_tree().physics_frame
		check(not mismatch,"native idle clock and source phase through %s game seconds"%seconds)
		if mismatch:
			break
	var victim := F.player(self,Vector2(25,20))
	var source_before := F.to_ground(actor.global_position)
	actor.idle_fixture = false
	actor.primary_target = victim
	actor.target = victim
	actor.spatial_actor_runtime_id = actor.get_instance_id()
	actor.combat_spatial_index = F.Spatial.new()
	actor.combat_spatial_index.register(actor.spatial_actor_runtime_id,1,source_before,actor.combat_radius_gu,1,actor)
	actor.take_damage(1,victim)
	actor._leave_background_deep_sleep()
	var chase_end := elapsed+5.0
	while elapsed<chase_end:
		await get_tree().physics_frame
	check(not mismatch,"wake and five-second chase retain source oracle")
	check(F.to_ground(actor.global_position).distance_to(source_before)>.5,"real chase moves after idle")
	sampling = false
	F.dispose(actor,victim)
	check(F.write_evidence("source_idle_wake_phase",{"checks":checks,"errors":errors,"rows":rows,"fixture":"structural idle acquisition disabled, real background Timer"}),"write evidence")
	print(("R3_IDLE_PHASE_PASS" if errors.is_empty() else "R3_IDLE_PHASE_FAIL")+" checks="+str(checks)+" errors="+str(errors))
	get_tree().quit(0 if errors.is_empty() else 1)
