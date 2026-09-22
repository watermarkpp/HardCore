extends "res://tests/ui_layout_calibration_workbench.gd"
const OUT := "res://outputs/ui_calibration/loot_ui_20260914/longest_line_centered/"

func _ready() -> void:
	await super._ready()
	await _show_panel(8)
	overlay.hide()
	await _capture("settings_production")
	await _show_panel(1)
	overlay.hide()
	var panel: Control = hud.get("inventory_panel")
	var view = panel.item_detail_presenter
	view.show_item(GameData.get_item_record("珍珠戒指"))
	await _capture("pearl_content_fit")
	var item := GameData.get_item_rules_record({"item_id":128})
	var rules := preload("res://scripts/item_drop_instance_rules.gd")
	for i in range(100):
		var instance := rules.create_instance(item,"v81-shot:%d" % i)
		if rules.is_affixed_instance(instance,item):
			view.show_item(item,instance)
			break
	await _capture("armor_jp_title")
	var metrics := {"plain_title":view.title_label.text,"title_font":view.title_label.get_theme_font_size("font_size"),"body_font":view.detail_label.get_theme_font_size("normal_font_size"),"panel_width":view.size.x,"title_center":view.title_label.position.x+view.title_label.size.x*0.5,"body_ink_center":view.detail_label.position.x+float(view.detail_label.get_content_width())*0.5}
	var evidence := FileAccess.open(OUT+"detail_geometry.json",FileAccess.WRITE)
	evidence.store_string(JSON.stringify(metrics,"\t"))
	evidence.close()
	panel.hide()
	var player: PlayerCharacter = game.get("player")
	player.apply_mac_buff(120,4)
	for id in range(910001,910007):
		var water := GameData.get_item_record(id)
		PlayerState.apply_temporary_item_buff(water.name, water.effectProfile)
	player.apply_ac_buff(150,4)
	game.call("_update_taoist_buff_hints")
	for i in range(15):
		var pickup := LootPickup.new()
		var record := GameData.get_item_record(130 if i % 2 else 99)
		var id := GameData._stable_item_id(record)
		pickup.setup_item_record({"item_id":id,"output_item_id":id,"item_name":record.name,"output_record":record},player)
		pickup.position = player.position + Vector2(140+(i%3)*12,90+(i/3)*8)
		game.add_child(pickup)
		game.get("_loot_pickup_runtime_manager").register_pickup(pickup)
	await _capture("buffs_and_ground_names")
	print("V81_PRESENTATION_CAPTURE_PASS ", OUT)
	get_tree().quit()

func _capture(label: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(OUT)
	assert(get_viewport().get_texture().get_image().save_png(OUT+label+".png") == OK)
