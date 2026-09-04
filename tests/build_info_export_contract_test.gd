extends Node

func _ready() -> void:
	var f := FileAccess.open("user://../build_info.json", FileAccess.READ)
	if f == null:
		f = FileAccess.open("res://assets/generated/build_info.json", FileAccess.READ)
	if f == null:
		print("BUILD_INFO_EXPORT_CONTRACT_TEST_PASS (no build_info, skipping contract)")
		get_tree().quit(0)
		return
	var raw := f.get_as_text()
	f.close()
	var j := JSON.new()
	assert(j.parse(raw) == OK, "build_info.json must be valid JSON")
	var d: Dictionary = j.get_data()
	assert(not d.get("git_head", "").is_empty(), "git_head must be set")
	assert(not d.get("git_short_head", "").is_empty(), "git_short_head must be set")
	assert(d.get("version_code", 0) > 0, "version_code must be positive")
	assert(not d.get("version_name", "").is_empty(), "version_name must be set")
	assert(d.has("git_dirty"), "git_dirty field must exist")
	assert(not d.get("build_type", "").is_empty(), "build_type must be set")
	print("BUILD_INFO_EXPORT_CONTRACT_TEST_PASS")
	get_tree().quit(0)
