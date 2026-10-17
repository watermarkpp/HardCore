extends RefCounted

## Concrete legacy Node/physics/render boundaries for the single Summon model.
## S supplies owner-local ActorLink, native motion and presentation-value ports.
const Observer := preload("res://scripts/damage_ledger_observer.gd")
const WorldRules := preload("res://scripts/world_spatial_rules.gd")
var _actor: WeakRef
var _index: RefCounted

var recording_enabled: bool:
	get: return Observer.recording_enabled

func _init(actor: Node) -> void:
	_actor = weakref(actor)

func capture_actor(actor: Node) -> RefCounted:
	return weakref(actor) if is_instance_valid(actor) else null

func resolve_actor(link: RefCounted) -> Node:
	if link == null:
		return null
	assert(link is WeakRef, "legacy actor access requires a legacy object reference")
	return link.get_ref() as Node

func resolve_model(link: RefCounted) -> Object:
	return resolve_actor(link)

func is_present() -> bool:
	# Lifetime presence is the original is_inside_tree guard. A null target
	# remains absent through the separate actor_is_present operation.
	return is_instance_valid(_actor.get_ref()) and _actor.get_ref().is_inside_tree()

func actor_is_present(link: RefCounted) -> bool:
	return is_instance_valid(resolve_actor(link))

func is_retiring(link: RefCounted) -> bool:
	var actor := resolve_actor(link)
	return not is_instance_valid(actor) or actor.is_queued_for_deletion()

func is_enemy(link: RefCounted) -> bool:
	return resolve_actor(link) is EnemyActor

func actor_position_screen_px(link: RefCounted) -> Vector2:
	return (resolve_actor(link) as Node2D).global_position

func current_hp(link: RefCounted) -> int:
	return resolve_actor(link).get("current_hp")

func runtime_map_id(link: RefCounted) -> int:
	return resolve_actor(link).get("runtime_map_id")

func position_ground_gu(link: RefCounted) -> Vector2:
	return resolve_actor(link).call("spatial_index_position")

func movement_facing(link: RefCounted) -> Vector2:
	return resolve_actor(link).get("movement_facing")

func facing(link: RefCounted) -> Vector2:
	return resolve_actor(link).get("facing")

func agility(link: RefCounted) -> int:
	return resolve_actor(link).get("agility")

func combat_transition_is_active(link: RefCounted) -> bool:
	return resolve_actor(link).call("combat_transition_is_active")

func accepts_external_attack(link: RefCounted) -> bool:
	return resolve_actor(link).call("accepts_external_attack_from", _actor.get_ref())

func apply_enemy_damage(target_model: Object, amount: int) -> void:
	# Keep the resolved object alive in the caller's synchronous settlement scope.
	target_model.take_damage(amount, _actor.get_ref())

static func target_combat_radius_gu_for_actor(target: Node) -> float:
	if is_instance_valid(target) and target is EnemyActor:
		return maxf(0.0, (target as EnemyActor).combat_radius_gu)
	return 0.0

func enemy_combat_radius_gu(link: RefCounted) -> float:
	return target_combat_radius_gu_for_actor(resolve_actor(link))

func position_screen_px() -> Vector2:
	return _actor.get_ref().global_position

func set_position_screen_px(value: Vector2) -> void:
	_actor.get_ref().global_position = value

func velocity_screen_px_per_sec() -> Vector2:
	return _actor.get_ref().velocity

func set_velocity_screen_px_per_sec(value: Vector2) -> void:
	_actor.get_ref().velocity = value

func collision_layer() -> int:
	return _actor.get_ref().collision_layer

func set_collision_layer(value: int) -> void:
	_actor.get_ref().collision_layer = value

func collision_mask() -> int:
	return _actor.get_ref().collision_mask

func set_collision_mask(value: int) -> void:
	_actor.get_ref().collision_mask = value

func move_and_slide() -> void:
	_actor.get_ref().move_and_slide()

func world_path_clear(origin: Vector2, target: Vector2) -> bool:
	var world: World2D = _actor.get_ref().get_world_2d()
	if world == null or world.direct_space_state == null:
		return false
	var query := PhysicsRayQueryParameters2D.create(origin, target, WorldRules.WORLD_MASK)
	query.collide_with_bodies = true
	query.collide_with_areas = true
	return world.direct_space_state.intersect_ray(query).is_empty()

func unregister_combat_target() -> void:
	_actor.get_ref().remove_from_group("combat_targets")

func request_retirement() -> void:
	_actor.get_ref().queue_free()

func configure_spatial_index(index: RefCounted) -> void:
	_index = index

func available() -> bool:
	return _index != null and is_instance_valid(_index)

func query_aabb_candidates(map_id: int, bounds: Rect2, padding: float) -> Array[Dictionary]:
	var rows: Array = _index.query_aabb_candidates(map_id, bounds, padding)
	var result: Array[Dictionary] = []
	for row: Dictionary in rows:
		var adapted := row.duplicate(false)
		adapted["actor"] = capture_actor(row.get("node", null))
		adapted.erase("node")
		result.append(adapted)
	return result

func canonical_follow_landing_plan() -> Dictionary:
	var authority: Node = _actor.get_ref()._owner_follow_landing_authority()
	if authority != null:
		var raw_plan: Variant = authority.call("_canonical_summon_follow_landing_plan", _actor.get_ref())
		if raw_plan is Dictionary:
			return raw_plan
	return {"valid": false, "reason": "canonical_landing_authority_unavailable", "defer_allowed": false}

func capture_follow_landing_authority() -> RefCounted:
	var authority: Node = _actor.get_ref()._owner_follow_landing_authority()
	return weakref(authority) if authority != null else null

func register_pending_arrival(authority: RefCounted) -> void:
	# Reuse the exact provider captured before synchronous wake-signal reentry.
	authority.get_ref().call("_register_pending_main_pet_arrival", _actor.get_ref())

func record_terminal(source: Variant, kind: String, reason: String) -> void:
	Observer.record_terminal(source, kind, reason)

func record_hp_mutation(amount: int, hp_before: int, hp_after: int, damage_type: String, identity: Variant) -> void:
	Observer.record_hp_mutation(_actor.get_ref(), amount, hp_before, hp_after, damage_type, identity)

func redraw() -> void:
	_actor.get_ref()._request_visual_redraw()

func update_stealth_visual() -> void:
	_actor.get_ref()._update_stealth_visual()

func refresh_buff_redraw_if_needed() -> void:
	_actor.get_ref()._refresh_buff_redraw_if_needed()

func refresh_buff_draw_signature() -> void:
	_actor.get_ref()._last_buff_draw_signature = _actor.get_ref()._buff_draw_signature()

func update_fire_visual(delta: float) -> void:
	_actor.get_ref()._update_fire_visual(delta)

func reset_fire_visual() -> void:
	_actor.get_ref()._fire_visual_remaining = 0.0
	if _actor.get_ref()._fire_sprite != null:
		_actor.get_ref()._fire_sprite.visible = false

func start_fire_visual() -> void:
	_actor.get_ref()._start_fire_visual()

func poll_visual_activation() -> void:
	_actor.get_ref()._poll_visual_activation()

func apply_visual_frame(_state: String, _direction: int, _frame: int) -> void:
	_actor.get_ref()._apply_visual_frame()

func set_visible(value: bool) -> void:
	_actor.get_ref().visible = value

func reset_audio_state() -> void:
	_actor.get_ref()._audio_appear_emitted = false
	_actor.get_ref()._audio_death_emitted = false
	_actor.get_ref()._audio_attack_sequence = 0
	_actor.get_ref()._audio_attack_frame_sequence = -1

func audio_attack_started() -> void:
	_actor.get_ref()._audio_attack_started()

func audio_attack_frame() -> void:
	_actor.get_ref()._audio_attack_frame()

func audio_death_once() -> void:
	_actor.get_ref()._audio_death_once()

func audio_hurt() -> void:
	_actor.get_ref()._audio_hurt()
