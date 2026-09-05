extends Node

const FIXTURE_MONSTER_ID := 19
## Authored world_bich_province monster_id=19 spawn tile [40, 13].
const FIXTURE_GROUND_POSITION := Vector2(40.5, 13.5)
const WorldSpatialRulesScript := preload("res://scripts/world_spatial_rules.gd")

var _assignment_change_count := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.level = 50
	PlayerState.learned_skills = {
		"基本剑术": 3,
		"攻杀剑术": 3,
		"刺杀剑术": 3,
		"半月弯刀": 3,
		"烈火剑法": 3,
		"野蛮冲撞": 3,
	}
	PlayerState.attack_skill_slots = [""]
	PlayerState.attack_ring_slots = [
		"刺杀剑术",
		"半月弯刀",
		"烈火剑法",
		"野蛮冲撞",
		"",
		"",
	]
	PlayerState._sync_legacy_quick_slots_from_ring()
	PlayerState.recalculate_stats()
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame

	PlayerState.quick_slots_changed.connect(_on_assignment_changed)
	game.hud.skill_button_assignment_requested.emit({
		"contract_id": "ui.skill.button_assignment.v3",
		"slot_group": "attack_ring",
		"slot_index": 1,
		"slot_id": "hud.attack_ring_skill.2",
		"skill_id": "warrior.wild_rush",
	})
	assert(PlayerState.attack_ring_slots[1] == "野蛮冲撞", "六环槽未保存主动技能")
	assert(PlayerState.attack_ring_slots[0] == "刺杀剑术", "修改单一六环槽污染了其他槽")
	assert(PlayerState.attack_skill_slots == [""], "修改六环槽污染了攻击主键")
	assert(_assignment_change_count == 1, "六环置换没有发出唯一状态信号")
	assert(
		str(game.hud.attack_ring_skill_icons[1].get_meta("skill_name", "")) == "野蛮冲撞",
		"六环置换后HUD没有立即刷新"
	)

	game.hud.skill_button_assignment_requested.emit({
		"contract_id": "ui.skill.button_assignment.v3",
		"slot_group": "attack",
		"slot_index": 0,
		"slot_id": "hud.attack.primary",
		"skill_id": "warrior.wild_rush",
	})
	assert(PlayerState.attack_skill_slots == ["野蛮冲撞"], "主动技能不能绑定攻击主键")
	assert(game.hud.attack_button.get_meta("bound_skill_name", "") == "野蛮冲撞")
	game.hud.skill_button_assignment_requested.emit({
		"contract_id": "ui.skill.button.assignment.v3",
		"slot_group": "attack",
		"slot_index": 0,
		"slot_id": "hud.attack.primary",
		"clear": true,
	})
	assert(PlayerState.attack_skill_slots == ["野蛮冲撞"], "错误合同不应清空攻击主键")
	game.hud.skill_button_assignment_requested.emit({
		"contract_id": "ui.skill.button_assignment.v3",
		"slot_group": "attack",
		"slot_index": 0,
		"slot_id": "hud.attack.primary",
		"clear": true,
	})
	assert(PlayerState.attack_skill_slots == [""], "清空攻击主键没有恢复普通攻击")

	var before_passive := PlayerState.skill_button_assignments_snapshot()
	game.hud.skill_button_assignment_requested.emit({
		"contract_id": "ui.skill.button_assignment.v3",
		"slot_group": "attack_ring",
		"slot_index": 5,
		"slot_id": "hud.attack_ring_skill.6",
		"skill_id": "warrior.slaying_swordsmanship",
	})
	assert(
		PlayerState.skill_button_assignments_snapshot() == before_passive,
		"攻杀被动错误进入主动技能槽"
	)

	var player: PlayerCharacter = game.player
	player.set_physics_process(false)
	player.velocity = Vector2.ZERO
	player.set_test_combat_time_ms(1000)
	player.restore_warrior_runtime_state(PlayerState.warrior_runtime_state_for_restore())
	player.current_mp = 40
	for value: Variant in get_tree().get_nodes_in_group("enemies"):
		if value is EnemyActor:
			(value as EnemyActor).global_position = player.global_position + Vector2(2000, 2000)
	player.facing = Vector2.RIGHT
	var input_deadline_ms := Time.get_ticks_msec() + 5000
	while not game.gameplay_input_is_enabled() and Time.get_ticks_msec() < input_deadline_ms:
		await get_tree().process_frame
	assert(game.gameplay_input_is_enabled(), "世界启动未在战士攻击测试时限内开放输入")
	assert(not game._active_safe_zones.is_empty(), "烈火 fixture needs the formal safe-zone context")
	# Keep both footpoints on an authored outdoor tile.  The old Vector2.ZERO
	# fixture was inside the formal safe polygon and its hand-built enemy was
	# absent from the combat spatial index, so the real release had no eligible
	# target and correctly spent no MP.
	var target_position: Vector2 = game._canonical_ground_gu_to_screen_px(
		FIXTURE_GROUND_POSITION
	)
	var player_position: Vector2 = target_position - Vector2(16.0, 0.0)
	var player_ground: Vector2 = game._canonical_screen_px_to_ground_gu(player_position)
	assert(target_position.is_finite() and player_ground.is_finite(), "烈火 fixture needs a finite map projection")
	game._set_player_world_position(player_position)
	assert(
		not WorldSpatialRulesScript.point_inside_safe_zones_ground_gu(
			FIXTURE_GROUND_POSITION,
			game._active_safe_zones,
		)
			and not WorldSpatialRulesScript.point_inside_safe_zones_ground_gu(
				player_ground,
				game._active_safe_zones,
			),
		"烈火 fixture must be outside the authored safe area"
	)
	var target: EnemyActor = _make_enemy(game, player, target_position)
	# A dynamically added CharacterBody may finish its ready-time overlap
	# correction on the next frame. Pin the fixture after that lifecycle step.
	await get_tree().process_frame
	target.process_mode = Node.PROCESS_MODE_DISABLED
	target.set_combat_position(target_position, &"test_fire_sword_target")
	target.velocity = Vector2.ZERO
	target.apply_control(60.0)
	game._set_locked_target(target, true)
	var target_hp_before: int = target.current_hp

	assert(player.request_skill("烈火剑法"), "烈火开关无法开启")
	assert(player.fire_sword_enabled, "烈火开关状态没有保留")
	assert(player.current_mp == 40, "开启烈火开关不应立即扣MP")
	assert(player.request_attack_toward(Vector2.RIGHT, true, target.get_instance_id()), "烈火开关后攻击输入未被接受")
	await get_tree().create_timer(player.attack_hit_windup + 0.08).timeout
	assert(
		player.current_mp == 33,
		"烈火必须在同一次攻击唯一扣除7点MP（actual=%d target=%s hp=%d）" % [
			player.current_mp,
			target.global_position,
			target.current_hp,
		]
	)
	assert(target.current_hp < target_hp_before, "烈火真实攻击没有命中正式空间注册的目标")
	assert(player.skill_cooldown_remaining_ms("warrior.fire_sword") > 0, "烈火独立冷却未建立")
	assert(game._canonical_fire_charge_expires_ms == 0, "烈火直释错误建立旧式二段充能")
	assert(player.fire_sword_enabled, "烈火释放后不应自动关闭开关")
	assert(player.skill_cooldown_remaining_ms("warrior.wild_rush") == 0, "烈火冷却串到其他技能")

	player._physics_process(player._attack_timer + 0.01)
	var mana_before_fallback := player.current_mp
	assert(player.request_attack_toward(Vector2.RIGHT, true, target.get_instance_id()), "烈火冷却时必须接受低优先级攻击")
	await get_tree().create_timer(player.attack_hit_windup + 0.08).timeout
	assert(player.current_mp == mana_before_fallback, "烈火冷却降级攻击不得再次扣除烈火MP")

	player._physics_process(
		float(player.skill_cooldown_remaining_ms("warrior.fire_sword")) / 1000.0 + 0.01
	)
	assert(player.request_attack_toward(Vector2.RIGHT, true, target.get_instance_id()), "烈火冷却结束后攻击输入未恢复")
	await get_tree().create_timer(player.attack_hit_windup + 0.08).timeout
	assert(player.current_mp == mana_before_fallback - 7, "烈火冷却结束后没有恢复最高优先级")

	PlayerState.quick_slots_changed.disconnect(_on_assignment_changed)
	print("SKILL_RUNTIME_INTEGRATION_PASS：烈火冷却回退及冷却结束优先级恢复正常")
	get_tree().quit(0)


func _on_assignment_changed(_change: Dictionary) -> void:
	_assignment_change_count += 1


func _make_enemy(game: Node, player: PlayerCharacter, position: Vector2) -> EnemyActor:
	var canonical_data: Dictionary = GameData.get_monster_by_id(FIXTURE_MONSTER_ID)
	assert(
		not canonical_data.is_empty(),
		"runtime integration fixture monster_id=%d must exist" % FIXTURE_MONSTER_ID
	)
	var enemy: EnemyActor = game._spawn_enemy(
		canonical_data,
		position,
		false,
		-1.0,
		{
			"respawn_enabled": false,
			"spawn_slot_id": "test:skill_runtime:19",
		},
	)
	assert(
		enemy != null
			and enemy.monster_id == FIXTURE_MONSTER_ID
			and not enemy.is_boss
			and enemy.runtime_map_id == int(game.get("current_map_id"))
			and enemy.projection_ready()
			and enemy.spatial_actor_runtime_id > 0,
		"runtime integration fixture must use the formal exact-ID mapped spawn"
	)
	enemy.max_hp = 9999
	enemy.current_hp = enemy.max_hp
	enemy.primary_target = null
	assert(
		is_instance_valid(enemy)
		and not enemy.is_queued_for_deletion()
		and enemy.can_receive_damage(),
		"runtime integration fixture target must survive exact-ID admission"
	)
	# Freeze the formal fixture after it enters the tree so it cannot leave melee
	# range during the player's wind-up.
	enemy.process_mode = Node.PROCESS_MODE_DISABLED
	enemy.set_combat_position(position, &"test_skill_runtime_target")
	enemy.velocity = Vector2.ZERO
	enemy.apply_control(60.0)
	return enemy
