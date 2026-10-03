extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Compiler := preload("res://scripts/features/compilation/feature_compiler.gd")
const Authority := preload("res://scripts/features/adapters/feature_authority.gd")
const Root := preload("res://tests/framework/fixtures/lease_probe_root.gd")
const Fixture := preload("res://tests/helpers/formal_world_skill_fixture.gd")
const PACKAGE := "res://assets/data/features/validation/resource_cue_registry.json"
const AUDIO := "res://assets/audio/sfx/client/137__M26-3.wav"
@export var cancel_during_audio := false
@export var check_acceptance_resources := false
@export var multi_source_reentry := false
var proof := Proof.new()
var checks := 0
var failures: Array[String] = []
var game: Node
var played: Array[Dictionary] = []

func check(value: bool, label: String) -> void:
	proof.record(value,label)
	checks += 1
	if not value: failures.append(label)

func _ready() -> void:
	_run.call_deferred()

func _observe_audio(event: Dictionary) -> void:
	if event.context.has("feature_effect_handle"):
		played.append(event)
		if cancel_during_audio: game._feature_effect_runtime.clear()

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.profession = "法师" if multi_source_reentry else "战士"
	PlayerState.level = 50
	PlayerState.learned_skills = {"hc.skill.wizard.ice_storm":3} if multi_source_reentry else {"hc.skill.warrior.fire_sword":3}
	if multi_source_reentry:
		PlayerState.equipment["hc.slot.weapon"] = preload("res://scripts/item_drop_instance_rules.gd").create_instance(GameData.get_item_record({"item_id":85}),"resource:multi:weapon")
	PlayerState.recalculate_stats(false)
	var parent: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/features/validation/resource_natural_parent.json" if multi_source_reentry else "res://assets/data/features/validation/resource_cue_parent.json"))
	var child: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/features/validation/resource_natural_child.json" if multi_source_reentry else "res://assets/data/features/validation/resource_cue_child.json"))
	check(Compiler.compile_catalog([parent,child],Authority.build()).success, "known critical cue closes its actual sound through a required child module")
	var missing := child.duplicate(true)
	missing.resource_dependencies = []
	check(not Compiler.compile_catalog([parent,missing],Authority.build()).success, "missing possible cue sound rejects the whole otherwise legal candidate")
	for invalid: Variant in [null, 137, "hc.cue.unknown.v1", "player.skill.fire_sword"]:
		var bad := parent.duplicate(true)
		bad.mechanics[0].cue_id = invalid
		check(not Compiler.compile_catalog([bad,child],Authority.build()).success, "unknown or malformed cue identity refuses publication " + str(invalid))
	var ready: bool = await ContentLayers.reload_feature_catalog_async("res://assets/data/features/validation/resource_natural_registry.json" if multi_source_reentry else PACKAGE)
	check(ready, "formal compiler preparation and atomic publication admit critical cue closure")
	if not ready: _finish(); return
	var resource_owner: WeakRef = weakref(ContentLayers.feature_configuration().resource_lease)
	game = Root.new()
	add_child(game)
	var deadline := Time.get_ticks_msec()+20000
	while not game.gameplay_input_is_enabled() and Time.get_ticks_msec()<deadline: await get_tree().process_frame
	check(game.gameplay_input_is_enabled(), "actual mapped world reaches READY with prepared cue")
	if not game.gameplay_input_is_enabled(): _finish(); return
	var target := await Fixture.prepare_target(self,game,game.player,19,"feature_resource_cue")
	check(target != null, "real projected receiver")
	if target == null: _finish(); return
	game.set_process(false)
	game.set_physics_process(false)
	game.player.set_physics_process(false)
	for actor: Node in get_tree().get_nodes_in_group("enemies"): actor.set_physics_process(false)
	target.max_hp = 10000
	target.current_hp = 10000
	target.direct_spell_anti_magic_points = 0
	target.direct_spell_magic_defense_min = 0
	target.direct_spell_magic_defense_max = 0
	target.direct_spell_stats_valid = true
	game.player.attack_min = 100
	game.player.attack_max = 100
	if multi_source_reentry:
		PlayerState.computed_stats.magic_min = 100; PlayerState.computed_stats.magic_max = 100
	game.player.current_mp = 100
	game.player.fire_sword_enabled = true
	game.player.half_moon_enabled = false
	game.player.thrusting_enabled = false
	game._skill_cast_target = target
	game._set_magic_locked_target(target,true)
	game._audio_runtime_service.event_started.connect(_observe_audio)
	var lease: RefCounted = game._capture_action_configuration("hc.skill.wizard.ice_storm") if multi_source_reentry else game._capture_melee_configuration()
	check(lease != null and lease.resource_lease() != null, "real accepted configuration owns its prepared nonempty cue resources")
	if lease == null: _finish(); return
	if multi_source_reentry:
		check(lease.event_bindings_for("hc.skill.wizard.ice_storm").size()==3,"real rule item and learned skill qualify three distinct accepted bindings")
	if check_acceptance_resources:
		var resource_type := preload("res://scripts/features/contracts/feature_resource_lease.gd")
		var empty_plan: Dictionary = resource_type.requirements(ContentLayers.feature_configuration().catalog,[])
		var empty_lease: RefCounted = resource_type.issue(empty_plan,{},ContentLayers._feature_resource_service,{})
		check(empty_lease != null, "legitimate typed empty lease exists for resource-free configurations")
		var action_type := preload("res://scripts/features/contracts/action_config_lease.gd")
		var batch_type := preload("res://scripts/features/runtime/damage_batch.gd")
		var snapshot: Dictionary = lease._snapshot
		var bindings: Array = lease.event_bindings_for("hc.skill.warrior.fire_sword")
		var hp_before: int = target.current_hp
		var mp_before: int = game.player.current_mp
		var rng_before: int = game._rng.state
		for invalid_resources: RefCounted in [null,empty_lease]:
			var invalid_action: Dictionary = action_type.create(snapshot.definition,snapshot.rank,snapshot.actor_level,
				snapshot.primary_stats,snapshot.versions,snapshot.actor_identity,snapshot.partner_definition,
				snapshot.partner_rank,snapshot.primary_policy,snapshot.melee,snapshot.event_index,invalid_resources)
			check(not invalid_action.success, "critical configuration refuses missing accepted resource closure " + str(invalid_resources != null))
			var ticket: RefCounted = game._reserve_feature_bindings("hc.skill.warrior.fire_sword",bindings)
			check(ticket != null, "valid otherwise unchanged bindings receive a real capacity promise")
			if ticket == null: continue
			var release_id: String = game._feature_effect_runtime._reservations[ticket.sequence()].expected_release_id
			var invalid_batch: Dictionary = batch_type.create(game._world_context,release_id,"hc.skill.warrior.fire_sword",bindings,{},0,ticket,invalid_resources)
			check(not invalid_batch.success, "critical batch refuses missing resources before taking its producer promise")
			check(ticket.can_begin_release(release_id), "missing resources do not consume the lawful producer's only release qualification")
			var valid_batch: Dictionary = batch_type.create(game._world_context,release_id,"hc.skill.warrior.fire_sword",bindings,{},0,ticket,lease.resource_lease())
			check(valid_batch.success, "same lawful promise still accepts the correctly prepared resource owner")
			if valid_batch.success: valid_batch.batch.finish_production()
			if invalid_batch.success: invalid_batch.batch.finish_production()
			ticket.close()
		check(target.current_hp == hp_before and game.player.current_mp == mp_before and game._rng.state == rng_before,
			"qualification rejection and corrected empty producer have no HP MP or RNG side effects")
		check(game._feature_effect_runtime.reservation_snapshot().actions == 0, "resource qualification probes leave no unfinished producer capacity")
		game.queue_free()
		await get_tree().process_frame
		check(ContentLayers.reload_feature_catalog(), "resource qualification world retires before ordinary catalog restoration")
		_finish()
		return
	var accepted: bool = game.player.request_skill("hc.skill.wizard.ice_storm",target.get_instance_id(),lease) if multi_source_reentry \
		else game.player.request_attack_toward(Vector2.RIGHT,true,target.get_instance_id(),lease)
	check(accepted and lease.effect_reservation() != null, "natural player request accepts nonempty ticket before real windup")
	check(ContentLayers.set_feature_module_enabled("hc.ignite",false) and ContentLayers.set_feature_module_enabled("hc.ignite_cue_assets",false), "withdraw parent then child without revoking already accepted work")
	deadline = Time.get_ticks_msec()+3000
	while game.observed_releases == 0 and Time.get_ticks_msec()<deadline: await get_tree().process_frame
	check(game.observed_releases == 1 and target.current_hp < 10000, "single canonical release commits actual base HP once")
	var base_hp: int = target.current_hp
	var raw := roundi(float(10000-base_hp)*0.05)
	var runtime: RefCounted = game._feature_effect_runtime
	var rng: int = game._rng.state
	for frame in range(120):
		runtime.pump()
		if runtime.pending_count() == 0: break
		await get_tree().process_frame
	var port: RefCounted = runtime.presentation()
	if cancel_during_audio:
		check(played.size() == 1, "real prepared audio onset reaches the synchronous cancellation observer once")
		check(runtime.active_count() == 0 and runtime.pending_count() == 0 and port.node_count() == 0, "synchronous retirement leaves no live effect or native cue")
		check(port._audio_handles.is_empty(), "retired cue cannot register a late audio ownership record")
		if multi_source_reentry:
			check(runtime.heap_count()==0 and runtime.reservation_snapshot().actions==0 and runtime.reservation_snapshot().receipts==0,
				"synchronous retirement clears heap producer and all receipts before the next binding")
			check(preload("res://scripts/layers/runtime/execution/frame_budget.gd").snapshot().open_scopes==0,
				"synchronous retirement returns with all shared budget scopes closed")
		if played.size() == 1:
			var request: Dictionary = played[0]
			var player: AudioStreamPlayer = game._audio_runtime_service._event_players[int(request.pool_index)]
			check(not player.playing and player.stream == null, "synchronously retired onset stops its exact real player and releases the prepared stream")
		check(game._rng.state == rng and target.current_hp == base_hp, "retirement observation preserves committed base HP and gameplay RNG")
		lease = null
		await get_tree().process_frame
		check(resource_owner.get_ref() == null, "synchronous cancellation retires the accepted lease after native cue destruction")
		game._time_domains.advance_simulation(1.0)
		runtime.pump()
		check(target.current_hp == base_hp and runtime.errors.is_empty(), "retired onset neither schedules periodic damage nor reports a missing required cue")
		game.queue_free()
		await get_tree().process_frame
		check(ContentLayers.reload_feature_catalog(), "retired world restores the default catalog after onset cancellation")
		_finish()
		return
	check(runtime.active_count() == 1 and port.node_count() == 1, "required procedural cue actually instantiates even when optional headless decoration is suppressed")
	check(played.size() == 1, "actual accepted effect sends exactly one prepared stream to existing audio service")
	if played.size() == 1:
		var request: Dictionary = played[0]
		var player: AudioStreamPlayer = game._audio_runtime_service._event_players[int(request.pool_index)]
		check(player.playing and is_same(player.stream,resource_owner.get_ref().resource_at(AUDIO)), "real engine player consumes the exact accepted AudioStream rather than a later lookup")
		check(request.event_id == "player.skill.fire_sword" and request.runtime_path == AUDIO, "stable cue uses the exact existing primary sound event")
		check(game._audio_runtime_service.has_method("stop_prepared_event"), "prepared playback has identity-scoped stop")
		if game._audio_runtime_service.has_method("stop_prepared_event"):
			var wrong := request.duplicate(true)
			wrong.request_serial = int(request.request_serial)+1
			check(not game._audio_runtime_service.stop_prepared_event(wrong) and player.playing, "stale playback identity cannot stop another pooled owner")
		var handle: String = runtime._states.keys()[0]
		port.refresh(handle,raw+1)
		check(played.size() == 1 and port.node_count() == 1, "refresh preserves one cue and does not replay onset sound")
	check(game._rng.state == rng and target.current_hp == base_hp, "presentation consumption neither rerolls gameplay nor changes HP")
	lease = null
	for second in range(1,5):
		game._time_domains.advance_simulation(float(second*1000000-game._time_domains.simulation_usec())/1000000.0)
		for frame in range(120):
			runtime.pump()
			if not runtime.has_due(): break
			await get_tree().process_frame
		check(target.current_hp == base_hp-second*raw, "original periodic damage completes unchanged at tick " + str(second))
	check(runtime.active_count() == 0 and port.node_count() == 0, "terminal effect stops its native critical cue")
	await get_tree().process_frame
	check(resource_owner.get_ref() == null, "last accepted cue and state retire the lease after actual node destruction")
	check(runtime.errors.is_empty() and game._rng.state == rng, "resource-backed presentation preserves original periodic authority and RNG")
	game.queue_free()
	await get_tree().process_frame
	check(ContentLayers.reload_feature_catalog(), "world retirement restores ordinary default-off source")
	_finish()

func _finish() -> void:
	var scene_id := "feature_resource_cue_reentry_test" if cancel_during_audio else "feature_resource_cue_test"
	if check_acceptance_resources: scene_id = "feature_resource_acceptance_test"
	if multi_source_reentry: scene_id = "feature_resource_multi_reentry_test"
	if not proof.write_receipt(scene_id,checks,failures.size()): failures.append("receipt")
	print("FEATURE_RESOURCE_CUE_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL",checks,str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
