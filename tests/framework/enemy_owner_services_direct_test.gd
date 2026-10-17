extends Node

const OwnerBudget := preload("res://scripts/gameplay/enemy/enemy_owner_frame_budget.gd")
const OwnerToken := preload("res://scripts/gameplay/enemy/enemy_owner_context_token.gd")
const OwnerFootprint := preload("res://scripts/gameplay/enemy/enemy_owner_skill_footprint.gd")
const SourceBudget := preload("res://scripts/layers/runtime/execution/frame_budget.gd")
const SourceToken := preload("res://scripts/monster_ai_package/m30/context_token.gd")
const SourceFootprint := preload("res://scripts/skills/skill_footprint_snapshot.gd")
const Spatial := preload("res://scripts/world_spatial_rules.gd")
var checks := 0

class Inputs:
	extends RefCounted
	var epoch := 200
	var usec := 1000
	var ACTOR_GROUND_FOOTPRINT_CONTRACT_ID = Spatial.ACTOR_GROUND_FOOTPRINT_CONTRACT_ID
	func owner_thread_id() -> int: return OS.get_thread_caller_id()
	func get_process_frames() -> int: return epoch
	func get_physics_frames() -> int: return epoch
	func get_ticks_usec() -> int: return usec
	func get_setting(_key: String, fallback: Variant) -> Variant: return fallback
	func tree_is_paused() -> bool: return false
	func actor_footprint_ground_polygon_gu(radius: float) -> PackedVector2Array:
		return Spatial.actor_footprint_ground_polygon_gu(radius)

func _check(value: bool, label: String) -> void:
	checks += 1
	proof.record(value, label)
	assert(value, label)

func _ready() -> void:
	var input := Inputs.new()
	var bindings := {"Engine": input, "Time": input, "ProjectSettings": input, "phase": input, "WorldSpatialRulesScript": input}
	var budget := OwnerBudget.new()
	_check(budget.configure_owner(bindings, input), "budget admitted complete owner ABI")
	var epoch := Callable(input, "get_process_frames")
	var clock := Callable(input, "get_ticks_usec")
	SourceBudget.configure_for_tests(500, epoch, clock)
	budget.configure_for_tests(500, epoch, clock)
	for service in [SourceBudget, budget]:
		service.mark_pending("first", true)
		service.mark_pending("second", true)
	_check(SourceBudget.begin("second") == budget.begin("second"), "same oldest-first fairness denial")
	var old_token: int = SourceBudget.begin("first")
	var new_token: int = budget.begin("first")
	input.usec += 120
	SourceBudget.end(old_token)
	budget.end(new_token)
	_check(SourceBudget.snapshot() == budget.snapshot(), "same source ledger after scope")
	old_token = SourceBudget.begin("second")
	new_token = budget.begin("second")
	input.usec += 460
	SourceBudget.end(old_token)
	budget.end(new_token)
	_check(SourceBudget.snapshot() == budget.snapshot(), "same source overrun/served order")
	input.epoch += 1
	_check(SourceBudget.snapshot() == budget.snapshot(), "same epoch reset without clearing pending age")
	SourceBudget.reset_test_configuration()
	var tokens := OwnerToken.new()
	_check(tokens.configure_owner({}, input), "context admitted")
	var context := {"same_data": true}
	var token: int = tokens.token(context)
	var source_token: int = SourceToken.token(context)
	_check(tokens.token(context) == token and SourceToken.token(context) == source_token, "same Dictionary identity reuses token")
	_check(tokens.token(context.duplicate()) != token and SourceToken.token(context.duplicate()) != source_token, "equal Dictionary data does not alias")
	for index in range(65):
		var distinct := {"index": index}
		tokens.token(distinct)
		SourceToken.token(distinct)
	_check(tokens.retained_count() == SourceToken.retained_count(), "same 64-context bound")
	_check(tokens.token(context) != token and SourceToken.token(context) != source_token, "evicted identity receives new token")
	var footprint := OwnerFootprint.new()
	_check(footprint.configure_owner(bindings, input), "footprint admitted")
	var a := PackedVector2Array([Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN])
	var b := PackedVector2Array([Vector2(1, 0), Vector2(2, 0), Vector2(2, 1), Vector2(1, 1)])
	_check(footprint.convex_polygons_intersect_inclusive_ground_gu(a, b) == SourceFootprint.convex_polygons_intersect_inclusive_ground_gu(a, b), "same touching-edge inclusive footprint")
	_check(footprint.shape_classification("circle") == SourceFootprint.shape_classification("circle"), "same shape contract")
	print("ENEMY_OWNER_SERVICES_DIRECT: PASS checks=", checks, " scope=Main direct source oracle; S native NOT_RUN")
	var receipt_ok := proof.write_receipt("enemy_owner_services_direct_test", proof.records.size(), 0)
	print("ENEMY_OWNER_SERVICES_DIRECT_TEST_", "PASS" if receipt_ok else "FAIL")
	get_tree().quit(0 if receipt_ok else 1)

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var proof := Proof.new()
func _verify(value: bool, label: String) -> void:
	proof.record(value, label)
	assert(value, label)
