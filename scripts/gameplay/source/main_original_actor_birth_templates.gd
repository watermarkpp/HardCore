extends RefCounted
## Reviewed original constructor values, not actor instances/READY. No physics
## object is constructed here. Native body values remain in environment boot.
const Scope := preload("res://scripts/gameplay/world/world_temporal_scope.gd")
const Observer := preload("res://scripts/damage_ledger_observer.gd")
const Units := preload("res://scripts/monster_unit_adapter.gd")
const SOURCES := {
	"enemy_projectile":["res://scripts/monster_ranged_projectile_effect.gd","985b6c084ba6a4da52e51ac4490e3dbabc9a2e831866cb18361eb5fb66018836"],
	"enemy_target_magic":["res://scripts/monster_target_magic_effect.gd","a7d555822e44a655b6c39562a6d2ccb61fa7cdb4c435d11c97b4d0813abd820e"],
	"player":["res://scripts/player.gd","4b5e8bdd16b10c0ab230d934c36e6aefa423a0da3f736b5b1e992d074222190d"],
	"enemy":["res://scripts/enemy.gd","325baf31ed079950a5df21964c9ed5e5e7d65bcd7c4abe96571f60fc0c3f23f2"],
	"summon":["res://scripts/summon_actor.gd","cbf7a23ad4833164849385985540f3f87126a5571f3c0b97cfb43ba906d2c9b6"],
	"projectile":["res://scripts/skill_projectile.gd","ca91a0545bbf80a9eba2ee617dee79010b6cbdabbaa3ad24b7468052d51f88ef"],
	"field":["res://scripts/ground_effect.gd","906ce54ec94739f18f44e5c6386003209fc15647985188fd0e2229b4d2c683c2"],
	"fire_wall":["res://scripts/fire_wall_field_controller.gd","d5672ddb85668bb98dd58029876cda2c4506dc5270b4ad52eed570e601578e93"],
	"loot":["res://scripts/loot_pickup.gd","945e0a8a924237b5d6cca1ca65352b914bad27095e252713f72843c5a616ced2"],
	"npc":["res://scripts/npc_actor.gd","61a829928c169fb36d14f0e3d7dede7cf1eae648750f9e32306f8cc9f4ce2096"],
	"portal":["res://scripts/zone_portal.gd","86e78478fa70fca7e20745d45d462ac0c76bd0b3e789d96d81a297bd422181b5"]}

static func capture_callbacks(code: Script) -> Dictionary:
	var callbacks: Dictionary = {}
	for method: String in ["_process","_physics_process"]:
		var origin: Script = code
		var expression := RegEx.create_from_string("(?m)^func "+method+"\\s*\\(")
		while origin != null:
			if expression.search(origin.get_source_code()) != null:
				callbacks[method] = {"domain":"P" if method == "_process" else "H","internal":false,"entry":origin.resource_path+":"+method,"script_sha256":origin.get_source_code().sha256_text()}
				break
			origin = origin.get_base_script()
	return callbacks

static func capture_native_node2d_scope(parent_scope: Dictionary) -> Dictionary:
	var node := Node2D.new()
	var structural := Scope.new()
	var scope := {"runtime_present":is_instance_valid(node),"life_generation":structural.life_generation,
		"inside_world":node.is_inside_tree(),"queued_for_retirement":node.is_queued_for_deletion(),"parent_scope_id":0,"can_process":false,
		"process_processing_enabled":node.is_processing(),"physics_processing_enabled":node.is_physics_processing(),
		"ordinary_p_enabled":node.is_processing(),"raw_h_enabled":node.is_physics_processing(),
		"process_priority":node.process_priority,"physics_priority":node.process_physics_priority,
		"process_mode":node.process_mode,"effective_process_mode":parent_scope.effective_process_mode}
	node.free()
	return scope

static func capture_main(parent_scope: Dictionary, body_templates: Dictionary) -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or not parent_scope.get("effective_process_mode") is int or parent_scope.effective_process_mode not in [1,2,3,4]: return _fail("actual_Main_parent_scope_required")
	if not body_templates.get("footprints",{}).get("player") is Dictionary: return _fail("actual_player_footprint_required")
	var templates: Dictionary = {}
	for kind: String in SOURCES:
		var specification: Array = SOURCES[kind]
		var code: Script = load(specification[0])
		if code == null or code.get_source_code().sha256_text() != specification[1] or code.get_instance_base_type() not in [&"Node2D",&"CharacterBody2D"]: return _fail("reviewed_actor_constructor_changed:"+kind)
		var base := Node2D.new()
		var metadata: Dictionary = {}
		for key: StringName in base.get_meta_list(): metadata[key] = base.get_meta(key)
		var template := {"contract_id":"world.actor.original_birth.v1","scope":capture_native_node2d_scope(parent_scope),"metadata":metadata,
			"position_screen_px":base.position,"source_callbacks":capture_callbacks(code),"damage_recording_enabled":Observer.recording_enabled,
			"exact_player_contract":kind == "player","visual_available":false,"overhead_present":false,
			"constructor_source_path":specification[0],"constructor_source_sha256":specification[1]}
		base.free()
		if kind == "player":
			var radius: Variant = body_templates.footprints.player.get("screen_radius_px")
			if not radius is float or not is_finite(radius) or radius <= 0.0: return _fail("actual_player_radius_required")
			template.combat_radius_gu = Units.footprint_radius_px_to_combat_radius_gu(radius)
		templates[kind] = template
	var graph: RefCounted = ClassDB.instantiate("HardCoreContentValueGraph")
	var copied: Dictionary = graph.capture(templates,true,false)
	return {"success":true,"templates":copied.value} if copied.get("success") == true else _fail("actor_template_not_plain")

static func _fail(reason: String) -> Dictionary:
	return {"success":false,"status":"MISSING","error":reason}
