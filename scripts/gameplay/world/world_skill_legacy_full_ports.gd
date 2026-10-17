extends "res://scripts/gameplay/world/legacy_world_skill_ports.gd"

## M-only facade over the original GameRoot/Node authorities. Every method
## checks the inherited Main owner. S uses WorldSkillActorPort and WorldCore.
const LegacyLinkMap := preload("res://scripts/gameplay/world/world_skill_legacy_link_map.gd")
const LegacyLinkSequence := preload("res://scripts/gameplay/world/world_skill_legacy_link_sequence.gd")
const LegacyActorLink := preload("res://scripts/gameplay/world/world_skill_legacy_actor_link.gd")
var _field_map: RefCounted
var _arrival_sequence: RefCounted
var profession: Object = ProfessionRules
var equipment: Object = preload("res://scripts/equipment_rules.gd")
var granted: Object = preload("res://scripts/equipment_granted_skill_rules.gd")
var taoist: Object = TaoistCombatMath
var warrior: Object = WarriorCombatMath
var combat: Object = preload("res://scripts/combat_resolution_rules.gd")
var mapper: Object = preload("res://scripts/map_coordinate_mapper.gd")
var map_data: Object = preload("res://scripts/layers/runtime/map_editor_runtime_bridge.gd")

var EnemyMagicDeliveryKind = preload("res://scripts/layers/runtime/combat_runtime_service.gd").EnemyMagicDeliveryKind
var SummonState = SummonActor.SummonState
var errors: Array:
	get: return _root()._feature_effect_runtime.errors if _root() != null and _root()._feature_effect_runtime != null else []
var require_reservations: bool:
	get: return _root() != null and _root()._feature_effect_runtime != null and _root()._feature_effect_runtime.require_reservations
	set(value):
		if _feature() != null: _feature().require_reservations = value

func full_bindings(domain: RefCounted) -> Dictionary:
	var root := _root()
	assert(root != null)
	_field_map = LegacyLinkMap.new(root)
	_arrival_sequence = LegacyLinkSequence.new(root)
	return {"fields":self,"profile":PlayerState._model,"input":self,"clock":self,"actors":self,
		"execution":domain,"presentation":self,"world":self,"random":root._rng,"rules":self,"geometry":self,
		"casting":self,"diagnostics":self,"engagement":self,"combat":self,"spatial":root._combat_spatial_index,
		"world_context":root._world_context,"time_domains":root._time_domains,
		"feature_runtime":self,"feature_target_bound":root._feature_target_bound,
		"legacy_planner":preload("res://scripts/skills/skill_runtime_router.gd"),
		"legacy_plan_contract":preload("res://scripts/skills/skill_execution_plan_contract.gd")}

func read_field(name: String) -> Variant:
	var root := _root()
	if root == null: return null
	if name == "_fire_wall_field_registry": return _field_map
	if name == "_pending_main_pet_arrivals": return _arrival_sequence
	return root.get(name)

func now_usec() -> int:
	assert(_root() != null)
	return Time.get_ticks_usec()

func set_locked_target(actor: Object) -> void:
	assert(_root() != null)
	_root().locked_target = actor

func magic_locked_target() -> Object:
	return _root().magic_locked_target if _root() != null else null

func set_magic_locked_target(actor: Object) -> void:
	assert(_root() != null)
	_root().magic_locked_target = actor

func cast_target() -> Object:
	return _root()._skill_cast_target if _root() != null else null

func set_cast_target(actor: Object) -> void:
	assert(_root() != null)
	_root()._skill_cast_target = actor

func actor_view(actor: Object) -> Dictionary:
	if _root() == null or not is_instance_valid(actor): return {}
	return {"runtime_id":actor.get_instance_id(),"position_screen_px":actor.global_position}

func capture(actor: Object) -> RefCounted:
	assert(_root() != null)
	return LegacyActorLink.new(actor) if is_instance_valid(actor) else null

func is_runtime_present(actor: Object) -> bool:
	return _root() != null and is_instance_valid(actor)

func actors_in_group(group: StringName) -> Array[Object]:
	var result: Array[Object] = []
	assert(_root() != null)
	for actor: Object in _root().get_tree().get_nodes_in_group(group): result.append(actor)
	return result

func resolve_runtime_model(id: int) -> Object:
	assert(_root() != null)
	return instance_from_id(id)

func is_kind(actor: Object, kind: StringName) -> bool:
	if _root() == null: return false
	match kind:
		&"enemy": return actor is EnemyActor
		&"summon": return actor is SummonActor
		&"projectile": return actor is SkillProjectile
		&"field", &"ground_effect": return actor is GroundSkillEffect
		&"fire_wall": return actor is FireWallFieldController
	return false

func is_inside_world(actor: Object = null) -> bool:
	return _root().is_inside_tree() if actor == null and _root() != null else is_instance_valid(actor) and actor.is_inside_tree()

func is_queued_for_retirement(actor: Object = null) -> bool:
	return _root().is_queued_for_deletion() if actor == null and _root() != null else not is_instance_valid(actor) or actor.is_queued_for_deletion()

func is_in_parent_scope(actor: Object) -> bool:
	return _root() != null and _root().is_ancestor_of(actor)

func position_screen_px(actor: Object) -> Vector2:
	assert(_root() != null)
	return actor.global_position

func set_position_screen_px(actor: Object, value: Vector2) -> void:
	assert(_root() != null)
	actor.global_position = value

func stop_velocity(actor: Object) -> void:
	assert(_root() != null)
	actor.velocity = Vector2.ZERO

func owner_model(actor: Object) -> Object:
	assert(_root() != null)
	return actor.owner_player

func fault(code: String, details: Dictionary = {}) -> void:
	push_error("WorldSkill legacy fault: " + code + " " + str(details))

func register_cast_model(actor: Object) -> void:
	assert(_root() != null)
	_root().add_child(actor)

func discard_cast_birth(actor: Object) -> void:
	assert(_root() != null)
	actor.free()

func environment_blocks_actor_screen_px(background: Object, position: Vector2, radius: float) -> bool:
	assert(_root() != null)
	return WorldSpatialRules.environment_blocks_actor_screen_px(_root().background, position, radius)

func is_present() -> bool:
	return _root() != null and is_instance_valid(_root().background)

func is_environment_point_blocked(position: Vector2) -> bool:
	assert(_root() != null)
	return _root().background.is_environment_point_blocked(position)

func randi() -> int:
	assert(_root() != null)
	return _root()._rng.randi()

func randi_range(low: int, high: int) -> int:
	assert(_root() != null)
	return _root()._rng.randi_range(low, high)

func randf_range(low: float, high: float) -> float:
	assert(_root() != null)
	return _root()._rng.randf_range(low, high)

func global_randi_range(low: int, high: int) -> int:
	assert(_root() != null)
	return preload("res://scripts/gameplay/world/world_skill_legacy_global_random.gd").draw(low, high)

func create_fire_wall_model() -> Object:
	assert(_root() != null)
	return FireWallFieldController.new()

func create_ground_model() -> Object:
	assert(_root() != null)
	return GroundSkillEffect.new()

func create_projectile_model() -> Object:
	assert(_root() != null)
	return SkillProjectile.new()

func create_summon_model(_stable_skill_id: String = "") -> Object:
	assert(_root() != null)
	return SummonActor.new()

func setup_summon_model(summon: Object, owner: Object, display_name: String, power: int,
	learned_level := -1, source_skill_id := "", owner_level_value := -1, maximum_pet_level_value := -1) -> void:
	assert(_root() != null)
	summon.setup(owner, display_name, power, learned_level, source_skill_id, owner_level_value, maximum_pet_level_value)

func configure_summon_spatial_index(summon: Object, index: RefCounted) -> void:
	assert(_root() != null)
	summon.configure_spatial_index(index)

func create_ground_manager(spatial: RefCounted, combat: RefCounted) -> RefCounted:
	assert(_root() != null)
	return PersistentGroundEffectManager.new(spatial, _root()._combat_runtime)

func bind_field_retirement(field: Object, callback: Callable) -> void:
	assert(_root() != null)
	field.tree_exited.connect(callback)

func update_warrior_states(states: Dictionary) -> void:
	assert(_root() != null)
	_root().hud.update_warrior_states(states)

func redraw_cast(actor: Object) -> void:
	assert(_root() != null)
	actor.queue_redraw()

func _feature() -> RefCounted:
	var root := _root()
	if root == null: return null
	if root._feature_effect_runtime == null:
		root._feature_effect_runtime = preload("res://scripts/features/runtime/effect_runtime.gd").new()
		if not root._feature_effect_runtime.configure(root._world_context,root._time_domains,root._combat_runtime): return null
		if not root._feature_effect_runtime.configure_child_executor(Callable(root,"_execute_feature_child_action")): return null
	return root._feature_effect_runtime

func create_damage_batch(world: RefCounted, release_id: String, skill_id: String, bindings: Array,
	credit: Dictionary, usec: int, reservation: RefCounted, resources: RefCounted,
	chain: Dictionary = {}, source_class: String = "direct", root_skill_id: String = "") -> Dictionary:
	assert(_root() != null)
	return preload("res://scripts/features/runtime/damage_batch.gd").create(world,release_id,skill_id,bindings,credit,usec,reservation,resources,chain,source_class,root_skill_id)

func reserve_action(skill_id: String, bindings: Array, maximum: int, release_id: String, receivers: int) -> RefCounted:
	return _feature().reserve_action(skill_id,bindings,maximum,release_id,receivers) if _feature() != null else null

func submit_batch(batch: RefCounted) -> bool:
	return _feature() != null and _feature().submit_batch(batch)

func build_melee_input_diagnostic(
	target: Object,
	mode: String,
	attack_direction: Vector2,
	release_geometry: Dictionary,
	has_hittable_target: bool,
	facing_before: Vector2,
	touch_before: Vector2,
	movement_was_active: bool
) -> Dictionary:
	assert(_root() != null)
	return _root()._build_melee_input_diagnostic(target, mode, attack_direction, release_geometry, has_hittable_target, facing_before, touch_before, movement_was_active)

func play_skill_audio_phase(stable_skill_id: String, phase: String) -> void:
	assert(_root() != null)
	_root()._play_skill_audio_phase(stable_skill_id, phase)

func record_melee_release_diagnostic(
	diagnostic: Dictionary,
	context: Dictionary,
	release_geometry: Dictionary,
	origin: Vector2,
	direction: Vector2,
	selection_mode: String,
	effect_mode: String,
	primary_targets: Array,
	eligible_target_count: int,
	has_eligible_target: bool,
	canonical_resolution: String,
	hit_any: bool
) -> void:
	assert(_root() != null)
	var primary_targets_legacy: Array[EnemyActor] = []
	for value: Variant in primary_targets: primary_targets_legacy.append(value as EnemyActor)
	_root()._record_melee_release_diagnostic(diagnostic, context, release_geometry, origin, direction, selection_mode, effect_mode, primary_targets_legacy, eligible_target_count, has_eligible_target, canonical_resolution, hit_any)

func refresh_target_highlights() -> void:
	assert(_root() != null)
	_root()._refresh_target_highlights()

func register_passive_wake_emitter(emitter: Object) -> void:
	assert(_root() != null)
	_root()._register_passive_wake_emitter(emitter)

func set_player_world_position(position_px: Vector2, reset_camera_follow := true) -> void:
	assert(_root() != null)
	_root()._set_player_world_position(position_px, reset_camera_follow)

func show_attack_flash(origin: Vector2, direction: Vector2, hit: bool, color: Color) -> void:
	assert(_root() != null)
	_root()._show_attack_flash(origin, direction, hit, color)

func spawn_canonical_teleport_arrival(
	stable_skill_id: String,
	destination: Vector2,
	direction: Vector2,
	skill_release_snapshot: Dictionary = {}
) -> void:
	assert(_root() != null)
	_root()._spawn_canonical_teleport_arrival(stable_skill_id, destination, direction, skill_release_snapshot)

func spawn_target_aligned_melee_visual(
	snapshot: Dictionary,
	mode: String,
	hit_any: bool,
	anchor_screen_px: Vector2,
	release_geometry: Dictionary = {}
) -> void:
	assert(_root() != null)
	_root()._spawn_target_aligned_melee_visual(snapshot, mode, hit_any, anchor_screen_px, release_geometry)

func try_safe_ring_teleport() -> bool:
	assert(_root() != null)
	return _root()._try_safe_ring_teleport()

func update_target_hud() -> void:
	assert(_root() != null)
	_root()._update_target_hud()

func wire_canonical_main_pet_persistence(summon: Object) -> void:
	assert(_root() != null)
	_root()._wire_canonical_main_pet_persistence(summon)

func apply_damage(target: Object, amount: int) -> bool:
	assert(_root() != null)
	return _root()._combat_runtime.apply_damage(target, amount)

func apply_enemy_physical_damage(
	target: Object,
	amount: int,
	source_actor: Object = null,
	damage_context: Dictionary = {},
) -> bool:
	assert(_root() != null)
	return _root()._combat_runtime.apply_enemy_physical_damage(target, amount, source_actor, damage_context)

func apply_enemy_direct_spell_damage(
	target: Object,
	stable_skill_id: String,
	raw_damage: int,
	source_actor: Object,
	rng: RandomNumberGenerator = null,
	magic_defense_adapter := Callable(),
	anti_magic_roll := -1,
	target_stats_scratch: Dictionary = {},
	delivery_kind: int = EnemyMagicDeliveryKind.DIRECT_MAGSTRUCK,
	damage_context: Dictionary = {},
) -> Dictionary:
	assert(_root() != null)
	return _root()._combat_runtime.apply_enemy_direct_spell_damage(target, stable_skill_id, raw_damage, source_actor, rng, magic_defense_adapter, anti_magic_roll, target_stats_scratch, delivery_kind, damage_context)

func apply_feature_child_damage(target: Object, raw_damage: int, source_actor: Object,
	child_rng: RandomNumberGenerator, historical_credit: Dictionary, batch: RefCounted) -> Dictionary:
	assert(_root() != null)
	return _root()._combat_runtime.apply_feature_child_damage(target, raw_damage, source_actor, child_rng, historical_credit, batch)

func face_target_screen_px(actor: Object, target: Object) -> Vector2:
	assert(_root() != null)
	return _root()._combat_runtime.face_target_screen_px(actor, target)

func create_cast_models_from_canonical_plan(
	plan: Dictionary,
	origin: Vector2,
	direction := Vector2.DOWN,
	color := Color.WHITE,
	target: Object = null,
	owner: Object = null,
	spiritual_power := 1,
	owner_level := 1,
	summon_sink := Callable(),
	runtime_context: Dictionary = {}
) -> Array[Object]:
	assert(_root() != null)
	var values: Array[Object] = []
	for actor: Object in CasterSkillRuntime.create_cast_nodes_from_canonical_plan(plan,origin,direction,color,target,owner,spiritual_power,owner_level,summon_sink,runtime_context): values.append(actor)
	return values

func timing_start() -> int:
	assert(_root() != null)
	return RuntimeDiagnostics.timing_start()

func timing_elapsed_usec(started_usec: int) -> int:
	assert(_root() != null)
	return RuntimeDiagnostics.timing_elapsed_usec(started_usec)

func record_timing_usec(field: StringName, started_usec: int) -> int:
	assert(_root() != null)
	return RuntimeDiagnostics.record_timing_usec(field, started_usec)

func increment_performance_counter(field: StringName, amount := 1) -> void:
	assert(_root() != null)
	RuntimeDiagnostics.increment_performance_counter(field, amount)

func record_performance_max(field: StringName, value: float) -> void:
	assert(_root() != null)
	RuntimeDiagnostics.record_performance_max(field, value)

func set_performance_release_context(release_id: String, skill_id: String) -> void:
	assert(_root() != null)
	RuntimeDiagnostics.set_performance_release_context(release_id, skill_id)

func combat_capture_enabled() -> bool:
	assert(_root() != null)
	return CombatDiagnosticLog.capture_enabled()

func combat_record(raw_event: Dictionary) -> Dictionary:
	assert(_root() != null)
	return CombatDiagnosticLog.record(raw_event)

func footprint_capture_enabled() -> bool:
	assert(_root() != null)
	return SkillFootprintDiagnosticLog.capture_enabled()

func footprint_record(raw_event: Dictionary) -> Dictionary:
	assert(_root() != null)
	return SkillFootprintDiagnosticLog.record(raw_event)

func on_field_spawned(stable_skill_id: String) -> void:
	assert(_root() != null)
	AoeEngagementWindow.on_field_spawned(stable_skill_id)

func on_ground_damage_tick(stable_skill_id: String) -> void:
	assert(_root() != null)
	AoeEngagementWindow.on_ground_damage_tick(stable_skill_id)
