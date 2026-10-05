extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Player := preload("res://scripts/player.gd")
const Ledger := preload("res://scripts/damage_ledger_observer.gd")
var proof := Proof.new()
var failures: Array[String] = []

func check(value: bool, label: String) -> void:
	proof.record(value,label)
	if not value: failures.append(label)

func _ready() -> void: _run.call_deferred()

func _run() -> void:
	check(not PlayerState.test_mode and OS.get_environment("APPDATA").replace("\\","/").contains("/.godot/runtime_appdata/"),
		"resource observation counterexample owns an isolated real profile")
	PlayerState.begin_startup_save_upgrade()
	check(PlayerState.finish_startup_save_upgrade() and PlayerState.create_character("资源观测边界","hc.profession.wizard").is_empty(),
		"actual startup and production profile creation")
	if not failures.is_empty(): _finish(); return
	PlayerState.level = 50
	check(PlayerState.recalculate_stats(false) and PlayerState.save_game(true,true,true),"sole stat authority and writer prepare the profile")
	var actor := Player.new(); add_child(actor); actor.set_physics_process(false)
	var caps := {"hp":int(PlayerState.computed_stats.max_hp),"mp":int(PlayerState.computed_stats.max_mp)}
	Ledger.reset(); Ledger.recording_enabled = true
	# Reproduce the existing natural fixture's one-time stress input. No damage
	# API runs before the production XP transaction broadcasts profile_changed.
	actor.max_hp = 100000; actor.current_hp = 100000
	actor.max_mp = 5000; actor.current_mp = 5000
	var xp_before: int = PlayerState.experience
	PlayerState.add_experience(15)
	check(PlayerState.experience == xp_before+15,"real persisted XP update completes")
	check(actor.max_hp == caps.hp and actor.max_mp == caps.mp and actor.current_hp == caps.hp and actor.current_mp == caps.mp,
		"production profile notification restores authoritative caps and clamps the stress values")
	check(actor.current_hp < 100000 and actor.current_mp < 5000 and Ledger.events.is_empty(),
		"end-value decrease alone passes despite zero actual damage mutations")
	var hp_before: int = actor.current_hp
	actor.take_damage(5,false)
	check(Ledger.events.size() == 1 and not Ledger.overflowed,"actual Player damage has one complete read-only HP observation")
	if Ledger.events.size() == 1:
		var row: Dictionary = Ledger.events[0]
		check(int(row.victim_instance_id) == actor.get_instance_id() and int(row.actual_hp_delta)>0
			and int(row.actual_hp_delta) == hp_before-actor.current_hp and int(row.hp_before) == hp_before,
			"actual mutation evidence distinguishes incoming damage from cap synchronization")
	var path := "res://outputs/test_logs/framework/natural_resource_observation_trace.json"
	var file := FileAccess.open(path,FileAccess.WRITE)
	check(file != null,"owned bounded observation evidence opens")
	if file != null:
		file.store_string(JSON.stringify({"run_id":OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID"),
			"source_content_sha256":OS.get_environment("HARDCORE_R3_CONTENT_SHA256"),"authoritative_caps":caps,
			"actual_damage_rows":Ledger.events,"scope":"production profile cap synchronization and actual Player HP write; not sustained combat, Root timing or Android"}))
		file.flush(); check(file.get_error() == OK,"observation evidence writes completely"); file.close()
	Ledger.recording_enabled = false; Ledger.reset()
	var owner: WeakRef = weakref(actor)
	actor.queue_free(); actor = null; await get_tree().process_frame
	check(owner.get_ref() == null,"actual Player observer fixture retires its owned node")
	_finish()

func _finish() -> void:
	Ledger.recording_enabled = false
	var written := proof.write_receipt("natural_resource_observation_test",proof.records.size(),failures.size())
	print("NATURAL_RESOURCE_OBSERVATION_",("PASS" if written and failures.is_empty() else "FAIL")," checks=",proof.records.size()," failures=",failures)
	get_tree().quit(0 if written and failures.is_empty() else 1)
