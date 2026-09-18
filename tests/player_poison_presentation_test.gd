extends Node

## Poison status presentation (R1). Verifies the poisoned state presents
## through the existing HUD status-flag strip lane (the same lane used by
## 魔法盾/隐身术/治愈术), with exactly one 中毒 flag merged across both poison
## sources, immediate expiry, death clearing and zero gameplay changes.
## The former green ground ring must be gone from player.gd while the existing
## paralysis (control) ring stays byte-identical.

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
		player_source.contains("draw_circle(Vector2(0, -4), 37.0, Color(0.42, 0.62, 1.0, 0.75), false, 4.0)"),
		"the existing paralysis control ring must stay byte-identical"
	)
	assert(
		player_source.contains("if control_time > 0.0:"),
		"the paralysis ring condition must stay"
	)
	assert(
		player_source.contains("func poison_status_remaining() -> float:"),
		"presentation accessor must exist"
	)
	var game_root_source := _read("res://scripts/game_root.gd")
	assert(
		game_root_source.contains("\"id\":\"poison\", \"skill\":\"施毒术\""),
		"poison must join the existing status strip lane via the 施毒术 icon entry"
	)

	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	var player: Node = game.player
	var hud: Node = game.hud
	assert(player != null and hud != null, "runtime boot must expose player and hud")
	player.set_physics_process(false)

	# --- Case A: legacy poison ----------------------------------------------
	player.poison_time = 0.0
	player._monster_source_poison.clear()
	player.apply_poison(3, 12.0)
	assert(player.poison_time > 0.0, "caseA legacy poison active")
	var entries_a: Array = game._status_buff_entries()
	var poison_a := _poison_entries(entries_a)
	assert(poison_a.size() == 1, "caseA exactly one poison flag, got %d" % poison_a.size())
	assert(int(ceil(float(poison_a[0].remaining))) == int(ceil(player.poison_time)), "caseA strip remaining mirrors legacy poison")
	assert(str(poison_a[0].skill) == "施毒术", "caseA strip icon source is the existing poison skill icon")

	# --- Case B: monster source poison ---------------------------------------
	player.poison_time = 0.0
	player._monster_source_poison.clear()
	assert(player.apply_monster_poison(2, 9.0, 2.5), "caseB monster poison applied")
	var entries_b: Array = game._status_buff_entries()
	var poison_b := _poison_entries(entries_b)
	assert(poison_b.size() == 1, "caseB exactly one poison flag for source poison")
	assert(
		is_equal_approx(float(poison_b[0].remaining), player._monster_source_poison.remaining_seconds),
		"caseB strip remaining mirrors monster source poison"
	)

	# --- Case C: both sources at once -> one flag ----------------------------
	player.apply_poison(3, 12.0)
	assert(player.poison_time > 0.0 and player._monster_source_poison.remaining_seconds > 0.0, "caseC both sources active")
	var entries_c: Array = game._status_buff_entries()
	var poison_c := _poison_entries(entries_c)
	assert(poison_c.size() == 1, "caseC both sources must render one merged flag")
	assert(
		is_equal_approx(float(poison_c[0].remaining), player.poison_status_remaining()),
		"caseC merged remaining equals maxf(legacy, source)"
	)
	assert(
		is_equal_approx(player.poison_status_remaining(), maxf(player.poison_time, player._monster_source_poison.remaining_seconds)),
		"caseC accessor semantics"
	)

	# --- Case D: one source ends, the other remains --------------------------
	player.poison_time = 0.0
	assert(player._monster_source_poison.remaining_seconds > 0.0, "caseD source poison remains")
	var entries_d: Array = game._status_buff_entries()
	assert(_poison_entries(entries_d).size() == 1, "caseD flag persists while one source remains")

	# --- Case E: all sources end ---------------------------------------------
	player.poison_time = 0.0
	player._monster_source_poison.clear()
	assert(is_zero_approx(player.poison_status_remaining()), "caseE no poison left")
	assert(_poison_entries(game._status_buff_entries()).is_empty(), "caseE flag removed immediately")

	# --- Strip rendering lifecycle through the real HUD lane ------------------
	hud.update_status_buffs([{"id": "poison", "skill": "施毒术", "remaining": 5.0, "started_at": 0}])
	var icon: TextureRect = hud._status_buff_icons.get("poison")
	assert(icon != null, "strip creates one icon for the poison entry")
	assert(icon.visible, "poison icon visible while poisoned")
	var seconds: Label = icon.get_node("Seconds")
	assert(seconds.text == "5", "poison icon carries the same countdown rule as the lane")
	var expected_texture: Texture2D = HUDSkillIconCatalog.SKILL_TEXTURES.get("施毒术")
	assert(expected_texture != null and icon.texture == expected_texture, "poison icon reuses the existing catalog texture")
	hud.update_status_buffs([])
	assert(not icon.visible, "poison icon hidden when the state ends")

	# --- Case F: death clears the flag immediately ----------------------------
	player.poison_time = 30.0
	player._monster_source_poison.clear()
	player.current_hp = 0
	player._dead = true
	assert(player.poison_status_remaining() > 0.0, "caseF gameplay poison is NOT cleared by presentation")
	assert(_poison_entries(game._status_buff_entries()).is_empty(), "caseF flag cleared on death without touching gameplay")
	player._dead = false
	player.current_hp = 100

	# --- Case G: paralysis presentation untouched -----------------------------
	player.control_time = 0.0
	player.apply_control(5.0)
	assert(player.control_time == 5.0, "caseG control state entry unchanged")
	var entries_g: Array = game._status_buff_entries()
	for entry: Dictionary in entries_g:
		assert(str(entry.get("id", "")) != "paralysis" and str(entry.get("id", "")) != "control", "caseG paralysis keeps out of the strip lane (unchanged behavior)")
	assert(player_source.contains("draw_circle(Vector2(0, -4), 37.0, Color(0.42, 0.62, 1.0, 0.75), false, 4.0)"), "caseG paralysis ring visual unchanged")

	game.queue_free()
	await get_tree().process_frame
	print("PLAYER_POISON_PRESENTATION_PASS: no ground ring, one strip flag, lifecycle, death clear, paralysis untouched")
	get_tree().quit(0)


func _read(res_path: String) -> String:
	var file := FileAccess.open(res_path, FileAccess.READ)
	assert(file != null, "cannot open %s" % res_path)
	return file.get_as_text()
