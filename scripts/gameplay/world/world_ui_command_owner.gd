extends RefCounted
## Source callbacks retain their original Profile algorithms. Actual Main view
## stock/page values accompany the genuine emitted signal as plain context.
const SkillLoadoutRules := preload("res://scripts/skill_loadout_rules.gd")
const ROUTES := {
	"movement_changed":["_on_gameplay_movement",1],"interact_pressed":["_try_interact",0],
	"skill_slot_pressed":["_use_skill_slot",2],"target_switch_pressed":["_cycle_target",0],
	"auto_target_changed":["_set_auto_target_enabled",1],"map_teleport_availability_requested":["_on_map_teleport_availability_requested",1],
	"map_teleport_requested":["_on_map_teleport_requested",1],"revival_requested":["_on_revival_requested",1],
	"continue_requested":["_hide_system_menu",0],"return_to_character_select_requested":["_return_to_character_select",0],
	"save_and_exit_requested":["_exit_game",0]
}
var _owner := OS.get_thread_caller_id()
var _core: WeakRef
var _root: WeakRef
var _hud: RefCounted
var _menu: RefCounted
var _viewport: RefCounted
func owner_thread_id() -> int: return _owner
func configure_owner(core: RefCounted, root: RefCounted, hud: RefCounted, menu: RefCounted, viewport: RefCounted) -> bool:
	if _core != null or _owner == OS.get_main_thread_id(): return false
	for value: RefCounted in [core,root,hud,menu,viewport]:
		if value == null or value.owner_thread_id() != _owner: return false
	_core = weakref(core); _root = weakref(root); _hud = hud; _menu = menu; _viewport=viewport
	return true
func _context(event: Dictionary, field: String) -> Variant:
	var context: Dictionary = event.get("view_context",{})
	if context.get("actual_Main_capture") != true or not context.has(field): return null
	if context.get("world_context") != _core.get_ref().current_world_identity():
		if not (event.get("kind") == "world_viewport_publication" and context.get("world_context") is Dictionary and _viewport.can_accept_original_main_world(context.world_context)): return null
	return context.get(field)
func dispatch_original_hud_event(event: Dictionary) -> bool:
	if not event.get("kind") is String or not event.get("arguments") is Array: return false
	var kind: String = event.kind
	var args: Array = event.arguments
	var profile: RefCounted = _core.get_ref().profile
	match kind:
		"loading_transition_covered":
			return args.size()==1 and args[0] is Dictionary and _hud.deliver_original_loading_cover(args[0],event.get("view_context",{}))
		"world_viewport_publication":
			var observation: Variant = _context(event,"actual_hud_observation")
			return args.size()==1 and args[0] is Dictionary and args[0].get("world_identity") == event.get("view_context",{}).get("world_context") and observation is Dictionary and _hud.accept_actual_original_hud_observation(observation) and _viewport.accept_original_main(args[0])
		"shop_sell_quotes_requested":
			if args.size() != 1 or not args[0] is Array: return false
			_hud.set_shop_sell_quotes(profile.shop_sell_quotes(args[0]))
		"shop_buy_quotes_requested":
			if args.size() != 1 or not args[0] is Array: return false
			_hud.set_shop_buy_quotes(profile.shop_buy_quotes(args[0]))
		"shop_buy_requested":
			if args.size() != 1 or not args[0] is Dictionary: return false
			var stock: Variant = _context(event,"shop_stock")
			if not stock is Array: return false
			_hud.apply_shop_buy_result(profile.buy_shop_item(args[0],stock))
		"shop_sell_requested":
			if args.size() != 1 or not args[0] is Dictionary: return false
			var request: Dictionary = args[0]
			var result: Dictionary = profile.sell_inventory_items(request.get("batch",[])) if request.get("batch",null) is Array else profile.sell_inventory_item(request)
			_hud.apply_shop_sell_result(result)
		"quest_abandon_requested":
			if args.size() != 1 or not args[0] is String: return false
			_hud.apply_quest_abandon_result(profile.abandon_quest(args[0]))
		"warehouse_sort_requested":
			if not args.is_empty(): return false
			var page: Variant = _context(event,"warehouse_page")
			if not page is int: return false
			_hud.apply_warehouse_sort_result(profile.sort_warehouse(page))
		"skill_button_assignment_requested":
			if args.size() != 1 or not args[0] is Dictionary: return false
			_skill_assignment(args[0])
		"visibility_changed":
			if not args.is_empty(): return false
			var visible_now: Variant = _context(event,"menu_visible_in_tree")
			if not visible_now is bool: return false
			_menu.accept_original_visible(visible_now)
			if not visible_now: _root.get_ref()._release_system_menu_pause()
		"audio_setting_changed":
			if args.size() != 1 or not args[0] is Dictionary: return false
			return _core.get_ref().emit_original_main_event(&"original_audio_setting",[args[0]])
		"target_switch_pressed":
			if not args.is_empty(): return false
			_cycle_target()
		"auto_target_changed":
			if args.size()!=1 or not args[0] is bool: return false
			_set_auto_target_enabled(args[0])
		"skill_slot_pressed":
			if args.size()!=2 or not args[0] is String or not args[1] is int: return false
			_core.get_ref().skills._use_skill_slot(args[0],args[1])
		"return_to_character_select_requested", "save_and_exit_requested":
			if not args.is_empty(): return false
			_safe_logout(kind)
		"source_frames_texture_demand":
			if args.size()!=1 or not args[0] is Dictionary: return false
			return _core.get_ref().required_owner_service(&"SourceFrames").accept_original_texture_demand(args[0])
		_:
			if not ROUTES.has(kind) or args.size() != ROUTES[kind][1]: return false
			var root: RefCounted = _root.get_ref()
			if not root.has_method(ROUTES[kind][0]):
				_core.get_ref().fault("MISSING_original_Source_UI_callback",{"event":kind,"method":ROUTES[kind][0]})
				return false
			root.callv(ROUTES[kind][0],args)
	return not _core.get_ref().is_faulted()
func _safe_logout(kind: String) -> void:
	var root: RefCounted=_root.get_ref()
	var result: Dictionary=root._prepare_safe_logout()
	if result.get("success")!=true:
		root._handle_safe_logout_failure(&"return_to_character_select" if kind=="return_to_character_select_requested" else &"exit_game",result)
		return
	if not _core.get_ref().emit_original_main_event(&"original_tree_pause",[false]): return
	if kind=="return_to_character_select_requested":
		var core: RefCounted=_core.get_ref()
		if not core.emit_original_main_event(&"original_character_select_transition",[]): return
		if not core.original_source_session().record_actual_profile_return_intent(core,root): core.fault("actual_Source_profile_return_intent_rejected",{})
	else:
		_core.get_ref().emit_original_main_event(&"original_tree_quit",[])
func _cycle_target() -> void:
	var skills: RefCounted=_core.get_ref().skills
	skills._validate_locked_target()
	var magic: bool=skills._magic_target_domain_is_active()
	var candidates: Array=skills._spell_lock_candidates() if magic else skills._attack_lock_candidates()
	if candidates.is_empty():
		if magic: skills._cancel_magic_target()
		else: skills._cancel_target()
		_hud.show_error_message("周围12格内没有可锁定目标" if magic else "周围10格内没有可锁定目标")
		return
	var next_index:=0
	var current: Object=skills.magic_locked_target if magic else skills.locked_target
	var current_index: int=candidates.find(current)
	if current_index>=0: next_index=(current_index+1)%candidates.size()
	if magic:
		skills._set_magic_locked_target(candidates[next_index],true)
		skills._skill_cast_target=skills.magic_locked_target
		skills._face_skill_cast_target()
	else:
		skills._set_attack_locked_target(candidates[next_index],true)
		skills._face_locked_target()
func _set_auto_target_enabled(enabled: bool) -> void:
	var skills: RefCounted=_core.get_ref().skills
	skills.auto_target_enabled=enabled
	_hud.set_auto_target_enabled(enabled)
	if enabled:
		if skills._uses_magic_lock_domain(): skills._cancel_target();skills._cancel_magic_target()
		else: skills._cancel_target()
	else:
		skills.manual_target_lock=_core.get_ref().skill_actors.is_runtime_present(skills.locked_target)
		if skills._uses_magic_lock_domain(): skills.manual_magic_target_lock=_core.get_ref().skill_actors.is_runtime_present(skills.magic_locked_target)
		_root.get_ref()._update_target_hud()
func _skill_assignment(request: Dictionary) -> void:
	var profile: RefCounted = _core.get_ref().profile
	var result: Dictionary = SkillLoadoutRules.clear_button_slot(profile.skill_button_assignments_snapshot(),request) if bool(request.get("clear",false)) else SkillLoadoutRules.assign_button_slot(profile.skill_button_assignments_snapshot(),profile.skill_assignment_roster(),request)
	if not bool(result.get("ok",false)):
		_hud.show_error_message("技能栏配置失败")
		return
	if not profile.apply_skill_button_assignment(result):
		_hud.set_skill_button_assignments(profile.skill_button_assignments_snapshot())
		_hud.show_error_message("技能栏配置未能保存")
		return
	var root: RefCounted = _root.get_ref()
	root._reset_attack_action_lifecycle(&"skill_assignment_changed")
	_hud.cancel_attack_inputs(&"skill_assignment_changed"); _hud.cancel_skill_inputs(&"skill_assignment_changed")
	root._cancel_all_mobile_attack_inputs(true); root._cancel_all_skill_inputs(true)
	_hud.set_skill_button_assignments(profile.skill_button_assignments_snapshot())
	var change: Dictionary = result.get("change",{})
	var group_label := "攻击键" if str(change.get("slot_group","")) == profile.SKILL_SLOT_GROUP_ATTACK else "攻击环%d" % (int(change.get("slot_index",0))+1)
	if str(change.get("operation","")) == "clear": _hud.show_message("%s已恢复普通攻击" % group_label if group_label == "攻击键" else "%s已清空" % group_label,1.5)
	else: _hud.show_message("已将%s配置到%s" % [str(change.get("skill_name","技能")),group_label],1.5)
