extends Node
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const World := preload("res://scripts/layers/runtime/execution/world_context.gd")
var _zone_generation := 31
var current_map_id := 910001
var proof := Proof.new()
var checks := 0
var errors: Array[String] = []
func check(value: bool,label: String) -> void:
	proof.record(value,label); checks += 1
	if not value: errors.append(label)
func _ready() -> void:
	PlayerState.test_mode = true; PlayerState.reset_progress(false)
	PlayerState.active_profile_id = "framework-profile-generation"
	# Imported role snapshots carry legal string ledger generations. Drive the
	# actual PlayerState restore boundary, rather than a second fixture owner.
	var snapshot: Dictionary = PlayerState._creation_runtime_snapshot()
	snapshot.world_clock_generation = "a".repeat(32)
	PlayerState._restore_creation_runtime(snapshot)
	var world := World.new(); world.configure(self,PlayerState)
	var before_world := world.capture_world()
	var before_profile := world.capture_profile()
	var raw_before: String = PlayerState._world_clock_generation
	check(not raw_before.is_empty() and before_profile.world_clock_generation is String \
		and str(before_profile.world_clock_generation) == raw_before,"profile identity preserves exact actual string generation without coercion")
	check(world.matches_profile(before_profile),"current profile receipt identity matches its original owner")
	_zone_generation += 1
	check(world.matches_profile(before_profile) and not world.matches_world(before_world),"ordinary map transition changes mutation identity and preserves profile receipt owner")
	snapshot.world_clock_generation = "b".repeat(32)
	PlayerState._restore_creation_runtime(snapshot)
	check(PlayerState._world_clock_generation != raw_before,"actual restore replaces the character clock ledger identity")
	check(not world.matches_profile(before_profile),"same profile ID after character restore rejects prior economic lifecycle")
	check(str(world.capture_profile().world_clock_generation) == PlayerState._world_clock_generation,"new quote binds exact new generation rather than a numeric truncation")
	if not proof.write_receipt("profile_identity_generation_test",checks,errors.size()): errors.append("receipt")
	print("PROFILE_IDENTITY_GENERATION_%s checks=%d errors=%s" % ["PASS" if errors.is_empty() else "FAIL",checks,str(errors)])
	get_tree().quit(0 if errors.is_empty() else 1)
