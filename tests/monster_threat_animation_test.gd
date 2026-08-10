extends Node

func _ready()->void:
	var player:=PlayerCharacter.new();player.global_position=Vector2(300,0);add_child(player)
	var enemy:=EnemyActor.new();enemy.setup(GameData.get_monster("多钩猫"),player,false);enemy.global_position=Vector2.ZERO;enemy.set_meta("spawn_position",Vector2.ZERO);enemy.set_meta("safe_zones",[]);add_child(enemy)
	assert(is_equal_approx(enemy.aggro_radius_gu, 12.0))
	enemy._add_threat(player,100.0);assert(enemy._threat_for(player)>=100.0)
	enemy._decay_threat(1.0);assert(enemy._threat_for(player)<100.0)
	var visual:=enemy.visual;visual.play_attack(0.46)
	assert(visual._attack_remaining>0.0)
	enemy.apply_poison(1, 5.0)
	enemy.set_meta("canonical_red_poison", {
		"contract_id": "buff.taoist.red_poison.v1",
		"expires_at_ms": Time.get_ticks_msec() + 5000,
	})
	assert(EnemyActor.POISON_INDICATOR_STYLE == "overhead_three_diamonds", "poison feedback regressed to a ground ring")
	var health_bar_rect := Rect2(
		-enemy.overhead.bar_width * 0.5,
		enemy.health_bar_anchor_y(),
		enemy.overhead.bar_width,
		MonsterOverhead.HEALTH_BAR_HEIGHT
	)
	assert(enemy.poison_indicator_anchor_y() > health_bar_rect.end.y, "green poison must sit below the HP bar")
	assert(enemy.red_poison_indicator_anchor_y() > health_bar_rect.end.y, "red poison must sit below the HP bar")
	assert(not enemy.poison_indicator_rect().intersects(health_bar_rect))
	assert(not enemy.red_poison_indicator_rect().intersects(health_bar_rect))
	assert(not enemy.poison_indicator_rect().intersects(enemy.red_poison_indicator_rect()))
	assert(enemy.poison_indicator_anchor_y() < enemy.ground_indicator_center().y - 24.0, "poison feedback regressed to a ground/portal ring")
	var timing_enemy := EnemyActor.new()
	timing_enemy.max_hp = 100
	timing_enemy.current_hp = 100
	add_child(timing_enemy)
	timing_enemy.apply_poison(3, 4.0, 2.0)
	timing_enemy._update_status_effects(1.99)
	assert(timing_enemy.current_hp == 100, "2-second poison tick fired early")
	timing_enemy._update_status_effects(0.01)
	assert(timing_enemy.current_hp == 97, "2-second poison first tick missing")
	timing_enemy._update_status_effects(1.99)
	assert(timing_enemy.current_hp == 97, "2-second poison second tick fired early")
	timing_enemy._update_status_effects(0.01)
	assert(timing_enemy.current_hp == 94, "2-second poison second tick missing")
	assert(timing_enemy.poison_time == 0.0)
	assert(timing_enemy.poison_damage == 0 and timing_enemy.poison_tick_elapsed_seconds == 0.0)
	var refresh_enemy := EnemyActor.new()
	refresh_enemy.max_hp = 100
	refresh_enemy.current_hp = 100
	add_child(refresh_enemy)
	refresh_enemy.apply_poison(4, 5.0, 2.0)
	refresh_enemy._update_status_effects(1.25)
	var duration_before_refresh := refresh_enemy.poison_time
	refresh_enemy.apply_poison(1, 1.0, 2.0)
	assert(refresh_enemy.poison_time == duration_before_refresh, "short refresh reduced poison duration")
	refresh_enemy._update_status_effects(0.74)
	assert(refresh_enemy.current_hp == 100)
	refresh_enemy._update_status_effects(0.01)
	assert(refresh_enemy.current_hp == 96, "poison refresh reset accumulated tick progress")
	var fallback_enemy:=EnemyActor.new();fallback_enemy.display_name="测试占位怪";var fallback:=MonsterVisual.new();fallback.setup(fallback_enemy);fallback_enemy.visual=fallback;fallback.play_attack(0.46);fallback._attack_remaining=0.23
	assert(not fallback.has_authored_client_art() and fallback.should_draw_procedural_fallback(), "unmapped test monster lost its intentional procedural fallback")
	assert(fallback.is_fallback_attacking());assert(fallback.fallback_attack_scale()!=Vector2.ONE)
	fallback.free();fallback_enemy.free();timing_enemy.queue_free();refresh_enemy.queue_free();enemy.queue_free();player.queue_free()
	print("MONSTER_THREAT_ANIMATION_PASS")
	get_tree().quit()
