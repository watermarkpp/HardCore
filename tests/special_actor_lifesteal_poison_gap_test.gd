extends Node2D
const GroundUnit := preload("res://scripts/ground_unit_space.gd")

func _ready() -> void: _run.call_deferred()
func _run() -> void:
	PlayerState.test_mode = true; PlayerState.reset_progress(false)
	var victim := _make_player(Vector2(1, 0))
	var leader := _make_actor(193, victim)
	await get_tree().process_frame
	victim.max_hp = 1000
	victim.current_hp = 1000
	# Pin AC after player _ready. This records the existing physical pre-AC
	# heal basis without inventing an undocumented actual-loss balance change.
	victim.defense_min = 11
	victim.defense_max = 11
	leader.current_hp = maxi(1, leader.max_hp - 100)
	var leader_before := leader.current_hp
	var victim_before := victim.current_hp
	leader._apply_attack_damage(victim, 30, false, -1, true, -1, false)
	var actual_loss := victim_before - victim.current_hp
	var expected_heal := 9 # Existing pre-AC input30 * .33, integer truncation.
	assert(actual_loss == 19 and is_equal_approx(leader.life_steal_ratio, 0.33))
	assert(actual_loss > 0, "ID193 positive attack did not lose target HP")
	assert(leader.current_hp == leader_before + expected_heal,
		"ID193 existing pre-AC heal/input contract changed: before=%d after=%d loss=%d ratio=%f" % [leader_before, leader.current_hp, actual_loss, leader.life_steal_ratio])
	var no_heal := leader.current_hp
	var no_loss_hp := victim.current_hp
	leader._apply_attack_damage(victim, 0, false, -1, true, -1, false)
	assert(victim.current_hp == no_loss_hp, "ID193 zero attack changed target HP")
	assert(leader.current_hp == no_heal, "ID193 zero damage healed")
	var miss_target_hp := victim.current_hp
	var source_accuracy := leader.accuracy
	leader.accuracy = 0
	leader._apply_attack_damage(victim, 30, true, 0, true, -1, false)
	leader.accuracy = source_accuracy
	assert(victim.current_hp == miss_target_hp and leader.current_hp == no_heal,
		"ID193 miss changed HP or healed")

	# ID169 has a legacy profile binding but no canonical runtime entry. It
	# cannot be promoted to a formal on-hit actor by fabricating its identity.
	assert(GameData.get_monster_by_id(169).is_empty(), "legacy-only ID169 unexpectedly entered the formal runtime catalog")
	print(JSON.stringify({"id193_loss":actual_loss,"id193_input":30,"id193_heal_basis":"pre_ac_input","id193_heal":expected_heal,"zero_no_heal":true,"miss_no_heal":true,"id169_actor_coverage":"MISSING","id169_runtime_lookup_missing":true}))
	leader.queue_free(); victim.queue_free(); await get_tree().process_frame
	print("SPECIAL_LIFESTEAL_POISON_GAP_PASS id193=1 legacy169_exclusion=1")
	get_tree().quit(0)

func _make_player(g: Vector2) -> PlayerCharacter:
	var p := PlayerCharacter.new(); p.global_position = _ground_to_screen(g); p.set_meta("runtime_map_id", 1); p.set_meta("zone_generation", 1); p.set_meta("safe_zones", []); p.max_hp = 1000; p.current_hp = 1000; p.defense_min = 0; p.defense_max = 0; add_child(p); p.set_physics_process(false); return p
func _make_actor(id: int, target: PlayerCharacter) -> EnemyActor:
	var a := EnemyActor.new(); a.setup(GameData.get_monster_by_id(id), target, false); a.set_meta("zone_generation", 1); a.configure_runtime_map_projection(1, Callable(self, "_ground_to_screen"), Callable(self, "_screen_to_ground")); a.configure_terrain_navigation_context({}); a.global_position = _ground_to_screen(Vector2.ZERO); add_child(a); a.set_physics_process(false); return a
func _ground_to_screen(v: Vector2) -> Vector2: return GroundUnit.ground_delta_gu_to_screen_delta_px(v)
func _screen_to_ground(v: Vector2) -> Vector2: return GroundUnit.screen_delta_px_to_ground_delta_gu(v)
