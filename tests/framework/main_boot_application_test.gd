extends Node
## Actual concrete Main bodies. No Host start, success provider doubles, actor
## identity fixtures, profile creation, profile selection or persistence writes.
const App := preload("res://scripts/gameplay/source/main_boot_application.gd")
const Loading := preload("res://scripts/gameplay/source/main_boot_launch_loading.gd")
const MainRoot := preload("res://scripts/gameplay/source/main_boot_root_transport.gd")
const Overlay := preload("res://scripts/loading_transition_overlay.gd")
const Factory := preload("res://scripts/gameplay/source/main_original_boot_provider_factory.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var _proof := Proof.new()
var _failures: Array[String] = []

func check(condition: bool, label: String) -> void:
	_proof.record(condition,label)
	if not condition: _failures.append(label)

func _ready() -> void:
	var facade: Node = get_tree().root.get_node_or_null("PlayerState")
	var content: Node = get_tree().root.get_node_or_null("ContentLayers")
	var model_before: RefCounted = facade.get("_model")
	var profile_before: String = model_before.get("active_profile_id")
	var policy: Dictionary = {"bridge_generation":1,"primitive_request_capacity":4096,"primitive_result_capacity":4096,
		"max_epochs_per_turn":1,"timer_capacity":8,"input_capacity":8,"event_capacity":8,"live_primitive_capacity":4}
	# These are explicit test capacity inputs, never session/ready/pin facts.
	var checked: Dictionary = App.validate_actual_host_policy(policy)
	check(checked.get("success") == true and checked.policy == policy,"explicit_capacity_policy_round_trip")
	checked.policy.input_capacity = 7
	check(policy.input_capacity == 8,"policy_capture_does_not_alias_input")
	var missing: Dictionary = App.validate_actual_host_policy({})
	check(missing.get("status") == "BLOCKED" and missing.details.fields.size() == App.POLICY_KEYS.size(),"no_Host_capacity_or_generation_defaults")
	var invalid: Dictionary = policy.duplicate(true)
	invalid.timer_capacity = 8.0
	check(App.validate_actual_host_policy(invalid).get("status") == "BLOCKED","capacity_types_are_exact_integers")
	invalid = policy.duplicate(true); invalid.live_primitive_capacity = 9
	check(App.validate_actual_host_policy(invalid).get("error") == "original_Host_live_capacity_exceeds_event_capacity","live_capacity_cannot_exceed_event_storage")
	var scope_owner: RefCounted = Loading.new()
	check(scope_owner.configure_main(get_tree(),facade,content),"bind_real_autoload_Loading_observer")
	check(scope_owner.verify_actual_original_loading_scope({}).get("status") == "BLOCKED","no_uncaptured_Loading_scope")
	check(scope_owner.capture_actual_original_launch_loading_scope(self,{}).get("error") == "actual_current_CharacterSelect_launch_required","foreign_receiver_cannot_become_original_launch")
	check(scope_owner.captured_scope().is_empty(),"rejected_capture_produces_no_scope")
	# Exercise the real original overlay's actual headless process handshake.
	var overlay: Control = Overlay.new()
	add_child(overlay)
	check(Loading.capture_original_presented_cover(overlay).get("status") == "BLOCKED","unpresented_real_overlay_does_not_prove_cover")
	overlay.begin_loading("main_boot_application_test",false)
	await overlay.transition_covered
	var covered: Dictionary = Loading.capture_original_presented_cover(overlay)
	check(covered.get("success") == true,"actual_original_overlay_covered_handshake")
	if covered.get("success") == true:
		check(covered.covered == overlay.code_preparation_cover_receipt() and covered.covered.overlay_instance_id == overlay.get_instance_id(),"cover_receipt_is_from_same_actual_overlay")
		overlay.begin_loading("main_boot_application_test_replaced",false)
		check(not overlay.code_preparation_cover_current(covered.covered),"original_overlay_rejects_old_transition_receipt")
	overlay.queue_free()
	# The original cover signal is still emitting when this await resumes.
	# Let its stack return and the engine's actual delete queue run.
	await get_tree().process_frame
	await get_tree().process_frame
	check(not is_instance_valid(overlay), "real overlay retired after original signal returned")
	check(ClassDB.class_exists("HardCoreSimulationHost"),"actual_Native_Host_required")
	if ClassDB.class_exists("HardCoreSimulationHost"):
		var host: Object = ClassDB.instantiate("HardCoreSimulationHost")
		var scene: PackedScene = load("res://scenes/main.tscn")
		var code: Script = preload("res://scripts/game_root.gd")
		var preflight: Dictionary = MainRoot.inspect_actual_Main_constructor(host,scene,code)
		check(preflight.get("success") == true,"actual_pinned_original_Main_constructor_preflight")
		check(preflight.get("host_object_id") == host.get_instance_id() and preflight.get("scene_node_count") == 1,"constructor_preflight_uses_actual_Host_and_scene")
		check(MainRoot.inspect_actual_Main_constructor(host,null,code).get("status") == "BLOCKED","missing_prepared_scene_rejected_before_instantiation")
		# Genuine original constructor; never attach this gameplay template to
		# SceneTree or label a CharacterBody as a renderer.
		var original: Node2D = scene.instantiate()
		check(original.get_script() == code and original.get_child_count() == 1,"original_Main_constructor_has_real_plain_combat_child")
		var combat: Node = original.get("_combat_runtime")
		check(combat != null and combat.get_class() == "Node" and combat.get_parent() == original,"original_combat_child_is_not_physics_actor")
		var identity: Dictionary = App.inspect_original_root_identity(original,facade)
		check(identity.get("status") == "BLOCKED" and identity.get("error") == "prepared_original_Main_has_no_active_runtime_map","fresh_original_Main_cannot_invent_active_map")
		if identity.get("error") == "prepared_original_Main_has_no_active_runtime_map":
			check(identity.details.actual_context.world_runtime_id == original.get_instance_id() and identity.details.actual_context.runtime_map_id == original.get("current_map_id"),"rejected_world_preserves_exact_real_root_context")
		original.free()
		var no_vault: Dictionary = Factory.create_application_main(host,facade,{},policy)
		check(no_vault.get("status") == "BLOCKED" and no_vault.get("error") == "actual_configured_Feature_Main_vault_required","concrete_factory_cannot_promote_missing_physical_vault")
		check(host.status().get("running") != true,"Main_tests_never_claim_Source_physics")
	check(facade.get("_model") == model_before and model_before.get("active_profile_id") == profile_before,"same_Profile_authority_after_all_Main_preparation_checks")
	check(not get_tree().root.has_meta(App.ENTRY_META),"unconfigured_application_never_installs_launch_hook")
	var written: bool = _proof.write_receipt("main_boot_application_test",_proof.records.size(),_failures.size())
	print("MAIN_BOOT_APPLICATION_", "PASS" if written and _failures.is_empty() else "FAIL", " failures=",_failures)
	get_tree().quit(0 if written and _failures.is_empty() else 1)
