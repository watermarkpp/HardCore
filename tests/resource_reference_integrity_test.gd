extends Node

func _ready() -> void:
	# Verify key BLOCKER resources are loadable at runtime
	var files := [
		"res://project.godot",
		"res://assets/data/skill_visual_profiles.json",
		"res://assets/data/caster_skill_visuals.json",
		"res://scripts/caster_skill_visual_factory.gd",
		"res://scripts/caster_skill_runtime.gd",
		"res://scripts/caster_skill_beam_visual_effect.gd",
		"res://scripts/caster_skill_sky_strike_visual_effect.gd",
		"res://scripts/fire_wall_field_controller.gd",
		"res://scripts/runtime_diagnostics.gd",
	]
	var missing: Array[String] = []
	for path: String in files:
		if not FileAccess.file_exists(path):
			missing.append(path)
	assert(missing.is_empty(), "BLOCKER resources missing: " + str(missing))
	print("RESOURCE_REFERENCE_INTEGRITY_TEST_PASS")
	get_tree().quit(0)
