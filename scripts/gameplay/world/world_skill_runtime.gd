extends RefCounted

## Source-owned gameplay input state. World execution, actors, clocks and
## presentation are explicit owner-local ports; no SceneTree lookup on S.
var _owner_thread := OS.get_thread_caller_id()
var _configured := false
var _fields: RefCounted
var _profile: RefCounted
var _input: RefCounted
var _clock: RefCounted
var _actors: RefCounted
var _execution: RefCounted
var _presentation: RefCounted

func configure_ports(bindings: Dictionary) -> bool:
	if OS.get_thread_caller_id() != _owner_thread or _configured: return false
	for key: String in ["fields", "profile", "input", "clock", "actors", "execution", "presentation"]:
		if not bindings.get(key) is RefCounted or bindings[key] is Resource: return false
	_fields = bindings.fields
	_profile = bindings.profile
	_input = bindings.input
	_clock = bindings.clock
	_actors = bindings.actors
	_execution = bindings.execution
	_presentation = bindings.presentation
	_configured = true
	return true

func _owned() -> bool:
	return _configured and OS.get_thread_caller_id() == _owner_thread

var player: Object:
	get: return _actors.player() if _owned() else null
var locked_target: Object:
	get: return _actors.locked_target() if _owned() else null

const SkillInputPolicyScript := preload("res://scripts/skill_input_policy.gd")
const SkillDataLoaderScript := preload("res://scripts/skills/skill_data_loader.gd")
const ATTACK_INPUT_TICKET_CONTRACT_ID := "combat.input.ordinary_attack.live_owner_no_debt.v2"
const SKILL_INPUT_TICKET_CONTRACT_ID := (
	"combat.input.skill_ticket.cooldown_coalesce_hold_repeat.v2"
)
const SKILL_HOLD_REPEAT_THRESHOLD_MS := 300
const MAGIC_SHIELD_AUTO_REFRESH_CHECK_SECONDS := 0.10
const MAGIC_SHIELD_AUTO_REFRESH_EXPIRY_LEAD_SECONDS := 0.60
const ATTACK_ACTION_LIFECYCLE_CONTRACT_ID := "input.attack.fresh_down.v1"
const ATTACK_ACTION_DIAGNOSTIC_LIMIT := 256

var current_map_id: int:
	get: return _fields.read_field("current_map_id") if _owned() else -1
	set(value):
		if _owned(): _fields.write_field("current_map_id", value)
var _zone_generation: int:
	get: return _fields.read_field("_zone_generation") if _owned() else 0
	set(value):
		if _owned(): _fields.write_field("_zone_generation", value)
var _mobile_attack_held: bool:
	get: return _fields.read_field("_mobile_attack_held") if _owned() else false
	set(value):
		if _owned(): _fields.write_field("_mobile_attack_held", value)
var _queued_mobile_attack_tickets: Array[int]:
	get: return _fields.read_field("_queued_mobile_attack_tickets") if _owned() else ([] as Array[int])
	set(value):
		if _owned(): _fields.write_field("_queued_mobile_attack_tickets", value)
var _active_mobile_attack_tokens: Dictionary:
	get: return _fields.read_field("_active_mobile_attack_tokens") if _owned() else {}
	set(value):
		if _owned(): _fields.write_field("_active_mobile_attack_tokens", value)
var _legacy_mobile_attack_token: int:
	get: return _fields.read_field("_legacy_mobile_attack_token") if _owned() else 0
	set(value):
		if _owned(): _fields.write_field("_legacy_mobile_attack_token", value)
var _next_synthetic_attack_token: int:
	get: return _fields.read_field("_next_synthetic_attack_token") if _owned() else -1
	set(value):
		if _owned(): _fields.write_field("_next_synthetic_attack_token", value)
var _active_skill_inputs: Dictionary:
	get: return _fields.read_field("_active_skill_inputs") if _owned() else {}
	set(value):
		if _owned(): _fields.write_field("_active_skill_inputs", value)
var _next_skill_input_sequence: int:
	get: return _fields.read_field("_next_skill_input_sequence") if _owned() else 1
	set(value):
		if _owned(): _fields.write_field("_next_skill_input_sequence", value)
var _skill_input_retry_remaining: float:
	get: return _fields.read_field("_skill_input_retry_remaining") if _owned() else 0.0
	set(value):
		if _owned(): _fields.write_field("_skill_input_retry_remaining", value)
var _keyboard_bound_skill_token: int:
	get: return _fields.read_field("_keyboard_bound_skill_token") if _owned() else 0
	set(value):
		if _owned(): _fields.write_field("_keyboard_bound_skill_token", value)
var _attack_action_press_owned: bool:
	get: return _fields.read_field("_attack_action_press_owned") if _owned() else false
	set(value):
		if _owned(): _fields.write_field("_attack_action_press_owned", value)
var _attack_action_neutral_observed: bool:
	get: return _fields.read_field("_attack_action_neutral_observed") if _owned() else true
	set(value):
		if _owned(): _fields.write_field("_attack_action_neutral_observed", value)
var _attack_action_ignored_pressed_recorded: bool:
	get: return _fields.read_field("_attack_action_ignored_pressed_recorded") if _owned() else false
	set(value):
		if _owned(): _fields.write_field("_attack_action_ignored_pressed_recorded", value)
var _attack_action_lifecycle_epoch: int:
	get: return _fields.read_field("_attack_action_lifecycle_epoch") if _owned() else 0
	set(value):
		if _owned(): _fields.write_field("_attack_action_lifecycle_epoch", value)
var _attack_action_diagnostic_serial: int:
	get: return _fields.read_field("_attack_action_diagnostic_serial") if _owned() else 0
	set(value):
		if _owned(): _fields.write_field("_attack_action_diagnostic_serial", value)
var _attack_action_diagnostic_events: Array[Dictionary]:
	get: return _fields.read_field("_attack_action_diagnostic_events") if _owned() else ([] as Array[Dictionary])
	set(value):
		if _owned(): _fields.write_field("_attack_action_diagnostic_events", value)
var _magic_shield_auto_enabled: bool:
	get: return _fields.read_field("_magic_shield_auto_enabled") if _owned() else false
	set(value):
		if _owned(): _fields.write_field("_magic_shield_auto_enabled", value)
var _magic_shield_auto_retry_remaining: float:
	get: return _fields.read_field("_magic_shield_auto_retry_remaining") if _owned() else 0.0
	set(value):
		if _owned(): _fields.write_field("_magic_shield_auto_retry_remaining", value)


func _allocate_synthetic_attack_token() -> int:
	if not _owned(): return 0
	var token = _next_synthetic_attack_token
	_next_synthetic_attack_token -= 1
	return token


func _submit_mobile_attack_ticket(press_token: int) -> void:
	if not _owned(): return
	# Compatibility entry point only. A DOWN is an attempt, NOT a future debt.
	_queued_mobile_attack_tickets.clear()
	if press_token == 0:
		return
	_try_ordinary_attack_intent(&"fresh_down")


func _drain_next_mobile_attack_ticket() -> bool:
	if not _owned(): return false
	# Compatibility shim: an old caller can never resurrect deferred attacks.
	_queued_mobile_attack_tickets.clear()
	return false


func _refresh_mobile_attack_held() -> void:
	if not _owned(): return
	_mobile_attack_held = not _active_mobile_attack_tokens.is_empty()


func _on_mobile_attack_input_started(
	press_token: int,
	touch_id: int,
	source: StringName
) -> void:
	if not _owned(): return
	if not _input.gameplay_input_is_enabled() or press_token == 0:
		return
	if _active_mobile_attack_tokens.has(press_token):
		return
	var ordinary_attack = _profile.skill_name_for_slot(
		_profile.SKILL_SLOT_GROUP_ATTACK, 0
	).is_empty()
	if not ordinary_attack:
		_on_skill_input_started(
			_profile.SKILL_SLOT_GROUP_ATTACK, 0,
			press_token, touch_id, source
		)
		return
	_active_mobile_attack_tokens[press_token] = {
		"press_token": press_token,
		"touch_id": touch_id,
		"source": source,
		"started_at_ms": _clock.now_msec(),
	}
	_refresh_mobile_attack_held()
	_record_attack_action_diagnostic(&"pointer_down", source, {
		"press_token": press_token, "touch_id": touch_id,
	})
	_submit_mobile_attack_ticket(press_token)


func _on_mobile_attack_input_ended(
	press_token: int,
	touch_id: int,
	source: StringName
) -> void:
	if not _owned(): return
	if not _active_mobile_attack_tokens.has(press_token):
		_on_skill_input_ended(
			_profile.SKILL_SLOT_GROUP_ATTACK, 0,
			press_token, touch_id, source
		)
		return
	if not _ordinary_attack_owner_matches(press_token, touch_id, source):
		return
	_active_mobile_attack_tokens.erase(press_token)
	_queued_mobile_attack_tickets.clear()
	_refresh_mobile_attack_held()
	_record_attack_action_diagnostic(&"pointer_up", source, {
		"press_token": press_token, "touch_id": touch_id,
	})


func _on_mobile_attack_input_cancelled(
	press_token: int,
	touch_id: int,
	source: StringName,
	reason: StringName
) -> void:
	if not _owned(): return
	if not _active_mobile_attack_tokens.has(press_token):
		_on_skill_input_cancelled(
			_profile.SKILL_SLOT_GROUP_ATTACK, 0,
			press_token, touch_id, source, reason
		)
		return
	if not _ordinary_attack_owner_matches(press_token, touch_id, source):
		return
	_active_mobile_attack_tokens.erase(press_token)
	_queued_mobile_attack_tickets.clear()
	_refresh_mobile_attack_held()
	_record_attack_action_diagnostic(&"pointer_cancel", reason, {
		"press_token": press_token, "touch_id": touch_id,
		"source": str(source),
	})


func _cancel_all_mobile_attack_inputs(_clear_tickets = false) -> void:
	if not _owned(): return
	# Retain the argument for old callers, but stale debt is never retained.
	_active_mobile_attack_tokens.clear()
	_mobile_attack_held = false
	_legacy_mobile_attack_token = 0
	_queued_mobile_attack_tickets.clear()


func _skill_input_key(
	slot_group: String,
	slot_index: int,
	press_token: int,
	touch_id: int
) -> String:
	if not _owned(): return ""
	return "%s:%d:%d:%d" % [slot_group, slot_index, press_token, touch_id]


func _on_skill_input_started(
	slot_group: String,
	slot_index: int,
	press_token: int,
	touch_id: int,
	source: StringName
) -> void:
	if not _owned(): return
	if not _input.gameplay_input_is_enabled(): return
	if press_token == 0:
		return
	var input_key = _skill_input_key(
		slot_group, slot_index, press_token, touch_id
	)
	if _active_skill_inputs.has(input_key):
		return
	var skill_name = _profile.skill_name_for_slot(slot_group, slot_index)
	if skill_name.is_empty():
		_presentation.show_error_message("技能栏为空")
		return
	var metadata = SkillInputPolicyScript.metadata(skill_name)
	if metadata.is_empty() or bool(metadata.get("passive", false)):
		return
	_execution.activate_magic_skill_domain()
	var entry = {
		"contract_id": SKILL_INPUT_TICKET_CONTRACT_ID,
		"input_key": input_key,
		"slot_group": slot_group,
		"slot_index": slot_index,
		"press_token": press_token,
		"touch_id": touch_id,
		"source": source,
		"skill_name": skill_name,
		"skill_id": str(metadata.get("skill_id", "")),
		"repeatable": bool(metadata.get("repeatable_offensive_spell", false)),
		"started_at_ms": _clock.now_msec(),
		"sequence": _next_skill_input_sequence,
	}
	_next_skill_input_sequence += 1
	_active_skill_inputs[input_key] = entry
	if bool(metadata.get("toggle", false)):
		# Keep the physical input active until UP/CANCEL so duplicate DOWN events
		# from the same touch cannot flip a toggle twice.
		_handle_toggle_skill_input(skill_name)
		return
	_submit_skill_input_ticket(entry)


func _on_skill_input_ended(
	slot_group: String,
	slot_index: int,
	press_token: int,
	touch_id: int,
	_source: StringName
) -> void:
	if not _owned(): return
	_active_skill_inputs.erase(
		_skill_input_key(slot_group, slot_index, press_token, touch_id)
	)


func _on_skill_input_cancelled(
	slot_group: String,
	slot_index: int,
	press_token: int,
	touch_id: int,
	_source: StringName,
	_reason: StringName
) -> void:
	if not _owned(): return
	var input_key = _skill_input_key(
		slot_group, slot_index, press_token, touch_id
	)
	_active_skill_inputs.erase(input_key)


func _cancel_all_skill_inputs(clear_tickets = false) -> void:
	if not _owned(): return
	_active_skill_inputs.clear()
	_keyboard_bound_skill_token = 0
	# Kept as an API-compatible argument for callers that clear attack and skill
	# input together. Skill clicks are no longer buffered past their physical
	# lifetime, so there are no deferred skill tickets to clear.
	if clear_tickets:
		_skill_input_retry_remaining = 0.0


func _reset_attack_action_lifecycle(reason: StringName) -> void:
	if not _owned(): return
	if _keyboard_bound_skill_token != 0:
		_on_skill_input_cancelled(
			_profile.SKILL_SLOT_GROUP_ATTACK,
			0,
			_keyboard_bound_skill_token,
			-4,
			&"keyboard",
			reason
		)
		_keyboard_bound_skill_token = 0
	_attack_action_press_owned = false
	_attack_action_neutral_observed = not _input.is_action_pressed("attack")
	_attack_action_ignored_pressed_recorded = false
	_attack_action_lifecycle_epoch += 1
	_record_attack_action_diagnostic(&"boundary", reason)


func _poll_attack_action_lifecycle(input_enabled: bool) -> Dictionary:
	if not _owned(): return {}
	var pressed = _input.is_action_pressed("attack")
	if not input_enabled:
		_attack_action_press_owned = false
		_attack_action_neutral_observed = not pressed
		return {"started": false, "ended": false, "active": false}
	if not pressed:
		var ended = _attack_action_press_owned
		_attack_action_press_owned = false
		_attack_action_neutral_observed = true
		_attack_action_ignored_pressed_recorded = false
		if ended:
			_record_attack_action_diagnostic(&"released", &"input_action")
		return {"started": false, "ended": ended, "active": false}
	if (
		not _attack_action_press_owned
		and _attack_action_neutral_observed
		and _input.is_action_just_pressed("attack")
	):
		_attack_action_press_owned = true
		_attack_action_neutral_observed = false
		_attack_action_ignored_pressed_recorded = false
		_record_attack_action_diagnostic(&"fresh_down", &"input_action")
		return {"started": true, "ended": false, "active": true}
	if not _attack_action_press_owned and not _attack_action_ignored_pressed_recorded:
		_attack_action_ignored_pressed_recorded = true
		_record_attack_action_diagnostic(&"pressed_without_fresh_down_ignored", &"input_action")
	return {"started": false, "ended": false, "active": _attack_action_press_owned}


func _record_attack_action_diagnostic(
	kind: StringName,
	reason: StringName,
	details: Dictionary = {}
) -> void:
	if not _owned(): return
	_attack_action_diagnostic_serial += 1
	var entry = {
		"serial": _attack_action_diagnostic_serial,
		"time_ms": _clock.now_msec(),
		"epoch": _attack_action_lifecycle_epoch,
		"kind": str(kind),
		"reason": str(reason),
		"pressed": _input.is_action_pressed("attack"),
		"touch_attack_held": _mobile_attack_held,
		"active_touch_count": _active_mobile_attack_tokens.size(),
		"queued_ticket_count": _queued_mobile_attack_tickets.size(),
		"map_id": current_map_id,
		"zone_generation": _zone_generation,
	}
	if is_instance_valid(player):
		entry["attack_timer"] = player._attack_timer
		entry["attack_action_timer"] = player._attack_action_timer
		entry["attack_cooldown"] = player.attack_cooldown
		entry["combat_action_sequence"] = player._combat_action_sequence
		entry["player_hp"] = player.current_hp
	if is_instance_valid(locked_target):
		entry["locked_target_id"] = _actors.runtime_actor_id(locked_target)
		entry["locked_target_hp"] = locked_target.current_hp
	else:
		entry["locked_target_id"] = 0
		entry["locked_target_hp"] = 0
	entry["details"] = details.duplicate(true)
	_attack_action_diagnostic_events.append(entry)
	while _attack_action_diagnostic_events.size() > ATTACK_ACTION_DIAGNOSTIC_LIMIT:
		_attack_action_diagnostic_events.pop_front()


func attack_action_lifecycle_snapshot() -> Dictionary:
	if not _owned(): return {}
	var result = {
		"contract_id": ATTACK_ACTION_LIFECYCLE_CONTRACT_ID,
		"ordinary_attack_contract_id": ATTACK_INPUT_TICKET_CONTRACT_ID,
		"epoch": _attack_action_lifecycle_epoch,
		"press_owned": _attack_action_press_owned,
		"neutral_observed": _attack_action_neutral_observed,
		"raw_attack_pressed": _input.is_action_pressed("attack"),
		"touch_attack_held": _mobile_attack_held,
		"active_touch_count": _active_mobile_attack_tokens.size(),
		"active_touch_owners": _active_mobile_attack_tokens.duplicate(true),
		"queued_ticket_count": _queued_mobile_attack_tickets.size(),
		"events": _attack_action_diagnostic_events.duplicate(true),
	}
	if is_instance_valid(player):
		result["attack_timer"] = player._attack_timer
		result["attack_action_timer"] = player._attack_action_timer
		result["combat_action_sequence"] = player._combat_action_sequence
		result["attack_cooldown"] = player.attack_cooldown
	if _input.has_button_lifecycle_snapshot():
		result["button"] = _input.button_lifecycle_snapshot()
	return result


func _submit_skill_input_ticket(entry: Dictionary) -> void:
	if not _owned(): return
	# One physical DOWN makes exactly one immediate attempt. A busy cast gate
	# coalesces all additional taps during that interval instead of storing them
	# for forced release later. Continuous casting is owned exclusively by the
	# still-active press in _process_skill_input_actions().
	_execution.try_release_skill(str(entry.get("skill_name", "")), true)


func _process_skill_input_actions(delta: float) -> void:
	if not _owned(): return
	_skill_input_retry_remaining = maxf(
		0.0, _skill_input_retry_remaining - delta
	)
	if _skill_input_retry_remaining > 0.0:
		return
	_skill_input_retry_remaining = 0.05
	var repeat_entry: Dictionary = {}
	var now_ms = _clock.now_msec()
	for raw_entry: Variant in _active_skill_inputs.values():
		if not raw_entry is Dictionary:
			continue
		var entry: Dictionary = raw_entry
		if not bool(entry.get("repeatable", false)):
			continue
		if (
			now_ms - int(entry.get("started_at_ms", now_ms))
			< SKILL_HOLD_REPEAT_THRESHOLD_MS
		):
			continue
		if (
			repeat_entry.is_empty()
			or int(entry.get("sequence", 0))
			< int(repeat_entry.get("sequence", 0))
		):
			repeat_entry = entry
	if not repeat_entry.is_empty():
		_execution.try_release_skill(str(repeat_entry.get("skill_name", "")), false)


func _handle_toggle_skill_input(skill_name: String) -> void:
	if not _owned(): return
	var stable_skill_id = SkillDataLoaderScript.stable_skill_id(skill_name)
	if stable_skill_id != "wizard.magic_shield":
		_execution.try_release_skill(skill_name, true)
		return
	_magic_shield_auto_enabled = not _magic_shield_auto_enabled
	if not _magic_shield_auto_enabled:
		_presentation.show_message("魔法盾自动补盾：关", 1.5)
		return
	_presentation.show_message("魔法盾自动补盾：开", 1.5)
	_magic_shield_auto_retry_remaining = 0.0
	_process_magic_shield_auto_refresh(
		MAGIC_SHIELD_AUTO_REFRESH_CHECK_SECONDS
	)


func _process_magic_shield_auto_refresh(delta: float) -> void:
	if not _owned(): return
	if not _magic_shield_auto_enabled or not is_instance_valid(player):
		return
	_magic_shield_auto_retry_remaining = maxf(
		0.0, _magic_shield_auto_retry_remaining - delta
	)
	if _magic_shield_auto_retry_remaining > 0.0:
		return
	_magic_shield_auto_retry_remaining = MAGIC_SHIELD_AUTO_REFRESH_CHECK_SECONDS
	if not player.magic_shield_requires_refresh(
		_actors.magic_shield_auto_refresh_ratio(),
		MAGIC_SHIELD_AUTO_REFRESH_EXPIRY_LEAD_SECONDS
	):
		return
	_execution.try_release_skill(
		SkillDataLoaderScript.display_name("wizard.magic_shield"),
		false
	)


func _on_mobile_attack_pressed() -> void:
	if not _owned(): return
	if not _input.gameplay_input_is_enabled(): return
	if _legacy_mobile_attack_token != 0:
		return
	_legacy_mobile_attack_token = _allocate_synthetic_attack_token()
	_on_mobile_attack_input_started(
		_legacy_mobile_attack_token,
		-3,
		&"legacy"
	)


func _on_mobile_attack_released() -> void:
	if not _owned(): return
	# A duplicate legacy release must not release another finger's ownership.
	if _legacy_mobile_attack_token == 0:
		return
	var press_token = _legacy_mobile_attack_token
	_legacy_mobile_attack_token = 0
	_on_mobile_attack_input_ended(press_token, -3, &"legacy")


func _ordinary_attack_owner_matches(
	press_token: int, touch_id: int, source: StringName
) -> bool:
	if not _owned(): return false
	var raw_entry: Variant = _active_mobile_attack_tokens.get(press_token)
	if not raw_entry is Dictionary:
		return false
	var entry = raw_entry as Dictionary
	return (
		int(entry.get("touch_id", -999)) == touch_id
		and StringName(entry.get("source", &"")) == source
	)


func _process_ordinary_attack_input(attack_action_lifecycle: Dictionary) -> void:
	if not _owned(): return
	_queued_mobile_attack_tickets.clear()
	if not _input.gameplay_input_is_enabled():
		_cancel_all_mobile_attack_inputs(true)
		return
	_reconcile_ordinary_attack_button_owners()
	if bool(attack_action_lifecycle.get("started", false)):
		_submit_mobile_attack_ticket(_allocate_synthetic_attack_token())
	elif _mobile_attack_held or bool(attack_action_lifecycle.get("active", false)):
		_try_ordinary_attack_intent(&"live_hold")


func _reconcile_ordinary_attack_button_owners() -> void:
	if not _owned(): return
	# Reconcile two software ledgers; this is NOT an inactivity/hold timer.
	# No inference is made from the absence of DRAG events.
	if not _input.has_button_lifecycle_owner():
		return
	for raw_token: Variant in _active_mobile_attack_tokens.keys():
		var token = int(raw_token)
		var raw_entry: Variant = _active_mobile_attack_tokens.get(token)
		if not raw_entry is Dictionary:
			# Legacy bool entries cannot describe a current verified pointer.
			_active_mobile_attack_tokens.erase(token)
			continue
		var entry = raw_entry as Dictionary
		var source = StringName(entry.get("source", &""))
		if source not in [&"touch", &"mouse", &"ui_accept"]:
			continue
		var touch_id = int(entry.get("touch_id", -999))
		if not bool(_input.button_owns_lifecycle_input(token, touch_id, source)):
			_on_mobile_attack_input_cancelled(
				token, touch_id, source, &"button_owner_revoked"
			)
	_refresh_mobile_attack_held()


func _try_ordinary_attack_intent(origin: StringName) -> bool:
	if not _owned(): return false
	if not _input.gameplay_input_is_enabled():
		return false
	# Reject before target selection/geometry. Never adjust gameplay timers.
	if not player.can_start_attack():
		return false
	var accepted = _execution.request_mobile_attack()
	if accepted:
		# This means action STARTED; it does NOT mean damage has been committed.
		_record_attack_action_diagnostic(&"attack_action_started", origin)
	return accepted
