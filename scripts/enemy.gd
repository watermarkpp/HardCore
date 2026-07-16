class_name EnemyActor
extends CharacterBody2D

const MonsterVisualScript := preload("res://scripts/monster_visual.gd")
const WorldSpatialRulesScript := preload("res://scripts/world_spatial_rules.gd")
const LARGE_CLIENT_BOSSES := ["骷髅精灵", "尸王"]

signal died(enemy: EnemyActor, monster_data: Dictionary)
signal target_requested(enemy: EnemyActor)

var monster_data: Dictionary = {}
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

var _attack_timer := 0.0
var _attack_interval := 1.55
var _attack_animation_duration := 0.46
var _attack_hit_delay := 0.0
var _pending_attack_time := -1.0
var _pending_attack_damage := 0
var _pending_attack_target: Node2D
var _retarget_timer := 0.0
var _boss_skill_cooldown := 3.0
var _boss_warning := 0.0
var _boss_phase_two := false
var _boss_phase_enabled := true
var _boss_skill_enabled := true
var _boss_skill_direction := Vector2.DOWN
var _last_boss_skill_hit := false
var _rng := RandomNumberGenerator.new()
var _threat_table := {}
var _threat_decay_per_second := 4.0
var _leash_multiplier := 1.5
var _control_anchor := Vector2.INF


func setup(data: Dictionary, player_target: PlayerCharacter, boss := false) -> void:
	monster_data = data
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
	if is_boss:
		boss_rule = GameData.boss_service_rules.get("runtimeRules", {}).get(display_name, {}).duplicate(true)
		if not boss_rule.is_empty():
			_apply_boss_rule()
	if display_name == "骷髅精灵" and boss_rule.is_empty():
		attack_range = 60.0
		move_speed = 48.0
		aggro_radius = 380.0
		_boss_skill_cooldown = 2.8
	if display_name == "森林雪人":
		move_speed = 52.0
		attack_range = 44.0
		aggro_radius = 330.0
	if display_name == "食人花":
		move_speed = 0.0
		attack_range = 78.0
		aggro_radius = 240.0
	if display_name == "洞蛆":
		move_speed = 32.0
		attack_range = 40.0
	if display_name == "山洞蝙蝠":
		move_speed = 62.0
		attack_range = 36.0
	if display_name == "蝎子":
		move_speed = 48.0
		attack_range = 45.0
	if "火焰沃玛" in display_name:
		attack_range = 155.0
		move_speed = 46.0
		aggro_radius = 360.0
	if display_name == "触龙神":
		attack_range = 210.0
		move_speed = 0.0
		aggro_radius = 430.0
	if display_name == "千年树妖":
		attack_range = 230.0
		move_speed = 0.0
		aggro_radius = 440.0
	if display_name == "幻影蜘蛛":
		attack_range = 210.0
		move_speed = 0.0
		aggro_radius = 400.0
	if display_name == "赤月恶魔":
		attack_range = 260.0
		move_speed = 0.0
		aggro_radius = 470.0
	if display_name == "虹魔教主":
		life_steal_ratio = 0.33
	if display_name == "祖玛弓箭手":
		attack_range = 205.0
		move_speed = 44.0
	if display_name in ["骷髅弓箭手", "牛魔法师"]:
		attack_range = 205.0
		move_speed = 43.0
	if display_name == "牛魔祭司":
		attack_range = 175.0
		life_steal_ratio = 0.2
	if display_name in ["祖玛雕像", "祖玛卫士"]:
		dormant = true
	if display_name in ["楔蛾", "月魔蜘蛛"]:
		control_on_hit_seconds = 1.2


func _apply_boss_rule() -> void:
	var projection: Dictionary = boss_rule.get("runtimeProjection", {})
	var timing: Dictionary = boss_rule.get("timing", {})
	move_speed = float(projection.get("moveSpeed", move_speed))
	attack_range = float(projection.get("attackRange", attack_range))
	aggro_radius = float(projection.get("aggroRadius", aggro_radius))
	_attack_interval = float(timing.get("attackIntervalMs", 1550)) / 1000.0
	_attack_animation_duration = float(timing.get("attackAnimationMs", 460)) / 1000.0
	_attack_hit_delay = float(timing.get("hitDelayMs", 0)) / 1000.0
	_boss_skill_enabled = bool(boss_rule.get("specialSkill", {}).get("enabled", false))
	_boss_phase_enabled = bool(boss_rule.get("phaseTwo", {}).get("enabled", false))


func _ready() -> void:
	add_to_group("enemies")
	input_pickable = true
	collision_layer = WorldSpatialRulesScript.ENEMY_LAYER
	collision_mask = WorldSpatialRulesScript.ENEMY_MASK
	if display_name in ["山洞蝙蝠", "山洞蝙蝠0", "蝙蝠"]:
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
	var common_radius := {"洞蛆": 10.0, "山洞蝙蝠": 12.0, "蝎子": 17.0, "多钩猫": 18.0}.get(display_name, -1.0) as float
	collision_radius = ArtSpec.BOSS_COLLISION_RADIUS if is_boss else (common_radius if common_radius > 0.0 else (20.0 if display_name in ["半兽人", "森林雪人"] else (18.0 if display_name == "食人花" else (15.0 if display_name == "稻草人" else ArtSpec.MONSTER_COLLISION_RADIUS))))
	shape.radius = collision_radius
	collision.shape = shape
	add_child(collision)
	_resolve_invalid_spawn_overlap()
	name_label = Label.new()
	name_label.text = display_name
	name_label.position = Vector2(-70, -116 if display_name in LARGE_CLIENT_BOSSES else (-62 if is_boss else -50))
	name_label.size = Vector2(140, 24)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_color_override("font_color", Color(1.0, 0.60, 0.34) if is_boss else Color(0.82, 0.78, 0.66))
	add_child(name_label)
	visual = MonsterVisualScript.new()
	visual.name = "MonsterVisual"
	visual.setup(self)
	add_child(visual)
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
	_retarget(delta)
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
			_move_with_spatial_rules()
		queue_redraw()
		return
	var offset := target.global_position - global_position
	var distance := offset.length()
	var contact_distance := collision_radius + _target_collision_radius(target) + 14.0
	var engagement_distance := maxf(attack_range, contact_distance)
	if offset.length_squared() > 0.001:
		facing = offset.normalized()
	if _pending_attack_time >= 0.0:
		velocity = Vector2.ZERO
		queue_redraw()
		return
	if dormant:
		if distance <= 190.0:
			dormant = false
		else:
			velocity = Vector2.ZERO
			queue_redraw()
			return
	if control_time > 0.0 or charm_time > 0.0:
		if _control_anchor == Vector2.INF:
			_control_anchor = global_position
		else:
			global_position = _control_anchor
		velocity = Vector2.ZERO
		queue_redraw()
		return
	_control_anchor = Vector2.INF
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
		var steering := pursuit + _crowd_separation() * 0.72
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
		_move_with_spatial_rules()
		if get_real_velocity().length_squared() > 9.0:
			movement_facing = get_real_velocity().normalized()
	if is_boss and is_instance_valid(target):
		var fresh_offset := target.global_position - global_position
		if fresh_offset.length_squared() > 0.001:
			facing = fresh_offset.normalized()
	queue_redraw()


func _point_inside_safe_zone(point:Vector2)->bool:
	return WorldSpatialRulesScript.point_inside_safe_zones(point, get_meta("safe_zones", []))


func _move_with_spatial_rules() -> void:
	var position_before_move := global_position
	move_and_slide()
	var entered_safe_zone := not _point_inside_safe_zone(position_before_move) and _point_inside_safe_zone(global_position)
	if entered_safe_zone or WorldSpatialRulesScript.environment_blocks_actor(environment_blocker, global_position, collision_radius):
		global_position = position_before_move
		velocity = Vector2.ZERO


func _current_attack_interval() -> float:
	if not boss_rule.is_empty():
		return _attack_interval
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
	var offset := hit_target.global_position - global_position
	var hit_distance := maxf(attack_range, collision_radius + _target_collision_radius(hit_target) + 14.0) + 8.0
	if offset.length() > hit_distance:
		return
	if offset.length_squared() > 0.001:
		facing = offset.normalized()
	_deal_melee_hit(hit_target, damage)


func _deal_melee_hit(hit_target: Node2D, dealt_damage: int) -> void:
	if not is_instance_valid(hit_target) or not hit_target.has_method("take_damage"):
		return
	hit_target.take_damage(dealt_damage)
	apply_life_steal(dealt_damage)
	if control_on_hit_seconds > 0.0 and hit_target.has_method("apply_control"):
		hit_target.apply_control(control_on_hit_seconds)
	if display_name in ["邪恶钳虫", "触龙神", "赤月恶魔"] and hit_target.has_method("apply_poison"):
		hit_target.apply_poison(4 if display_name == "触龙神" else 2, 8.0 if display_name == "触龙神" else 6.0)


func _target_collision_radius(target_node: Node2D) -> float:
	if target_node is PlayerCharacter:
		return ArtSpec.PLAYER_COLLISION_RADIUS
	if target_node is EnemyActor:
		return target_node.collision_radius
	if target_node is SummonActor:
		return target_node.collision_radius
	return 16.0


func _crowd_separation() -> Vector2:
	var separation := Vector2.ZERO
	for node: Node in get_tree().get_nodes_in_group("enemies"):
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
	if visual != null and current_hp > 0:
		visual.play_hit()
	if is_boss and _boss_phase_enabled and not _boss_phase_two and current_hp <= max_hp / 2:
		_boss_phase_two = true
		move_speed *= 1.55
		attack_range = 64.0 if display_name == "骷髅精灵" else 46.0
		_boss_skill_cooldown = minf(_boss_skill_cooldown, 1.8)
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
	var previous_poison_second := int(ceil(poison_time))
	poison_time = maxf(0.0, poison_time - delta)
	control_time = maxf(0.0, control_time - delta)
	charm_time = maxf(0.0, charm_time - delta)
	if poison_time > 0.0 and int(ceil(poison_time)) < previous_poison_second:
		take_damage(poison_damage)


func _retarget(delta := 0.0) -> void:
	if charm_time > 0.0:
		return
	_decay_threat(delta)
	if not boss_rule.is_empty():
		_retarget_timer = maxf(0.0, _retarget_timer - delta)
		if is_instance_valid(target) and _retarget_timer > 0.0:
			return
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
	velocity=global_position.direction_to(spawn_position)*move_speed*0.75
	_move_with_spatial_rules()
	if velocity.length_squared()>0.01:facing=velocity.normalized()
	queue_redraw()


func _draw() -> void:
	var radius := 27.0 if is_boss else 16.0
	draw_ellipse_shadow(radius)
	if _dying:
		return
	if is_targeted:
		# 细线选中圈与脚底接触阴影共面，避免形成托起Boss的发光平台。
		draw_set_transform(Vector2(0, radius * 0.28), 0.0, Vector2(1.0, 0.30))
		draw_circle(Vector2.ZERO, radius + 6.0, Color(1.0, 0.78, 0.18, 0.78), false, 2.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var uses_final_art := visual != null and visual.uses_final_art()
	var fallback_attacking := visual != null and visual.is_fallback_attacking()
	var body_center := Vector2(0, -5) + (visual.fallback_lunge_offset(facing) if fallback_attacking else Vector2.ZERO)
	if not uses_final_art:
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
		draw_circle(Vector2(0, -5), radius + 4.0, Color(0.20, 0.85, 0.22, 0.55), false, 3.0)
	if control_time > 0.0 or charm_time > 0.0:
		draw_circle(Vector2(0, -5), radius + 8.0, Color(0.35, 0.65, 1.0, 0.55), false, 3.0)
	if dormant:
		draw_circle(Vector2(0, -5), radius + 3.0, Color(0.52, 0.50, 0.46, 0.72))
	if _boss_warning > 0.0:
		if display_name == "骷髅精灵":
			var sector := PackedVector2Array([Vector2.ZERO])
			for index in range(15):
				var angle := _boss_skill_direction.angle() - 0.68 + 1.36 * float(index) / 14.0
				sector.append(Vector2.from_angle(angle) * 135.0)
			draw_colored_polygon(sector, Color(0.95, 0.12, 0.04, 0.22))
			draw_arc(Vector2.ZERO, 135.0, _boss_skill_direction.angle() - 0.68, _boss_skill_direction.angle() + 0.68, 24, Color(1.0, 0.34, 0.08, 0.92), 5.0)
		else:
			draw_circle(Vector2.ZERO, 155.0, Color(0.95, 0.18, 0.06, 0.16))
			draw_circle(Vector2.ZERO, 155.0, Color(1.0, 0.36, 0.12, 0.85), false, 5.0)
	if not uses_final_art:
		draw_circle(body_center + Vector2(-radius * 0.35, -3), 3.0, Color(0.95, 0.75, 0.25))
		draw_circle(body_center + Vector2(radius * 0.35, -3), 3.0, Color(0.95, 0.75, 0.25))
	var bar_width := 80.0 if is_boss else 46.0
	var bar_y := -92.0 if display_name in LARGE_CLIENT_BOSSES else -radius - 24.0
	draw_rect(Rect2(-bar_width * 0.5, bar_y, bar_width, 5), Color(0.10, 0.03, 0.03, 0.9))
	draw_rect(Rect2(-bar_width * 0.5, bar_y, bar_width * float(current_hp) / float(max_hp), 5), Color(0.85, 0.12, 0.08))


func draw_ellipse_shadow(radius: float) -> void:
	draw_set_transform(Vector2(0, radius * 0.28), 0.0, Vector2(1.0, 0.36))
	draw_circle(Vector2.ZERO, radius, Color(0, 0, 0, 0.30))
	draw_circle(Vector2(0, -radius * 0.08), radius * 0.56, Color(0, 0, 0, 0.58))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _update_boss_skill(delta: float, distance: float) -> void:
	if _boss_warning > 0.0:
		_boss_warning -= delta
		if _boss_warning <= 0.0:
			_last_boss_skill_hit = false
			if display_name == "骷髅精灵" and is_instance_valid(target):
				var fresh_offset := target.global_position - global_position
				var in_cone := fresh_offset.length() <= 135.0 and fresh_offset.normalized().dot(_boss_skill_direction) >= cos(0.68)
				if in_cone:
					target.take_damage(_rng.randi_range(attack_min, attack_max) * (2 if _boss_phase_two else 1))
					_last_boss_skill_hit = true
				_boss_skill_cooldown = 1.8 if _boss_phase_two else 3.4
			else:
				if distance <= 155.0 and is_instance_valid(target):
					target.take_damage(_rng.randi_range(attack_min, attack_max) * (2 if _boss_phase_two else 1))
					_last_boss_skill_hit = true
				_boss_skill_cooldown = 3.2 if _boss_phase_two else 4.6
	elif _boss_skill_cooldown > 0.0:
		_boss_skill_cooldown -= delta
	elif distance <= 250.0:
		_boss_skill_direction = (target.global_position - global_position).normalized() if is_instance_valid(target) else facing
		_boss_warning = 0.68 if display_name == "骷髅精灵" else 0.85
		if display_name == "骷髅精灵" and visual != null:
			visual.play_attack(0.72)
