extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const CORE_PATH := "res://scripts/gameplay/actors/summon_domain_state.gd"
var proof := Proof.new()
var errors: Array[String] = []
var wake_observations: Array = []

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	if not value:
		errors.append(label)

func _ready() -> void:
	_run.call_deferred()

func _observe_wakeup(core: Object) -> void:
	wake_observations.append([core.stealth_remaining_seconds, core.ac_buff_remaining_seconds, core.mac_buff_remaining_seconds])
	if not core.is_stealthed():
		# A real synchronous listener may refresh defence before the remaining
		# original timer sweep. Late buffered notifications would yield 5.0.
		core.apply_ac_buff(9, 5.0, "reentrant")

func _run() -> void:
	check(FileAccess.file_exists(CORE_PATH), "summon growth and support state have a non-Node owner")
	if not FileAccess.file_exists(CORE_PATH):
		_finish()
		return
	var core: Object = load(CORE_PATH).new(TaoistCombatMath, SkillRankResolver, 5.0)
	check(not core is Node, "summon numeric domain requires no SceneTree")
	core.current_hp = 100
	core.pet_growth_exp = 1
	check(not core.gain_growth_from_kill(162) and core.pet_growth_exp == 325 and core.summon_exp_level == 0, "equal threshold retains strict greater-than growth contract")
	check(core.gain_growth_from_kill(1) and core.summon_exp_level == 1 and core.pet_growth_exp == 2, "crossing threshold grants exactly one level with residual credit")
	check(core.max_hp == 196 and core.current_hp == 100 and core.attack_min == 12 and core.attack_max == 24, "growth applies canonical authored stats and preserves absolute HP")
	check(not core.gain_growth_from_kill(9999) and core.pet_growth_exp == 2, "capped summon does not accumulate more credit")
	check(core.synchronize_skill_rank(3) and core.maximum_pet_level == 7 and core.skill_level == 3, "rank increase raises same canonical cap")
	check(is_equal_approx(core.attack_interval, 1.2) and is_equal_approx(core.move_speed_gu_per_sec, 1000.0 / 350.0), "rank increase retains original attack and move interval formulas")
	check(not core.synchronize_skill_rank(1) and core.maximum_pet_level == 7, "lower rank cannot downgrade learned rank or cap")
	check(core.gain_growth_from_kill(10000) and core.summon_exp_level == 2, "large credit advances only one pet level per kill")
	check(core.growth_contract_snapshot().persistence == "transient_non_permanent_pet", "growth snapshot retains transient pet persistence contract")
	core.summon_id = "divine_beast"
	core.synchronize_skill_rank(4)
	check(core.effective_skill_rank == 4 and core.divine_damage_more > 1.0, "effective divine rank retains above-formula more multiplier")
	core.passive_wakeup_changed.connect(_observe_wakeup.bind(core))
	core.apply_ac_buff(7, 2.0, "ac")
	core.apply_mac_buff(4, 3.0, "mac")
	core.apply_stealth(0.5, "stealth")
	check(wake_observations.size() == 1, "first stealth application synchronously wakes passive consumers")
	core.apply_stealth(0.2, "new_stealth")
	check(wake_observations.size() == 1 and core.stealth_remaining() == 0.5 and core.stealth_buff_id == "new_stealth", "short refresh retains duration and refreshes source without a second wake")
	core.update_support_buff_timers(0.75)
	check(wake_observations.size() == 2 and wake_observations[1] == [0.0, 2.0, 3.0], "stealth expiry signal occurs before either defence clock is charged")
	check(core.ac_buff_remaining_seconds == 4.25 and core.mac_buff_remaining_seconds == 2.25 and core.ac_buff_bonus == 9, "reentrant defence refresh is charged by the same original timer sweep")
	core.apply_mac_buff(1, 0.5, "weaker")
	check(core.magic_defence_bonus() == 4 and core.mac_buff_remaining_seconds == 2.25 and core.mac_buff_id == "weaker", "weaker shorter buff cannot lower active power or time")
	core.update_support_buff_timers(3.0)
	check(core.magic_defence_bonus() == 0 and core.mac_buff_id.is_empty() and core.physical_defence_bonus() == 9, "MAC expiry clears only its own independent state")
	core.clear_ac_buff()
	check(core.physical_defence_bonus() == 0 and core.ac_buff_id.is_empty(), "explicit AC clear removes power time and source")
	var summon: Object = SummonActor.new()
	summon.current_hp = 73
	summon.domain_state.maximum_pet_level = 7
	check(summon.domain_state.current_hp == 73 and summon.maximum_pet_level == 7, "legacy and data paths reference the same HP and growth storage")
	summon.pet_growth_exp = 325
	check(summon.gain_growth_from_kill(1) and summon.current_hp == 73 and summon.domain_state.summon_exp_level == 1, "legacy growth executes the shared domain rule without healing")
	var before: int = wake_observations.size()
	summon.passive_wakeup_changed.connect(_observe_wakeup.bind(summon.domain_state))
	summon.apply_stealth(0.25)
	check(wake_observations.size() == before + 1, "legacy signal forwards the domain synchronous wake")
	summon._update_support_buff_timers(0.5)
	check(wake_observations.size() == before + 2 and summon.ac_buff_remaining_seconds == 4.5, "legacy listener reentry preserves the exact expiry sweep order")
	summon.free()
	_finish()

func _finish() -> void:
	proof.write_receipt("multicore_summon_domain_20261014", proof.records.size(), errors.size())
	if errors.is_empty():
		print("MULTICORE_SUMMON_DOMAIN_20261014_PASS")
	else:
		for message: String in errors:
			printerr(message)
	get_tree().quit(0 if errors.is_empty() else 1)
