extends Node

## Actual original Main coordinator/ResourceLoader/background retirement kernel.
## No fake Source, Native scope, map CAS, full application or GPU acceptance.
const Leaf := preload("res://scripts/gameplay/world/world_map_visual_main.gd")
const Owner := preload("res://scripts/gameplay/source/main_original_map_loading_owner.gd")
const CoordinatorCode := preload("res://scripts/world_bootstrap_coordinator.gd")
const BackgroundCode := preload("res://scripts/gameplay/world/world_main_background.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const PATHS := ["res://assets/ui/gothic_hud/v2/runtime/target_bar_fill_mask.png","res://assets/ui/gothic_hud/v2/runtime/target_bar_v2.png"]
var _proof := Proof.new()
var _failed := 0

func check(ok: bool, label: String) -> void:
	_proof.record(ok,label)
	if not ok: _failed += 1

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	check(OS.get_user_data_dir().replace("\\","/").contains("/.godot/runtime_appdata/"),"physical Map lifecycle uses the official isolated test data directory")
	var owner := Owner.new()
	check(owner.capture_scope(null,{},"unadmitted",1,913203).get("success") == false,"a new owner cannot issue a numeric scope without the actual original Root/loading/executor graph")
	check(not owner.verify_scope(null,{},{}),"an empty purported Main proof cannot verify a real map scope")
	var root := Node2D.new(); add_child(root)
	var unrelated := Node2D.new(); root.add_child(unrelated)
	var background := BackgroundCode.new()
	check(background.configure_original_Main_visual_only(),"actual original display configures before tree entry without collision authority")
	root.add_child(background)
	check(background.original_visual_environment_is_physics_free(),"same real Main background contains no Source collision objects")
	var coordinator := CoordinatorCode.new()
	coordinator.begin_map_transition(913203)
	var leaf := Leaf.new()
	# Direct physical kernel dependencies only. Formal execute/capture still
	# requires real Source journal/Native admission and is not exercised here.
	leaf.set("_coordinator",coordinator); leaf.set("_background",background)
	check(not leaf.has_pending_actual_original_map_claims(),"real fresh coordinator has no already-issued loader claim")
	var accepted := 0
	var held: Dictionary = {}
	for path: String in PATHS:
		var texture := load(path) as Texture2D
		check(texture != null,"nonempty original imported texture exists: "+path)
		if texture == null: continue
		held[path] = texture
		coordinator.register_resource(path,"texture",true,"map-physical-component")
		# Each successful real request owns a genuine Godot retrieval token.
		# This explicitly exercises physical retirement, not a Source entitlement.
		for attempt: int in 2:
			var error := ResourceLoader.load_threaded_request(path)
			if error == OK:
				accepted += 1
				var entry: Dictionary = coordinator.resource_manifest[path]
				entry.status = "requested"; entry.claim_count = int(entry.get("claim_count",0))+1
	check(accepted > 0 and leaf.has_pending_actual_original_map_claims(),"only actual OK requests create retained original Map claim debt")
	var deadline := Time.get_ticks_usec()+20000000
	var result: Dictionary = leaf.service_actual_original_map_claim_retirement()
	while result.get("status") == "PENDING" and Time.get_ticks_usec() < deadline:
		check(leaf.has_pending_actual_original_map_claims(),"a PENDING physical retirement keeps the actual accepted responsibility")
		await get_tree().process_frame
		result = leaf.service_actual_original_map_claim_retirement()
	check(result.get("success") == true and result.get("status") == "READY" and not leaf.has_pending_actual_original_map_claims(),"all real accepted Map loader tokens reach actual terminal retirement")
	var history: Array = leaf.get("_actual_claim_history").duplicate(true)
	var gets := 0
	var released := 0
	for item: Dictionary in history:
		released += int(item.released_count)
		if item.get_performed: gets += 1
	check(released == accepted and gets <= accepted,"real token accounting releases exactly accepted responsibilities and never performs an extra get")
	for path: String in PATHS:
		if held.has(path): check(ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE,"actual loader has no user token after retirement: "+path)
	check(leaf.service_actual_original_map_claim_retirement().status == "READY" and history == leaf.get("_actual_claim_history"),"duplicate retirement cannot replay a get or rewrite historical physical facts")
	if not held.is_empty():
		var texture: Texture2D = held.values()[0]
		var visual := Sprite2D.new(); visual.texture = texture; background.add_child(visual)
		var sorted_sibling := Sprite2D.new(); sorted_sibling.texture = texture; root.add_child(sorted_sibling)
		background.get("_environment_nodes").append(visual)
		background.get("_environment_nodes").append(sorted_sibling)
		coordinator.get("_prefetched_resources")[PATHS[0]] = texture
		var weak_visual: WeakRef = weakref(visual); var weak_sibling: WeakRef = weakref(sorted_sibling)
		result = leaf.service_actual_original_map_terminal()
		check(result.status == "PENDING" and weak_visual.get_ref() != null and weak_sibling.get_ref() != null,"original queue_free is still a real pending visual obligation, including actor-sort siblings")
		while result.status == "PENDING" and Time.get_ticks_usec() < deadline:
			await get_tree().process_frame
			result = leaf.service_actual_original_map_terminal()
		check(result.status == "READY" and weak_visual.get_ref() == null and weak_sibling.get_ref() == null,"terminal waits for actual original owned visual storage to disappear")
		check(coordinator.get("_prefetched_resources").is_empty() and coordinator.resource_manifest.is_empty() and is_instance_valid(unrelated),"actual map cache pins release while unrelated Root children keep their own lifetime")
		check(leaf.service_actual_original_map_terminal().status == "READY" and history == leaf.get("_actual_claim_history"),"repeated terminal service neither reloads resources nor consumes another token")
	held.clear(); root.free()
	var written: bool = _proof.write_receipt("map_owner_physical_lifecycle_20261016",_proof.records.size(),_failed)
	print("MAP_OWNER_PHYSICAL_LIFECYCLE_20261016_","PASS" if written and _failed == 0 else "FAIL"," checks=",_proof.records.size()," failures=",_failed)
	get_tree().quit(0 if written and _failed == 0 else 1)
