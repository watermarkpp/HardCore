extends Node
const Root := preload("res://scripts/game_root.gd")
const HUD := preload("res://scripts/hud.gd")

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	assert(GameData.ensure_loaded())
	assert(PlayerState.is_processing(), "autoload must have its production timer enabled")
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	# Drive the same production _process(delta) deterministically at the boundary.
	PlayerState.set_process(false)
	PlayerState.level = 60
	PlayerState.inventory = []
	PlayerState.equipment = PlayerState._empty_equipment()
	PlayerState.recalculate_stats(false)
	var baseline := PlayerState.computed_stats.duplicate(true)
	var game := Root.new()
	game.player = PlayerCharacter.new()
	game.hud = HUD.new()
	add_child(game.hud)
	var checked := 0
	for raw: Dictionary in GameData.item_runtime_authority.newItems:
		if raw.useEffect != "temporary_stat_buff": continue
		var item := GameData.get_item_record(int(raw.itemId))
		var duration := float(item.effectProfile.durationSeconds)
		var key := "item:" + str(item.effectProfile.buffGroup)
		PlayerState.inventory = [{"name":item.name,"item_id":int(raw.itemId),"count":1}]
		PlayerState.use_inventory_index(0)
		assert(PlayerState.item_count(item.name) == 0 and not PlayerState.temporary_item_buffs.is_empty())
		assert(PlayerState.computed_stats != baseline, "used water must affect real computed stats")
		game._update_taoist_buff_hints()
		var icon: TextureRect = game.hud._status_buff_icons[key]
		assert(icon.visible and icon.texture != null)
		PlayerState._process(duration - 0.01)
		game._update_taoist_buff_hints()
		assert(icon.visible and not PlayerState.temporary_item_buffs.is_empty(), "must not expire early")
		PlayerState._process(0.02)
		game._update_taoist_buff_hints()
		assert(PlayerState.temporary_item_buffs.is_empty(), "expired buff entry survived")
		assert(PlayerState.computed_stats == baseline, "expired water left residual stat bonuses: " + str(item.name))
		assert(not icon.visible, "expired water icon survived")
		checked += 1
	assert(checked == 12)
	var water := GameData.get_item_record(910001)
	var duration := float(water.effectProfile.durationSeconds)
	assert(PlayerState.apply_temporary_item_buff(water.name,water.effectProfile).ok)
	PlayerState._process(duration - 1.0)
	assert(PlayerState.apply_temporary_item_buff(water.name,water.effectProfile).ok)
	PlayerState._process(1.1)
	assert(not PlayerState.temporary_item_buffs.is_empty(), "refresh retained old expiry")
	PlayerState._process(duration)
	game._update_taoist_buff_hints()
	assert(PlayerState.temporary_item_buffs.is_empty() and PlayerState.computed_stats == baseline)
	game.hud.queue_free()
	game.player.free()
	game.free()
	await get_tree().process_frame
	print("BUFF_EXPIRY_V81_PASS waters=12 actual_use, production_timer_boundary, stats_removed, icons_removed, refreshed_expiry")
	get_tree().quit()
