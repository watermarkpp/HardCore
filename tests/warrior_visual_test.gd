extends Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.select_profession("战士")
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	var visual: Node2D = game.player.get_node("PlayerVisual")
	var sprite: Sprite2D = visual.get_node("BodySprite")
	var health_bar: PlayerHealthBar = game.player.get_node("HealthBar")
	var fixed_health_bar_position := health_bar.position
	assert(fixed_health_bar_position == ArtSpec.PLAYER_HEALTH_BAR_OFFSET, "player health bar must use a fixed actor-space anchor")
	assert(visual.visible and visual.uses_final_art(), "warrior final art should be active")
	assert(sprite.texture.get_size() == Vector2(768, 1280), "warrior idle atlas size is wrong")
	assert(sprite.region_rect.size == Vector2(ArtSpec.WARRIOR_FRAME) and sprite.position == -Vector2(ArtSpec.WARRIOR_FOOT_ANCHOR), "warrior frame size or foot anchor is wrong")
	for marker_name in ["hand_r", "hand_l", "head", "back", "feet"]:
		assert(visual.has_node(marker_name), "warrior marker missing: %s" % marker_name)
	for layer_name in ["ClientWeaponLayer", "ClientHelmetLayer", "WeaponAccent", "ArmorAccent", "HelmetAccent", "SkillEffect", "ClientSkillEffect", "WeaponAudio"]:
		assert(visual.has_node(layer_name), "warrior visual layer missing: %s" % layer_name)
	PlayerState.equipment["武器"] = {"name": "炼狱", "durability": 10}
	PlayerState.equipment["衣服"] = {"name": "重盔甲(男)", "durability": 10}
	PlayerState.equipment["头盔"] = {"name": "黑铁头盔", "durability": 10}
	PlayerState.equipment_changed.emit()
	visual._process(0.01)
	assert(visual.get_node("ClientWeaponLayer").visible and not visual.get_node("WeaponAccent").visible, "client weapon layer did not replace placeholder accent")
	var helmet_layer: Sprite2D = visual.get_node("ClientHelmetLayer")
	assert(not visual.get_node("ArmorAccent").visible and not visual.get_node("HelmetAccent").visible, "translucent equipment prototype residue is still visible")
	assert(helmet_layer.visible and helmet_layer.texture.resource_path.ends_with("black_iron_helmet_idle.png"), "directional world helmet idle art is missing")
	assert(helmet_layer.region_enabled and not helmet_layer.centered, "helmet must use the body atlas region rather than a floating icon")
	assert(helmet_layer.texture.get_size() == Vector2(768, 1280), "helmet idle atlas must supply four frames across all eight directions")
	var helmet_image := helmet_layer.texture.get_image()
	var direction_hashes := {}
	for row in range(8):
		var cell := helmet_image.get_region(Rect2i(0, row * ArtSpec.WARRIOR_FRAME.y, ArtSpec.WARRIOR_FRAME.x, ArtSpec.WARRIOR_FRAME.y))
		direction_hashes[hash(cell.get_data())] = true
	assert(direction_hashes.size() >= 6, "helmet atlas is duplicated front art rather than real directional frames")
	assert(helmet_layer.region_rect == sprite.region_rect and helmet_layer.position == sprite.position, "helmet and body regions must share one foot-anchored cell")
	assert(sprite.texture.resource_path.ends_with("dress_006_idle.png"), "equipped heavy armor should select its Hum atlas")
	game.player.facing = Vector2.RIGHT
	visual._process(0.2)
	assert(visual.current_direction == 2, "warrior east direction mapping is wrong")
	game.player.facing = Vector2.UP
	visual._process(0.2)
	assert(visual.current_direction == 0, "warrior north Hum row mapping is wrong")
	game.player.facing = Vector2.DOWN
	visual._process(0.2)
	assert(visual.current_direction == 4, "warrior south Hum row mapping is wrong")
	game.player.velocity = Vector2.RIGHT * 80.0
	visual._process(0.12)
	assert(visual.current_state == "walk", "warrior should switch to walk state")
	assert(sprite.texture.resource_path.ends_with("dress_006_walk.png"), "warrior walk state should use equipped dress atlas")
	assert(helmet_layer.texture.resource_path.ends_with("black_iron_helmet_walk.png"), "helmet must switch to its directional walk atlas")
	assert(health_bar.position == fixed_health_bar_position, "walking must not move the health bar")
	assert(sprite.texture.get_size() == Vector2(1152, 1280), "warrior walk atlas must contain MIR2 six-frame directions")
	var attack_emitted := [false]
	game.player.attack_requested.connect(func(_origin: Vector2, _direction: Vector2, _damage: int) -> void: attack_emitted[0] = true)
	game.player._attack_timer = 0.0
	game.player.request_attack()
	assert(not attack_emitted[0], "warrior damage must not occur before the attack hit frame")
	await get_tree().create_timer(0.19).timeout
	assert(attack_emitted[0], "warrior damage was not emitted at the configured windup")
	assert(visual.current_frame >= 2, "warrior hit timing must align with client effect frame two")
	visual.play_action("attack", 0.5)
	visual._process(0.05)
	assert(visual.current_state == "action", "warrior attack state did not trigger")
	assert(visual.current_animation_name() == "attack", "warrior action name was not preserved")
	assert(sprite.texture.resource_path.ends_with("dress_006_attack.png"), "warrior attack should use equipped dress atlas")
	assert(helmet_layer.texture.resource_path.ends_with("black_iron_helmet_attack.png"), "helmet must switch to its directional attack atlas")
	assert(health_bar.position == fixed_health_bar_position, "attacking must not move the health bar into the chest")
	assert(sprite.texture.get_size() == Vector2(1152, 1280), "warrior attack atlas must contain MIR2-size six-frame directions")
	assert(sprite.region_rect.size == Vector2(ArtSpec.WARRIOR_ATTACK_FRAME), "warrior attack should use the MIR2 attack frame size")
	assert(sprite.position == -Vector2(ArtSpec.WARRIOR_ATTACK_FOOT_ANCHOR), "warrior attack foot anchor should preserve MIR2 offsets")
	visual.play_action("烈火剑法", 0.86)
	visual._process(0.01)
	assert(sprite.texture.resource_path.ends_with("dress_006_attack.png"), "warrior skills should reuse the equipped attack atlas")
	assert(visual.current_animation_name() == "烈火剑法" and visual.get_node("ClientSkillEffect").visible, "warrior client skill effect is missing")
	var hp_before_hit: int = game.player.current_hp
	game.player.current_hp = hp_before_hit - 1
	game.player.stats_changed.emit(game.player.current_hp, game.player.max_hp)
	visual.play_hit()
	visual._process(0.01)
	assert(visual.current_animation_name() == "hit", "warrior hit state did not trigger")
	assert(sprite.texture.resource_path.ends_with("dress_006_hit.png"), "warrior hit should use equipped dress atlas")
	assert(helmet_layer.texture.resource_path.ends_with("black_iron_helmet_hit.png"), "helmet must switch to its directional hit atlas")
	assert(health_bar.current_hp == hp_before_hit - 1, "independent health bar did not receive the damage value")
	assert(health_bar.position == fixed_health_bar_position, "being hit must not relocate the health bar")
	assert(sprite.texture.get_size() == Vector2(576, 1280), "warrior hit atlas must contain MIR2 three-frame directions")
	visual.play_death()
	visual._process(0.01)
	assert(visual.current_animation_name() == "death", "warrior death state did not trigger")
	assert(sprite.texture.resource_path.ends_with("dress_006_death.png"), "warrior death should use equipped dress atlas")
	assert(helmet_layer.texture.resource_path.ends_with("black_iron_helmet_death.png"), "helmet must switch to its directional death atlas")
	assert(health_bar.position == fixed_health_bar_position, "death animation must not relocate the health bar")
	assert(sprite.texture.get_size() == Vector2(768, 1280), "warrior death atlas must contain MIR2 four-frame directions")
	visual.play_action("attack", 0.5)
	assert(visual.current_animation_name() == "death", "death state must not be interrupted by attack")
	PlayerState.select_profession("法师")
	await get_tree().process_frame
	assert(not visual.visible and not visual.uses_final_art(), "mage should fall back to procedural placeholder")
	print("WARRIOR_VISUAL_PASS: warrior idle/walk/attack/hit/death atlases, hit timing, anchors, markers, and state switching are valid")
	get_tree().quit(0)
