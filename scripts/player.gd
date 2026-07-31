class_name PlayerCharacter
extends CharacterBody2D

const PlayerGroundRuntimeDiagnosticOverlayScript := preload(
	"res://scripts/player_ground_runtime_diagnostic_overlay.gd"
)
const SkillDataLoaderScript := preload("res://scripts/skills/skill_data_loader.gd")
const SkillInputPolicyScript := preload("res://scripts/skill_input_policy.gd")
const CombatReleaseGeometryScript := preload(
	"res://scripts/skills/combat_release_geometry.gd"
)

const PlayerVisualScript := preload("res://scripts/player_visual.gd")
const PlayerHealthBarScript := preload("res://scripts/player_health_bar.gd")
const EquipmentRulesScript := preload("res://scripts/equipment_rules.gd")
const WorldSpatialRulesScript := preload("res://scripts/world_spatial_rules.gd")
const CombatResolutionRules := preload("res://scripts/combat_resolution_rules.gd")
const DIRECT_SPELL_DAMAGE_RUNTIME_ID := "player.direct_spell_damage.openmir2.v1"

# GameOfMir server evidence:
# - M2Server/ObjBase.pas RM_STRUCK only records m_dwStruckTick when nPower > 0.
# - ClientWalkXY/ClientRunXY call CheckActionStatus before moving.
# - CheckActionStatus rejects the action while dwStruckTime has not elapsed.
# - M2Server/Mir200/!Setup.txt configures StruckTime=100 (milliseconds).
# That source identifies itself as a modified 1.5 build, not an exact 1.76 source.
# HardCore keeps source evidence and its custom balance values in ProfessionRules.

signal stats_changed(current_hp: int, max_hp: int)
signal attack_requested(origin: Vector2, direction: Vector2, damage: int)
signal skill_requested(skill_name: String, origin: Vector2, direction: Vector2, damage: int)
signal warrior_skill_state_changed(skill_name: String, enabled: bool, message: String)
signal resources_changed(current_hp: int, max_hp: int, current_mp: int, max_mp: int)
signal movement_performed(position: Vector2, facing: Vector2)
signal death_requested

@export var move_speed := 190.0
@export var max_hp := 120
@export var attack_min := 2
@export var attack_max := 5
@export var attack_cooldown := 0.9
@export var attack_animation_duration := 0.51
@export var attack_hit_windup := 0.17

var current_hp := 120
var max_mp := 40
var current_mp := 40
var defense_min := 0
var defense_max := 0
var damage_reduction := 0.0
var shield_time := 0.0
var stealth_time := 0.0
var defense_buff := 0
var defense_buff_time := 0.0
var control_time := 0.0
var poison_time := 0.0
var poison_damage := 0
var touch_vector := Vector2.ZERO
var facing := Vector2.DOWN
var _attack_timer := 0.0
var _attack_action_timer := 0.0
var _skill_cooldown_remaining: Dictionary = {}
var _struck_lock_remaining := 0.0
var _struck_reaction_lock_remaining := 0.0
var _queued_struck_reaction := false
var _rng := RandomNumberGenerator.new()
var visual: Node2D
var health_bar: PlayerHealthBar
var thrusting_enabled := false
var half_moon_enabled := false
var fire_sword_enabled := false
# Read-only presentation mirror; GameRoot owns charge creation, expiry, and consumption.
var _fire_sword_charge_expires_at_ms := 0
var _pending_attack_context: Dictionary = {}
var _pending_skill_context: Dictionary = {}
var _combat_action_sequence := 0
var _pending_combat_action_id := 0
var _pending_combat_action_active := false
var _pending_combat_action_committed := false
var _pending_combat_action_kind := ""
var _test_combat_time_ms := -1
var _last_revival_at_ms := -60000
var _pending_potion_health := 0
var _pending_potion_mana := 0
var _potion_tick_remaining := 0.0
var _attack_speed_tier := 0
var _cast_speed_multiplier := 1.0
var _dead := false
var movement_input_active := false
var movement_facing := Vector2.DOWN
var actual_motion_facing := Vector2.DOWN
var environment_blocker: Node
var ground_runtime_diagnostic_overlay: Node2D

const FACING_DIRECTIONS: Array[Vector2] = [
	Vector2.DOWN, Vector2(-0.70710678, 0.70710678), Vector2.LEFT, Vector2(-0.70710678, -0.70710678),
	Vector2.UP, Vector2(0.70710678, -0.70710678), Vector2.RIGHT, Vector2(0.70710678, 0.70710678),
]


func _ready() -> void:
	add_to_group("player")
	add_to_group("combat_targets")
	collision_layer = WorldSpatialRulesScript.PLAYER_LAYER
	collision_mask = WorldSpatialRulesScript.PLAYER_MASK
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	safe_margin = 0.35
	max_slides = 6
	_rng.randomize()
	PlayerState.profile_changed.connect(_apply_profile_stats)
	_apply_profile_stats()
	current_hp = max_hp
	current_mp = max_mp
	var collision := CollisionShape2D.new()
	collision.name = "CollisionShape2D"
	collision.shape = WorldSpatialRulesScript.actor_footprint_shape(ArtSpec.PLAYER_COLLISION_RADIUS)
	add_child(collision)
	visual = PlayerVisualScript.new()
	visual.name = "PlayerVisual"
	visual.setup(self)
	add_child(visual)
	if PlayerGroundRuntimeDiagnosticOverlayScript.enabled_for_runtime():
		ground_runtime_diagnostic_overlay = (
			PlayerGroundRuntimeDiagnosticOverlayScript.new()
		)
		ground_runtime_diagnostic_overlay.name = "GroundRuntimeDiagnosticOverlay"
		ground_runtime_diagnostic_overlay.setup(self)
		add_child(ground_runtime_diagnostic_overlay)
	health_bar = PlayerHealthBarScript.new()
	health_bar.name = "HealthBar"
	health_bar.position = ArtSpec.PLAYER_HEALTH_BAR_OFFSET
	health_bar.z_index = 20
	health_bar.setup(current_hp, max_hp)
	add_child(health_bar)
	stats_changed.connect(health_bar.set_health)
	queue_redraw()
	stats_changed.emit(current_hp, max_hp)
	resources_changed.emit(current_hp, max_hp, current_mp, max_mp)


func _physics_process(delta: float) -> void:
	var position_before_move := global_position
	var was_struck_locked := _struck_lock_remaining > 0.0 or _struck_reaction_lock_remaining > 0.0
	_attack_timer = maxf(0.0, _attack_timer - delta)
	_attack_action_timer = maxf(0.0, _attack_action_timer - delta)
	for stable_skill_id: Variant in _skill_cooldown_remaining.keys():
		var remaining := maxf(
			0.0,
			float(_skill_cooldown_remaining.get(stable_skill_id, 0.0)) - delta
		)
		if remaining <= 0.0:
			_skill_cooldown_remaining.erase(stable_skill_id)
		else:
			_skill_cooldown_remaining[stable_skill_id] = remaining
	if _attack_action_timer <= 0.0 and _pending_combat_action_active and _pending_combat_action_committed:
		_finish_combat_action(_pending_combat_action_id)
	if _attack_action_timer <= 0.0 and _queued_struck_reaction:
		_start_queued_struck_reaction()
		was_struck_locked = true
	_struck_lock_remaining = maxf(0.0, _struck_lock_remaining - delta)
	_struck_reaction_lock_remaining = maxf(0.0, _struck_reaction_lock_remaining - delta)
	if _struck_lock_remaining < 0.000001:
		_struck_lock_remaining = 0.0
	shield_time = maxf(0.0, shield_time - delta)
	stealth_time = maxf(0.0, stealth_time - delta)
	defense_buff_time = maxf(0.0, defense_buff_time - delta)
	control_time = maxf(0.0, control_time - delta)
	_process_potion_restore(delta)
	var previous_poison_second := int(ceil(poison_time))
	poison_time = maxf(0.0, poison_time - delta)
	if poison_time > 0.0 and int(ceil(poison_time)) < previous_poison_second:
		# Periodic poison damage is not an RM_STRUCK hit in the reference server,
		# so it must not refresh the movement/action lock.
		take_damage(poison_damage, false)
	if shield_time == 0.0:
		damage_reduction = 0.0
	if defense_buff_time == 0.0:
		defense_buff = 0
	var keyboard := _keyboard_movement_vector()
	var direction := touch_vector if touch_vector.length() > keyboard.length() else keyboard
	if _dead or control_time > 0.0 or _attack_action_timer > 0.0 or was_struck_locked:
		direction = Vector2.ZERO
	movement_input_active = direction.length() > 0.08
	if _attack_action_timer > 0.0 or was_struck_locked:
		velocity = Vector2.ZERO
	elif direction.length() > 0.08:
		direction = direction.normalized()
		facing = FACING_DIRECTIONS[ArtSpec.direction_index(direction)]
		movement_facing = facing
		velocity = direction * move_speed
	else:
		velocity = velocity.move_toward(Vector2.ZERO, move_speed * 8.0 * delta)
	move_and_slide()
	if WorldSpatialRulesScript.environment_blocks_actor(environment_blocker, global_position, ArtSpec.PLAYER_COLLISION_RADIUS):
		global_position = position_before_move
		velocity = Vector2.ZERO
	var actual_motion := global_position - position_before_move
	if actual_motion.length_squared() > 0.01:
		# Walking art follows displacement that really happened on screen. This
		# cannot be overwritten by targeting, stale input, or collision sliding.
		actual_motion_facing = FACING_DIRECTIONS[ArtSpec.direction_index(actual_motion)]
		movement_facing = actual_motion_facing
		facing = actual_motion_facing
		movement_performed.emit(global_position, facing)


func set_touch_vector(value: Vector2) -> void:
	touch_vector = value.limit_length(1.0)


func _keyboard_movement_vector() -> Vector2:
	for action: StringName in [&"move_left", &"move_right", &"move_up", &"move_down"]:
		if not InputMap.has_action(action):
			return Vector2.ZERO
	return Input.get_vector("move_left", "move_right", "move_up", "move_down")


func set_combat_facing(direction: Vector2) -> void:
	if direction.length_squared() <= 0.01:
		return
	facing = FACING_DIRECTIONS[ArtSpec.direction_index(direction.normalized())]
	movement_facing = facing
	actual_motion_facing = facing
	movement_input_active = false


func can_start_attack() -> bool:
	return _attack_timer <= 0.0 and _attack_action_timer <= 0.0 and _struck_lock_remaining <= 0.0 and _struck_reaction_lock_remaining <= 0.0 and control_time <= 0.0


func request_attack(has_combat_target := false, locked_target_instance_id := 0) -> bool:
	if not can_start_attack():
		return false
	var context := _build_warrior_attack_context(has_combat_target)
	if str(context.get("action", "attack")) != "attack":
		return false
	if bool(context.get("direct_toggle_release", false)):
		# Resource consumption remains in GameRoot's canonical result commit.
		# Lock the independent cooldown at input acceptance so repeated attack
		# presses cannot queue duplicate direct releases before the hit frame.
		var fire_definition := SkillDataLoaderScript.skill("warrior.fire_sword")
		var fire_cooldown_ms := int(fire_definition.get("timing", {}).get("cooldown_ms", 8000))
		_skill_cooldown_remaining["warrior.fire_sword"] = (
			maxf(0.0, float(fire_cooldown_ms) / 1000.0)
			/ _cast_speed_multiplier
		)
	var action_duration := attack_animation_duration
	_attack_timer = attack_cooldown
	_attack_action_timer = action_duration
	velocity = Vector2.ZERO
	var action_id := _begin_combat_action("attack")
	var animation_name := str(context.get("skill_name", "attack"))
	visual.play_action(animation_name, action_duration)
	var damage := WarriorCombatMath.roll_attack_power(attack_min, attack_max, int(PlayerState.computed_stats.get("luck", 0)), _rng)
	var critical_chance := float(PlayerState.computed_stats.get("critical_chance", 0.0))
	if critical_chance > 0.0 and EquipmentRulesScript.critical_succeeds(critical_chance, _rng.randf()):
		damage = EquipmentRulesScript.critical_damage(damage, float(PlayerState.computed_stats.get("critical_damage_multiplier", 1.5)))
	_emit_attack_after_windup(
		damage,
		attack_hit_windup,
		context,
		action_id,
		facing.normalized(),
		locked_target_instance_id
	)
	if _rng.randi_range(1, 25) == 1:
		PlayerState.damage_equipment_durability("武器")
	return true


func request_attack_toward(
	direction: Vector2,
	has_combat_target := false,
	locked_target_instance_id := 0
) -> bool:
	if not can_start_attack() or direction.length_squared() <= 0.01:
		return false
	set_combat_facing(direction)
	return request_attack(has_combat_target, locked_target_instance_id)


func request_skill(skill_name: String, locked_target_instance_id := 0) -> bool:
	if skill_name.is_empty() or not PlayerState.is_skill_learned(skill_name):
		return false
	if _struck_lock_remaining > 0.0 or _struck_reaction_lock_remaining > 0.0 or control_time > 0.0 or _dead:
		return false
	var learned_level := PlayerState.effective_skill_level(skill_name)
	if PlayerState.profession == "战士" and skill_name in ["基本剑术", "攻杀剑术", "刺杀剑术", "半月弯刀", "烈火剑法"]:
		return _request_warrior_state_skill(skill_name, learned_level)
	return _request_active_skill(skill_name, locked_target_instance_id)


func _request_active_skill(skill_name: String, locked_target_instance_id := 0) -> bool:
	var learned_level := PlayerState.effective_skill_level(skill_name)
	if _attack_timer > 0.0:
		return false
	var stable_skill_id := SkillDataLoaderScript.stable_skill_id(skill_name)
	if skill_cooldown_remaining_ms(stable_skill_id) > 0:
		return false
	var canonical_definition := SkillDataLoaderScript.skill(stable_skill_id)
	if canonical_definition.is_empty():
		return false
	var mp_costs: Array = canonical_definition.get("mp_cost_by_rank", [])
	var mana_cost := int(mp_costs[clampi(learned_level, 0, 3)]) if not mp_costs.is_empty() else 0
	if current_mp < mana_cost:
		return false
	var canonical_timing: Dictionary = canonical_definition.get("timing", {})
	var combat_profile := ProfessionRules.skill_combat_profile(skill_name, learned_level)
	var track_locked_target := CombatReleaseGeometryScript.tracks_locked_target(
		str(combat_profile.get("target_mode", "self"))
	)
	var body_cast_ms := int(canonical_timing.get(
		"body_cast_ms",
		roundi(ProfessionRules.CASTER_SPELL_ACTION_DURATION * 1000.0)
	))
	var total_action_lock_ms := int(canonical_timing.get(
		"total_action_lock_ms",
		body_cast_ms
	))
	var cooldown_ms := int(canonical_timing.get(
		"cooldown_ms",
		total_action_lock_ms
	))
	var release_ms := int(canonical_timing.get(
		"effect_resolve_ms_from_cast_start",
		body_cast_ms
	))
	var action_lock_seconds := maxf(
		0.0,
		float(total_action_lock_ms) / 1000.0
	) / _cast_speed_multiplier
	var cooldown_seconds := maxf(
		0.0,
		float(cooldown_ms) / 1000.0
	) / _cast_speed_multiplier
	_attack_timer = action_lock_seconds
	if cooldown_seconds > 0.0:
		_skill_cooldown_remaining[stable_skill_id] = cooldown_seconds
	var action_duration := maxf(0.0, float(body_cast_ms) / 1000.0)
	_attack_action_timer = action_duration
	velocity = Vector2.ZERO
	movement_input_active = false
	var action_id := _begin_combat_action("skill:%s" % skill_name)
	visual.play_action(skill_name if PlayerState.profession == "战士" else "cast", action_duration)
	_emit_skill_after_windup(
		skill_name,
		0,
		maxf(0.0, float(release_ms) / 1000.0),
		action_id,
		facing.normalized(),
		locked_target_instance_id,
		track_locked_target
	)
	if _rng.randi_range(1, 30) == 1:
		PlayerState.damage_equipment_durability("武器")
	return true


func take_damage(amount: int, causes_struck: bool = true) -> void:
	var absorbed := (_rng.randi_range(defense_min, defense_max) if defense_max >= defense_min else defense_min) + defense_buff
	_apply_resolved_damage(maxi(1, amount - absorbed), causes_struck)


func take_direct_spell_damage(
	skill_id: String,
	raw_damage: int,
	anti_magic_roll := -1,
	magic_defense_roll := -1,
	causes_struck := true
) -> Dictionary:
	var stable_skill_id := ProfessionRules.skill_id(skill_id)
	var target_stats: Dictionary = PlayerState.computed_stats
	var checked_anti_magic_roll := anti_magic_roll
	if checked_anti_magic_roll < 0:
		checked_anti_magic_roll = _rng.randi_range(0, CombatResolutionRules.ANTI_MAGIC_ROLL_SIDES - 1)
	var magic_defense_state := {}
	var magic_defense_adapter := Callable(
		self,
		"_resolve_direct_spell_magic_defense"
	).bind(magic_defense_roll, magic_defense_state)
	var resolution := CombatResolutionRules.resolve_direct_spell_damage(
		stable_skill_id,
		raw_damage,
		target_stats,
		checked_anti_magic_roll,
		magic_defense_adapter
	)
	resolution["runtime_contract"] = DIRECT_SPELL_DAMAGE_RUNTIME_ID
	resolution["magic_defense_min"] = maxi(0, int(target_stats.get("magic_defense_min", 0)))
	resolution["magic_defense_max"] = maxi(
		int(resolution.magic_defense_min),
		int(target_stats.get("magic_defense_max", resolution.magic_defense_min))
	)
	resolution["magic_defense_roll"] = int(magic_defense_state.get("roll", -1))
	resolution["physical_defense_bypassed"] = true
	var hp_before := current_hp
	if int(resolution.final_damage) > 0:
		_apply_resolved_damage(int(resolution.final_damage), causes_struck)
	resolution["player_pipeline_input"] = int(resolution.final_damage)
	resolution["applied_damage"] = maxi(0, hp_before - current_hp)
	return resolution


func _resolve_direct_spell_magic_defense(
	_skill_id: String,
	incoming_damage: int,
	target_stats: Dictionary,
	roll_override: int,
	resolution_state: Dictionary
) -> int:
	var minimum := maxi(0, int(target_stats.get("magic_defense_min", 0)))
	var maximum := maxi(minimum, int(target_stats.get("magic_defense_max", minimum)))
	var roll := clampi(roll_override, minimum, maximum) if roll_override >= 0 else _rng.randi_range(minimum, maximum)
	resolution_state["roll"] = roll
	return maxi(0, incoming_damage - roll)


func _apply_resolved_damage(amount: int, causes_struck: bool) -> void:
	var reduced_amount := int(round(maxi(1, amount) * (1.0 - clampf(damage_reduction, 0.0, 0.8))))
	var final_damage := maxi(1, reduced_amount)
	if PlayerState.has_special_effect("magic_shield") and current_mp > 0:
		var shield_mp_cost := int(round(final_damage * 1.5))
		if current_mp >= shield_mp_cost:
			current_mp -= shield_mp_cost
			final_damage = 0
		else:
			var unpaid_mp := shield_mp_cost - current_mp
			current_mp = 0
			final_damage = int(round(unpaid_mp / 1.5))
	current_hp = maxi(0, current_hp - final_damage)
	if causes_struck and ProfessionRules.should_player_stagger(final_damage, max_hp) and current_hp > 0:
		_struck_lock_remaining = maxf(_struck_lock_remaining, ProfessionRules.player_struck_action_lock_seconds())
		velocity = Vector2.ZERO
		movement_input_active = false
		# The legacy client only consumes SM_STRUCK while its current action is
		# idle. Queue the reaction so an attack animation and its hit transaction
		# remain causally consistent instead of showing a false cancellation.
		if _attack_action_timer > 0.0 or _pending_combat_action_active:
			_queued_struck_reaction = true
		else:
			_start_struck_reaction()
	if _rng.randi_range(1, 30) == 1:
		PlayerState.damage_equipment_durability("衣服")
	stats_changed.emit(current_hp, max_hp)
	resources_changed.emit(current_hp, max_hp, current_mp, max_mp)
	queue_redraw()
	if current_hp == 0:
		var now_ms := Time.get_ticks_msec()
		if PlayerState.has_special_effect("revival") and now_ms - _last_revival_at_ms >= 60000:
			_last_revival_at_ms = now_ms
			current_hp = max_hp
			PlayerState.damage_special_effect_item("revival")
			stats_changed.emit(current_hp, max_hp)
			resources_changed.emit(current_hp, max_hp, current_mp, max_mp)
			return
		_dead = true
		velocity = Vector2.ZERO
		touch_vector = Vector2.ZERO
		visual.play_death()
		PlayerState.lose_gold_percent(0.05)
		await get_tree().create_timer(0.8).timeout
		if not is_inside_tree():
			return
		current_hp = max_hp
		current_mp = max_mp
		_dead = false
		death_requested.emit()
		stats_changed.emit(current_hp, max_hp)
		resources_changed.emit(current_hp, max_hp, current_mp, max_mp)


func _emit_attack_after_windup(
	damage: int,
	windup: float,
	context: Dictionary,
	action_id: int,
	input_direction: Vector2,
	locked_target_instance_id: int
) -> void:
	if windup > 0.0:
		await get_tree().create_timer(windup).timeout
	if is_inside_tree() and _commit_combat_action(action_id):
		var release_geometry := _resolve_combat_release_geometry(
			input_direction,
			locked_target_instance_id,
			true
		)
		_pending_attack_context = context.duplicate(true)
		_pending_attack_context["release_geometry"] = release_geometry
		attack_requested.emit(
			release_geometry.origin_world,
			release_geometry.direction_world,
			damage
		)
		_pending_attack_context.clear()


func _emit_skill_after_windup(
	skill_name: String,
	damage: int,
	windup: float,
	action_id: int,
	input_direction: Vector2,
	locked_target_instance_id: int,
	track_locked_target: bool
) -> void:
	if windup > 0.0:
		await get_tree().create_timer(windup).timeout
	if is_inside_tree() and _commit_combat_action(action_id):
		var release_geometry := _resolve_combat_release_geometry(
			input_direction,
			locked_target_instance_id,
			track_locked_target
		)
		_pending_skill_context = {"release_geometry": release_geometry}
		skill_requested.emit(
			skill_name,
			release_geometry.origin_world,
			release_geometry.direction_world,
			damage
		)
		_pending_skill_context.clear()


func _resolve_combat_release_geometry(
	input_direction: Vector2,
	locked_target_instance_id: int,
	track_locked_target: bool
) -> Dictionary:
	var target_position := Vector2.ZERO
	var target_valid := false
	if track_locked_target and locked_target_instance_id > 0:
		var candidate := instance_from_id(locked_target_instance_id)
		if candidate is Node2D and is_instance_valid(candidate) and candidate.is_inside_tree():
			target_position = candidate.global_position
			target_valid = true
	return CombatReleaseGeometryScript.resolve(
		global_position,
		input_direction,
		locked_target_instance_id,
		target_position,
		target_valid,
		track_locked_target
	)


func _begin_combat_action(action_kind: String) -> int:
	_combat_action_sequence += 1
	_pending_combat_action_id = _combat_action_sequence
	_pending_combat_action_active = true
	_pending_combat_action_committed = false
	_pending_combat_action_kind = action_kind
	return _pending_combat_action_id


func _commit_combat_action(action_id: int) -> bool:
	if not _pending_combat_action_active or action_id != _pending_combat_action_id:
		return false
	_pending_combat_action_committed = true
	return true


func _finish_combat_action(action_id: int) -> void:
	if action_id != _pending_combat_action_id:
		return
	_pending_combat_action_active = false
	_pending_combat_action_kind = ""


func _start_struck_reaction() -> void:
	var duration := ProfessionRules.player_struck_reaction_seconds()
	_struck_reaction_lock_remaining = maxf(_struck_reaction_lock_remaining, duration)
	visual.play_hit(duration)


func _start_queued_struck_reaction() -> void:
	_queued_struck_reaction = false
	_start_struck_reaction()


func combat_action_snapshot() -> Dictionary:
	return {
		"action_id": _pending_combat_action_id,
		"kind": _pending_combat_action_kind,
		"active": _pending_combat_action_active,
		"committed": _pending_combat_action_committed,
	}


func struck_reaction_snapshot() -> Dictionary:
	return {
		"policy_id": str(ProfessionRules.COMBAT_REACTION_POLICY.policy_id),
		"server_action_lock_remaining": _struck_lock_remaining,
		"reaction_lock_remaining": _struck_reaction_lock_remaining,
		"queued": _queued_struck_reaction,
	}


func consume_attack_context() -> Dictionary:
	return _pending_attack_context.duplicate(true)


func consume_skill_context() -> Dictionary:
	return _pending_skill_context.duplicate(true)


func set_test_combat_time_ms(value: int) -> void:
	_test_combat_time_ms = value


func set_combat_seed(seed_value: int) -> void:
	_rng.seed = seed_value


func set_fire_sword_charge_display(expires_at_ms: int) -> void:
	_fire_sword_charge_expires_at_ms = maxi(0, expires_at_ms)


func skill_cooldown_remaining_ms(stable_skill_id: String) -> int:
	return ceili(maxf(
		0.0,
		float(_skill_cooldown_remaining.get(stable_skill_id, 0.0))
	) * 1000.0)


func warrior_state_snapshot() -> Dictionary:
	var fire_expires_remaining_ms := maxi(
		0,
		_fire_sword_charge_expires_at_ms - Time.get_ticks_msec()
	)
	return {
		"contract_id": "gameplay.warrior.skill_runtime.v2",
		"slaying_auto": PlayerState.learned_skills.has("攻杀剑术"),
		"thrusting": thrusting_enabled,
		"half_moon": half_moon_enabled,
		"fire_enabled": fire_sword_enabled,
		"fire_armed": fire_expires_remaining_ms > 0,
		"fire_expires_remaining_ms": fire_expires_remaining_ms,
		"fire_cooldown_remaining_ms": skill_cooldown_remaining_ms(
			"warrior.fire_sword"
		),
		# Compatibility keys only. Proc state is resolved exactly once by the
		# canonical melee-modifier API and is never pre-rolled in Player.
		"slaying_remaining": 0,
		"slaying_trigger": -1,
	}


func warrior_runtime_state_for_save() -> Dictionary:
	return {
		"contract_id": "gameplay.warrior.skill_runtime.v2",
		"toggles": {
			"warrior.thrusting": thrusting_enabled,
			"warrior.half_moon": half_moon_enabled,
			# Existing v2 field is re-used, so this interaction update does not
			# change the persisted contract shape.
			"warrior.fire_sword.auto_enabled": fire_sword_enabled,
		},
		"cooldowns": {},
	}


func restore_warrior_runtime_state(saved_state: Dictionary) -> bool:
	if str(saved_state.get("contract_id", "")) != "gameplay.warrior.skill_runtime.v2":
		return false
	var toggles: Dictionary = saved_state.get("toggles", {})
	thrusting_enabled = bool(toggles.get("warrior.thrusting", false))
	half_moon_enabled = bool(toggles.get("warrior.half_moon", false))
	fire_sword_enabled = bool(toggles.get("warrior.fire_sword.auto_enabled", false))
	# An in-flight charge never survives a reload; only the input toggle does.
	set_fire_sword_charge_display(0)
	return true


func _combat_time_ms() -> int:
	return _test_combat_time_ms if _test_combat_time_ms >= 0 else Time.get_ticks_msec()


func _request_warrior_state_skill(skill_name: String, _level: int) -> bool:
	match skill_name:
		"基本剑术":
			warrior_skill_state_changed.emit(skill_name, true, "基本剑术为被动命中技能")
			return true
		"攻杀剑术":
			warrior_skill_state_changed.emit(skill_name, true, "攻杀剑术按攻击周期自动触发")
			return true
		"刺杀剑术":
			thrusting_enabled = not thrusting_enabled
			warrior_skill_state_changed.emit(skill_name, thrusting_enabled, "刺杀剑术：%s" % ("开启" if thrusting_enabled else "关闭"))
			return true
		"半月弯刀":
			half_moon_enabled = not half_moon_enabled
			warrior_skill_state_changed.emit(skill_name, half_moon_enabled, "半月弯刀：%s" % ("开启" if half_moon_enabled else "关闭"))
			return true
		"烈火剑法":
			fire_sword_enabled = not fire_sword_enabled
			warrior_skill_state_changed.emit(skill_name, fire_sword_enabled, "烈火剑法：%s" % ("开启" if fire_sword_enabled else "关闭"))
			return true
	return false


func _build_warrior_attack_context(has_combat_target := false) -> Dictionary:
	var context := {
		"policy_id": SkillInputPolicyScript.WARRIOR_ATTACK_POLICY_ID,
		"action": "attack",
		"mode": "normal",
		"skill_name": "attack",
		"skill_level": 0,
	}
	if PlayerState.profession != "战士":
		return context
	var fire_remaining_ms := maxi(0, _fire_sword_charge_expires_at_ms - Time.get_ticks_msec())
	var resolution := SkillInputPolicyScript.resolve_warrior_attack({
		"learned_skills": PlayerState.learned_skills,
		"toggles": {
			"warrior.fire_sword": fire_sword_enabled,
			"warrior.half_moon": half_moon_enabled,
			"warrior.thrusting": thrusting_enabled,
		},
		"has_combat_target": has_combat_target,
		"current_mp": current_mp,
		"fire_armed": fire_remaining_ms > 0,
		"fire_cooldown_remaining_ms": skill_cooldown_remaining_ms("warrior.fire_sword"),
		"fire_rank": PlayerState.effective_skill_level("烈火剑法"),
		"half_moon_rank": PlayerState.effective_skill_level("半月弯刀"),
		"slaying_rank": PlayerState.effective_skill_level("攻杀剑术"),
	})
	var selected_id := str(resolution.get("skill_id", ""))
	resolution["skill_level"] = (
		PlayerState.effective_skill_level(selected_id)
		if not selected_id.is_empty()
		else 0
	)
	return resolution


func restore_health(amount: int) -> void:
	current_hp = mini(max_hp, current_hp + maxi(0, amount))
	stats_changed.emit(current_hp, max_hp)
	resources_changed.emit(current_hp, max_hp, current_mp, max_mp)
	queue_redraw()


func restore_mana(amount: int) -> void:
	current_mp = mini(max_mp, current_mp + maxi(0, amount))
	resources_changed.emit(current_hp, max_hp, current_mp, max_mp)


func queue_potion_restore(health_amount: int, mana_amount: int) -> void:
	_pending_potion_health = mini(65535, _pending_potion_health + maxi(0, health_amount))
	_pending_potion_mana = mini(65535, _pending_potion_mana + maxi(0, mana_amount))


func _process_potion_restore(delta: float) -> void:
	if _pending_potion_health <= 0 and _pending_potion_mana <= 0:
		_potion_tick_remaining = 0.0
		return
	_potion_tick_remaining -= delta
	if _potion_tick_remaining > 0.0:
		return
	# Original M2Server ObjBase.pas: interval = 600-min(400, level*10) ms;
	# each tick restores level div 10 + 5 from the queued potion pools.
	_potion_tick_remaining = float(600 - mini(400, PlayerState.level * 10)) / 1000.0
	var per_tick: int = 5 + int(PlayerState.level / 10)
	if _pending_potion_health > 0:
		var hp_tick := mini(per_tick, _pending_potion_health)
		_pending_potion_health -= hp_tick
		restore_health(hp_tick)
		if current_hp >= max_hp:
			_pending_potion_health = 0
	if _pending_potion_mana > 0:
		var mp_tick := mini(per_tick, _pending_potion_mana)
		_pending_potion_mana -= mp_tick
		restore_mana(mp_tick)
		if current_mp >= max_mp:
			_pending_potion_mana = 0


func spend_mana(amount: int) -> bool:
	var cost := maxi(0, amount)
	if current_mp < cost:
		return false
	current_mp -= cost
	resources_changed.emit(current_hp, max_hp, current_mp, max_mp)
	return true


func apply_magic_shield(seconds: float, reduction: float) -> void:
	shield_time = maxf(shield_time, seconds)
	damage_reduction = maxf(damage_reduction, clampf(reduction, 0.0, 0.8))
	queue_redraw()


func apply_stealth(seconds: float) -> void:
	stealth_time = maxf(stealth_time, seconds)
	queue_redraw()


func apply_defense_buff(seconds: float, amount: int) -> void:
	defense_buff_time = maxf(defense_buff_time, seconds)
	defense_buff = maxi(defense_buff, amount)
	queue_redraw()


func apply_control(seconds: float) -> void:
	control_time = maxf(control_time, seconds)
	queue_redraw()


func apply_poison(tick_damage: int, seconds: float) -> void:
	poison_damage = maxi(poison_damage, maxi(1, tick_damage))
	poison_time = maxf(poison_time, seconds)
	queue_redraw()


func is_stealthed() -> bool:
	return stealth_time > 0.0 or PlayerState.has_special_effect("stealth")


func _draw() -> void:
	# Final MIR2 character frames already contain their own direction-aware
	# ground shadow. Drawing another ellipse at the actor origin creates two
	# separated shadows and makes the body look airborne.
	if visual == null or not visual.uses_final_art():
		draw_set_transform(Vector2(0, 2), 0.0, Vector2(1.0, 0.36))
		draw_circle(Vector2.ZERO, 20.0, Color(0, 0, 0, 0.48))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if visual == null or not visual.uses_final_art():
		draw_circle(Vector2(0, -8), 17.0, Color(0.76, 0.66, 0.46))
		var profession_color: Color = {"战士": Color(0.24, 0.34, 0.48), "法师": Color(0.20, 0.28, 0.56), "道士": Color(0.36, 0.42, 0.24)}.get(PlayerState.profession, Color(0.24, 0.34, 0.48))
		draw_colored_polygon(PackedVector2Array([Vector2(-17, -5), Vector2(17, -5), Vector2(13, 23), Vector2(-13, 23)]), profession_color)
		draw_line(Vector2(0, 7), facing * 27.0 + Vector2(0, 7), Color(0.92, 0.86, 0.65), 5.0)
	if shield_time > 0.0:
		draw_circle(Vector2(0, -4), 30.0, Color(0.25, 0.62, 1.0, 0.22))
		draw_circle(Vector2(0, -4), 30.0, Color(0.48, 0.82, 1.0, 0.85), false, 3.0)
	if stealth_time > 0.0:
		draw_circle(Vector2(0, -4), 34.0, Color(0.55, 0.9, 0.7, 0.16), false, 3.0)
	if control_time > 0.0:
		draw_circle(Vector2(0, -4), 37.0, Color(0.42, 0.62, 1.0, 0.75), false, 4.0)
	if poison_time > 0.0:
		draw_circle(Vector2(0, -4), 40.0, Color(0.20, 0.85, 0.22, 0.70), false, 4.0)


func _apply_profile_stats() -> void:
	var old_max := maxi(1, max_hp)
	var hp_ratio := float(current_hp) / float(old_max) if current_hp > 0 else 1.0
	var stats: Dictionary = PlayerState.computed_stats
	max_hp = int(stats.get("max_hp", 120))
	max_mp = int(stats.get("max_mp", 40))
	attack_min = int(stats.get("attack_min", 2))
	attack_max = int(stats.get("attack_max", 5))
	_attack_speed_tier = int(stats.get("attack_speed_tier", 0))
	attack_cooldown = WarriorCombatMath.physical_attack_interval_seconds(_attack_speed_tier)
	_cast_speed_multiplier = clampf(1.0 + float(stats.get("cast_speed_percent", 0.0)), 0.2, 6.0)
	defense_min = int(stats.get("defense_min", 0))
	defense_max = maxi(defense_min, int(stats.get("defense_max", 0)))
	current_hp = clampi(int(round(max_hp * hp_ratio)), 1, max_hp)
	current_mp = clampi(current_mp, 0, max_mp)
	stats_changed.emit(current_hp, max_hp)
	resources_changed.emit(current_hp, max_hp, current_mp, max_mp)
	if visual != null:
		visual.refresh_profession()
	queue_redraw()
