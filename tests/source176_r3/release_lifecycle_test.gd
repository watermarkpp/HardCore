extends Node2D
const F := preload("res://tests/source176_r3/helpers/runtime_fixture.gd")
class CaptureEnemy:
	extends EnemyActor
	var captured: Dictionary = {}
	func _emit_physical_projectile_descriptor(record: Dictionary) -> void:
		captured = record
var errors: Array[String] = []
var checks := 0
func _ready() -> void:
	run.call_deferred()
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		errors.append(label)
func run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	for id: int in [50,220]:
		var victim := F.player(self,Vector2(22,20))
		var actor := CaptureEnemy.new()
		actor.setup(GameData.get_monster_by_id(id),victim,false)
		actor.global_position = F.to_screen(Vector2(20,20))
		actor.set_meta("zone_generation",1)
		actor.set_meta("safe_zones",[])
		actor.configure_runtime_map_projection(1,Callable(F.GU,"ground_delta_gu_to_screen_delta_px"),Callable(F.GU,"screen_delta_px_to_ground_delta_gu"))
		actor.configure_terrain_navigation_context(F.open_context())
		add_child(actor)
		actor.set_physics_process(false)
		var parent := actor._allocate_attack_action(.6)
		check(actor._launch_physical_projectile(victim,20) if id==50 else actor._launch_target_magic(victim,20),"actual delivery creates release")
		var record: Dictionary = actor.captured if id==50 else actor._pending_attack_release_record
		check(int(record.get("parent_action_id",-1))==parent,"release binds original parent")
		check(int(record.get("source_life",-1))==actor._hc_life(actor),"release binds original source life")
		actor._attack_action_active = false
		check(actor._physical_projectile_release_target_is_valid(victim,record),"released child survives presentation expiry")
		actor.set_meta("hc_combat_life_epoch",actor._hc_life(actor)+1)
		check(not actor._physical_projectile_release_target_is_valid(victim,record),"source reuse rejects old child")
		F.dispose(actor,victim)
	F.write_evidence("release_lifecycle",{"checks":checks,"errors":errors})
	print(("R3_RELEASE_LIFE_PASS" if errors.is_empty() else "R3_RELEASE_LIFE_FAIL")+" checks="+str(checks)+" errors="+str(errors))
	get_tree().quit(0 if errors.is_empty() else 1)
