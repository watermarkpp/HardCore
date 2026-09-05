extends Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var file := FileAccess.open("res://assets/data/warrior_client_art_sources.json", FileAccess.READ)
	assert(file != null, "战士客户端美术来源表不存在")
	var source: Variant = JSON.parse_string(file.get_as_text())
	assert(source is Dictionary, "战士客户端美术来源表不是有效JSON")
	assert(source.effects.get("攻杀剑术", {}).get("hitEffectBase", -1) == 800, "攻杀Magic.wil基址错误")
	assert(source.effects.get("刺杀剑术", {}).get("hitEffectBase", -1) == 1410, "刺杀Magic.wil基址错误")
	assert(source.effects.get("半月弯刀", {}).get("hitEffectBase", -1) == 1700, "半月Magic.wil基址错误")
	assert(source.effects.get("烈火剑法", {}).get("hitEffectBase", -1) == 3480, "烈火Magic.wil基址错误")
	assert(source.missingSkillSounds.size() == 8, "客户端缺失130—137号技能WAV没有完整记录")
	assert(source.clientAssetDistribution == "client.classic_raw_complete", "技能特效没有绑定全面扫描后的主客户端")
	assert(source.clientRuleDistribution == "source.original_gameofmir.mirclient", "技能方向规则没有绑定主客户端规则")
	var actor_offset: Array = source.alignment.runtimeActorOffset
	assert(Vector2(float(actor_offset[0]), float(actor_offset[1])) == Vector2(-32, -28), "技能特效与战士运行脚点的坐标差未记录")
	for path in ["res://assets/audio/warrior/51.wav", "res://assets/audio/warrior/52.wav", "res://assets/audio/warrior/57.wav"]:
		assert(ResourceLoader.exists(path), "已存在的客户端武器声没有接入：%s" % path)

	var expected_sizes := {
		"power_hit.png": Vector2i(1344, 1792), "long_hit.png": Vector2i(1728, 1792),
		"wide_hit.png": Vector2i(1440, 1792),
		"fire_hit_d0_f0.png": Vector2i(1920, 1920), "fire_hit_d0_f1.png": Vector2i(1920, 1920),
		"fire_hit_d1_f0.png": Vector2i(1920, 1920), "fire_hit_d1_f1.png": Vector2i(1920, 1920),
	}
	for filename: String in expected_sizes:
		var texture := load("res://assets/art/characters/warrior/effects/%s" % filename) as Texture2D
		assert(texture != null and Vector2i(texture.get_size()) == expected_sizes[filename], "客户端技能图集规格错误：%s" % filename)

	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.learned_skills = {"攻杀剑术": 3, "刺杀剑术": 3, "半月弯刀": 3, "烈火剑法": 3}
	PlayerState.quick_slots = ["攻杀剑术", "刺杀剑术", "半月弯刀", "烈火剑法"]
	PlayerState.recalculate_stats()
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	var visual: Node2D = game.player.visual
	var effect_sprite := visual.get_node("ClientSkillEffect") as Sprite2D
	var effect_line := visual.get_node("SkillEffect") as Line2D
	var audio := visual.get_node("WeaponAudio") as AudioStreamPlayer2D
	game.player.facing = Vector2.RIGHT
	visual.play_action("攻杀剑术", 0.51)
	visual._process(0.19)
	assert(effect_sprite.visible and not effect_line.visible, "攻杀没有使用客户端Magic.wil效果")
	assert(effect_sprite.texture.resource_path.ends_with("power_hit.png"), "攻杀效果图集错误")
	assert(effect_sprite.region_rect.position == Vector2(visual.current_frame * 224, visual.current_direction * 224), "攻杀帧/方向区域错误")
	assert(effect_sprite.position == -Vector2(86, 130) + Vector2(-32, -28), "技能特效没有与迁移后的战士脚点保持同一演员原点")
	assert(audio.stream != null and audio.stream.resource_path.ends_with("57.wav"), "空手攻击没有使用客户端57号挥击声")
	assert(not audio.playing, "暂时关闭技能音效时不得启动WeaponAudio播放")
	visual.play_action("半月弯刀", 0.51)
	visual.play_passive_proc_effect("攻杀剑术", 0.24)
	visual._process(0.05)
	var passive_proc_sprite := visual.get_node("PassiveProcSkillEffect") as Sprite2D
	assert(
		effect_sprite.visible
		and effect_sprite.texture.resource_path.ends_with("wide_hit.png"),
		"攻杀触发错误覆盖了半月主体特效"
	)
	assert(
		passive_proc_sprite.visible
		and passive_proc_sprite.texture.resource_path.ends_with("power_hit.png"),
		"攻杀没有作为独立概率附加层显示"
	)
	assert(visual._action_name == "半月弯刀", "攻杀附加层错误替换主体动作")

	PlayerState.equipment["武器"] = {"name": "裁决之杖", "durability": 30, "max_durability": 30}
	PlayerState.equipment_changed.emit()
	visual.play_action("烈火剑法", 0.51)
	visual._process(0.40)
	assert(effect_sprite.texture.resource_path.ends_with("fire_hit_d0_f1.png"), "烈火没有切换到原尺寸分片图集")
	assert(effect_sprite.region_rect.size == Vector2(640, 480), "烈火仍在使用缩小后的旧画布")
	var frame_index: int = int(visual.current_direction) * 6 + int(visual.current_frame)
	var weapon_frame: Dictionary = visual._weapon_attack_source_frames[frame_index]
	var fire_frame: Dictionary = GameData.warrior_client_art.effects.get("烈火剑法", {}).sourceFrames[frame_index]
	var attachment := Vector2(weapon_frame.weaponTipOffset[0] - fire_frame.ignitionOffset[0], weapon_frame.weaponTipOffset[1] - fire_frame.ignitionOffset[1])
	assert(effect_sprite.position == -Vector2(296, 267) + Vector2(-32, -28) + attachment, "烈火没有逐帧吸附到武器头")

	visual.play_action("野蛮冲撞", 0.51)
	visual._process(0.19)
	assert(not effect_sprite.visible and not effect_line.visible, "无正式素材的技能不应继续显示V形占位特效")
	game.hud.update_warrior_states({
		"slaying_auto": true,
		"thrusting": true,
		"half_moon": false,
		"fire_enabled": true,
		"fire_armed": true,
		"fire_expires_remaining_ms": 10_000,
	})
	assert(
		"攻杀:几率" in game.hud.warrior_state_label.text
		and "刺杀:开" in game.hud.warrior_state_label.text
		and "烈火:开·充能" in game.hud.warrior_state_label.text,
		"HUD没有显示攻杀概率层、战士开关与烈火充能状态"
	)
	assert(game.hud.quick_buttons.is_empty(), "已取消的中央四技能按钮不应恢复")

	print("WARRIOR_CLIENT_ART_PASS：四套Magic.wil八方向效果、现存武器WAV与HUD状态提示已接入，缺失技能WAV已显式记录")
	get_tree().quit(0)
