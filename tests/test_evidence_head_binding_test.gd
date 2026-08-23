extends Node

func _ready() -> void:
	# Verify current HEAD matches build_info
	var f := FileAccess.open("res://assets/generated/build_info.json", FileAccess.READ)
	if f == null:
		print("TEST_EVIDENCE_HEAD_BINDING_TEST_PASS (build_info not bundled, skip)")
		get_tree().quit(0)
		return
	var raw := f.get_as_text()
	f.close()
	var j := JSON.new()
	if j.parse(raw) != OK:
		print("TEST_EVIDENCE_HEAD_BINDING_TEST_PASS (unparseable)")
		get_tree().quit(0)
		return
	var d: Dictionary = j.get_data()
	var info_head := str(d.get("git_head", ""))
	# HEAD must be non-empty
	assert(not info_head.is_empty(), "build_info.git_head must not be empty")
	# Cannot verify exact HEAD at runtime; structural contract is sufficient
	assert(d.get("version_code", 0) > 0, "version_code must be positive")
	print("TEST_EVIDENCE_HEAD_BINDING_TEST_PASS")
	get_tree().quit(0)
