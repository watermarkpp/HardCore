extends Node2D
const F := preload("res://tests/source176_r3/helpers/runtime_fixture.gd")
class PinnedEnemy:
	extends EnemyActor
	func _retarget(_delta: float = 0.0, _cached: Node2D = null) -> void:
		pass
class CancelledChild:
	extends PinnedEnemy
	func _launch_target_magic(_recipient: Node2D, _damage: int) -> bool:
		# Structural cancellation after an accepted parent (e.g. a callback
		# invalidates delivery). Cancellation does not un-admit that parent.
		return false
var errors: Array[String] = []
func _ready() -> void:
	run.call_deferred()
func run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var victim := F.player(self,Vector2(22,20))
	victim.set_meta("runtime_map_id",2)
	var actor := PinnedEnemy.new()
	actor.setup(GameData.get_monster_by_id(220),victim,false)
	actor.global_position = F.to_screen(Vector2(20,20))
	actor.set_meta("safe_zones",[])
	actor.set_meta("zone_generation",1)
	actor.configure_runtime_map_projection(1,Callable(F.GU,"ground_delta_gu_to_screen_delta_px"),Callable(F.GU,"screen_delta_px_to_ground_delta_gu"))
	actor.configure_terrain_navigation_context(F.open_context())
	add_child(actor)
	actor.set_physics_process(false)
	actor.target = victim
	actor._attack_timer = 0.0
	var rng: int = actor._rng.state
	var parent := actor._attack_logic_serial
	var hp := victim.current_hp
	# Structural stale target: retargeting is intentionally pinned so the
	# release owner itself must reject cross-map input before side effects.
	actor._physics_process_internal(.01)
	if actor._attack_logic_serial!=parent or actor._rng.state!=rng:
		errors.append("cross-map rejected dispatch consumed parent/RNG")
	if actor._attack_timer>0.0 or victim.current_hp!=hp or not actor._pending_attack_release_record.is_empty():
		errors.append("cross-map rejected dispatch consumed cooldown or release")
	actor.free()
	victim.free()
	victim = F.player(self,Vector2(22,20))
	var cancelled := CancelledChild.new()
	cancelled.setup(GameData.get_monster_by_id(220),victim,false)
	cancelled.global_position = F.to_screen(Vector2(20,20))
	cancelled.set_meta("safe_zones",[])
	cancelled.configure_runtime_map_projection(1,Callable(F.GU,"ground_delta_gu_to_screen_delta_px"),Callable(F.GU,"screen_delta_px_to_ground_delta_gu"))
	cancelled.configure_terrain_navigation_context(F.open_context())
	add_child(cancelled)
	cancelled.set_physics_process(false)
	cancelled.target = victim
	cancelled._attack_timer = 0.0
	cancelled._physics_process_internal(.01)
	if cancelled._attack_logic_serial!=1 or cancelled._try_reserve_source_body_action(false):
		errors.append("cancelled child lent already accepted parent's same-tick body reservation")
	cancelled.free()
	victim.free()
	F.write_evidence("target_magic_admission",{"errors":errors,"scope":"pinned stale target structural fixture, actual parent entry"})
	print(("R3_TARGET_ADMISSION_PASS" if errors.is_empty() else "R3_TARGET_ADMISSION_FAIL")+" errors="+str(errors))
	get_tree().quit(0 if errors.is_empty() else 1)
