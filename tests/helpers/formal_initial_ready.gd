extends RefCounted

## Formal initial-READY completion contract, migrated 2026-10-06 from the
## stale two-frame / five-second fixture assumptions (Pro-reviewed verdict:
## fixture contract stale; no production birth defect was proven by them).
##
## The initial world counts as READY only when ALL of the following hold:
##   1. the current runtime map is the service home runtime map;
##   2. WorldBootstrapCoordinator.Stage.READY;
##   3. no map transition is in progress;
##   4. gameplay input is enabled.
##
## The production bounded bootstrap window (INITIAL_WORLD_BOOTSTRAP_TIMEOUT_MSEC
## = 60000 in scripts/game_root.gd) is used ONLY as the fail-safe ceiling of
## this wait. It is explicitly NOT a startup-performance PASS threshold:
## startup performance stays OPEN / PRODUCT SLA MISSING.

const READY_FAILSAFE_CEILING_MSEC := 60000
const CoordinatorScript := preload("res://scripts/world_bootstrap_coordinator.gd")


static func initial_ready_reached(game: Node) -> bool:
	var home_map_id: int = GameData.service_runtime_map_id(0)
	if int(game.get("current_map_id")) != home_map_id:
		return false
	var coordinator: Variant = game.get("_world_bootstrap_coordinator")
	if coordinator == null:
		return false
	if int(coordinator.get("stage")) != int(CoordinatorScript.Stage.READY):
		return false
	if bool(game.get("_map_transition_in_progress")):
		return false
	return bool(game.call("gameplay_input_is_enabled"))


static func wait_for_initial_ready(owner: Node, game: Node, label: String) -> void:
	var deadline_ms: int = Time.get_ticks_msec() + READY_FAILSAFE_CEILING_MSEC
	while Time.get_ticks_msec() < deadline_ms:
		if initial_ready_reached(game):
			return
		await owner.get_tree().process_frame
	assert(
		initial_ready_reached(game),
		"%s: initial world did not reach the formal READY contract within the production fail-safe ceiling (%d ms); startup performance stays OPEN / PRODUCT SLA MISSING" % [label, READY_FAILSAFE_CEILING_MSEC],
	)
