extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Ledger := preload("res://scripts/world_monster_clock_ledger.gd")
const WorldState := preload("res://scripts/world_monster_respawn_state.gd")
const EXPECTED := "res://outputs/test_logs/framework/world_generation_persistence_expected.json"
var proof := Proof.new()
var checks := 0
var failures: Array[String] = []

func check(value: bool,label: String) -> void:
	proof.record(value,label); checks += 1
	if not value: failures.append(label)

func _ready() -> void: _run.call_deferred()

func _run() -> void:
	check(not PlayerState.test_mode,"actual persistence is enabled before test setup")
	check(OS.get_environment("APPDATA").replace("\\","/").contains("/.godot/runtime_appdata/"),"native runner isolated user data before autoload initialization")
	if not failures.is_empty(): _finish(); return
	PlayerState.begin_startup_save_upgrade()
	check(PlayerState.finish_startup_save_upgrade(),"production startup migration gate completes")
	check(PlayerState.create_character("世界代次验证","hc.profession.wizard").is_empty(),"production profile service creates the test-owned character")
	if not failures.is_empty(): _finish(); return
	var profile: String = PlayerState.active_profile_id
	check(PlayerState.save_game(true,true,true),"existing sole writer saves the starting profile")
	var path: String = PlayerState._profile_path(profile)
	var legacy: Dictionary = _read(path)
	check(not legacy.is_empty() and legacy.profile_id == profile,"starting durable document belongs to the newly created profile")
	if not failures.is_empty(): _finish(); return
	# Only fixture preparation writes a sequence-less legacy before-image. Never
	# assign a fabricated generation: the production import must generate it.
	legacy.erase("death_event_sequence"); legacy.erase("world_clock_generation")
	legacy.erase("world_clock_import_source")
	legacy.level = 22; legacy.experience = 345; legacy.gold = 12345
	var deadline := Time.get_unix_time_from_system()+3600.0
	legacy.world_monster_respawn_state = WorldState.with_deadline(WorldState.empty_snapshot(),913203,"group:0",64,"normal_cave",deadline)
	var seed := JSON.stringify(legacy)
	check(_write(path,seed) and _write(path+".bak",seed),"only owned primary and matching backup receive the same legacy before-image")
	if not failures.is_empty(): _finish(); return
	var before_digest: String = PlayerState._shared_digest(legacy)
	PlayerState.load_save()
	check(bool(PlayerState.last_load_result.get("success",false)),"production load imports the real legacy document: "+str(PlayerState.last_load_result))
	var generation: String = PlayerState._world_clock_generation
	check(not generation.is_empty() and Ledger.valid_generation(generation),"production legacy importer generated a nonempty canonical namespace")
	if not failures.is_empty(): _finish(); return
	var archive: String = PlayerState.last_load_result.get("world_clock_migration_archive","")
	check(not archive.is_empty() and FileAccess.file_exists(archive),"production migration keeps its before-image archive")
	check(PlayerState._shared_digest(_read(archive)) == before_digest,"archived original content matches the owned legacy input")
	var archive_hash := FileAccess.get_sha256(archive)
	check(PlayerState.level == 22 and PlayerState.experience == 345 and PlayerState.gold == 12345,"actual imported progress remains exact")
	check(PlayerState.monster_respawn_entry(913203,"group:0").get("respawn_at_unix") == deadline,"actual world deadline survives the production import")
	var clock_path: String = PlayerState._world_clock_path(profile,generation)
	var clock := _read(clock_path)
	check(Ledger.valid_snapshot(clock,profile,generation),"production world snapshot uses the same nonempty profile namespace")
	var primary := _read(path)
	var backup := _read(path+".bak")
	check(primary.get("world_clock_generation") == generation and backup.get("world_clock_generation") == generation,"production import promoted primary and matching recovery backup into the generated namespace")
	check(primary.get("world_clock_import_source") == before_digest,"durable import identifies the preserved source digest")
	# Test the real ledger validator/replay with a copied wrong namespace. No
	# runtime or durable generation is overwritten by this negative example.
	var wrong := ("1" if generation.begins_with("0") else "0")+generation.substr(1)
	check(not Ledger.valid_snapshot(clock,profile,wrong),"different nonempty namespace is rejected by the production snapshot validator")
	var wrong_profile := primary.duplicate(true); wrong_profile.world_clock_generation = wrong
	var rejected := Ledger.replay(wrong_profile,clock,[])
	check(not bool(rejected.get("ok",false)) and rejected.get("reason") == "invalid_world_snapshot","actual ledger replay refuses a mismatched generation")
	check(PlayerState.save_game(true,true,true),"existing writer checkpoints imported progress without replacing the generated namespace")
	check(PlayerState.save_game(true,true,true),"existing backup path can checkpoint the same imported namespace again")
	primary = _read(path); backup = _read(path+".bak"); clock = _read(clock_path)
	check(primary.get("world_clock_generation") == generation and backup.get("world_clock_generation") == generation and clock.get("world_clock_generation") == generation,"live, durable primary, backup and world snapshot retain the same nonempty generation")
	check(FileAccess.get_sha256(archive) == archive_hash,"normal checkpoints preserve the original import archive bytes")
	check(PlayerState._json_persistence.pending_count() == 0 and PlayerState._world_json_persistence.pending_count() == 0,"all real persistence callbacks have completed before native handoff")
	if failures.is_empty():
		var expected := {"profile_id":profile,"generation":generation,"experience":345,"level":22,"gold":12345,
			"deadline":deadline,"archive":archive,"archive_sha256":archive_hash,"source_digest":before_digest,
			"producer_run_id":OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID"),
			"invocation_id":OS.get_environment("HARDCORE_FRAMEWORK_INVOCATION_ID"),
			"source_content_sha256":OS.get_environment("HARDCORE_R3_CONTENT_SHA256")}
		check(_write(EXPECTED,JSON.stringify(expected)),"this successful producer writes a checked cold expectation")
	_finish()

func _read(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path): return {}
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return value if value is Dictionary else {}

func _write(path: String,value: String) -> bool:
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file == null: return false
	file.store_string(value); file.flush()
	var result := file.get_error() == OK; file.close()
	return result

func _finish() -> void:
	if not proof.write_receipt("world_generation_persistence_test",checks,failures.size()): failures.append("receipt")
	print("WORLD_GENERATION_PERSISTENCE_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL",checks,str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
