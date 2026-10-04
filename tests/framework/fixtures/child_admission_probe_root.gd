extends "res://tests/framework/fixtures/lease_probe_root.gd"

var clear_before_child_submit := false
var clear_count := 0
var child_results: Array[Dictionary] = []
var reenter_before_child_submit := false
var child_reentry_calls := 0
var child_reentry_served := -1
var maximum_producing_branches := 0

func _finish_feature_damage_batch(batch: RefCounted) -> Dictionary:
	if batch!=null and int(batch.chain_context().get("generation",0))>0:
		var producing:=0
		for root: Dictionary in _feature_effect_runtime._reservations.values():
			for branch: Dictionary in root.get("branches",{}).values():
				if branch.stage=="producing": producing+=1
		maximum_producing_branches=maxi(maximum_producing_branches,producing)
		if reenter_before_child_submit:
			reenter_before_child_submit=false; child_reentry_calls+=1
			child_reentry_served=_feature_effect_runtime.pump()
	if clear_before_child_submit and batch!=null and int(batch.chain_context().get("generation",0))>0:
		clear_before_child_submit=false; clear_count+=1
		# Explicit test-owned retirement after real HP/capture, before transfer.
		_feature_effect_runtime.clear()
	return super._finish_feature_damage_batch(batch)

func _execute_feature_child_action(request: Dictionary,ticket: RefCounted,bindings: Array,
	source: Node2D,resources: RefCounted) -> Dictionary:
	var result: Dictionary=super._execute_feature_child_action(request,ticket,bindings,source,resources)
	child_results.append(result.duplicate(true))
	return result
