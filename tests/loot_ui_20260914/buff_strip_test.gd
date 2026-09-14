extends Node
const Root := preload("res://scripts/game_root.gd")
const HUD := preload("res://scripts/hud.gd")

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	assert(GameData.ensure_loaded())
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	var game := Root.new()
	var player := PlayerCharacter.new()
	game.player = player
	game.hud = HUD.new()
	add_child(game.hud)
	for i in range(3): await get_tree().process_frame
	var hud: GameHUD = game.hud
	print("BUFF_ANCHOR_GEOMETRY strip=", hud.taoist_buff_icon_strip.get_global_rect(), " slot=", hud.hud_item_buttons[0].get_global_rect())
	assert(absf(hud.taoist_buff_icon_strip.get_global_rect().position.x - hud.hud_item_buttons[0].get_global_rect().position.x) < 0.1)
	var bar_top := INF
	for slot: Button in hud.hud_item_buttons: bar_top = minf(bar_top, slot.get_global_rect().position.y)
	assert(absf(hud.taoist_buff_icon_strip.get_global_rect().end.y - bar_top + 6.0) < 0.1)
	player.apply_mac_buff(40,3)
	var water := GameData.get_item_record(910001)
	assert(PlayerState.apply_temporary_item_buff(water.name, water.effectProfile).ok)
	var started: int = PlayerState.temporary_item_buffs[water.name].started_at_usec
	player.apply_ac_buff(30,3)
	player.apply_magic_shield(20,0.2)
	player.apply_stealth(10)
	game._register_ongoing_heal(player.get_instance_id(),1,10,0.8)
	game._update_taoist_buff_hints()
	var entries: Array = game._status_buff_entries()
	assert(entries.size() == 6)
	var item_key := "item:" + str(water.effectProfile.buffGroup)
	var ordered := ["mac",item_key,"ac","shield","stealth","heal"]
	for i in range(ordered.size()):
		var icon: TextureRect = hud._status_buff_icons[ordered[i]]
		assert(icon.visible and icon.texture != null)
		assert(icon.position == Vector2(i * 32, 0) and icon.size == Vector2(26,26))
	assert(hud._status_buff_icons[item_key].texture.resource_path == GameData.get_item_art_path({"item_id":910001}))
	assert(not hud.taoist_buff_hint_label.visible)
	assert(PlayerState.apply_temporary_item_buff(water.name, water.effectProfile).ok)
	assert(PlayerState.temporary_item_buffs[water.name].started_at_usec == started)
	game._update_taoist_buff_hints()
	assert(hud._status_buff_icons[item_key].position.x == 32)
	PlayerState.advance_temporary_item_buffs(4000)
	game._update_taoist_buff_hints()
	assert(not hud._status_buff_icons[item_key].visible)
	assert(hud.taoist_ac_buff_icon.position.x == 32)
	assert(PlayerState.apply_temporary_item_buff(water.name, water.effectProfile).ok)
	game._update_taoist_buff_hints()
	assert(hud._status_buff_icons[item_key].position.x == 160)
	player.free()
	hud.queue_free()
	game.free()
	await get_tree().process_frame
	print("BUFF_STRIP_V81_PASS: chronological order, refresh, expiry, source icons, quick-slot alignment")
	get_tree().quit()
