extends RefCounted

## Explicit legacy adapters for the player model. These methods execute on M
## against the original Node and SceneTree. Simulation owners must supply their
## own native phase/lifetime/motion, value-presentation and observer ports.
## No gameplay formula or HP state is owned here.
const DamageObserver := preload("res://scripts/damage_ledger_observer.gd")
var _actor: WeakRef

var recording_enabled: bool:
	get: return DamageObserver.recording_enabled


func _init(actor: Node) -> void:
	_actor = weakref(actor)


func create_timer(delay_seconds: float, process_always := true, process_in_physics := false, ignore_time_scale := false) -> RefCounted:
	return _actor.get_ref().get_tree().create_timer(delay_seconds, process_always, process_in_physics, ignore_time_scale)


func is_present() -> bool:
	var actor: Object = _actor.get_ref()
	return is_instance_valid(actor) and actor.is_inside_tree()


func stop_velocity() -> void:
	_actor.get_ref().velocity = Vector2.ZERO


func has_visual() -> bool:
	return _actor.get_ref().visual != null


func redraw() -> void:
	_actor.get_ref().queue_redraw()


func play_hit(duration: float) -> void:
	_actor.get_ref().visual.play_hit(duration)


func play_death() -> void:
	_actor.get_ref().visual.play_death()


func play_action(action: String, duration: float) -> void:
	_actor.get_ref().visual.play_action(action, duration)


func refresh_profession() -> void:
	_actor.get_ref().visual.refresh_profession()


func read_red_poison() -> Variant:
	var actor: Object = _actor.get_ref()
	if not actor.has_meta("canonical_red_poison"):
		return null
	return actor.get_meta("canonical_red_poison")


func write_red_poison(value: Dictionary) -> void:
	_actor.get_ref().set_meta("canonical_red_poison", value)


func call_damage_write_hook(hook: Callable, delivery_identity: Variant, final_damage: int) -> Variant:
	# Preserve the explicit legacy fixture's victim parameter. The observer
	# still has no authority over writes when the separate hook is disabled.
	return hook.call(_actor.get_ref(), delivery_identity, final_damage)


func record_hp_mutation(resolved_damage: int, hp_before: int, hp_after: int, damage_type: String, source: Variant = null, mp_before := -1, mp_after := -1) -> void:
	DamageObserver.record_hp_mutation(_actor.get_ref(), resolved_damage, hp_before, hp_after, damage_type, source, mp_before, mp_after)


func record_terminal(source: Variant, kind: String, reason: String, hp_before := -1, hp_after := -1, mp_before := -1, mp_after := -1) -> void:
	DamageObserver.record_terminal(source, kind, reason, hp_before, hp_after, mp_before, mp_after)


func is_retiring() -> bool:
	return _actor.get_ref().is_queued_for_deletion()


func keyboard_movement_vector() -> Vector2:
	return _actor.get_ref()._keyboard_movement_vector()


func position_screen_px() -> Vector2:
	return _actor.get_ref().global_position


func velocity_screen_px_per_sec() -> Vector2:
	return _actor.get_ref().velocity


func set_velocity_screen_px_per_sec(value: Vector2) -> void:
	_actor.get_ref().velocity = value


func set_position_screen_px(value: Vector2) -> void:
	_actor.get_ref().global_position = value


func safe_margin() -> float:
	return _actor.get_ref().safe_margin


func collide_motion(motion_px: Vector2, test_only: bool, margin: float, recovery_as_collision := false) -> void:
	_actor.get_ref().move_and_collide(motion_px, test_only, margin, recovery_as_collision)


func environment_blocks_actor_screen_px(position: Vector2, radius: float) -> bool:
	return preload("res://scripts/world_spatial_rules.gd").environment_blocks_actor_screen_px(_actor.get_ref().environment_blocker, position, radius)


func actor_view(runtime_id: int) -> Dictionary:
	var candidate := instance_from_id(runtime_id)
	if not candidate is Node2D or not is_instance_valid(candidate) or not candidate.is_inside_tree():
		return {}
	var is_enemy := candidate is EnemyActor
	return {
		"runtime_id": runtime_id,
		"position_screen_px": candidate.global_position,
		"combat_radius_gu": maxf(0.0, candidate.combat_radius_gu) if is_enemy else 0.0,
		"kind": &"enemy" if is_enemy else &"legacy_spatial",
	}
