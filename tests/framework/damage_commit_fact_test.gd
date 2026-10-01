extends Node
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Enemy := preload("res://scripts/enemy.gd")
const World := preload("res://scripts/layers/runtime/execution/world_context.gd")
var _zone_generation := 1
var current_map_id := 910001
var proof := Proof.new()
var checks := 0
var errors: Array[String] = []
class HealingEnemy extends Enemy:
	var heal_after_commit := false
	func _refresh_overhead_health() -> void:
		if heal_after_commit:
			current_hp = max_hp
		super._refresh_overhead_health()
func check(value: bool, label: String) -> void:
	proof.record(value,label)
	checks += 1
	if not value: errors.append(label)
func _ready() -> void:
	_run.call_deferred()
func _run() -> void:
	var path := "res://scripts/features/runtime/damage_batch.gd"
	check(FileAccess.file_exists(path), "damage batch contract exists at the real HP commit boundary")
	if not FileAccess.file_exists(path):
		_finish()
		return
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	var world := World.new()
	world.configure(self, PlayerState)
	var target := HealingEnemy.new()
	target.setup(GameData.get_monster_by_id(19), null)
	add_child(target)
	target.set_physics_process(false)
	target.max_hp = 100
	target.current_hp = 100
	target.heal_after_commit = true
	var batch_type: Variant = load(path)
	var created: Dictionary = batch_type.create(world, "fact:test:1", "hc.skill.warrior.fire_sword", [], {"profile_id":PlayerState.active_profile_id})
	check(bool(created.success), "batch owns frozen formal skill, release and historical credit")
	if not bool(created.success):
		_finish()
		return
	var batch: RefCounted = created.batch
	check(batch.begin_base_scope(), "base scope opens explicitly")
	check(batch.begin_base_scope(), "nested scope does not publish early")
	target.take_damage(60, null, {"feature_damage_batch":batch,"source_class":"direct","damage_channel":"physical"})
	check(target.current_hp == 100, "synchronous legacy callback actually heals after HP commit")
	var facts: Array = batch.facts()
	check(facts.size() == 1 and facts[0].hp_before == 100 and facts[0].hp_after == 40 and facts[0].actual_loss == 60, "fact captures actual HP write before synchronous healing")
	check(facts.size() == 1 and facts[0].is_read_only() and facts[0].target.is_read_only(), "fact recursively freezes only plain data")
	check(not batch.finish_base_scope() and batch.consume().is_empty(), "nested finish cannot flush while outer base work remains")
	target.current_hp = 30
	target.take_damage(100, null, {"feature_damage_batch":batch,"source_class":"direct","damage_channel":"physical"})
	facts = batch.facts()
	check(facts.size() == 2 and facts[1].actual_loss == 30 and not facts[1].target_survived_commit, "overkill uses actual loss and commit-time death despite later healing")
	check(batch.finish_base_scope(), "outer base completion seals facts")
	var entries: Array = batch.consume()
	check(entries.size() == 2 and batch.consume().is_empty(), "completed batch can be consumed once in stable HP order")
	check(entries[0].target.resolve(false) == target, "weak actor ref delegates current world and life authority")
	_zone_generation += 1
	check(entries[0].target.resolve(false) == null and entries[0].fact.actual_loss == 60, "world invalidates actor mutation while preserving historical fact")
	target.queue_free()
	await get_tree().process_frame
	_finish()
func _finish() -> void:
	if not proof.write_receipt("damage_commit_fact_test",checks,errors.size()): errors.append("receipt")
	print(("FRAMEWORK_DAMAGE_COMMIT_FACT_PASS" if errors.is_empty() else "FRAMEWORK_DAMAGE_COMMIT_FACT_FAIL") + " checks=" + str(checks) + " errors=" + str(errors))
	get_tree().quit(0 if errors.is_empty() else 1)
