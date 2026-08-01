extends Node

const DiagnosticLog := preload("res://scripts/layers/runtime/combat_diagnostic_log.gd")


func _ready() -> void:
	var previous_enabled := DiagnosticLog.enabled
	DiagnosticLog.enabled = false
	DiagnosticLog.clear_recent_events()
	var event := DiagnosticLog.record({
		"event": "test_attack_release",
		"origin_world": Vector2(32.5, -16.25),
		"direction_tile": Vector2i(1, -1),
		"nested": {"target_world": Vector2(-4.0, 8.0)},
		"candidates": [{"tile_delta": Vector2(1.25, 0.5)}],
	})
	assert(str(event.get("schema", "")) == DiagnosticLog.SCHEMA_ID)
	assert(str(event.get("contract_id", "")) == DiagnosticLog.CONTRACT_ID)
	assert(event.get("origin_world", {}) == {"x": 32.5, "y": -16.25})
	assert(event.get("direction_tile", {}) == {"x": 1, "y": -1})
	assert(
		(event.get("nested", {}) as Dictionary).get("target_world", {})
		== {"x": -4.0, "y": 8.0}
	)
	assert(
		((event.get("candidates", []) as Array)[0] as Dictionary).get("tile_delta", {})
		== {"x": 1.25, "y": 0.5}
	)
	assert(JSON.stringify(event).contains("test_attack_release"))
	assert(DiagnosticLog.recent_events().size() == 1)
	DiagnosticLog.clear_recent_events()
	DiagnosticLog.enabled = previous_enabled
	print("COMBAT_DIAGNOSTIC_LOG_PASS：运行时近战诊断事件可JSON序列化且不改变战斗状态")
	get_tree().quit(0)
