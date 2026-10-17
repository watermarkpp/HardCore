extends RefCounted

## Read-only Source capture leaf. It reads the existing model/handle/visual;
## it never updates pose, HP, action state, RNG, or a Resource/Node on Main.
const Contract := preload("res://scripts/gameplay/presentation/actor_visual_projection_contract.gd")

static func capture_original(core: RefCounted, handle: Object, model: RefCounted, visual: RefCounted,
	sequence: int, advance_visual: bool, delta: float) -> Dictionary:
	if core == null or handle == null or model == null or core.owner_thread_id() != OS.get_thread_caller_id(): return {}
	var identity: Dictionary = _actual_render_identity(core,handle,model)
	if identity.is_empty(): return {}
	var frame: Dictionary = core.current_clock_frame()
	for key: String in ["epoch","source_process_frame","source_physics_frame"]:
		if not frame.get(key) is int: return {}
	var kind: String = str(handle.kind())
	var position: Vector2
	var velocity: Vector2
	if kind == "player":
		# The canonical PlayerModel delegates to the sole S-owned native motion
		# controller; global_position/velocity belong to the old Node facade.
		if model.motion == null: return {}
		position = model.motion.position_screen_px()
		velocity = model.motion.velocity_screen_px_per_sec()
	else:
		position = model.global_position
		velocity = model.velocity
	var actor: Dictionary = {"position_screen_px":position,"velocity":velocity,"facing":model.facing,
		"current_hp":model.current_hp,"max_hp":model.max_hp,"control_time":float(model.control_time),
		"source_present":handle.runtime_object_is_present(),"source_inside_world":handle.is_inside_world(),"source_retiring":handle.is_queued_for_retirement()}
	var profile: Dictionary = {}; var enemy_visual: Dictionary = {}; var enemy_root: Dictionary = {}
	var combat_time: float
	if kind == "player":
		actor.poison_remaining = float(model.poison_status_remaining())
		actor.movement_facing = model.movement_facing; actor.actual_motion_facing = model.actual_motion_facing
		actor.movement_input_active = model.movement_input_active; actor.locomotion_state = model.locomotion_state
		profile = {"profession_id":model.profile.profession_id,"gender":model.profile.gender,"level":model.profile.level,"equipment":model.profile.equipment}
		combat_time = model._combat_action_time_getter()
	elif kind == "enemy":
		if visual == null: return {} # No fabricated visual-present/final-art fact.
		actor.poison_remaining = float(model.poison_time); actor.charm_time = float(model.charm_time)
		actor.is_boss = model.is_boss; actor.dying = model._dying; actor.targeted = model.is_targeted
		actor.boss_phase_two = model._boss_phase_two; actor.boss_warning = float(model._boss_warning)
		actor.monster_id = model.monster_id; actor.display_name = model.display_name; actor.monster_data = model.monster_data
		actor.spawn_context = model.metadata.read("spawn_context",{})
		enemy_visual = visual.render_snapshot_at_original_boundary()
		enemy_visual.dying = model._dying; enemy_visual.targeted = model.is_targeted
		var observer: RefCounted = core._enemy_presentation[identity.runtime_id]
		var warning_polygon := PackedVector2Array()
		var procedural: bool = observer.should_draw_synthetic_ground_shadow()
		var fallback := {"attacking":false,"scale":Vector2.ONE,"angle":0.0,"progress":0.0,"offset":Vector2.ZERO}
		if not model._dying:
			fallback.attacking = procedural and visual.is_fallback_attacking()
			if fallback.attacking: fallback.offset = visual.fallback_lunge_offset_px(model.facing)
			if procedural:
				fallback.scale = visual.fallback_attack_scale()
				fallback.angle = float(visual.fallback_attack_angle(model.facing))
			if fallback.attacking: fallback.progress = float(visual.fallback_attack_progress())
		if not model._dying and model._boss_warning > 0.0:
			warning_polygon = model.boss_warning_polygon_px(model.boss_rule.get("specialSkill",{}))
		enemy_root = {"ground_center":observer.ground_indicator_center(),"ground_radii":observer.ground_indicator_radii(),
			"poison_center":observer.poison_indicator_center(),"red_poison_center":observer.red_poison_indicator_center(),
			"health_bar_anchor_y":float(observer.health_bar_anchor_y()),"procedural_fallback":procedural,
			"red_poison_active":model.canonical_red_poison_active(),"warning_polygon":warning_polygon,
			"warning_is_cone":str(model._boss_skill_footprint_snapshot.get("shape_type","")) == "sector_arc",
			"fallback":fallback}
		combat_time = model._combat_action_time_getter()
	else: return {}
	var publication: Dictionary = {"contract_id":Contract.PREMAP_PLAYER_CONTRACT if identity.world.runtime_map_id == -1 else Contract.CONTRACT,"identity":identity,"kind":kind,"publication_sequence":sequence,
		"source_process_frame":frame.source_process_frame,"source_physics_frame":frame.source_physics_frame,"clock_epoch":frame.epoch,
		"scaled_delta":delta,"advance_visual":advance_visual,"combat_time_s":combat_time,"actor":actor,"profile":profile,
		"enemy_visual":enemy_visual,"enemy_root":enemy_root}
	if not Contract.validate_presentation(publication): return {}
	return Contract.capture(publication)

static func _actual_render_identity(core: RefCounted, handle: Object, model: RefCounted) -> Dictionary:
	var formal: Dictionary = handle.identity()
	if Contract.valid_identity(formal): return formal
	var world: Dictionary = core.current_world_identity()
	if handle.kind() != &"player" or core.registry.resolve_runtime_actor(handle.get_instance_id()) != handle or handle.model() != model or model.get_script() != preload("res://scripts/gameplay/actors/player_actor_model.gd") or world.get("runtime_map_id") != -1 or world.get("world_epoch") != 0: return {}
	var life: Variant = model.current_life()
	if not life is int or life < 0: return {}
	# Actual registered runtime, solely as a display descriptor. ActorHandle,
	# ActorRef, target eligibility and damage continue to reject life zero.
	return {"world":world,"runtime_id":handle.get_instance_id(),"life_generation":life}

class PlayerVisualProcessPublisher:
	extends RefCounted
	var _core: WeakRef
	var _runtime_id: int
	var _owner := OS.get_thread_caller_id()
	func _init(core: RefCounted, runtime_id: int) -> void: _core = weakref(core); _runtime_id = runtime_id
	func owner_thread_id() -> int: return _owner
	func _process(delta: float) -> bool:
		if OS.get_thread_caller_id() != _owner or _core.get_ref() == null: return false
		return _core.get_ref().publish_original_actor_visual_projection(_runtime_id,true,delta)
