extends Node

# Observe the real production implementation; every spy calls super.
class StatsSpy:
	extends "res://scripts/inventory_panel.gd"
	var stats_calls := 0
	var text_build_calls := 0
	var attribute_layout_calls := 0
	var stats_elapsed_usec := 0
	var text_elapsed_usec := 0
	var layout_elapsed_usec := 0

	func _refresh_character_stats() -> void:
		stats_calls += 1
		var started := Time.get_ticks_usec()
		super._refresh_character_stats()
		stats_elapsed_usec += Time.get_ticks_usec() - started

	func _character_stats_text(stats: Dictionary) -> String:
		text_build_calls += 1
		var started := Time.get_ticks_usec()
		var result := super._character_stats_text(stats)
		text_elapsed_usec += Time.get_ticks_usec() - started
		return result

	func _layout_character_attributes() -> void:
		attribute_layout_calls += 1
		var started := Time.get_ticks_usec()
		super._layout_character_attributes()
		layout_elapsed_usec += Time.get_ticks_usec() - started

	func reset_observations() -> void:
		stats_calls = 0
		text_build_calls = 0
		attribute_layout_calls = 0
		stats_elapsed_usec = 0
		text_elapsed_usec = 0
		layout_elapsed_usec = 0


var _panel: StatsSpy
var _failures: Array[String] = []
var _checks := 0
var _fixed_geometry: Dictionary
var _original_font_size := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var previous_test_mode := PlayerState.test_mode
	PlayerState.test_mode = true
	assert(GameData.ensure_loaded(), "stats fixture requires the real catalog")
	PlayerState.reset_progress(false)
	_set_profile(10, "统计初始")
	_panel = StatsSpy.new()
	_panel.hide()
	add_child(_panel)
	await _panel.wait_until_runtime_ready()
	# Let the existing three-pass layout contract and deferred grid builder settle.
	await _frames(8)
	_panel.show()
	await _frames(3)
	_expect_latest("initial visible panel")
	_fixed_geometry = _container_geometry()
	_original_font_size = _panel.equipment_stats_label.get_theme_font_size("normal_font_size")
	_expect_presentation("initial presentation")
	_panel.hide()
	await _frames(2)

	# A hidden burst must neither generate RichText nor measure/recenter it.
	_panel.reset_observations()
	var before := _content()
	var geometry_before := _stats_geometry()
	var bag_refresh_before := _panel._refresh_execution_count
	var emit_usec := _emit_burst("隐藏", 11, 33)
	_expect_counts(0, "hidden burst immediately")
	_expect(_content() == before, "hidden burst rewrote identity/stats content immediately")
	await _frames(2)
	_record("hidden_100", 100, emit_usec, bag_refresh_before)
	_expect_counts(0, "hidden burst after deferred work")
	_expect(_content() == before, "hidden burst generated new identity/stats content")
	_expect(_stats_geometry() == geometry_before, "hidden burst changed attribute geometry")
	_expect(_panel._refresh_execution_count == bag_refresh_before, "hidden profile signals rebuilt the bag")

	# First show must synchronously expose the latest values, once, without a bag rebuild.
	_panel.reset_observations()
	var show_started := Time.get_ticks_usec()
	_panel.show()
	var show_usec := Time.get_ticks_usec() - show_started
	_expect_latest("first show after hidden burst")
	await _frames(2)
	_record("show_latest", 0, show_usec, bag_refresh_before)
	_expect_counts(1, "first show restores pending stats once")
	_expect(_panel._refresh_execution_count == bag_refresh_before, "stats-only show rebuilt the bag")
	_expect_presentation("show after hidden burst")

	# Visible signals may schedule one stats refresh, but must not perform 100 inline refreshes.
	_panel.reset_observations()
	before = _content()
	bag_refresh_before = _panel._refresh_execution_count
	emit_usec = _emit_burst("可见", 12, 44)
	_expect_counts(0, "visible same-frame burst before deferred flush")
	_expect(_content() == before, "visible burst did not defer/coalesce RichText updates")
	await _frames(2)
	_record("visible_100", 100, emit_usec, bag_refresh_before)
	_expect_counts(1, "visible burst coalesces to one stats refresh")
	_expect_latest("visible burst latest data")
	_expect(_panel._refresh_execution_count == bag_refresh_before, "visible stats-only signals rebuilt the bag")
	_expect_presentation("visible burst presentation")

	# A legitimate complete refresh owns the pending stats work and consumes it.
	_panel.reset_observations()
	bag_refresh_before = _panel._refresh_execution_count
	_set_profile(45, "完整刷新消费待处理统计")
	PlayerState.profile_changed.emit()
	_panel.refresh()
	_expect_latest("full refresh current data")
	await _frames(2)
	_record("full_refresh_consumes_pending", 1, 0, bag_refresh_before)
	_expect_counts(1, "full refresh must consume queued stats without a second refresh")
	_expect(_panel._refresh_execution_count == bag_refresh_before + 1, "explicit full refresh executed more than once")
	_expect_presentation("full refresh presentation")

	# Closing before a deferred flush must preserve dirty data until the next show.
	_panel.reset_observations()
	before = _content()
	bag_refresh_before = _panel._refresh_execution_count
	_set_profile(46, "关闭再开最新统计")
	PlayerState.profile_changed.emit()
	_panel.hide()
	await _frames(2)
	_record("close_before_flush", 1, 0, bag_refresh_before)
	_expect_counts(0, "close-before-flush must leave hidden stats dormant")
	_expect(_content() == before, "close-before-flush rewrote hidden stats content")
	_panel.reset_observations()
	_panel.show()
	_expect_latest("reopen after a cancelled visible flush")
	await _frames(2)
	_record("reopen_latest", 0, 0, bag_refresh_before)
	_expect_counts(1, "reopen must consume retained dirty stats exactly once")
	_expect(_panel._refresh_execution_count == bag_refresh_before, "reopen stats-only recovery rebuilt the bag")
	_expect_presentation("reopen presentation")

	_panel.queue_free()
	await _frames(2)
	PlayerState.test_mode = previous_test_mode
	for failure: String in _failures:
		push_error("HIDDEN_INVENTORY_STATS_REFRESH " + failure)
	print("HIDDEN_INVENTORY_STATS_REFRESH_%s checks=%d failures=%d" % [
		"PASS" if _failures.is_empty() else "FAIL", _checks, _failures.size(),
	])
	get_tree().quit(0 if _failures.is_empty() else 1)


func _set_profile(next_level: int, next_name: String) -> void:
	PlayerState.level = next_level
	PlayerState.character_name = next_name
	# Use production derived statistics, rather than replacing the display/model with a mock.
	PlayerState.recalculate_stats(false)


func _emit_burst(label: String, first_level: int, final_level: int) -> int:
	var emit_usec := 0
	for index in 100:
		_set_profile(final_level if index == 99 else first_level + index % 20, "%s_%03d" % [label, index])
		var started := Time.get_ticks_usec()
		PlayerState.profile_changed.emit()
		emit_usec += Time.get_ticks_usec() - started
	return emit_usec


func _content() -> Dictionary:
	return {
		"stats_content": _panel.equipment_stats_label.text,
		"stats_plain": _panel.equipment_stats_label.get_parsed_text(),
		"identity_content": _panel.character_identity_label.text,
		"identity_plain": _panel.character_identity_label.get_parsed_text(),
	}


func _stats_geometry() -> Dictionary:
	return {
		"stats_position": _panel.equipment_stats_label.position,
		"stats_size": _panel.equipment_stats_label.size,
		"identity_position": _panel.character_identity_label.position,
		"identity_size": _panel.character_identity_label.size,
		"font_size": _panel.equipment_stats_label.get_theme_font_size("normal_font_size"),
	}


func _container_geometry() -> Dictionary:
	var geometry := {"panel_size": _panel.size, "columns": _panel.item_grid.columns}
	for path: String in ["AttributePanel", "AttributePanel/AttributePanelDecoration", "AttributePanel/AttributePanelDecoration/AttributePanelFrame", "BagPanel", "BagPanel/InventoryScroll/ItemGrid"]:
		var control := _panel.get_node(path) as Control
		geometry[path] = Rect2(control.position, control.size)
	return geometry


func _expect_presentation(label: String) -> void:
	_expect(_panel._bag_cells.size() == 100 and _panel.item_grid.get_child_count() == 100, label + ": lost the 100-slot contract")
	_expect(_container_geometry() == _fixed_geometry, label + ": changed approved container geometry")
	_expect(_panel.equipment_stats_label.get_theme_font_size("normal_font_size") == _original_font_size, label + ": changed the approved stats font size")


func _expect_latest(label: String) -> void:
	var content := _content()
	var identity := str(content["identity_plain"])
	var stats_content := str(content["stats_content"])
	var plain := str(content["stats_plain"])
	var stats: Dictionary = PlayerState.computed_stats
	_expect(identity.contains(PlayerState.character_name), label + ": stale character identity")
	_expect(identity.contains("等级：%d" % PlayerState.level), label + ": stale level")
	_expect(not stats_content.is_empty(), label + ": empty RichText stats content")
	_expect(plain.contains("生命 %d　魔法值 %d" % [int(stats["max_hp"]), int(stats["max_mp"])]), label + ": stale HP/MP")
	_expect(plain.contains("攻击 %d-%d" % [int(stats["attack_min"]), int(stats["attack_max"])]), label + ": stale attack range")
	_expect(plain.contains("防御 %d-%d　魔防 %d-%d" % [int(stats["defense_min"]), int(stats["defense_max"]), int(stats["magic_defense_min"]), int(stats["magic_defense_max"])]), label + ": stale AC/MAC ranges")
	_expect(plain.contains("穿戴重量 %d/%d" % [int(stats["wear_weight"]), int(stats["max_wear_weight"])]), label + ": stale wear capacity")


func _expect_counts(expected: int, label: String) -> void:
	_expect(_panel.stats_calls == expected, "%s: stats calls expected %d got %d" % [label, expected, _panel.stats_calls])
	_expect(_panel.text_build_calls == expected, "%s: text builds expected %d got %d" % [label, expected, _panel.text_build_calls])
	_expect(_panel.attribute_layout_calls == expected, "%s: attribute layouts expected %d got %d" % [label, expected, _panel.attribute_layout_calls])


func _record(phase: String, signal_count: int, emit_or_show_usec: int, bag_refresh_before: int) -> void:
	# stats_usec includes its nested text/layout work; do not sum the nested timings.
	# Time is diagnostic, never a machine-dependent PASS threshold.
	print("HIDDEN_INVENTORY_STATS_METRIC " + JSON.stringify({
		"phase": phase, "signals": signal_count, "dispatch_or_show_usec": emit_or_show_usec,
		"stats_calls": _panel.stats_calls, "text_build_calls": _panel.text_build_calls,
		"layout_calls": _panel.attribute_layout_calls, "stats_usec": _panel.stats_elapsed_usec,
		"text_usec": _panel.text_elapsed_usec, "layout_usec": _panel.layout_elapsed_usec,
		"full_refresh_delta": _panel._refresh_execution_count - bag_refresh_before,
		"stats_content_length": _panel.equipment_stats_label.text.length(),
		"latest_level": PlayerState.level, "latest_name": PlayerState.character_name,
	}))


func _expect(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(message)


func _frames(count: int) -> void:
	for _frame in count:
		await get_tree().process_frame
