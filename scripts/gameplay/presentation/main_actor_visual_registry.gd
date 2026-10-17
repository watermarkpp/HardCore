extends RefCounted

const Contract := preload("res://scripts/gameplay/presentation/actor_visual_projection_contract.gd")
const Shell := preload("res://scripts/gameplay/presentation/actor_main_visual_shell.gd")
var _root: Node2D
var _world: Dictionary
var _validator: RefCounted
var _phase_bridge: RefCounted
var _actors: Dictionary = {}
var _retiring: Dictionary = {}
var _player_id := 0
var _prepared_player_shell: Node2D
var _prepared_player_receipt: Dictionary = {}
var _failure: Dictionary = {}
var _header_prefix_consumer: WeakRef
var _header_resources: RefCounted
var _player_input_template: Dictionary
var _player_input_loading: RefCounted
var _loot_registry: RefCounted

func configure_main(root: Node2D, world: Dictionary, actual_publication_validator: RefCounted,
	actual_enemy_phase_bridge: RefCounted) -> bool:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _root != null or root == null or not root.is_inside_tree() or root.get_instance_id() != world.get("world_runtime_id"): return false
	for specification: Array in [[actual_publication_validator,["verify_actual_original_actor_publication"]],
		[actual_enemy_phase_bridge,["publish_visual_process_qualification"]]]:
		if specification[0] == null: return false
		for method: String in specification[1]:
			if not specification[0].has_method(method): return false
	_root = root; _world = world.duplicate(true); _validator = actual_publication_validator
	_phase_bridge = actual_enemy_phase_bridge
	return true

func owner_thread_id() -> int: return OS.get_main_thread_id()
func _main() -> bool: return OS.get_thread_caller_id() == OS.get_main_thread_id() and _root != null
func _fail(error: String) -> Dictionary:
	_failure = {"success":false,"status":"MISSING","error":error}
	return _failure
func failure() -> Dictionary: return _failure.duplicate(true)

func _valid_publication(publication: Dictionary) -> bool:
	if not _main() or not _failure.is_empty() or not Contract.validate_presentation(publication) or publication.identity.world != _world: return false
	if _header_prefix_consumer != null:
		if _header_prefix_consumer.get_ref() == null: return false
		var current: Dictionary = _header_prefix_consumer.get_ref().actual_current_original_event()
		if current.get("kind") == "original_world_presentation" and current.get("operation") == &"actor_visual_projection":
			return current.get("arguments") is Array and current.arguments.size() == 1 and current.arguments[0] == publication
		return current.get("payload") is Dictionary and current.payload.get("visual_projection") == publication
	if _validator == null: return false
	var proof: Dictionary = _validator.verify_actual_original_actor_publication(publication)
	return proof.get("success") == true and proof.get("identity") == publication.identity and proof.get("publication") == publication

func create_original_actor_view(publication: Dictionary, assets: RefCounted) -> Dictionary:
	return _bind_original_actor_view(publication,assets,null)

func prepare_original_player_shell() -> Dictionary:
	if not _main() or not _failure.is_empty() or _prepared_player_shell != null or _player_id != 0: return _fail("prepared_player_shell_state_conflict")
	_prepared_player_shell = Shell.new()
	_prepared_player_shell.name = "PlayerCharacter"
	_prepared_player_shell.set_process(false); _prepared_player_shell.set_physics_process(false)
	_prepared_player_shell.set_process_input(false); _prepared_player_shell.set_process_unhandled_input(false)
	_root.add_child(_prepared_player_shell)
	_prepared_player_receipt = {"contract_id":"hardcore.actor.prepared_player_shell.v1","world_context":_world,"renderer_registry_id":get_instance_id(),"actual_node_id":_prepared_player_shell.get_instance_id()}
	return {"success":true,"view":_prepared_player_shell,"prepared_shell":_prepared_player_receipt.duplicate(true)}

func actual_original_prepared_player_shell(world: Dictionary) -> Node2D:
	if not _main() or world != _world or not is_instance_valid(_prepared_player_shell): return null
	return _prepared_player_shell

func bind_original_prepared_player_view(publication: Dictionary, assets: RefCounted) -> Dictionary:
	if not _main() or publication.get("kind") != "player" or not is_instance_valid(_prepared_player_shell) or _prepared_player_shell.get_instance_id() != _prepared_player_receipt.get("actual_node_id"): return _fail("actual_prepared_player_shell_missing")
	return _bind_original_actor_view(publication,assets,_prepared_player_shell)

func configure_original_player_input_template(loading: RefCounted, template: Dictionary) -> bool:
	if not _main() or _header_resources == null or _header_prefix_consumer == null or _player_input_loading != null or loading == null or template.get("success") != true or template.get("phase") != "INPUTS_PINNED" or template.get("world_context") != _world or not template.get("template_key") is String: return false
	if loading.verify_actual_original_loading_scope(template.get("loading_scope",{})).get("success") != true: return false
	var ledger: Variant = _header_resources.get("_actor_assets")
	if not ledger is RefCounted or not ledger.get("_templates").has(template.template_key) or ledger._template_receipt(template.template_key) != template: return false
	_player_input_loading = loading; _player_input_template = template.duplicate(true)
	return true

func ensure_original_player_presentation(publication: Dictionary) -> bool:
	if not _valid_publication(publication) or publication.kind != "player":
		if _failure.is_empty(): _fail("actual_Player_current_Source_publication_required")
		return false
	var id: int = publication.identity.runtime_id
	if _actors.has(id): return true
	if _player_input_loading == null or _header_resources == null or _player_id != 0:
		_fail("actual_Player_prepared_input_owners_required")
		return false
	# The first accepted descriptor is the actual original life-zero birth.
	# Later transition/arrival identities must rehome this same row and Node.
	if publication.contract_id != Contract.PREMAP_PLAYER_CONTRACT or publication.identity.life_generation != 0:
		_fail("actual_Player_original_birth_display_contract_required")
		return false
	var owner := {"contract_id":"hardcore.actor.renderer_owner.v1","actor_identity":publication.identity,"renderer_registry_id":get_instance_id(),"kind":"player"}
	var scope: Dictionary = _player_input_template.loading_scope
	var bound: Dictionary = _header_resources.bind_original_actor_renderer_inputs(owner,_player_input_template.template_key,scope)
	if bound.get("success") != true:
		_fail("actual_Player_renderer_inputs_rejected:"+str(bound.get("error","unspecified")))
		return false
	var assets := preload("res://scripts/gameplay/presentation/actor_main_asset_port.gd").new()
	if not assets.configure_main(_header_resources,_player_input_loading,owner,scope):
		_fail("actual_Player_asset_port_configuration_rejected")
		return false
	return bind_original_prepared_player_view(publication,assets).get("success") == true

func _bind_original_actor_view(publication: Dictionary, assets: RefCounted, prepared: Node2D) -> Dictionary:
	if not _valid_publication(publication) or assets == null or not assets.is_actual_loading_bound(): return _fail("actual_actor_Source_publication_and_Loading_pin_required")
	var id: int = publication.identity.runtime_id
	var expected_owner: Dictionary = {"contract_id":"hardcore.actor.renderer_owner.v1","actor_identity":publication.identity,"renderer_registry_id":get_instance_id(),"kind":publication.kind}
	var structural: Dictionary = _actors.get(id,{})
	var reuse_header: bool = publication.kind == "enemy" and structural.get("structural_only") == true
	if (_actors.has(id) and not reuse_header) or _retiring.has(id) or assets.owner_descriptor() != expected_owner or (publication.kind == "player" and _player_id != 0): return _fail("actor_identity_or_actual_renderer_pin_owner_conflict")
	if reuse_header:
		if structural.identity != publication.identity or structural.visual_header.is_empty() or structural.visual_header.visual_service_id != publication.enemy_visual.service_id: return _fail("actual_enemy_header_full_binding_identity_conflict")
		prepared = structural.view
	publication = Contract.capture(publication)
	var view: Node2D = Shell.new() if prepared == null else prepared
	if not view.configure_main(publication,assets,_phase_bridge):
		_actors[id] = {"view":view,"assets":assets,"identity":publication.identity,"last":publication,"retire_required":true}
		return _fail("actual_actor_projection_configuration_failed")
	# No legacy CharacterBody is created, nor are gameplay/input callbacks
	# disabled on such a body. This object is physically a pure Node2D.
	if prepared == null: _root.add_child(view)
	if publication.kind == "player" and not view.visual.actual_render_binding_ok():
		_actors[id] = {"view":view,"assets":assets,"identity":publication.identity,"last":publication,"retire_required":true}
		return _fail("actual_player_render_pin_failed_after_Node_admission")
	if publication.kind == "player" and (not assets.has_method("bind_actual_original_instance") or not assets.bind_actual_original_instance(view)):
		_actors[id] = {"view":view,"assets":assets,"identity":publication.identity,"last":publication,"retire_required":true}
		return _fail("actual_player_instance_resource_binding_unproved")
	_actors[id] = {"view":view,"assets":assets,"identity":publication.identity,"last":publication,"last_actor_fact":{},"last_enemy_event":{},"last_advance_source_process_frame":publication.source_process_frame if publication.advance_visual else -1}
	if reuse_header:
		_actors[id].actor_header = structural.actor_header
		_actors[id].visual_header = structural.visual_header
		_actors[id].kind = "enemy"
	if publication.kind == "player": _player_id = id
	return {"success":true,"view":view,"identity":publication.identity,"renderer_node_id":view.get_instance_id()}

func apply_source_projection(publication: Dictionary) -> bool:
	if not _valid_publication(publication): return false
	var id: int = publication.identity.runtime_id
	if not _actors.has(id) or _retiring.has(id): return false
	var row: Dictionary = _actors[id]
	if row.get("structural_only") == true: return false # MISSING genuine complete asset/binding caller
	if publication.publication_sequence == row.last.publication_sequence: return publication == row.last
	if publication.publication_sequence != row.last.publication_sequence + 1 or publication.source_process_frame < row.last.source_process_frame or publication.clock_epoch < row.last.clock_epoch: return false
	if publication.advance_visual and publication.source_process_frame <= row.last_advance_source_process_frame: return false
	if row.identity != publication.identity:
		# Consume the actual authenticated Source transition, including repeated
		# original begin_combat_transition calls before the next map arrival.
		# Sequence checks precede any identity/pin mutation; no generation is
		# invented and no formal ActorRef or premap contract is relaxed.
		if id != _player_id or row.identity.world != publication.identity.world or publication.identity.life_generation <= row.identity.life_generation or not _rehome_actual_player_identity(publication.identity,{}): return false
	publication = Contract.capture(publication)
	if not row.view.apply_source_publication(publication): return false
	row.last = publication
	if publication.advance_visual: row.last_advance_source_process_frame = publication.source_process_frame
	return true

func _rehome_actual_player_identity(identity: Dictionary, transaction: Dictionary) -> bool:
	if not _main() or _player_id == 0 or not _actors.has(_player_id) or _retiring.has(_player_id) or identity.get("runtime_id") != _player_id: return false
	var row: Dictionary = _actors[_player_id]
	var before: Dictionary = row.identity
	var accepted: Dictionary = row.assets.rehome_actual_original_player_identity(identity,transaction)
	if accepted.get("success") != true or accepted.get("actual_instance_id") != row.view.get_instance_id(): return false
	if not row.view.accept_actual_original_player_identity_rehome(before,identity): return false
	row.identity = identity.duplicate(true)
	return row.assets.finish_actual_original_player_identity_rehome(accepted.before,row.view)

func can_commit_actual_original_map_arrival(transaction: Dictionary) -> bool:
	if not _main() or not _failure.is_empty() or _header_prefix_consumer == null or _header_prefix_consumer.get_ref() == null or transaction.get("before_world") != _world or transaction.get("player_runtime_id") != _player_id or not _actors.has(_player_id) or _retiring.has(_player_id): return false
	if not _world_retirement.is_empty() or _loot_registry!=null and not _loot_registry.can_commit_empty_world(transaction.get("before_world",{}),transaction.get("after_world",{})): return false
	if _enemy_effect_registry!=null and not _enemy_effect_registry.can_commit_empty_world(transaction.get("before_world",{}),transaction.get("after_world",{})): return false
	var prefix: RefCounted = _header_prefix_consumer.get_ref()
	var event: Dictionary = prefix.actual_current_original_event()
	if event.get("operation") != &"source_map_arrival" or event.get("arguments") != [transaction] or not prefix.get("_host").verify_committed_original_map_arrival(transaction): return false
	for id: int in _actors:
		if id != _player_id and not _retiring.has(id): return false
	var row: Dictionary = _actors[_player_id]
	var identity: Variant = transaction.get("player_identity")
	return transaction.get("contract_id") == "hardcore.source.map_arrival.v2" and identity is Dictionary and Contract.valid_identity(identity) and identity.world == transaction.get("after_world") and identity.runtime_id == _player_id and identity.life_generation >= row.identity.life_generation and row.identity.world == _world and row.view.get("_identity") == row.identity and row.assets.owner_descriptor().actor_identity == row.identity and _phase_bridge.can_commit_actual_original_map_arrival(transaction)

func commit_actual_original_map_arrival(transaction: Dictionary) -> bool:
	if not can_commit_actual_original_map_arrival(transaction): return false
	var identity: Dictionary = transaction.player_identity.duplicate(true)
	if not _rehome_actual_player_identity(identity,transaction): return false
	if not _phase_bridge.commit_actual_original_map_arrival(transaction): return false
	if _loot_registry!=null and not _loot_registry.commit_empty_world(transaction.before_world,transaction.after_world): return false
	if _enemy_effect_registry!=null and not _enemy_effect_registry.commit_empty_world(transaction.before_world,transaction.after_world): return false
	_world = transaction.after_world.duplicate(true)
	# Existing enemy rows retain their old identities and physical retirement
	# debt. Only new publications are admitted against the current world.
	return true

func apply_original_enemy_visual_event(event: Dictionary) -> bool:
	if not _main() or not event.get("arguments") is Array: return false
	for row: Dictionary in _actors.values():
		if row.get("kind",row.last.get("kind","")) == "enemy" and row.view.visual != null and row.view.visual.canonical_service_id == event.get("service_id"):
			if not event.get("sequence") is int or event.sequence <= 0: return false
			if not row.last_enemy_event.is_empty():
				if event.sequence == row.last_enemy_event.sequence: return event == row.last_enemy_event
				if event.sequence < row.last_enemy_event.sequence: return false
			var render_event: Dictionary = event.duplicate(true)
			# The sole original producer already publishes `arguments`.
			# Reinterpreting it as an absent `args` field loses the real payload.
			if not render_event.get("arguments") is Array: return false
			if not row.view.visual.apply_event_checked(render_event): return false
			row.last_enemy_event = event.duplicate(true)
			return true
	return false

func apply_original_enemy_actor_operation(operation: StringName, arguments: Array) -> bool:
	if not _main() or arguments.is_empty() or not arguments[0] is int or not _actors.has(arguments[0]) or _retiring.has(arguments[0]): return false
	var row: Dictionary = _actors[arguments[0]]
	if row.get("kind",row.last.get("kind","")) != "enemy": return false
	var view: Node2D = row.view
	match operation:
		&"enemy_configure_y_sort":
			if arguments.size() != 1: return false
			preload("res://scripts/monster_visual.gd").configure_actor_y_sort_item(view,"actor_root")
		&"enemy_overhead_create":
			if arguments.size() != 5 or not arguments[1] is String or not arguments[2] is bool or not arguments[3] is int or not arguments[4] is int: return false
			return view.create_original_overhead(arguments[1],arguments[2],arguments[3],arguments[4])
		&"enemy_overhead_health":
			if arguments.size() != 3 or view.overhead == null or not arguments[1] is int or not arguments[2] is int: return false
			view.overhead.set_health(arguments[1],arguments[2])
		&"enemy_overhead_anchor_y":
			if arguments.size() != 2 or view.overhead == null or not arguments[1] is float or not is_finite(arguments[1]): return false
			view.overhead.set_anchor_y(arguments[1])
		&"enemy_overhead_visible":
			if arguments.size() != 2 or view.overhead == null or not arguments[1] is bool: return false
			view.overhead.visible = arguments[1]
		&"enemy_overhead_retire":
			return arguments.size() == 1 and view.retire_original_overhead()
		&"enemy_redraw":
			if arguments.size() != 1: return false
			view.queue_redraw()
		_: return false
	return true

func apply_original_player_presentation_fact(runtime_id: int, actor_ordinal: int, event: String, payload: Dictionary) -> bool:
	if not _main() or not _actors.has(runtime_id) or _retiring.has(runtime_id): return false
	var row: Dictionary = _actors[runtime_id]
	var fact: Dictionary = {"actor_ordinal":actor_ordinal,"event":event,"payload":payload}
	if actor_ordinal <= 0: return false
	if not row.last_actor_fact.is_empty():
		if actor_ordinal == row.last_actor_fact.actor_ordinal: return fact == row.last_actor_fact
		if actor_ordinal < row.last_actor_fact.actor_ordinal: return false
	if row.last.kind != "player" or not payload.get("visual_projection") is Dictionary or not apply_source_projection(payload.visual_projection): return false
	if not row.view.apply_original_player_fact(event,payload): return false
	row.last_actor_fact = fact.duplicate(true)
	return true

func apply_original_actor_stealth_event(event: Dictionary) -> bool:
	if not _main() or not _failure.is_empty() or _header_prefix_consumer == null or _header_prefix_consumer.get_ref() == null: return false
	if event.get("kind") != "original_world_presentation" or event.get("operation") != &"set_actor_stealth_alpha" or not event.get("arguments") is Array: return false
	var consumer: RefCounted = _header_prefix_consumer.get_ref()
	if consumer.actual_current_original_event() != event: return false
	var arguments: Array = event.arguments
	if arguments.size() != 3 or not arguments[0] is int or not arguments[1] is bool or not arguments[2] is bool: return false
	var id: int = arguments[0]
	if not _actors.has(id) or _retiring.has(id): return false
	var row: Dictionary = _actors[id]
	if row.get("structural_only") == true or row.get("identity",{}).get("world") != _world: return false
	var view: Node2D = row.view
	if not is_instance_valid(view) or view.get_parent() != _root or not view.is_inside_tree() or view.is_queued_for_deletion(): return false
	# The Source caller distinguishes its actual SummonActor before encoding.
	# Main owns pure display shells, so its Node class cannot recover that fact.
	if arguments[2]:
		if id == _player_id: return false
		view.modulate.a = 1.0
		_root._stealth_alpha_restore.erase(view.get_instance_id())
	else:
		if id != _player_id: return false
		# Reuse the original Main-only fade/cache/restore behavior. The actual
		# pre-map player display may have life=0; no combat ActorRef is minted.
		_root._set_actor_stealth_alpha(view,arguments[1])
	return true

func actual_original_player_view(world: Dictionary) -> Node2D:
	if not _main() or world != _world or _player_id == 0 or not _actors.has(_player_id): return null
	return _actors[_player_id].view

func resolve_original_actor_attachment(identity: Dictionary) -> Node2D:
	if not _main() or not Contract.valid_identity(identity) or identity.world != _world or not _actors.has(identity.runtime_id) or _retiring.has(identity.runtime_id) or _actors[identity.runtime_id].identity != identity: return null
	if _actors[identity.runtime_id].get("structural_only") == true: return null # No guessed early attachment pose/readiness.
	return _actors[identity.runtime_id].view

func actual_original_audio_projection(identity: Dictionary) -> Dictionary:
	if _main() and Contract.valid_identity(identity) and identity.world == _world and _actors.has(identity.runtime_id) and not _retiring.has(identity.runtime_id):
		var row: Dictionary = _actors[identity.runtime_id]
		var delivered: Dictionary = row.get("actual_audio_delivery",{})
		if row.identity == identity and delivered.get("actor_identity") == identity:
			var actual_root: Node2D = row.view
			if not is_instance_valid(actual_root): return {}
			var source: Dictionary = delivered.source_pose
			return {"actor_identity":identity,"world_context":_world,"runtime_id":identity.runtime_id,"life":identity.life_generation,"kind":"enemy","monster_id":source.monster_id,"present":source.source_present,"inside_tree":source.source_inside_world and actual_root.is_inside_tree(),"queued_for_deletion":source.source_retiring or actual_root.is_queued_for_deletion()}
	var view: Node2D = resolve_original_actor_attachment(identity)
	if view == null: return {}
	if _actors[identity.runtime_id].get("structural_only") == true: return {}
	var publication: Dictionary = _actors[identity.runtime_id].last
	return {"actor_identity":identity,"world_context":_world,"runtime_id":identity.runtime_id,"life":identity.life_generation,
		"kind":publication.kind,"monster_id":publication.actor.monster_id if publication.kind == "enemy" else -1,
		"present":bool(publication.actor.source_present) and is_instance_valid(view),
		"inside_tree":bool(publication.actor.source_inside_world) and view.is_inside_tree(),
		"queued_for_deletion":bool(publication.actor.source_retiring) or view.is_queued_for_deletion()}

func capture_actual_original_audio_delivery(event: Dictionary) -> Dictionary:
	if not _main() or _header_prefix_consumer == null or _header_prefix_consumer.get_ref() == null: return {"status":"INVALID","error":"actual_audio_prefix_owner_required"}
	var prefix: RefCounted = _header_prefix_consumer.get_ref()
	if prefix.actual_current_original_event() != event or event.get("kind") != "original_world_presentation" or event.get("operation") != &"caster_presentation" or not event.get("arguments") is Array or event.arguments.size() != 1 or not event.arguments[0] is Dictionary: return {"status":"INVALID","error":"actual_claimed_audio_event_required"}
	var command: Dictionary = event.arguments[0]
	if command.get("world_context") != _world or command.get("operation") not in ["monster_audio","player_physical_contact_audio"] or not command.get("payload") is Dictionary: return {"status":"INVALID","error":"actual_audio_command_required"}
	var payload: Dictionary = command.payload
	var source: Dictionary = payload.get("source_pose",{})
	if not preload("res://scripts/gameplay/world/world_audio_source_contract.gd").accepts(source) or source.actor_identity != payload.get("actor_identity") or source.actor_identity.world != _world: return {"status":"INVALID","error":"actual_audio_Source_pose_required"}
	var identity: Dictionary = source.actor_identity
	if not _actors.has(identity.runtime_id): return {"status":"INVALID","error":"actual_audio_ACTOR_HEADER_must_precede_sound"}
	var row: Dictionary = _actors[identity.runtime_id]
	if row.identity != identity or _retiring.has(identity.runtime_id) or not source.source_present or not source.source_inside_world or source.source_retiring:
		return {"status":"REJECTED_STALE_OWNER","requested_identity":identity,"actual_identity":row.identity,"actual_retiring":_retiring.has(identity.runtime_id),"source_pose":source}
	var view: Node2D = row.view
	if row.get("kind",row.get("last",{}).get("kind")) != "enemy" or not is_instance_valid(view) or view.get_parent() != _root or not view.is_inside_tree() or view.is_queued_for_deletion(): return {"status":"INVALID","error":"actual_audio_Main_root_required"}
	# The real display root receives the S pose before its real Canvas is read.
	# Header-only never borrows a later complete sprite/BindingFact.
	view.global_position = source.position_screen_px
	if view.global_position != source.position_screen_px: return {"status":"INVALID","error":"actual_audio_Main_pose_application_failed"}
	var viewport: Viewport = view.get_viewport()
	var observed := {"status":"OBSERVED","actor_identity":identity.duplicate(true),"source_pose":source.duplicate(true),"actual_main_node_id":view.get_instance_id(),"actual_Main_process_frame":Engine.get_process_frames(),"original_journal_ordinal":event.get("ordinal"),"actual_source_site":event.get("source_site"),"visible":view.visible,"visible_in_tree":view.is_visible_in_tree(),"viewport_available":is_instance_valid(viewport),"position_screen_px":view.global_position,"global_transform_with_canvas":view.get_global_transform_with_canvas()}
	if is_instance_valid(viewport): observed.visible_rect = viewport.get_visible_rect()
	row.actual_audio_delivery = observed.duplicate(true)
	return observed

var _world_retirement: Dictionary = {}

func _retiring_row_matches(row: Dictionary, identity: Dictionary) -> bool:
	if row.identity == identity: return true
	# An authenticated Player can retire before its latest life publication.
	# Preserve both actual identities, including the original premap life zero.
	var observed: Dictionary = row.identity
	return row.get("kind",row.get("last",{}).get("kind","")) == "player" and preload("res://scripts/gameplay/world/world_source_application_contract.gd").accepts_retiring_actor(observed) and preload("res://scripts/gameplay/world/world_source_application_contract.gd").accepts_retiring_actor(identity) and observed.world == identity.world and observed.runtime_id == identity.runtime_id and observed.life_generation <= identity.life_generation

func begin_original_actor_retirement(identity: Dictionary) -> bool:
	if not _main() or not preload("res://scripts/gameplay/world/world_source_application_contract.gd").accepts_retiring_actor(identity) or not _actors.has(identity.runtime_id) or not _retiring_row_matches(_actors[identity.runtime_id],identity): return false
	if _retiring.has(identity.runtime_id): return true
	var row: Dictionary = _actors[identity.runtime_id]
	var view: Node2D = row.view
	if not is_instance_valid(view) or not view.is_inside_tree(): return false
	var visual: Variant = view.get("visual")
	var service_id := 0
	var renderer_id := 0
	if row.get("kind",row.get("last",{}).get("kind","")) == "enemy" and is_instance_valid(visual):
		service_id = int(visual.canonical_service_id); renderer_id = visual.get_instance_id()
		if _header_resources == null or service_id <= 0 or not _header_resources.get("_renderers").has(service_id) or _header_resources.get("_renderers")[service_id].get_ref() != visual: return false
	elif row.get("kind",row.get("last",{}).get("kind","")) == "enemy" and not row.get("visual_header",{}).is_empty(): return false
	_retiring[identity.runtime_id] = {"row":row,"requested_identity":identity.duplicate(true),"request_bound":false,"node_id":view.get_instance_id(),"service_id":service_id,"renderer_id":renderer_id,"vault_retire_started":false,"asset_receipt":{},"node_receipt":{}}
	view.queue_free()
	return true

func retire_original_prepared_player_shell() -> bool:
	if not _main() or _player_id != 0: return false
	if is_instance_valid(_prepared_player_shell): _prepared_player_shell.queue_free()
	return true

func service_actual_retirements() -> bool:
	if not _main(): return false
	for id: int in _retiring.keys():
		var pending: Dictionary = _retiring[id]
		if not pending.node_receipt.is_empty() or is_instance_valid(pending.row.view): continue
		if pending.asset_receipt.is_empty():
			if pending.row.assets == null:
				if pending.row.get("structural_only") != true or pending.row.get("actor_header",{}).get("actor_identity") != pending.row.identity: return false
				var ledger: RefCounted = _header_resources.get("_actor_assets") if _header_resources != null else null
				var owned: Dictionary = {}
				if ledger != null:
					for owner: Dictionary in ledger.get("_owners").values():
						if owner.owner.actor_identity.runtime_id != id: continue
						if not owned.is_empty() or owner.owner.actor_identity != pending.row.identity or owner.owner.renderer_registry_id != get_instance_id(): return false
						owned = owner
				if owned.is_empty():
					if pending.vault_retire_started: return false
					pending.asset_receipt = {"structural_only":true,"actual_actor_header":pending.row.actor_header,"actual_physical_pins_released":true,"actual_original_obligations_terminal":true,"actual_absent_asset_owner":true}
				else:
					# A failed full adoption can own real pins before an AssetPort
					# reaches this row. Retire that exact ledger owner and scope.
					if not pending.vault_retire_started:
						var admitted: Dictionary = _header_resources.begin_original_actor_renderer_retirement(owned.owner,owned.scope)
						if admitted.get("status") not in ["PENDING","READY"]: return false
						pending.vault_retire_started = true
					var retired: Dictionary = _header_resources.poll_original_actor_renderer_retirement(owned.owner,owned.scope)
					if retired.get("status") == "PENDING": continue
					if retired.get("status") != "READY": return false
					pending.asset_receipt = retired.duplicate(true); pending.asset_receipt.structural_only = true
			else:
				if not pending.vault_retire_started:
					var started: Dictionary = pending.row.assets.begin_actual_retirement()
					if started.get("status") not in ["PENDING","READY"]: return false
					pending.vault_retire_started = true
				var actual: Dictionary = pending.row.assets.poll_actual_retirement()
				if actual.get("status") == "PENDING": continue
				if actual.get("status") != "READY": return false
				pending.asset_receipt = actual.duplicate(true)
		pending.node_receipt = {"success":true,"status":"READY","contract_id":"hardcore.main.actor_view_free.v1","actor_identity":pending.requested_identity,"actual_presented_identity":pending.row.identity,"world":pending.requested_identity.world,"runtime_id":id,"service_id":pending.service_id,"actual_registry_id":get_instance_id(),"actual_node_id":pending.node_id,"actual_renderer_id":pending.renderer_id,"actual_node_absent":true,"actual_assets":pending.asset_receipt,"renderer_registration_retired":false,"metadata_released":false,"actual_Main_process_frame":Engine.get_process_frames()}
	return true

func _actual_renderer_registration_retired(pending: Dictionary) -> bool:
	if pending.service_id == 0: return pending.renderer_id == 0
	if pending.renderer_id <= 0 or _header_resources == null: return false
	var id: int = pending.service_id
	return not _header_resources.get("_renderers").has(id) and not _header_resources.get("_visual_profiles").has(id) and not _header_resources.get("_profile_identities").has(id) and not _header_resources.get("_binding_versions").has(id) and not _header_resources.get("_binding_mutations").has(id) and not _header_resources.get("_texture_roots").has("visual_profile:%d" % id)

func capture_original_actor_free_state(identity: Dictionary) -> Dictionary:
	if not begin_original_actor_retirement(identity): return {"success":false,"status":"INVALID","error":"actual_known_actor_retirement_required"}
	var id: int = identity.runtime_id
	var pending: Dictionary = _retiring[id]
	if pending.request_bound and pending.requested_identity != identity: return {"success":false,"status":"INVALID","error":"actual_retirement_request_changed"}
	if not pending.request_bound:
		pending.request_bound = true; pending.requested_identity = identity.duplicate(true)
		if not pending.node_receipt.is_empty():
			pending.node_receipt = pending.node_receipt.duplicate(true)
			pending.node_receipt.actor_identity = identity.duplicate(true); pending.node_receipt.world = identity.world
	if not service_actual_retirements(): return {"success":false,"status":"INVALID","error":"actual_actor_assets_retirement_failed"}
	if pending.node_receipt.is_empty(): return {"success":true,"status":"PENDING","actor_identity":identity}
	if not _actual_renderer_registration_retired(pending): return pending.node_receipt.duplicate(true)
	# The original S final-free retires the actual visual binding. Its second
	# admitted observation receives the facts before these active rows disappear.
	var final: Dictionary = pending.node_receipt.duplicate(true)
	final.renderer_registration_retired = true; final.metadata_released = true
	_actors.erase(id); _retiring.erase(id)
	if _player_id == id: _player_id = 0
	return final

func capture_original_world_exit_state(world: Dictionary) -> Dictionary:
	if not _main() or world != _world: return {"success":false,"status":"INVALID"}
	if _world_retirement.is_empty():
		var identities: Array = []
		for row: Dictionary in _actors.values(): identities.append(row.identity.duplicate(true))
		_world_retirement = {"world":world.duplicate(true),"identities":identities,"receipt":{}}
		for identity: Dictionary in identities:
			if not begin_original_actor_retirement(identity): return {"success":false,"status":"INVALID"}
		if _player_id == 0 and not retire_original_prepared_player_shell(): return {"success":false,"status":"INVALID"}
	if _enemy_effect_registry!=null:
		var effect_exit: Dictionary=_enemy_effect_registry.capture_actual_world_exit(world)
		if effect_exit.get("success")!=true or effect_exit.get("status")!="READY": return effect_exit
		_world_retirement.actual_enemy_effect_exit=effect_exit
	if _loot_registry!=null:
		var loot_exit: Dictionary=_loot_registry.capture_actual_world_exit(world)
		if loot_exit.get("success")!=true or loot_exit.get("status")!="READY": return loot_exit
		_world_retirement.actual_loot_exit=loot_exit
	if not _world_retirement.receipt.is_empty(): return _world_retirement.receipt
	if not service_actual_retirements(): return {"success":false,"status":"INVALID"}
	var facts: Array = []
	for identity: Dictionary in _world_retirement.identities:
		if not _retiring.has(identity.runtime_id): return {"success":false,"status":"INVALID","error":"actual_world_actor_fact_missing"}
		var pending: Dictionary = _retiring[identity.runtime_id]
		if pending.node_receipt.is_empty(): return {"success":true,"status":"PENDING"}
		facts.append(pending.node_receipt.duplicate(true))
	if is_instance_valid(_prepared_player_shell): return {"success":true,"status":"PENDING"}
	_world_retirement.receipt = {"success":true,"status":"READY","world":world,"actual_original_exit":true,"actual_actor_nodes_absent":true,"actual_enemy_effect_nodes_absent":_enemy_effect_registry==null or _enemy_effect_registry.actual_nodes_absent(),"actual_enemy_effect_exit":_world_retirement.get("actual_enemy_effect_exit",{}),"actual_loot_nodes_absent":_loot_registry==null or _loot_registry.actual_nodes_absent(),"actual_loot_exit":_world_retirement.get("actual_loot_exit",{}),"actual_actor_facts":facts,"actual_prepared_shell_id":_prepared_player_receipt.get("actual_node_id",0),"actual_prepared_shell_absent":not is_instance_valid(_prepared_player_shell),"actual_registry_id":get_instance_id(),"actual_Main_process_frame":Engine.get_process_frames()}
	return _world_retirement.receipt

func has_accepted_original_retirement(operation: String, arguments: Array) -> bool:
	if not _main() or arguments.size() != 1: return false
	if operation == "world_view_exit_state": return not _world_retirement.is_empty() and arguments[0] == _world_retirement.world
	return operation == "actor_view_free_state" and arguments[0] is Dictionary and _retiring.has(arguments[0].get("runtime_id")) and _retiring[arguments[0].runtime_id].requested_identity == arguments[0]

func actual_world_views_retired(world: Dictionary) -> bool:
	return _main() and world == _world and not _world_retirement.is_empty() and not _world_retirement.receipt.is_empty()


const EnemyBirthHeader := preload("res://scripts/gameplay/presentation/enemy_birth_structural_header.gd")
func configure_original_structural_main(root: Node2D, world: Dictionary, actual_phase_bridge: RefCounted) -> bool:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _root != null or root == null or not root.is_inside_tree() or world.size() != 5 or world.get("contract_id") != "hardcore.execution.world_context.v1" or world.get("world_runtime_id") != root.get_instance_id() or not world.get("world_epoch") is int or world.world_epoch < 0 or not world.get("runtime_map_id") is int or not world.get("profile_id") is String or world.profile_id.is_empty(): return false
	if world.runtime_map_id < 0:
		# Only the genuine covered pre-map Root can prepare an unbound pure
		# shell. This does not accept a zero-life ActorRef or activate a map.
		if world.runtime_map_id != -1 or world.world_epoch != 0 or root.get_script() != preload("res://scripts/game_root.gd") or root.get("current_map_id") != -1 or root.get("_zone_generation") != 0: return false
		var attachment: Variant = root.get("_original_source_main_attachment")
		if not attachment is RefCounted or attachment.get_script() != preload("res://scripts/gameplay/world/world_main_root_attachment.gd") or not attachment.get("_root") is WeakRef or attachment.get("_root").get_ref() != root or attachment.get("_ready_entered") != true or attachment.get("_exited") == true: return false
		var transport: RefCounted = attachment.get("_transport")
		if transport == null or transport.get_script() != preload("res://scripts/gameplay/source/main_boot_root_transport.gd") or transport.get("_scope").get("profile_id") != world.profile_id or transport.get("_host") == null or transport.get("_host").status().get("running") == true: return false
	if actual_phase_bridge == null or not actual_phase_bridge.has_method("publish_visual_process_qualification"): return false
	_root = root; _world = world.duplicate(true); _phase_bridge = actual_phase_bridge
	# No full-publication/asset admission follows from this structural route.
	return true

func bind_original_enemy_header_channel(actual_prefix_consumer: RefCounted, actual_resources: RefCounted) -> bool:
	if not _main() or _header_prefix_consumer != null or actual_prefix_consumer == null or actual_prefix_consumer.get_script() != preload("res://scripts/gameplay/world/world_main_prefix_consumer.gd") or actual_resources == null or actual_resources.get_script() != preload("res://scripts/gameplay/enemy/enemy_main_resource_primitives.gd"): return false
	if not actual_prefix_consumer.has_method("actual_current_original_event") or not actual_prefix_consumer.has_method("actual_current_original_prefix") or not actual_resources.has_method("register_renderer") or not actual_resources.has_method("texture_from_token") or actual_resources.get("_configured") != true: return false
	_header_prefix_consumer = weakref(actual_prefix_consumer); _header_resources = actual_resources
	return true

func apply_original_enemy_structural_header(event: Dictionary) -> bool:
	if not _main() or _header_prefix_consumer == null or _header_prefix_consumer.get_ref() == null or event.get("kind") != "original_world_presentation" or not event.get("arguments") is Array or event.arguments.size() != 1 or not event.arguments[0] is Dictionary: return false
	var consumer: RefCounted = _header_prefix_consumer.get_ref()
	var header: Dictionary = event.arguments[0]
	var kind: String = String(event.get("operation",""))
	var prefix: Dictionary = consumer.actual_current_original_prefix()
	if consumer.actual_current_original_event() != event or not EnemyBirthHeader.validate(header,kind) or header.actor_identity.world != _world or event.get("source_site") != header.source_site or event.get("ordinal") != header.sequence or prefix.get("bridge_generation") != header.event_identity.bridge_generation or prefix.get("journal_generation") != header.event_identity.journal_generation or int(prefix.get("through_ordinal",-1)) < header.sequence: return false
	header = EnemyBirthHeader.capture(header)
	var id: int = header.actor_identity.runtime_id
	if kind == "ACTOR_HEADER":
		if _actors.has(id): return _actors[id].get("actor_header",{}) == header
		if _retiring.has(id): return false
		var view: Node2D = Shell.new()
		if not view.prepare_original_enemy_actor_header(header.actor_identity): view.free(); return false
		_root.add_child(view)
		_actors[id] = {"kind":"enemy","structural_only":true,"view":view,"assets":null,"identity":header.actor_identity,
			"actor_header":header,"visual_header":{},"last":{},"last_actor_fact":{},"last_enemy_event":{},"last_advance_source_process_frame":-1}
		return true
	if not _actors.has(id) or _retiring.has(id): return false
	var row: Dictionary = _actors[id]
	if row.identity != header.actor_identity: return false
	if not row.get("visual_header",{}).is_empty(): return row.visual_header == header
	if row.get("structural_only") != true or row.view.visual != null: return false
	if not row.view.prepare_original_enemy_visual_header(header.visual_service_id,_header_resources,_phase_bridge): return false
	# Current real physical primitive now accepts the existing checked API.
	# Registration produces no BindingFact/BirthACK and allocates no sprite.
	if not _header_resources.register_renderer(header.visual_service_id,row.view.visual): return false
	row.visual_header = header
	return true

# Loot uses real cast runtime IDs; it never manufactures an ActorRef/life epoch.
func apply_original_loot_event(event: Dictionary) -> bool:
	if not _main() or not _world_retirement.is_empty() or _header_prefix_consumer==null or _header_prefix_consumer.get_ref()==null: return false
	if _loot_registry==null:
		var registry := preload("res://scripts/gameplay/presentation/main_loot_visual_registry.gd").new()
		if not registry.configure_main(_root,_world,_header_prefix_consumer.get_ref()): return false
		_loot_registry=registry
	return _loot_registry.apply_original_event(event)

var _enemy_effect_registry: RefCounted
func apply_original_enemy_input_pickable_event(event: Dictionary) -> bool:
	if not _main() or _header_prefix_consumer==null or _header_prefix_consumer.get_ref()==null or not _world_retirement.is_empty(): return false
	var consumer: RefCounted=_header_prefix_consumer.get_ref()
	var prefix: Dictionary=consumer.actual_current_original_prefix()
	var args: Variant=event.get("arguments")
	if consumer.actual_current_original_event()!=event or prefix.is_empty() or event.get("kind")!="original_world_presentation" or event.get("operation")!=&"enemy_input_pickable" or event.get("source_site",{}).get("world_context")!=_world or not event.get("ordinal") is int or event.ordinal<=0 or prefix.get("through_ordinal",0)<event.ordinal or not args is Array or args.size()!=2 or not args[0] is int or not args[1] is bool or not _actors.has(args[0]) or _retiring.has(args[0]): return false
	var row: Dictionary=_actors[args[0]]
	if row.get("kind",row.get("last",{}).get("kind"))!="enemy" or row.identity.world!=_world or not is_instance_valid(row.view): return false
	return row.view.apply_original_source_pickable_fact(args[1],event.ordinal)
func apply_original_enemy_effect_event(event: Dictionary) -> Variant:
	if not _main() or not _world_retirement.is_empty() or _header_prefix_consumer==null or _header_prefix_consumer.get_ref()==null: return false
	if _enemy_effect_registry==null:
		var registry:=preload("res://scripts/gameplay/presentation/main_enemy_effect_registry.gd").new()
		if not registry.configure_main(_root,_world,_header_prefix_consumer.get_ref()): return false
		_enemy_effect_registry=registry
	return _enemy_effect_registry.apply_original_event(event)

func prepare_actual_original_map_arrival_effect_exit(transaction: Dictionary) -> bool:
	if not _main() or _header_prefix_consumer==null or _header_prefix_consumer.get_ref()==null: return false
	var consumer: RefCounted=_header_prefix_consumer.get_ref()
	var event: Dictionary=consumer.actual_current_original_event()
	if transaction.get("before_world")!=_world or event.get("kind")!="original_world_presentation" or event.get("operation")!=&"source_map_arrival" or event.get("arguments")!=[transaction] or not consumer.get("_host").verify_committed_original_map_arrival(transaction): return false
	return _enemy_effect_registry==null or _enemy_effect_registry.prepare_actual_map_melee_exit(transaction).get("status")=="READY"
