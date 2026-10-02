extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Gate := preload("res://tests/framework/helpers/native_producer_gate.gd")
const Ledger := preload("res://scripts/world_monster_clock_ledger.gd")
const EXPECTED := "res://outputs/test_logs/framework/world_generation_persistence_expected.json"
var proof := Proof.new()
var checks := 0
var failures: Array[String] = []

func check(value: bool,label: String) -> void:
	proof.record(value,label); checks += 1
	if not value: failures.append(label)

func _ready() -> void: _run.call_deferred()

func _run() -> void:
	check(not PlayerState.test_mode,"independent native process uses production persistence")
	var expected: Variant = Gate.read_json(EXPECTED)
	check(Gate.accepts(expected,"world_generation_persistence_test"),"runner confirms this invocation's successful live producer before profile loading")
	if not failures.is_empty(): _finish(); return
	check(expected.get("generation") is String and not str(expected.generation).is_empty() and Ledger.valid_generation(expected.generation),"producer expectation requires a nonempty canonical generation")
	if not failures.is_empty(): _finish(); return
	PlayerState.begin_startup_save_upgrade()
	check(PlayerState.finish_startup_save_upgrade(),"actual independent startup upgrade gate completes")
	check(PlayerState.select_character(expected.profile_id),"actual profile service loads the producer's durable character")
	check(PlayerState._world_clock_generation == expected.generation,"independent cold process restores the nonempty production generation exactly")
	check(PlayerState.level == int(expected.level) and PlayerState.experience == int(expected.experience) and PlayerState.gold == int(expected.gold),"cold progress is exact without repeated migration or reward")
	check(PlayerState.monster_respawn_entry(913203,"group:0").get("respawn_at_unix") == expected.deadline,"independent world ledger replay retains the real imported deadline")
	var primary: Variant = Gate.read_json(PlayerState._profile_path(expected.profile_id))
	var backup: Variant = Gate.read_json(PlayerState._profile_path(expected.profile_id)+".bak")
	var clock: Variant = Gate.read_json(PlayerState._world_clock_path(expected.profile_id,expected.generation))
	check(primary is Dictionary and primary.get("world_clock_generation") == expected.generation,"cold primary retains the same nonempty namespace")
	check(backup is Dictionary and backup.get("world_clock_generation") == expected.generation,"cold recovery backup retains the same nonempty namespace")
	check(Ledger.valid_snapshot(clock,expected.profile_id,expected.generation),"cold world snapshot validates against the expected nonempty namespace")
	check(FileAccess.get_sha256(expected.archive) == expected.archive_sha256,"cold load leaves the original legacy archive bytes unchanged")
	check(PlayerState._json_persistence.pending_count() == 0 and PlayerState._world_json_persistence.pending_count() == 0,"cold load drains both actual persistence services")
	_finish()

func _finish() -> void:
	if not proof.write_receipt("world_generation_persistence_cold_test",checks,failures.size()): failures.append("receipt")
	print("WORLD_GENERATION_PERSISTENCE_COLD_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL",checks,str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
