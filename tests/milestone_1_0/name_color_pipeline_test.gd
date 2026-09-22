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
	var expected := {80:"E6DDCB",99:"FFD86B",100:"FFD86B",101:"FFD86B",195:"FFD86B",218:"FFD86B",219:"FFD86B",220:"FFD86B",102:"FF943D",104:"FF943D",105:"FF943D",128:"FF943D",129:"FF943D",130:"FF943D",131:"FF943D",132:"FF943D",133:"FF943D",151:"FF943D",191:"FF943D",196:"FF943D",221:"FF943D",222:"FF943D",223:"FF943D",224:"FF943D",244:"FF943D",110:"FF943D",232:"C48CFF",140:"C48CFF",145:"C48CFF",103:"C83B35",108:"C83B35",111:"C83B35",112:"C83B35",113:"C83B35",228:"C83B35",229:"C83B35",230:"C83B35",231:"C83B35",252:"C83B35",260:"E6DDCB",920007:"E6DDCB"}
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
				_assert_outline(child, color == Color("C83B35"))
				found = true
		assert(found)
		# Run the real successful-outcome -> HUD batch -> toast rendering path.
		var candidates := [{"item_id":id,"item_name":"测试名字","pickup":pickup}]
		game._finish_loot_collection_outcomes(candidates,{"success":true,"outcomes":[{"success":true}]},1,0,Time.get_ticks_usec())
		assert(hud.loot_feedback_layer.toast_labels[0].get_theme_color("font_color") == color,"toast name must match ground and UI id=%d" % id)
		_assert_outline(hud.loot_feedback_layer.toast_labels[0], color == Color("C83B35"))
		pickup.queue_free()
		await get_tree().process_frame
	assert(Names.describe({"item_id":999999,"name":"屠龙"}).group == "default","never classify by name")
	# Reuse the exact toast label for currency after a red/gold rare item.
	hud.loot_feedback_layer.show_feedback({"item_id":108,"item_name":"屠龙"})
	_assert_outline(hud.loot_feedback_layer.toast_labels[0], true)
	hud.loot_feedback_layer.show_feedback({"item_name":"金币","item_kind":"currency"})
	_assert_outline(hud.loot_feedback_layer.toast_labels[0], false)
	game.hud = null
	game.free()
	hud.queue_free()
	await get_tree().process_frame
	print("NAME_COLOR_PIPELINE_PASS ids=%d" % expected.size())
	get_tree().quit()


func _assert_outline(label: Label, rare: bool) -> void:
	if rare:
		assert(label.get_theme_color("font_outline_color") == Color("B08A3E"), "rare name has dark-gold outline")
		assert(label.get_theme_constant("outline_size") == 2)
	else:
		assert(not label.has_theme_color_override("font_outline_color") and not label.has_theme_constant_override("outline_size"), "ordinary names shed recycled rare outline")
