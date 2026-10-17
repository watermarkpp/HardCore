extends Node

## Direct MAIN-thread fixture only. Exercises actual ResourceLoader primitives
## and original numerical oracle. This cannot prove a cross-owner Host bridge.
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Coordinator := preload("res://scripts/gameplay/enemy/enemy_owner_streaming_coordinator.gd")
const Primitives := preload("res://scripts/gameplay/enemy/enemy_owner_resource_primitives.gd")
const MainPrimitives := preload("res://scripts/gameplay/enemy/enemy_main_resource_primitives.gd")
const Budget := preload("res://scripts/gameplay/enemy/enemy_owner_streaming_budget.gd")
const VisualPorts := preload("res://scripts/gameplay/enemy/enemy_owner_streaming_visual_ports.gd")
const Renderer := preload("res://scripts/gameplay/enemy/enemy_main_visual_renderer.gd")
const Publication := preload("res://scripts/gameplay/enemy/enemy_main_streaming_texture_publication.gd")
const Original := preload("res://scripts/monster_visual_streaming_coordinator.gd")
var proof := Proof.new()
var failures := 0
var fatal_messages: Array[String] = []
var entry_ordinal := 0

class RenderBridge:
	extends RefCounted
	func apply_original_coordinator_operation(_renderer: Object, _id: int, _event: Dictionary) -> void: assert(false, "numeric coordinator must not replay on Main")
	func dispatch_original_visual_callback(_id: int, _method: StringName, _args: Array) -> void: assert(false, "direct fixture does not run a second residency scheduler")
	func publish_visual_process_qualification(_id: int, _enabled: bool) -> void: assert(false, "direct binding fixture does not install visual processing")

class Clock:
	extends RefCounted
	func owner_thread_id() -> int: return OS.get_thread_caller_id()
	func get_ticks_usec() -> int: return Time.get_ticks_usec()
	func get_ticks_msec() -> int: return Time.get_ticks_msec()
	func get_process_frames() -> int: return Engine.get_process_frames()
	func get_setting(key: String, default: Variant) -> Variant: return ProjectSettings.get_setting(key, default)
	func tree_is_paused() -> bool: return false
	func timing_start() -> int: return Time.get_ticks_usec()
	func timing_elapsed_usec(start: int) -> int: return Time.get_ticks_usec() - start
	func record_performance_max(_key: StringName, _value: float) -> void: pass # Diagnostic-only fixture.

class Scopes:
	extends RefCounted
	func owner_thread_id() -> int: return OS.get_thread_caller_id()
	func capture(value: Object) -> WeakRef: return weakref(value)
	func resolve(value: WeakRef) -> Object: return value.get_ref()
	func present(value: Object) -> bool: return is_instance_valid(value)
	func queued(_value: Object) -> bool: return false
	func inside(_value: Object) -> bool: return true
	func can_process(_value: Object) -> bool: return true
	func physics_enabled(_value: Object) -> bool: return true
	func process_enabled(_value: Object) -> bool: return true

class Registry:
	extends RefCounted
	var handle: Object
	var queued := false
	func owner_thread_id() -> int: return OS.get_thread_caller_id()
	func resolve_service(id: int) -> Object: return handle if handle != null and id == handle.get_instance_id() else null
	func service_qualification(id: int) -> Dictionary:
		return {"present": resolve_service(id) != null, "queued_for_retirement": queued}

class Visual:
	extends RefCounted
	var handle: Object
	var polls := 0
	func owner_thread_id() -> int: return OS.get_thread_caller_id()
	func source_object_id() -> int: return handle.get_instance_id()
	func streaming_residency_poll(_msec: int) -> void: polls += 1

class DirectTransport:
	extends RefCounted
	var main: RefCounted
	var exchanges := 0
	var ports: RefCounted
	var renderer: Node2D
	var receipts: Array[Dictionary] = []
	var get_replay_matches := true
	func owner_thread_id() -> int: return OS.get_thread_caller_id()
	func capabilities() -> Dictionary:
		# Valid solely because this direct fixture is synchronous on Main and
		# retains one synchronous stack on Main. It must never install on S.
		assert(OS.get_thread_caller_id() == OS.get_main_thread_id())
		return {"original_point_continuation": true, "explicit_observation_process_epoch": true,
			"exclusive_same_epoch_budget": true, "ordered_main_prefix": true,
			"deadline_preserves_continuation": true, "abort_owner_on_failure": true, "bridge_generation": 1}
	func ordered_main_prefix() -> int: return ports._event_sequence if ports != null else 0
	func exchange_original_primitive(request: Dictionary) -> Dictionary:
		exchanges += 1
		if ports != null:
			for event: Dictionary in ports.take_events(): renderer.apply_event(event)
		var reply: Dictionary = main.execute_original_primitive(request)
		if request.operation == &"load_threaded_get":
			get_replay_matches = get_replay_matches and main.execute_original_primitive(request) == reply
		receipts.append(reply)
		return reply

func source_site(callback: String) -> Dictionary:
	entry_ordinal += 1
	return {"clock_epoch": Engine.get_process_frames(), "domain": &"P", "entry_id": callback,
		"entry_ordinal": entry_ordinal, "bootstrap": false, "observation_process_epoch": Engine.get_process_frames(),
		"world_context": 1, "deadline_usec": Time.get_ticks_usec() + 20000000}

func check(ok: bool, label: String) -> void:
	proof.record(ok, label)
	if not ok:
		failures += 1
		push_error(label)

func fatal(reason: String) -> void:
	fatal_messages.append(reason)

func ticket_valid(_ticket: Dictionary, _purpose: StringName) -> bool:
	return OS.get_thread_caller_id() == OS.get_main_thread_id()

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	check(ClassDB.class_exists("HardCoreResourceObservation"), "required explicit-epoch native status API exists (missing is RED)")
	if not ClassDB.class_exists("HardCoreResourceObservation"):
		_finish()
		return
	var observer: Object = ClassDB.instantiate("HardCoreResourceObservation")
	var main := MainPrimitives.new()
	check(main.configure_main(ticket_valid, observer, 1), "Main primitive executor configures with exact native API")
	var catalog: Dictionary = main.capture_catalog(PackedInt32Array([19]))
	var mapping: Dictionary = catalog.mappings["19"]
	check(not mapping.is_empty(), "real canonical monster 19 mapping published")
	if mapping.is_empty():
		_finish()
		return
	var clock := Clock.new()
	var scopes := Scopes.new()
	var budget := Budget.new()
	check(budget.configure_owner({"Engine": clock, "Time": clock, "ProjectSettings": clock, "phase": clock}, scopes), "one original owner FrameBudget configured")
	check(budget.configure_resource_continuations(fatal), "same original ledger installs external segment exclusion")
	# Large direct-test cap isolates policy correctness from machine speed. The
	# production default is unchanged. A zero-cap assertion below tests denial.
	budget.configure_for_tests(100000000, clock.get_process_frames, clock.get_ticks_usec)
	var transport := DirectTransport.new()
	transport.main = main
	var primitives := Primitives.new()
	check(primitives.configure_owner(catalog, transport, budget, clock, fatal), "actual resource protocol endpoint configured")
	var registry := Registry.new()
	registry.handle = Object.new()
	var visual := Visual.new()
	visual.handle = registry.handle
	var owner := Coordinator.new()
	check(owner.configure_owner({"FrameBudget": budget, "Time": clock, "RuntimeDiagnostics": clock,
		"services": registry, "primitives": primitives}, clock, fatal, true), "numeric coordinator configures only with explicit Main direct-test exemption")
	var key: String = owner._client_resource_cache_key(mapping)
	owner.register_visual(visual, 101, 1, 0, key, {}, 1)
	check(owner.visual_resource_state(visual) == "registered", "registration is R, not a demand")
	check(owner.declare_visual_need(visual.source_object_id(), key, 0), "canonical visual enters W")
	check(primitives.begin_original_phase(source_site("direct.request_client_profile/P_GROUP")), "cold request continuation begins")
	owner.request_client_profile(mapping, 19, 0)
	check(owner.threaded_texture_request_count() == 5, "five real action requests accepted")
	check(main.execute_original_primitive(main._last_request) == main._last_reply, "duplicate transport delivery returns same receipt without resubmission")
	var accepted := 0
	for count: int in main.ownership_receipt().accepted_claims.values(): accepted += count
	check(accepted == 5, "native claim ownership remains five after replay")
	check(primitives.finish_original_phase(), "request phase consumed no guessed status")
	var ordered: Array[String] = []
	for action: String in owner.ACTIONS: ordered.append(str(mapping.actions[action].path))
	var deadline := Time.get_ticks_msec() + 20000
	var all_loaded := false
	while Time.get_ticks_msec() < deadline:
		all_loaded = true
		for path: String in ordered:
			if ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_LOADED: all_loaded = false
		if all_loaded: break
		await get_tree().process_frame
	check(all_loaded, "actual threaded action loads reach terminal before test deadline")
	if not all_loaded:
		# Keep failure visible; do not fake terminal state or call a blocking get.
		_finish()
		return
	var late_site := source_site("direct.actual_late_status/P_GROUP")
	late_site.deadline_usec = Time.get_ticks_usec() - 1
	check(primitives.begin_original_phase(late_site), "expired transport deadline remains original source continuation")
	var late_status := primitives.load_threaded_get_status(ordered[0])
	check(late_status == int(main._last_reply.result) and late_status in [0, 1, 2, 3] and primitives.deadline_fail_count == 1 and primitives.deadline_failures[0].status == &"FAIL", "late actual result is retained with deadline FAIL, never replaced with invented loader state")
	check(primitives.finish_original_phase() and not budget.resource_external_segment_active(), "late real receipt resumes and settles the same original stack")
	check(primitives.begin_original_phase(source_site("GameRoot._process/P_GROUP")), "actual source status calls begin without pre-read publication")
	owner.poll_once(Engine.get_process_frames())
	check(primitives.finish_original_phase(), "all actual resource calls resume their original stack")
	var actual_status_receipts := 0
	var observed_resource_wall := 0
	for receipt: Dictionary in transport.receipts:
		if receipt.request.operation == &"status":
			actual_status_receipts += 1
			check(receipt.native_observation.ok and receipt.native_observation.observation_process_epoch == receipt.request.site.observation_process_epoch and receipt.native_observation.bridge_generation == 1, "native receipt carries exact source P observation epoch and bridge incarnation")
		if not receipt.request.budget.scopes.is_empty(): observed_resource_wall += int(receipt.finished_usec) - int(receipt.started_usec)
	check(actual_status_receipts >= 5, "unconsumed action statuses observed at actual original calls")
	check(budget.snapshot().spent_usec >= observed_resource_wall and not budget.resource_external_segment_active(), "original scope wall includes actual resource service without double ledger or unsettled continuation")
	check(owner.threaded_texture_get_count() == 5 and main.ownership_receipt().accepted_claims.is_empty(), "five native claims consumed exactly once")
	check(transport.get_replay_matches, "duplicate GET delivery returns exact receipt and never consumes another native claim")
	check(main.ownership_receipt().escrow_count == 0, "collecting local escrow closed after profile admission")
	check(owner.pending_request_count() == 0 and owner.waiting_visual_count_for_resource(key) == 1, "loaded profile remains W-protected until actual apply")
	var polls: int = owner.heavy_poll_execution_count
	owner.poll_once(Engine.get_process_frames())
	check(owner.heavy_poll_execution_count == polls, "same P epoch dedup remains exact")
	check(primitives.begin_original_phase(source_site("direct.original_activation_release_free/P_GROUP")), "binding and destruction use explicit original continuation")
	var before_exchanges := transport.exchanges
	var profile: Dictionary = owner.request_visual_resources(visual, mapping, 19, true)
	check(not profile.is_empty() and transport.exchanges == before_exchanges, "hot request is fully local and issues no Main exchange")
	var render_actor := Node2D.new()
	add_child(render_actor)
	var renderer := Renderer.new()
	render_actor.add_child(renderer)
	var texture_publication := Publication.new()
	check(texture_publication.configure_primitive_owner(main), "renderer texture lookup uses actual held Main resource")
	var render_bridge := RenderBridge.new()
	check(renderer.configure_main(render_actor, visual.source_object_id(), texture_publication, render_bridge), "actual renderer binds canonical visual service")
	check(main.register_renderer(visual.source_object_id(), renderer), "resource binding registry maps actual renderer")
	var ports := VisualPorts.new()
	check(ports.configure_owner({"appearances": {}, "source_profiles": {}, "direction_offsets": {}, "ground_contact": {}, "manual_alignment": {}, "overhead": {}}, fatal), "binding fixture configures only unused numeric catalog tables")
	check(ports.configure_streaming_bindings(primitives, owner), "visual ports use single numeric coordinator and actual binding protocol")
	transport.ports = ports
	transport.renderer = renderer
	ports.emit_visual(visual.source_object_id(), &"visual_visible", [false])
	ports.emit_visual(visual.source_object_id(), &"visual_create_body_sprite", [])
	check(not ports.confirmed_uses_final_art(visual.source_object_id(), {}), "cold final-art uses actual absent texture")
	owner.bind_visual_profile(visual.source_object_id(), profile)
	ports.emit_visual(visual.source_object_id(), &"visual_visible", [true])
	ports.emit_visual(visual.source_object_id(), &"sprite_texture", [profile.idle])
	check(renderer.sprite.texture.get_instance_id() == profile.idle and ports.confirmed_uses_final_art(visual.source_object_id(), profile), "true final-art requires actual Sprite binding and visible receipt")
	before_exchanges = transport.exchanges
	ports.emit_visual(visual.source_object_id(), &"sprite_texture", [profile.death])
	check(ports.confirmed_uses_final_art(visual.source_object_id(), profile) and transport.exchanges == before_exchanges, "same held profile nonnull transition preserves stable final-art without RPC")
	check(owner.notify_visual_applied(visual.source_object_id(), key, 0), "fully applied profile moves W to L")
	check(owner.notify_visual_applied(visual.source_object_id(), key, 0) and owner.resource_apply_count == 1, "duplicate apply cannot add a second lease")
	var oracle := Original.new()
	var oracle_visual := Node.new()
	oracle.register_visual(oracle_visual, 101, 1, 0, key, {}, 1)
	oracle.declare_visual_need(oracle_visual.get_instance_id(), key, 0)
	var actual_profile := profile.duplicate(true)
	for action: String in owner.ACTIONS:
		actual_profile[action] = main.texture_for_renderer(int(profile[action]))
		check(actual_profile[action].get_instance_id() == profile[action], "exact native texture identity preserved: " + action)
	oracle.retain_client_resource_profile(key, actual_profile)
	oracle.notify_visual_applied(oracle_visual, key, 0)
	check(owner.cached_client_profile_decoded_rgba8_bytes() == oracle.cached_client_profile_decoded_rgba8_bytes(), "original decoded RGBA8 accounting equals token profile")
	check(owner.leased_profile_count() == oracle.leased_profile_count() and owner.leased_visual_count() == oracle.leased_visual_count(), "original lease cardinality equals migrated coordinator")
	check(owner.protected_overbudget_bytes() == oracle.protected_overbudget_bytes(), "original protected-overbudget policy preserved")
	owner.release_visual_resource(visual.source_object_id(), key)
	oracle.release_visual_resource(oracle_visual, key)
	check(owner.cached_client_profile_count() == oracle.cached_client_profile_count(), "release uses original immediate eviction policy")
	check(owner.cached_client_profile_decoded_rgba8_bytes() == oracle.cached_client_profile_decoded_rgba8_bytes(), "post-release byte accounting matches original")
	ports.emit_visual(visual.source_object_id(), &"visual_visible", [false])
	check(renderer.sprite.texture.get_instance_id() == profile.death and not ports.confirmed_uses_final_art(visual.source_object_id(), profile), "next binding receipt applies earlier texture journal prefix then actual visibility")
	ports.emit_visual(visual.source_object_id(), &"sprite_texture", [null])
	owner.bind_visual_profile(visual.source_object_id(), {})
	check(renderer.sprite.texture == null and not ports.confirmed_uses_final_art(visual.source_object_id(), {}), "clear profile releases actual texture before stable cold fact")
	# Original object destruction, not unregister, ends active profile lifetime.
	render_actor.free()
	transport.renderer = null
	owner.finish_visual_resources_at_original_free(visual.source_object_id())
	owner.unregister_visual(visual.source_object_id())
	oracle.unregister_visual(oracle_visual.get_instance_id())
	check(owner.registered_visual_count() == oracle.registered_visual_count(), "unregister cleans matching subscriptions")
	budget.configure_for_tests(0, clock.get_process_frames, clock.get_ticks_usec)
	owner._last_streaming_poll_frame = -1
	owner.poll_once(Engine.get_process_frames())
	check(owner.heavy_poll_execution_count == polls, "original zero budget denies heavy poll without fake progress")
	check(owner.finish_owner(), "explicit original owner destruction boundary retires cleanly")
	check(main.ownership_receipt().texture_count == 0 and main.ownership_receipt().root_count == 0, "Main primitive slots do not retain a second cache")
	check(primitives.finish_original_phase(), "final mapped continuation settles once")
	check(main.close_generation({"direct_main_fixture": true}).ok, "native observation generation retires only after actual roots/renderers/claims finish")
	check(main.close_generation({"direct_main_fixture": true}).already_closed, "generation close is idempotent without another resource operation")
	check(fatal_messages.is_empty(), "no unknown publication/identity/phase was accepted")
	oracle_visual.free()
	registry.handle.free()
	registry.handle = null
	if not observer is RefCounted: observer.free()
	_finish()

func _finish() -> void:
	if not proof.write_receipt("enemy_owner_streaming_direct_test", proof.records.size(), failures): failures += 1
	print("ENEMY_OWNER_STREAMING_DIRECT_%s" % ("PASS" if failures == 0 else "FAIL"))
	get_tree().quit(0 if failures == 0 else 1)
