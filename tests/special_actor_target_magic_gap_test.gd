extends Node2D
const GroundUnit := preload("res://scripts/ground_unit_space.gd")
var descriptors: Array[Dictionary] = []

func _ready() -> void: _run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true; PlayerState.reset_progress(false)
	PlayerState.computed_stats["anti_magic_points"] = 0
	PlayerState.computed_stats["magic_defense_min"] = 10
	PlayerState.computed_stats["magic_defense_max"] = 10
	var target := _make_player(Vector2(2, 0))
	await get_tree().process_frame
	target.max_hp = 1000
	target.current_hp = 1000
	for id: int in [220, 222, 224]:
		var caster := _make_caster(id, target)
		caster.target_magic_requested.connect(_capture)
		caster.attack_min = 50; caster.attack_max = 50; caster._attack_timer = 0.0
		descriptors.clear()
		var before := target.current_hp
		assert(caster._launch_target_magic(target, 50))
		assert(target.current_hp == before)
		var pending: Dictionary = caster._pending_attack_release_record
		assert(not pending.is_empty() and bool(pending.is_read_only()))
		assert(str(pending.get("release_id", "")).contains(":target_magic:release:"))
		assert(int(pending.get("source_monster_id", -1)) == id)
		assert(int(pending.get("source_instance_id", -1)) == caster.get_instance_id())
		assert(int(pending.get("target_instance_id", -1)) == target.get_instance_id())
		assert(int(pending.get("source_life", -1)) == caster._hc_life(caster))
		assert(int(pending.get("target_life", -1)) == caster._hc_life(target))
		assert(int(pending.get("runtime_map_id", -1)) == 1)
		assert(int(pending.get("source_generation", -1)) == 1 and int(pending.get("target_generation", -1)) == 1)
		assert(descriptors.size() == 1)
		assert(str(descriptors[0].get("release_id", "")) == str(pending.get("release_id", "")))
		caster._update_pending_attack(1.0)
		assert(target.current_hp < before, "ID%d target magic did not settle" % id)
		assert(str(caster.last_magic_attack_resolution.get("release_id", "")) == str(pending.get("release_id", "")))
		assert(caster.last_magic_attack_resolution.get("damage_channel", "") == "magic_defense")
		var once_hp := target.current_hp
		caster._update_pending_attack(1.0)
		assert(target.current_hp == once_hp, "target magic settled twice")
		print(JSON.stringify({"id": id,"release": pending,"hp_before":before,"hp_after":once_hp,"resolution":caster.last_magic_attack_resolution}))
		caster.queue_free(); await get_tree().process_frame
	# ID222 actual post-MAC healing positive path.
	var priest := _make_caster(222, target)
	await get_tree().process_frame
	priest.current_hp = maxi(1, priest.max_hp - 100)
	var priest_before := priest.current_hp
	target.current_hp = target.max_hp
	priest.attack_min = 50; priest.attack_max = 50; priest._attack_timer = 0.0
	assert(priest._launch_target_magic(target, 50)); priest._update_pending_attack(1.0)
	var committed_magic_damage := int(priest.last_magic_attack_resolution.get("final_damage", 0))
	var actual_magic_loss := target.max_hp - target.current_hp
	assert(committed_magic_damage == actual_magic_loss)
	var expected_magic_heal := floori(float(actual_magic_loss) * priest.life_steal_ratio + 0.000001)
	assert(committed_magic_damage > 0 and target.max_hp - target.current_hp > 0,
		"ID222 positive release did not commit target HP loss")
	assert(priest.current_hp == priest_before + expected_magic_heal,
		"ID222 heal was not based on post-MAC committed damage")
	# Zero raw damage: valid release, no HP loss and no heal.
	var zero_heal_before := priest.current_hp
	var zero_target_before := target.current_hp
	priest._attack_timer = 0.0; assert(priest._launch_target_magic(target, 0))
	priest._update_pending_attack(1.0)
	assert(priest.current_hp == zero_heal_before and target.current_hp == zero_target_before)
	# Guaranteed magic evade through the real player stat context.
	var saved_anti_magic: Variant = PlayerState.computed_stats.get("anti_magic_points", 0)
	PlayerState.computed_stats["anti_magic_points"] = 10
	var evade_heal_before := priest.current_hp
	var evade_target_before := target.current_hp
	priest._attack_timer = 0.0; assert(priest._launch_target_magic(target, 50))
	priest._update_pending_attack(1.0)
	assert(priest.current_hp == evade_heal_before and target.current_hp == evade_target_before)
	PlayerState.computed_stats["anti_magic_points"] = saved_anti_magic
	# A stale map release cannot heal or damage.
	var stale_hp := priest.current_hp; var target_hp := target.current_hp
	priest._attack_timer = 0.0; assert(priest._launch_target_magic(target, 50))
	target.set_meta("runtime_map_id", 2); priest._update_pending_attack(1.0)
	assert(priest.current_hp == stale_hp and target.current_hp == target_hp)
	target.set_meta("runtime_map_id", 1)
	assert(priest._launch_target_magic(target, 50))
	target.set_meta("zone_generation", 2)
	priest._update_pending_attack(1.0)
	assert(priest.current_hp == stale_hp and target.current_hp == target_hp, "stale generation settled")
	print(JSON.stringify({"id":222,"positive_magic_loss":actual_magic_loss,"expected_heal":expected_magic_heal,"zero":true,"evade":true,"map_rejection":true,"generation_rejection":true}))
	priest.queue_free(); target.queue_free(); await get_tree().process_frame
	print("SPECIAL_TARGET_MAGIC_GAP_PASS descriptors=%d" % descriptors.size())
	get_tree().quit(0)

func _capture(d: Dictionary) -> void: descriptors.append(d)
func _make_player(g: Vector2) -> PlayerCharacter:
	var p := PlayerCharacter.new(); p.global_position = _ground_to_screen(g); p.set_meta("runtime_map_id", 1); p.set_meta("zone_generation", 1); p.set_meta("safe_zones", [])
	p.max_hp = 1000; p.current_hp = 1000; p.defense_min = 999; p.defense_max = 999; add_child(p); p.set_physics_process(false); return p
func _make_caster(id: int, target: PlayerCharacter) -> EnemyActor:
	var a := EnemyActor.new(); a.setup(GameData.get_monster_by_id(id), target, false); a.set_meta("zone_generation", 1); a.configure_runtime_map_projection(1, Callable(self, "_ground_to_screen"), Callable(self, "_screen_to_ground")); a.configure_terrain_navigation_context({}); a.global_position = Vector2.ZERO; add_child(a); a.set_physics_process(false); a.target = target; return a
func _ground_to_screen(v: Vector2) -> Vector2: return GroundUnit.ground_delta_gu_to_screen_delta_px(v)
func _screen_to_ground(v: Vector2) -> Vector2: return GroundUnit.screen_delta_px_to_ground_delta_gu(v)
