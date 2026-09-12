extends Node

func _ready() -> void:
	var failures: Array[String] = []
	var required := {
		"StyleBoxTexture": ["get_expand_margin"],
		"StyleBoxFlat": ["get_expand_margin"],
		"Control": ["is_inside_tree", "has_focus", "release_focus", "get_transform"],
	}
	for type_name: String in required:
		for method_name: String in required[type_name]:
			if not ClassDB.class_has_method(type_name, method_name):
				failures.append(type_name + "." + method_name)
	var out := {
		"schema": "hc.r31.engine_api.v1", "engine": Engine.get_version_info(),
		"display_server": DisplayServer.get_name(), "missing": failures,
		"base_stylebox_public_draw_rect": ClassDB.class_has_method("StyleBox", "get_draw_rect"),
		"scope": "API probe only; not visual, transaction or performance acceptance",
	}
	var file := FileAccess.open("user://r31_engine_api.json", FileAccess.WRITE)
	if file == null:
		failures.append("EVIDENCE_WRITE_FAILED")
	else:
		file.store_string(JSON.stringify(out, "  "))
		file.close()
	print("R31_ENGINE_API_", "PASS" if failures.is_empty() else "FAIL", " ", JSON.stringify(out))
	get_tree().quit(0 if failures.is_empty() else 1)
