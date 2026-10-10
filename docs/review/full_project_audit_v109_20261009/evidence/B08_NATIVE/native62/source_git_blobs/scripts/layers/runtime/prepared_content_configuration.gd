extends RefCounted

## A short-lived preparation owned by ContentLayers. It never enters the
## scene tree or becomes a runtime database authority.
var owner: WeakRef
var expected_expansions: Dictionary = {}
var database_revision := 0
var database_loaded := false
var layer_revision := 0
var requested_expansions: Dictionary = {}
var merged_database: Dictionary = {}
var merge_diagnostics: Array[String] = []
var database_candidate: Node
var consumed := false

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and is_instance_valid(database_candidate):
		database_candidate.free()
