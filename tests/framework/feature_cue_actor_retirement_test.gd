extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Root := preload("res://tests/framework/fixtures/lease_probe_root.gd")
const Fixture := preload("res://tests/helpers/formal_world_skill_fixture.gd")
const Cue := preload("res://scripts/features/presentation/ignite_cue.gd")
const Actor := preload("res://scripts/features/contracts/actor_ref.gd")
const Budget := preload("res://scripts/layers/runtime/execution/frame_budget.gd")
const PACKAGE := "res://assets/data/features/validation/resource_cue_registry.json"
const AUDIO := "res://assets/audio/sfx/client/137__M26-3.wav"
@export var retire_during_cue_attach := false
@export var reuse_audio_pool_before_retirement := false
@export var replace_during_audio_onset := false
@export var wait_for_native_audio_finish_before_reuse := false
@export var retire_world_with_active_cue := false
var proof := Proof.new()
var failures: Array[String] = []
var game: Node
var target: EnemyActor
var played: Array[Dictionary] = []
var attach_callbacks := 0
var cue_seen := WeakRef.new()
var replaced_cue_seen := WeakRef.new()
var replacement_resources: RefCounted
var pool_reuse_attempts := 0
var native_finish_deadline_msec := 0
var native_finished_count := 0
var service_finished_count := 0
var last_service_finished: Dictionary = {}

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	if not value: failures.append(label)

func _ready() -> void:
	_run.call_deferred()

func _observe_audio(event: Dictionary) -> void:
	if event.get("context", {}).has("feature_effect_handle"):
		played.append(event.duplicate(true))
		if wait_for_native_audio_finish_before_reuse and played.size() == 1:
			native_finish_deadline_msec = Time.get_ticks_msec() + 5000
			var player: AudioStreamPlayer = game._audio_runtime_service._event_players[int(event.pool_index)]
			player.finished.connect(_observe_native_audio_finished.bind(event.duplicate(true), player))
		if replace_during_audio_onset and played.size() == 1:
			var port: RefCounted = game._feature_effect_runtime.presentation()
			var handle: String = str(event.context.feature_effect_handle)
			replaced_cue_seen = port._nodes[handle]
			check(game._audio_runtime_service.stop_prepared_event(event),
				"synchronous observer releases the original actual audio slot")
			port.stop(handle)
			check(port.start(handle, Actor.capture(game._world_context, target),
				{"cue_id": "hc.cue.ignite.fire_sword.v1", "cue_policy": "required_procedural", "raw_per_tick": 9},
				replacement_resources), "synchronous observer replaces the same presentation handle with a real Cue")

func _same_audio_request(first: Dictionary, second: Dictionary) -> bool:
	return first.get("event_id") == second.get("event_id") \
		and first.get("request_serial") == second.get("request_serial") \
		and first.get("pool_index") == second.get("pool_index")

func _observe_service_audio_finished(event: Dictionary) -> void:
	if not wait_for_native_audio_finish_before_reuse or played.is_empty(): return
	if int(event.get("pool_index", -1)) != int(played[0].pool_index): return
	last_service_finished = event.duplicate(true)
	if not _same_audio_request(event, played[0]): return
	service_finished_count += 1
	var index: int = int(event.pool_index)
	var audio: Node = game._audio_runtime_service
	check(service_finished_count == 1 and bool(event.get("prepared", false)),
		"one actual service event_finished carries the prepared original request")
	check(audio._event_slots[index].is_empty() and audio._event_players[index].stream == null,
		"service finish callback has already cleared original slot and prepared stream")

func _observe_native_audio_finished(expected: Dictionary, player: AudioStreamPlayer) -> void:
	if not wait_for_native_audio_finish_before_reuse: return
	# The same player is reused below. A later finish for its new serial does
	# not count as a second finish for the original request.
	if not _same_audio_request(last_service_finished, expected): return
	native_finished_count += 1
	var index: int = int(expected.pool_index)
	var audio: Node = game._audio_runtime_service
	check(native_finished_count == 1 and _same_audio_request(last_service_finished, expected)
		and service_finished_count == 1,
		"one real AudioStreamPlayer.finished follows the matching service finish event")
	check(is_same(player, audio._event_players[index]) and audio._event_slots[index].is_empty()
		and player.stream == null and not player.playing,
		"native finish callback sees the original player with no slot or prepared stream")

func _observe_child(child: Node) -> void:
	if child.get_script() != Cue: return
	attach_callbacks += 1
	cue_seen = weakref(child)
	# Real SceneTree notification between add_child and the caller's return.
	# This observer is deliberately injected, not claimed as a natural UI flow.
	if retire_during_cue_attach and attach_callbacks == 1:
		game._feature_effect_runtime.clear()

func _drain(runtime: RefCounted) -> void:
	for frame in range(120):
		runtime.pump()
		if runtime.pending_count() == 0 and not runtime.has_due(): return
		await get_tree().process_frame
	check(false, "bounded public consumer reaches its current service boundary")

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	check(PlayerState.set_profession_identity("hc.profession.warrior"), "registered warrior identity")
	PlayerState.level = 50
	PlayerState.learned_skills = {"hc.skill.warrior.fire_sword": 3}
	PlayerState.recalculate_stats(false)
	var ready: bool = await ContentLayers.reload_feature_catalog_async(PACKAGE)
	check(ready, "existing default-off critical cue registry prepares its declared resources")
	if not ready: _finish(); return
	game = Root.new()
	add_child(game)
	var deadline := Time.get_ticks_msec() + 20000
	while not game.gameplay_input_is_enabled() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(game.gameplay_input_is_enabled(), "actual mapped Root reaches READY")
	if not game.gameplay_input_is_enabled(): await _cleanup(); _finish(); return
	target = await Fixture.prepare_target(self, game, game.player, 19, "cue_actor_retirement")
	check(target != null, "actual factory creates the mapped receiver")
	if target == null: await _cleanup(); _finish(); return
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
	game.player.current_mp = 100
	game.player.fire_sword_enabled = true
	game.player.half_moon_enabled = false
	game.player.thrusting_enabled = false
	game._audio_runtime_service.event_started.connect(_observe_audio)
	if wait_for_native_audio_finish_before_reuse:
		game._audio_runtime_service.event_finished.connect(_observe_service_audio_finished)
		# Empty the real pool before the original request exists; never stop A to
		# manufacture a finished notification.
		game._audio_runtime_service.stop_all_events("fixture_pool_prepare")
	target.child_entered_tree.connect(_observe_child)
	var old_ref: RefCounted = Actor.capture(game._world_context, target)
	check(old_ref != null, "receiver has actual world and life qualification")
	var slot: String = str(target.get_meta("spawn_slot_id"))
	var position: Vector2 = target.global_position
	var lease: RefCounted = game._capture_melee_configuration()
	check(lease != null and lease.resource_lease() != null, "actual action configuration owns its nonempty resource lease")
	if lease == null: await _cleanup(); _finish(); return
	var resource_owner: WeakRef = weakref(lease.resource_lease())
	if replace_during_audio_onset: replacement_resources = lease.resource_lease()
	var accepted: bool = game.player.request_attack_toward(Vector2.RIGHT, true, target.get_instance_id(), lease)
	check(accepted and lease.effect_reservation() != null, "real Player accepts a capacity ticket before windup")
	if not accepted: lease = null; await _cleanup(); _finish(); return
	check(ContentLayers.set_feature_module_enabled("hc.ignite", false)
		and ContentLayers.set_feature_module_enabled("hc.ignite_cue_assets", false),
		"source withdrawal leaves accepted resource ownership intact")
	deadline = Time.get_ticks_msec() + 3000
	while game.observed_releases == 0 and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(game.observed_releases == 1 and target.current_hp < 10000, "original timer and Root pipeline commit base HP exactly once")
	var base_hp: int = target.current_hp
	var rng: int = game._rng.state
	var runtime: RefCounted = game._feature_effect_runtime
	if reuse_audio_pool_before_retirement or replace_during_audio_onset:
		# Test-owned preparation establishes a deterministic empty real pool;
		# the original accepted state then starts its own prepared event.
		game._audio_runtime_service.stop_all_events("fixture_pool_prepare")
	await _drain(runtime)
	replacement_resources = null
	var port: RefCounted = runtime.presentation()
	check(attach_callbacks == (2 if replace_during_audio_onset else 1),
		"each actual onset attaches exactly one CanvasItem to the receiver")
	check(game._rng.state == rng and target.current_hp == base_hp, "cue lifecycle preserves committed HP and gameplay RNG")
	if retire_during_cue_attach:
		check(runtime.active_count() == 0 and runtime.heap_count() == 0 and runtime.pending_count() == 0,
			"synchronous actor-tree observer retires logic before cue attachment returns")
		check(port.node_count() == 0 and port._nodes.is_empty(),
			"retired onset cannot register a late live cue after add_child callback")
		check(played.is_empty() and port._audio_handles.is_empty(),
			"retirement before audio onset cannot start or register old playback")
		lease = null
		await get_tree().process_frame
		await get_tree().process_frame
		check(cue_seen.get_ref() == null, "retired actual cue is destroyed after deferred deletion")
		check(resource_owner.get_ref() == null, "retired accepted lease is released without a surviving cue")
		game._time_domains.advance_simulation(1.0)
		await _drain(runtime)
		check(target.current_hp == base_hp and runtime.errors.is_empty(), "retired onset never produces a later periodic mutation")
	elif retire_world_with_active_cue:
		check(runtime.active_count() == 1 and runtime.has_work() and port.node_count() == 1 and played.size() == 1,
			"formal world exit begins with accepted logic and its actual Cue still active")
		if played.size() != 1: lease = null; await _cleanup(); _finish(); return
		var request: Dictionary = played[0]
		var audio: Node = game._audio_runtime_service
		var player: AudioStreamPlayer = audio._event_players[int(request.pool_index)]
		check(player.playing and is_same(player.stream, resource_owner.get_ref().resource_at(AUDIO))
			and audio._event_slots[int(request.pool_index)].request_serial == request.request_serial,
			"world exit begins with exact accepted stream and current native playback ownership")
		var watched := {"root":weakref(game),"actor":weakref(target),"cue":cue_seen,
			"audio_service":weakref(audio),"audio_player":weakref(player),"runtime":weakref(runtime),
			"presentation":weakref(port),"world":weakref(game._world_context),"clock":weakref(game._time_domains)}
		var actor_identity: Dictionary = old_ref.identity()
		var before := {"active":runtime.active_count(),"pending":runtime.pending_count(),
			"nodes":port.node_count(),"playing":player.playing,"request":request}
		lease = null
		# No fixture clear, stop or synthetic exit is allowed before this owner
		# boundary. The actual Root exit is the only retirement consumer here.
		game.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
		var nodes_retired := true
		for key: String in ["root","actor","cue","audio_service","audio_player"]:
			nodes_retired = nodes_retired and watched[key].get_ref() == null
		check(nodes_retired, "formal queued Root exit destroys old actor, Cue, audio service and native player")
		check(not runtime.has_work() and runtime.active_count() == 0 and runtime.heap_count() == 0
			and runtime.pending_count() == 0 and runtime.child_count() == 0 and runtime._receipts.is_empty(),
			"formal exit clears every live state, fact, child, heap and historical receipt")
		var no_reservations := true
		for value: int in runtime.reservation_snapshot().values(): no_reservations = no_reservations and value == 0
		check(no_reservations and port.node_count() == 0 and port._nodes.is_empty() and port._audio_handles.is_empty(),
			"formal exit drains promise ownership, actual Cue registry and exact audio requests")
		check(resource_owner.get_ref() == null and runtime.errors.is_empty(),
			"withdrawn accepted resource lease retires through active world exit without delivery errors")
		var events: Array = port.events.duplicate(true)
		port = null; runtime = null; old_ref = null
		await get_tree().process_frame
		var contexts_retired := true
		for key: String in ["runtime","presentation","world","clock"]:
			contexts_retired = contexts_retired and watched[key].get_ref() == null
		check(contexts_retired, "test observers release the final runtime, presentation, world and clock references")
		check(Budget.snapshot().open_scopes == 0, "active owner exit leaves every shared budget scope closed")
		print("CUE_ACTIVE_WORLD_EXIT_TRACE ", JSON.stringify({"actor":actor_identity,"before":before,
			"nodes_retired":nodes_retired,"contexts_retired":contexts_retired,
			"resource_retired":resource_owner.get_ref() == null,"events":events}))
		await _cleanup()
		_finish()
		return
	elif reuse_audio_pool_before_retirement or replace_during_audio_onset or wait_for_native_audio_finish_before_reuse:
		check(runtime.active_count() == 1 and port.node_count() == 1,
			"presentation boundary preserves the one accepted logical state")
		check(played.size() == (2 if replace_during_audio_onset else 1),
			"observed prepared onsets exactly match the controlled replacement path")
		if not played.is_empty():
			var old_request: Dictionary = played[0]
			var audio: Node = game._audio_runtime_service
			var new_request: Dictionary
			if replace_during_audio_onset and played.size() == 2:
				new_request = played[1]
				check(port._audio_handles[str(old_request.context.feature_effect_handle)].request == new_request,
					"outer original onset cannot overwrite the replacement Cue audio ownership")
			else:
				if wait_for_native_audio_finish_before_reuse:
					while (native_finished_count == 0 or service_finished_count == 0) \
						and Time.get_ticks_msec() < native_finish_deadline_msec:
						await get_tree().process_frame
					var naturally_finished: bool = native_finished_count == 1 and service_finished_count == 1
					check(naturally_finished,
						"the original prepared request finishes through both native callbacks within five seconds")
					if not naturally_finished:
						lease = null
						await _cleanup()
						_finish()
						return
				else:
					check(audio.stop_prepared_event(old_request), "old actual audio request releases its pool slot")
				# The real service advances a round-robin cursor. Traverse its
				# bounded pool through real start/stop requests, without assigning
				# a cursor or emitting a synthetic finished signal.
				for index in audio._event_players.size():
					var candidate: Dictionary = audio.play_prepared_event(str(old_request.event_id),
						resource_owner.get_ref().resource_at(AUDIO),
						{"audio_owner_key": "fixture_independent_reuse", "release_id": "second_onset:%d" % index})
					pool_reuse_attempts += 1
					if candidate.get("status") != "played": break
					if candidate.pool_index == old_request.pool_index:
						new_request = candidate
						break
					check(audio.stop_prepared_event(candidate), "intermediate real pool traversal request retires only itself")
				check(new_request.get("status") == "played", "independent owner starts the exact prepared stream")
			if new_request.get("status") == "played":
				check(new_request.request_serial != old_request.request_serial,
					"replacement playback has a distinct real request identity")
				if reuse_audio_pool_before_retirement or wait_for_native_audio_finish_before_reuse:
					check(new_request.pool_index == old_request.pool_index,
						"real round-robin traversal reuses the exact original AudioStreamPlayer")
				var player: AudioStreamPlayer = audio._event_players[int(new_request.pool_index)]
				check(not audio.stop_prepared_event(old_request), "delayed old request cannot retire the reused audio slot")
				check(player.playing and is_same(player.stream, resource_owner.get_ref().resource_at(AUDIO))
					and audio._event_slots[int(new_request.pool_index)].request_serial == new_request.request_serial,
					"stale retirement preserves the replacement slot, real playback and exact resource")
				lease = null
				await get_tree().process_frame
				await get_tree().process_frame
				if replace_during_audio_onset:
					check(replaced_cue_seen.get_ref() == null and cue_seen.get_ref() != null,
						"old queued Cue is destroyed while the replacement same-handle Cue remains alive")
					check(cue_seen.get_ref().strength == 9, "replacement Cue keeps its independently selected presentation strength")
				# This is the production retirement consumer, not a simulated signal.
				runtime.clear()
				check(runtime.active_count() == 0 and port.node_count() == 0 and port._audio_handles.is_empty(),
					"logical retirement drains the actual Cue and its registered audio ownership")
				if reuse_audio_pool_before_retirement or wait_for_native_audio_finish_before_reuse:
					check(player.playing and audio._event_slots[int(new_request.pool_index)].request_serial == new_request.request_serial,
						"old logical retirement cannot stop another owner's reused playback")
					check(audio.stop_prepared_event(new_request), "only the replacement request retires its own actual playback")
				else:
					check(not player.playing and player.stream == null and audio._event_slots[int(new_request.pool_index)].is_empty(),
						"same-handle replacement retires through the current logical owner")
				await get_tree().process_frame
				await get_tree().process_frame
				check(cue_seen.get_ref() == null and resource_owner.get_ref() == null,
					"terminal Cue and accepted resource lease release after deferred deletion")
				check(target.current_hp == base_hp and game._rng.state == rng and runtime.errors.is_empty(),
					"pool reuse and replacement leave committed HP, gameplay RNG and delivery errors unchanged")
	else:
		check(runtime.active_count() == 1 and port.node_count() == 1 and played.size() == 1,
			"accepted state owns one actual cue and one prepared audio onset")
		if played.size() == 1:
			var request: Dictionary = played[0]
			var player: AudioStreamPlayer = game._audio_runtime_service._event_players[int(request.pool_index)]
			check(is_same(player.stream, resource_owner.get_ref().resource_at(AUDIO)),
				"actual AudioStreamPlayer consumes the exact accepted stream")
			var handle: String = str(request.context.feature_effect_handle)
			port.refresh(handle, 9)
			check(port.node_count() == 1 and played.size() == 1, "refresh keeps one cue without replaying audio")
			var bound: Dictionary = game.feature_world_capacity_bound()
			target.queue_free()
			check(old_ref.resolve(false) == null, "queued actor immediately loses its original mutation qualification")
			var replacement: EnemyActor = game._spawn_enemy(GameData.get_monster_by_id(19), position, false, -1.0,
				{"respawn_enabled": false, "spawn_slot_id": slot})
			check(replacement != null and game.feature_world_capacity_bound() == bound,
				"same declared slot admits a new life without growing the world bound")
			if replacement != null:
				replacement.set_physics_process(false)
				var replacement_hp: int = replacement.current_hp
				lease = null
				await get_tree().process_frame
				await get_tree().process_frame
				check(cue_seen.get_ref() == null, "actor destruction also destroys its actual child cue")
				# Existing contract allows logic to retire at its next due service.
				game._time_domains.advance_simulation(1.0)
				await _drain(runtime)
				check(runtime.active_count() == 0 and runtime.heap_count() == 0
					and port.node_count() == 0 and port._audio_handles.is_empty(),
					"old actor state and exact playback retire at the existing due boundary")
				check(replacement.current_hp == replacement_hp and game._rng.state == rng,
					"old delayed service cannot mutate replacement life or gameplay RNG")
				port.stop(handle); port.stop(handle); port.clear(); port.clear()
				check(port.node_count() == 0 and port._audio_handles.is_empty(), "repeated stop and clear remain empty")
				await get_tree().process_frame
				check(resource_owner.get_ref() == null, "last accepted state and cue release the withdrawn lease")
	check(Budget.snapshot().open_scopes == 0, "public consumer closes all shared budget scopes")
	print("CUE_ACTOR_RETIREMENT_TRACE ", JSON.stringify({"reentry": retire_during_cue_attach,
		"pool_reuse": reuse_audio_pool_before_retirement, "audio_replacement": replace_during_audio_onset,
		"native_finish_reuse": wait_for_native_audio_finish_before_reuse,
		"native_finished_count": native_finished_count, "service_finished_count": service_finished_count,
		"last_service_finished": last_service_finished,
		"pool_reuse_attempts": pool_reuse_attempts,
		"actor": old_ref.identity() if old_ref != null else {}, "audio_requests": played,
		"attach_callbacks": attach_callbacks, "events": port.events, "errors": runtime.errors}))
	lease = null
	port.clear()
	await _cleanup()
	_finish()

func _cleanup() -> void:
	if is_instance_valid(game): game.queue_free()
	await get_tree().process_frame
	check(ContentLayers.reload_feature_catalog(), "retired test world restores the ordinary catalog")

func _finish() -> void:
	var id := "feature_cue_actor_retirement_reentry_test" if retire_during_cue_attach else "feature_cue_actor_retirement_test"
	if reuse_audio_pool_before_retirement: id = "feature_cue_pool_reuse_test"
	if replace_during_audio_onset: id = "feature_cue_audio_replacement_test"
	if wait_for_native_audio_finish_before_reuse: id = "feature_cue_native_finish_reuse_test"
	if retire_world_with_active_cue: id = "feature_cue_active_world_exit_test"
	var written: bool = proof.write_receipt(id, proof.records.size(), failures.size())
	print("FEATURE_CUE_ACTOR_RETIREMENT_", "PASS" if written and failures.is_empty() else "FAIL",
		" checks=", proof.records.size(), " failures=", failures)
	get_tree().quit(0 if written and failures.is_empty() else 1)
