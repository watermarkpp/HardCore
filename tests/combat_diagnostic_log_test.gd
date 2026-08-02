extends Node

const DiagnosticLog := preload("res://scripts/layers/runtime/combat_diagnostic_log.gd")


func _ready() -> void:
	var previous_enabled := DiagnosticLog.enabled
	DiagnosticLog.enabled = false
	DiagnosticLog.clear_recent_events()
	var event := DiagnosticLog.record({
		"event": "test_attack_release",
		"origin_screen_px": Vector2(32.5, -16.25),
		"direction_grid_step": Vector2i(1, -1),
		"nested": {"target_screen_px": Vector2(-4.0, 8.0)},
		"candidates": [{"ground_delta_gu": Vector2(1.25, 0.5)}],
	})
	assert(str(event.get("schema", "")) == DiagnosticLog.SCHEMA_ID)
	assert(str(event.get("contract_id", "")) == DiagnosticLog.CONTRACT_ID)
	assert(event.get("origin_screen_px", {}) == {"x": 32.5, "y": -16.25})
	assert(event.get("direction_grid_step", {}) == {"x": 1, "y": -1})
	assert(
		(event.get("nested", {}) as Dictionary).get("target_screen_px", {})
		== {"x": -4.0, "y": 8.0}
	)
	assert(
		((event.get("candidates", []) as Array)[0] as Dictionary).get("ground_delta_gu", {})
		== {"x": 1.25, "y": 0.5}
	)
	assert(JSON.stringify(event).contains("test_attack_release"))
	assert(DiagnosticLog.recent_events().size() == 1)
	DiagnosticLog.clear_recent_events()
	DiagnosticLog.enabled = previous_enabled
	print("COMBAT_DIAGNOSTIC_LOG_PASS：运行时近战诊断事件可JSON序列化且不改变战斗状态")
	get_tree().quit(0)
