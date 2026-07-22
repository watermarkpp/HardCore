class_name EnemyActor
extends CharacterBody2D

const MonsterVisualScript := preload("res://scripts/monster_visual.gd")
const MonsterIdentityScript := preload("res://scripts/monster_identity.gd")
const WorldSpatialRulesScript := preload("res://scripts/world_spatial_rules.gd")
const CROWD_GRID_CELL_SIZE := 96.0
const CROWD_GRID_REFRESH_FRAMES := 3
const CROWD_STEERING_INTERVAL_SECONDS := 0.10
const FAR_RETARGET_MIN_SECONDS := 0.28
const FAR_RETARGET_STAGGER_SECONDS := 0.017
const NEAR_RETARGET_MIN_SECONDS := 0.18
const NEAR_RETARGET_STAGGER_SECONDS := 0.011
const BACKGROUND_AI_INTERVAL_SECONDS := 0.25
const BACKGROUND_AI_MIN_DISTANCE := 1200.0
const ENVIRONMENT_GUARD_INTERVAL_SECONDS := 0.10
const ENEMY_MOTION_MASK := WorldSpatialRulesScript.WORLD_LAYER | WorldSpatialRulesScript.PLAYER_LAYER
const POISON_INDICATOR_STYLE := "overhead_three_diamonds"
const NAME_LABEL_SIZE := Vector2(140, 24)
const NAME_LABEL_HEALTH_BAR_GAP := 4.0

static var _crowd_grid_physics_frame := -1
static var _crowd_grid: Dictionary = {}
static var _crowd_grid_build_count := 0
static var _crowd_grid_actor_scan_count := 0
static var _crowd_query_candidate_count := 0
static var _crowd_steering_evaluation_count := 0
static var _retarget_full_scan_count := 0
static var _background_ai_evaluation_count := 0
static var _physics_move_count := 0
static var _environment_guard_check_count := 0

signal died(enemy: EnemyActor, monster_data: Dictionary)
signal target_requested(enemy: EnemyActor)
signal summon_requested(enemy: EnemyActor, monster_ids: Array, count: int, max_active: int)
signal relocation_requested(enemy: EnemyActor, radius_cells: int)

var monster_data: Dictionary = {}
var monster_id := -1
var display_name := "怪物"
var max_hp := 20
var current_hp := 20
var attack_min := 1
var attack_max := 2
var agility := WarriorCombatMath.BASE_AGILITY
var anti_poison := 0
var level := 1
var move_speed := 55.0
var aggro_radius := 384.0 # 12 logical tiles; authored monsters may override.
var attack_range := 38.0
var target: Node2D
var primary_target: PlayerCharacter
var is_boss := false
var poison_time := 0.0
var poison_damage := 0
var control_time := 0.0:
	set(value):
		if value > 0.0 and control_time <= 0.0:
			_control_anchor = global_position
		control_time = value
var charm_time := 0.0
var dormant := false
var life_steal_ratio := 0.0
var control_on_hit_seconds := 0.0
var is_targeted := false
var facing := Vector2.DOWN
var movement_facing := Vector2.DOWN
var visual: MonsterVisual
var name_label: Label
var collision_radius := ArtSpec.MONSTER_COLLISION_RADIUS
var environment_blocker: Node
var _dying := false
var boss_rule: Dictionary = {}
var behavior_profile: Dictionary = {}
var service_ai_code := -1
var service_move_interval_ms := 0
var stationary := false
var area_attack_rule: Dictionary = {}
var summon_rule: Dictionary = {}

var _attack_timer := 0.0
var _attack_interval := 1.55
var _attack_animation_duration := 0.46
var _attack_hit_delay := 0.0
var _pending_attack_time := -1.0
var _pending_attack_damage := 0
var _pending_attack_target: Node2D
var _retarget_timer := 0.0
var _crowd_steering_timer := 0.0
var _cached_crowd_separation := Vector2.ZERO
var _background_ai_timer := 0.0
var _boss_skill_cooldown := 3.0
var _boss_warning := 0.0
var _boss_phase_two := false
var _boss_phase_enabled := true
var _boss_skill_enabled := true
var _boss_skill_direction := Vector2.DOWN
var _last_boss_skill_hit := false
var _boss_health_stage := -1
var _boss_rage_time := 0.0
var _boss_base_move_speed := 0.0
var _boss_base_attack_interval := 0.0
var _burrowed := false
var _rng := RandomNumberGenerator.new()
var _threat_table := {}
var _threat_decay_per_second := 4.0
var _leash_multiplier := 1.5
var _control_anchor := Vector2.INF
var _area_attack_cooldown := 0.0
var _area_attack_warning := 0.0
var _summon_cooldown := 0.0
var _summon_warning := 0.0
var _environment_guard_timer := 0.0
var _last_environment_safe_position := Vector2.INF


func setup(data: Dictionary, player_target: PlayerCharacter, boss := false) -> void:
	monster_data = data
	monster_id = MonsterIdentityScript.monster_id(data)
	target = player_target
	primary_target = player_target
	is_boss = boss
	display_name = str(data.get("name", "怪物"))
	max_hp = maxi(1, int(data.get("hp", 20)))
	current_hp = max_hp
	attack_min = maxi(1, int(data.get("attackMin", 1)))
	attack_max = maxi(attack_min, int(data.get("attackMax", attack_min + 1)))
	agility = maxi(1, int(data.get("agility", data.get("speedPoint", WarriorCombatMath.BASE_AGILITY))))
	anti_poison = maxi(0, int(data.get("antiPoison", 0)))
	level = maxi(1, int(data.get("level", 1)))
	move_speed = 40.0 if is_boss else 58.0
	if not is_boss and int(data.get("attackIntervalMs", 0)) > 0:
		_attack_interval = float(data.get("attackIntervalMs")) / 1000.0
	behavior_profile = MonsterIdentityScript.behavior_profile(data)
	_apply_behavior_profile()
	if is_boss:
		boss_rule = MonsterIdentityScript.boss_rule(data, GameData.boss_service_rules)
		if not boss_rule.is_empty():
			_apply_boss_rule()
	if stationary:
		move_speed = 0.0


func _apply_behavior_profile() -> void:
	var projection: Dictionary = behavior_profile.get("runtimeProjection", {})
	move_speed = float(projection.get("moveSpeed", move_speed))
	attack_range = float(projection.get("attackRange", attack_range))
	aggro_radius = float(projection.get("aggroRadius", aggro_radius))
	var timing: Dictionary = behavior_profile.get("timing", {})
	if int(timing.get("attackIntervalMs", 0)) > 0:
		_attack_interval = float(timing.get("attackIntervalMs")) / 1000.0
	service_move_interval_ms = int(timing.get("moveIntervalMs", 0))
	service_ai_code = int(behavior_profile.get("serviceBehavior", {}).get("aiCode", -1))
	stationary = bool(behavior_profile.get("movement", {}).get("stationary", false))
	area_attack_rule = behavior_profile.get("areaAttack", {}).duplicate(true)
	_area_attack_cooldown = float(area_attack_rule.get("initialCooldownSeconds", 0.0))
	summon_rule = behavior_profile.get("summonRule", {}).duplicate(true)
	_summon_cooldown = float(summon_rule.get("initialCooldownSeconds", 0.0))
	if stationary:
		move_speed = 0.0
	life_steal_ratio = float(behavior_profile.get("lifeStealRatio", life_steal_ratio))
	dormant = bool(behavior_profile.get("dormant", dormant))
	var on_hit: Dictionary = behavior_profile.get("onHit", {})
	control_on_hit_seconds = float(on_hit.get("controlSeconds", control_on_hit_seconds))


func _apply_boss_rule() -> void:
	var projection: Dictionary = boss_rule.get("runtimeProjection", {})
	var timing: Dictionary = boss_rule.get("timing", {})
	move_speed = float(projection.get("moveSpeed", move_speed))
	attack_range = float(projection.get("attackRange", attack_range))
	aggro_radius = float(projection.get("aggroRadius", aggro_radius))
	_attack_interval = float(timing.get("attackIntervalMs", 1550)) / 1000.0
	_attack_animation_duration = float(timing.get("attackAnimationMs", 460)) / 1000.0
	_attack_hit_delay = float(timing.get("hitDelayMs", 0)) / 1000.0
	var special: Dictionary = boss_rule.get("specialSkill", {})
	_boss_skill_enabled = bool(special.get("enabled", false))
	_boss_skill_cooldown = float(special.get("initialCooldownSeconds", _boss_skill_cooldown))
	_boss_phase_enabled = bool(boss_rule.get("phaseTwo", {}).get("enabled", false))
	var mechanics: Dictionary = boss_rule.get("mechanics", {})
	var burrow: Dictionary = mechanics.get("burrowAmbush", {})
	_burrowed = bool(burrow.get("enabled", false))
	if _burrowed:
		dormant = true
	var summon: Dictionary = mechanics.get("healthStageSummon", {})
	var rage: Dictionary = mechanics.get("healthStageRage", {})
	_boss_health_stage = int(summon.get("stages", rage.get("stages", -1)))
	_boss_base_move_speed = move_speed
	_boss_base_attack_interval = _attack_interval


func _ready() -> void:
	MonsterVisualScript.configure_actor_y_sort_item(self, "actor_root")
	add_to_group("enemies")
	input_pickable = true
	collision_layer = WorldSpatialRulesScript.ENEMY_LAYER
	# The crowd grid/separation policy is authoritative for monster-to-monster
	# spacing. Keeping ENEMY_LAYER in this mask makes the physics server solve the
	# same dense crowd again for every moving actor, which scales disastrously.
	# World and player remain hard physics collisions.
	collision_mask = ENEMY_MOTION_MASK
	if not bool(behavior_profile.get("worldCollision", true)):
		# 飞行怪参与攻击和选取，但不作为人物移动的实体墙。
		collision_layer = 0
		collision_mask = WorldSpatialRulesScript.WORLD_MASK
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	safe_margin = 0.35
	max_slides = 6
	_rng.randomize()
	var collision := CollisionShape2D.new()
	collision.name = "CollisionShape2D"
	var shape := CircleShape2D.new()
	var authored_radius := float(behavior_profile.get("collisionRadius", -1.0))
	collision_radius = ArtSpec.BOSS_COLLISION_RADIUS if is_boss else (authored_radius if authored_radius > 0.0 else ArtSpec.MONSTER_COLLISION_RADIUS)
	shape.radius = collision_radius
	collision.shape = shape
	add_child(collision)
	_resolve_invalid_spawn_overlap()
	_last_environment_safe_position = global_position
	_environment_guard_timer = ENVIRONMENT_GUARD_INTERVAL_SECONDS * float(posmod(get_instance_id(), 11)) / 11.0
	name_label = Label.new()
	MonsterVisualScript.configure_actor_y_sort_item(name_label, "name_label")
	name_label.text = display_name
	name_label.size = NAME_LABEL_SIZE
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_color_override("font_color", Color(1.0, 0.60, 0.34) if is_boss else Color(0.82, 0.78, 0.66))
	add_child(name_label)
	visual = MonsterVisualScript.new()
	visual.name = "MonsterVisual"
	visual.setup(self)
	add_child(visual)
	refresh_name_label_position()
	if _burrowed:
		visual.visible = false
		name_label.visible = false
	if boss_rule.is_empty():
		_retarget_timer = FAR_RETARGET_STAGGER_SECONDS * float(posmod(get_instance_id(), 11))
		_crowd_steering_timer = CROWD_STEERING_INTERVAL_SECONDS * float(posmod(get_instance_id(), 7)) / 7.0
		_background_ai_timer = BACKGROUND_AI_INTERVAL_SECONDS * float(posmod(get_instance_id(), 13)) / 13.0
	queue_redraw()


func _resolve_invalid_spawn_overlap() -> void:
	if not is_instance_valid(primary_target):
		return
	var offset := global_position - primary_target.global_position
	var minimum_distance := collision_radius + ArtSpec.PLAYER_COLLISION_RADIUS + 14.0
	if offset.length() >= minimum_distance:
		return
	if offset.length_squared() < 0.01:
		var angle := float(posmod(get_instance_id(), 32)) / 32.0 * TAU
		offset = Vector2.from_angle(angle)
	global_position = primary_target.global_position + offset.normalized() * minimum_distance


func set_targeted(value: bool) -> void:
	is_targeted = value
	queue_redraw()


func _input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventScreenTouch and event.pressed:
		target_requested.emit(self)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		target_requested.emit(self)


func _physics_process(delta: float) -> void:
	if _dying:
		return
	_attack_timer = maxf(0.0, _attack_timer - delta)
	_update_status_effects(delta)
	_update_pending_attack(delta)
	if _can_use_background_ai():
		_background_ai_timer -= delta
		if _background_ai_timer <= 0.0:
			_background_ai_timer = BACKGROUND_AI_INTERVAL_SECONDS
			_background_ai_evaluation_count += 1
			_retarget(BACKGROUND_AI_INTERVAL_SECONDS)
			if not is_instance_valid(target):
				_return_to_spawn()
		return
	_background_ai_timer = 0.0
	_retarget(delta)
	if _update_area_attack(delta):
		velocity = Vector2.ZERO
		queue_redraw()
		return
	if _update_behavior_summon(delta):
		velocity = Vector2.ZERO
		queue_redraw()
		return
	# Keep the established retarget/attack/summon timing, but immobilization must
	# win over the no-target return path after an actor is relocated beyond its
	# authored spawn leash.
	if control_time > 0.0 or charm_time > 0.0:
		if _control_anchor == Vector2.INF:
			_control_anchor = global_position
		else:
			global_position = _control_anchor
		velocity = Vector2.ZERO
		queue_redraw()
		return
	_control_anchor = Vector2.INF
	if not is_instance_valid(target):
		_return_to_spawn()
		return
	if target is PlayerCharacter and _point_inside_safe_zone(target.global_position):
		_pending_attack_time = -1.0
		_pending_attack_target = null
		velocity = Vector2.ZERO
		var spawn_position:Vector2=get_meta("spawn_position",global_position)
		if _point_inside_safe_zone(global_position) and global_position.distance_to(spawn_position)>4.0:
			velocity=global_position.direction_to(spawn_position)*move_speed
			_move_with_spatial_rules(delta)
		queue_redraw()
		return
	var offset := target.global_position - global_position
	var distance := offset.length()
	if _burrowed:
		var burrow: Dictionary = boss_rule.get("mechanics", {}).get("burrowAmbush", {})
		if distance <= float(burrow.get("emergeRange", 128.0)):
			_burrowed = false
			dormant = false
			if bool(burrow.get("healToFullOnEmerge", false)):
				current_hp = max_hp
			if visual != null:
				visual.visible = true
			name_label.visible = true
		else:
			velocity = Vector2.ZERO
			return
	var contact_distance := collision_radius + _target_collision_radius(target) + 14.0
	var engagement_distance := maxf(attack_range, contact_distance)
	if offset.length_squared() > 0.001:
		facing = offset.normalized()
	if _pending_attack_time >= 0.0:
		velocity = Vector2.ZERO
		queue_redraw()
		return
	if dormant:
		var wake_range := float(behavior_profile.get("wakeRange", 190.0))
		var stone_wake: Dictionary = boss_rule.get("mechanics", {}).get("stoneWake", {})
		wake_range = float(stone_wake.get("wakeRange", wake_range))
		if distance <= wake_range:
			dormant = false
		else:
			velocity = Vector2.ZERO
			queue_redraw()
			return
	if target.has_method("is_stealthed") and target.is_stealthed() and distance > 35.0:
		velocity = Vector2.ZERO
		return
	if is_boss and _boss_skill_enabled:
		_update_boss_skill(delta, distance)
	if move_speed > 0.0 and distance < contact_distance - 3.0 and distance > 0.01 and not target is PlayerCharacter:
		# 怪物和召唤物重叠时可以自行分离；玩家普通移动不能迫使怪物后退。
		velocity = -offset.normalized() * move_speed * 0.72
	elif distance <= engagement_distance:
		velocity = Vector2.ZERO
		if _attack_timer <= 0.0:
			_attack_timer = _current_attack_interval()
			if visual != null:
				visual.play_attack(maxf(_attack_animation_duration,0.62))
			var dealt_damage := _rng.randi_range(attack_min, attack_max)
			if _attack_hit_delay > 0.0:
				_pending_attack_time = _attack_hit_delay
				_pending_attack_target = target
				_pending_attack_damage = dealt_damage
			else:
				_deal_melee_hit(target, dealt_damage)
	elif distance <= aggro_radius:
		var pursuit := offset.normalized()
		var steering := pursuit + _crowd_separation_for_motion(delta) * 0.72
		# Separation may move sideways but must never reverse a pursuing monster.
		# Removing the negative forward component eliminates visible rollback.
		if steering.dot(pursuit) < 0.12:
			steering += pursuit * (0.12 - steering.dot(pursuit))
		var desired_velocity := steering.normalized() * move_speed
		velocity = velocity.lerp(desired_velocity, clampf(delta * 10.0, 0.0, 1.0))
	else:
		velocity = velocity.move_toward(Vector2.ZERO, move_speed * 3.0 * delta)
	# 零速度时不做碰撞恢复，避免玩家压住碰撞边缘时把怪物挤走。
	if velocity.length_squared() > 0.01:
		_move_with_spatial_rules(delta)
		if get_real_velocity().length_squared() > 9.0:
			movement_facing = get_real_velocity().normalized()
	if is_boss and is_instance_valid(target):
		var fresh_offset := target.global_position - global_position
		if fresh_offset.length_squared() > 0.001:
			facing = fresh_offset.normalized()
	if visual != null and visual.is_fallback_attacking():
		queue_redraw()


func _point_inside_safe_zone(point:Vector2)->bool:
	return WorldSpatialRulesScript.point_inside_safe_zones(point, get_meta("safe_zones", []))


func _move_with_spatial_rules(delta := 1.0 / 60.0) -> void:
	var position_before_move := global_position
	move_and_slide()
	_physics_move_count += 1
	var entered_safe_zone := not _point_inside_safe_zone(position_before_move) and _point_inside_safe_zone(global_position)
	if entered_safe_zone:
		global_position = position_before_move
		velocity = Vector2.ZERO
		return
	# Physics chunks are the per-frame wall authority. The imported occupancy
	# provider is a deterministic fallback, sampled at a staggered 10 Hz instead
	# of doing five script calls for every moving monster on every physics tick.
	# A failed sample rolls back to the last verified point, so a rebuilding or
	# temporarily absent chunk cannot let an actor tunnel through map occupancy.
	if _last_environment_safe_position == Vector2.INF or position_before_move.distance_squared_to(_last_environment_safe_position) > 4096.0:
		_last_environment_safe_position = position_before_move
		_environment_guard_timer = 0.0
	_environment_guard_timer = maxf(0.0, _environment_guard_timer - maxf(0.0, delta))
	if _environment_guard_timer > 0.0:
		return
	_environment_guard_timer = ENVIRONMENT_GUARD_INTERVAL_SECONDS
	_environment_guard_check_count += 1
	if WorldSpatialRulesScript.environment_blocks_actor(environment_blocker, global_position, collision_radius):
		global_position = _last_environment_safe_position
		velocity = Vector2.ZERO
	else:
		_last_environment_safe_position = global_position


func _current_attack_interval() -> float:
	if not boss_rule.is_empty():
		var phase: Dictionary = boss_rule.get("phaseTwo", {})
		return _attack_interval * (float(phase.get("attackIntervalMultiplier", 1.0)) if _boss_phase_two else 1.0)
	return (0.78 if _boss_phase_two else 1.15) if is_boss else _attack_interval


func _update_pending_attack(delta: float) -> void:
	if _pending_attack_time < 0.0:
		return
	_pending_attack_time -= delta
	if _pending_attack_time > 0.0:
		return
	var hit_target := _pending_attack_target
	var damage := _pending_attack_damage
	_pending_attack_time = -1.0
	_pending_attack_target = null
	_pending_attack_damage = 0
	if not is_instance_valid(hit_target):
		return
	if _target_is_safe_player(hit_target):
		return
	var offset := hit_target.global_position - global_position
	var hit_distance := maxf(attack_range, collision_radius + _target_collision_radius(hit_target) + 14.0) + 8.0
	if offset.length() > hit_distance:
		return
	if offset.length_squared() > 0.001:
		facing = offset.normalized()
	_deal_melee_hit(hit_target, damage)


func _deal_melee_hit(hit_target: Node2D, dealt_damage: int) -> void:
	if not is_instance_valid(hit_target) or not hit_target.has_method("take_damage") or _target_is_safe_player(hit_target):
		return
	hit_target.take_damage(dealt_damage)
	apply_life_steal(dealt_damage)
	if control_on_hit_seconds > 0.0 and hit_target.has_method("apply_control"):
		hit_target.apply_control(control_on_hit_seconds)
	var on_hit: Dictionary = behavior_profile.get("onHit", {})
	var poison_damage_value := int(on_hit.get("poisonDamage", 0))
	if poison_damage_value > 0 and hit_target.has_method("apply_poison"):
		hit_target.apply_poison(poison_damage_value, float(on_hit.get("poisonSeconds", 0.0)))


func _target_is_safe_player(hit_target: Node2D) -> bool:
	return hit_target is PlayerCharacter and _point_inside_safe_zone(hit_target.global_position)


func _update_area_attack(delta: float) -> bool:
	if not bool(area_attack_rule.get("enabled", false)):
		return false
	if _area_attack_warning > 0.0:
		_area_attack_warning -= delta
		if _area_attack_warning <= 0.0:
			for victim: Node2D in _area_attack_targets():
				_deal_melee_hit(victim, _rng.randi_range(attack_min, attack_max))
			_area_attack_cooldown = _attack_interval
	elif _area_attack_cooldown > 0.0:
		_area_attack_cooldown = maxf(0.0, _area_attack_cooldown - delta)
	elif not _area_attack_targets().is_empty():
		_area_attack_warning = maxf(0.001, float(area_attack_rule.get("hitDelaySeconds", 0.2)))
		if visual != null:
			visual.play_attack(maxf(_attack_animation_duration, _area_attack_warning))
	return true


func _area_attack_targets() -> Array[Node2D]:
	var result: Array[Node2D] = []
	var candidates: Array[Node] = []
	if is_instance_valid(primary_target):
		candidates.append(primary_target)
	for node: Node in get_tree().get_nodes_in_group("combat_targets"):
		if not candidates.has(node):
			candidates.append(node)
	var range_pixels := float(area_attack_rule.get("rangePixels", attack_range))
	for node: Node in candidates:
		if (
			node is Node2D
			and node.has_method("take_damage")
			and not _point_inside_safe_zone(node.global_position)
			and global_position.distance_to(node.global_position) <= range_pixels
		):
			result.append(node)
	return result


func _update_behavior_summon(delta: float) -> bool:
	if not bool(summon_rule.get("enabled", false)):
		return false
	if _summon_warning > 0.0:
		_summon_warning -= delta
		if _summon_warning <= 0.0:
			var ids: Array = summon_rule.get("monsterIds", []).duplicate()
			if not ids.is_empty():
				summon_requested.emit(
					self,
					ids,
					maxi(1, int(summon_rule.get("count", 1))),
					maxi(1, int(summon_rule.get("maxActive", 15)))
				)
			_summon_cooldown = _attack_interval
	elif _summon_cooldown > 0.0:
		_summon_cooldown = maxf(0.0, _summon_cooldown - delta)
	elif is_instance_valid(target):
		_summon_warning = maxf(0.001, float(summon_rule.get("delaySeconds", 0.5)))
		if visual != null:
			visual.play_attack(maxf(_attack_animation_duration, _summon_warning))
	return true


func _target_collision_radius(target_node: Node2D) -> float:
	if target_node is PlayerCharacter:
		return ArtSpec.PLAYER_COLLISION_RADIUS
	if target_node is EnemyActor:
		return target_node.collision_radius
	if target_node is SummonActor:
		return target_node.collision_radius
	return 16.0


func _crowd_separation() -> Vector2:
	_ensure_crowd_grid()
	var separation := Vector2.ZERO
	var center_cell := _crowd_grid_cell(global_position)
	for offset_y in range(-1, 2):
		for offset_x in range(-1, 2):
			var bucket: Array = _crowd_grid.get(center_cell + Vector2i(offset_x, offset_y), [])
			for value: Variant in bucket:
				_crowd_query_candidate_count += 1
				if not is_instance_valid(value):
					continue
				var node := value as Node
				if node == self or not node is EnemyActor or node.is_queued_for_deletion():
					continue
				var other := node as EnemyActor
				var away := global_position - other.global_position
				var desired := collision_radius + other.collision_radius + 12.0
				var distance := away.length()
				if distance >= desired:
					continue
				if distance < 0.01:
					var angle := float(posmod(get_instance_id(), 16)) / 16.0 * TAU
					away = Vector2.from_angle(angle)
					distance = 1.0
				separation += away.normalized() * (1.0 - distance / desired)
	return separation.limit_length(1.0)


func _crowd_separation_for_motion(delta: float) -> Vector2:
	_crowd_steering_timer = maxf(0.0, _crowd_steering_timer - delta)
	if _crowd_steering_timer > 0.0:
		return _cached_crowd_separation
	_crowd_steering_timer = CROWD_STEERING_INTERVAL_SECONDS
	_crowd_steering_evaluation_count += 1
	_cached_crowd_separation = _crowd_separation()
	return _cached_crowd_separation


func _ensure_crowd_grid() -> void:
	var physics_frame := Engine.get_physics_frames()
	if _crowd_grid_physics_frame >= 0 and physics_frame - _crowd_grid_physics_frame < CROWD_GRID_REFRESH_FRAMES:
		return
	_crowd_grid_physics_frame = physics_frame
	_crowd_grid.clear()
	_crowd_grid_build_count += 1
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		if not node is EnemyActor or node.is_queued_for_deletion():
			continue
		_crowd_grid_actor_scan_count += 1
		var enemy := node as EnemyActor
		var cell := _crowd_grid_cell(enemy.global_position)
		var bucket: Array = _crowd_grid.get(cell, [])
		bucket.append(enemy)
		_crowd_grid[cell] = bucket


func _crowd_grid_cell(world_position: Vector2) -> Vector2i:
	return Vector2i(floori(world_position.x / CROWD_GRID_CELL_SIZE), floori(world_position.y / CROWD_GRID_CELL_SIZE))


static func reset_performance_diagnostics() -> void:
	_crowd_grid_physics_frame = -1
	_crowd_grid.clear()
	_crowd_grid_build_count = 0
	_crowd_grid_actor_scan_count = 0
	_crowd_query_candidate_count = 0
	_crowd_steering_evaluation_count = 0
	_retarget_full_scan_count = 0
	_background_ai_evaluation_count = 0
	_physics_move_count = 0
	_environment_guard_check_count = 0


static func performance_diagnostics() -> Dictionary:
	return {
		"crowd_grid_builds": _crowd_grid_build_count,
		"crowd_grid_actor_scans": _crowd_grid_actor_scan_count,
		"crowd_query_candidates": _crowd_query_candidate_count,
		"crowd_steering_evaluations": _crowd_steering_evaluation_count,
		"retarget_full_scans": _retarget_full_scan_count,
		"background_ai_evaluations": _background_ai_evaluation_count,
		"physics_moves": _physics_move_count,
		"environment_guard_checks": _environment_guard_check_count,
	}


func _can_use_background_ai() -> bool:
	if is_boss or not is_instance_valid(primary_target):
		return false
	if target != primary_target and is_instance_valid(target):
		return false
	if not _threat_table.is_empty() or poison_time > 0.0 or control_time > 0.0 or charm_time > 0.0:
		return false
	if _pending_attack_time >= 0.0 or _area_attack_warning > 0.0 or _summon_warning > 0.0:
		return false
	var activation_distance := maxf(BACKGROUND_AI_MIN_DISTANCE, aggro_radius + 256.0)
	return global_position.distance_squared_to(primary_target.global_position) > activation_distance * activation_distance


func apply_life_steal(dealt_damage: int) -> void:
	if life_steal_ratio <= 0.0 or dealt_damage <= 0:
		return
	current_hp = mini(max_hp, current_hp + maxi(1, int(dealt_damage * life_steal_ratio)))


func take_damage(amount: int, attacker: Node2D = null) -> void:
	if _dying:
		return
	if is_instance_valid(attacker):
		_add_threat(attacker, float(maxi(1,amount))*5.0+25.0)
	current_hp = maxi(0, current_hp - amount)
	if is_boss and not boss_rule.is_empty():
		_apply_health_stage_mechanics()
	if visual != null and current_hp > 0:
		visual.play_hit()
	if is_boss and _boss_phase_enabled and not _boss_phase_two and current_hp <= max_hp / 2:
		_boss_phase_two = true
		var phase: Dictionary = boss_rule.get("phaseTwo", {})
		move_speed *= float(phase.get("moveSpeedMultiplier", 1.0))
		attack_range = float(phase.get("attackRange", attack_range))
		_boss_skill_cooldown = minf(_boss_skill_cooldown, float(phase.get("skillCooldownSeconds", _boss_skill_cooldown)))
	queue_redraw()
	if current_hp == 0:
		_begin_death()


func _begin_death() -> void:
	_dying = true
	velocity = Vector2.ZERO
	_pending_attack_time = -1.0
	_pending_attack_target = null
	input_pickable = false
	collision_layer = 0
	collision_mask = 0
	remove_from_group("enemies")
	if name_label != null:
		name_label.visible = false
	var has_death_art := visual != null and visual.uses_final_art()
	if has_death_art:
		visual.play_death()
	died.emit(self, monster_data)
	if has_death_art:
		_finish_death_after_animation()
	else:
		queue_free()


func _finish_death_after_animation() -> void:
	await get_tree().create_timer(0.64).timeout
	if is_instance_valid(self):
		queue_free()


func apply_poison(tick_damage: int, seconds: float) -> void:
	poison_damage = maxi(poison_damage, maxi(1, tick_damage))
	poison_time = maxf(poison_time, seconds)
	queue_redraw()


func apply_control(seconds: float) -> void:
	# Re-applying control after a scripted relocation must pin the new position,
	# not an obsolete anchor captured before teleport/knockback resolution.
	if seconds > 0.0:
		_control_anchor = global_position
		_pending_attack_time = -1.0
		_pending_attack_target = null
		_pending_attack_damage = 0
		velocity = Vector2.ZERO
	control_time = maxf(control_time, seconds)
	queue_redraw()


func apply_charm(seconds: float) -> void:
	charm_time = maxf(charm_time, seconds)
	queue_redraw()


func _update_status_effects(delta: float) -> void:
	var had_visible_status := poison_time > 0.0 or control_time > 0.0 or charm_time > 0.0
	var previous_poison_second := int(ceil(poison_time))
	poison_time = maxf(0.0, poison_time - delta)
	control_time = maxf(0.0, control_time - delta)
	charm_time = maxf(0.0, charm_time - delta)
	if _boss_rage_time > 0.0:
		_boss_rage_time = maxf(0.0, _boss_rage_time - delta)
		if _boss_rage_time <= 0.0:
			move_speed = _boss_base_move_speed
			_attack_interval = _boss_base_attack_interval
	if poison_time > 0.0 and int(ceil(poison_time)) < previous_poison_second:
		take_damage(poison_damage)
	var has_visible_status := poison_time > 0.0 or control_time > 0.0 or charm_time > 0.0
	if had_visible_status != has_visible_status:
		queue_redraw()


func _apply_health_stage_mechanics() -> void:
	if _boss_health_stage <= 0 or max_hp <= 0:
		return
	var mechanics: Dictionary = boss_rule.get("mechanics", {})
	var summon: Dictionary = mechanics.get("healthStageSummon", {})
	var rage: Dictionary = mechanics.get("healthStageRage", {})
	var stage_count := int(summon.get("stages", rage.get("stages", _boss_health_stage)))
	var current_stage := int(floor(float(current_hp) / float(max_hp) * float(stage_count)))
	if current_stage >= _boss_health_stage:
		return
	_boss_health_stage -= 1
	if bool(summon.get("enabled", false)):
		var count := _rng.randi_range(int(summon.get("minCount", 6)), int(summon.get("maxCount", 11)))
		var ids: Array = summon.get("monsterIds", []).duplicate()
		summon_requested.emit(self, ids, count, int(summon.get("maxActive", 30)))
	if bool(rage.get("enabled", false)):
		_boss_rage_time = float(rage.get("durationSeconds", 8.0))
		move_speed = _boss_base_move_speed * float(rage.get("moveSpeedMultiplier", 1.0))
		_attack_interval = float(rage.get("attackIntervalSeconds", _boss_base_attack_interval))


func _retarget(delta := 0.0) -> void:
	if charm_time > 0.0:
		return
	_decay_threat(delta)
	_retarget_timer = maxf(0.0, _retarget_timer - delta)
	if not boss_rule.is_empty():
		if is_instance_valid(target) and _retarget_timer > 0.0:
			return
	else:
		# Ordinary monsters keep their current target between decision ticks.
		# Damage threat still switches immediately in _add_threat(), so scanning
		# the target set every physics frame adds CPU cost without improving
		# reaction latency.
		# delta == 0 is the explicit decision API used when the target set changes
		# immediately (for example, a newly summoned combat target). Physics calls
		# always pass delta and remain rate-limited.
		if _retarget_timer > 0.0 and delta > 0.0:
			return
	_retarget_full_scan_count += 1
	var chosen: Node2D
	var best_score := -INF
	var spawn_position:Vector2=get_meta("spawn_position",global_position)
	var leash_radius:=aggro_radius*_leash_multiplier
	var candidates:Array=[]
	if is_instance_valid(primary_target):candidates.append(primary_target)
	for node: Node in get_tree().get_nodes_in_group("combat_targets"):
		if node is Node2D and is_instance_valid(node) and not candidates.has(node):candidates.append(node)
	for node:Node2D in candidates:
		if _point_inside_safe_zone(node.global_position):continue
		var distance := global_position.distance_to(node.global_position)
		var spawn_distance:=spawn_position.distance_to(node.global_position)
		var threat:=_threat_for(node)
		if distance>aggro_radius and threat<=0.0:continue
		if spawn_distance>leash_radius:continue
		var distance_score:=maxf(0.0,1.0-distance/aggro_radius)*100.0
		var score:=threat+distance_score
		if score>best_score:best_score=score;chosen=node
	target = chosen
	if not boss_rule.is_empty():
		var search: Dictionary = boss_rule.get("targetSearch", {})
		_retarget_timer = float(search.get("withTargetMs" if is_instance_valid(target) else "withoutTargetMs", 1000)) / 1000.0
	elif is_instance_valid(target):
		_retarget_timer = NEAR_RETARGET_MIN_SECONDS + NEAR_RETARGET_STAGGER_SECONDS * float(posmod(get_instance_id(), 7))
	else:
		_retarget_timer = FAR_RETARGET_MIN_SECONDS + FAR_RETARGET_STAGGER_SECONDS * float(posmod(get_instance_id(), 11))


func _add_threat(source:Node2D,amount:float)->void:
	var key:=source.get_instance_id()
	_threat_table[key]={"node":weakref(source),"score":float(_threat_table.get(key,{}).get("score",0.0))+maxf(0.0,amount)}
	target=source


func _threat_for(source:Node2D)->float:
	return float(_threat_table.get(source.get_instance_id(),{}).get("score",0.0))


func _decay_threat(delta:float)->void:
	for key:Variant in _threat_table.keys():
		var record:Dictionary=_threat_table[key];var ref:WeakRef=record.get("node")
		var node:Node = null
		if ref!=null:node=ref.get_ref() as Node
		if not is_instance_valid(node):_threat_table.erase(key);continue
		record["score"]=maxf(0.0,float(record.get("score",0.0))-_threat_decay_per_second*delta)
		if float(record.score)<=0.0:_threat_table.erase(key)
		else:_threat_table[key]=record


func _return_to_spawn()->void:
	var spawn_position:Vector2=get_meta("spawn_position",global_position)
	var distance:=global_position.distance_to(spawn_position)
	if distance<=6.0:velocity=Vector2.ZERO;return
	var return_direction := global_position.direction_to(spawn_position)
	velocity=return_direction*move_speed*0.75
	# Walk animation reads movement_facing, not combat facing. Update both before
	# moving so a monster never spends a frame playing its stale pursuit row and
	# visibly backing toward its spawn point.
	facing=return_direction
	movement_facing=return_direction
	_move_with_spatial_rules()
	var actual_motion := get_real_velocity()
	if actual_motion.length_squared()>9.0:
		facing=actual_motion.normalized()
		movement_facing=facing
	queue_redraw()


func _draw() -> void:
	var radius := 27.0 if is_boss else 16.0
	var uses_final_art := visual != null and visual.uses_final_art()
	var ground_center := ground_indicator_center()
	# Final WIL frames already contain their direction-aware source shadow.
	# A second ellipse creates a detached double shadow below the actor.
	if not uses_final_art:
		draw_ellipse_shadow(radius, ground_center)
	if _dying:
		return
	if is_targeted:
		# 细线选中圈与脚底接触阴影共面，避免形成托起Boss的发光平台。
		draw_set_transform(ground_center, 0.0, Vector2(1.0, 0.30))
		draw_circle(Vector2.ZERO, radius + 6.0, Color(1.0, 0.78, 0.18, 0.78), false, 2.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var draw_procedural_fallback := visual == null or visual.should_draw_procedural_fallback()
	var fallback_attacking := draw_procedural_fallback and visual != null and visual.is_fallback_attacking()
	var body_center := Vector2(0, -5) + (visual.fallback_lunge_offset(facing) if fallback_attacking else Vector2.ZERO)
	if draw_procedural_fallback:
		var body_color := Color(0.55, 0.11, 0.09) if is_boss else Color(0.30, 0.48, 0.18)
		var attack_scale:=visual.fallback_attack_scale() if visual!=null else Vector2.ONE
		var attack_angle:=visual.fallback_attack_angle(facing) if visual!=null else 0.0
		draw_set_transform(body_center,attack_angle,attack_scale)
		draw_circle(Vector2.ZERO, radius, body_color.lightened(0.18) if fallback_attacking else body_color)
		draw_set_transform(Vector2.ZERO,0.0,Vector2.ONE)
		if fallback_attacking:
			var strike_angle := facing.angle()
			var progress:=visual.fallback_attack_progress();var tip:=body_center+facing.normalized()*(radius+6.0+sin(progress*PI)*10.0)
			draw_arc(tip, radius + 8.0, strike_angle - 0.82, strike_angle + 0.82, 12, Color(1.0, 0.78, 0.26, 0.90), 4.0)
			draw_circle(tip,4.0+sin(progress*PI)*3.0,Color(1.0,0.9,0.5,0.82))
	if is_boss and _boss_phase_two:
		draw_circle(Vector2(0, -5), radius + 7.0, Color(0.90, 0.15, 0.05, 0.22), false, 4.0)
	if poison_time > 0.0:
		# Poison is an overhead three-diamond badge. It stays readable without
		# creating a green ground ring that can be mistaken for a portal marker.
		var poison_anchor := Vector2(-8.0, poison_indicator_anchor_y())
		for index in range(3):
			var center := poison_anchor + Vector2(float(index) * 8.0, 0.0 if index == 1 else 2.0)
			draw_colored_polygon(PackedVector2Array([
				center + Vector2(0, -3), center + Vector2(3, 0),
				center + Vector2(0, 3), center + Vector2(-3, 0),
			]), Color(0.36, 0.92, 0.28, 0.90))
	if control_time > 0.0 or charm_time > 0.0:
		draw_circle(Vector2(0, -5), radius + 8.0, Color(0.35, 0.65, 1.0, 0.55), false, 3.0)
	if dormant:
		draw_circle(Vector2(0, -5), radius + 3.0, Color(0.52, 0.50, 0.46, 0.72))
	if _boss_warning > 0.0:
		var special: Dictionary = boss_rule.get("specialSkill", {})
		var warning_radius := float(special.get("radius", 155.0))
		if str(special.get("shape", "circle")) == "cone":
			var half_angle := float(special.get("coneHalfAngleRadians", 0.68))
			var sector := PackedVector2Array([Vector2.ZERO])
			for index in range(15):
				var angle := _boss_skill_direction.angle() - half_angle + half_angle * 2.0 * float(index) / 14.0
				sector.append(Vector2.from_angle(angle) * warning_radius)
			draw_colored_polygon(sector, Color(0.95, 0.12, 0.04, 0.22))
			draw_arc(Vector2.ZERO, warning_radius, _boss_skill_direction.angle() - half_angle, _boss_skill_direction.angle() + half_angle, 24, Color(1.0, 0.34, 0.08, 0.92), 5.0)
		else:
			draw_circle(Vector2.ZERO, warning_radius, Color(0.95, 0.18, 0.06, 0.16))
			draw_circle(Vector2.ZERO, warning_radius, Color(1.0, 0.36, 0.12, 0.85), false, 5.0)
	if draw_procedural_fallback:
		draw_circle(body_center + Vector2(-radius * 0.35, -3), 3.0, Color(0.95, 0.75, 0.25))
		draw_circle(body_center + Vector2(radius * 0.35, -3), 3.0, Color(0.95, 0.75, 0.25))
	var bar_width := 80.0 if is_boss else 46.0
	var bar_y := health_bar_anchor_y()
	draw_rect(Rect2(-bar_width * 0.5, bar_y, bar_width, 5), Color(0.10, 0.03, 0.03, 0.9))
	draw_rect(Rect2(-bar_width * 0.5, bar_y, bar_width * float(current_hp) / float(max_hp), 5), Color(0.85, 0.12, 0.08))


func health_bar_anchor_y() -> float:
	var radius := 27.0 if is_boss else 16.0
	var fallback_y := -92.0 if bool(behavior_profile.get("largeClientBoss", false)) else -radius - 24.0
	return visual.health_bar_anchor_y(fallback_y) if visual != null else fallback_y


func name_label_anchor_y() -> float:
	return health_bar_anchor_y() - NAME_LABEL_SIZE.y - NAME_LABEL_HEALTH_BAR_GAP


func refresh_name_label_position() -> void:
	if name_label != null:
		name_label.position = Vector2(-NAME_LABEL_SIZE.x * 0.5, name_label_anchor_y())


func poison_indicator_anchor_y() -> float:
	return health_bar_anchor_y() - 8.0


func ground_indicator_center() -> Vector2:
	var radius := 27.0 if is_boss else 16.0
	var fallback := Vector2(0, radius * 0.28)
	return visual.ground_contact_position(fallback) if visual != null else fallback


func draw_ellipse_shadow(radius: float, center := Vector2.ZERO) -> void:
	draw_set_transform(center, 0.0, Vector2(1.0, 0.36))
	draw_circle(Vector2.ZERO, radius, Color(0, 0, 0, 0.30))
	draw_circle(Vector2(0, -radius * 0.08), radius * 0.56, Color(0, 0, 0, 0.58))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _update_boss_skill(delta: float, distance: float) -> void:
	var special: Dictionary = boss_rule.get("specialSkill", {})
	var phase: Dictionary = boss_rule.get("phaseTwo", {})
	var skill_radius := float(special.get("radius", 155.0))
	var damage_multiplier := int(special.get("damageMultiplier", 1))
	if _boss_phase_two:
		damage_multiplier = int(phase.get("skillDamageMultiplier", damage_multiplier))
	if _boss_warning > 0.0:
		queue_redraw()
		_boss_warning -= delta
		if _boss_warning <= 0.0:
			_last_boss_skill_hit = false
			if str(special.get("shape", "circle")) == "cone" and is_instance_valid(target):
				var fresh_offset := target.global_position - global_position
				var in_cone := fresh_offset.length() <= skill_radius and fresh_offset.normalized().dot(_boss_skill_direction) >= cos(float(special.get("coneHalfAngleRadians", 0.68)))
				if in_cone and not _target_is_safe_player(target):
					target.take_damage(_rng.randi_range(attack_min, attack_max) * damage_multiplier)
					_last_boss_skill_hit = true
			else:
				var target_mode := str(special.get("targetMode", "current_target"))
				var victims: Array[Node2D] = []
				if target_mode == "all_combat_targets":
					victims = _boss_skill_targets(skill_radius)
				elif is_instance_valid(target):
					victims.append(target)
				for victim: Node2D in victims:
					if _target_is_safe_player(victim):
						continue
					victim.take_damage(_rng.randi_range(attack_min, attack_max) * damage_multiplier)
					_apply_boss_skill_status(victim, special)
					_last_boss_skill_hit = true
			_boss_skill_cooldown = float(phase.get("skillCooldownSeconds", special.get("cooldownSeconds", 4.6))) if _boss_phase_two else float(special.get("cooldownSeconds", 4.6))
	elif _boss_skill_cooldown > 0.0:
		_boss_skill_cooldown -= delta
	elif distance <= float(special.get("triggerRange", 250.0)):
		_boss_skill_direction = (target.global_position - global_position).normalized() if is_instance_valid(target) else facing
		_boss_warning = maxf(0.001, float(special.get("warningSeconds", 0.85)))
		if visual != null:
			visual.play_attack(float(special.get("animationSeconds", _attack_animation_duration)))


func _boss_skill_targets(radius: float) -> Array[Node2D]:
	var result: Array[Node2D] = []
	var candidates: Array[Node] = []
	if is_instance_valid(primary_target):
		candidates.append(primary_target)
	for node: Node in get_tree().get_nodes_in_group("combat_targets"):
		if not candidates.has(node):
			candidates.append(node)
	for node: Node in candidates:
		if node is Node2D and node.has_method("take_damage") and not _target_is_safe_player(node) and global_position.distance_to(node.global_position) <= radius:
			result.append(node)
	return result


func _apply_boss_skill_status(victim: Node2D, special: Dictionary) -> void:
	if _rng.randf() > float(special.get("statusChance", 0.0)):
		return
	var poison_weight := maxi(0, int(special.get("poisonWeight", 0)))
	var control_weight := maxi(0, int(special.get("controlWeight", 0)))
	if poison_weight + control_weight <= 0:
		return
	if _rng.randi_range(1, poison_weight + control_weight) <= poison_weight and victim.has_method("apply_poison"):
		victim.apply_poison(int(special.get("poisonDamage", 1)), float(special.get("poisonSeconds", 1.0)))
	elif victim.has_method("apply_control"):
		victim.apply_control(float(special.get("controlSeconds", 1.0)))


func request_surrounded_relocation(blocking_neighbor_count: int) -> bool:
	var relocation: Dictionary = boss_rule.get("mechanics", {}).get("surroundedRelocation", {})
	if not bool(relocation.get("enabled", false)) or blocking_neighbor_count < int(relocation.get("blockingNeighbors", 5)):
		return false
	relocation_requested.emit(self, int(relocation.get("radiusCells", 4)))
	return true
