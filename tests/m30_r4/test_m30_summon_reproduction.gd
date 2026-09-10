extends Node

## M30-R4 real-map summon reproduction: mother 126 (角蝇) -> child 127 (蝙蝠).
## Formal mapped world, canonical spawn authority, production summon queue.
## The mother's respawn uses the production _respawn_later transaction with a
## fixture-chosen short wait (the production tier minimum is 300 s and cannot
## fit a headless runner scene); the respawn code path itself is unchanged.

const Fixture := preload("res://tests/helpers/formal_world_skill_fixture.gd")
const WorldSpatialRulesScript := preload("res://scripts/world_spatial_rules.gd")
const MOTHER_MONSTER_ID := 126
const CHILD_MONSTER_ID := 127
const MOTHER_SLOT := "test:m30_mother_126"
const DEFAULT_MONSTER_COLLISION_RADIUS_PX := 16.0  # ArtSpec.MONSTER_COLLISION_RADIUS_PX

var checks: int = 0
var failures: int = 0
var notes: Array[String] = []


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("M30REPRO FAIL: " + label)


func note(text: String) -> void:
	notes.append(text)
	print("M30REPRO_NOTE " + text)


func _wait_physics_frames(owner: Node, count: int) -> void:
	for _index: int in range(count):
		await owner.get_tree().physics_frame


func _wait_for_children(owner: Node, game: Node, minimum: int, max_frames: int) -> Array[EnemyActor]:
	var frames: int = 0
	while frames < max_frames:
		var children: Array[EnemyActor] = []
		for value: Variant in owner.get_tree().get_nodes_in_group("enemies"):
			var enemy := value as EnemyActor
			if enemy != null and enemy.monster_id == CHILD_MONSTER_ID and enemy.current_hp > 0:
				children.append(enemy)
		if children.size() >= minimum:
			return children
		await owner.get_tree().physics_frame
		frames += 1
	return []


func _wait_for_respawned_mother(owner: Node, old_instance_id: int, max_frames: int) -> EnemyActor:
	for _frame: int in range(max_frames):
		for value: Variant in owner.get_tree().get_nodes_in_group("enemies"):
			var enemy := value as EnemyActor
			if (
				enemy != null
				and enemy.monster_id == MOTHER_MONSTER_ID
				and enemy.get_instance_id() != old_instance_id
				and str(enemy.get_meta("spawn_slot_id", "")) == MOTHER_SLOT
				and enemy.current_hp > 0
			):
				return enemy
		await owner.get_tree().physics_frame
	return null


func _kill(actor: EnemyActor, killer: Node2D) -> void:
	actor.take_damage(999999, killer, {"source": "m30_repro_test"})


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await Fixture.wait_for_formal_world(self, game, "m30_repro")
	var caster: PlayerCharacter = game.player
	caster.max_hp = 999999
	caster.current_hp = caster.max_hp
	var caster_position: Vector2 = game._canonical_ground_gu_to_screen_px(
		Fixture.FIXTURE_GROUND_POSITION + Fixture.CASTER_GROUND_OFFSET
	)
	game._set_player_world_position(caster_position)
	for value: Variant in get_tree().get_nodes_in_group("enemies"):
		if value is EnemyActor:
			(value as EnemyActor).set_combat_position(
				caster.global_position + Vector2(3000.0, 3000.0), &"test_m30_repro_clear"
			)

	var mother_ground: Vector2 = Fixture.FIXTURE_GROUND_POSITION
	var mother_position: Vector2 = game._canonical_ground_gu_to_screen_px(mother_ground)
	check(
		not WorldSpatialRulesScript.point_inside_safe_zones_ground_gu(mother_ground, game._active_safe_zones),
		"mother ground must be outside the authored safe area",
	)
	var spawn_context := {"respawn_enabled": false, "spawn_slot_id": MOTHER_SLOT}
	var mother: EnemyActor = game._spawn_enemy(
		GameData.get_monster_by_id(MOTHER_MONSTER_ID), mother_position, false, -1.0, spawn_context
	)
	check(mother != null and mother.monster_id == MOTHER_MONSTER_ID, "mother 126 (角蝇) must spawn by exact id")
	if mother == null:
		print("M30_MOTHER_REPRO_FAIL spawn_failed")
		get_tree().quit(1)
		return
	check(mother.collision_radius_px > 0.0, "mother needs a real collision radius")
	note("mother collision_radius_px=%.2f combat_radius_gu=%.3f" % [mother.collision_radius_px, mother.combat_radius_gu])
	note("mother summon_rule=" + JSON.stringify(mother.summon_rule))

	var children: Array[EnemyActor] = await _wait_for_children(self, game, 3, 720)
	check(children.size() >= 3, "mother must summon at least three children while player stands beside")
	note("children_born=%d" % children.size())
	var queue_snapshot: Dictionary = game.hc_m30_summon_snapshot()
	note("summon_snapshot=" + JSON.stringify(queue_snapshot))
	check(int(queue_snapshot.get("max_probes_in_tick", 0)) <= 8, "global probe budget per tick must hold")
	check(
		int(queue_snapshot.get("max_materializations_in_tick", 0)) <= 1,
		"one materialization attempt per physics tick must hold",
	)
	check(int(queue_snapshot.get("capacity_rejected", 0)) == 0, "open field must not reject capacity")
	check(int(queue_snapshot.get("pending_batches", 1)) == 0, "queue must drain after births")
	var child_radii_ok := true
	for child: EnemyActor in children:
		if child.runtime_map_id != int(game.get("current_map_id")):
			child_radii_ok = false
		if str(child.get_meta("summoner_spawn_slot", "")) != MOTHER_SLOT:
			child_radii_ok = false
		if not is_equal_approx(child.collision_radius_px, DEFAULT_MONSTER_COLLISION_RADIUS_PX):
			child_radii_ok = false
	check(child_radii_ok, "every child must keep the default summon footprint radius on the same map")
	note("child collision_radius_px=%.2f combat_radius_gu=%.3f" % [children[0].collision_radius_px, children[0].combat_radius_gu])
	var reserved_after_births: Dictionary = queue_snapshot.get("reserved_by_slot", {})
	check((reserved_after_births as Dictionary).is_empty(), "completed births release all reservations")

	var mother_instance_id := mother.get_instance_id()
	_kill(mother, caster)
	var mother_gone := false
	for _frame: int in range(600):
		if not is_instance_valid(mother) or mother.is_queued_for_deletion():
			mother_gone = true
			break
		await get_tree().physics_frame
	check(mother_gone, "killed mother must leave the world")
	for child: EnemyActor in children:
		check(is_instance_valid(child) and child.current_hp > 0, "mother death must not delete living children")

	game._respawn_later(
		GameData.get_monster_by_id(MOTHER_MONSTER_ID),
		mother_position,
		false,
		0.1,
		int(game.get("_zone_generation")),
		spawn_context,
	)
	var respawned: EnemyActor = await _wait_for_respawned_mother(self, mother_instance_id, 1200)
	check(respawned != null, "respawned mother must reappear at the same spawn slot")
	if respawned != null:
		check(respawned.monster_id == MOTHER_MONSTER_ID, "respawned mother keeps monster_id 126")
		note("respawned mother instance_id=%d" % respawned.get_instance_id())
	var children_after_respawn: Array[EnemyActor] = await _wait_for_children(self, game, children.size() + 1, 720)
	check(
		children_after_respawn.size() >= children.size() + 1,
		"respawned mother must keep summoning on top of previous-life children",
	)
	for child: EnemyActor in children:
		check(
			is_instance_valid(child) and child.current_hp > 0,
			"previous-life child must survive the respawned mother's summon cycle",
		)
	var second_snapshot: Dictionary = game.hc_m30_summon_snapshot()
	note("second_snapshot=" + JSON.stringify(second_snapshot))

	for child: EnemyActor in children_after_respawn:
		if is_instance_valid(child):
			_kill(child, caster)
	if is_instance_valid(respawned):
		_kill(respawned, caster)
	await _wait_physics_frames(self, 240)
	var final_snapshot: Dictionary = game.hc_m30_summon_snapshot()
	check(int(final_snapshot.get("pending_batches", 1)) == 0, "all summon work must settle at the end")
	var final_reserved: Dictionary = final_snapshot.get("reserved_by_slot", {})
	check((final_reserved as Dictionary).is_empty(), "all reservations must be released at the end")
	check(
		int(final_snapshot.get("max_probes_in_tick", 999)) <= 8
			and int(final_snapshot.get("max_materializations_in_tick", 999)) <= 1,
		"budgets must hold for the whole scene",
	)

	print("M30_MOTHER_REPRO_%s checks=%d failures=%d mother_id=%d child_id=%d children=%d" % [
		"PASS" if failures == 0 else "FAIL", checks, failures, MOTHER_MONSTER_ID, CHILD_MONSTER_ID,
		children_after_respawn.size(),
	])
	for note_text: String in notes:
		print("M30REPRO_EVIDENCE " + note_text)
	get_tree().quit(0 if failures == 0 else 1)


func _ready() -> void:
	call_deferred("_run")
