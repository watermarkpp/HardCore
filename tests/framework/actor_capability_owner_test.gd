extends "res://tests/monster_anti_stealth_runtime_test.gd"

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const CAN_SEE := "hc.can_see_stealth"
var proof := Proof.new()
var checks := 0
var errors: Array[String] = []

func check(value: bool, label: String) -> void:
	proof.record(value,label); checks += 1
	if not value: errors.append(label)

func _run() -> void:
	var previous_test_mode := PlayerState.test_mode
	PlayerState.test_mode = false; PlayerState.reset_progress()
	var player := PlayerCharacter.new()
	player.set_physics_process(false); add_child(player)
	await get_tree().process_frame
	player.max_hp = 1000; player.current_hp = 1000
	player.global_position = GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(Vector2(4.0,0.0))
	player.apply_stealth(60.0)
	var enemy := await _make_enemy(NORMAL_MONSTER_ID,player,Vector2.ZERO)
	check(not enemy.anti_stealth and not enemy.has_actor_capability(CAN_SEE),"canonical ordinary actor starts without capability")
	check(enemy.replace_actor_capability_source("hc.source.fixture.a",[CAN_SEE]),"first capability grant is admitted")
	check(enemy.anti_stealth and enemy.has_actor_capability(CAN_SEE),"legacy view delegates to the sole capability owner")
	_force_cadence_ready(enemy); enemy._physics_process(1.0/60.0)
	check(enemy._movement_step_active and enemy.actual_ground_motion_gu.length() > 0.0,"capability drives actual hidden-target pursuit")
	check(player.current_hp == 1000,"perception does not turn distant tracking into damage")
	check(enemy._hc_access(player) == "OUT_OF_RANGE","capability retains melee range rejection")
	enemy.set_combat_position(Vector2.ZERO,&"test_setup")
	player.global_position = GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(Vector2(0.9,0.9))
	check(enemy._hc_access(player,0.0,true) == "CLEAR","capability reaches ordinary melee qualification")
	check(enemy.replace_actor_capability_source("hc.source.fixture.b",[CAN_SEE]),"second source is independently admitted")
	check(enemy.replace_actor_capability_source("hc.source.fixture.a",[]) and enemy.anti_stealth,"removing one source retains the other source")
	enemy.anti_stealth = false
	check(enemy.anti_stealth,"legacy setter only removes its own canonical source")
	var before: Dictionary = enemy._feature_capabilities.snapshot()
	check(not enemy.replace_actor_capability_source("hc.source.fixture.b",["hc.capability.unknown"]) and enemy._feature_capabilities.snapshot() == before,"unknown capability rejects atomically")
	check(not enemy.replace_actor_capability_source("hc.source.fixture.b",[CAN_SEE,CAN_SEE]) and enemy._feature_capabilities.snapshot() == before,"duplicate capability rejects atomically")
	enemy.control_time = 1.0
	check(enemy._hc_access(player) == "ACTION_LOCKED","capability retains control-state rejection")
	enemy.control_time = 0.0; enemy.current_hp = 0
	check(enemy._hc_access(player) == "INVALID_TARGET","capability retains actor-life rejection")
	enemy.current_hp = enemy.max_hp
	check(enemy.replace_actor_capability_source("hc.source.fixture.b",[]) and not enemy.anti_stealth,"last removal also clears the legacy view")
	check(enemy._hc_access(player) == "TARGET_HIDDEN","hidden-target qualification resumes after last source removal")
	enemy.anti_stealth = true
	check(enemy.has_actor_capability(CAN_SEE),"legacy canonical setter writes through the capability owner")
	enemy.setup(GameData.get_monster_by_id(NORMAL_MONSTER_ID),player,false)
	check(not enemy.anti_stealth and enemy._feature_capabilities.snapshot().sources.is_empty(),"fresh ordinary life clears old capability grants")
	enemy.setup(GameData.get_monster_by_id(ANTI_STEALTH_MONSTER_ID),player,false)
	check(enemy.anti_stealth and enemy.has_actor_capability(CAN_SEE),"canonical source-backed actor owns the same formal capability")
	check(enemy.replace_actor_capability_source("hc.source.fixture.b",[CAN_SEE]),"temporary grant coexists with canonical projection")
	enemy.anti_stealth = false
	check(enemy.anti_stealth,"canonical source withdrawal retains independent grant")
	enemy.setup(GameData.get_monster_by_id(NORMAL_MONSTER_ID),player,false)
	check(not enemy.anti_stealth,"next life cannot inherit a prior temporary capability")
	enemy.queue_free(); player.queue_free(); await get_tree().process_frame
	PlayerState.test_mode = previous_test_mode
	if not proof.write_receipt("actor_capability_owner_test",checks,errors.size()): errors.append("receipt")
	for error: String in errors: push_error(error)
	print("ACTOR_CAPABILITY_OWNER_%s checks=%d" % ["PASS" if errors.is_empty() else "FAIL",checks])
	get_tree().quit(0 if errors.is_empty() else 1)
