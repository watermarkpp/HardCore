extends Node

## Actual original metadata, numeric selector, AnimationPlayer and Main ground
## leaf component. No fake Source/Core/Host execution or whole-world claim.
const Structure := preload("res://scripts/gameplay/world/world_caster_visual_structure.gd")
const Registry := preload("res://scripts/caster_skill_visual_registry.gd")
const AnimationPlayerCode := preload("res://scripts/caster_skill_animation_player.gd")
const Executor := preload("res://scripts/gameplay/world/world_caster_main_executor.gd")
const Ground := preload("res://scripts/gameplay/world/world_caster_ground_display.gd")
const Gate := preload("res://scripts/gameplay/content/catalog_publication_gate.gd")
const Timing := preload("res://scripts/gameplay/world/world_skill_timing_publication.gd")
const Publication := preload("res://scripts/gameplay/world/world_caster_visual_publication.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var _proof := Proof.new()
var _failed := 0

func check(ok: bool, label: String) -> void:
	_proof.record(ok,label)
	if not ok: _failed += 1

func _oracle(direction: int, sequences: Array) -> int:
	var candidates: Array[Array] = []
	for index: int in sequences.size():
		var clockwise := posmod(int(sequences[index].get("direction_index",0))-posmod(direction,16),16)
		candidates.append([mini(clockwise,16-clockwise),clockwise,index])
	candidates.sort_custom(func(a: Array,b: Array) -> bool:
		return a[0] < b[0] or (a[0] == b[0] and (a[1] < b[1] or (a[1] == b[1] and a[2] < b[2]))))
	return candidates[0][2]

func _ready() -> void:
	var token: Dictionary = Gate.publish("actual-caster-structure:"+FileAccess.get_sha256(Registry.MANIFEST_PATH))
	check(not token.is_empty(),"actual catalog publisher gate owns this isolated Main component")
	var metadata: Dictionary = Publication.publish(token,Timing.publish(token))
	check(not metadata.is_empty() and metadata.metadata.structure_contract_id == Structure.CONTRACT,"real original timing and full visual catalog publish the shared structure contract")
	if metadata.is_empty(): _finish(token); return
	var directions := [Vector2(0,-1),Vector2(1,-2),Vector2(1,-1),Vector2(2,-1),Vector2(1,0),Vector2(2,1),Vector2(1,1),Vector2(1,2),Vector2(0,1),Vector2(-1,2),Vector2(-1,1),Vector2(-2,1),Vector2(-1,0),Vector2(-2,-1),Vector2(-1,-1),Vector2(-1,-2)]
	var numeric_ok := Structure.direction_index(Vector2.ZERO) == 8
	for index: int in directions.size(): numeric_ok = numeric_ok and Structure.direction_index(directions[index]) == index and Registry.direction_index(directions[index]) == index
	check(numeric_ok,"all16 original Mir direction vectors and zero preserve original numeric selection")
	check(Structure.sequence_index(0,[{"direction_index":14},{"direction_index":2}]) == 1 and Structure.sequence_index(15,[{"direction_index":14},{"direction_index":0}]) == 1 and Structure.sequence_index(2,4) == 1,"nearest sparse sequence uses clockwise tie and original numeric-count rounding including wrap")
	var selection_ok := true
	var merge_ok := true
	var cases := 0
	var cold_skill := ""
	for skill: String in metadata.metadata.profiles:
		var full: Dictionary = Registry.profile(skill)
		var expected: Dictionary = full.duplicate(true)
		for key: String in Registry.visual_profile(skill):
			if not expected.has(key) and key != "animation": expected[key] = Registry.visual_profile(skill)[key]
		var binding: Dictionary = Structure.binding(metadata.metadata,skill)
		merge_ok = merge_ok and not binding.is_empty() and binding.factory_profile == expected
		var phases: Array[String] = [""]
		for phase: String in full.get("animation_phases",{}): phases.append(phase)
		for phase: String in phases:
			var animation: Dictionary = Structure.animation_profile(full,phase)
			if animation.get("contract") != "caster_skill_animation.v1" or animation.get("sequences",[]).is_empty(): continue
			for direction: int in range(16):
				var normalized: int = direction if int(animation.get("direction_count",1)) > 1 else 0
				var selected: Dictionary = Structure.select_sequence(animation,direction)
				var actual: Dictionary = animation.sequences[_oracle(normalized,animation.sequences)]
				selection_ok = selection_ok and selected.sequence == actual and selected.accepted == (not actual.get("frames",[]).is_empty())
				cases += 1
		if cold_skill.is_empty() and Structure.projectile_structure(full,Vector2.RIGHT).animation_accepted and not Registry.animation_sequence_paths(skill,4).is_empty(): cold_skill = skill
	check(merge_ok,"every published catalog skill obtains the original factory merge without boot-workset filtering")
	check(selection_ok and cases > 0,"actual full-catalog phase/direction structures match independent nearest-clockwise ordering: "+str(cases))
	check(Structure.binding(metadata.metadata,"not.registered.skill").is_empty() and not Structure.binding(metadata.metadata,"").is_empty(),"unknown skill is rejected while the original unbound empty-skill fallback stays explicit")
	check(not cold_skill.is_empty(),"actual catalog supplies a nonempty structurally accepted projectile")
	if not cold_skill.is_empty(): _exercise_actual_animation(cold_skill)
	_exercise_actual_ground_leaf(metadata)
	_finish(token)

func _exercise_actual_animation(skill: String) -> void:
	var paths: Array[String] = Registry.animation_sequence_paths(skill,4)
	var baseline: int = Registry.frame_texture_cache_diagnostics().leased_sequence_refcount_total
	check(Registry.pending_warm_path_count() == 0 and not Registry.sequence_resident(paths),"isolated actual selected sequence begins cold with no preexisting warm demand")
	Registry.set_loading_window_active(false)
	var waiter := AnimationPlayerCode.new(); add_child(waiter)
	check(waiter.configure(skill,Vector2.RIGHT) and not waiter.visual_loaded and waiter.get("_waiting_for_residency") and not waiter.get("_sequence_lease_held"),"original cold configure accepts structure immediately without a resident-frame or fictitious lease requirement")
	waiter.free()
	check(Registry.frame_texture_cache_diagnostics().leased_sequence_refcount_total == baseline,"a never-acquired actual waiter exit cannot release another sequence owner")
	# These are actual queued logical paths, not threaded request entitlements.
	# Resolve this one selected sequence with the original Loading loader for
	# the subsequent physical lease check; no full catalog/direction prewarm.
	Registry.set_loading_window_active(true)
	var loaded := true
	while Registry.pending_warm_path_count() > 0:
		for path: String in Registry.take_pending_warm_paths(4):
			var texture: Texture2D = Registry.load_texture_path(path)
			loaded = texture != null and paths.has(path) and loaded
	check(loaded and Registry.sequence_resident(paths),"actual original loader resolves the demanded selected sequence in bounded batches")
	Registry.set_loading_window_active(false)
	var first := AnimationPlayerCode.new(); add_child(first)
	var second := AnimationPlayerCode.new(); add_child(second)
	check(first.configure(skill,Vector2.RIGHT) and second.configure(skill,Vector2.RIGHT) and first.get("_sequence_lease_held") and second.get("_sequence_lease_held"),"two real AnimationPlayers acquire their own actual resident sequence references")
	check(Registry.frame_texture_cache_diagnostics().leased_sequence_refcount_total == baseline+2*paths.size(),"actual lease counter counts both complete-sequence owners")
	second.configure(skill,Vector2.RIGHT)
	check(Registry.frame_texture_cache_diagnostics().leased_sequence_refcount_total == baseline+2*paths.size(),"original reconfigure releases then reacquires once without stacking phantom leases")
	first.free(); second.free()
	check(Registry.frame_texture_cache_diagnostics().leased_sequence_refcount_total == baseline,"real node exits release exactly acquired animation sequence references")
	Registry.set_loading_window_active(true)

func _exercise_actual_ground_leaf(metadata: Dictionary) -> void:
	var root := Node2D.new(); add_child(root)
	var host: Object = ClassDB.instantiate("HardCoreSimulationHost")
	var world := {"contract_id":"hardcore.execution.world_context.v1","world_runtime_id":root.get_instance_id(),"runtime_map_id":913203,"world_epoch":1,"profile_id":"physical-ground-component"}
	var executor := Executor.new()
	var configured: bool = executor.configure_main(root,world,metadata,_unexpected_actor,host,Callable(host,"sample_main_thread_cpu_usec"),8)
	check(configured,"actual Main ground kernel uses real metadata and CPU provider; it does not admit a Source command")
	if not configured: root.free(); return
	check(executor.execute({}).get("success") != true,"direct component input cannot bypass actual claimed Source journal admission")
	for skill: String in ["","wizard.fire_wall"]:
		var ground := Ground.new(); ground.skill_id = skill; root.add_child(ground)
		var identity := {"world":world,"runtime_id":ground.get_instance_id(),"life_generation":1}
		# Physical leaf only: retain the actual node under an explicit component
		# identity. This does not create a fake Source registry or Native event.
		executor.get("_casts")[identity.runtime_id] = {"identity":identity,"node":ground}
		var actual: Dictionary = executor.redraw_cast({"identity":identity,"only_without_sprite":true})
		check(actual.get("success") == true and actual.get("actual_redraw_without_sprite") == (ground.get("_sprite") == null),"conditional original ground redraw follows the actual sprite installer for "+skill)
		check(executor.redraw_cast({"identity":identity,"only_without_sprite":1}).get("success") != true,"conditional redraw rejects numeric truthiness")
		executor.get("_casts").erase(identity.runtime_id); ground.free()
	root.free()

func _unexpected_actor(_identity: Dictionary) -> Node2D:
	check(false,"physical component never resolves a fake Source actor")
	return null

func _finish(token: Dictionary) -> void:
	check(Gate.release_after_host_quiescence(token),"component leaves no Source reader when releasing its actual catalog token")
	var written: bool = _proof.write_receipt("caster_owner_structure_20261016",_proof.records.size(),_failed)
	print("CASTER_OWNER_STRUCTURE_20261016_","PASS" if written and _failed == 0 else "FAIL"," checks=",_proof.records.size()," failures=",_failed)
	get_tree().quit(0 if written and _failed == 0 else 1)
