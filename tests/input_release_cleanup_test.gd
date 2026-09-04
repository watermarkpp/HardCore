extends Node

# Verify the structural contract:
# B-class handlers (release/cancel) must never have a gate at the top
# that would skip their cleanup.
func _ready() -> void:
	const GameRoot := preload("res://scripts/game_root.gd")

	# Read game_root source to verify B-class handler structure
	var f := FileAccess.open("res://scripts/game_root.gd", FileAccess.READ)
	var src := f.get_as_text()
	f.close()

	var b_handlers := [
		"_on_mobile_attack_input_ended",
		"_on_mobile_attack_input_cancelled",
		"_on_skill_input_ended",
		"_on_skill_input_cancelled",
		"_on_mobile_attack_released",
	]
	for h in b_handlers:
		# Find the function and check its first non-comment body line
		var idx := src.find("func " + h + "(")
		assert(idx != -1, h + " function must exist")
		var after_sig := src.substr(idx)
		var nl := after_sig.find("\n")
		assert(nl != -1, h + " must have body")
		var body_start := src.substr(idx + nl + 1, 200)
		# The first body line must NOT be "if not gameplay_input_is_enabled"
		var lines := body_start.strip_edges().split("\n")
		var first_code := ""
		for l in lines:
			var t := l.strip_edges()
			if t != "" and not t.begins_with("#"):
				first_code = t
				break
		assert(not first_code.begins_with("if not gameplay_input_is_enabled"),
			h + " must do cleanup before gate check")

	# Verify GameRoot instantiates
	var root := GameRoot.new()
	add_child(root)
	assert(root.has_method("gameplay_input_is_enabled"))
	root.free()

	print("INPUT_RELEASE_CLEANUP_TEST_PASS")
	get_tree().quit(0)
