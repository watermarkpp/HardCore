extends RefCounted

var _owner = OS.get_thread_caller_id()
var deps: Dictionary
var _configured = false
func owner_thread_id() -> int:
	return _owner
var shared_heuristics: Dictionary = {}
var shared_heuristic_order: Array[String] = []
var shared_walkability: Dictionary = {}
var shared_walkability_order: Array = []
var shared_goal_fields: Dictionary = {}
var shared_goal_field_order: Array = []
var diagnostic_frontier_rebuilds = 0
var diagnostic_frontier_rebuild_usec = 0
var diagnostic_frontier_rebuild_max_cells = 0
var diagnostic_shared_field_services = 0
var diagnostic_shared_field_expansions = 0
var diagnostic_shared_field_fallbacks = 0
func reset_diagnostics() -> void:
	diagnostic_frontier_rebuilds = 0
	diagnostic_frontier_rebuild_usec = 0
	diagnostic_frontier_rebuild_max_cells = 0
	diagnostic_shared_field_services = 0
	diagnostic_shared_field_expansions = 0
	diagnostic_shared_field_fallbacks = 0

func diagnostics() -> Dictionary:
	return {
		"m30_frontier_rebuilds": diagnostic_frontier_rebuilds,
		"m30_frontier_rebuild_usec": diagnostic_frontier_rebuild_usec,
		"m30_frontier_rebuild_max_cells": diagnostic_frontier_rebuild_max_cells,
		"shared_field_services": diagnostic_shared_field_services,
		"shared_field_expansions": diagnostic_shared_field_expansions,
		"shared_field_fallbacks": diagnostic_shared_field_fallbacks,
	}
