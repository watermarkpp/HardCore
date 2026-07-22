extends Node

func _ready()->void:
	var player:=PlayerCharacter.new();player.global_position=Vector2(300,0);add_child(player)
	var enemy:=EnemyActor.new();enemy.setup(GameData.get_monster("多钩猫"),player,false);enemy.global_position=Vector2.ZERO;enemy.set_meta("spawn_position",Vector2.ZERO);enemy.set_meta("safe_zones",[]);add_child(enemy)
	assert(is_equal_approx(enemy.aggro_radius,384.0))
	assert(enemy.aggro_radius/32.0==12.0)
	enemy._add_threat(player,100.0);assert(enemy._threat_for(player)>=100.0)
	enemy._decay_threat(1.0);assert(enemy._threat_for(player)<100.0)
	var visual:=enemy.visual;visual.play_attack(0.46)
	assert(visual._attack_remaining>0.0)
	enemy.apply_poison(1, 5.0)
	assert(EnemyActor.POISON_INDICATOR_STYLE == "overhead_three_diamonds", "poison feedback regressed to a ground ring")
	assert(enemy.poison_indicator_anchor_y() < enemy.health_bar_anchor_y(), "poison indicator must stay overhead")
	assert(enemy.poison_indicator_anchor_y() < enemy.ground_indicator_center().y - 24.0, "poison feedback regressed to a ground/portal ring")
	var fallback_enemy:=EnemyActor.new();fallback_enemy.display_name="测试占位怪";var fallback:=MonsterVisual.new();fallback.setup(fallback_enemy);fallback_enemy.visual=fallback;fallback.play_attack(0.46);fallback._attack_remaining=0.23
	assert(fallback.is_fallback_attacking());assert(fallback.fallback_attack_scale()!=Vector2.ONE)
	fallback.free();fallback_enemy.free();enemy.queue_free();player.queue_free()
	print("MONSTER_THREAT_ANIMATION_PASS")
	get_tree().quit()
