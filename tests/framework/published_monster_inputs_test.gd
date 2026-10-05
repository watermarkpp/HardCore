extends Node
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Root := preload("res://tests/framework/fixtures/published_birth_probe_root.gd")
const Identity := preload("res://scripts/monster_identity.gd")
var proof := Proof.new()
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	proof.record(ok, label)
	if not ok: failures.append(label)

func _ready() -> void: _run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true; PlayerState.reset_progress(false)
	var game := Root.new(); add_child(game)
	var deadline := Time.get_ticks_msec() + 20000
	while not game.gameplay_input_is_enabled() and Time.get_ticks_msec() < deadline: await get_tree().process_frame
	check(game.gameplay_input_is_enabled(), "actual mapped world reaches READY")
	if not game.gameplay_input_is_enabled(): game.queue_free(); _finish(); return
	game.set_process(false); game.set_physics_process(false); game.player.set_physics_process(false)
	var original: EnemyActor
	for value: Variant in game._active_enemy_cache.values():
		var candidate := value as EnemyActor
		candidate.set_physics_process(false)
		if original == null and not candidate.is_boss and candidate.combat_enabled: original = candidate
	check(original != null, "published ordinary base slot exists")
	if original == null: game.queue_free(); _finish(); return
	var monster_id: int = original.monster_id
	var hp: int = original.max_hp
	var position: Vector2 = original.get_meta("spawn_position")
	var context: Dictionary = original.get_meta("spawn_context").duplicate(true)
	var seconds: float = original.get_meta("respawn_seconds")
	var slot: String = original.get_meta("spawn_slot_id")
	var old_catalog: Dictionary = Identity._catalog_cache.duplicate(true)
	var changed: Dictionary = old_catalog.duplicate(true)
	changed.entries_by_id[str(monster_id)].combat.stats.hp = hp + 321
	Identity._catalog_cache = changed
	Identity._entry_cache.clear(); Identity._appearance_cache.clear(); Identity._drop_cache.clear()
	original.queue_free()
	var replacement: EnemyActor = game._spawn_enemy({"monster_id": monster_id}, position, false, seconds, context)
	check(replacement != null, "normal vacant same-slot replacement remains admitted")
	check(replacement != null and replacement.max_hp == hp, "unpublished global config cannot change current-world replacement HP")
	if replacement != null: replacement.set_physics_process(false)
	var generation: int = game._zone_generation
	var started: bool = game._begin_map_transition(func(): game._load_zone(game.current_zone, true, game.current_map_data), game.current_map_id)
	check(started, "actual map republication begins through original transition owner")
	deadline = Time.get_ticks_msec() + 20000
	while game._map_transition_in_progress and Time.get_ticks_msec() < deadline: await get_tree().process_frame
	check(game.gameplay_input_is_enabled() and game._zone_generation > generation, "actual new publication reaches READY with original generated epoch")
	var published: EnemyActor
	for value: Variant in game._active_enemy_cache.values():
		var candidate := value as EnemyActor
		candidate.set_physics_process(false)
		if str(candidate.get_meta("spawn_slot_id", "")) == slot: published = candidate
	check(published != null and published.max_hp == hp + 321, "new configuration becomes active only after actual republication")
	Identity._catalog_cache = old_catalog
	Identity._entry_cache.clear(); Identity._appearance_cache.clear(); Identity._drop_cache.clear()
	game.queue_free(); await get_tree().process_frame
	_finish()

func _finish() -> void:
	var ok := proof.write_receipt("published_monster_inputs_test", proof.records.size(), failures.size())
	print("PUBLISHED_MONSTER_INPUTS_%s checks=%d failures=%s" % ["PASS" if ok and failures.is_empty() else "FAIL", proof.records.size(), str(failures)])
	get_tree().quit(0 if ok and failures.is_empty() else 1)
