extends Node


func _ready() -> void:
	var loaded := MapEditorLoadService.load_document("res://map_editor_workspace/bich_province/bich_province.editor.json")
	assert(loaded.ok, str(loaded.get("errors", [])))
	var document: Dictionary = loaded.document
	assert(document.layers.npc_points.size() == 8)
	assert(document.layers.monster_spawn.size() == 25)
	assert(document.layers.safe_area.size() == 1)
	var safe: Dictionary = document.layers.safe_area[0]
	assert(bool(safe.get("return_anchor", false)))
	assert(bool(safe.get("forced_return_on_exit", false)))
	assert(bool(safe.get("forced_return_on_process_loss", false)))
	var names: Array[String] = []
	for spawn: Dictionary in document.layers.monster_spawn:
		var name := str(spawn.get("display_name", "")); names.append(name)
		var tile: Array = spawn.get("tile", [0,0])
		assert(not Rect2i(88,88,80,80).has_point(Vector2i(int(tile[0]),int(tile[1]))), "spawn entered city buffer: %s" % name)
	for required: String in ["稻草人","多钩猫","钉耙猫","半兽人","森林雪人","食人花"]:
		assert(required in names)
	assert("鸡" not in names and "鹿" not in names)
	var runtime_file := FileAccess.open("res://assets/data/runtime/map_editor/bich_province.runtime.json", FileAccess.READ)
	assert(runtime_file != null)
	var runtime: Variant = JSON.parse_string(runtime_file.get_as_text())
	assert(runtime is Dictionary and runtime.semantics.monster_spawn.size() == 25 and runtime.semantics.npc_points.size() == 8)
	print("BICH_MAP_2_SEMANTICS_PASS")
	get_tree().quit()
