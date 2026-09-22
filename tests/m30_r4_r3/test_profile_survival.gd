extends Node
const Guard := preload("res://tests/m30_r4_r3/survival_guard.gd")
var failures: int = 0

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error("M30_R3_PROFILE " + label)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var player := PlayerCharacter.new()
	add_child(player) # Actual production _ready/profile_changed subscriber.
	player.max_hp = Guard.HP_MARGIN
	player.current_hp = Guard.HP_MARGIN
	var original_profile_max: int = int(PlayerState.computed_stats.get("max_hp", 120))
	PlayerState.profile_changed.emit() # Deterministic fixture event, not an actual kill.
	check(player.max_hp == original_profile_max and player.max_hp < Guard.HP_MARGIN,
		"one-shot max_hp override is replaced by production profile recalculation")
	check(player.current_hp > 0 and not player._dead, "profile recalculation alone is NOT proof of death")
	print("M30_R3_PROFILE_OBSERVED after_profile_max_hp=%d" % player.max_hp)
	var guard := Guard.new()
	check(guard.attach(player), "explicit lab guard attaches after actual player subscriber")
	player.current_hp -= 100
	PlayerState.profile_changed.emit()
	check(player.max_hp == Guard.HP_MARGIN and player.current_hp > 0,
		"lab margin survives synchronous profile recalculation")
	check(guard.profile_events == 1 and guard.repairs >= 2, "every repair is accounted for")
	player._dead = true
	player.current_hp = 0
	PlayerState.profile_changed.emit()
	check(player.current_hp == 0 and player._dead and guard.rejected_dead_state,
		"guard cannot resurrect a zero-HP/dead player")
	guard.detach()
	player.queue_free()
	print("M30_R3_PROFILE_SURVIVAL_%s failures=%d meaning=fixture_contract_not_pig_site_root_proof" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(0 if failures == 0 else 1)
