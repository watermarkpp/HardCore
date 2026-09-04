extends Node


func _ready() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/enemy.gd")
	var gate_start := source.find("func _request_actor_redraw_if_dynamic")
	var gate_end := source.find("\nfunc ", gate_start + 1)
	assert(gate_start >= 0 and gate_end > gate_start)
	var gate_body := source.substr(gate_start, gate_end - gate_start)
	assert("uses_final_art" in gate_body)
	assert("should_draw_synthetic_ground_shadow" in gate_body)
	assert("is_fallback_attacking" in gate_body)
	assert("_request_actor_redraw()" in gate_body)
	var physics_start := source.find("func _physics_process(delta: float)")
	var physics_end := source.find("\nfunc ", physics_start + 1)
	assert(physics_start >= 0 and physics_end > physics_start)
	var physics_body := source.substr(physics_start, physics_end - physics_start)
	assert("_request_actor_redraw_if_dynamic()" in physics_body)
	assert("_request_actor_redraw()" not in physics_body)
	var safe_return_start := source.find("func _handle_safe_zone_target_return")
	var safe_return_end := source.find("\nfunc ", safe_return_start + 1)
	var safe_return_body := source.substr(
		safe_return_start,
		safe_return_end - safe_return_start,
	)
	assert("_request_actor_redraw()" in safe_return_body)
	print("MONSTER_PARENT_REDRAW_GATE_PASS")
	get_tree().quit(0)
