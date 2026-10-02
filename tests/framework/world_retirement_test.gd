extends Node
const Root := preload("res://scripts/game_root.gd")
const Coordinator := preload("res://scripts/monster_visual_streaming_coordinator.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var proof := Proof.new()
var checks := 0
var failures: Array[String] = []

class ExitProbe extends Root:
	var spawn_attempts := 0
	# This focused lifecycle fixture observes the real Root exit and wakeup,
	# without loading a second playable world. Natural cycles test full setup.
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
	func _physics_process(_delta: float) -> void: pass
	func _spawn_enemy(_data: Dictionary,_position: Vector2,_boss: bool,_seconds := -1.0,_context: Dictionary = {}) -> EnemyActor:
		spawn_attempts += 1
		return null

func check(value: bool,label: String) -> void:
	proof.record(value,label); checks += 1
	if not value: failures.append(label)

func _ready() -> void: _run.call_deferred()
func _frames() -> void:
	for frame in 4: await get_tree().process_frame

func _run() -> void:
	var old := ExitProbe.new(); add_child(old)
	old._streaming_coordinator = Coordinator.new()
	MonsterVisual.set_streaming_coordinator(old._streaming_coordinator)
	var newer := Coordinator.new()
	MonsterVisual.set_streaming_coordinator(newer)
	old.queue_free(); await _frames()
	check(MonsterVisual.streaming_coordinator() == newer,"older world's real exit preserves the newer global coordinator")
	MonsterVisual.set_streaming_coordinator(null); newer = null
	var live := ExitProbe.new(); add_child(live)
	live._respawn_later(GameData.get_monster_by_id(19),Vector2.ZERO,false,0.04,live._zone_generation)
	await get_tree().create_timer(0.10).timeout
	check(live.spawn_attempts == 1,"live world keeps original timer and performs one due spawn attempt")
	live.queue_free(); await _frames()
	var reentered := ExitProbe.new(); add_child(reentered)
	reentered._respawn_later(GameData.get_monster_by_id(19),Vector2.ZERO,false,300.0,reentered._zone_generation)
	remove_child(reentered); add_child(reentered)
	reentered._respawn_later(GameData.get_monster_by_id(19),Vector2.ZERO,false,0.04,reentered._zone_generation)
	await get_tree().create_timer(0.10).timeout
	check(reentered.spawn_attempts == 1,"cancelled old callback cannot spawn early or consume a new live wakeup after re-entry")
	reentered.queue_free(); await _frames()
	var baseline := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var counts: Array[int] = []
	for cycle in 3:
		var game := ExitProbe.new(); add_child(game)
		game._respawn_later(GameData.get_monster_by_id(19),Vector2.ZERO,false,300.0,game._zone_generation)
		game._respawn_later(GameData.get_monster_by_id(19),Vector2.ZERO,false,3600.0,game._zone_generation)
		check(game.spawn_attempts == 0,"future wakeups do not spawn early: "+str(cycle))
		game.queue_free(); await _frames()
		var count := int(Performance.get_monitor(Performance.OBJECT_COUNT))
		counts.append(count)
		check(count <= baseline,"retired world releases both long-delay wakeups instead of retaining them until their deadlines: "+str(cycle))
	print("WORLD_RETIREMENT_TRACE ",JSON.stringify({"baseline_objects":baseline,"after_retirement_objects":counts}))
	if not proof.write_receipt("world_retirement_test",checks,failures.size()): failures.append("receipt")
	print("WORLD_RETIREMENT_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL",checks,str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
