extends Node

## WALL-P1R R8 visual spot-check capture (WINDOWED - real GPU render).
## Boots the real game, travels to one map, waits for the world to
## settle, then saves one viewport screenshot. Run twice per map
## (mode=legacy with WALL_RENDER_FORCE_LEGACY=1, mode=optimized) and
## feed the two PNGs to tools/wall_pixel_diff.gd.
## Usage:
##   godot --path . res://tools/wall_render_visual_capture.gd -- \
##       map=<map_key> mode=legacy|optimized out=<abs or res path>

const AUTHORITY := preload("res://tools/wall_rollout_authority.gd")
const R6_HELPER := preload("res://tests/wall_render_rollout_smoke.gd")


func _log(line: String) -> void:
	print(line)


func _ready() -> void:
	var map_key := ""
	var mode := "optimized"
	var out_path := ""
	var hide_dynamic := false
	for arg: String in OS.get_cmdline_user_args():
		var pair := arg.split("=", true, 1)
		if pair.size() != 2:
			continue
		match pair[0]:
			"map": map_key = pair[1]
			"mode": mode = pair[1]
			"out": out_path = pair[1]
			"hide_dynamic": hide_dynamic = pair[1] == "1"
	if map_key.is_empty() or out_path.is_empty():
		printerr("VISUAL_CAPTURE missing map/out")
		get_tree().quit(1)
		return
	if mode == "legacy":
		# Must be set before the scene tree registers plan resources; the
		# consumer reads it once per map arrival.
		OS.set_environment("WALL_RENDER_FORCE_LEGACY", "1")
	PlayerState.test_mode = true
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	var deadline := Time.get_ticks_msec() + 30000
	while (
		not bool(game.gameplay_input_is_enabled())
		and Time.get_ticks_msec() < deadline
	):
		await get_tree().create_timer(0.05, true).timeout
	game._monster_prefetch_enabled = false
	var authority := AUTHORITY.classify()
	var map_id := 0
	for row: Dictionary in authority["rows"]:
		if str(row["map_key"]) == map_key:
			map_id = int(row["map_id"])
	if map_id == 0:
		printerr("VISUAL_CAPTURE unknown map %s" % map_key)
		get_tree().quit(1)
		return
	if int(game.current_map_id) != map_id:
		var op := Callable(game, "_travel_to_map_immediate").bind(map_id)
		var travel_ok := false
		var lock_deadline := Time.get_ticks_msec() + 20000
		while (
			not bool(game.gameplay_input_is_enabled())
			and Time.get_ticks_msec() < lock_deadline
		):
			await get_tree().create_timer(0.05, true).timeout
		if game._begin_map_transition(op, map_id):
			travel_ok = true
			var hop := Time.get_ticks_msec() + 10000
			while (
				not bool(game._map_transition_in_progress)
				and Time.get_ticks_msec() < hop
			):
				await get_tree().create_timer(0.05, true).timeout
			game.hud.loading_transition_covered.emit({
				"contract_id": "ui.loading.transition.v1",
				"transition_id": game._active_map_transition_id,
			})
			while bool(game._map_transition_in_progress):
				await get_tree().create_timer(0.05, true).timeout
		if not travel_ok:
			printerr("VISUAL_CAPTURE travel failed")
			get_tree().quit(1)
			return
	var idle := Time.get_ticks_msec() + 30000
	while (
		bool(game._world_bootstrap_in_progress)
		and Time.get_ticks_msec() < idle
	):
		await get_tree().create_timer(0.05, true).timeout
	# Let per-map ambient animation start but keep the window short so
	# entity drift stays bounded; the diff tool reports the ratio.
	await get_tree().create_timer(2.0, true).timeout
	var stats: Dictionary = game.background.wall_render_stats()
	if hide_dynamic:
		# P1-1 wall-only masked capture: hide monsters (zone_content
		# group), the player (and its skill FX), the HUD (and its floating
		# text) so the two modes are compared on the background/wall
		# composites and chunks alone. Particles attached to hidden
		# entities go with them.
		for enemy in get_tree().get_nodes_in_group("zone_content"):
			if enemy is CanvasItem:
				enemy.visible = false
		if is_instance_valid(game.player) and game.player is CanvasItem:
			game.player.visible = false
		if is_instance_valid(game.hud) and game.hud is CanvasItem:
			game.hud.visible = false
		await get_tree().create_timer(0.2, true).timeout
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(out_path.get_base_dir())
	)
	image.save_png(ProjectSettings.globalize_path(out_path))
	print("VISUAL_CAPTURE %s mode=%s saved=%s wall_mode=%s hidden_dynamic=%s" % [
		map_key, mode, out_path, str(stats["wall_render_mode"]),
		str(hide_dynamic),
	])
	get_tree().quit(0)
