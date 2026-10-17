extends Node
const Proof:=preload("res://tests/framework/helpers/check_receipt.gd")
const Registry:=preload("res://scripts/gameplay/presentation/main_enemy_effect_registry.gd")
const InputCapture:=preload("res://scripts/gameplay/presentation/main_original_pick_input.gd")
const Consumer:=preload("res://scripts/gameplay/world/world_main_prefix_consumer.gd")
const Source:=preload("res://tests/framework/helpers/enemy_presentation_source_20261017.gd")
const Geometry:=preload("res://scripts/skills/warrior_melee_geometry.gd")
const Snapshot:=preload("res://scripts/skills/skill_footprint_snapshot.gd")
var proof:=Proof.new()
var failures:=0
var host: Object
var consumer: RefCounted
var registry: RefCounted
var foreign: RefCounted
var root: Node2D
var world: Dictionary
var closing:=false
var retiring_oracle_claims:=false
var oracle_claims: Dictionary
var tick:=0
var deadline:=0
var writes:=0
var oracles: Dictionary
var examples: Array[Dictionary]
var pending_traced: Array[int]
var retained_prefix: Dictionary
var witnesses: Array[Dictionary]
func check(value: bool,label: String) -> void:
	proof.record(value,label)
	if not value: failures+=1;print("ENEMY_PRESENTATION_FAIL ",label)
func _ready() -> void: _run.call_deferred()
func project_ground(p: Vector2) -> Vector2: return Vector2(p.x*64.0,p.y*32.0)
func _run() -> void:
	for path: String in ["scripts/gameplay/actors/enemy_actor_model.gd", "scripts/gameplay/presentation/actor_main_visual_journal_consumer.gd", "scripts/gameplay/presentation/actor_main_visual_shell.gd", "scripts/gameplay/presentation/enemy_main_visual_projection.gd", "scripts/gameplay/presentation/main_actor_visual_registry.gd", "scripts/gameplay/presentation/main_enemy_effect_registry.gd", "scripts/gameplay/presentation/main_enemy_projectile_preview.gd", "scripts/gameplay/presentation/main_enemy_target_magic_preview.gd", "scripts/gameplay/presentation/main_original_pick_input.gd", "scripts/gameplay/source/main_boot_root_transport.gd", "scripts/gameplay/source/main_original_actor_birth_templates.gd", "scripts/gameplay/world/world_enemy_native_motion.gd", "scripts/gameplay/world/world_enemy_projectile_effect_model.gd", "scripts/gameplay/world/world_enemy_runtime_ports.gd", "scripts/gameplay/world/world_enemy_target_magic_model.gd", "scripts/gameplay/world/world_main_root_attachment.gd", "scripts/gameplay/world/world_main_views.gd", "scripts/gameplay/world/world_original_source_tree.gd", "scripts/gameplay/world/world_owner_full_ports.gd", "scripts/gameplay/world/world_owner_input.gd", "scripts/gameplay/world/world_root_phase_adapter.gd", "scripts/gameplay/world/world_simulation_core.gd"]:
		var code: Script=load("res://"+path)
		check(code!=null and code.can_instantiate(),"candidate actual parser: "+path)
	var templates:=preload("res://scripts/gameplay/source/main_original_actor_birth_templates.gd")
	for key: String in ["enemy_projectile","enemy_target_magic"]:
		var specification: Array=templates.SOURCES[key]
		var original: Script=load(specification[0])
		check(original.get_source_code().sha256_text()==specification[1],"actual Godot source bytes match original birth template seal "+key)
		var callbacks: Dictionary=templates.capture_callbacks(original)
		check(callbacks.has("_process") and callbacks._process.domain=="P" and callbacks._process.script_sha256==specification[1],"actual original P callback manifest "+key)
		check(callbacks.has("_physics_process")== (key=="enemy_projectile"),"actual original H callback qualification "+key)
	check(OS.get_user_data_dir().replace("\\","/").contains("/.godot/runtime_appdata/"),"actual private runner userdata")
	root=Node2D.new();add_child(root)
	world={"contract_id":"hardcore.execution.world_context.v1","world_runtime_id":root.get_instance_id(),"world_epoch":1,"runtime_map_id":1001,"profile_id":"isolated.enemy.presentation.component"}
	var viewport: Viewport=root.get_viewport()
	var prior: Transform2D=viewport.get_canvas_transform();var pick: bool=viewport.physics_object_picking
	viewport.physics_object_picking=true;viewport.canvas_transform=Transform2D(0.2,Vector2(21,37))
	var mouse:=InputEventMouseButton.new();mouse.position=Vector2(170,90);mouse.pressed=true;mouse.button_index=MOUSE_BUTTON_LEFT
	var captured: Dictionary=InputCapture.capture_main(root,mouse)
	check(InputCapture.validate(captured,world) and captured.canvas_position==viewport.canvas_transform.affine_inverse()*mouse.position,"real Main Viewport inverse canvas capture and plain-value validation")
	mouse.pressed=false;check(InputCapture.capture_main(root,mouse).is_empty(),"release is not original Enemy selection")
	mouse.pressed=true;mouse.button_index=MOUSE_BUTTON_RIGHT;check(InputCapture.capture_main(root,mouse).is_empty(),"right mouse is not original Enemy selection")
	var touch:=InputEventScreenTouch.new();touch.position=Vector2(220,170);touch.index=2;touch.pressed=true
	var touch_fact: Dictionary=InputCapture.capture_main(root,touch)
	check(InputCapture.validate(touch_fact,world) and touch_fact.index==2 and InputCapture.source_event(touch_fact) is InputEventScreenTouch,"real touch index and pressed resource survive exact codec")
	viewport.canvas_transform=prior;viewport.physics_object_picking=pick
	var context: Dictionary=Snapshot.make_absolute_runtime_context(1001,Vector2.ZERO,Vector2.ZERO,Callable(self,"project_ground"))
	context.expected_runtime_map_id=1001
	var release: Dictionary={"origin_ground_gu":Vector2.ZERO,"locked_target_ground_gu_at_release":Vector2(1.2,0.4),"locked_target_valid_at_release":true,"locked_target_instance_id":9001,"live_locked_target_direction_ground_gu":Vector2(1.2,0.4).normalized(),"direction_index":Geometry.direction_index_for_ground_delta_gu(Vector2(1.2,0.4)),"release_id":"enemy_component_melee"}
	var plan: Dictionary=Geometry.target_aligned_melee_release_plan_ground_gu(release,Geometry.SKILL_THRUST,context)
	check(plan.get("target_axis_eligible")==true,"real canonical melee plan and strict snapshot")
	var melee_args: Array=[plan.get("skill_footprint_snapshot",{}),Geometry.SKILL_THRUST,true,Vector2.ZERO,{"target_aligned_plan":plan,"snapshot_validation_context":preload("res://scripts/gameplay/presentation/original_melee_presentation_context.gd").capture_source(context,plan.get("skill_footprint_snapshot",{}),world,{"world_context":world})}]
	var codec:=preload("res://scripts/gameplay/presentation/original_melee_presentation_context.gd")
	var plain: Dictionary=melee_args[4].snapshot_validation_context
	var restored: Dictionary=codec.restore_main(plain,melee_args[0],world,{"world_context":world})
	check(not plain.is_empty() and not restored.is_empty(),"full finite original projection codec preserves strict visual context")
	var invalid: Dictionary=plain.duplicate(true);var missing: Vector2=invalid.original_melee_projection.samples[1].ground;invalid.original_melee_projection.samples=invalid.original_melee_projection.samples.filter(func(sample: Dictionary) -> bool: return sample.ground!=missing)
	check(codec.restore_main(invalid,melee_args[0],world,{"world_context":world}).is_empty(),"missing actual polygon point refuses finite projection")
	invalid=plain.duplicate(true);var conflict: Dictionary=invalid.original_melee_projection.samples[0].duplicate(true);conflict.screen+=Vector2.ONE;invalid.original_melee_projection.samples.append(conflict)
	check(codec.restore_main(invalid,melee_args[0],world,{"world_context":world}).is_empty(),"conflicting duplicate point refuses finite projection")
	var wrong_world: Dictionary=world.duplicate(true);wrong_world.profile_id="wrong"
	check(codec.restore_main(plain,melee_args[0],wrong_world,{"world_context":world}).is_empty(),"finite projection cannot replay another world")
	var converter: Callable=restored.ground_position_gu_to_screen_position_px
	check(not converter.call(Vector2(999,999)).is_finite() and restored._actual_projection_values.failure.get("error")=="original_melee_projection_point_outside_captured_snapshot","out-of-domain point explicitly refuses without guessed transform")
	converter=Callable()
	check(codec.release_main(restored),"actual Main finite projection capsule is released after its pure consumer")
	# Arrow source 4 uses original16-direction WIL; axe42 uses real exact frames.
	for id: int in [4,42,62,220,222,224]:
		var kind: StringName=&"physical_projectile" if id<200 else &"target_magic"
		var descriptor: Dictionary={"effect_id":"monster.physical_arrow.v1" if id<200 else "monster.target_lightning.v1","release_id":"real.effect.%d"%id,"source_monster_id":id,"source_instance_id":0,"target_instance_id":0,"origin_world_px":Vector2(10,20),"target_world_px":Vector2(130,80),"source_world_px":Vector2(10,20),"duration_seconds":0.6,"damage":17,"presentation_only":false}
		examples.append({"kind":kind,"descriptor":descriptor,"constructor":{"source_world_px":Vector2(10,20),"source_direction8":3}})
	host=ClassDB.instantiate("HardCoreSimulationHost");consumer=Consumer.new(host,self)
	registry=Registry.new();check(registry.configure_main(root,world,consumer),"actual Native prefix consumer binds pure effect registry")
	foreign=Registry.new();var wrong: Dictionary=world.duplicate(true);wrong.profile_id="foreign";check(foreign.configure_main(root,wrong,consumer),"negative observer uses actual Native owner with foreign world")
	check(not registry.apply_original_event({"kind":"original_world_presentation","operation":&"retire_enemy_effect","arguments":[1],"source_site":{"world_context":world},"ordinal":1}),"no acquired real prefix refuses effect writes")
	var config: Dictionary={"physics_hz":60,"max_epochs_per_turn":8,"timer_capacity":16,"input_capacity":16,"event_capacity":32,"bridge_generation":115177,"source_process_frame":Engine.get_process_frames(),"source_physics_frame":Engine.get_physics_frames(),"primitive_request_capacity":65536,"primitive_result_capacity":65536,"source_deferred_max_pages":int(ProjectSettings.get_setting("memory/limits/message_queue/max_size_mb",32))*256}
	var area: Dictionary={"gravity":ProjectSettings.get_setting("physics/2d/default_gravity"),"gravity_vector":ProjectSettings.get_setting("physics/2d/default_gravity_vector"),"linear_damp":ProjectSettings.get_setting("physics/2d/default_linear_damp"),"angular_damp":ProjectSettings.get_setting("physics/2d/default_angular_damp")}
	print("ENEMY_TRACE Main_before_Host_start")
	var started: bool=host.start(Source,{"world_identity":world,"examples":examples,"pointer":captured,"touch":touch_fact,"area":area,"bridge_generation":config.bridge_generation},config)
	print("ENEMY_TRACE Main_after_Host_start ",started)
	check(started,"actual Source journal + Native point query component start")

	if not started:
		host=null;root.free();_finish();return
	deadline=Time.get_ticks_usec()+15000000
func apply_original_main_journal_event(event: Dictionary) -> Variant:
	check(not foreign.apply_original_event(event),"actual acquired event cannot write foreign world")
	var wrong: Dictionary=event.duplicate(true);wrong.source_site.world_context.profile_id="foreign"
	check(not registry.apply_original_event(wrong),"changed world/noncurrent event refuses before physical write")
	var applied: Variant=registry.apply_original_event(event)
	if applied is Dictionary:
		if not event.get("ordinal") in pending_traced: print("ENEMY_TRACE pending ",event.get("ordinal"),applied);pending_traced.append(event.get("ordinal"))
		return applied
	if applied!=true: return false
	writes+=1
	print("ENEMY_TRACE applied ",event.ordinal," ",event.operation)
	var args: Array=event.arguments
	if event.operation==&"enemy_create_effect":
		check(not registry.apply_original_event(event),"completed duplicate ID creation refuses")
		var holder: Node2D=registry.get("_rows")[args[0]].view
		var view: Node2D=holder.original_renderer()
		check(not view.is_processing() and not view.is_physics_processing() and holder.get_parent()==root and view.get_parent()==holder and not holder.is_processing() and not holder.is_physics_processing(),"actual original rendering leaf has no automatic flight/occlusion clock")
		check(args[2].source_instance_id>0 and registry.get("_rows")[args[0]].descriptor==args[2] and view.release_descriptor.source_instance_id==0,"Source full descriptor/damage/instance attributes retained unchanged")
		var oracle: Node2D
		if args[1]==&"physical_projectile":
			var copy: Dictionary=args[2].duplicate(true);copy.presentation_only=true;copy.source_instance_id=0;copy.target_instance_id=0
			oracle=preload("res://scripts/monster_ranged_projectile_effect.gd").create_visual(copy)
		else:
			# Oracle setup uses its original geometric fallback with no gameplay
			# object; fixture expected direction is that exact fallback value.
			var preview: Dictionary=args[2].duplicate(true);preview.source_instance_id=0;preview.source_world_px=args[3].source_world_px
			oracle=preload("res://scripts/monster_target_magic_effect.gd").create_visual(preview);oracle.source_direction8=args[3].source_direction8
		root.add_child(oracle);oracle.set_process(false);oracle.set_physics_process(false)
		oracles[args[0]]=oracle
		check(view.global_position==oracle.global_position and view.z_index==oracle.z_index,"original constructor/READY footpoint and draw plane")
		_compare(view,oracle)
		check(holder.global_position==view.global_position and holder.y_sort_enabled and view.position==Vector2.ZERO,"pure holder retains original actual footpoint and y-sort plane")
		var pending_exit: Dictionary=registry.capture_actual_world_exit(world)
		check(pending_exit.get("status")=="PENDING" and is_instance_valid(holder) and registry.get("_rows").has(args[0]),"Main world observer cannot retire a live Source cast or mask its debt")
		witnesses.append({"Source_effect_id":args[0],"kind":str(args[1]),"Source_descriptor":args[2].duplicate(true),"Source_constructor":args[3].duplicate(true),"Main_preview_descriptor":view.release_descriptor.duplicate(true),"actual_original_factory_script":view.get_script().resource_path,"actual_node_ids":registry.get("_rows")[args[0]].node_ids.duplicate(),"actual_texture_paths":_texture_paths(view),"Main_leaf_process":view.is_processing(),"Main_leaf_physics":view.is_physics_processing(),"full_original_oracle_compared":true,"actual_prefix":consumer.actual_current_original_prefix()})
	elif event.operation==&"enemy_effect_tick":
		var holder: Node2D=registry.get("_rows")[args[0]].view
		var view: Node2D=holder.original_renderer()
		var oracle: Node2D=oracles[args[0]];var state: Dictionary=args[1]
		oracle.set("_elapsed_seconds",state.elapsed)
		if registry.get("_rows")[args[0]].kind==&"physical_projectile":
			oracle.global_position=state.position
			if not oracle.get("_exact_profile").is_empty(): oracle._update_exact_frame()
		else:
			oracle.set("_duration_seconds",state.duration);oracle.set("_fly_blocked_by_world",state.blocked);oracle._update_presentation()
		_compare(view,oracle)
	elif event.operation==&"retire_enemy_effect":
		var fact: Dictionary=registry.get("_retired")[args[0]]
		check(not is_instance_id_valid(fact.node_id) and not registry.apply_original_event(event),"real physical free and retired event refusal")
		for id: int in fact.node_ids:check(not is_instance_id_valid(id),"actual original rendering subtree absent after precise Source retirement")
		oracles[args[0]].free();oracles.erase(args[0])
	elif event.operation==&"spawn_target_aligned_melee_visual":
		var facts: Array=registry.get("_melee")
		var view: Node2D=facts.back().view.get_ref()
		var restored_context: Dictionary=preload("res://scripts/gameplay/presentation/original_melee_presentation_context.gd").restore_main(args[4].snapshot_validation_context,args[0],world,event.source_site)
		var oracle: Node2D=preload("res://scripts/warrior_melee_visual_effect.gd").create_visual(args[0],args[1],{"hit":args[2],"release_id":args[4].target_aligned_plan.release_id},restored_context,args[3])
		check(preload("res://scripts/gameplay/presentation/original_melee_presentation_context.gd").release_main(restored_context),"original oracle projection capsule released after strict create_visual")
		root.add_child(oracle)
		check(view.visual_ready() and view.get_child_count()==3 and view.get_child_count()==oracle.get_child_count(),"actual original strict target-aligned melee has same three layers")
		for i: int in 3:check(view.get_child(i).polygon==oracle.get_child(i).polygon and view.get_child(i).color==oracle.get_child(i).color,"exact original melee layer polygon/color "+str(i))
		oracle.free()
	return true
func _compare(view: Node2D, oracle: Node2D) -> void:
	check(view.get_child_count()==oracle.get_child_count(),"original exact artwork child topology")
	_compare_children(view,oracle)
func _compare_children(view: Node, oracle: Node) -> void:
	for index: int in mini(view.get_child_count(),oracle.get_child_count()):
		var a: Node=view.get_child(index);var b: Node=oracle.get_child(index)
		check(a.get_class()==b.get_class(),"original display node class "+a.name)
		if a is Node2D and b is Node2D:check(a.position==b.position and a.visible==b.visible,"original exact sprite/proxy position and visibility "+a.name)
		if a is Sprite2D and b is Sprite2D:check(a.texture==b.texture and a.region_rect==b.region_rect and a.region_enabled==b.region_enabled and a.texture_filter==b.texture_filter,"actual identical texture/atlas/sampler "+a.name)
		_compare_children(a,b)
func _texture_paths(node: Node) -> Array[String]:
	var paths: Array[String]=[]
	if node is Sprite2D and node.texture!=null: paths.append(node.texture.resource_path)
	for child: Node in node.get_children(): paths.append_array(_texture_paths(child))
	return paths
func _process(_delta: float) -> void:
	if retiring_oracle_claims:
		var current: Dictionary=ContentLayers.threaded_resource_claim_diagnostics()
		if current.pending==0:
			oracle_claims.after=current
			check(current.get-oracle_claims.before.get==oracle_claims.paths.size() and current.missing==oracle_claims.before.missing,"original ContentLayers consumes each accepted oracle resource claim exactly once")
			_finish()
		elif Time.get_ticks_usec()>deadline:
			check(false,"actual oracle resource retirement completes within existing component deadline");_finish()
		return
	if host==null: return
	if retained_prefix.is_empty():
		var held: Dictionary=host.inspect_next_original_published_prefix()
		if held.get("status")=="READY": retained_prefix=held.prefix
	if not retained_prefix.is_empty():
		var result: Dictionary=consumer.apply_prefix(retained_prefix)
		if result.get("status")=="INVALID":check(false,"actual Native prefix applies concrete effect operations");print(result)
		if result.get("status")=="APPLIED":
			var ack: Dictionary={"bridge_generation":retained_prefix.bridge_generation,"journal_generation":retained_prefix.journal_generation,"through_ordinal":retained_prefix.through_ordinal,"applied":true}
			check(host.ack_published_original_main_prefix(retained_prefix,ack) and consumer.confirm_prefix_acknowledged(retained_prefix,ack),"actual complete applied prefix Native ACK")
			retained_prefix={}
	var packet: Dictionary=host.acquire_presentation(tick+1,32)
	if not packet.is_empty():
		tick=packet.tick;host.ack_events(packet.through_ordinal)
		if packet.frame.get("done")==true and not closing:
			for fact: Dictionary in packet.frame.checks:check(fact.pass,fact.label)
			check(writes==25,"all actual concrete effect operations applied once")
			var exit: Dictionary=registry.capture_actual_world_exit(world)
			check(exit.get("status")=="READY" and registry.actual_nodes_absent() and root.is_inside_tree(),"physical effects explicitly absent before retained Root exit")
			closing=true;host.request_close()
	if closing and host.status().get("join_complete")==true:
		check(host.close_and_join(),"actual Source world and journal quiesce and Native join")
		host=null;root.free()
		var frames:=preload("res://scripts/monster_source_frames.gd")
		oracle_claims={"before":ContentLayers.threaded_resource_claim_diagnostics(),"paths":[]}
		for path: String in frames._requested:
			oracle_claims.paths.append({"path":path,"actual_engine_status":ResourceLoader.load_threaded_get_status(path)})
		print("ENEMY_ORACLE_RESOURCE_CLAIMS_BEFORE ",oracle_claims)
		check(frames.retire_pending_threaded_claims() and frames._requested.is_empty(),"original oracle scene handoff transfers all actual ResourceLoader claims")
		retiring_oracle_claims=true
	elif Time.get_ticks_usec()>deadline:
		check(false,"bounded15s component completes; no force-free accepted Host");print(host.status());_finish()
func _finish() -> void:
	set_process(false)
	var file:=FileAccess.open("user://enemy_presentation_witness_20261017.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"scope":"actual Native prefix/source journal + original factory artwork component; full World/Source effect Scope NOT_RUN","witnesses":witnesses,"applied_operations":writes,"original_oracle_resource_retirement":oracle_claims},"  "));file.close()
	var ok: bool=proof.write_receipt("enemy_presentation_20261017",proof.records.size(),failures)
	print("ENEMY_PRESENTATION_20261017_","PASS" if ok else "FAIL"," checks=",proof.records.size()," failures=",failures," FULL_SOURCE_WORLD=NOT_RUN")
	get_tree().quit(0 if ok else 1)
