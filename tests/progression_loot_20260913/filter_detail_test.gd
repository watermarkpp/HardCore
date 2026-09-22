extends Node
const Names := preload("res://scripts/ui_item_name_style.gd")
const Rules := preload("res://scripts/item_drop_instance_rules.gd")
const Detail := preload("res://scripts/item_detail_presenter.gd")
const Manager := preload("res://scripts/loot_pickup_runtime_manager.gd")
const Menu := preload("res://scripts/system_menu_panel.gd")

func _ready() -> void:
	_run.call_deferred()

func _pickup(id: int, instance: Dictionary = {}) -> LootPickup:
	var item := GameData.get_item_record(id)
	var pickup := LootPickup.new()
	pickup.setup_item_record({"item_id":id,"output_item_id":id,"item_name":item.name,"output_record":item,"item_instance":instance}, PlayerCharacter.new())
	add_child(pickup)
	return pickup

func _run() -> void:
	assert(GameData.ensure_loaded())
	PlayerState.test_mode = true
	LootPreferences.storage_path = "user://filter_test_%d.cfg" % Time.get_ticks_usec()
	LootPreferences.set_filter_level(0)
	var low := _pickup(80)
	var wooma := _pickup(99)
	var zuma := _pickup(130)
	var mystery := _pickup(218)
	var potion := _pickup(920007)
	var ring := GameData.get_item_record(212)
	var affixed: Dictionary = {}
	for i in range(1000):
		var candidate := Rules.create_instance(ring,"v80-affix:%d" % i)
		for modifier: Dictionary in candidate.modifiers:
			if modifier.stat == "attack_max":
				affixed = candidate
		if not affixed.is_empty(): break
	assert(not affixed.is_empty())
	var bonus := 0
	for m: Dictionary in affixed.modifiers:
		if m.stat == "attack_max": bonus += int(m.value)
	var text := Detail.format_item(ring,affixed)
	assert("攻击 0-%d" % (5+bonus) in text, text)
	assert("攻击上限" not in text and "攻击力最大值" not in text)
	assert(Names.display_name(ring,affixed).begins_with("★"))
	var jp := _pickup(212,affixed)
	assert(jp.name_label.text.begins_with("★"))
	LootPreferences.set_filter_level(1)
	assert(low.filtered and not low.name_label.visible)
	assert(low.icon_sprite.visible)
	assert(not low.manager_evaluate_collection(true,0.0))
	assert(not wooma.filtered and not zuma.filtered and not mystery.filtered and not jp.filtered and not potion.filtered)
	LootPreferences.set_filter_level(2)
	assert(wooma.filtered and not mystery.filtered and not jp.filtered and not zuma.filtered)
	assert(LootPreferences.flush() == OK)
	LootPreferences.filter_level = 0
	LootPreferences.load_preferences()
	assert(LootPreferences.filter_level == 2 and low.filtered)
	LootPreferences.set_filter_level(0)
	assert(low.name_label.visible and not low.filtered)
	assert(low.manager_evaluate_collection(true,0.0))
	low.reject_collection()
	var manager := Manager.new()
	add_child(manager)
	manager.set_process(false)
	manager.configure_map(1,1,func(p: Vector2)->Vector2:return p,func(p: Vector2)->Vector2:return p)
	assert(manager.register_pickup(low))
	manager._expire_ground_loot(599.0)
	assert(not low.is_queued_for_deletion())
	manager._expire_ground_loot(1.0)
	assert(low.is_queued_for_deletion())
	var menu := Menu.new()
	add_child(menu)
	menu.open_menu()
	menu.show_settings_page()
	var filter_row := menu.loot_filter_slider.get_parent() as Control
	assert(filter_row.position.y > menu.sfx_slider.get_parent().position.y)
	assert(filter_row.position.y + filter_row.size.y <= menu.settings_back_button.position.y)
	assert(not menu.audio_save_note.visible)
	assert(menu.settings_back_button.position == Vector2(72,430))
	assert(menu.settings_back_button.position.y + menu.settings_back_button.size.y <= menu.modal.size.y)
	assert(menu.loot_filter_slider.step == 1 and menu.loot_filter_slider.max_value == 2)
	menu.loot_filter_slider.value = 2
	assert(LootPreferences.filter_level == 2)
	menu.close_menu()
	assert(not LootPreferences.dirty)
	PlayerState.warehouse_inventory = []
	PlayerState.warehouse_inventory.resize(205)
	for i in range(205): PlayerState.warehouse_inventory[i] = {}
	PlayerState.warehouse_inventory[0] = {"name":"untouched","count":1}
	PlayerState.warehouse_inventory[101] = {"name":"B","count":1}
	PlayerState.warehouse_inventory[150] = {"name":"A","count":1}
	PlayerState.warehouse_inventory[202] = {"name":"untouched2","count":1}
	var before := PlayerState.warehouse_inventory.duplicate(true)
	assert(PlayerState.sort_warehouse(1).success)
	assert(PlayerState.warehouse_inventory[100].name == "A" and PlayerState.warehouse_inventory[101].name == "B")
	assert(PlayerState.warehouse_inventory.slice(0,100) == before.slice(0,100))
	assert(PlayerState.warehouse_inventory.slice(200) == before.slice(200))
	for pickup: LootPickup in [low,wooma,zuma,mystery,potion,jp]:
		pickup.target.free()
		pickup.queue_free()
	menu.queue_free()
	manager.queue_free()
	await get_tree().process_frame
	print("FILTER_DETAIL_PASS: ranges, star, live filter exemptions, collection guard, expiry, persistence, slider, page-only sort")
	get_tree().quit(0)
