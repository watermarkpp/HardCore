extends RefCounted

## New S world starts with the original GameRoot scalar/container defaults.
## Existing M fields are accessed through LegacyWorldSkillPorts instead.
var _owner := OS.get_thread_caller_id()
var _values: Dictionary

func _init() -> void:
	_values = {
		"current_map_id": -1,
		"_zone_generation": 0,
		"_mobile_attack_held": false,
		"_queued_mobile_attack_tickets": ([] as Array[int]),
		"_active_mobile_attack_tokens": {},
		"_legacy_mobile_attack_token": 0,
		"_next_synthetic_attack_token": -1,
		"_active_skill_inputs": {},
		"_next_skill_input_sequence": 1,
		"_skill_input_retry_remaining": 0.0,
		"_keyboard_bound_skill_token": 0,
		"_attack_action_press_owned": false,
		"_attack_action_neutral_observed": true,
		"_attack_action_ignored_pressed_recorded": false,
		"_attack_action_lifecycle_epoch": 0,
		"_attack_action_diagnostic_serial": 0,
		"_attack_action_diagnostic_events": ([] as Array[Dictionary]),
		"_magic_shield_auto_enabled": false,
		"_magic_shield_auto_retry_remaining": 0.0,
	}

func read_field(name: String) -> Variant:
	if OS.get_thread_caller_id() != _owner: return null
	return _values[name]

func write_field(name: String, value: Variant) -> void:
	if OS.get_thread_caller_id() != _owner: return
	_values[name] = value
