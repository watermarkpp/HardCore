extends "res://tests/framework/periodic_effect_boundaries_test.gd"

func _run() -> void:
	PlayerState.test_mode = true; PlayerState.reset_progress(false)
	world = World.new(); world.configure(self,PlayerState)
	clock = Clock.new(); clock.configure(self)
	var combat := Combat.new(); add_child(combat)
	target = ObservedEnemy.new(); target.setup(GameData.get_monster_by_id(19),null); add_child(target)
	target.set_physics_process(false); target.max_hp = 5000; target.current_hp = 5000
	target.direct_spell_magic_defense_min = 0; target.direct_spell_magic_defense_max = 0
	source = Player.new(); add_child(source); source.set_physics_process(false)
	var view := Presentation.new(); view.configure(world,false)
	runtime = Runtime.new(); runtime.configure(world,clock,combat,view)
	check(ContentLayers.set_feature_module_enabled("hc.ignite",true),"known source is enabled")
	bindings = PlayerState.feature_bundle().event_index.get("damage_committed:hc.skill.wizard.ice_storm",[])
	await _submit("lifecycle:first",100)
	await _submit("lifecycle:first",100)
	check(runtime.active_count() == 1 and int(runtime.metrics().refreshed) == 0,"duplicate release across batches does not refresh an admitted state")
	var replacement := Presentation.new(); replacement.configure(world,true)
	check(runtime.call("configure",world,clock,combat,replacement) == false and is_same(runtime.presentation(),view),"active runtime refuses owner or presentation replacement atomically")
	# setup reuses the same Node runtime identity but changes the actual life
	# authority. No old effect may cross this boundary even if HP is positive.
	target.setup(GameData.get_monster_by_id(19),null); target.set_physics_process(false)
	target.max_hp = 5000; target.current_hp = 5000
	target.direct_spell_magic_defense_min = 0; target.direct_spell_magic_defense_max = 0
	clock.advance_simulation(1.0); var before: int = target.current_hp
	await _pump()
	check(target.current_hp == before and runtime.active_count() == 0 and int(runtime.metrics().invalidated) == 1,"new target life rejects old ticks before HP mutation")
	check(view.events.back().kind == "stop","unsupported presentation still receives explicit life stop")
	await _submit("lifecycle:second",100)
	_zone_generation += 1; runtime.pump()
	check(runtime.active_count() == 0 and runtime.pending_count() == 0 and runtime.heap_count() == 0,"world change drains every accepted state and queue")
	check(int(runtime.metrics().started) == int(runtime.metrics().invalidated)+int(runtime.metrics().expired)+runtime.active_count(),"world cancellation conserves terminal state counts")
	check(view.events.back().kind == "stop","world clear stops logical cue handles even with no native visual nodes")
	check(runtime.call("configure",world,clock,combat,replacement) == true,"drained runtime can explicitly replace its presentation owner")
	await _submit("lifecycle:third",100)
	check(replacement.node_count() == 1,"new visual owner starts one cue after complete drain")
	runtime.clear(); await get_tree().process_frame
	check(runtime.active_count() == 0 and runtime.heap_count() == 0 and replacement.node_count() == 0,"explicit teardown releases logic and native cue ownership")
	check(int(runtime.metrics().started) == int(runtime.metrics().invalidated)+int(runtime.metrics().expired)+runtime.active_count(),"explicit teardown also conserves terminal state counts")
	check(ContentLayers.set_feature_module_enabled("hc.ignite",false),"test source withdrawn")
	check(runtime.errors.is_empty(),"lifecycle and duplicate boundaries have no hidden failure")
	target.queue_free(); source.queue_free(); combat.queue_free(); await get_tree().process_frame
	if not proof.write_receipt("periodic_effect_lifecycle_test",checks,errors.size()): errors.append("receipt")
	print("PERIODIC_EFFECT_LIFECYCLE_%s checks=%d errors=%s" % ["PASS" if errors.is_empty() else "FAIL",checks,str(errors)])
	get_tree().quit(0 if errors.is_empty() else 1)
