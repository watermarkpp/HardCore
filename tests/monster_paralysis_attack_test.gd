extends Node


# 169 is the retired duplicate record for 月魔蜘蛛0. The compatibility map
# still points it at moth_control, but it is intentionally absent at runtime.
const PARALYSIS_MONSTER_IDS := [46, 60, 128, 168]


func _ready() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var target := PlayerCharacter.new()
	target.max_hp = 10000
	target.current_hp = 10000
	target.current_mp = 0
	target.defense_min = 0
	target.defense_max = 0
	add_child(target)
	await get_tree().process_frame

	for monster_id: int in PARALYSIS_MONSTER_IDS:
		var enemy := EnemyActor.new()
		enemy.setup(GameData.get_monster_by_id(monster_id), target, false)
		assert(enemy.control_on_hit_seconds == 5.0, "monster_id=%d 麻痹时长不是5秒" % monster_id)
		assert(enemy.control_chance_denominator_base == 20, "monster_id=%d 麻痹基础分母不是20" % monster_id)

		target.control_time = 0.0
		enemy._apply_attack_damage(target, 1, false, -1, false, 0)
		assert(target.control_time == 5.0, "monster_id=%d 麻痹成功分支未生效" % monster_id)

		target.control_time = 0.0
		enemy._apply_attack_damage(target, 1, false, -1, false, 1)
		assert(target.control_time == 0.0, "monster_id=%d 麻痹失败分支错误触发" % monster_id)
		enemy.free()

	var touch_dragon := EnemyActor.new()
	touch_dragon.setup(GameData.get_monster_by_id(124), target, true)
	var touch_dragon_status: Dictionary = touch_dragon.attack_delivery_rule.get("status", {})
	assert(float(touch_dragon_status.get("statusChance", 0.0)) == 0.25)
	assert(int(touch_dragon_status.get("poisonWeight", 0)) == 2)
	assert(int(touch_dragon_status.get("controlWeight", 0)) == 1)
	assert(float(touch_dragon_status.get("controlSeconds", 0.0)) == 5.0)
	touch_dragon.free()

	print("MONSTER_PARALYSIS_ATTACK_PASS ids=%s touch_dragon=1/12x5s" % str(PARALYSIS_MONSTER_IDS))
	get_tree().quit(0)
