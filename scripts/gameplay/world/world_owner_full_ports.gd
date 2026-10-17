extends RefCounted

## Real owner-local bindings for the migrated original 250 WorldSkill methods.
## Original numeric algorithms remain in those modules and RootNumeric.
const Batch := preload("res://scripts/features/runtime/damage_batch.gd")
const Warrior := preload("res://scripts/gameplay/world/world_owner_warrior_rules.gd")
const Granted := preload("res://scripts/gameplay/world/world_owner_granted_rules.gd")
var _owner := OS.get_thread_caller_id()
var _core: WeakRef
var profession: RefCounted
var equipment: RefCounted
var granted: RefCounted
var taoist: Object = preload("res://scripts/taoist_combat_math.gd")
var warrior: RefCounted
var combat: RefCounted
var mapper: RefCounted
var map_data: RefCounted
var errors: Array:
	get: return _world().feature.runtime.errors
var require_reservations: bool:
	get: return _world().feature.runtime.require_reservations
	set(value): _world().feature.runtime.require_reservations = value

func _init(core: RefCounted) -> void:
	assert(_owner != OS.get_main_thread_id())
	_core = weakref(core)
	profession = core.profile._rules.professions
	equipment = core.profile._rules.equipment
	granted = Granted.new()
	warrior = Warrior.new()
	combat = preload("res://scripts/gameplay/world/world_skill_combat_rules.gd").new()
	var configured: bool = combat.configure_contract(preload("res://scripts/combat_resolution_rules.gd")._contract_cache)
	if not configured:
		core.fault("original_combat_contract_configuration_failed",{})
		return
	mapper = core.environment_factory.coordinate_mapper
	map_data = core.environment_factory.runtime_maps

func owner_thread_id() -> int: return _owner
func _world() -> RefCounted:
	assert(OS.get_thread_caller_id() == _owner and _core.get_ref() != null)
	return _core.get_ref()
func fault(code: String, details: Dictionary = {}) -> void: _world().fault(code, details)
func is_inside_world() -> bool: return _world().is_inside_world()
func is_queued_for_retirement() -> bool: return _world().is_queued_for_retirement()
func register_cast_model(actor: Object) -> void: _world().register_cast_model(actor)
func discard_cast_birth(actor: Object) -> void: _world().discard_cast_birth(actor)
func register_passive_wake_emitter(actor: Object) -> void: _world()._root_numeric._register_passive_wake_emitter(actor)
func set_player_world_position(position: Vector2, reset_camera_follow := true) -> void: _world()._root_numeric._set_player_world_position(position, reset_camera_follow)
func try_safe_ring_teleport() -> bool: return _world()._root_numeric._try_safe_ring_teleport()
func wire_canonical_main_pet_persistence(summon: Object) -> void: _world()._root_numeric._wire_canonical_main_pet_persistence(summon)
func play_skill_audio_phase(skill: String, phase: String) -> void:
	var core: RefCounted = _world()
	var audio: Variant = core._root_numeric._fields.read_source_field(&"_audio_runtime_service")
	if audio != null:
		audio.play_event("skill.%s.%s" % [skill,phase],{"gender":core.profile.gender,"map_id":core._root_numeric.current_map_id})
func redraw_cast(actor: Object) -> void: _world().cast_presentation.redraw_cast(actor)
func refresh_target_highlights() -> void: _world()._root_numeric._refresh_target_highlights()
func show_attack_flash(origin: Vector2, direction: Vector2, hit: bool, color: Color) -> void: _world()._root_numeric._show_attack_flash(origin, direction, hit, color)
func show_error_message(message: String, duration: Variant = null) -> void:
	var hud: Variant = _world()._root_numeric.hud
	if duration == null: hud.show_error_message(message)
	else: hud.show_error_message(message,float(duration))
func show_message(message: String, duration: Variant = null) -> void:
	var hud: Variant = _world()._root_numeric.hud
	if duration == null: hud.show_message(message)
	else: hud.show_message(message,float(duration))
func update_target_hud() -> void: _world()._root_numeric._update_target_hud()
func update_warrior_states(states: Dictionary) -> void: _world()._root_numeric.hud.update_warrior_states(states)
func spawn_canonical_teleport_arrival(skill: String, destination: Vector2, direction: Vector2, snapshot: Dictionary = {}) -> void:
	if skill != "wizard.teleport": return
	var core: RefCounted = _world()
	# The original Root builds this visual-only plan from its current mapper and
	# strict release snapshot. Keep that work beside the sole Source skill owner;
	# the existing Caster channel owns physical assets and the actual Main node.
	var plan: Dictionary = {
		"success":true, "skill_id":skill, "release_id":str(snapshot.get("release_id","")),
		"canonical_geometry_contract":preload("res://scripts/skills/caster_spell_geometry.gd").CONTRACT_ID,
		"ground_gu_to_screen_position_px":Callable(core.skills,"_canonical_ground_gu_to_screen_px"),
		"operation":"canonical_visual_only", "visual":core.caster_visual.profile(skill),
		"visual_duration":core.caster_visual.animation_duration(skill,"arrival"), "visual_radius_px":72.0,
		"snapshot_validation_policy":preload("res://scripts/skills/skill_footprint_snapshot.gd").VALIDATION_STRICT_V2,
		"snapshot_validation_context":core.skills._canonical_snapshot_validation_context(core.skills._canonical_screen_px_to_ground_gu(destination)),
		"skill_footprint_snapshot":snapshot,
	}
	var arrival: Object = core.casts.create_visual(plan,destination,direction,core.skills.player,"arrival")
	if arrival != null: core.register_cast_model(arrival)
func spawn_target_aligned_melee_visual(snapshot: Dictionary, mode: String, hit: bool, anchor: Vector2, geometry: Dictionary = {}) -> void:
	var plan: Dictionary=geometry.get("target_aligned_plan",{})
	if plan.is_empty() or not bool(plan.get("target_axis_eligible",false)): return
	var resolved: Dictionary=geometry.duplicate(true)
	if not resolved.has("snapshot_validation_context"):
		resolved.snapshot_validation_context=_world().skills._canonical_snapshot_validation_context(plan.get("origin_ground_gu",Vector2.ZERO))
	resolved.snapshot_validation_context=preload("res://scripts/gameplay/presentation/original_melee_presentation_context.gd").capture_source(resolved.snapshot_validation_context,snapshot,_world().current_world_identity(),_world()._source_site)
	if resolved.snapshot_validation_context.is_empty():
		_world().fault("original_melee_Source_projection_export_failed",{});return
	_world().emit_original_main_event(&"spawn_target_aligned_melee_visual", [snapshot, mode, hit, anchor, resolved])
func build_melee_input_diagnostic(target: Object, mode: String, direction: Vector2, geometry: Dictionary,
	hittable: bool, facing: Vector2, touch: Vector2, movement: bool) -> Dictionary:
	return _world()._root_numeric._build_melee_input_diagnostic(target, mode, direction, geometry, hittable, facing, touch, movement)
func record_melee_release_diagnostic(diagnostic: Dictionary, context: Dictionary, geometry: Dictionary,
	origin: Vector2, direction: Vector2, selection: String, effect: String, targets: Array,
	count: int, eligible: bool, resolution: String, hit: bool) -> void:
	_world()._root_numeric._record_melee_release_diagnostic(diagnostic, context, geometry, origin, direction, selection, effect, targets, count, eligible, resolution, hit)
func create_damage_batch(world: RefCounted, release: String, skill: String, bindings: Array, credit: Dictionary,
	simulation_usec: int, reservation: RefCounted = null, resources: RefCounted = null, lineage: Dictionary = {},
	producer := "base", root_skill := "") -> Dictionary:
	return Batch.create(world, release, skill, bindings, credit, simulation_usec, reservation, resources, lineage, producer, root_skill)
func reserve_action(skill: String, bindings: Array, maximum: int, release: String, receivers: int) -> RefCounted:
	return _world().feature.runtime.reserve_action(skill, bindings, maximum, release, receivers)
func submit_batch(batch: RefCounted) -> bool: return _world().feature.runtime.submit_batch(batch)
func on_field_spawned(skill: String) -> void: _world().engagement.on_field_spawned(skill)
func on_ground_damage_tick(skill: String) -> void: _world().engagement.on_ground_damage_tick(skill)

func allocate_cast_model(model: RefCounted, kind: StringName) -> Object: return _world().allocate_cast_model(model, kind)
func create_summon_model(skill: String) -> Object: return _world().create_summon_model(skill)
func queue_cast_retirement(model: RefCounted) -> void: _world().queue_cast_retirement(model)
func enter_cast_group(model: RefCounted, group: StringName) -> void: _world().enter_cast_group(model, group)
func set_cast_physics_processing(model: RefCounted, enabled: bool) -> void: _world().set_cast_physics_processing(model, enabled)
