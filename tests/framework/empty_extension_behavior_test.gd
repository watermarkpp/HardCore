extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const StableRoot := preload("res://tests/framework/fixtures/legacy_baseline_root.gd")
const Fixture := preload("res://tests/helpers/formal_world_skill_fixture.gd")
const Observer := preload("res://scripts/damage_ledger_observer.gd")
const Items := preload("res://scripts/item_drop_instance_rules.gd")
const Persistence := preload("res://scripts/json_persistence_service.gd")
const BASELINE := "res://outputs/framework_v2/baseline/EMPTY_EXTENSION_BEHAVIOR.json"
var _proof := Proof.new()
var checks := 0
var errors: Array[String] = []

func _ready() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	_proof.record(value, label)
	checks += 1
	if not value:
		errors.append(label)

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.profession = "法师"
	PlayerState.level = 50
	PlayerState.learned_skills = {"冰咆哮":3}
	PlayerState.recalculate_stats()
	PlayerState.profile_directory = "user://framework_empty_baseline/characters"
	PlayerState.profile_index_path = "user://framework_empty_baseline/profiles.json"
	PlayerState.active_profile_id = "framework-empty-owner"
	PlayerState.character_name = "框架基线"
	var game := StableRoot.new()
	add_child(game)
	var deadline := Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < deadline and not game.gameplay_input_is_enabled():
		await get_tree().process_frame
	check(game.gameplay_input_is_enabled(), "real mapped world becomes READY before baseline work")
	if not game.gameplay_input_is_enabled():
		_finish()
		return
	var first: EnemyActor = await Fixture.prepare_target(self,game,game.player,19,"framework_empty_baseline")
	check(first != null and first.projection_ready(), "first target uses exact canonical mapped spawn")
	if first == null:
		game.queue_free()
		_finish()
		return
	var targets: Array[EnemyActor] = [first]
	var ground_positions := [Vector2(40.5,13.5), Vector2(41.2,13.5), Vector2(40.5,14.2)]
	var ids := [19,64,89]
	for index: int in range(1,3):
		var target: EnemyActor = game._spawn_enemy(GameData.get_monster_by_id(ids[index]),
			game._canonical_ground_gu_to_screen_px(ground_positions[index]),false,-1.0,
			{"respawn_enabled":false,"spawn_slot_id":"fixture:framework:empty:%d" % index})
		check(target != null and target.monster_id == ids[index] and target.projection_ready(),
			"AOE target %d uses canonical identity and projection" % index)
		if target != null:
			targets.append(target)
	check(targets.size() == 3, "all three independent real AOE targets exist")
	game.set_process(false)
	game.set_physics_process(false)
	game.player.set_physics_process(false)
	for existing: Node in get_tree().get_nodes_in_group("enemies"):
		existing.set_physics_process(false)
	game.player.current_mp = 100000
	var labels := {}
	var actor_rng_before := []
	for index: int in range(targets.size()):
		var target := targets[index]
		target.current_hp = 10000
		target.max_hp = 10000
		target.direct_spell_anti_magic_points = 0
		target.direct_spell_magic_defense_min = 0
		target.direct_spell_magic_defense_max = 0
		target.direct_spell_stats_valid = true
		target._rng.seed = 5300 + index
		labels[target.get_instance_id()] = index
		actor_rng_before.append(str(target._rng.state))
	game._rng.seed = 530076
	var rng_before := str(game._rng.state)
	Observer.reset()
	Observer.recording_enabled = true
	game._skill_cast_target = first
	var cast := game._execute_canonical_skill("冰咆哮",game.player.global_position,Vector2.RIGHT,0,
		{"release_id":"fixture:framework:empty:release:1"},true,true)
	Observer.recording_enabled = false
	check(bool(cast.get("accepted",false)), "baseline traverses sole canonical planner and actual release")
	var damage_rows := []
	for event: Dictionary in Observer.events:
		if labels.has(int(event.victim_instance_id)):
			damage_rows.append({"target_fixture_index":labels[int(event.victim_instance_id)],
				"resolved_damage":event.resolved_damage,"hp_before":event.hp_before,"hp_after":event.hp_after,
				"actual_hp_delta":event.actual_hp_delta,"damage_type":event.damage_type})
	check(damage_rows.size() == 3, "real base AOE writes exactly three target HP records")
	var hp_after := []
	var actor_rng_after := []
	for target: EnemyActor in targets:
		hp_after.append(target.current_hp)
		actor_rng_after.append(str(target._rng.state))
	var plan: Dictionary = cast.get("canonical_plan",{})
	check(not plan.get("cooldown_contract",{}).is_empty() and int(plan.get("effective_rank",0)) == 3,
		"baseline records actual canonical timing and effective rank")
	var drops := []
	for item_id: int in [80,85,81]:
		var catalog_item: Dictionary = GameData.get_item_record({"item_id":item_id})
		var record := Items.create_instance(catalog_item,"fixture:framework:empty:drop:" + str(catalog_item.get("itemId",0)))
		check(int(catalog_item.get("itemId",0)) == item_id and not record.is_empty() and Items.validate_instance(record,catalog_item), "real drop rule generates validated stable item " + str(item_id))
		drops.append(record)
	var document: Dictionary = PlayerState._prepare_character_save_payload(false)
	check(not document.is_empty() and int(document.get("save_version",0)) == 10,
		"empty extensions use actual legacy version 10 character payload")
	# Timestamp is an explicit fixed fixture input before either writer run.
	# Other fields and future/unknown payloads are not normalized or discarded.
	document.updated_at = 1710000000
	var target_path: String = PlayerState._profile_path(PlayerState.active_profile_id)
	var service := Persistence.new()
	var job = service.submit(target_path,{"domain":"framework.empty.baseline"},document,
		PlayerState._json_validator_for_path(target_path))
	check(job != null, "real ordered character writer accepts canonical payload")
	var receipt: Dictionary = service.finish(job,true) if job != null else {}
	check(bool(receipt.get("success",false)) and service.pending_count() == 0,
		"real validated writer completes exactly once and drains")
	var bytes := FileAccess.get_file_as_bytes(target_path)
	check(not bytes.is_empty(), "persisted legacy bytes are read from actual committed file")
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(bytes)
	var behavior := {"schema_version":1,"damage_rows":damage_rows,"target_hp_after":hp_after,
		"game_rng_before":rng_before,"game_rng_after":str(game._rng.state),
		"actor_rng_before":actor_rng_before,"actor_rng_after":actor_rng_after,"drops":drops,
		"resource_cost":plan.get("resource_cost",{}),"effective_rank":plan.get("effective_rank",0),
		"timing":plan.get("cooldown_contract",{}),"gameplay_actions":plan.get("gameplay_actions",[]),
		"effective_geometry_cells":plan.get("effective_geometry_cells",[]),
		"saved_bytes_utf8":bytes.get_string_from_utf8(),"saved_bytes_sha256":digest.finish().hex_encode()}
	if OS.get_environment("HC_FRAMEWORK_BASELINE_MODE") == "capture":
		check(not FileAccess.file_exists(BASELINE), "initial baseline is created once rather than overwriting prior proof")
		if not FileAccess.file_exists(BASELINE) and errors.is_empty():
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(BASELINE.get_base_dir()))
			var file := FileAccess.open(BASELINE,FileAccess.WRITE)
			check(file != null, "initial baseline evidence opens")
			if file != null:
				file.store_string(JSON.stringify(behavior,"  "))
	else:
		check(FileAccess.file_exists(BASELINE), "comparison requires preserved pre-framework baseline")
		if FileAccess.file_exists(BASELINE):
			var previous: Variant = JSON.parse_string(FileAccess.get_file_as_string(BASELINE))
			# The user explicitly authorized formal identity migration. Only
			# these named save identity lanes change; retain original evidence.
			if previous is Dictionary:
				var old_bytes: String = previous.saved_bytes_utf8
				check(old_bytes.sha256_text() == previous.saved_bytes_sha256,
					"original byte baseline remains intact before identity migration")
				var old_save: Dictionary = JSON.parse_string(old_bytes)
				var progression := preload("res://scripts/skills/skill_progression_service.gd").new()
				var imported: Dictionary = progression.load_snapshot(old_save.skill_progression)
				check(bool(imported.success), "preserved legacy skill IDs migrate explicitly")
				var projected := {}
				for id: String in progression.snapshot().skills:
					projected[id] = progression.snapshot().skills[id].base_rank
				old_save.learned_skills = projected
				old_save.skill_progression = progression.snapshot()
				old_save.skill_button_assignments.contract_id = "gameplay.skill.button_assignments.v4"
				old_save.skill_button_assignments.migration = "native_v4"
				var migrated_bytes := old_bytes
				for field: String in ["learned_skills", "skill_progression", "skill_button_assignments"]:
					migrated_bytes = _replace_identity_object(migrated_bytes, field, old_save[field])
				var character_codec := preload("res://scripts/identity/character_identity_codec.gd")
				var role: Dictionary = character_codec.decode(old_save)
				check(bool(role.success), "preserved legacy profession migrates explicitly")
				migrated_bytes = _insert_character_identity(migrated_bytes, character_codec.encode(role.profession_id))
				migrated_bytes = _insert_item_binding_identity(migrated_bytes, preload("res://scripts/identity/item_binding_codec.gd").encode(["", "", "", ""]))
				migrated_bytes = _insert_item_identity(migrated_bytes)
				var equipment_codec := preload("res://scripts/identity/equipment_identity_codec.gd")
				var equipment_import := equipment_codec.normalize_document(old_save, true)
				check(equipment_import.status == "KNOWN_VALID", "preserved equipment slots import only their explicit identity lanes")
				if equipment_import.status == "KNOWN_VALID":
					for field: String in ["equipment", "equip_cycle_cursor"]:
						migrated_bytes = _replace_identity_object(migrated_bytes, field, equipment_import.document[field])
					migrated_bytes = _insert_equipment_identity(migrated_bytes)
				previous.saved_bytes_utf8 = migrated_bytes
				previous.saved_bytes_sha256 = str(previous.saved_bytes_utf8).sha256_text()
			var encoded: Variant = JSON.parse_string(JSON.stringify(behavior))
			var observed := FileAccess.open("res://outputs/test_logs/framework/empty_extension_behavior.observed.json", FileAccess.WRITE)
			if observed != null:
				observed.store_string(JSON.stringify({"expected":previous,"actual":encoded}, "  "))
			check(previous is Dictionary and previous == encoded,
				"default-off damage/order/RNG/drop and all save bytes except explicit identity lanes equal baseline")
	game.queue_free()
	await get_tree().process_frame
	_finish()


# Preserve every unrelated byte, including original JSON number spelling.
# This test helper changes only three uniquely named top-level object values.
func _replace_identity_object(original: String, field: String, replacement: Dictionary) -> String:
	var prefix := "\"" + field + "\":"
	check(original.count(prefix) == 1, "save identity lane has one explicit field: " + field)
	var start := original.find(prefix) + prefix.length()
	if start < prefix.length() or original.substr(start, 1) != "{":
		check(false, "save identity object location: " + field)
		return original
	var depth := 0
	var quoted := false
	var escaped := false
	for index: int in range(start, original.length()):
		var character := original.substr(index, 1)
		if quoted:
			if escaped:
				escaped = false
			elif character == "\\":
				escaped = true
			elif character == "\"":
				quoted = false
			continue
		if character == "\"":
			quoted = true
		elif character == "{":
			depth += 1
		elif character == "}":
			depth -= 1
			if depth == 0:
				return original.substr(0, start) + JSON.stringify(replacement) + original.substr(index + 1)
	check(false, "save identity object terminates: " + field)
	return original

# Insert the one newly authorized identity object in the actual sorted writer
# position. Every pre-existing non-identity byte remains exactly as captured.
func _insert_character_identity(original: String, identity: Dictionary) -> String:
	var anchor := "\"character_name\":"
	check(original.count("\"character_identity\":") == 0 and original.count(anchor) == 1 \
		and not identity.is_empty(), "new character identity has one exact insertion boundary")
	var index := original.find(anchor)
	if index < 0 or identity.is_empty():
		return original
	return original.substr(0, index) + "\"character_identity\":" + JSON.stringify(identity) + "," + original.substr(index)

func _insert_item_binding_identity(original: String, identity: Dictionary) -> String:
	var anchor := "\"later_content_enabled\":"
	check(original.count("\"item_button_assignments\":") == 0 and original.count(anchor) == 1 \
		and not identity.is_empty(), "new item binding identity has one exact insertion boundary")
	var index := original.find(anchor)
	if index < 0 or identity.is_empty():
		return original
	return original.substr(0, index) + "\"item_button_assignments\":" + JSON.stringify(identity) + "," + original.substr(index)

func _insert_item_identity(original: String) -> String:
	var anchor := "\"later_content_enabled\":"
	check(original.count("\"item_identity\":") == 0 and original.count(anchor) == 1,
		"authorized formal item identity has one exact insertion boundary")
	var index := original.find(anchor)
	if index < 0: return original
	return original.substr(0, index) + "\"item_identity\":" \
		+ JSON.stringify(preload("res://scripts/identity/item_identity_codec.gd").HEADER) + "," + original.substr(index)

func _finish() -> void:
	if not _proof.write_receipt("empty_extension_behavior_test",checks,errors.size()):
		errors.append("framework assertion receipt failed")
	print(("FRAMEWORK_EMPTY_EXTENSION_BEHAVIOR_PASS" if errors.is_empty() else "FRAMEWORK_EMPTY_EXTENSION_BEHAVIOR_FAIL")
		+ " checks=" + str(checks) + " errors=" + str(errors))
	get_tree().quit(0 if errors.is_empty() else 1)

func _insert_equipment_identity(original: String) -> String:
	var anchor := "\"experience\":"
	check(original.count("\"equipment_identity\":") == 0 and original.count(anchor) == 1,
		"authorized equipment identity has one exact insertion boundary")
	var index := original.find(anchor)
	if index < 0: return original
	return original.substr(0, index) + "\"equipment_identity\":" \
		+ JSON.stringify(preload("res://scripts/identity/equipment_identity_codec.gd").HEADER) + "," + original.substr(index)
