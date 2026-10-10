extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Root := preload("res://scripts/game_root.gd")
const Guard := preload("res://scripts/map_editor/map_portal_travel_guard.gd")
const SkillFootprintSnapshotScript := preload("res://scripts/skills/skill_footprint_snapshot.gd")

var proof := Proof.new()
var failures: Array[String] = []
var game: Node

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	if not value:
		failures.append(label)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.profession = ProfessionRules.profession_display_name("taoist")
	PlayerState.level = 40
	var skeleton_skill_name := ProfessionRules.skill_display_name("taoist.summon_skeleton")
	PlayerState.learned_skills = {skeleton_skill_name: 3}
	PlayerState.computed_stats["skill_level_affix"] = {
		"contributions": {"all": 2}, "legacy": {}
	}
	PlayerState.recalculate_stats()
	PlayerState.computed_stats["skill_level_affix"] = {
		"contributions": {"all": 2}, "legacy": {}
	}
	game = Root.new()
	add_child(game)
	var deadline := Time.get_ticks_msec() + 30000
	while not game.gameplay_input_is_enabled() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(game.gameplay_input_is_enabled(), "formal GameRoot reaches READY")
	if not game.gameplay_input_is_enabled():
		_finish()
		return

	# The existing GameRoot lock is the sole input authority for both routes.
	game._acquire_gameplay_input_lock(&"v109_owner_test")
	game._on_gameplay_movement(Vector2.RIGHT)
	check(game.player.touch_vector == Vector2.ZERO, "touch route is rejected by the owner lock")
	Input.action_press("move_right")
	check(game.player._keyboard_movement_vector() == Vector2.ZERO, "keyboard route is rejected by the owner lock")
	Input.action_release("move_right")
	game._release_gameplay_input_lock(&"v109_owner_test")

	# A failed transition can retire its own claim, while a late failure from a
	# prior serial cannot retire a newer owner.
	var state: Dictionary = game._portal_guard_state
	check(Guard.begin_travel(state), "portal claim is accepted")
	var claim := Guard.active_claim_id(state)
	game._active_portal_claim_id = claim
	game._active_portal_claim_transition_serial = game._map_transition_serial
	await game._fail_map_transition(&"pre_arrival_keep_world")
	check(not bool(state.get("travel_in_flight", true)), "owned transition failure retires its portal claim")
	check(Guard.begin_travel(state), "new portal claim is accepted after failure")
	var newer_claim := Guard.active_claim_id(state)
	game._active_portal_claim_id = newer_claim
	game._active_portal_claim_transition_serial = game._map_transition_serial + 1
	await game._fail_map_transition(&"pre_arrival_keep_world")
	check(bool(state.get("travel_in_flight", false)), "stale transition failure preserves newer claim")
	game._cancel_portal_travel_claim(newer_claim)

	# Exercise the real SummonActor relocation/reset owner boundary: a pending
	# body restores its saved collision/visibility, and an interrupted divine
	# beast fire visual cannot survive the combat reset.
	var summon := SummonActor.new()
	game.add_child(summon)
	summon.owner_teleport_pending = true
	summon._owner_teleport_saved_collision_layer = 4
	summon._owner_teleport_saved_collision_mask = 8
	summon.collision_layer = 0
	summon.collision_mask = 0
	summon.visible = false
	var fire := Sprite2D.new()
	summon.add_child(fire)
	summon._fire_sprite = fire
	fire.visible = true
	summon.relocate_after_owner_teleport(Vector2.ZERO)
	check(summon.visible and summon.collision_layer == 4 and summon.collision_mask == 8, "pending summon relocation restores body state")
	check(not fire.visible, "owner teleport reset clears stale fire sprite")
	summon.queue_free()

	# Formal canonical poison owner: an expired strong red poison must not
	# participate in a later weak cast's max merge, while an active one must.
	var enemy := EnemyActor.new()
	game.add_child(enemy)
	enemy.setup(GameData.get_monster_by_id(34), game.player, false)
	var expired_red := {
		"contract_id": "buff.taoist.red_poison.v1", "poison_type": "red_poison",
		"flat_ac_reduction": 7, "flat_mac_reduction": 7,
		"extra_durability_loss_per_hit": 7, "duration_seconds": 10.0,
		"expires_at_ms": Time.get_ticks_msec() - 1,
	}
	enemy.set_meta("canonical_red_poison", expired_red)
	game._apply_canonical_poison(enemy, {
		"poison_type": "red_poison", "flat_ac_reduction": 3,
		"flat_mac_reduction": 3, "extra_durability_loss_per_hit": 3,
		"duration_seconds": 1.0,
	})
	var weak_red := enemy.get_meta("canonical_red_poison", {}) as Dictionary
	check(int(weak_red.get("flat_ac_reduction", -1)) == 3, "expired red AC does not max-merge")
	check(int(weak_red.get("flat_mac_reduction", -1)) == 3, "expired red MAC does not max-merge")
	check(int(weak_red.get("extra_durability_loss_per_hit", -1)) == 3, "expired red durability does not max-merge")
	check(float(weak_red.get("duration_seconds", 0.0)) < 2.0, "expired red duration is retired")
	var active_red := weak_red.duplicate(true)
	active_red["flat_ac_reduction"] = 7
	active_red["flat_mac_reduction"] = 7
	active_red["extra_durability_loss_per_hit"] = 7
	active_red["expires_at_ms"] = Time.get_ticks_msec() + 5000
	enemy.set_meta("canonical_red_poison", active_red)
	game._apply_canonical_poison(enemy, {
		"poison_type": "red_poison", "flat_ac_reduction": 3,
		"flat_mac_reduction": 3, "extra_durability_loss_per_hit": 3,
		"duration_seconds": 1.0,
	})
	var refreshed_red := enemy.get_meta("canonical_red_poison", {}) as Dictionary
	check(int(refreshed_red.get("flat_ac_reduction", -1)) == 7, "active red AC keeps max refresh")
	check(int(refreshed_red.get("flat_mac_reduction", -1)) == 7, "active red MAC keeps max refresh")
	game._apply_canonical_poison(enemy, {
		"poison_type": "green_poison", "damage_per_tick": 2,
		"duration_seconds": 1.0, "tick_interval_ms": 1000,
	})
	check(str(enemy.get_meta("canonical_red_poison", {}).get("poison_type", "")) == "red_poison", "green poison coexists with red poison")
	var red_runtime_stats := {}
	check(enemy.direct_spell_runtime_stats_into(red_runtime_stats), "red poison reaches direct spell stats consumer")
	check(int(red_runtime_stats.get("flat_ac_reduction", -1)) == 7, "red poison consumer applies AC reduction")
	check(int(red_runtime_stats.get("flat_mac_reduction", -1)) == 7, "red poison consumer applies MAC reduction")
	enemy.queue_free()

	# SUM001: real GameRoot restore preserves sparse stable slots and state when
	# the effective skeleton count is two (rank 3 plus the canonical +2 affix).
	var restore_pet_a := SummonActor.new()
	var restore_pet_b := SummonActor.new()
	for pet: SummonActor in [restore_pet_a, restore_pet_b]:
		pet.setup(game.player, "骷髅", 5, 5, "taoist.summon_skeleton", PlayerState.level)
	game.add_child(restore_pet_a)
	game.add_child(restore_pet_b)
	restore_pet_a.pet_slot_index = 0
	restore_pet_b.pet_slot_index = 2
	restore_pet_a.current_hp = restore_pet_a.max_hp - 11
	restore_pet_b.current_hp = restore_pet_b.max_hp - 23
	restore_pet_a.pet_growth_exp = 117
	restore_pet_b.pet_growth_exp = 239
	var saved_a := restore_pet_a.persistence_snapshot()
	var saved_b := restore_pet_b.persistence_snapshot()
	restore_pet_a.queue_free()
	restore_pet_b.queue_free()
	await get_tree().process_frame
	PlayerState.apply_taoist_main_pet_runtime_states({
		"contract_id": PlayerState.TAOIST_MAIN_PETS_PERSISTENCE_CONTRACT_ID,
		"groups": {"skeleton": [saved_a, saved_b], "divine_beast": []},
	})
	check(PlayerState.effective_skill_level("taoist.summon_skeleton") == 5, "effective skeleton rank permits two stable slots")
	check(PlayerState.taoist_main_pet_runtime_states_for_restore().get("groups", {}).get("skeleton", []).size() == 2, "persisted sparse snapshots pass the formal normalizer")
	check(game._restore_persisted_taoist_main_pet_if_needed(true), "GameRoot restores persisted sparse summon group")
	var restored_pets: Array[SummonActor] = game._canonical_main_pets("skeleton")
	check(restored_pets.size() == 2, "sparse restore keeps both permitted skeleton instances")
	check(restored_pets.size() == 2 and restored_pets[0].pet_slot_index == 0 and restored_pets[1].pet_slot_index == 2, "sparse restore preserves stable slot ids")
	check(restored_pets.size() == 2 and restored_pets[0].current_hp == int(saved_a.get("current_hp", -1)) and restored_pets[1].current_hp == int(saved_b.get("current_hp", -1)), "sparse restore preserves current HP")
	check(restored_pets.size() == 2 and restored_pets[0].pet_growth_exp == int(saved_a.get("pet_growth_exp", -1)) and restored_pets[1].pet_growth_exp == int(saved_b.get("pet_growth_exp", -1)), "sparse restore preserves growth XP")

	# SUM002: the canonical GameRoot recall consumer restores a current-generation
	# pending pet and retires the pending entry; an old generation cannot revive it.
	if restored_pets.size() == 2:
		var recall_pet := restored_pets[0]
		var recall_ground: Vector2 = game._canonical_screen_px_to_ground_gu(recall_pet.global_position)
		var recall_snapshot := SkillFootprintSnapshotScript.create_target_footprint(
			"taoist.summon_skeleton", "formal:recall:current", recall_ground,
			game._actor_combat_radius_gu(recall_pet), recall_pet.get_instance_id(),
			game._canonical_snapshot_absolute_context(recall_ground)
		)
		recall_pet.defer_owner_teleport_relocation()
		recall_pet.set_meta("pending_arrival_zone_generation", game._zone_generation)
		game._pending_main_pet_arrivals.append(recall_pet)
		game._apply_canonical_main_pet({
			"operation": "recall_existing_main_pet", "template_id": "skeleton",
			"pet_slot_index": recall_pet.pet_slot_index,
			"spawn_footprint_snapshot": recall_snapshot,
			"spawn_snapshot_id": str(recall_snapshot.get("snapshot_id", "")),
			"spawn_runtime_map_id": game.current_map_id,
		}, "taoist.summon_skeleton", "formal:recall:current")
		check(not recall_pet.owner_teleport_pending and recall_pet.visible, "current-generation recall restores pet body")
		check(not game._pending_main_pet_arrivals.has(recall_pet), "successful recall clears GameRoot pending arrival")

		var stale_pet := restored_pets[1]
		var stale_ground: Vector2 = game._canonical_screen_px_to_ground_gu(stale_pet.global_position)
		var stale_snapshot := SkillFootprintSnapshotScript.create_target_footprint(
			"taoist.summon_skeleton", "formal:recall:stale", stale_ground,
			game._actor_combat_radius_gu(stale_pet), stale_pet.get_instance_id(),
			game._canonical_snapshot_absolute_context(stale_ground)
		)
		stale_pet.defer_owner_teleport_relocation()
		stale_pet.set_meta("pending_arrival_zone_generation", game._zone_generation - 1)
		game._pending_main_pet_arrivals.append(stale_pet)
		game._apply_canonical_main_pet({
			"operation": "recall_existing_main_pet", "template_id": "skeleton",
			"pet_slot_index": stale_pet.pet_slot_index,
			"spawn_footprint_snapshot": stale_snapshot,
			"spawn_snapshot_id": str(stale_snapshot.get("snapshot_id", "")),
			"spawn_runtime_map_id": game.current_map_id,
		}, "taoist.summon_skeleton", "formal:recall:stale")
		check(stale_pet.owner_teleport_pending and not stale_pet.visible, "stale-generation recall cannot revive pet")
		check(not game._pending_main_pet_arrivals.has(stale_pet) and not stale_pet.has_meta("pending_arrival_zone_generation"), "stale recall retires pending entry and generation metadata")
	_finish()

func _finish() -> void:
	if is_instance_valid(game):
		game.queue_free()
	var written := proof.write_receipt(
		"v109_world_owner_formal_test", proof.records.size(), failures.size()
	)
	print("V109_WORLD_OWNER_FORMAL_", "PASS" if written and failures.is_empty() else "FAIL", " failures=", failures)
	get_tree().quit(0 if written and failures.is_empty() else 1)
