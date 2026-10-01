extends Node
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Root := preload("res://tests/framework/fixtures/lease_probe_root.gd")
const Fixture := preload("res://tests/helpers/formal_world_skill_fixture.gd")
const Relic := preload("res://scripts/layers/rules/relic_synthesis_rules.gd")
var proof := Proof.new()
var errors: Array[String] = []
var checks := 0
func check(value: bool, label: String) -> void:
 proof.record(value, label)
 checks += 1
 if not value: errors.append(label)
func _ready() -> void:
 _run.call_deferred()
func _run() -> void:
 PlayerState.test_mode = true
 PlayerState.reset_progress(false)
 PlayerState.profession = "法师"
 PlayerState.level = 50
 PlayerState.learned_skills = {"hc.skill.wizard.lightning":3}
 var item_rng := RandomNumberGenerator.new()
 item_rng.seed = 950102
 var catalog := Relic.record_for_id(950102)
 var relic: Dictionary = PlayerState._make_item_instance(str(catalog.name), catalog, 5302, false)
 relic.merge(Relic.roll_instance(950102, "法师", item_rng), true)
 PlayerState.equipment["hc.slot.relic"] = relic
 PlayerState.recalculate_stats(false)
 var proc_rng := RandomNumberGenerator.new()
 for seed_value: int in range(100):
  proc_rng.seed = seed_value
  if proc_rng.randi_range(0, 99) < Relic.PROC_CHANCE_PERCENT:
   proc_rng.seed = seed_value
   break
 PlayerState.configure_relic_proc_rng(proc_rng)
 var game := Root.new()
 add_child(game)
 var deadline := Time.get_ticks_msec() + 20000
 while not game.gameplay_input_is_enabled() and Time.get_ticks_msec() < deadline:
  await get_tree().process_frame
 check(game.gameplay_input_is_enabled(), "real mapped world ready")
 if not game.gameplay_input_is_enabled():
  _finish()
  return
 var target := await Fixture.prepare_target(self, game, game.player, 19, "framework_legacy_release_stat")
 check(target != null and target.projection_ready(), "formal source-ID receiver ready")
 if target == null:
  _finish()
  return
 target.max_hp = 10000
 target.current_hp = 10000
 game.set_process(false)
 game.set_physics_process(false)
 game.player.set_physics_process(false)
 check(PlayerState.feature_bundle().sources.is_empty(), "default-off extensions have no active numeric contributions")
 check(float(PlayerState.relic_proc_status().remaining) == 0.0, "relic is idle before input")
 # A deliberately distinct accepted value proves whether release uses the
 # existing live relic owner or incorrectly captures the previous value.
 PlayerState.computed_stats["magic_min"] = 100
 PlayerState.computed_stats["magic_max"] = 100
 var configuration: RefCounted = game._capture_action_configuration("hc.skill.wizard.lightning")
 game.player.current_mp = game.player.max_mp
 game._set_magic_locked_target(target, true)
 game._skill_cast_target = target
 check(game.player.request_skill("hc.skill.wizard.lightning", target.get_instance_id(), configuration), "natural typed request is accepted")
 deadline = Time.get_ticks_msec() + 3000
 while game.observed_releases == 0 and Time.get_ticks_msec() < deadline:
  await get_tree().process_frame
 check(game.observed_releases == 1 and bool(game.observed_execution.get("accepted", false)), "actual release executes once")
 check(float(PlayerState.relic_proc_status().remaining) > 0.0, "real relic triggers at original release boundary")
 var roll: int = game.observed_target_context.get("primary_stat_roll", -1)
 check(roll >= int(PlayerState.computed_stats.magic_min) and roll <= int(PlayerState.computed_stats.magic_max) and roll < 100,
  "default-off first relic proc participates in the same live release formula")
 game.queue_free()
 await get_tree().process_frame
 _finish()
func _finish() -> void:
 if not proof.write_receipt("legacy_release_stat_test", checks, errors.size()): errors.append("receipt")
 print(("FRAMEWORK_LEGACY_RELEASE_STAT_PASS" if errors.is_empty() else "FRAMEWORK_LEGACY_RELEASE_STAT_FAIL") + " checks=" + str(checks) + " errors=" + str(errors))
 get_tree().quit(0 if errors.is_empty() else 1)
