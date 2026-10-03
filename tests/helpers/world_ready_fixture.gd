extends RefCounted

## Read-only observation of the existing world/input owner; never force READY.
static func wait_for_world(owner: Node, game: Node, expected_map_id: int, label: String) -> void:
	var deadline_ms := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline_ms:
		if int(game.current_map_id) == expected_map_id and game.gameplay_input_is_enabled() \
			and not game._map_transition_in_progress and not game._world_bootstrap_in_progress and not _environment_retirement_pending(game):
			break
		await owner.get_tree().process_frame
	if int(game.current_map_id) != expected_map_id or not game.gameplay_input_is_enabled():
		print("WORLD_READY_FIXTURE " + JSON.stringify({"label":label,"expected_map_id":expected_map_id,
			"actual_map_id":game.current_map_id,"input":game.gameplay_input_gate_snapshot()}))
	assert(int(game.current_map_id) == expected_map_id, label + " requires the exact destination map")
	assert(not game._map_transition_in_progress and not game._world_bootstrap_in_progress, label + " requires a completed world transition")
	assert(game.gameplay_input_is_enabled(), label + " requires READY input")
	assert(not game.player.combat_transition_is_active(), label + " must leave combat isolation before acting")
	assert(not _environment_retirement_pending(game), label + " requires deferred old-world roots to finish retirement")

static func _environment_retirement_pending(game: Node) -> bool:
	for child: Node in game.background.get_children():
		if child.is_queued_for_deletion(): return true
	for child: Node in game.get_children():
		if bool(child.get_meta("editor_runtime_actor_occluder", false)) and child.is_queued_for_deletion(): return true
	return false
