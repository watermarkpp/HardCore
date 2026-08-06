class_name SummonActor
extends CharacterBody2D

signal summon_state_changed(previous_state: int, current_state: int)

const SummonVisualRegistryScript := preload("res://scripts/summon_visual_registry.gd")
const CasterAnimationPlayerScript := preload("res://scripts/caster_skill_animation_player.gd")
const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")
const SkillFootprintSnapshotScript := preload(
	"res://scripts/skills/skill_footprint_snapshot.gd"
)
const WorldSpatialRulesScript := preload("res://scripts/world_spatial_rules.gd")
const CombatUnitLegacyAdapterScript := preload(
	"res://scripts/skills/combat_unit_legacy_adapter.gd"
)

const SPATIAL_CONTRACT_ID := "skills.summon_actor.spatial_ground_gu.v1"
const SPAWN_FOOTPRINT_CONTRACT_ID := (
	"skills.summon.spawn_destination_footprint_snapshot.v1"
)
const ATTACK_FOOTPRINT_CONTRACT_ID := (
	"skills.summon.attack_release_footprint_snapshot.v1"
)
const RECALL_OFFSET_GU := (
	42.0 / CombatUnitLegacyAdapterScript.ISO_AREA_EQUIVALENT_PX_PER_GU
)

enum SummonState {
	FOLLOW_OWNER,
	ACQUIRE_TARGET,
	CHASE_TARGET,
	ATTACK_TARGET,
	RETURN_TO_OWNER,
	EXPIRED,
	DEAD,
}

const VISUAL_PATHS := {
	"taoist.summon_skeleton": "res://assets/art/characters/taoist/effects/summon_skeleton.png",
	"taoist.summon_divine_beast": "res://assets/art/characters/taoist/effects/summon_divine_beast.png",
}

var owner_player: PlayerCharacter
var runtime_map_id: int = -1
var runtime_ground_gu_to_screen_position_px := Callable()
var summon_name := "骷髅"
var summon_id := "skeleton"
var skill_id := "taoist.summon_skeleton"
var skill_level := 0
var summon_level := 0
var summon_exp_level := 0
var summon_count := 1
var attack_type := "physical"
var max_hp := 80
var current_hp := 80
var attack_min := 3
var attack_max := 6
var attack_interval := 1.25
var lifetime_seconds := 864000.0
var remaining_lifetime := 864000.0
var move_speed_gu_per_sec := (
	CombatUnitLegacyAdapterScript.legacy_isometric_screen_scalar_px_to_gu(135.0)
)
var attack_range_gu := (
	CombatUnitLegacyAdapterScript.legacy_isometric_screen_scalar_px_to_gu(48.0)
)
var aggro_radius_gu := (
	CombatUnitLegacyAdapterScript.legacy_isometric_screen_scalar_px_to_gu(330.0)
)
var combat_radius_gu := (
	CombatUnitLegacyAdapterScript.legacy_isometric_screen_scalar_px_to_gu(15.0)
)
var collision_radius_px := 15.0
var leash_range_gu := (
	CombatUnitLegacyAdapterScript.legacy_isometric_screen_scalar_px_to_gu(560.0)
)
var teleport_range_gu := (
	CombatUnitLegacyAdapterScript.legacy_isometric_screen_scalar_px_to_gu(900.0)
)
var follow_distance_gu := (
	CombatUnitLegacyAdapterScript.legacy_isometric_screen_scalar_px_to_gu(75.0)
)
var actual_ground_motion_gu := Vector2.ZERO
var owner_death_rule := "expire"
var reject_when_owner_has_slave := true
var recall_existing_on_create_failure := false
var state := SummonState.FOLLOW_OWNER
var last_attack_type := ""
var summon_release_id := ""
var summon_spawn_footprint_snapshot: Dictionary = {}
var last_attack_footprint_snapshot: Dictionary = {}
var last_attack_relation := ""
var _attack_timer := 0.0
var _attack_release_sequence := 0
var _rng := RandomNumberGenerator.new()
var _sprite: Sprite2D
var _current_target: EnemyActor
var _animation_resources: Dictionary = {}
var _visual_state := "idle"
var _visual_direction := 0
var _visual_frame := 0
var _visual_elapsed := 0.0
var _visual_facing := Vector2.DOWN
var _attack_visual_remaining := 0.0
var _hit_visual_remaining := 0.0
var _death_visual_remaining := 0.0
var _visual_activation_retry := 0.0


func setup(player: PlayerCharacter, display_name: String, power: int, learned_level := -1, source_skill_id := "", owner_level_value := -1) -> void:
	owner_player = player
	var inferred_skill_id := source_skill_id
	if inferred_skill_id.is_empty():
		inferred_skill_id = "taoist.summon_divine_beast" if display_name == "神兽" else "taoist.summon_skeleton"
	var inferred_level := learned_level
	if inferred_level < 0 and PlayerState != null:
		inferred_level = PlayerState.effective_skill_level(ProfessionRules.skill_display_name(inferred_skill_id))
	var inferred_owner_level := owner_level_value
	if inferred_owner_level < 1 and PlayerState != null:
		inferred_owner_level = PlayerState.level
	var profile := TaoistCombatMath.summon_profile(inferred_skill_id, maxi(0, inferred_level), maxi(1, inferred_owner_level), maxi(1, power))
	skill_id = inferred_skill_id
	skill_level = int(profile.get("skill_level", 0))
	summon_level = int(profile.get("summon_level", skill_level))
	summon_exp_level = int(profile.get("summon_exp_level", skill_level))
	summon_count = int(profile.get("summon_count", 1))
	summon_id = str(profile.get("summon_id", "skeleton"))
	summon_name = str(profile.get("display_name", display_name))
	attack_type = str(profile.get("attack_type", "physical"))
	max_hp = int(profile.get("max_hp", 60 + power * 12))
	current_hp = max_hp
	attack_min = int(profile.get("attack_min", maxi(1, int(power / 2))))
	attack_max = int(profile.get("attack_max", maxi(attack_min, power)))
	attack_interval = float(profile.get("attack_interval", 1.25))
	lifetime_seconds = float(profile.get("lifetime_seconds", 864000.0))
	remaining_lifetime = lifetime_seconds
	move_speed_gu_per_sec = float(profile.get(
		"move_speed_gu_per_sec",
		CombatUnitLegacyAdapterScript.legacy_isometric_screen_scalar_px_to_gu(
			155.0 if summon_id == "divine_beast" else 135.0
		)
	))
	attack_range_gu = float(profile.get(
		"attack_range_gu",
		CombatUnitLegacyAdapterScript.legacy_isometric_screen_scalar_px_to_gu(
			72.0 if summon_id == "divine_beast" else 48.0
		)
	))
	aggro_radius_gu = float(profile.get(
		"aggro_radius_gu",
		CombatUnitLegacyAdapterScript.legacy_isometric_screen_scalar_px_to_gu(
			380.0 if summon_id == "divine_beast" else 330.0
		)
	))
	leash_range_gu = float(profile.get(
		"leash_range_gu",
		CombatUnitLegacyAdapterScript.legacy_isometric_screen_scalar_px_to_gu(
			560.0
		)
	))
	teleport_range_gu = float(profile.get(
		"teleport_range_gu",
		CombatUnitLegacyAdapterScript.legacy_isometric_screen_scalar_px_to_gu(
			900.0
		)
	))
	follow_distance_gu = float(profile.get(
		"follow_distance_gu",
		CombatUnitLegacyAdapterScript.legacy_isometric_screen_scalar_px_to_gu(
			75.0
		)
	))
	owner_death_rule = str(profile.get("owner_death_rule", "expire"))
	reject_when_owner_has_slave = bool(profile.get("reject_when_owner_has_slave", true))
	recall_existing_on_create_failure = bool(profile.get("recall_existing_on_create_failure", false))
	state = SummonState.FOLLOW_OWNER


func configure_spawn_release_footprint(source_release_id: String) -> void:
	summon_release_id = (
		source_release_id
		if not source_release_id.is_empty()
		else "%s:summon:%d" % [skill_id, get_instance_id()]
	)
	var spawn_combat_radius_gu := (
		WorldSpatialRulesScript.actor_combat_radius_gu_from_screen_radius_px(
			21.0 if summon_id == "divine_beast" else 15.0
		)
	)
	var spawn_center_ground_gu := (
		GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(global_position)
	)
	summon_spawn_footprint_snapshot = (
		SkillFootprintSnapshotScript.create_target_footprint(
			skill_id,
			summon_release_id,
			spawn_center_ground_gu,
			spawn_combat_radius_gu,
			get_instance_id(),
			_snapshot_coordinate_context(spawn_center_ground_gu)
		)
	)


func configure_runtime_map_projection(
	map_id: int,
	ground_gu_to_screen_position_px: Callable
) -> void:
	runtime_map_id = int(map_id)
	runtime_ground_gu_to_screen_position_px = (
		ground_gu_to_screen_position_px
		if ground_gu_to_screen_position_px is Callable
		else Callable()
	)


func _snapshot_coordinate_context(origin_ground_gu: Vector2) -> Dictionary:
	return SkillFootprintSnapshotScript.make_absolute_runtime_context(
		runtime_map_id,
		origin_ground_gu,
		origin_ground_gu,
		runtime_ground_gu_to_screen_position_px
	)


func _ready() -> void:
	add_to_group("summons")
	add_to_group("combat_targets")
	add_to_group("zone_content")
	collision_layer = WorldSpatialRulesScript.PLAYER_LAYER
	collision_mask = (
		WorldSpatialRulesScript.WORLD_LAYER
		| WorldSpatialRulesScript.ENEMY_LAYER
	)
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	safe_margin = 0.35
	max_slides = 6
	_rng.randomize()
	var collision := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	collision_radius_px = 15.0 if summon_id == "skeleton" else 21.0
	combat_radius_gu = (
		WorldSpatialRulesScript.actor_combat_radius_gu_from_screen_radius_px(
			collision_radius_px
		)
	)
	shape.radius = collision_radius_px
	collision.shape = shape
	add_child(collision)
	_install_visual()
	queue_redraw()


func _process(delta: float) -> void:
	if summon_id != "divine_beast":
		return
	_attack_visual_remaining = maxf(0.0, _attack_visual_remaining - delta)
	_hit_visual_remaining = maxf(0.0, _hit_visual_remaining - delta)
	if state == SummonState.DEAD:
		_death_visual_remaining = maxf(0.0, _death_visual_remaining - delta)
		if _death_visual_remaining <= 0.0:
			queue_free()
			return
	if _animation_resources.is_empty():
		_visual_activation_retry = maxf(0.0, _visual_activation_retry - delta)
		if _visual_activation_retry <= 0.0:
			_visual_activation_retry = 0.25
			activate_visual_resources()
		return
	var next_visual_state := "idle"
	if state == SummonState.DEAD:
		next_visual_state = "death"
	elif _hit_visual_remaining > 0.0:
		next_visual_state = "hit"
	elif _attack_visual_remaining > 0.0:
		next_visual_state = "attack"
	elif velocity.length_squared() > 25.0:
		next_visual_state = "walk"
	if next_visual_state != _visual_state:
		_visual_state = next_visual_state
		_visual_elapsed = 0.0
	else:
		_visual_elapsed += delta
	if velocity.length_squared() > 25.0:
		_visual_facing = velocity.normalized()
	elif is_instance_valid(_current_target):
		var target_offset := _current_target.global_position - global_position
		if target_offset.length_squared() > 0.001:
			_visual_facing = target_offset.normalized()
	elif is_instance_valid(owner_player) and owner_player.facing.length_squared() > 0.001:
		_visual_facing = owner_player.facing.normalized()
	_visual_direction = ArtSpec.mir2_client_direction_row(_visual_facing)
	var frame_count := int(_animation_resources.get("frame_counts", {}).get(_visual_state, 1))
	var frame_ms := int(_animation_resources.get("frame_ms", {}).get(_visual_state, 100))
	if _visual_state in ["attack", "hit", "death"]:
		_visual_frame = mini(frame_count - 1, int(floor(_visual_elapsed * 1000.0 / float(maxi(1, frame_ms)))))
	else:
		_visual_frame = int(floor(_visual_elapsed * 1000.0 / float(maxi(1, frame_ms)))) % frame_count
	_apply_visual_frame()


func _physics_process(delta: float) -> void:
	if state == SummonState.DEAD:
		velocity = Vector2.ZERO
		actual_ground_motion_gu = Vector2.ZERO
		return
	_attack_timer = maxf(0.0, _attack_timer - delta)
	remaining_lifetime = maxf(0.0, remaining_lifetime - delta)
	if remaining_lifetime <= 0.0:
		_expire()
		return
	if not is_instance_valid(owner_player) or owner_player.current_hp <= 0:
		_expire()
		return
	var owner_distance_gu := distance_gu_to_screen_position_px(
		owner_player.global_position
	)
	if owner_distance_gu >= teleport_range_gu:
		_set_state(SummonState.RETURN_TO_OWNER)
		var owner_facing_ground_gu := (
			GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(
				owner_player.facing
			).normalized()
		)
		var recall_offset_ground_gu := Vector2(
			-owner_facing_ground_gu.y,
			owner_facing_ground_gu.x
		) * RECALL_OFFSET_GU
		global_position = (
			owner_player.global_position
			+ GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(
				recall_offset_ground_gu
			)
		)
		velocity = Vector2.ZERO
		actual_ground_motion_gu = Vector2.ZERO
		queue_redraw()
		return
	if not is_instance_valid(_current_target) or _current_target.is_queued_for_deletion():
		if state not in [SummonState.FOLLOW_OWNER, SummonState.RETURN_TO_OWNER]:
			_set_state(SummonState.ACQUIRE_TARGET)
		_current_target = _nearest_enemy()
	var enemy := _current_target
	if (
		enemy != null
		and _distance_gu_between_screen_positions_px(
			enemy.global_position, owner_player.global_position
		) > leash_range_gu
	):
		_current_target = null
		enemy = null
	if enemy != null:
		var offset_screen_px := enemy.global_position - global_position
		if target_footprint_surface_distance_gu(
			enemy.global_position,
			_target_combat_radius_gu(enemy)
		) <= attack_range_gu + GroundUnitSpaceScript.EPSILON_GU:
			_set_state(SummonState.ATTACK_TARGET)
			velocity = Vector2.ZERO
			if _attack_timer <= 0.0:
				_attack_timer = attack_interval
				last_attack_type = attack_type
				_attack_visual_remaining = _visual_action_duration("attack")
				last_attack_footprint_snapshot = (
					create_attack_release_footprint_snapshot(enemy)
				)
				if attack_release_snapshot_intersects_target(
					last_attack_footprint_snapshot, enemy
				):
					enemy.take_damage(
						_rng.randi_range(attack_min, attack_max), self
					)
		else:
			_set_state(SummonState.CHASE_TARGET)
			velocity = _screen_velocity_toward_delta_px(offset_screen_px)
	else:
		var owner_offset_screen_px := owner_player.global_position - global_position
		if owner_distance_gu > follow_distance_gu:
			_set_state(SummonState.RETURN_TO_OWNER)
			velocity = _screen_velocity_toward_delta_px(
				owner_offset_screen_px
			)
		else:
			_set_state(SummonState.FOLLOW_OWNER)
			velocity = Vector2.ZERO
	var position_before_move_px := global_position
	move_and_slide()
	actual_ground_motion_gu = (
		GroundUnitSpaceScript.actual_ground_motion_gu_from_screen_positions(
			position_before_move_px,
			global_position
		)
	)
	queue_redraw()


func _expire() -> void:
	if state == SummonState.EXPIRED or state == SummonState.DEAD:
		return
	_set_state(SummonState.EXPIRED)
	velocity = Vector2.ZERO
	queue_free()


func _set_state(next_state: int) -> void:
	if state == next_state:
		return
	var previous_state := state
	state = next_state
	summon_state_changed.emit(previous_state, state)


func _nearest_enemy() -> EnemyActor:
	var nearest: EnemyActor
	var nearest_distance_gu := INF
	var nearest_instance_id := 0
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		if not node is EnemyActor or node.is_queued_for_deletion():
			continue
		var distance_gu := target_footprint_surface_distance_gu(
			node.global_position,
			_target_combat_radius_gu(node)
		)
		if distance_gu > aggro_radius_gu + GroundUnitSpaceScript.EPSILON_GU:
			continue
		var instance_id := int(node.get_instance_id())
		if (
			distance_gu < nearest_distance_gu - GroundUnitSpaceScript.EPSILON_GU
			or (
				is_equal_approx(distance_gu, nearest_distance_gu)
				and (nearest == null or instance_id < nearest_instance_id)
			)
		):
			nearest = node
			nearest_distance_gu = distance_gu
			nearest_instance_id = instance_id
	return nearest


func spatial_contract_snapshot() -> Dictionary:
	return {
		"contract_id": SPATIAL_CONTRACT_ID,
		"unit_contract_id": GroundUnitSpaceScript.CONTRACT_ID,
		"move_speed_gu_per_sec": move_speed_gu_per_sec,
		"attack_range_gu": attack_range_gu,
		"aggro_radius_gu": aggro_radius_gu,
		"combat_radius_gu": combat_radius_gu,
		"leash_range_gu": leash_range_gu,
		"teleport_range_gu": teleport_range_gu,
		"follow_distance_gu": follow_distance_gu,
	}


func create_attack_release_footprint_snapshot(target: Node2D) -> Dictionary:
	if not is_instance_valid(target):
		return {}
	var origin_ground_gu := (
		GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(global_position)
	)
	var target_ground_gu := (
		GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(
			target.global_position
		)
	)
	var release_id := "%s:attack:%d:%d" % [
		skill_id,
		get_instance_id(),
		_attack_release_sequence,
	]
	_attack_release_sequence += 1
	var reach_from_center_gu := combat_radius_gu + attack_range_gu
	if summon_id == "divine_beast":
		last_attack_relation = "directed_core"
		return SkillFootprintSnapshotScript.create_directed_rectangle(
			skill_id,
			release_id,
			origin_ground_gu,
			GroundUnitSpaceScript.normalized_ground_direction(
				origin_ground_gu, target_ground_gu
			),
			reach_from_center_gu,
			combat_radius_gu * 2.0,
			0.0,
			0.0,
			0.0,
			"",
			_snapshot_coordinate_context(origin_ground_gu)
		)
	last_attack_relation = "release_contact"
	return SkillFootprintSnapshotScript.create_circle(
		skill_id,
		release_id,
		origin_ground_gu,
		reach_from_center_gu,
		SkillFootprintSnapshotScript.DEFAULT_CURVE_SEGMENTS,
		_snapshot_coordinate_context(origin_ground_gu)
	)


func attack_release_snapshot_intersects_target(
	attack_snapshot: Dictionary,
	target: Node2D
) -> bool:
	if not bool(SkillFootprintSnapshotScript.validate_for_consumer(
		attack_snapshot,
		_snapshot_coordinate_context(
			GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(
				global_position
			)
		),
		SkillFootprintSnapshotScript.VALIDATION_STRICT_V2
	).get("valid", false)):
		return false
	return SkillFootprintSnapshotScript.intersects_target_combat_footprint_ground_gu(
		attack_snapshot,
		GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(
			target.global_position
		),
		_target_combat_radius_gu(target)
	)


func distance_gu_to_screen_position_px(target_screen_position_px: Vector2) -> float:
	return _distance_gu_between_screen_positions_px(
		global_position,
		target_screen_position_px
	)


func target_footprint_surface_distance_gu(
	target_screen_position_px: Vector2,
	target_combat_radius_gu: float
) -> float:
	return maxf(
		0.0,
		distance_gu_to_screen_position_px(target_screen_position_px)
		- combat_radius_gu
		- maxf(0.0, target_combat_radius_gu)
	)


static func _target_combat_radius_gu(target: Node) -> float:
	if not is_instance_valid(target):
		return 0.0
	for property: Dictionary in target.get_property_list():
		if str(property.get("name", "")) == "combat_radius_gu":
			return maxf(0.0, float(target.get("combat_radius_gu")))
	return 0.0


func _screen_velocity_toward_delta_px(delta_screen_px: Vector2) -> Vector2:
	var direction_ground_gu := (
		GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(
			delta_screen_px
		)
	)
	return GroundUnitSpaceScript.desired_screen_velocity_px_per_sec(
		direction_ground_gu,
		move_speed_gu_per_sec
	)


static func _distance_gu_between_screen_positions_px(
	first_screen_position_px: Vector2,
	second_screen_position_px: Vector2
) -> float:
	return GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(
		second_screen_position_px - first_screen_position_px
	).length()


func take_damage(amount: int) -> void:
	current_hp = maxi(0, current_hp - maxi(1, amount))
	if current_hp == 0:
		_set_state(SummonState.DEAD)
		velocity = Vector2.ZERO
		_hit_visual_remaining = 0.0
		_attack_visual_remaining = 0.0
		_death_visual_remaining = _visual_action_duration("death")
		_visual_state = "death"
		_visual_elapsed = 0.0
	elif summon_id == "divine_beast":
		_hit_visual_remaining = _visual_action_duration("hit")
		_visual_state = "hit"
		_visual_elapsed = 0.0
	queue_redraw()


func state_name() -> String:
	return SummonState.keys()[state]


func _install_visual() -> void:
	if summon_id == "divine_beast":
		_sprite = Sprite2D.new()
		_sprite.name = "DivineBeastAnimatedBody"
		_sprite.centered = false
		_sprite.region_enabled = true
		_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(_sprite)
		activate_visual_resources()
		return
	if skill_id == "taoist.summon_skeleton":
		var skeleton_animation := CasterAnimationPlayerScript.new()
		if not skeleton_animation.configure(skill_id, Vector2.DOWN, 0.0):
			skeleton_animation.queue_free()
			return
		skeleton_animation.name = "SkeletonPrimaryStandAnimation"
		_sprite = skeleton_animation
		add_child(_sprite)
		return
	var texture := CasterSkillVisualRegistry.texture(skill_id)
	if texture == null:
		return
	_sprite = Sprite2D.new()
	_sprite.texture = texture
	var maximum_dimension := maxf(float(texture.get_width()), float(texture.get_height()))
	var desired_size := 64.0 if summon_id == "divine_beast" else 50.0
	_sprite.scale = Vector2.ONE * desired_size / maxf(1.0, maximum_dimension)
	_sprite.position = Vector2(0, -12)
	add_child(_sprite)


func activate_visual_resources() -> bool:
	if summon_id != "divine_beast":
		return _sprite != null
	var profile := SummonVisualRegistryScript.profile(summon_id)
	if profile.is_empty():
		return false
	_animation_resources = profile
	var frame_size: Vector2i = profile.get("frame_size", Vector2i.ZERO)
	var foot_anchor: Vector2i = profile.get("foot_anchor", Vector2i.ZERO)
	var actor_ground_offset: Vector2i = profile.get("actor_ground_offset", Vector2i.ZERO)
	_sprite.position = -Vector2(foot_anchor + actor_ground_offset)
	_sprite.region_rect = Rect2(Vector2.ZERO, frame_size)
	refresh_visual_after_activation()
	return true


func refresh_visual_after_activation() -> void:
	if _animation_resources.is_empty() or _sprite == null:
		return
	_visual_state = "death" if state == SummonState.DEAD else "idle"
	_visual_direction = ArtSpec.mir2_client_direction_row(_visual_facing)
	_visual_frame = 0
	_visual_elapsed = 0.0
	_apply_visual_frame()


func _apply_visual_frame() -> void:
	if _animation_resources.is_empty() or _sprite == null:
		return
	var frame_size: Vector2i = _animation_resources.get("frame_size", Vector2i.ZERO)
	_sprite.texture = _animation_resources.get(_visual_state, null)
	_sprite.region_rect = Rect2(
		_visual_frame * frame_size.x,
		_visual_direction * frame_size.y,
		frame_size.x,
		frame_size.y
	)


func _visual_action_duration(action_name: String) -> float:
	if _animation_resources.is_empty():
		return 1.2 if action_name == "death" else 0.2
	var frame_count := int(_animation_resources.get("frame_counts", {}).get(action_name, 1))
	var frame_ms := int(_animation_resources.get("frame_ms", {}).get(action_name, 100))
	return float(frame_count * frame_ms) / 1000.0


func _draw() -> void:
	var color := Color(0.88, 0.72, 0.35) if summon_name == "神兽" else Color(0.72, 0.74, 0.70)
	var radius := 21.0 if summon_name == "神兽" else 15.0
	draw_set_transform(Vector2(0, 5), 0.0, Vector2(1.0, 0.36))
	draw_circle(Vector2.ZERO, radius, Color(0, 0, 0, 0.28))
	draw_circle(Vector2(0, -1), radius * 0.56, Color(0, 0, 0, 0.56))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if _sprite == null and summon_id != "divine_beast":
		draw_circle(Vector2(0, -4), radius, color)
		draw_circle(Vector2(-6, -7), 2.5, Color(0.15, 0.75, 0.35))
		draw_circle(Vector2(6, -7), 2.5, Color(0.15, 0.75, 0.35))
	draw_rect(Rect2(-22, -35, 44, 4), Color(0.10, 0.03, 0.03, 0.9))
	draw_rect(Rect2(-22, -35, 44.0 * float(current_hp) / float(max_hp), 4), Color(0.22, 0.72, 0.25))
