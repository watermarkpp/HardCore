extends Node

## Direct source comparison only. Root must also run formal world regressions.
## No NativeWorld fixture or fake collision/damage provider appears here.
const Original := preload("res://tests/framework/fixtures/enemy_original_oracle.gd")
const Candidate := preload("res://scripts/enemy.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var proof := Proof.new()
var checks := 0
var failures: Array[String] = []

func check(value: bool, label: String) -> void:
	checks += 1
	proof.record(value, label)
	if not value: failures.append(label)

func _ready() -> void:
	_run.call_deferred()

func _fresh(script: Script) -> Node:
	var actor: Node = script.new()
	actor.monster_id = 19
	actor.max_hp = 100
	actor.current_hp = 100
	actor.runtime_map_id = 4
	actor.set_meta("hc_combat_life_epoch", 3)
	actor.set_meta("zone_generation", 7)
	actor._rng.seed = 7614321
	return actor

func _run() -> void:
	var old := _fresh(Original)
	var fresh := _fresh(Candidate)
	check(fresh.get("domain_model") != null, "RED before integration: Enemy has domain authority")
	var model: RefCounted = fresh.get("domain_model")
	if model == null:
		old.free()
		fresh.free()
		_finish()
		return
	check(model.runtime_actor_id() == fresh.get_instance_id(), "model binds original canonical positive Node identity on Main")
	check(model.runtime_actor_id() > 0 and model.runtime_actor_id() != model.get_instance_id(), "model RefCounted ID never becomes source identity")
	fresh.current_hp = 83
	check(model.current_hp == 83, "facade writes sole HP authority")
	model.current_hp = 100
	check(fresh.current_hp == 100, "facade reads same model HP")
	model.write_meta("hc_combat_life_epoch", 4)
	check(fresh.get_meta("hc_combat_life_epoch") == 4 and model.current_life() == 4, "single life metadata authority")
	fresh.set_meta("hc_combat_life_epoch", 3)
	old.consume_direct_magic_compatibility_roll()
	fresh.consume_direct_magic_compatibility_roll()
	check(old._rng.state == fresh._rng.state, "direct magic preserves original single RNG draw")
	for amount: int in [-9, 0, 7, 11]:
		old.take_damage(amount, null)
		fresh.take_damage(amount, null)
		check(old.current_hp == fresh.current_hp, "ordinary damage HP oracle " + str(amount))
		check(old._rng.state == fresh._rng.state, "ordinary damage RNG oracle " + str(amount))
	var before: int = fresh.current_hp
	old._body_admission_rejected = true
	fresh._body_admission_rejected = true
	old.take_damage(999, null)
	fresh.take_damage(999, null)
	check(old.current_hp == before and fresh.current_hp == before, "rejected body cannot enter damage closure")
	old._body_admission_rejected = false
	fresh._body_admission_rejected = false
	var old_receipt := {"hp_before":-1,"hp_after":-1,"actual_loss":-1}
	var new_receipt := old_receipt.duplicate()
	old._apply_damage_core(13, null, {"feature_damage_receipt":old_receipt}, false)
	fresh._apply_damage_core(13, null, {"feature_damage_receipt":new_receipt}, false)
	check(old_receipt == new_receipt and new_receipt.actual_loss == 13, "periodic committed HP receipt oracle")
	check(old.current_hp == fresh.current_hp, "periodic HP oracle")
	old.take_damage(999, null)
	fresh.take_damage(999, null)
	check(old.current_hp == 0 and fresh.current_hp == 0 and fresh._death_pending, "lethal synchronous closure precedes deferred presentation")
	check(old.get_meta("hc_combat_life_epoch") == fresh.get_meta("hc_combat_life_epoch"), "lethal original life increment oracle")
	check(model.current_hp == fresh.current_hp and model.current_life() == fresh.get_meta("hc_combat_life_epoch"), "lethal authority remains single")
	check(old.collision_layer == fresh.collision_layer and old.collision_mask == fresh.collision_mask, "lethal body filtering oracle")
	check(not old.can_receive_damage() and not fresh.can_receive_damage(), "death pending damage qualification oracle")
	# Free before the next message-queue turn; this direct test intentionally
	# does not claim SceneTree timers, full visual death or owner S closure.
	old.free()
	fresh.free()
	_finish()

func _finish() -> void:
	if not proof.write_receipt("enemy_full_authority_oracle_test", checks, failures.size()):
		failures.append("receipt")
	print("ENEMY_FULL_AUTHORITY_ORACLE_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL", checks, str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
