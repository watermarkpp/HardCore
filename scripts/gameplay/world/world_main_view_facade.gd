extends RefCounted
signal loading_transition_covered(request: Dictionary)
## Same-S facade for literal Main view writes. It has no Node or resource.
var _owner := OS.get_thread_caller_id()
var _core: WeakRef
var _kind: String
var _facts: Dictionary
var _state: Dictionary
var _ui_loading: RefCounted
func owner_thread_id() -> int: return _owner
func configure_owner(core: RefCounted, kind: String, facts: Dictionary) -> bool:
	if _core != null or _owner == OS.get_main_thread_id() or core.owner_thread_id() != _owner or facts.get("present") != true or not facts.get("node_id") is int or facts.node_id <= 0: return false
	_core = weakref(core); _kind = kind; _facts = facts.duplicate(true); _state = facts.get("state",{}).duplicate(true)
	return true
func is_original_view_present() -> bool: return _core != null and _facts.present
func actual_original_main_node_id() -> int: return int(_facts.node_id)
func deliver_original_loading_cover(request: Dictionary, context: Dictionary) -> bool:
	if OS.get_thread_caller_id() != _owner or _kind != "hud" or context.get("actual_Main_capture") != true or context.get("world_context") != _core.get_ref().current_world_identity() or context.get("actual_hud_id") != _facts.node_id: return false
	if request.get("contract_id") != preload("res://scripts/loading_transition_overlay.gd").CONTRACT_ID or not request.get("transition_id") is String or request.transition_id.is_empty(): return false
	# The original awaiting Root filters the transition ID itself. A genuine
	# earlier cover can arrive while a newer transition is already waiting.
	loading_transition_covered.emit(request)
	return true

func accept_actual_original_hud_observation(observation: Dictionary) -> bool:
	if OS.get_thread_caller_id() != _owner or _kind != "hud" or observation.size() != 4 or observation.get("actual_hud_id") != _facts.node_id: return false
	if not observation.get("_last_hp") is int or not observation.get("_last_max_hp") is int or not observation.get("_catalog_icon_prewarm_complete") is bool: return false
	for field: String in ["_last_hp","_last_max_hp","_catalog_icon_prewarm_complete"]: _state[field] = observation[field]
	return true

# These are observed display values, never the Player's HP/state authority.
var _last_hp: int:
	get: return int(_state._last_hp)
var _last_max_hp: int:
	get: return int(_state._last_max_hp)
var _catalog_icon_prewarm_complete: bool:
	get: return bool(_state._catalog_icon_prewarm_complete)
func bind_original_UI_Loading(port: RefCounted) -> bool:
	if _kind!="hud" or _ui_loading!=null or port==null or port.owner_thread_id()!=_owner: return false
	_ui_loading=port
	return true
func _emit(method: StringName, args: Array) -> void:
	if not _core.get_ref().emit_original_main_event(&"original_view_call",[_kind,_facts.node_id,method,args]): _core.get_ref().fault("original_view_journal_rejected",{"kind":_kind,"method":method})
func _set_state(key: StringName, value: Variant) -> void:
	_state[key] = value
	if not _core.get_ref().emit_original_main_event(&"original_view_set",[_kind,_facts.node_id,key,value]): _core.get_ref().fault("original_view_property_rejected",{"kind":_kind,"property":key})
var visible: bool:
	get: return bool(_state.get("visible",false))
func accept_original_visible(value: bool) -> void: _state.visible = value
var global_position: Vector2:
	get: return _state.get("global_position",Vector2.ZERO)
	set(value): _set_state(&"global_position",value)
var position: Vector2:
	get: return _state.get("position",Vector2.ZERO)
	set(value): _set_state(&"position",value)
var zoom: Vector2:
	get: return _state.get("zoom",Vector2.ONE)
	set(value): _set_state(&"zoom",value)
var offset: Vector2:
	get: return _state.get("offset",Vector2.ZERO)
	set(value): _set_state(&"offset",value)
var position_smoothing_enabled: bool:
	get: return bool(_state.get("position_smoothing_enabled",false))
	set(value): _set_state(&"position_smoothing_enabled",value)
func force_update_scroll() -> void: _emit(&"force_update_scroll",[])
func reset_smoothing() -> void: _emit(&"reset_smoothing",[])
func open_menu() -> void: _state.visible = true; _emit(&"open_menu",[])
func close_menu() -> void: _state.visible = false; _emit(&"close_menu",[])
func show_save_exit_failure(message: String) -> void: _emit(&"show_save_exit_failure",[message])
func replay(point: Vector2) -> void: _emit(&"replay",[point])
func play_item_event(identity: String, semantic: String, context: Dictionary) -> void: _emit(&"play_item_event",[identity,semantic,context])
func play_event(id: String, context: Dictionary = {}) -> void: _emit(&"play_event",[id,context])
func stop_all_audio(reason := "world_exit") -> void: _emit(&"stop_all_audio",[reason])
func set_town_presence(inside: bool) -> void: _emit(&"set_town_presence",[inside])
func begin_map_transition(map: int, transition: String) -> void: _emit(&"begin_map_transition",[map,transition])
func set_map_context(map: int, zones: Array, position_gu: Vector2, transition: String) -> void: _emit(&"set_map_context",[map,zones,position_gu,transition])
func cancel(reason := "cancelled") -> void: _emit(&"cancel",[reason])
func show_message(message: String, duration := 2.0) -> void: _emit(&"show_message",[message,duration])
func show_error_message(message: String, duration := 2.0) -> void: _emit(&"show_error_message",[message,duration])
func show_success_message(message: String, duration := 2.0) -> void: _emit(&"show_success_message",[message,duration])
func update_resources(hp: int, maximum: int, mp: int, maximum_mp: int) -> void: _emit(&"update_resources",[hp,maximum,mp,maximum_mp])
func update_hp(hp: int, maximum: int) -> void: _emit(&"update_hp",[hp,maximum])
func show_loot_batch(names: Array) -> void: _emit(&"show_loot_batch",[names])
func show_death_screen(context: Dictionary = {}) -> void: _emit(&"show_death_screen",[context])
func apply_revival_result(result: Dictionary) -> void: _emit(&"apply_revival_result",[result])
func update_warrior_states(states: Dictionary) -> void: _emit(&"update_warrior_states",[states])
func update_status_buffs(entries: Array) -> void: _emit(&"update_status_buffs",[entries])
func cancel_attack_inputs(reason: StringName) -> void: _emit(&"cancel_attack_inputs",[reason])
func cancel_skill_inputs(reason: StringName) -> void: _emit(&"cancel_skill_inputs",[reason])
func cancel_item_slot_input_boundary(reason: StringName) -> void: _emit(&"cancel_item_slot_input_boundary",[reason])
func cancel_movement_input() -> void: _emit(&"cancel_movement_input",[])
func set_item_quick_slots(slots: Array) -> void: _emit(&"set_item_quick_slots",[slots])
func set_skill_button_assignments(slots: Dictionary, modes: Dictionary = {}) -> void: _emit(&"set_skill_button_assignments",[slots,modes])
func update_target(title: String, hp: int, maximum: int, manual: bool, automatic: bool, monster_id := -1) -> void: _emit(&"update_target",[title,hp,maximum,manual,automatic,monster_id])
func set_zone_name(title: String) -> void: _emit(&"set_zone_name",[title])
func begin_loading_transition(id: String) -> void: _emit(&"begin_loading_transition",[id])
func update_loading_progress(id: String, progress: float, message: String) -> void: _emit(&"update_loading_progress",[id,progress,message])
func finish_loading_transition() -> void: _emit(&"finish_loading_transition",[])
func set_shop_sell_quotes(quotes: Dictionary) -> void: _emit(&"set_shop_sell_quotes",[quotes])
func set_shop_buy_quotes(quotes: Array) -> void: _emit(&"set_shop_buy_quotes",[quotes])
func apply_shop_buy_result(result: Dictionary) -> void: _emit(&"apply_shop_buy_result",[result])
func apply_shop_sell_result(result: Dictionary) -> void: _emit(&"apply_shop_sell_result",[result])
func apply_quest_abandon_result(result: Dictionary) -> void: _emit(&"apply_quest_abandon_result",[result])
func apply_warehouse_sort_result(result: Dictionary) -> void: _emit(&"apply_warehouse_sort_result",[result])
func set_map_teleport_availability(rules: Dictionary) -> void: _emit(&"set_map_teleport_availability",[rules])
func set_auto_target_enabled(enabled: bool) -> void: _emit(&"set_auto_target_enabled",[enabled])
func prewarm_all_panels(menu: RefCounted) -> bool: return await _ui_loading.prewarm_all_panels(int(_facts.node_id),menu.actual_original_main_node_id())
func _start_catalog_icon_prewarm(all_icons: bool) -> void: _ui_loading.start_original_catalog_icon_prewarm(int(_facts.node_id),all_icons)
func all_panels_are_prewarmed() -> bool: return _ui_loading.actual_original_panels_prewarmed(int(_facts.node_id))
func panel_prewarm_diagnostic() -> Dictionary: return _ui_loading.actual_original_panel_prewarm_diagnostic(int(_facts.node_id))
func start_budgeted_panel_prewarm(menu: RefCounted) -> void: _ui_loading.start_original_budgeted_panel_prewarm(int(_facts.node_id),menu.actual_original_main_node_id())
func register_original_input_routes(routes: Array) -> bool:
	for route: String in routes:
		if route not in _facts.input_routes: return false
	return true # Captured actual signal connections, never newly guessed routes.
