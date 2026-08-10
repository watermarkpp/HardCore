class_name SummonActor
extends CharacterBody2D

signal summon_state_changed(previous_state: int, current_state: int)

const SummonVisualRegistryScript := preload("res://scripts/summon_visual_registry.gd")
const WarriorCombatMathScript := preload("res://scripts/warrior_combat_math.gd")
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
	"skills.summon.attack_release_directed_gu.v2"
)
const PERSISTENCE_CONTRACT_ID := "skills.summon.persistence.runtime_state.v1"
const STEALTH_STATE_CONTRACT_ID := "skills.summon_actor.stealth_state.v1"
const BUFF_STATE_CONTRACT_ID := "skills.summon_actor.buff_state.v1"
const SUSTAINED_FRAME_COST_CONTRACT_ID := (
	"skills.summon.sustained_frame_cost.bounded.v1"
)
const VISUAL_FOOT_ANCHOR_CONTRACT_ID := (
	"skills.summon.visual_authored_ground_point_at_actor_origin.v2"
)
const LEVEL_LABEL_CONTRACT_ID := "skills.summon.level_label.current_pet_level.v1"
const TARGET_ACQUIRE_INTERVAL_SECONDS := 0.25
const RECALL_OFFSET_GU := (
	42.0 / CombatUnitLegacyAdapterScript.ISO_AREA_EQUIVALENT_PX_PER_GU
)
const STEALTH_BODY_MODULATE_ALPHA := 0.22
const BUFF_HINT_FONT_SIZE := 10
const BUFF_HINT_LINE_SPACING := 12.0
const BUFF_HINT_OFFSET_Y := 6.0
const LEVEL_LABEL_FONT_SIZE := 10
const LEVEL_LABEL_GAP_PX := 2.0
const SKELETON_ATTACK_LENGTH_GU := 1.5
const DIVINE_BEAST_ATTACK_LENGTH_GU := 3.0
const SUMMON_ATTACK_WIDTH_GU := 1.0
const _VISUAL_REQUEST_MAX_ATTEMPTS := 8

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
## Owner character level frozen at summon creation. Fully independent of the
## pet's own growth level (summon_exp_level).
var owner_level := 1
var runtime_map_id: int = -1
var runtime_ground_gu_to_screen_position_px := Callable()
var runtime_screen_to_ground_position_px := Callable()
## FREEZE-P0.1: fail-closed projection diagnostics.
var missing_projection_rejection_count := 0
var projection_rejection_reason := &""
var summon_name := "骷髅"
var summon_id := "skeleton"
var skill_id := "taoist.summon_skeleton"
var skill_level := 0
var summon_level := 0
var summon_exp_level := 0
var maximum_pet_level := 1
var pet_growth_exp := 0
var summon_count := 1
var attack_type := "physical"
var monster_level := 1
var max_hp := 80
var current_hp := 80
var attack_min := 3
var attack_max := 6
var ac_min := 0
var ac_max := 0
var mac_min := 0
var mac_max := 0
var accuracy := 1
var agility := 1
var name_color_index := 255
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
var _fire_sprite: Sprite2D
var _current_target: EnemyActor
var _animation_resources: Dictionary = {}
var _visual_profile_complete := false
var _visual_preview_active := false
var _visual_state := "idle"
var _visual_direction := 0
var _visual_frame := 0
var _visual_elapsed := 0.0
var _visual_facing := Vector2.DOWN
var _attack_visual_remaining := 0.0
var _hit_visual_remaining := 0.0
var _death_visual_remaining := 0.0
var _pending_attack_target: EnemyActor
var _pending_attack_snapshot: Dictionary = {}
var _pending_attack_release_remaining := 0.0
var _pending_attack_direction := Vector2.DOWN
var _fire_visual_elapsed := 0.0
var _fire_visual_remaining := 0.0
var _health_bar_y := -35.0
var _visual_request_id := SummonVisualRegistryScript.REQUEST_UNKNOWN
var _visual_request_attempts := 0
var _target_acquire_remaining := 0.0
var _target_scan_count := 0
var _custom_draw_request_count := 0
var _sprite_frame_apply_count := 0
var _last_buff_draw_signature := Vector2i(-1, -1)

## Independent support-buff state: stealth, physical defence (AC) and magic
## defence (MAC) each keep their own timer and refresh independently.
var stealth_remaining_seconds := 0.0
var stealth_buff_id := ""
var ac_buff_bonus := 0
var ac_buff_remaining_seconds := 0.0
var ac_buff_id := ""
var mac_buff_bonus := 0
var mac_buff_remaining_seconds := 0.0
var mac_buff_id := ""


func setup(
	player: PlayerCharacter,
	display_name: String,
	power: int,
	learned_level := -1,
	source_skill_id := "",
	owner_level_value := -1,
	maximum_pet_level_value := -1
) -> void:
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
	owner_level = maxi(1, inferred_owner_level)
	var profile := TaoistCombatMath.summon_profile(
		inferred_skill_id,
		maxi(0, inferred_level),
		owner_level,
		maxi(1, power)
	)
	skill_id = inferred_skill_id
	skill_level = int(profile.get("skill_level", 0))
	summon_level = int(profile.get("summon_level", skill_level))
	summon_exp_level = int(profile.get("summon_exp_level", skill_level))
	maximum_pet_level = (
		maximum_pet_level_value
		if maximum_pet_level_value >= 0
		else int(profile.get("max_pet_level", 1))
	)
	maximum_pet_level = clampi(maximum_pet_level, summon_exp_level, 7)
	pet_growth_exp = int(profile.get("pet_growth_exp", 0))
	summon_count = int(profile.get("summon_count", 1))
	summon_id = str(profile.get("summon_id", "skeleton"))
	summon_name = str(profile.get("display_name", display_name))
	attack_type = str(profile.get("attack_type", "physical"))
	monster_level = int(profile.get("monster_level", 1))
	max_hp = int(profile.get("max_hp", 60 + power * 12))
	current_hp = max_hp
	attack_min = int(profile.get("attack_min", maxi(1, int(power / 2))))
	attack_max = int(profile.get("attack_max", maxi(attack_min, power)))
	ac_min = int(profile.get("ac_min", 0))
	ac_max = int(profile.get("ac_max", ac_min))
	mac_min = int(profile.get("mac_min", 0))
	mac_max = int(profile.get("mac_max", mac_min))
	accuracy = int(profile.get("accuracy", 1))
	agility = int(profile.get("agility", 1))
	name_color_index = TaoistCombatMath.summon_name_color_index(summon_exp_level)
	attack_interval = float(profile.get("attack_interval", 1.25))
	lifetime_seconds = float(profile.get("lifetime_seconds", 864000.0))
	remaining_lifetime = lifetime_seconds
	move_speed_gu_per_sec = float(profile.get(
		"move_speed_gu_per_sec",
		CombatUnitLegacyAdapterScript.legacy_isometric_screen_scalar_px_to_gu(
			155.0 if summon_id == "divine_beast" else 135.0
		)
	))
	## User-authored combat geometry supersedes the legacy screen-pixel range:
	## skeleton uses the warrior-normal 1.5 GU reach and divine beast uses a
	## 3 GU by 1 GU directed footprint.
	attack_range_gu = _attack_effect_length_gu()
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
	if runtime_map_id >= 0 and not runtime_screen_to_ground_position_px.is_valid():
		# FREEZE-P0.1: mapped summon without a projection must not create a
		# formal spawn snapshot at fake/delta coordinates.
		missing_projection_rejection_count += 1
		projection_rejection_reason = (
			GroundUnitSpaceScript.REASON_MISSING_SCREEN_TO_GROUND_PROJECTION
		)
		summon_spawn_footprint_snapshot = {}
		return
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
		_runtime_screen_to_ground_position(global_position)
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
	ground_gu_to_screen_position_px: Callable,
	screen_position_px_to_ground_gu: Callable = Callable()
) -> void:
	runtime_map_id = int(map_id)
	runtime_ground_gu_to_screen_position_px = (
		ground_gu_to_screen_position_px
		if ground_gu_to_screen_position_px is Callable
		else Callable()
	)
	runtime_screen_to_ground_position_px = (
		screen_position_px_to_ground_gu
		if screen_position_px_to_ground_gu is Callable
		else Callable()
	)


func projection_ready() -> bool:
	if runtime_map_id < 0:
		return true
	return runtime_screen_to_ground_position_px.is_valid()


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
	_last_buff_draw_signature = _buff_draw_signature()
	_request_visual_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_EXIT_TREE:
		## Advance one ready ResourceLoader result so an actor teardown can still
		## contribute to the shared warm cache; ResourceLoader owns worker life.
		SummonVisualRegistryScript.reap_completed_requests()


func _process(delta: float) -> void:
	_update_support_buff_timers(delta)
	_update_stealth_visual()
	_refresh_buff_redraw_if_needed()
	_attack_visual_remaining = maxf(0.0, _attack_visual_remaining - delta)
	_hit_visual_remaining = maxf(0.0, _hit_visual_remaining - delta)
	_update_fire_visual(delta)
	if state == SummonState.DEAD:
		_death_visual_remaining = maxf(0.0, _death_visual_remaining - delta)
		if _death_visual_remaining <= 0.0:
			queue_free()
			return
	if not _visual_profile_complete:
		## The registry can finalize at most one imported texture per poll. Polling
		## each frame makes the idle-first preview visible as soon as its formal
		## Texture2D import completes without adding a blocking load.
		_poll_visual_activation()
	if _animation_resources.is_empty():
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
	if _pending_attack_target != null:
		_visual_facing = _pending_attack_direction
	elif velocity.length_squared() > 25.0:
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
	_target_acquire_remaining = maxf(
		0.0,
		_target_acquire_remaining - delta
	)
	_update_pending_attack(delta)
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
		return
	if (
		not is_instance_valid(_current_target)
		or _current_target.is_queued_for_deletion()
		or _current_target.current_hp <= 0
	):
		_current_target = null
		if _target_acquire_remaining <= 0.0:
			if state not in [SummonState.FOLLOW_OWNER, SummonState.RETURN_TO_OWNER]:
				_set_state(SummonState.ACQUIRE_TARGET)
			_current_target = _nearest_enemy()
			_target_acquire_remaining = TARGET_ACQUIRE_INTERVAL_SECONDS
	var enemy := _current_target
	if (
		enemy != null
		and _distance_gu_between_screen_positions_px(
			enemy.global_position, owner_player.global_position
		) > leash_range_gu
	):
		_current_target = null
		_target_acquire_remaining = 0.0
		enemy = null
	if enemy != null:
		var offset_screen_px := enemy.global_position - global_position
		if _target_within_attack_geometry(enemy):
			_set_state(SummonState.ATTACK_TARGET)
			velocity = Vector2.ZERO
			if _attack_timer <= 0.0 and _pending_attack_target == null:
				_begin_attack(enemy)
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


func _begin_attack(enemy: EnemyActor) -> void:
	## Entering an attack breaks group invisibility immediately, rather than
	## waiting for the delayed damage-release frame.
	if is_stealthed():
		stealth_remaining_seconds = 0.0
		stealth_buff_id = ""
		_update_stealth_visual()
	_attack_timer = attack_interval
	last_attack_type = attack_type
	_pending_attack_target = enemy
	_pending_attack_snapshot = create_attack_release_footprint_snapshot(enemy)
	last_attack_footprint_snapshot = _pending_attack_snapshot.duplicate(true)
	_pending_attack_release_remaining = _attack_release_delay_seconds()
	var target_offset := enemy.global_position - global_position
	if target_offset.length_squared() > 0.001:
		_pending_attack_direction = target_offset.normalized()
	_visual_facing = _pending_attack_direction
	_attack_visual_remaining = _visual_action_duration("attack")
	_visual_state = "attack"
	_visual_elapsed = 0.0


func _update_pending_attack(delta: float) -> void:
	if _pending_attack_target == null:
		return
	_pending_attack_release_remaining = maxf(
		0.0, _pending_attack_release_remaining - delta
	)
	if _pending_attack_release_remaining <= 0.0:
		_release_pending_attack()


func _release_pending_attack() -> void:
	var target := _pending_attack_target
	var snapshot := _pending_attack_snapshot
	if summon_id == "divine_beast":
		_start_fire_visual()
	if (
		is_instance_valid(target)
		and not target.is_queued_for_deletion()
		and target.current_hp > 0
		and attack_release_snapshot_intersects_target(snapshot, target)
		and _attack_hit_succeeds(target)
	):
		var hp_before := target.current_hp
		target.take_damage(_rng.randi_range(attack_min, attack_max), self)
		if hp_before > 0 and target.current_hp <= 0:
			gain_growth_from_kill(int(target.monster_data.get("level", 0)))
	_clear_pending_attack()


func _attack_hit_succeeds(target: EnemyActor) -> bool:
	if attack_type != "physical" or PlayerState.test_mode:
		return true
	return WarriorCombatMathScript.roll_hit(accuracy, target.agility, _rng)


func _attack_release_delay_seconds() -> float:
	if not _animation_resources.is_empty():
		var explicit_ms := int(_animation_resources.get("attack_release_ms", -1))
		if explicit_ms >= 0:
			return float(explicit_ms) / 1000.0
		var release_frame_index := 5
		var frame_ms := int(
			_animation_resources.get("frame_ms", {}).get("attack", 100)
		)
		return float(release_frame_index * frame_ms) / 1000.0
	return 0.5


func _clear_pending_attack() -> void:
	_pending_attack_target = null
	_pending_attack_snapshot = {}
	_pending_attack_release_remaining = 0.0


func _expire() -> void:
	if state == SummonState.EXPIRED or state == SummonState.DEAD:
		return
	_set_state(SummonState.EXPIRED)
	_clear_pending_attack()
	velocity = Vector2.ZERO
	queue_free()


func _set_state(next_state: int) -> void:
	if state == next_state:
		return
	var previous_state := state
	state = next_state
	summon_state_changed.emit(previous_state, state)


func _nearest_enemy() -> EnemyActor:
	_target_scan_count += 1
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
		"attack_footprint_contract_id": ATTACK_FOOTPRINT_CONTRACT_ID,
		"attack_effect_length_gu": _attack_effect_length_gu(),
		"attack_effect_width_gu": SUMMON_ATTACK_WIDTH_GU,
		"attack_interval_seconds": attack_interval,
		"aggro_radius_gu": aggro_radius_gu,
		"combat_radius_gu": combat_radius_gu,
		"leash_range_gu": leash_range_gu,
		"teleport_range_gu": teleport_range_gu,
		"follow_distance_gu": follow_distance_gu,
	}


func gain_growth_from_kill(killed_monster_level: int) -> bool:
	if summon_exp_level >= maximum_pet_level:
		return false
	pet_growth_exp += maxi(0, killed_monster_level)
	var threshold := TaoistCombatMath.summon_growth_threshold(
		summon_id, summon_exp_level
	)
	if pet_growth_exp <= threshold:
		return false
	pet_growth_exp -= threshold
	summon_exp_level = mini(maximum_pet_level, summon_exp_level + 1)
	_apply_growth_stats_preserving_current_hp()
	_request_visual_redraw()
	return true


func growth_contract_snapshot() -> Dictionary:
	return {
		"contract_id": TaoistCombatMath.summon_baseline_contract_id(),
		"summon_id": summon_id,
		"skill_rank": skill_level,
		"pet_level": summon_exp_level,
		"maximum_pet_level": maximum_pet_level,
		"growth_exp": pet_growth_exp,
		"next_threshold": TaoistCombatMath.summon_growth_threshold(
			summon_id, summon_exp_level
		),
		"name_color_index": name_color_index,
		"persistence": "transient_non_permanent_pet",
	}


func _apply_growth_stats_preserving_current_hp() -> void:
	var absolute_hp_before := current_hp
	var stats := TaoistCombatMath.summon_stats(summon_id, summon_exp_level)
	max_hp = int(stats.get("max_hp", max_hp))
	attack_min = int(stats.get("dc_min", attack_min))
	attack_max = int(stats.get("dc_max", attack_max))
	ac_min = int(stats.get("ac_min", ac_min))
	ac_max = int(stats.get("ac_max", ac_max))
	mac_min = int(stats.get("mac_min", mac_min))
	mac_max = int(stats.get("mac_max", mac_max))
	accuracy = int(stats.get("accuracy", accuracy))
	agility = int(stats.get("agility", agility))
	current_hp = mini(absolute_hp_before, max_hp)
	name_color_index = TaoistCombatMath.summon_name_color_index(summon_exp_level)


func create_attack_release_footprint_snapshot(target: Node2D) -> Dictionary:
	if not is_instance_valid(target):
		return {}
	if runtime_map_id >= 0 and not runtime_screen_to_ground_position_px.is_valid():
		missing_projection_rejection_count += 1
		projection_rejection_reason = (
			GroundUnitSpaceScript.REASON_MISSING_SCREEN_TO_GROUND_PROJECTION
		)
		last_attack_footprint_snapshot = {}
		return {}
	var origin_ground_gu := (
		_runtime_screen_to_ground_position(global_position)
	)
	var target_ground_gu := (
		_runtime_screen_to_ground_position(target.global_position)
	)
	var release_id := "%s:attack:%d:%d" % [
		skill_id,
		get_instance_id(),
		_attack_release_sequence,
	]
	_attack_release_sequence += 1
	last_attack_relation = "directed_ground_gu"
	return SkillFootprintSnapshotScript.create_directed_rectangle(
		skill_id,
		release_id,
		origin_ground_gu,
		GroundUnitSpaceScript.normalized_ground_direction(
			origin_ground_gu, target_ground_gu
		),
		_attack_effect_length_gu(),
		SUMMON_ATTACK_WIDTH_GU,
		0.0,
		0.0,
		0.0,
		"",
		_snapshot_coordinate_context(origin_ground_gu)
	)


func _attack_effect_length_gu() -> float:
	return (
		DIVINE_BEAST_ATTACK_LENGTH_GU
		if summon_id == "divine_beast"
		else SKELETON_ATTACK_LENGTH_GU
	)


func _target_within_attack_geometry(target: Node2D) -> bool:
	if not is_instance_valid(target):
		return false
	var origin_ground_gu := _runtime_screen_to_ground_position(global_position)
	var target_ground_gu := _runtime_screen_to_ground_position(
		target.global_position
	)
	if not origin_ground_gu.is_finite() or not target_ground_gu.is_finite():
		return false
	## The target is the aiming axis, so the exact directed-rectangle contact
	## condition reduces to length plus the target's canonical GU footprint.
	## Release still uses the frozen polygon snapshot, preserving width when a
	## target moves sideways during the attack animation.
	return (
		origin_ground_gu.distance_to(target_ground_gu)
		<= _attack_effect_length_gu()
			+ _target_combat_radius_gu(target)
			+ GroundUnitSpaceScript.EPSILON_GU
	)


func attack_release_snapshot_intersects_target(
	attack_snapshot: Dictionary,
	target: Node2D
) -> bool:
	if attack_snapshot.is_empty():
		return false
	if not bool(SkillFootprintSnapshotScript.validate_for_consumer(
		attack_snapshot,
		_snapshot_coordinate_context(
			_runtime_screen_to_ground_position(global_position)
		),
		SkillFootprintSnapshotScript.VALIDATION_STRICT_V2
	).get("valid", false)):
		return false
	return SkillFootprintSnapshotScript.intersects_target_combat_footprint_ground_gu(
		attack_snapshot,
		_runtime_screen_to_ground_position(target.global_position),
		_target_combat_radius_gu(target)
	)


func _runtime_screen_to_ground_position(screen_position_px: Vector2) -> Vector2:
	if runtime_screen_to_ground_position_px.is_valid():
		var ground_position_gu: Variant = (
			runtime_screen_to_ground_position_px.call(screen_position_px)
		)
		if ground_position_gu is Vector2:
			return ground_position_gu
	if runtime_map_id < 0:
		return GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(
			screen_position_px
		)
	missing_projection_rejection_count += 1
	projection_rejection_reason = (
		GroundUnitSpaceScript.REASON_MISSING_SCREEN_TO_GROUND_PROJECTION
	)
	return Vector2.INF


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
	_apply_resolved_damage(maxi(1, amount - physical_defence_bonus()))


func take_magic_damage(amount: int) -> void:
	_apply_resolved_damage(maxi(1, amount - magic_defence_bonus()))


func _apply_resolved_damage(amount: int) -> void:
	if state in [SummonState.DEAD, SummonState.EXPIRED]:
		return
	current_hp = maxi(0, current_hp - maxi(1, amount))
	if current_hp == 0:
		_set_state(SummonState.DEAD)
		remove_from_group("combat_targets")
		collision_layer = 0
		collision_mask = 0
		velocity = Vector2.ZERO
		_current_target = null
		_clear_pending_attack()
		_hit_visual_remaining = 0.0
		_attack_visual_remaining = 0.0
		_death_visual_remaining = _visual_action_duration("death")
		_visual_state = "death"
		_visual_elapsed = 0.0
	else:
		_hit_visual_remaining = _visual_action_duration("hit")
		_visual_state = "hit"
		_visual_elapsed = 0.0
	_request_visual_redraw()


func apply_stealth(seconds: float, buff_id := "buff.taoist.mass_invisibility") -> void:
	## Refresh semantics: keep the longer remaining duration, mirroring the
	## player stealth contract (player.apply_stealth uses max).
	if seconds <= 0.0:
		return
	stealth_remaining_seconds = maxf(stealth_remaining_seconds, seconds)
	if not buff_id.is_empty():
		stealth_buff_id = buff_id


func is_stealthed() -> bool:
	return stealth_remaining_seconds > 0.0


func stealth_remaining() -> float:
	return stealth_remaining_seconds


func apply_ac_buff(bonus: int, seconds: float, buff_id := "") -> void:
	if seconds <= 0.0:
		return
	## Reliable refresh: a weaker or shorter refresh never downgrades an
	## active buff. A fresh cast after expiry starts from the new value.
	var safe_bonus := maxi(0, bonus)
	if ac_buff_remaining_seconds <= 0.0:
		ac_buff_bonus = safe_bonus
	else:
		ac_buff_bonus = maxi(ac_buff_bonus, safe_bonus)
	ac_buff_remaining_seconds = maxf(ac_buff_remaining_seconds, seconds)
	if not buff_id.is_empty():
		ac_buff_id = buff_id


func apply_mac_buff(bonus: int, seconds: float, buff_id := "") -> void:
	if seconds <= 0.0:
		return
	var safe_bonus := maxi(0, bonus)
	if mac_buff_remaining_seconds <= 0.0:
		mac_buff_bonus = safe_bonus
	else:
		mac_buff_bonus = maxi(mac_buff_bonus, safe_bonus)
	mac_buff_remaining_seconds = maxf(mac_buff_remaining_seconds, seconds)
	if not buff_id.is_empty():
		mac_buff_id = buff_id


func physical_defence_bonus() -> int:
	return ac_buff_bonus if ac_buff_remaining_seconds > 0.0 else 0


func magic_defence_bonus() -> int:
	return mac_buff_bonus if mac_buff_remaining_seconds > 0.0 else 0


func clear_ac_buff() -> void:
	ac_buff_bonus = 0
	ac_buff_remaining_seconds = 0.0
	ac_buff_id = ""


func clear_mac_buff() -> void:
	mac_buff_bonus = 0
	mac_buff_remaining_seconds = 0.0
	mac_buff_id = ""


func buff_state_snapshot() -> Dictionary:
	return {
		"contract_id": BUFF_STATE_CONTRACT_ID,
		"stealth_contract_id": STEALTH_STATE_CONTRACT_ID,
		"stealth_remaining_seconds": stealth_remaining_seconds,
		"stealth_buff_id": stealth_buff_id,
		"is_stealthed": is_stealthed(),
		"physical_defence": {
			"bonus": physical_defence_bonus(),
			"remaining_seconds": ac_buff_remaining_seconds,
			"buff_id": ac_buff_id,
		},
		"magic_defence": {
			"bonus": magic_defence_bonus(),
			"remaining_seconds": mac_buff_remaining_seconds,
			"buff_id": mac_buff_id,
		},
	}


func _update_support_buff_timers(delta: float) -> void:
	if stealth_remaining_seconds > 0.0:
		stealth_remaining_seconds = maxf(0.0, stealth_remaining_seconds - delta)
		if stealth_remaining_seconds <= 0.0:
			stealth_buff_id = ""
	if ac_buff_remaining_seconds > 0.0:
		ac_buff_remaining_seconds = maxf(0.0, ac_buff_remaining_seconds - delta)
		if ac_buff_remaining_seconds <= 0.0:
			clear_ac_buff()
	if mac_buff_remaining_seconds > 0.0:
		mac_buff_remaining_seconds = maxf(0.0, mac_buff_remaining_seconds - delta)
		if mac_buff_remaining_seconds <= 0.0:
			clear_mac_buff()


func _buff_draw_signature() -> Vector2i:
	return Vector2i(
		ceili(ac_buff_remaining_seconds)
			if ac_buff_bonus > 0 and ac_buff_remaining_seconds > 0.0
			else 0,
		ceili(mac_buff_remaining_seconds)
			if mac_buff_bonus > 0 and mac_buff_remaining_seconds > 0.0
			else 0
	)


func _refresh_buff_redraw_if_needed() -> void:
	var signature := _buff_draw_signature()
	if signature == _last_buff_draw_signature:
		return
	_last_buff_draw_signature = signature
	_request_visual_redraw()


func _request_visual_redraw() -> void:
	_custom_draw_request_count += 1
	queue_redraw()


func _update_stealth_visual() -> void:
	## Only the summoned body/fire layers fade. The health bar and buff hints
	## are drawn separately in _draw() and must stay readable.
	var body_modulate := Color(
		1.0,
		1.0,
		1.0,
		STEALTH_BODY_MODULATE_ALPHA if is_stealthed() else 1.0
	)
	if _sprite != null and _sprite.self_modulate != body_modulate:
		_sprite.self_modulate = body_modulate
	if _fire_sprite != null and _fire_sprite.self_modulate != body_modulate:
		_fire_sprite.self_modulate = body_modulate


func _buff_hint_lines() -> Array[String]:
	## Directly consumes buff_state_snapshot() so hints always agree with the
	## canonical AC/MAC boost and expiry state.
	var snapshot := buff_state_snapshot()
	var lines: Array[String] = []
	var physical: Dictionary = snapshot.get("physical_defence", {})
	var ac_bonus := int(physical.get("bonus", 0))
	var ac_remaining := float(physical.get("remaining_seconds", 0.0))
	if ac_bonus > 0 and ac_remaining > 0.0:
		lines.append("AC+%d %ds" % [ac_bonus, ceili(ac_remaining)])
	var magic: Dictionary = snapshot.get("magic_defence", {})
	var mac_bonus := int(magic.get("bonus", 0))
	var mac_remaining := float(magic.get("remaining_seconds", 0.0))
	if mac_bonus > 0 and mac_remaining > 0.0:
		lines.append("MAC+%d %ds" % [mac_bonus, ceili(mac_remaining)])
	return lines


func state_name() -> String:
	return SummonState.keys()[state]


func _install_visual() -> void:
	_sprite = Sprite2D.new()
	_sprite.name = (
		"DivineBeastAnimatedBody"
		if summon_id == "divine_beast"
		else "MutantSkeletonAnimatedBody"
	)
	_sprite.centered = false
	_sprite.region_enabled = true
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_sprite)
	request_visual_resources()


func request_visual_resources() -> void:
	if _visual_profile_complete:
		return
	if _visual_request_id == SummonVisualRegistryScript.REQUEST_FAILED:
		return
	_visual_request_id = SummonVisualRegistryScript.request_profile(summon_id)
	if _visual_request_id == SummonVisualRegistryScript.REQUEST_READY:
		_visual_request_attempts = 0
		activate_visual_resources()
	elif _visual_request_id > SummonVisualRegistryScript.REQUEST_UNKNOWN:
		_visual_request_attempts = 0


func _poll_visual_activation() -> void:
	if _visual_profile_complete:
		return
	if _visual_request_id == SummonVisualRegistryScript.REQUEST_READY:
		activate_visual_resources()
		return
	if _visual_request_id == SummonVisualRegistryScript.REQUEST_FAILED:
		return
	if _visual_request_id == SummonVisualRegistryScript.REQUEST_UNKNOWN:
		_visual_request_attempts += 1
		if _visual_request_attempts >= _VISUAL_REQUEST_MAX_ATTEMPTS:
			_visual_request_id = SummonVisualRegistryScript.REQUEST_FAILED
			return
		request_visual_resources()
		return
	var profile := SummonVisualRegistryScript.poll_profile(_visual_request_id)
	if profile.is_empty():
		var preview := SummonVisualRegistryScript.preview_profile(
			_visual_request_id
		)
		if not preview.is_empty() and not _visual_preview_active:
			_activate_profile(preview, true)
		if not SummonVisualRegistryScript.request_active(_visual_request_id):
			## The request finished without a profile for this poller: it may
			## have been completed by another actor (cache now ready) or it
			## failed. Ask the registry once so a cache hit activates and a
			## terminal failure is adopted instead of re-requesting forever.
			_visual_request_id = SummonVisualRegistryScript.REQUEST_UNKNOWN
			request_visual_resources()
		return
	_visual_request_id = SummonVisualRegistryScript.REQUEST_UNKNOWN
	_activate_profile(profile, false)


## Synchronous activation is retained for deterministic test callers. The
## production _ready/_process path uses request_visual_resources() and
## _poll_visual_activation(), so imported textures use the registry's
## bounded ResourceLoader threaded path.
func activate_visual_resources() -> bool:
	var profile := SummonVisualRegistryScript.profile(summon_id)
	return _activate_profile(profile, false)


func _activate_profile(profile: Dictionary, is_streaming_preview := false) -> bool:
	if profile.is_empty():
		return false
	_animation_resources = profile
	_visual_preview_active = is_streaming_preview
	_visual_profile_complete = not is_streaming_preview
	var frame_size: Vector2i = profile.get("frame_size", Vector2i.ZERO)
	var foot_anchor: Vector2i = profile.get("foot_anchor", Vector2i.ZERO)
	var actor_ground_offset: Vector2i = profile.get(
		"actor_ground_offset",
		Vector2i.ZERO
	)
	## The manifest's authored ground point is foot_anchor +
	## actor_ground_offset. Alpha-bounds verification shows that this composite
	## point, not the raw atlas anchor alone, is the body contact point.
	_sprite.position = -Vector2(foot_anchor + actor_ground_offset)
	_health_bar_y = _sprite.position.y + float(profile.get("stable_body_top", 0)) - 7.0
	_sprite.region_rect = Rect2(Vector2.ZERO, frame_size)
	if summon_id == "divine_beast" and profile.has("fire"):
		if _fire_sprite == null:
			_fire_sprite = Sprite2D.new()
			_fire_sprite.name = "DivineBeastFire"
			_fire_sprite.centered = false
			_fire_sprite.region_enabled = true
			_fire_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			add_child(_fire_sprite)
		_fire_sprite.texture = profile.fire
		_fire_sprite.visible = false
		var fire_foot_anchor: Vector2i = profile.get(
			"fire_foot_anchor", Vector2i.ZERO
		)
		var fire_ground_offset: Vector2i = profile.get(
			"fire_actor_ground_offset", Vector2i.ZERO
		)
		_fire_sprite.position = -Vector2(
			fire_foot_anchor + fire_ground_offset
		)
	refresh_visual_after_activation()
	_update_stealth_visual()
	_request_visual_redraw()
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
	var next_texture: Texture2D = _animation_resources.get(_visual_state, null)
	var next_region := Rect2(
		_visual_frame * frame_size.x,
		_visual_direction * frame_size.y,
		frame_size.x,
		frame_size.y
	)
	if _sprite.texture == next_texture and _sprite.region_rect == next_region:
		return
	_sprite.texture = next_texture
	_sprite.region_rect = next_region
	_sprite_frame_apply_count += 1


func performance_diagnostics() -> Dictionary:
	return {
		"contract_id": SUSTAINED_FRAME_COST_CONTRACT_ID,
		"target_acquire_interval_seconds": TARGET_ACQUIRE_INTERVAL_SECONDS,
		"target_scan_count": _target_scan_count,
		"custom_draw_request_count": _custom_draw_request_count,
		"sprite_frame_apply_count": _sprite_frame_apply_count,
		"visual_request_active": SummonVisualRegistryScript.request_active(
			_visual_request_id
		),
		"visual_foot_anchor_contract_id": VISUAL_FOOT_ANCHOR_CONTRACT_ID,
		"visual_profile_complete": _visual_profile_complete,
		"visual_preview_active": _visual_preview_active,
	}


func persistence_snapshot() -> Dictionary:
	return {
		"contract_id": PERSISTENCE_CONTRACT_ID,
		"alive": (
			current_hp > 0
			and state not in [SummonState.EXPIRED, SummonState.DEAD]
		),
		"runtime_state": state_name(),
		"summon_id": summon_id,
		"skill_id": skill_id,
		"skill_rank": skill_level,
		"owner_level": owner_level,
		"current_hp": current_hp,
		"max_hp": max_hp,
		"summon_exp_level": summon_exp_level,
		"maximum_pet_level": maximum_pet_level,
		"pet_growth_exp": pet_growth_exp,
		"remaining_lifetime": remaining_lifetime,
		"stealth": {
			"remaining_seconds": stealth_remaining_seconds,
			"buff_id": stealth_buff_id,
		},
		"physical_defence": {
			"bonus": ac_buff_bonus,
			"remaining_seconds": ac_buff_remaining_seconds,
			"buff_id": ac_buff_id,
		},
		"magic_defence": {
			"bonus": mac_buff_bonus,
			"remaining_seconds": mac_buff_remaining_seconds,
			"buff_id": mac_buff_id,
		},
	}


func restore_persistence_snapshot(snapshot: Dictionary) -> bool:
	if str(snapshot.get("contract_id", "")) != PERSISTENCE_CONTRACT_ID:
		return false
	if not bool(snapshot.get("alive", true)):
		return false
	var restored_summon_id := str(snapshot.get("summon_id", ""))
	if restored_summon_id not in ["skeleton", "divine_beast"]:
		return false
	summon_id = restored_summon_id
	skill_id = str(snapshot.get("skill_id", skill_id))
	skill_level = maxi(0, int(snapshot.get("skill_rank", skill_level)))
	owner_level = maxi(1, int(snapshot.get("owner_level", owner_level)))
	max_hp = maxi(1, int(snapshot.get("max_hp", max_hp)))
	current_hp = clampi(int(snapshot.get("current_hp", current_hp)), 0, max_hp)
	summon_exp_level = clampi(
		int(snapshot.get("summon_exp_level", summon_exp_level)), 0, 7
	)
	maximum_pet_level = clampi(
		int(snapshot.get("maximum_pet_level", maximum_pet_level)),
		summon_exp_level,
		7
	)
	pet_growth_exp = maxi(0, int(snapshot.get("pet_growth_exp", pet_growth_exp)))
	remaining_lifetime = maxf(
		0.0, float(snapshot.get("remaining_lifetime", remaining_lifetime))
	)
	var stealth: Dictionary = snapshot.get("stealth", {})
	stealth_remaining_seconds = maxf(
		0.0, float(stealth.get("remaining_seconds", 0.0))
	)
	stealth_buff_id = str(stealth.get("buff_id", ""))
	var physical: Dictionary = snapshot.get("physical_defence", {})
	ac_buff_bonus = maxi(0, int(physical.get("bonus", 0)))
	ac_buff_remaining_seconds = maxf(
		0.0, float(physical.get("remaining_seconds", 0.0))
	)
	ac_buff_id = str(physical.get("buff_id", ""))
	var magic: Dictionary = snapshot.get("magic_defence", {})
	mac_buff_bonus = maxi(0, int(magic.get("bonus", 0)))
	mac_buff_remaining_seconds = maxf(
		0.0, float(magic.get("remaining_seconds", 0.0))
	)
	mac_buff_id = str(magic.get("buff_id", ""))
	name_color_index = TaoistCombatMath.summon_name_color_index(summon_exp_level)
	attack_range_gu = _attack_effect_length_gu()
	_last_buff_draw_signature = _buff_draw_signature()
	_update_stealth_visual()
	_request_visual_redraw()
	return true


func level_label_layout_snapshot() -> Dictionary:
	var font := ThemeDB.fallback_font
	var display_level := clampi(summon_exp_level, 1, 7)
	var label_text := "Lv.%d" % display_level
	var label_width := font.get_string_size(
		label_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		LEVEL_LABEL_FONT_SIZE
	).x
	var descent := font.get_descent(LEVEL_LABEL_FONT_SIZE)
	var ascent := font.get_ascent(LEVEL_LABEL_FONT_SIZE)
	var baseline_y := _health_bar_y - LEVEL_LABEL_GAP_PX - descent
	return {
		"contract_id": LEVEL_LABEL_CONTRACT_ID,
		"internal_pet_level": summon_exp_level,
		"display_level": display_level,
		"text": label_text,
		"origin": Vector2(-label_width * 0.5, baseline_y),
		"bounds": Rect2(
			Vector2(-label_width * 0.5, baseline_y - ascent),
			Vector2(label_width, ascent + descent)
		),
		"health_bar_y": _health_bar_y,
	}


func reset_performance_diagnostics_for_tests() -> void:
	_target_scan_count = 0
	_custom_draw_request_count = 0
	_sprite_frame_apply_count = 0


func _visual_action_duration(action_name: String) -> float:
	if _animation_resources.is_empty():
		return 1.2 if action_name == "death" else 0.2
	var frame_count := int(_animation_resources.get("frame_counts", {}).get(action_name, 1))
	var frame_ms := int(_animation_resources.get("frame_ms", {}).get(action_name, 100))
	return float(frame_count * frame_ms) / 1000.0


func _start_fire_visual() -> void:
	if _fire_sprite == null or _animation_resources.is_empty():
		return
	_fire_visual_elapsed = 0.0
	_fire_visual_remaining = (
		float(
			int(_animation_resources.get("fire_frame_count", 0))
			* int(_animation_resources.get("fire_frame_ms", 100))
		) / 1000.0
	)
	_fire_sprite.visible = _fire_visual_remaining > 0.0
	_apply_fire_frame()


func _update_fire_visual(delta: float) -> void:
	if _fire_sprite == null or _fire_visual_remaining <= 0.0:
		return
	_fire_visual_elapsed += delta
	_fire_visual_remaining = maxf(0.0, _fire_visual_remaining - delta)
	if _fire_visual_remaining <= 0.0:
		_fire_sprite.visible = false
		return
	_apply_fire_frame()


func _apply_fire_frame() -> void:
	if _fire_sprite == null:
		return
	var frame_size: Vector2i = _animation_resources.get(
		"fire_frame_size", Vector2i.ZERO
	)
	var frame_count := int(_animation_resources.get("fire_frame_count", 1))
	var frame_ms := int(_animation_resources.get("fire_frame_ms", 100))
	var frame := mini(
		frame_count - 1,
		int(floor(_fire_visual_elapsed * 1000.0 / float(maxi(1, frame_ms))))
	)
	_fire_sprite.region_rect = Rect2(
		frame * frame_size.x,
		ArtSpec.mir2_client_direction_row(_pending_attack_direction) * frame_size.y,
		frame_size.x,
		frame_size.y
	)


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
	draw_rect(Rect2(-22, _health_bar_y, 44, 4), Color(0.10, 0.03, 0.03, 0.9))
	draw_rect(
		Rect2(
			-22,
			_health_bar_y,
			44.0 * float(current_hp) / float(maxi(1, max_hp)),
			4
		),
		Color(0.22, 0.72, 0.25)
	)
	var level_layout := level_label_layout_snapshot()
	var level_font := ThemeDB.fallback_font
	var level_origin: Vector2 = level_layout.get("origin", Vector2.ZERO)
	var level_text := str(level_layout.get("text", ""))
	var level_bounds: Rect2 = level_layout.get("bounds", Rect2())
	var level_width := level_bounds.size.x
	draw_string_outline(
		level_font,
		level_origin,
		level_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		level_width,
		LEVEL_LABEL_FONT_SIZE,
		3,
		Color(0.0, 0.0, 0.0, 0.9)
	)
	draw_string(
		level_font,
		level_origin,
		level_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		level_width,
		LEVEL_LABEL_FONT_SIZE,
		Color(1.0, 0.9, 0.35)
	)
	var buff_hints := _buff_hint_lines()
	if not buff_hints.is_empty():
		var font := ThemeDB.fallback_font
		var hint_y := _health_bar_y + BUFF_HINT_OFFSET_Y
		for line: String in buff_hints:
			var line_width := font.get_string_size(
				line,
				HORIZONTAL_ALIGNMENT_LEFT,
				-1.0,
				BUFF_HINT_FONT_SIZE
			).x
			var hint_origin := Vector2(-line_width * 0.5, hint_y)
			draw_string_outline(
				font,
				hint_origin,
				line,
				HORIZONTAL_ALIGNMENT_LEFT,
				line_width,
				BUFF_HINT_FONT_SIZE,
				3,
				Color(0.0, 0.0, 0.0, 0.85)
			)
			draw_string(
				font,
				hint_origin,
				line,
				HORIZONTAL_ALIGNMENT_LEFT,
				line_width,
				BUFF_HINT_FONT_SIZE,
				Color(0.95, 0.95, 0.72)
			)
			hint_y += BUFF_HINT_LINE_SPACING
