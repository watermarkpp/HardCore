extends Node
## Value-schema and real thread/viewport boundary checks only. They do not
## manufacture a successful Native map arrival or claim actual HUD adoption.
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Port := preload("res://scripts/gameplay/world/world_visual_viewport_port.gd")
const InputOwner := preload("res://scripts/gameplay/world/world_owner_input.gd")
var proof := Proof.new()
var failed := 0
func check(ok: bool,label: String) -> void:
	proof.record(ok,label)
	if not ok: failed += 1
func _ready() -> void: _run.call_deferred()
func _source(packet: Dictionary) -> Array:
	var rows: Array = []
	var input := InputOwner.new(null)
	var method: StringName = &"_is_original_viewport_observation"
	var exists: bool = input.has_method(method)
	rows.append([exists,"production input has an explicit observation-only shape gate"])
	if exists:
		rows.append([input.call(method,packet),"schema allows one same-world original Main viewport observation; NOT Native authority"])
		for kind: String in ["mobile_attack_started","skill_input_started","notification","shop_buy_requested","warehouse_sort_requested"]:
			var changed: Dictionary = packet.duplicate(true);changed.original_events[0].kind = kind
			rows.append([not input.call(method,changed),"no observation privilege for gameplay/lifecycle command " + kind])
		var extra: Dictionary = packet.duplicate(true);extra.original_events.append(extra.original_events[0].duplicate(true))
		rows.append([not input.call(method,extra),"mixed or duplicated event packet is not one viewport observation"])
		var context: Dictionary = packet.duplicate(true);context.original_events[0].view_context.world_context.profile_id = "foreign"
		rows.append([not input.call(method,context),"foreign event context cannot borrow original packet identity"])
		var measure: Dictionary = packet.duplicate(true);measure.original_events[0].arguments[0].world_identity.world_epoch += 1
		rows.append([not input.call(method,measure),"measurement identity cannot be relabeled to after-world"])
		var forged: Dictionary = packet.duplicate(true);forged.original_events[0].view_context.actual_Main_capture = false
		rows.append([not input.call(method,forged),"missing real Main capture marker refused"])
		var future: Dictionary = packet.duplicate(true);future.original_events[0].view_context.main_process_frame += 1
		rows.append([not input.call(method,future),"future or inconsistent Main capture frame refused"])
		var missing: Dictionary = packet.duplicate(true);missing.original_events[0].view_context.erase("actual_hud_observation")
		rows.append([not input.call(method,missing),"missing HUD observation remains a schema error"])
	var port := Port.new()
	var authority_exists: bool = port.has_method("can_accept_original_main_world")
	rows.append([authority_exists,"production viewport exposes independently checked observation binding"])
	if authority_exists: rows.append([not port.call("can_accept_original_main_world",packet.world_context),"unconfigured Source viewport cannot authorize even shape-valid delayed observation"])
	return rows
func _run() -> void:
	var root := Node2D.new(); add_child(root)
	var world := {"contract_id":"hardcore.execution.world_context.v1","world_runtime_id":root.get_instance_id(),"world_epoch":0,"runtime_map_id":-1,"profile_id":"late_viewport_schema_only"}
	var publication: Dictionary = Port.capture_original_main(root,world,3)
	check(not publication.is_empty() and publication.visible_rect == root.get_viewport().get_visible_rect(),"real physical Main viewport measurement captured")
	# Metadata prototype deliberately carries no command, fabricated Native
	# receipt or live HUD. A full World is still required for authorization.
	var packet := {"contract_id":"world.input.publication.v1","world_context":world,"sequence":8,"main_process_frame":Engine.get_process_frames(),"original_events":[{"kind":"world_viewport_publication","arguments":[publication],"view_context":{"actual_Main_capture":true,"world_context":world.duplicate(true),"main_process_frame":Engine.get_process_frames(),"actual_hud_observation":{}}}]}
	var worker := Thread.new();check(worker.start(Callable(self,"_source").bind(packet)) == OK,"actual independent Source constructor thread")
	while worker.is_alive(): await get_tree().process_frame
	for row: Array in worker.wait_to_finish():check(row[0],row[1])
	var input_source: String = FileAccess.get_file_as_string("res://scripts/gameplay/world/world_owner_input.gd")
	check(input_source.contains("_last_received_world == current") and input_source.contains("_is_original_viewport_observation(packet)"),"static input seam fences old-world observations once a current-world packet is received")
	var ui_source: String = FileAccess.get_file_as_string("res://scripts/gameplay/world/world_ui_command_owner.gd")
	check(ui_source.contains("event.get(\"kind\") == \"world_viewport_publication\"") and ui_source.contains("can_accept_original_main_world"),"static HUD context seam remains restricted to viewport observations")
	root.free()
	var written: bool = proof.write_receipt("late_viewport_observation_20261017",proof.records.size(),failed)
	print("LATE_VIEWPORT_OBSERVATION_", "PASS" if written and failed == 0 else "FAIL")
	get_tree().quit(0 if written and failed == 0 else 1)
