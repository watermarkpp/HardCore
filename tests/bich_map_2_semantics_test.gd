extends Node


func _ready() -> void:
	var loaded := MapEditorLoadService.load_document("res://map_editor_workspace/bich_province/bich_province.editor.json")
	assert(loaded.ok, str(loaded.get("errors", [])))
	var document: Dictionary = loaded.document
	assert(document.layers.npc_points.size() == 5)
	assert(document.layers.monster_spawn.size() == 44)
	assert(document.layers.safe_area.size() == 1)
	var safe: Dictionary = document.layers.safe_area[0]
	assert(bool(safe.get("return_anchor", false)))
	assert(bool(safe.get("death_return_anchor", false)))
	assert(bool(safe.get("logout_return_anchor", false)))
	assert(bool(safe.get("blocks_monster_entry", false)))
	var names: Array[String] = []
	var raw_size: Array = document.design.design_size
	var design_size := Vector2i(int(raw_size[0]), int(raw_size[1]))
	for spawn: Dictionary in document.layers.monster_spawn:
		var name := str(spawn.get("display_name", "")); names.append(name)
		var tile: Array = spawn.get("tile", [0,0])
		assert(MapEditorCoordinate.contains_tile(Vector2(float(tile[0]), float(tile[1])), design_size), "spawn left the 80x80 map: %s" % name)
	for required: String in ["稻草人","多钩猫","钉耙猫","森林雪人","毒蜘蛛","蛤蟆"]:
		assert(required in names)
	assert("鸡" not in names and "鹿" not in names)
	var runtime_file := FileAccess.open("res://assets/data/runtime/map_editor/bich_province.runtime.json", FileAccess.READ)
	assert(runtime_file != null)
	var runtime: Variant = JSON.parse_string(runtime_file.get_as_text())
	assert(runtime is Dictionary and runtime.semantics.monster_spawn.size() == 44 and runtime.semantics.npc_points.size() == 5)
	print("BICH_MAP_2_SEMANTICS_PASS")
	get_tree().quit()
