extends Node

const GU := preload("res://scripts/ground_unit_space.gd")
const Root := preload("res://scripts/game_root.gd")
const PlanContract := preload("res://scripts/skills/skill_execution_plan_contract.gd")

class PlannerProbe extends Root:
	var requested_radii: Array = []
	func _canonical_screen_px_to_ground_gu(p: Vector2) -> Vector2:
		return GU.screen_delta_px_to_ground_delta_gu(p)
	func _canonical_ground_gu_to_screen_px(p: Vector2) -> Vector2:
		return GU.ground_delta_gu_to_screen_delta_px(p)
	func _canonical_summon_position_is_valid(
		_p: Vector2, radius: float, _ignored: SummonActor,
		_ignored_summons: Array[SummonActor] = []
	) -> bool:
		# Narrowly observe the planner's actual WORLD/body query parameter.
		requested_radii.append(radius)
		return true

func _ready() -> void:
	var failures: Array = []
	var game := PlannerProbe.new()
	game.player = PlayerCharacter.new()
	game.player.position = GU.ground_delta_gu_to_screen_delta_px(Vector2(16, 16))
	for row: Array in [["taoist.summon_skeleton", 16.0 / (32.0 * sqrt(2.0))], ["taoist.summon_divine_beast", 0.5]]:
		game.requested_radii.clear()
		var plan := game._canonical_summon_spawn_plan(str(row[0]))
		if not bool(plan.get("valid", false)) or game.requested_radii.is_empty():
			failures.append("planner_did_not_query:" + str(row[0]))
		for radius: float in game.requested_radii:
			if absf(radius - float(row[1])) > 0.00001:
				failures.append("%s:planner_radius=%f actual_body=%f" % [row[0], radius, row[1]])
		var template := "divine_beast" if str(row[0]).ends_with("divine_beast") else "skeleton"
		var snapshot := PlanContract.build_release_snapshot(str(row[0]), "r4-radius:" + template,
			{"effects": [{"type": "summon", "template_id": template}]},
			{"runtime_map_id": 9001, "screen_to_ground_position_px": GU.screen_delta_px_to_ground_delta_gu,
			"ground_gu_to_screen_position_px": GU.ground_delta_gu_to_screen_delta_px,
			"summon_spawn_position_screen_px": plan.get("position_screen_px", Vector2.ZERO), "caster_runtime_id": game.player.get_instance_id()})
		if snapshot.is_empty() or absf(float(snapshot.get("target_combat_radius_gu", -1)) - float(row[1])) > 0.00001:
			failures.append("%s:release_snapshot_radius_mismatch" % row[0])
	game.player.free()
	game.player = null
	game.free()
	print("R4_SUMMON_PLANNER_RADIUS_PASS" if failures.is_empty() else "R4_SUMMON_PLANNER_RADIUS_FAIL " + str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
