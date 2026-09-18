extends Node

## R11: WALL_RENDER_FORCE_LEGACY must be a debug-build-only measurement
## hook. The gate function must exist on WorldBackground and evaluate to
## OS.is_debug_build() for the running binary - true for the dev/test
## editor binary (so R8/R9 A/B measurements keep working), and by
## construction false for release export templates where is_debug_build()
## is false. Also pins that an env-forced boot marks the wall mode LEGACY
## with an explicit fallback reason, which a plain LEGACY map never sets.
## Usage: godot --headless --path . res://tests/wall_render_force_legacy_gate_test.tscn

const WorldBackgroundScript := preload("res://scripts/world_background.gd")


func _ready() -> void:
	var failures := PackedStringArray()
	# The gate must mirror the build type - this pins the R11 contract so
	# removing the guard (or inverting it) fails this test.
	var allowed: bool = WorldBackgroundScript.wall_render_legacy_force_allowed()
	if allowed != OS.is_debug_build():
		failures.append(
			"gate must equal OS.is_debug_build() (got %s, debug=%s)" % [
				str(allowed), str(OS.is_debug_build()),
			]
		)
	# In the dev/test binary the hook stays armed so the formal A/B runs
	# (R8 capture, R9 matrix) can still force the legacy path.
	if OS.is_debug_build() and not allowed:
		failures.append("dev binary lost the A/B measurement hook")
	# Boot the production game with the env var engaged: even the plan-less
	# initial world must carry the explicit forced-legacy fallback reason,
	# which a normal LEGACY map never sets.
	OS.set_environment("WALL_RENDER_FORCE_LEGACY", "1")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	var deadline := Time.get_ticks_msec() + 30000
	while (
		not bool(main.gameplay_input_is_enabled())
		and Time.get_ticks_msec() < deadline
	):
		await get_tree().create_timer(0.016, true).timeout
	await get_tree().create_timer(0.3, true).timeout
	var stats: Dictionary = main.background.wall_render_stats()
	OS.set_environment("WALL_RENDER_FORCE_LEGACY", "0")
	if str(stats.get("wall_render_mode", "?")) != "LEGACY":
		failures.append(
			"env-forced run must read LEGACY (got %s)" % str(
				stats.get("wall_render_mode", "?")
			)
		)
	if str(stats.get("wall_render_fallback_reason", "")).is_empty():
		failures.append("env-forced run must record an explicit fallback reason")
	if failures.is_empty():
		print("WALL_RENDER_FORCE_LEGACY_GATE_TEST_PASS")
		get_tree().quit(0)
	else:
		for failure: String in failures:
			print("R11_FAIL ", failure)
		print("WALL_RENDER_FORCE_LEGACY_GATE_TEST_FAIL failures=%d" % failures.size())
		get_tree().quit(1)
