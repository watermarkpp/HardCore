extends RefCounted

## Leaf owned by the SAME Main caster executor. Source fields are display mirrors.
const NPCShell := preload("res://scripts/gameplay/world/world_npc_visual_shell.gd")
const PortalShell := preload("res://scripts/gameplay/world/world_portal_visual_shell.gd")
const OriginalNPC := preload("res://scripts/npc_actor.gd")
const OriginalVisual := preload("res://scripts/npc_visual.gd")
const OriginalRoot := preload("res://scripts/game_root.gd")
var _root: Node2D
var _executor: WeakRef
var _loading: RefCounted
var _router: RefCounted
var _world: Dictionary
var _proof: Dictionary
var _textures: Dictionary = {}
var _nodes: Dictionary = {}
var _closed := false
func configure_main(root: Node2D,executor: RefCounted,loading: RefCounted,router: RefCounted,world: Dictionary) -> bool:
	if OS.get_thread_caller_id()!=OS.get_main_thread_id() or _root!=null or root==null or not root.is_inside_tree() or executor==null or loading==null or router==null: return false
	if root.global_transform!=Transform2D.IDENTITY: return false # Original GameRoot scene origin; no unpublished parent transform.
	if loading.get_script()!=preload("res://scripts/gameplay/source/main_boot_launch_loading.gd") or router.get_script()!=preload("res://scripts/gameplay/source/main_root_checkpoint_router.gd") or executor.get_script()!=preload("res://scripts/gameplay/world/world_caster_main_executor.gd") or executor.get("_root")!=root or world.get("world_runtime_id")!=root.get_instance_id(): return false
	_root=root; _executor=weakref(executor); _loading=loading; _router=router; _world=world.duplicate(true); return true
func _main() -> void: assert(OS.get_thread_caller_id()==OS.get_main_thread_id() and _root!=null)
func _fail(code: String) -> Dictionary: return {"success":false,"status":"INVALID","error":code}
func can_commit_actual_original_map_arrival(transaction: Dictionary) -> bool:
	if OS.get_thread_caller_id()!=OS.get_main_thread_id() or _closed or _proof.is_empty() or _executor==null or not is_instance_valid(_root) or not _root.is_inside_tree(): return false
	var executor: RefCounted = _executor.get_ref()
	return executor!=null and executor.get("_interactable")==self and executor.get("_root")==_root and executor.get("_world")==_world and _world==transaction.get("before_world") and executor.get("_host").verify_committed_original_map_arrival(transaction)
func commit_actual_original_map_arrival(transaction: Dictionary) -> bool:
	if not can_commit_actual_original_map_arrival(transaction): return false
	_world=transaction.after_world.duplicate(true)
	# Only current command routing changes. Issued identities, retained NPC
	# textures and the original Loading proof keep their exact provenance.
	return true
func prepare_original_loading(proof: Dictionary,boundary: Dictionary,appearances: Array[int]) -> Dictionary:
	_main()
	if not _proof.is_empty() or appearances.is_empty() or proof.get("world_context")!=_world or proof.get("main_executor_id")!=_executor.get_ref().get_instance_id() or not proof.get("closure_id") is int or proof.closure_id<=0: return _fail("same_actual_caster_Loading_closure_required")
	if proof != _executor.get_ref().get("_proof"): return _fail("actual_same_retained_Caster_proof_required")
	var scope: Dictionary = _loading.actual_original_loading_scope(_world)
	var actual: Dictionary=_loading.verify_actual_original_loading_scope(scope)
	var terminal: Dictionary=_router.verify_original_profile_ui_receiver_closure(boundary)
	if actual.get("success")!=true or terminal.get("success")!=true: return _fail("MISSING_actual_Loading_UI_IO_terminal_checkpoint")
	var profiles: Dictionary={}
	for appearance: int in appearances:
		if profiles.has(appearance): continue
		# Probe only original visual code, never NPC interaction/group/Source data logic.
		var probe := NPCShell.new()
		probe.appearance=appearance; probe.hide(); _root.add_child(probe)
		if not probe.is_node_ready() or probe.visual==null: probe.free(); return _fail("actual_original_NPCVisual_ready_failed")
		var texture: Texture2D=probe.visual.sprite.texture if probe.visual.sprite!=null else null
		var config: Dictionary=probe.visual._appearance_config(appearance)
		profiles[appearance]={"uses_final_art":probe.uses_final_art(),"configuration":config.duplicate(true),"actual_texture_id":texture.get_instance_id() if texture!=null else 0}
		_textures[appearance]=texture # Genuine Main RefCounted pin, no Source Texture copy.
		probe.free()
	var refresh := -1.0
	if DisplayServer.get_name()!="headless": refresh=DisplayServer.screen_get_refresh_rate()
	var facts := {"godot":str(Engine.get_version_info().get("string","")),"renderer":str(ProjectSettings.get_setting("rendering/renderer/rendering_method","")),"adapter":RenderingServer.get_video_adapter_name(),"api":RenderingServer.get_video_adapter_api_version(),"refresh_rate":refresh,"physics_tps":Engine.physics_ticks_per_second,"max_physics_steps":Engine.max_physics_steps_per_frame,"app_version":str(ProjectSettings.get_setting("application/config/version","")),"os":OS.get_name()}
	var pub := {"contract_id":"world.interactable.loading.v1","world_context":_world,"closure_id":proof.closure_id,"main_executor_id":proof.main_executor_id,"npc_profiles":profiles,"session_diagnostics":facts,"session_diagnostics_header_printed":OriginalRoot._session_header_printed,"actual_Loading_receipt":actual,"actual_terminal_receipt":terminal}
	var graph: RefCounted=ClassDB.instantiate("HardCoreContentValueGraph")
	var copied: Dictionary=graph.capture(pub,true,false)
	if copied.get("success")!=true:
		_textures.clear()
		return _fail("interactable_loading_not_plain")
	_proof=copied.value
	return {"success":true,"publication":_proof}
func actual_node(id: int) -> Node2D:
	return instance_from_id(id) as Node2D if OS.get_thread_caller_id()==OS.get_main_thread_id() else null
func _actor(payload: Dictionary) -> Node2D:
	var id: int=payload.identity.runtime_id
	if not _nodes.has(id) or _nodes[id].identity!=payload.identity: return null
	return _nodes[id].node.get_ref()
func execute_leaf(operation: StringName,payload: Dictionary) -> Dictionary:
	_main()
	if _closed or _proof.is_empty(): return _fail("interactable_Main_not_configured")
	if operation==&"source_interactable::session_diagnostics":
		if payload.get("facts")!=_proof.session_diagnostics: return _fail("changed_session_diagnostics_facts")
		if OriginalRoot._session_header_printed: return {"success":true,"actual_node_id":0}
		OriginalRoot._session_header_printed=true # Original process-static flag stays solely Main.
		var f: Dictionary=payload.facts
		print("[SESSION-ID] godot=%s renderer=%s adapter=%s api=%s refresh=%.1fHz physics_tps=%d max_physics_steps=%d app_version=%s os=%s" % [f.godot,f.renderer,f.adapter,f.api,f.refresh_rate,f.physics_tps,f.max_physics_steps,f.app_version,f.os])
		return {"success":true,"actual_node_id":0}
	if not payload.get("identity") is Dictionary or payload.identity.get("world")!=_world or not payload.identity.get("runtime_id") is int or payload.identity.runtime_id<=0: return _fail("interactable_actual_actor_identity_required")
	var id: int=payload.identity.runtime_id
	if operation in [&"source_interactable::spawn_npc",&"source_interactable::spawn_portal"]:
		if _nodes.has(id) or not payload.get("state") is Dictionary: return _fail("duplicate_interactable_Node")
		var state: Dictionary=payload.state
		var node: Node2D
		if operation==&"source_interactable::spawn_npc":
			if not _proof.npc_profiles.has(state.appearance): return _fail("actual_npc_pin_missing")
			var npc := NPCShell.new()
			npc.npc_name=state.npc_name; npc.npc_kind=state.npc_kind; npc.appearance=state.appearance; npc.facing=state.facing; npc.default_facing=state.default_facing; npc.service_identity_id=state.service_identity_id
			if not npc.configure_original_loading_texture(_textures[state.appearance],_proof.npc_profiles[state.appearance].configuration): return _fail("actual_npc_Loading_pin_invalid")
			node=npc
		else:
			var portal := PortalShell.new()
			portal.target_zone=state.target_zone; portal.target_map_id=state.target_map_id; portal.display_name=state.display_name; portal.portal_role=state.portal_role; portal.portal_data=state.portal_data.duplicate(true); node=portal
		node.global_position=state.position_screen_px
		_nodes[id]={"identity":payload.identity.duplicate(true),"node":weakref(node)}
		node.tree_exited.connect(_on_tree_exited.bind(id)); _root.add_child(node)
		if not node.is_node_ready(): return _fail("original_interactable_Node_ready_missing")
		return {"success":true,"identity":payload.identity,"actual_node_id":node.get_instance_id(),"actual_ready":node.is_node_ready(),"uses_final_art":node.uses_final_art() if node is NPCShell else false}
	var node: Node2D=_actor(payload)
	if node==null: return _fail("original_interactable_Node_identity_missing")
	match operation:
		&"source_interactable::face_npc":
			if not node is NPCShell: return _fail("original_NPC_shell_required")
			node.facing=payload.facing; node.default_facing=payload.default_facing; node._refresh_name_label_anchor()
		&"source_interactable::retire": node.queue_free() # Original deferred physical Node/Texture lifetime.
		_: return _fail("unknown_interactable_leaf")
	return {"success":true,"identity":payload.identity,"actual_node_id":0}
func _on_tree_exited(id: int) -> void: _nodes.erase(id)
func inspect_actual_original_interactable_io() -> Dictionary:
	_main()
	var nodes: Array[Dictionary]=[]
	for id: int in _nodes:
		var node: Node=_nodes[id].node.get_ref()
		if node!=null: nodes.append({"identity":_nodes[id].identity,"actual_node_id":node.get_instance_id(),"queued_for_deletion":node.is_queued_for_deletion()})
	var textures: Array[Dictionary]=[]
	for appearance: int in _textures:
		var texture: Texture2D=_textures[appearance]
		if texture!=null: textures.append({"appearance":appearance,"actual_texture_id":texture.get_instance_id()})
	return {"producer_runtime_id":get_instance_id(),"producer_script_sha256":get_script().get_source_code().sha256_text(),"actual_nodes":nodes,"actual_texture_pins":textures,"world_context":_world}
func release_original_loading_pins(closure_id: int) -> bool:
	_main()
	if _closed: return closure_id==_proof.get("closure_id")
	if _proof.is_empty() or closure_id!=_proof.closure_id or not _nodes.is_empty(): return false
	_textures.clear(); _loading=null; _router=null; _closed=true; return true

func inspect_actual_original_loading_pins(publication: Dictionary) -> Dictionary:
	_main()
	if _closed or publication != _proof or _proof.is_empty() or not is_instance_valid(_root) or not _root.is_inside_tree() or _executor.get_ref() == null or _executor.get_ref().get("_interactable") != self or _textures.size() != publication.npc_profiles.size(): return _fail("actual_interactable_physical_owner_changed")
	for appearance: int in publication.npc_profiles:
		if not _textures.has(appearance): return _fail("actual_NPC_texture_pin_missing")
		var texture: Texture2D = _textures[appearance]
		if (texture.get_instance_id() if texture != null else 0) != publication.npc_profiles[appearance].actual_texture_id: return _fail("actual_NPC_texture_pin_changed")
	return {"success":true,"publication":_proof,"actual_io":inspect_actual_original_interactable_io()}
