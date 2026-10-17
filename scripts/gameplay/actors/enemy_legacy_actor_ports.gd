extends RefCounted

## Main-only implementation of every direct Enemy model boundary.
## This bridge owns no HP, life counter, target policy, attack RNG or pose copy.
const AccessScript := preload("res://scripts/gameplay/actors/enemy_legacy_access.gd")
const FeatureBatch := preload("res://scripts/features/runtime/damage_batch.gd")
const BodyPolicy := preload("res://scripts/actor_body_policy.gd")
const PathScheduler := preload("res://scripts/monster_ai_package/path_scheduler.gd")
const PathSearch := preload("res://scripts/monster_ai_package/path_search.gd")
const PolygonPursuit := preload("res://scripts/map_editor/polygon/poly_pursuit_driver.gd")
const Entrapment := preload("res://scripts/entrapment_boundary_controller.gd")
const Projectile := preload("res://scripts/monster_ranged_projectile_effect.gd")
const TargetMagic := preload("res://scripts/monster_target_magic_effect.gd")
var _actor: WeakRef
var _model: WeakRef
var _context: RefCounted
var _access: RefCounted

func _init(actor: Node, model: RefCounted, context: RefCounted) -> void:
	assert(OS.get_thread_caller_id() == OS.get_main_thread_id())
	_actor = weakref(actor)
	_model = weakref(model)
	_context = context
	_access = AccessScript.new(actor)

func owner_thread_id() -> int:
	return OS.get_main_thread_id()

func _node() -> Node:
	assert(OS.get_thread_caller_id() == OS.get_main_thread_id())
	var actor: Node = _actor.get_ref()
	assert(is_instance_valid(actor), "Enemy legacy port outlived its Node")
	return actor

func bindings() -> Dictionary:
	return {"legacy":true,"actor_links":_access,"motion":self,"lifetime":self,
		"metadata":self,"phase_scheduler":self,"presentation":self,
		"feature_damage":self,"navigation":self,"services":_context.services,
		"shared":_context.shared}

func to_domain(value: Variant) -> Variant:
	# Legacy objects are legal only in this Main-only bridge. Persistent model
	# actor references are independently captured by its access port.
	return value

func to_legacy(value: Variant) -> Variant:
	return value

func read(key: StringName, fallback: Variant = null) -> Variant:
	return _node().get_meta(key, fallback)

func write(key: StringName, value: Variant) -> void:
	_node().set_meta(key, value)

func contains(key: StringName) -> bool:
	return _node().has_meta(key)

func erase(key: StringName) -> void:
	_node().remove_meta(key)

func is_initialized() -> bool:
	return _node().is_node_ready()

func position_screen_px() -> Vector2:
	return _node().global_position

func set_position_screen_px(value: Vector2) -> void:
	_node().global_position = value

func velocity_screen_px_per_sec() -> Vector2:
	return _node().velocity

func set_velocity_screen_px_per_sec(value: Vector2) -> void:
	_node().velocity = value

func collision_layer() -> int:
	return _node().collision_layer

func set_collision_layer(value: int) -> void:
	_node().collision_layer = value

func collision_mask() -> int:
	return _node().collision_mask

func set_collision_mask(value: int) -> void:
	_node().collision_mask = value

func safe_margin() -> float:
	return _node().safe_margin

func collide_motion(motion: Vector2, test_only := false, margin := 0.08,
		recovery_as_collision := false) -> KinematicCollision2D:
	return _node().move_and_collide(motion, test_only, margin, recovery_as_collision)

func slide(_delta: float) -> void:
	_node().move_and_slide()

func slide_collision_count() -> int:
	return _node().get_slide_collision_count()

func slide_collision(index: int) -> KinematicCollision2D:
	return _node().get_slide_collision(index)

func prepare_actor_footprint(radius: float) -> void:
	var collision := CollisionShape2D.new()
	collision.name = "CollisionShape2D"
	collision.shape = BodyPolicy.footsole_shape_px(radius)
	_node()._body_collision_shape = collision

func query_port() -> PhysicsDirectSpaceState2D:
	var world: World2D = _node().get_world_2d()
	return world.direct_space_state if world != null else null

func ray_parameters(origin: Vector2, destination: Vector2, mask: int = 0xffffffff,
		exclude: Array[RID] = []) -> PhysicsRayQueryParameters2D:
	return PhysicsRayQueryParameters2D.create(origin, destination, mask, exclude)

func runtime_object_is_present() -> bool:
	return is_instance_valid(_actor.get_ref())

func is_inside_world() -> bool:
	return _node().is_inside_tree()

func is_queued_for_retirement() -> bool:
	return _node().is_queued_for_deletion()

func parent_scope() -> Object:
	return _node().get_parent()

func can_process() -> bool:
	return _node().can_process()

func physics_processing_enabled() -> bool:
	return _node().is_physics_processing()

func set_physics_processing(enabled: bool) -> void:
	_node().set_physics_process(enabled)

func input_pickable() -> bool:
	return _node().input_pickable

func set_input_pickable(enabled: bool) -> void:
	_node().input_pickable = enabled

func process_mode() -> int:
	return _node().process_mode

func add_to_group(group: StringName, persistent := false) -> void:
	_node().add_to_group(group, persistent)

func remove_from_group(group: StringName) -> void:
	_node().remove_from_group(group)

func queue_retirement() -> void:
	_node().queue_free()

func world_services() -> SceneTree:
	return _node().get_tree()

func physics_delta() -> float:
	return _node().get_physics_process_delta_time()

func defer_after_damage_stack(callback: Callable) -> void:
	# Bind the queue entry to the original Node lifetime. Keeping the model's
	# RefCounted Callable here would run after its Node was freed.
	assert(callback.get_method() == &"_begin_death")
	_node().call_deferred(callback.get_method())

func gameplay_visual_state() -> Object:
	return _node().visual

func has_overhead() -> bool:
	return _node().overhead != null

func set_overhead_visible(value: bool) -> void:
	_node().overhead.visible = value

func redraw() -> void:
	_node().queue_redraw()

func invoke_original(method: StringName, arguments: Array) -> Variant:
	assert(_node().has_method(method), "missing retained Enemy presentation method")
	return _node().callv(method, arguments)

func read_observer_field(key: StringName) -> Variant:
	assert(key in [&"_audio_attack_start_accepted", &"_audio_attack_frame_ready"])
	return _node().get(key)

func write_observer_field(key: StringName, value: Variant) -> void:
	assert(key in [&"_audio_attack_start_accepted", &"_audio_attack_frame_ready"])
	_node().set(key, value)

func create_original_effect(kind: StringName, descriptor: Dictionary) -> void:
	var host := _node().get_parent()
	if not is_instance_valid(host):
		return
	var effect: Node2D
	match kind:
		&"physical_projectile": effect = Projectile.create_visual(descriptor)
		&"target_magic": effect = TargetMagic.create_visual(descriptor)
		_: assert(false, "unknown original Enemy effect"); return
	host.add_child(effect)

func is_damage_batch(value: Variant) -> bool:
	return value is RefCounted and value.get_script() == FeatureBatch

func prepare_commit_context(batch: RefCounted, context: Dictionary) -> Dictionary:
	return batch.prepare_commit_context(_node(), context)

func capture_commit(batch: RefCounted, attacker: Object, before: int, after: int,
		amount: int, context: Dictionary) -> void:
	batch.capture_commit(_node(), attacker, before, after, amount, context)

func scheduler() -> Object:
	return PathScheduler.for_tree(_node().get_tree())

func create_search() -> RefCounted:
	return PathSearch.new()

func create_polygon_pursuit(_actor_view: Object) -> Object:
	var driver := PolygonPursuit.new()
	driver.name = "PolygonPursuitBudgetAdapter"
	_node().add_child(driver)
	driver.setup(_node())
	return driver

func create_entrapment_controller() -> RefCounted:
	return Entrapment.new()

func connect_model_signals() -> void:
	var model: RefCounted = _model.get_ref()
	model.combat_target_changed.connect(_combat_target_changed)
	model.died.connect(_died)
	model.target_requested.connect(_target_requested)
	model.summon_requested.connect(_summon_requested)
	model.relocation_requested.connect(_relocation_requested)
	model.fixed_area_ground_spike_requested.connect(_fixed_area_ground_spike_requested)
	model.ranged_projectile_requested.connect(_ranged_projectile_requested)
	model.target_magic_requested.connect(_target_magic_requested)
	model.monster_special_delivery_requested.connect(_monster_special_delivery_requested)

func _combat_target_changed(enemy: Object, target: Object) -> void:
	_node().emit_signal("combat_target_changed", enemy, target)

func _died(enemy: Object, data: Dictionary) -> void:
	_node().emit_signal("died", enemy, data)

func _target_requested(enemy: Object) -> void:
	_node().emit_signal("target_requested", enemy)

func _summon_requested(enemy: Object, ids: Array, count: int, maximum: int) -> void:
	_node().emit_signal("summon_requested", enemy, ids, count, maximum)

func _relocation_requested(enemy: Object, radius: float) -> void:
	_node().emit_signal("relocation_requested", enemy, radius)

func _fixed_area_ground_spike_requested(value: Dictionary) -> void:
	_node().emit_signal("fixed_area_ground_spike_requested", value)

func _ranged_projectile_requested(value: Dictionary) -> void:
	_node().emit_signal("ranged_projectile_requested", value)

func _target_magic_requested(value: Dictionary) -> void:
	_node().emit_signal("target_magic_requested", value)

func _monster_special_delivery_requested(value: Dictionary) -> void:
	_node().emit_signal("monster_special_delivery_requested", value)
