extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Gate := preload("res://scripts/gameplay/content/catalog_publication_gate.gd")
const NumericPublisher := preload("res://scripts/gameplay/world/world_skill_timing_publication.gd")
const Publisher := preload("res://scripts/gameplay/world/world_caster_visual_publication.gd")
const Port := preload("res://scripts/gameplay/world/world_caster_visual_port.gd")
const TimingPort := preload("res://scripts/gameplay/world/world_skill_timing_port.gd")
const Professions := preload("res://scripts/gameplay/profile/rules/professions_core.gd")
const Registry := preload("res://scripts/caster_skill_visual_registry.gd")
const ViewportPort := preload("res://scripts/gameplay/world/world_visual_viewport_port.gd")
var _proof := Proof.new()
var _checks := 0
var _failures := 0
var _thread := Thread.new()
var _lease: Dictionary
var _numeric: Dictionary
var _published: Dictionary
var _expected: Dictionary

func _check(value: bool, name: String) -> void:
	_checks += 1
	_failures += 0 if value else 1
	_proof.record(value, name)

func _ready() -> void:
	var actual_view := Node2D.new()
	add_child(actual_view)
	var world := {"contract_id":"hardcore.execution.world_context.v1","world_runtime_id":actual_view.get_instance_id(),"world_epoch":1,"runtime_map_id":913203,"profile_id":"viewport_capture_fixture"}
	var viewport_publication := ViewportPort.capture_original_main(actual_view, world, 1)
	_check(not viewport_publication.is_empty() and viewport_publication.canvas_transform == actual_view.get_canvas_transform() and viewport_publication.visible_rect == actual_view.get_viewport().get_visible_rect(), "actual Main canvas/viewport captured")
	_check(viewport_publication.is_read_only() and viewport_publication.world_identity.is_read_only(), "actual viewport graph independently sealed")
	var wrong_world := world.duplicate(true)
	wrong_world.world_runtime_id += 1
	_check(ViewportPort.capture_original_main(actual_view, wrong_world, 2).is_empty(), "viewport cannot be relabeled to a different root")
	actual_view.queue_free()
	_lease = Gate.publish("actual_caster_metadata_20261014")
	_numeric = NumericPublisher.publish(_lease)
	_published = Publisher.publish(_lease, _numeric)
	_check(not _lease.is_empty() and not _numeric.is_empty() and not _published.is_empty(), "actual Main registry capture")
	if _published.is_empty():
		_finish()
		return
	for skill: String in _numeric.profiles:
		var source := Registry.profile(skill)
		var phases: Array = [""]
		phases.append_array(source.get("animation_phases", {}).keys())
		var expected := {"profile":source, "visual":Registry.visual_profile(skill), "ready":Registry.is_runtime_ready(skill), "phases":{}}
		for phase: String in phases:
			expected.phases[phase] = {"duration":Registry.animation_duration(skill, phase), "render":Registry.render_policy(skill, phase)}
		_expected[skill] = expected
	_check(_thread.start(_run_owner.bind(GameData.profession_growth_source_path)) == OK, "real owner thread started")

func _run_owner(growth_path: String) -> Dictionary:
	var entered := Gate.enter_reader(_lease)
	if not entered: return {"entered":false}
	var professions := Professions.new(growth_path)
	var timing := TimingPort.create_owner(_numeric, professions)
	var port := Port.create_owner(_published, _numeric, professions, timing)
	var rows: Dictionary = {}
	if port != null:
		for skill: String in _expected:
			var row := {"profile":port.profile(skill), "visual":port.visual_profile(skill), "ready":port.is_runtime_ready(skill), "phases":{}}
			for phase: String in _expected[skill].phases:
				row.phases[phase] = {"duration":port.animation_duration(skill, phase), "render":port.render_policy(skill, phase)}
			var mutable: Dictionary = port.profile(skill)
			mutable["fixture_mutation"] = true
			row["independent_result"] = not port.profile(skill).has("fixture_mutation")
			rows[skill] = row
	var roles_match: bool = port != null and port.ROLE_PROJECTILE == Registry.ROLE_PROJECTILE and port.ROLE_GROUND_EFFECT == Registry.ROLE_GROUND_EFFECT and port.ROLE_LINE_EFFECT == Registry.ROLE_LINE_EFFECT and port.ROLE_SELF_EFFECT == Registry.ROLE_SELF_EFFECT and port.ROLE_SELF_AREA == Registry.ROLE_SELF_AREA and port.ROLE_SUMMON_ACTOR == Registry.ROLE_SUMMON_ACTOR
	return {"entered":entered,"created":port != null,"roles_match":roles_match,"rows":rows,"left":Gate.leave_reader(_lease)}

func _process(_delta: float) -> void:
	if not _thread.is_started() or _thread.is_alive(): return
	var result: Dictionary = _thread.wait_to_finish()
	_check(result.get("entered", false) and result.get("created", false) and result.get("left", false), "actual owner lease lifecycle")
	_check(result.get("roles_match", false), "original casting consumers retain role constants")
	for skill: String in _expected:
		var actual: Dictionary = result.get("rows", {}).get(skill, {})
		_check(actual.get("profile") == _expected[skill].profile, "actual full profile " + skill)
		_check(actual.get("visual") == _expected[skill].visual, "actual visual profile " + skill)
		_check(actual.get("ready") == _expected[skill].ready and actual.get("phases") == _expected[skill].phases, "same existing timing formulas " + skill)
		_check(actual.get("independent_result", false), "independent mutable result " + skill)
	_check(Gate.release_after_host_quiescence(_lease), "actual completed fixture reader released")
	_finish()

func _finish() -> void:
	var written := _proof.write_receipt("multicore_caster_metadata_20261014", _checks, _failures)
	print("MULTICORE_CASTER_METADATA_", "PASS" if written and _failures == 0 else "FAIL")
	get_tree().quit(0 if written and _failures == 0 else 1)
