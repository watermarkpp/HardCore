extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Root := preload("res://scripts/game_root.gd")
const RelicRules := preload("res://scripts/layers/rules/relic_synthesis_rules.gd")
const Request := preload("res://scripts/skills/skill_cast_request.gd")
const Router := preload("res://scripts/skills/skill_runtime_router.gd")

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
	var relic := _legal_relic(950101, 6101)
	var badge := _legal_relic(950203, 6102)
	check(not relic.is_empty() and not badge.is_empty(), "formal legal relic and badge instances are generated")
	if relic.is_empty() or badge.is_empty():
		_finish()
		return
	PlayerState.equipment["hc.slot.relic"] = relic
	PlayerState.recalculate_stats(false)
	check(PlayerState.effective_skill_level("taoist.summon_skeleton") == 4,
		"legal relic recompute raises live skeleton rank to four")

	game = Root.new()
	add_child(game)
	var deadline := Time.get_ticks_msec() + 30000
	while not game.gameplay_input_is_enabled() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(game.gameplay_input_is_enabled(), "formal GameRoot reaches READY")
	if not game.gameplay_input_is_enabled():
		_finish()
		return

	var accepted: RefCounted = game._capture_action_configuration("taoist.summon_skeleton")
	check(accepted != null and accepted.rank() == 4, "ActionLease captures accepted rank four")
	if accepted == null:
		_finish()
		return
	check(accepted.accept(PlayerState.action_configuration_versions(), game._action_configuration_identity()),
		"formal ActionLease accepts the summon configuration")

	# The active pet is at the accepted rank-4 group limit. This is the exact
	# release-time context where the accepted action must be a free recall.
	var accepted_context: Dictionary = game._canonical_resource_context("taoist.summon_skeleton", accepted)
	accepted_context["mana"] = 0
	accepted_context["active_main_pet_summon_ids"] = ["skeleton"]
	accepted_context["active_skeleton_count"] = 1
	accepted_context["requested_main_pet_summon_id"] = "skeleton"
	accepted_context["effective_skill_rank"] = accepted.rank()

	# A second legal item is equipped after acceptance. The live rank changes to
	# five, but the accepted request must continue quoting rank four.
	PlayerState.equipment["hc.slot.badge"] = badge
	PlayerState.recalculate_stats(false)
	check(PlayerState.effective_skill_level("taoist.summon_skeleton") == 5,
		"legal badge recompute changes live rank after acceptance")
	accepted_context["effective_skill_rank"] = PlayerState.effective_skill_level("taoist.summon_skeleton")

	var request := Request.create("taoist.summon_skeleton", accepted.rank(), accepted.actor_level(),
		Vector2i.ZERO, Vector2i.DOWN, {
			"requested_main_pet_summon_id": "skeleton",
			"active_main_pet_summon_ids": ["skeleton"],
			"active_skeleton_count": 1,
			"spawn_tile_valid": true,
		}, accepted_context, 17)
	request["action_config_lease"] = accepted
	# The self-summon has no spatial footprint. Exercise the single underlying
	# planner used by build_canonical_plan so its real request -> quote -> Taoist
	# runtime chain is tested without inventing a geometry snapshot.
	var plan: Dictionary = Router._plan(request, accepted.definition_for("taoist.summon_skeleton"))
	check(bool(plan.get("accepted", false)),
		"accepted summon request survives live rank change through the formal router")
	var resource_quote: Dictionary = plan.get("resource_quote", plan.get("resource_cost", {}))
	check(int(resource_quote.get("mp_cost", -1)) == 0 and bool(resource_quote.get("main_pet_recall", false)),
		"rank-four accepted recall is free despite live rank-five context")
	var effects: Array = plan.get("effects", [])
	check(not effects.is_empty() and str(effects[0].get("type", "")) == "recall_existing_main_pet",
		"taoist runtime consumes the same accepted rank and chooses recall")
	_finish()

func _finish() -> void:
	if is_instance_valid(game):
		game.queue_free()
	var valid := proof.write_receipt("v109_accepted_summon_rank_resource_test", checks, failures.size())
	if not valid:
		failures.append("receipt failed")
	print("V109_ACCEPTED_SUMMON_RANK_RESOURCE_", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
