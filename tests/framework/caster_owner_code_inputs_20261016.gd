extends "res://tests/framework/main_launch_loading_scope_20261015.gd"

## Real original CharacterSelect code lease and covered Native checkpoint.
## This is a Main code-owner component; no Source or full-world readiness.
const CasterExecutor := preload("res://scripts/gameplay/world/world_caster_main_executor.gd")
const CasterRegistry := preload("res://scripts/caster_skill_visual_registry.gd")
const CasterGate := preload("res://scripts/gameplay/content/catalog_publication_gate.gd")
const CasterTiming := preload("res://scripts/gameplay/world/world_skill_timing_publication.gd")
const CasterPublication := preload("res://scripts/gameplay/world/world_caster_visual_publication.gd")

func _inspect_actual_launch(request: Dictionary) -> void:
	super._inspect_actual_launch(request)
	if _failed > 0 or not is_instance_valid(_root): return
	var identity: Dictionary = Identity.inspect_original_root_identity(_root,_facade)
	check(identity.get("success") == true,"Caster code owner retains the actual selected guarded Root")
	if identity.get("success") != true: return
	var begun: Dictionary = _router.begin_original_character_launch(_launcher,identity.world)
	check(begun.get("success") == true,"actual original callback stack opens its own new current checkpoint")
	if begun.get("success") != true: return
	var deferred: Object = ClassDB.instantiate("HardCoreMainSourceDeferred")
	var source: Script = _router.get_script()
	check(deferred.configure_original_checkpoint_producer(_router,source.resource_path,source.get_source_code().sha256_text()),"actual Native observer authenticates the real checkpoint producer Script")
	var terminal: Dictionary = deferred.flush_original_main_source_checkpoint(begun.checkpoint,_facade,_content,_content._feature_resources())
	check(terminal.get("success") == true,"actual Native checkpoint flush reaches original Main receiver and IO terminal facts: "+str(terminal))
	if terminal.get("success") == true: _exercise_actual_owner(begun.checkpoint,deferred,identity.world)
	check(_router.abort_original_checkpoint(begun.checkpoint).get("success") == true,"component abort restores the real uncommitted original checkpoint")

func _exercise_actual_owner(checkpoint: Dictionary, deferred: Object, world: Dictionary) -> void:
	var token: Dictionary = CasterGate.publish("actual-caster-code-owner:"+FileAccess.get_sha256(CasterRegistry.MANIFEST_PATH))
	check(not token.is_empty(),"real catalog gate publishes only this isolated Main owner component")
	var metadata: Dictionary = CasterPublication.publish(token,CasterTiming.publish(token))
	check(not metadata.is_empty(),"actual full-catalog metadata is independent of boot warm workset")
	if metadata.is_empty(): CasterGate.release_after_host_quiescence(token); return
	var executor := CasterExecutor.new()
	var configured: bool = executor.configure_main(_root,world,metadata,_unexpected_caster_actor,_host,Callable(_host,"sample_main_thread_cpu_usec"),8)
	check(configured,"actual Caster Main executor binds actual Root metadata Host CPU provider and capacity")
	if not configured: CasterGate.release_after_host_quiescence(token); return
	var before: Dictionary = CasterRegistry.frame_texture_cache_diagnostics()
	var rejected: Dictionary = executor.prepare_actual_original_owner_closure(115216,checkpoint,deferred,_facade,_content,_content._feature_resources(),{"paths":["res://scripts/caster_skill_animation_player.gd"],"consumer":_launcher})
	check(rejected.get("success") != true and executor.get("_proof").is_empty(),"a filename list cannot manufacture actual code lease or owner proof")
	var result: Dictionary = _launcher.get("_launch_code_result")
	var prepared: Dictionary = executor.prepare_actual_original_owner_closure(115216,checkpoint,deferred,_facade,_content,_content._feature_resources(),{"result":result,"consumer":_launcher})
	check(prepared.get("success") == true,"actual original retained Script Shader lease and checkpoint create owner.v2: "+str(prepared.get("error","")))
	if prepared.get("success") == true:
		var proof: Dictionary = prepared.publication
		check(proof.contract_id == "world.caster.presentation.owner.v2" and not proof.has("bindings") and not proof.has("texture_facts"),"production owner proof has no boot-workset binding or all-direction texture residency entitlement")
		check(proof.code_input_receipt.actual_code_lease_verified and proof.code_input_receipt.code_lease_id == result.lease.get_instance_id() and proof.code_input_receipt.retained_script_runtime_id == result.resource.get_instance_id() and not proof.code_input_receipt.actual_resource_facts.is_empty(),"owner code receipt records actual physical lease Script Shader and executor objects")
		var pins: Dictionary = executor.inspect_actual_original_loading_pins(proof)
		check(pins.get("success") == true and pins.actual_sequence_lease_paths.is_empty() and pins.actual_retained_texture_count == 0 and pins.actual_code_inputs_current and pins.actual_current_code_consumer_id == _launcher.get_instance_id(),"real owner inspector proves the actual current consumer and code retention without an additional texture sequence lease")
		var after: Dictionary = CasterRegistry.frame_texture_cache_diagnostics()
		check(after.leased_sequence_refcount_total == before.leased_sequence_refcount_total and after.entries == before.entries and after.loads == before.loads,"owner preparation performs no animation frame load or extra sequence acquire")
		check(executor.release_loading_closure(115216),"owner close releases only its actual held references after no accepted effects remain")
		check(executor.get("_code_result").is_empty() and executor.get("_code_objects").is_empty() and not executor.get("_loading_sequence_lease_held"),"closed Caster retains no code or phantom Loading sequence ownership")
		check(_content.is_internal_code_retention_current(result,_launcher),"Caster close does not retire the external original code lease a second time")
		check(executor.release_loading_closure(115216) and _content.is_internal_code_retention_current(result,_launcher) and CasterRegistry.frame_texture_cache_diagnostics().leased_sequence_refcount_total == before.leased_sequence_refcount_total,"idempotent owner release cannot decrement an unacquired sequence or the external code lease")
	check(CasterGate.release_after_host_quiescence(token),"Main code component leaves no catalog Source reader")

func _unexpected_caster_actor(_identity: Dictionary) -> Node2D:
	check(false,"code-owner preparation never invents a Source actor resolver result")
	return null
