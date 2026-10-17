extends "res://scripts/gameplay/actors/actor_runtime_ports.gd"

## Per Enemy borrowed ports. One canonical Handle and original EnemyModel.
const Batch := preload("res://scripts/features/runtime/damage_batch.gd")
var access: RefCounted
var scope: RefCounted
var shared: RefCounted
var services: Dictionary
var initialized := false
var pickable := false
var observer_fields: Dictionary
func configure_enemy(owner_access: RefCounted, source_scope: RefCounted, source_services: Dictionary, shared_state: RefCounted) -> void:
	access = owner_access
	scope = source_scope
	services = source_services
	shared = shared_state
	observer_fields = {} # actual original observer scalars live in Core presentation instance
func bindings(motion: RefCounted) -> Dictionary:
	return {"actor_links": access, "motion": motion, "lifetime": self, "metadata": self,
		"phase_scheduler": self, "presentation": self, "feature_damage": self,
		"navigation": self, "services": services, "shared": shared}
func read(key: StringName, fallback: Variant = null) -> Variant: return _core.get_ref().actor_metadata_read(_handle.get_ref(), key, fallback)
func write(key: StringName, value: Variant) -> void:
	_core.get_ref().actor_metadata_write(_handle.get_ref(), key, value)
	if key == &"hc_combat_life_epoch" and _handle.get_ref().identity().is_empty() == false and _core.get_ref().registry.resolve_runtime_actor(runtime_id()) == null:
		if not _core.get_ref().commit_enemy_at_original_setup_life(runtime_id()): fail("original_enemy_setup_life_commit_failed", {})
func contains(key: StringName) -> bool: return _core.get_ref().actor_metadata_contains(_handle.get_ref(), key)
func erase(key: StringName) -> void: _core.get_ref().actor_metadata_erase(_handle.get_ref(), key)
func is_initialized() -> bool: return initialized
func mark_initialized() -> void: initialized = true
func runtime_object_is_present() -> bool: return _handle.get_ref() != null and _handle.get_ref().runtime_object_is_present()
func is_inside_world() -> bool: return _handle.get_ref().is_inside_world()
func is_queued_for_retirement() -> bool: return _handle.get_ref().is_queued_for_retirement()
func parent_scope() -> Object: return access.parent_scope(_handle.get_ref())
func can_process() -> bool: return _handle.get_ref().can_process()
func physics_processing_enabled() -> bool: return _handle.get_ref().is_physics_processing_enabled()
func set_physics_processing(value: bool) -> void:
	scope.physics_processing_enabled = value
	_handle.get_ref().set_processing_qualification(can_process(), value)
func input_pickable() -> bool: return pickable
func set_input_pickable(value: bool) -> void:
	if _motion==null or _motion.get_ref()==null or not _motion.get_ref().set_input_pickable(value):
		fail("original_enemy_native_pickable_write_failed",{});return
	pickable = value
	_core.get_ref().emit_original_main_event(&"enemy_input_pickable", [runtime_id(), value])
func process_mode() -> int: return scope.process_mode
func add_to_group(group: StringName, _persistent := false) -> void: _core.get_ref().enter_actor_group(_handle.get_ref(), group)
func remove_from_group(group: StringName) -> void: _core.get_ref().leave_actor_group(_handle.get_ref(), group)
func queue_retirement() -> void: _core.get_ref().queue_actor_retirement(runtime_id())
func world_services() -> RefCounted: return _core.get_ref().paths
func physics_delta() -> float: return float(_core.get_ref().current_clock_frame().scaled_delta)
func defer_after_damage_stack(callback: Callable) -> void: _core.get_ref().defer_original_actor_callback(runtime_id(), callback)
func create_background_wakeup_timer(callback: Callable) -> RefCounted: return _core.get_ref().create_original_node_timer(runtime_id(), callback, true, 0)
func gameplay_visual_state() -> Object: return _core.get_ref().enemy_visual_for_actor(runtime_id())
func has_overhead() -> bool: return _core.get_ref().actor_source_publication(runtime_id()).overhead_present
func set_overhead_visible(value: bool) -> void: _core.get_ref().emit_original_main_event(&"enemy_overhead_visible", [runtime_id(), value])
func configure_actor_y_sort() -> void: _core.get_ref().emit_original_main_event(&"enemy_configure_y_sort", [runtime_id()])
func redraw() -> void: _core.get_ref().emit_original_main_event(&"enemy_redraw", [runtime_id()])
func read_observer_field(key: StringName) -> Variant:
	return _core.get_ref().read_enemy_observer_field(runtime_id(), key)
func write_observer_field(key: StringName, value: Variant) -> void:
	_core.get_ref().write_enemy_observer_field(runtime_id(), key, value)
func invoke_original(method: StringName, arguments: Array) -> Variant: return _core.get_ref().enemy_original_presentation(runtime_id(), method, arguments)
func activate_original_profile(_actor: Object, clock: Callable, title: String, boss: bool, hp: int, maximum: int) -> void:
	_core.get_ref().activate_enemy_visual_at_original_ready(runtime_id(), clock, title, boss, hp, maximum)
func create_original_effect(kind: StringName, descriptor: Dictionary) -> void:
	var core: RefCounted=_core.get_ref()
	var model: RefCounted
	var configured:=false
	if kind==&"physical_projectile":
		model=preload("res://scripts/gameplay/world/world_enemy_projectile_effect_model.gd").new()
		configured=model.configure_source(core,access,descriptor)
	elif kind==&"target_magic":
		model=preload("res://scripts/gameplay/world/world_enemy_target_magic_model.gd").new()
		var visual: Object=gameplay_visual_state()
		if visual==null: fail("actual_target_magic_source_visual_missing",{});return
		configured=model.configure_source(core,descriptor,_motion.get_ref().position_screen_px(),int(visual.current_direction))
	if not configured: fail("original_enemy_effect_birth_failed",{"kind":kind});return
	core.register_cast_model(model)
func is_damage_batch(value: Variant) -> bool: return value is RefCounted and value.get_script() == Batch
func prepare_commit_context(batch: RefCounted, context: Dictionary) -> Dictionary: return batch.prepare_commit_context(_handle.get_ref(), context)
func capture_commit(batch: RefCounted, attacker: Object, before: int, after: int, amount: int, context: Dictionary) -> void:
	batch.capture_commit(_handle.get_ref(), access.canonical(attacker) if attacker != null else null, before, after, amount, context)
func scheduler() -> RefCounted: return _core.get_ref().paths.scheduler()
func create_search() -> RefCounted: return _core.get_ref().paths.create_search()
func create_polygon_pursuit(actor: Object) -> RefCounted: return _core.get_ref().paths.create_polygon_pursuit(actor)
func create_entrapment_controller() -> RefCounted: return preload("res://scripts/entrapment_boundary_controller.gd").new()
