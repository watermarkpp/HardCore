extends Node

## Poison/paralysis status presentation (R1.1 closure). The player presents
## both states the way the user required and the way monsters already do: as
## fixed-slot dots on the status marker row UNDER the overhead HP bar
## (PlayerStatusMarkerStrip). No ground rings for either state, no entry on the
## bottom HUD buff strip. Gameplay timers/values are only read, never changed.

const UIErrorFeedbackScript := preload("res://scripts/ui_error_feedback.gd")


func _ready() -> void:
	_run.call_deferred()


func _poison_entries(entries: Array) -> Array:
	var out: Array = []
	for entry: Dictionary in entries:
		if str(entry.get("id", "")) == "poison":
			out.append(entry)
	return out


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()

	# --- Static presentation contract ---------------------------------------
	var player_source := _read("res://scripts/player.gd")
	assert(
		not player_source.contains("Color(0.20, 0.85, 0.22, 0.70)"),
		"the green poison ground ring must be removed"
	)
	assert(
		not player_source.contains("draw_circle(Vector2(0, -4), 40.0"),
		"no ground ring drawing may remain for poison"
	)
	assert(
		not player_source.contains("draw_circle(Vector2(0, -4), 37.0, Color(0.42, 0.62, 1.0, 0.75), false, 4.0)"),
		"the paralysis ground ring must also be removed (R1.1): both states present under the HP bar"
	)
	assert(
		not player_source.contains("if control_time > 0.0:\n\t\tdraw_circle"),
		"no control-conditioned ground ring drawing may remain"
	)
	assert(
		player_source.contains("func poison_status_remaining() -> float:"),
		"presentation accessor must exist"
	)
	var health_bar_source := _read("res://scripts/player_health_bar.gd")
	assert(
		health_bar_source.contains("PlayerStatusMarkerStripScript.new()"),
		"the overhead health bar must attach the status marker strip"
	)
	assert(
		health_bar_source.contains("STATUS_MARKER_ROW_GAP"),
		"the marker row must sit below the bar by the documented gap"
	)
	var marker_source := _read("res://scripts/player_status_marker_strip.gd")
	assert(
		marker_source.contains("markers.append(\"paralysis\")") and marker_source.contains("markers.append(\"poison\")"),
		"the strip must expose the fixed-order marker contract"
	)
	assert(
		marker_source.contains("MARKER_DOT_RADIUS := 3.0") and marker_source.contains("MARKER_SLOT_OFFSET_X := 5.0"),
		"marker geometry mirrors the established overhead dot idiom"
	)
	var game_root_source := _read("res://scripts/game_root.gd")
	assert(
		not game_root_source.contains("\"id\":\"poison\""),
		"poison must not surface on the bottom HUD buff strip"
	)

	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	var player: Node = game.player
	var hud: Node = game.hud
	assert(player != null and hud != null, "runtime boot must expose player and hud")
	player.set_physics_process(false)
	var health_bar: Node = player.health_bar
	assert(health_bar != null, "player exposes its overhead health bar")
	var marker_strip: Node = health_bar.status_marker_strip
	assert(marker_strip != null and marker_strip.name == "PlayerStatusMarkerStrip", "health bar owns the status marker strip")
	assert(
		marker_strip.position == health_bar.layout_snapshot()["status_marker_strip_position"],
		"marker row sits directly below the bar at the documented offset"
	)

	# --- Case A: legacy poison -> single fixed-slot poison marker ------------
	player.poison_time = 0.0
	player._monster_source_poison.clear()
	player.apply_poison(3, 12.0)
	assert(player.poison_time > 0.0, "caseA legacy poison active")
	var markers_a: Array[String] = marker_strip.active_status_markers()
	assert(_join(markers_a) == "poison", "caseA exactly the poison marker, got [%s]" % _join(markers_a))
	assert(_poison_entries(game._status_buff_entries()).is_empty(), "caseA no bottom-strip entry for poison")

	# --- Case B: monster source poison ----------------------------------------
	player.poison_time = 0.0
	player._monster_source_poison.clear()
	assert(player.apply_monster_poison(2, 9.0, 2.5), "caseB monster poison applied")
	var markers_b: Array[String] = marker_strip.active_status_markers()
	assert(_join(markers_b) == "poison", "caseB one poison marker for source poison, got [%s]" % _join(markers_b))

	# --- Case C: both sources at once -> still one poison marker --------------
	player.apply_poison(3, 12.0)
	assert(player.poison_time > 0.0 and player._monster_source_poison.remaining_seconds > 0.0, "caseC both sources active")
	var markers_c: Array[String] = marker_strip.active_status_markers()
	assert(_join(markers_c) == "poison", "caseC both sources merge into one poison marker, got [%s]" % _join(markers_c))
	assert(
		is_equal_approx(player.poison_status_remaining(), maxf(player.poison_time, player._monster_source_poison.remaining_seconds)),
		"caseC accessor semantics"
	)

	# --- Case D: one source ends, the other remains ---------------------------
	player.poison_time = 0.0
	assert(player._monster_source_poison.remaining_seconds > 0.0, "caseD source poison remains")
	assert(_join(marker_strip.active_status_markers()) == "poison", "caseD marker persists while one source remains")

	# --- Case E: all sources end -----------------------------------------------
	player.poison_time = 0.0
	player._monster_source_poison.clear()
	assert(is_zero_approx(player.poison_status_remaining()), "caseE no poison left")
	assert(marker_strip.active_status_markers().is_empty(), "caseE marker removed immediately")

	# --- Case F: death clears the poison marker, gameplay poison untouched ----
	player.poison_time = 30.0
	player._monster_source_poison.clear()
	player.current_hp = 0
	player._dead = true
	assert(player.poison_status_remaining() > 0.0, "caseF gameplay poison is NOT cleared by presentation")
	assert(marker_strip.active_status_markers().is_empty(), "caseF marker cleared on death without touching gameplay")
	player._dead = false
	player.current_hp = 100

	# --- Case G: paralysis -> its own fixed slot, still no ground ring --------
	player.poison_time = 0.0
	player._monster_source_poison.clear()
	player.control_time = 0.0
	player.apply_control(5.0)
	assert(player.control_time == 5.0, "caseG control state entry unchanged")
	var markers_g: Array[String] = marker_strip.active_status_markers()
	assert(_join(markers_g) == "paralysis", "caseG paralysis shows its own marker, got [%s]" % _join(markers_g))
	assert(_poison_entries(game._status_buff_entries()).is_empty(), "caseG no strip entry for paralysis either")

	# --- Case H: paralysis + poison -> fixed slot order ------------------------
	player.apply_poison(3, 12.0)
	assert(player.control_time > 0.0 and player.poison_time > 0.0, "caseH both statuses active")
	var markers_h: Array[String] = marker_strip.active_status_markers()
	assert(_join(markers_h) == "paralysis,poison", "caseH fixed order: paralysis slot first, poison slot second, got [%s]" % _join(markers_h))
	# Slots stay fixed: the paralysis dot never re-centers when poison ends.
	player.poison_time = 0.0
	player._monster_source_poison.clear()
	var markers_h2: Array[String] = marker_strip.active_status_markers()
	assert(_join(markers_h2) == "paralysis", "caseH paralysis keeps its own slot after poison ends")
	assert(
		marker_strip.marker_slot_center("paralysis").x < 0.0 and marker_strip.marker_slot_center("poison").x > 0.0,
		"caseH fixed slot geometry: paralysis left, poison right"
	)

	# --- Case I: clean state ----------------------------------------------------
	player.control_time = 0.0
	assert(marker_strip.active_status_markers().is_empty(), "caseI no markers in the clean state")
	assert(_poison_entries(game._status_buff_entries()).is_empty(), "caseI no strip entries for either state")

	game.queue_free()
	await get_tree().process_frame
	print("PLAYER_POISON_PRESENTATION_PASS: no ground rings, fixed-slot markers under the HP bar, lifecycle, death clear")
	get_tree().quit(0)


func _join(markers: Array[String]) -> String:
	return ",".join(markers)


func _read(res_path: String) -> String:
	var file := FileAccess.open(res_path, FileAccess.READ)
	assert(file != null, "cannot open %s" % res_path)
	return file.get_as_text()
