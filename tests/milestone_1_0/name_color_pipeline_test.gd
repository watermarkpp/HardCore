extends Node
const Names := preload("res://scripts/ui_item_name_style.gd")
const Root := preload("res://scripts/game_root.gd")
const HUD := preload("res://scripts/hud.gd")
const Pickup := preload("res://scripts/loot_pickup.gd")

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	assert(GameData.ensure_loaded())
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	var hud := HUD.new()
	add_child(hud)
	var game := Root.new()
	game.hud = hud
	var expected := {80:"E6DDCB",99:"FFD86B",100:"FFD86B",104:"FFD86B",228:"FFD86B",229:"FFD86B",230:"FFD86B",231:"FFD86B",105:"FF943D",103:"FF943D",151:"FF943D",244:"FF943D",232:"C48CFF",140:"C48CFF",113:"C48CFF",108:"C48CFF",252:"C48CFF",920007:"E6DDCB"}
	for id: int in expected:
		var color := Color(expected[id])
		assert(Names.describe({"item_id":id}).color == color, "UI name color id=%d" % id)
		var pickup := Pickup.new()
		pickup.setup_item_record({"item_id":id,"output_item_id":id,"item_name":"测试名字","output_record":GameData.get_item_record(id)},null)
		add_child(pickup)
		var found := false
		for child: Node in pickup.get_children():
			if child is Label:
				assert(child.get_theme_color("font_color") == color,"ground name must match UI id=%d" % id)
				found = true
		assert(found)
		# Run the real successful-outcome -> HUD batch -> toast rendering path.
		var candidates := [{"item_id":id,"item_name":"测试名字","pickup":pickup}]
		game._finish_loot_collection_outcomes(candidates,{"success":true,"outcomes":[{"success":true}]},1,0,Time.get_ticks_usec())
		assert(hud.loot_feedback_layer.toast_labels[0].get_theme_color("font_color") == color,"toast name must match ground and UI id=%d" % id)
		pickup.queue_free()
		await get_tree().process_frame
	assert(Names.describe({"item_id":999999,"name":"屠龙"}).group == "default","never classify by name")
	game.hud = null
	game.free()
	hud.queue_free()
	await get_tree().process_frame
	print("NAME_COLOR_PIPELINE_PASS ids=%d" % expected.size())
	get_tree().quit()
