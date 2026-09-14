extends AudioStream

## Prepare only the native decoder, never start/mix/advance it. The ordinary
## AudioStreamPlayer still owns playback, buses, pause, stop and finished.
var source_stream: AudioStream
var _prepared: AudioStreamPlayback


func prepare() -> void:
	if _prepared == null and source_stream != null:
		_prepared = source_stream.instantiate_playback()


func _instantiate_playback() -> AudioStreamPlayback:
	if _prepared != null:
		var playback := _prepared
		_prepared = null
		return playback
	return source_stream.instantiate_playback() if source_stream != null else null


func _get_length() -> float:
	return source_stream.get_length() if source_stream != null else 0.0


func _get_stream_name() -> String:
	return source_stream.get_stream_name() if source_stream != null else ""
