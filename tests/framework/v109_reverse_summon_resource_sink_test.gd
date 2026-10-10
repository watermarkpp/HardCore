extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Root := preload("res://scripts/game_root.gd")
const RelicRules := preload("res://scripts/layers/rules/relic_synthesis_rules.gd")

var proof := Proof.new()
var failures: Array[String] = []
var checks := 0
var game: Node

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	checks += 1
	if not value:
		failures.append(label)

func _ready() -> void:
	_run.call_deferred()

func _legal_relic(item_id: int, serial: int) -> Dictionary:
	var catalog := GameData.get_item_record({"item_id": item_id})
	if catalog.is_empty():
		catalog = GameData.get_item_record(str(RelicRules.record_for_id(item_id).get("name", "")))
	var instance := PlayerState._make_item_instance(str(catalog.get("name", "")), catalog, serial, false)
	var rng := RandomNumberGenerator.new()
	for seed in range(1, 1000):
		rng.seed = seed
		var rolled := RelicRules.roll_instance(item_id, "道士", rng)
		if str(rolled.get("relic_roll", {}).get("skill_id", "")) == "taoist.summon_skeleton":
			instance.merge(rolled, true)
			return instance
	return {}

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.profession = ProfessionRules.profession_display_name("taoist")
	PlayerState.level = 40
	var skill_name := ProfessionRules.skill_display_name("taoist.summon_skeleton")
	PlayerState.learned_skills = {skill_name: 3}
	var relic := _legal_relic(950101, 7101)
	var badge := _legal_relic(950203, 7102)
	check(not relic.is_empty() and not badge.is_empty(), "formal legal relic and badge instances are generated")
	if relic.is_empty() or badge.is_empty():
		_finish()
		return
	PlayerState.equipment["hc.slot.relic"] = relic
	PlayerState.recalculate_stats(false)
	check(PlayerState.effective_skill_level("taoist.summon_skeleton") == 4,
		"initial legal equipment establishes rank four")

	game = Root.new()
	add_child(game)
	var deadline := Time.get_ticks_msec() + 30000
	while not game.gameplay_input_is_enabled() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(game.gameplay_input_is_enabled(), "formal GameRoot reaches READY")
	if not game.gameplay_input_is_enabled():
		_finish()
		return
	game.player.current_mp = 1000

	# Establish one real live skeleton while rank four is active. This is the
	# precondition for the accepted-rank-five spawn attempt below.
	var initial_lease: RefCounted = game._capture_action_configuration("taoist.summon_skeleton")
	check(initial_lease != null and initial_lease.rank() == 4,
		"initial ActionLease captures rank four")
	if initial_lease == null:
		_finish()
		return
	check(initial_lease.accept(PlayerState.action_configuration_versions(), game._action_configuration_identity()),
		"initial ActionLease is accepted")
	var initial_mp: int = game.player.current_mp
	var initial_result: Dictionary = game._execute_canonical_skill(
		"召唤骷髅", game.player.global_position, Vector2.DOWN, 0,
		{"release_id": "reverse:initial"}, true, false, initial_lease
	)
	check(bool(initial_result.get("accepted", false)),
		"formal rank-four summon release is accepted")
	var first_pet: SummonActor = game._canonical_main_pet("skeleton")
	check(first_pet != null, "formal rank-four release creates the first live skeleton")
	if first_pet == null:
		_finish()
		return
	check(game.player.current_mp < initial_mp, "initial spawn commits its canonical MP cost")

	# Accept rank five while the +1 badge is equipped, then remove it before
	# release. The accepted lease must retain rank five; the final live cap is
	# rank four (one skeleton), so the sink must reject before resource commit.
	PlayerState.equipment["hc.slot.badge"] = badge
	PlayerState.recalculate_stats(false)
	check(PlayerState.effective_skill_level("taoist.summon_skeleton") == 5,
		"legal badge raises the live rank to five before acceptance")
	var accepted_rank_five: RefCounted = game._capture_action_configuration("taoist.summon_skeleton")
	check(accepted_rank_five != null and accepted_rank_five.rank() == 5,
		"ActionLease captures accepted rank five")
	if accepted_rank_five == null:
		_finish()
		return
	check(accepted_rank_five.accept(PlayerState.action_configuration_versions(), game._action_configuration_identity()),
		"rank-five ActionLease is accepted")
	PlayerState.equipment.erase("hc.slot.badge")
	PlayerState.recalculate_stats(false)
	check(PlayerState.effective_skill_level("taoist.summon_skeleton") == 4,
		"removing the badge lowers live rank to four before release")
	var mp_before_release: int = game.player.current_mp
	var pet_count_before: int = game._canonical_main_pets("skeleton").size()
	var release_result: Dictionary = game._execute_canonical_skill(
		"召唤骷髅", game.player.global_position, Vector2.DOWN, 0,
		{"release_id": "reverse:accepted-rank-five"}, true, false, accepted_rank_five
	)
	var release_plan: Dictionary = release_result.get("canonical_plan", {})
	var release_quote: Dictionary = release_plan.get("resource_cost", {})
	check(bool(release_plan.get("rejection", {}).get("accepted", false)),
		"accepted rank-five plan reaches the formal release chain")
	check(int(release_quote.get("mp_cost", 0)) > 0,
		"rank-five spawn plan carries its normal MP quote")
	check(not bool(release_result.get("accepted", true)),
		"live-cap change rejects the spawn before resource commit")
	check(game.player.current_mp == mp_before_release,
		"live-cap rejection does not consume MP")
	check(game._canonical_main_pets("skeleton").size() == pet_count_before,
		"live-cap rejection does not create a summon beyond the live cap")
	check(str(release_result.get("reason", "")) == "summon_live_cap_changed",
		"release reports the live-cap handoff reason")

	_finish()

func _finish() -> void:
	if is_instance_valid(game):
		game.queue_free()
	var valid := proof.write_receipt("v109_reverse_summon_resource_sink_test", checks, failures.size())
	if not valid:
		failures.append("receipt failed")
	print("V109_REVERSE_SUMMON_RESOURCE_SINK_", "PASS" if failures.is_empty() else "FAIL",
		" checks=", checks, " failures=", failures)
	get_tree().quit(0 if valid and failures.is_empty() else 1)
