class_name CasterSkillAnimationBatch
extends RefCounted

## One presentation clock for identical looping sequences. Gameplay time,
## target queries, damage and world sort keys remain with their own owners.
var _players: Array[CasterSkillAnimationPlayer] = []
var _retry_players: Array[CasterSkillAnimationPlayer] = []
var _sequence_key := ""
var _frame_count := 0
var _frame_time_ms := 0.0
var _last_frame := -1
var frame_dispatch_count := 0
var player_commit_count := 0


func add_player(player: CasterSkillAnimationPlayer) -> bool:
	if player == null or not player.is_looping_sequence():
		return false
	var key := player.animation_sequence_key()
	if _players.is_empty():
		_sequence_key = key
		_frame_count = player.frame_count()
		_frame_time_ms = player.animation_duration() * 1000.0 / float(maxi(1, _frame_count))
	if key != _sequence_key or _frame_count <= 0 or _frame_time_ms <= 0.0:
		return false
	if _players.has(player):
		return true
	_players.append(player)
	player.set_batched_playback(true)
	_retry_players.append(player)
	return true


func synchronize(clock_ms: float) -> void:
	if _players.is_empty() or not is_finite(clock_ms) or clock_ms < 0.0:
		return
	var frame := clampi(int(floor(fmod(clock_ms, _frame_count * _frame_time_ms) / _frame_time_ms)), 0, _frame_count - 1)
	if frame == _last_frame and _retry_players.is_empty():
		return
	var candidates: Array[CasterSkillAnimationPlayer] = _players if frame != _last_frame else _retry_players.duplicate()
	_retry_players.clear()
	_last_frame = frame
	frame_dispatch_count += 1
	for player: CasterSkillAnimationPlayer in candidates:
		if not is_instance_valid(player) or player.is_queued_for_deletion():
			continue
		player_commit_count += 1
		if not player.commit_batched_frame(frame):
			_retry_players.append(player)


func diagnostics() -> Dictionary:
	return {
		"players": _players.size(), "frame_dispatches": frame_dispatch_count,
		"player_commits": player_commit_count, "pending_players": _retry_players.size(),
	}
