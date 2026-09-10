extends RefCounted

# Test fixture only. Never a production invulnerability policy.
# Observe mode never attaches this guard. Guarded mode records every repair.
const HP_MARGIN: int = 1000000000
var _player_ref: WeakRef
var repairs: int = 0
var profile_events: int = 0
var last_before: Dictionary = {}
var rejected_dead_state: bool = false

func attach(player: PlayerCharacter) -> bool:
	if _player_ref != null or not PlayerState.test_mode or not is_instance_valid(player):
		return false
	if player._dead or player.current_hp <= 0 or player.combat_transition_is_active():
		return false
	_player_ref = weakref(player)
	# Player._ready() connected _apply_profile_stats before this subscription.
	# The accompanying real-player regression verifies this ordering.
	PlayerState.profile_changed.connect(_after_profile_changed)
	_maintain_margin()
	return true

func _after_profile_changed() -> void:
	profile_events += 1
	_maintain_margin()

func _maintain_margin() -> void:
	var player: PlayerCharacter = _player_ref.get_ref() as PlayerCharacter if _player_ref != null else null
	if not is_instance_valid(player) or not PlayerState.test_mode:
		return
	last_before = {"hp": player.current_hp, "max_hp": player.max_hp, "dead": player._dead,
		"transition": player.combat_transition_is_active(), "physics_tick": Engine.get_physics_frames()}
	if player._dead or player.current_hp <= 0 or player.combat_transition_is_active():
		rejected_dead_state = true
		return # NEVER revive, release an input lock, or undo a combat epoch.
	if player.max_hp < HP_MARGIN:
		# Explicitly restore the lab survival margin after the production profile
		# recalculator. This is not an assertion about real gameplay HP semantics.
		var deficit: int = maxi(0, player.max_hp - player.current_hp)
		player.max_hp = HP_MARGIN
		player.current_hp = maxi(1, HP_MARGIN - deficit)
		repairs += 1

func snapshot() -> Dictionary:
	return {"enabled": _player_ref != null, "repairs": repairs, "profile_events": profile_events,
		"last_before": last_before.duplicate(), "rejected_dead_state": rejected_dead_state}

func detach() -> void:
	if PlayerState.profile_changed.is_connected(_after_profile_changed):
		PlayerState.profile_changed.disconnect(_after_profile_changed)
	_player_ref = null
