extends Node2D
const F := preload("res://tests/source176_r3/helpers/runtime_fixture.gd")
const Rules := preload("res://scripts/world_spatial_rules.gd")
var errors: Array[String] = []
var checks := 0
var rows: Array = []
func _ready() -> void:
	run.call_deferred()
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		errors.append(label)
func run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	for kind: String in ["player","skeleton","beast"]:
		var owner := F.player(self,Vector2(30,30))
		var victim: Node2D = owner
		if kind=="player":
			owner.global_position = F.to_screen(Vector2(20.99,20))
		else:
			var summon := SummonActor.new()
			summon.setup(owner,"变异骷髅" if kind=="skeleton" else "神兽",30,3,"taoist.summon_skeleton" if kind=="skeleton" else "taoist.summon_divine_beast",26 if kind=="skeleton" else 40)
			summon.configure_runtime_map_projection(1,Callable(F.GU,"ground_delta_gu_to_screen_delta_px"),Callable(F.GU,"screen_delta_px_to_ground_delta_gu"))
			summon.global_position = F.to_screen(Vector2(20.99,20))
			add_child(summon)
			summon.set_physics_process(false)
			victim = summon
		var actor := F.enemy(self,64,Vector2(20,20),owner)
		actor.set_combat_position(F.to_screen(Vector2(20,20)),&"r3_body_clearance_fixture")
		actor._attack_timer = 0.0
		var target_radius: float = actor._target_combat_radius_gu(victim)
		check(.99>=actor.combat_radius_gu+target_radius,"real body pair does not overlap: "+kind)
		check(actor._hc_try_start(victim),"ordinary axial inside admits actual body: "+kind)
		rows.append({"kind":kind,"source_radius":actor.combat_radius_gu,"target_radius":target_radius,"center_distance":.99,"parent":actor._attack_logic_serial})
		if victim!=owner:
			victim.free()
		F.dispose(actor,owner)
	var victim := F.player(self,Vector2(20.99,20))
	var actor := F.enemy(self,64,Vector2(20,20),victim)
	actor.set_combat_position(F.to_screen(Vector2(20,20)),&"r3_wall_fixture")
	actor._attack_timer = 0.0
	var wall := StaticBody2D.new()
	wall.collision_layer = Rules.WORLD_LAYER
	var shape := CollisionPolygon2D.new()
	shape.polygon = PackedVector2Array([F.to_screen(Vector2(20.47,19)),F.to_screen(Vector2(20.5,19)),F.to_screen(Vector2(20.5,21)),F.to_screen(Vector2(20.47,21))])
	wall.add_child(shape)
	add_child(wall)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var rng: int = actor._rng.state
	var parent := actor._attack_logic_serial
	var hp := victim.current_hp
	var timer := actor._attack_timer
	check(actor._hc_access(victim,0.0,true)=="WORLD_BLOCKED","real wall prevents box access")
	check(not actor._hc_try_start(victim),"box alone cannot admit through wall")
	check(actor._rng.state==rng and actor._attack_logic_serial==parent and actor._attack_timer==timer and victim.current_hp==hp,"blocked admission has zero transaction effects")
	rows.append({"kind":"wall","timer_before":timer,"timer_after":actor._attack_timer,"rng_before":str(rng),"rng_after":str(actor._rng.state),"parent_before":parent,"parent_after":actor._attack_logic_serial,"hp_before":hp,"hp_after":victim.current_hp})
	wall.free()
	F.dispose(actor,victim)
	F.write_evidence("ordinary_body_clearance",{"checks":checks,"errors":errors,"rows":rows,"scope":"structural admission with actual player/skeleton/beast radii and WORLD wall; native crowd proof is d3_motion_pressure"})
	print(("R3_BODY_CLEARANCE_PASS" if errors.is_empty() else "R3_BODY_CLEARANCE_FAIL")+" checks="+str(checks)+" errors="+str(errors))
	get_tree().quit(0 if errors.is_empty() else 1)
