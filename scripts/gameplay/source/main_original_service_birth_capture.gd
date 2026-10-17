extends RefCounted
## Constructor publications for the original service kinds consumed by
## WorldCore.new_original_service_scope. No READY, actor, scheduler or child
## membership is executed here. Source still owns each original add_child site.
const Scope := preload("res://scripts/gameplay/world/world_temporal_scope.gd")
const ORIGINALS := {
	"player_visual":preload("res://scripts/player_visual.gd"),
	"monster_visual":preload("res://scripts/monster_visual.gd"),
	"polygon_pursuit_driver":preload("res://scripts/map_editor/polygon/poly_pursuit_driver.gd"),
	"m30_summon_queue":preload("res://scripts/monster_ai_package/m30/summon_queue.gd"),
	"loot_runtime_manager":preload("res://scripts/loot_pickup_runtime_manager.gd")}
const REVIEWED_CONSTRUCTORS := {
	"player_visual":"0d872dd209c91825a0b1a725a92d6d84dcdd6a1b6f6142af6be4fa658411f5da",
	"monster_visual":"8bb4828acb9656bc7df2e751e565452e2c8cbf8da306eaf1fa31baa3849e3724",
	"polygon_pursuit_driver":"2f31d3fae977275bc3e77d874475812f9c83143a23a7bf29bd7f261b53be0bc2",
	"m30_summon_queue":"96bcd616093871c6035b38a050b76fe5b78663336c507644886c25d1a08eeacc",
	"loot_runtime_manager":"ea5da023eb5a1bbcfa3951edc1b1058a5aae9acd305d958e069402c19b5af36b"}

static func capture(actual_parent: Node) -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or not is_instance_valid(actual_parent) or not actual_parent.is_inside_tree() or actual_parent.is_queued_for_deletion(): return _missing("actual_entered_Main_parent_required")
	var inherited_mode := Node.PROCESS_MODE_INHERIT
	var ancestor: Node = actual_parent
	while ancestor != null and inherited_mode == Node.PROCESS_MODE_INHERIT:
		inherited_mode = ancestor.process_mode
		ancestor = ancestor.get_parent()
	if inherited_mode not in [1,2,3,4]: return _missing("actual_original_parent_process_mode_required")
	# These exact constructor preimages create only plain Node/Node2D and
	# value helpers. Source drift must be reviewed before instantiation, rather
	# than discovering a new forbidden physics constructor after it has run.
	for kind: String in ORIGINALS:
		var script: Script = ORIGINALS[kind]
		if script.get_source_code().sha256_text() != REVIEWED_CONSTRUCTORS[kind] or script.get_instance_base_type() not in [&"Node",&"Node2D"]: return _missing("reviewed_original_service_constructor_changed:"+kind)
	var scopes: Dictionary = {}
	var callbacks: Dictionary = {}
	var witnesses: Dictionary = {}
	var kinds: Array = ORIGINALS.keys()
	kinds.append("node_timer")
	for kind: String in kinds:
		var script: Script = ORIGINALS.get(kind)
		var node: Node = script.new() if script != null else Timer.new()
		if node.is_inside_tree() or node.get_parent() != null or node.get_child_count(true) != 0:
			node.free()
			return _missing("original_service_constructor_has_unreviewed_membership:"+kind)
		var effective: int = inherited_mode if node.process_mode == Node.PROCESS_MODE_INHERIT else node.process_mode
		var structural: RefCounted = Scope.new()
		scopes[kind] = {"runtime_present":is_instance_valid(node),"life_generation":structural.life_generation,
			"inside_world":node.is_inside_tree(),"queued_for_retirement":node.is_queued_for_deletion(),"parent_scope_id":0,"can_process":false,
			"process_processing_enabled":node.is_processing(),"physics_processing_enabled":node.is_physics_processing(),
			"ordinary_p_enabled":node.is_processing(),"raw_h_enabled":node.is_physics_processing(),
			"process_priority":node.process_priority,"physics_priority":node.process_physics_priority,
			"process_mode":node.process_mode,"effective_process_mode":effective}
		var entries: Dictionary = {}
		for method: String in ["_process","_physics_process"]:
			if not node.has_method(method): continue
			var origin: Script = script
			var expression := RegEx.create_from_string("(?m)^func "+method+"\\s*\\(")
			while origin != null and expression.search(origin.get_source_code()) == null: origin = origin.get_base_script()
			if origin == null:
				node.free()
				return _missing("actual_original_service_callback_body_missing:"+kind+":"+method)
			entries[method] = {"domain":"P" if method == "_process" else "H","internal":false,"entry":origin.resource_path+":"+method,"script_sha256":origin.get_source_code().sha256_text()}
		var witness := {"script_path":script.resource_path if script != null else "","script_sha256":script.get_source_code().sha256_text() if script != null else "",
			"original_class":node.get_class(),"actual_original_child_count":node.get_child_count(true),"actual_constructor_id":node.get_instance_id()}
		if kind == "node_timer":
			# Timer's real native INTERNAL notifications are independent of its
			# optional ordinary Script callbacks. WorldOriginalNodeTimer retains
			# these exact two slots and changes enable flags at start/stop.
			entries.original_internal_process = {"domain":"P","internal":true,"entry":"scene/main/timer.cpp:Timer::_notification:"+str(Node.NOTIFICATION_INTERNAL_PROCESS)}
			entries.original_internal_physics = {"domain":"H","internal":true,"entry":"scene/main/timer.cpp:Timer::_notification:"+str(Node.NOTIFICATION_INTERNAL_PHYSICS_PROCESS)}
			witness.timer_constructor = {"wait_time":node.wait_time,"one_shot":node.one_shot,"autostart":node.autostart,"paused":node.paused,"process_callback":node.process_callback,"ignore_time_scale":node.ignore_time_scale,"time_left":node.time_left}
		callbacks[kind] = {"callbacks":entries}
		witnesses[kind] = witness
		node.free()
	var graph: RefCounted = ClassDB.instantiate("HardCoreContentValueGraph")
	var copied: Dictionary = graph.capture({"contract_id":"hardcore.original.service_constructors.v1","service_birth_scopes":scopes,"service_callback_templates":callbacks,"constructor_witnesses":witnesses,
		"actual_parent_id":actual_parent.get_instance_id(),"parent_effective_process_mode":inherited_mode,"actual_Main_process_frame":Engine.get_process_frames(),"engine_version":Engine.get_version_info()},true,false)
	return {"success":true,"publication":copied.value} if copied.get("success") == true else _missing("original_service_constructor_value_capture_failed")

static func _missing(reason: String) -> Dictionary:
	return {"success":false,"status":"MISSING","error":reason}
