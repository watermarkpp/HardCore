extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Root := preload("res://tests/framework/fixtures/lease_probe_root.gd")
const Fixture := preload("res://tests/helpers/formal_world_skill_fixture.gd")
const Batch := preload("res://scripts/features/runtime/damage_batch.gd")
var proof := Proof.new()
var checks := 0
var errors: Array[String] = []
var deaths := 0
func check(value: bool,label: String) -> void:
	proof.record(value,label); checks += 1
	if not value: errors.append(label)
func _ready() -> void: _run.call_deferred()
func _run() -> void:
	PlayerState.test_mode = true; PlayerState.reset_progress(false)
	PlayerState.profession = "法师"; PlayerState.level = 50
	PlayerState.recalculate_stats(false)
	var game := Root.new(); add_child(game)
	var deadline := Time.get_ticks_msec()+20000
	while not game.gameplay_input_is_enabled() and Time.get_ticks_msec() < deadline: await get_tree().process_frame
	check(game.gameplay_input_is_enabled(),"real world is ready")
	if not game.gameplay_input_is_enabled(): _finish(); return
	var target := await Fixture.prepare_target(self,game,game.player,19,"periodic_effect_death")
	check(target != null,"receiver uses formal mapped spawn and real death connection")
	if target == null: _finish(); return
	game.set_process(false); game.set_physics_process(false); game.player.set_physics_process(false)
	for actor: Node in get_tree().get_nodes_in_group("enemies"): actor.set_physics_process(false)
	game._enemy_death_flush_queued = true
	target.max_hp = 110; target.current_hp = 110
	target.direct_spell_magic_defense_min = 0; target.direct_spell_magic_defense_max = 0
	target.died.connect(func(_enemy: EnemyActor,_data: Dictionary) -> void: deaths += 1)
	var source := PlayerCharacter.new(); game.add_child(source); source.set_physics_process(false)
	check(ContentLayers.set_feature_module_enabled("hc.ignite",true),"source module enabled through formal content owner")
	var batch: RefCounted = game._begin_feature_damage_batch("wizard.ice_storm","periodic:death:one")
	check(batch != null,"real Root accepts one qualified base batch")
	if batch == null: game.queue_free(); _finish(); return
	target.take_damage(100,source,{"feature_damage_batch":batch,"source_class":"direct","damage_channel":"magic_defense"})
	game._finish_feature_damage_batch(batch)
	var runtime: RefCounted = game._feature_effect_runtime
	await _pump(runtime)
	check(target.current_hp == 10 and runtime.active_count() == 1,"surviving base hit admits exactly one five-damage effect")
	check(batch.facts()[0].historical_credit.profile_id == PlayerState.active_profile_id,"accepted fact freezes exact profile credit")
	check(ContentLayers.set_feature_module_enabled("hc.ignite",false),"source module is withdrawn before any tick")
	var life: int = source.combat_epoch
	source.take_damage(100000,false)
	check(source.current_hp == 0 and source.combat_epoch > life,"source crosses actual formal player death boundary")
	var xp: int = PlayerState.experience
	game._time_domains.advance_simulation(1.0); await _pump(runtime)
	check(target.current_hp == 5 and deaths == 0,"source death does not cancel the accepted nonlethal tick")
	game._time_domains.advance_simulation(1.0); await _pump(runtime)
	check(runtime.active_count() == 0 and runtime.heap_count() == 0 and int(runtime.metrics().ticks) == 2,"lethal tick stops its old mutation handle immediately")
	await get_tree().process_frame
	check(deaths == 1 and game._pending_enemy_deaths.size() == 1,"sole actor death pipeline emits one event and queues one reward job")
	check(PlayerState.experience == xp,"no experience is granted before existing settlement boundary")
	game._flush_enemy_deaths(false)
	check(game._pending_enemy_deaths.is_empty() and game._enemy_death_terminal_jobs.size() == 1 \
		and game._enemy_death_terminal_jobs[0].state == "COMMITTED","existing settlement and drop pipeline commits the periodic death exactly once")
	var expected: int = game._build_enemy_death_runtime_snapshot(GameData.get_monster_by_id(19)).experience
	check(PlayerState.experience == xp+expected,"periodic kill grants canonical experience through the sole old owner")
	var drops := _drop_count(game); var rng: int = game._rng.state
	game._time_domains.advance_simulation(8.0); await _pump(runtime)
	game._flush_enemy_deaths(false)
	check(deaths == 1 and game._enemy_death_terminal_jobs.size() == 1 and _drop_count(game) == drops \
		and game._rng.state == rng and PlayerState.experience == xp+expected,"late pumping repeats neither death, reward, drops nor old reward RNG")
	check(runtime.errors.is_empty(),"death and reward path has no hidden failure")
	game.queue_free(); await get_tree().process_frame
	_finish()
func _pump(runtime: RefCounted) -> void:
	for iteration in range(120):
		runtime.pump()
		if runtime.pending_count() == 0 and not runtime.has_due(): return
		await get_tree().process_frame
	check(false,"effect queue terminates")
func _drop_count(game: Node) -> int:
	var count := 0
	for child: Node in game.get_children():
		if child is LootPickup: count += 1
	return count
func _finish() -> void:
	if not proof.write_receipt("periodic_effect_death_production_test",checks,errors.size()): errors.append("receipt")
	print("PERIODIC_EFFECT_DEATH_PRODUCTION_%s checks=%d errors=%s" % ["PASS" if errors.is_empty() else "FAIL",checks,str(errors)])
	get_tree().quit(0 if errors.is_empty() else 1)
