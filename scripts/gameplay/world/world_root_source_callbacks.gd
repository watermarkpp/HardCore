extends "res://scripts/gameplay/world/world_root_numeric.gd"
## All gameplay callbacks execute on the same S Root/Profile/actor. Only the
## literal HUD/audio/render effects are token based Main view calls.
const UIErrorFeedbackScript := preload("res://scripts/ui_error_feedback.gd")
const UIPlayerNoticeScript := preload("res://scripts/ui_player_notice.gd")
const MapCoordinateMapperScript := preload("res://scripts/map_coordinate_mapper.gd")
var player: Object:
	get: return _world.skill_actors.player()
func gameplay_input_is_enabled() -> bool: return _world.gameplay_input_is_enabled()
func _world_skill_runtime() -> RefCounted: return _world.skills
func feature_world_capacity_bound() -> Dictionary:
	return _world_skill_runtime().feature_world_capacity_bound()
func _on_enemy_target_requested(enemy: Object) -> void:
	_world_skill_runtime()._on_enemy_target_requested(enemy)
func source_hud_is_present() -> bool:
	return hud != null and hud.has_method("is_original_view_present") and hud.is_original_view_present()
var _player_relic_proc_effect: Variant:
	get: return _fields.read_source_field(&"_player_relic_proc_effect")
	set(value): _fields.write_source_field(&"_player_relic_proc_effect",value)
var _player_level_up_effect: Variant:
	get: return _fields.read_source_field(&"_player_level_up_effect")
	set(value): _fields.write_source_field(&"_player_level_up_effect",value)
var _system_menu_panel: Variant:
	get: return _fields.read_source_field(&"_system_menu_panel")
	set(value): _fields.write_source_field(&"_system_menu_panel",value)
var _system_menu_pause_owned: Variant:
	get: return _fields.read_source_field(&"_system_menu_pause_owned")
	set(value): _fields.write_source_field(&"_system_menu_pause_owned",value)
var _test_force_home_failure: Variant:
	get: return _fields.read_source_field(&"_test_force_home_failure")
	set(value): _fields.write_source_field(&"_test_force_home_failure",value)

func _on_consumable_used(entity_id: String) -> void:
	if not gameplay_input_is_enabled(): return
	var item: Variant = _world.owner_services.GameData.get_entity_record(entity_id)
	if item.get("kind") != "consumable" or not item.get("usable", true): return
	var effect: Variant = str(item.get("useEffect", ""))
	var restored_hp: Variant = int(item.get("restoreHealth", 0))
	var restored_mp: Variant = int(item.get("restoreMana", 0))
	if effect == "delayed_restore" and (restored_hp > 0 or restored_mp > 0):
		player.queue_potion_restore(restored_hp, restored_mp)
	elif effect == "restore_both" and (restored_hp > 0 or restored_mp > 0):
		player.restore_health(restored_hp)
		player.restore_mana(restored_mp)
	elif effect == "temporary_buff":
		var duration: Variant = maxf(1.0, float(item.get("durationMinutes", 1)) * 60.0)
		var stats: Dictionary = item.get("stats", {})
		player.apply_defense_buff(duration, maxi(int(stats.get("MaxAC", 0)), int(stats.get("MaxMAC", 0))))
	elif entity_id == "hc.service_item.000123":
		# Preserve this exact pre-ID compatibility behavior. Its source curse
		# rule is a separate gameplay decision, not an identity migration.
		player.restore_health(30)
		player.restore_mana(30)
		player.apply_defense_buff(60.0, 2)
	# R2: the generic "使用了X" text is retired here — the structured use
	# result is the single central owner for every consumable use notice, so
	# this legacy signal lane must not add a second one. Effects stay.

func _on_background_item_save_failed() -> void:
	if source_hud_is_present():
		hud.show_error_message("最近的进度尚未保存，请检查存储空间")

func _on_scroll_used(entity_id: String) -> void:
	if not gameplay_input_is_enabled(): return
	var item: Variant = _world.owner_services.GameData.get_entity_record(entity_id)
	if item.get("kind") != "scroll" or not item.get("usable", true): return
	var effect: Variant = str(item.get("useEffect", ""))
	if effect in ["town_teleport", "dungeon_escape"]:
		travel_to_service_home(false, false, "比奇省")
	elif effect == "random_teleport":
		var destination: Variant = _find_valid_random_teleport_position(player.global_position)
		if destination == player.global_position:
			hud.show_error_message("附近没有可用传送落点")
			return
		_set_player_world_position(destination)
		_world.skill_actors.stop_velocity(player)
		_relocate_main_pets_after_map_arrival()
	elif effect == "repair_oil":
		_report_repair_oil_result(_world.profile.apply_weapon_repair_oil_result(false))
		return
	elif effect == "war_god_oil":
		_report_repair_oil_result(_world.profile.apply_weapon_repair_oil_result(true))
		return
	# R2: the generic "使用了X" text is retired here — the structured use
	# result is the single central owner for every scroll use notice, so this
	# legacy signal lane must not add a second one. Effects stay.

func _on_item_audio_committed(identity_domain: String, identity_id: int, semantic_event: String) -> void:
	if identity_domain not in ["item", "service"] or identity_id < 0:
		return
	if (_audio_runtime_service != null and _audio_runtime_service.is_original_view_present()):
		_audio_runtime_service.play_item_event(
			"%s:%d" % [identity_domain, identity_id], semantic_event,
			{"map_id": current_map_id},
		)

func _on_temporary_item_buff_expired(entity_id: String) -> void:
	if not source_hud_is_present():
		return
	var item: Variant = _world.owner_services.GameData.get_entity_record(entity_id)
	if not item.is_empty():
		hud.show_message("%s效果结束" % str(item.get("name", "")))


## R2: legacy potion combat buffs (ac/mac) report their end the same way.

func _on_player_potion_buff_expired(kind: String) -> void:
	if not source_hud_is_present():
		return
	hud.show_message("神水效果结束")

func _on_relic_proc_started(_item_id: int) -> void:
	if _world.skill_actors.is_runtime_present(player) and (_player_relic_proc_effect != null and _player_relic_proc_effect.is_original_view_present()):
		_player_relic_proc_effect.replay(player.approved_ground_footpoint_local_px())

func _on_player_levels_gained(previous_level: int, new_level: int) -> void:
	if new_level <= previous_level or not _world.skill_actors.is_runtime_present(player):
		return
	player.restore_level_up_resources()
	# PlayerState emits once per successful experience settlement, outside its
	# level loop. The approved visual follows the actor rather than a world point.
	if (_player_level_up_effect != null and _player_level_up_effect.is_original_view_present()):
		_player_level_up_effect.replay(player.approved_ground_footpoint_local_px())
	# R2: the level-up result joins the unified central notice layer.
	hud.show_success_message("等级提升至 %d" % new_level)

func _synchronize_main_pet_skill_ranks() -> void:
	_world_skill_runtime()._synchronize_main_pet_skill_ranks()

func _capture_taoist_main_pet_runtime_states() -> Dictionary:
	return _world_skill_runtime()._capture_taoist_main_pet_runtime_states()

func _sync_player_runtime_snapshot_to_hud() -> void:
	if hud == null or player == null:
		return
	hud.update_resources(player.current_hp, player.max_hp, player.current_mp, player.max_mp)
	hud.update_warrior_states(player.warrior_state_snapshot())

func _cancel_player_input_boundary(reason: StringName) -> void:
	if source_hud_is_present():
		hud.cancel_attack_inputs(reason)
		hud.cancel_skill_inputs(reason)
		hud.cancel_item_slot_input_boundary(reason)
	_cancel_map_transition_movement_input()
	_cancel_all_mobile_attack_inputs(true)
	_cancel_all_skill_inputs(true)
	_reset_attack_action_lifecycle(reason)


## R2: timed 神水 (temporary stat buff) expiry reports once through the
## central notice layer, projecting display text from the formal item owner.

func _toggle_system_menu() -> void:
	if _system_menu_panel != null and _system_menu_panel.visible:
		_hide_system_menu()
	else:
		_show_system_menu()

func _prepare_safe_logout() -> Dictionary:
	var death_queue_result: Variant = _drain_enemy_death_queue_for_logout()
	if not bool(death_queue_result.get("success", false)):
		return death_queue_result
	var loot_queue_result: Variant = _drain_loot_collection_queue_for_logout()
	if not bool(loot_queue_result.get("success", false)):
		return loot_queue_result
	_world.profile.apply_warrior_runtime_state(player.warrior_runtime_state_for_save())
	_world.profile.apply_taoist_main_pet_runtime_states(
		_capture_taoist_main_pet_runtime_states()
	)
	var home_map_id: Variant = _world.owner_services.GameData.service_home_runtime_map_id(false)
	var resolved: Variant = _resolve_bich_home()
	if not bool(resolved.get("valid", false)):
		return {
			"success": false,
			"save_performed": false,
			"reason": str(
				resolved.get("reason", "safe_logout_home_resolution_failed")
			),
			"home_source": str(resolved.get("source", "")),
		}
	var home_screen_position_px: Vector2 = resolved.get(
		"position_px", Vector2.ZERO
	) as Vector2
	var home_ground_gu: Variant = _ground_position_gu_for_map(
		home_map_id,
		home_screen_position_px
	)
	if not home_ground_gu.is_finite():
		# FREEZE-P0.2: never write Vector2.INF into the save/_world.profile.
		return {
			"success": false,
			"save_performed": false,
			"reason": "safe_logout_projection_unavailable",
			"home_source": str(resolved.get("source", "")),
		}
	var save_success: Variant = _world.profile.save_safe_logout(
		home_map_id,
		home_screen_position_px,
		home_ground_gu
	)
	if not save_success:
		return {
			"success": false,
			"save_performed": false,
			"reason": "safe_logout_save_failed",
			"home_source": str(resolved.get("source", "")),
		}
	return {
		"success": true,
		"save_performed": true,
		"reason": "",
		"home_source": str(resolved.get("source", "")),
	}

func _handle_safe_logout_failure(action: StringName, result: Dictionary) -> void:
	var diagnostic: Variant = {
		"action": str(action),
		"reason": str(result.get("reason", "")),
		"home_source": str(result.get("home_source", "")),
		"current_map_id": current_map_id,
		"player_position": (
			player.global_position if _world.skill_actors.is_runtime_present(player) else Vector2.ZERO
		),
		"save_performed": bool(result.get("save_performed", false)),
		"timestamp": Time.get_ticks_msec(),
	}
	set_meta("safe_logout_failure_diagnostic", diagnostic)
	_report_safe_logout_error(
		action,
		str(result.get("reason", "safe_logout_failed"))
	)
	var user_message: Variant = UIErrorFeedbackScript.from_result(result, "安全退出失败，请稍后重试。")
	if (_system_menu_panel != null and _system_menu_panel.is_original_view_present()) and _system_menu_panel.visible:
		_system_menu_panel.show_save_exit_failure(user_message)
	if source_hud_is_present() and hud.has_method("show_error_message"):
		# Player sees Chinese prose only; the raw reason stays in the
		# diagnostic above and in push_error via the reporter.
		hud.show_error_message(
			user_message,
			2.0
		)

func _cancel_map_transition_movement_input() -> void:
	if source_hud_is_present() and hud.has_method("cancel_movement_input"):
		hud.cancel_movement_input()
	if _world.skill_actors.is_runtime_present(player):
		# HUD's zero signal is intentionally ignored while the gameplay lock is
		# held, so clear the authoritative player vector at the boundary too.
		player.set_touch_vector(Vector2.ZERO)

func _play_skill_audio_phase(stable_skill_id: String, phase: String) -> void:
	if (_audio_runtime_service != null and _audio_runtime_service.is_original_view_present()):
		_audio_runtime_service.play_event("skill.%s.%s" % [stable_skill_id, phase], {
			"gender": _world.profile.gender,
			"map_id": current_map_id,
		})

func _on_skill_cast_audio_started(stable_skill_id: String) -> void:
	_play_skill_audio_phase(stable_skill_id, "cast")


## AOE first-engagement window (perf-smoothness-r1 Phase A): the first
## wizard.fire_wall cast opens the milestone window in _world.engagement. The
## window closes on the first committed enemy death (or its deadline) and
## reports real wall-clock frame intervals once. See _world.engagement.

func _on_first_fire_wall_cast_probe(stable_skill_id: String) -> void:
	_world.engagement.on_skill_cast(stable_skill_id)

func _on_warrior_skill_state_changed(_skill_name: String, _enabled: bool, message: String) -> void:
	_world.profile.apply_warrior_runtime_state(player.warrior_runtime_state_for_save(), true)
	if hud != null:
		hud.show_message(message, 1.5)
		hud.update_warrior_states(player.warrior_state_snapshot())

func _report_repair_oil_result(result: Dictionary) -> void:
	# The repair-oil authority now reports a structured result: an actual
	# repair stays on the notice lane, every rejection (no weapon, nothing to
	# repair, save failure) surfaces on the dedicated error channel.
	if bool(result.get("success", false)):
		hud.show_message(str(result.get("message", "")))
	else:
		hud.show_error_message(
			UIErrorFeedbackScript.from_result(result, "修复失败，请稍后重试。")
		)

func _sync_item_quick_slots_to_hud(_change: Dictionary = {}) -> void:
	if not source_hud_is_present() or not hud.has_method("set_item_quick_slots"):
		return
	hud.call("set_item_quick_slots", _world.profile.quick_item_slots_snapshot())

func _on_item_quick_slot_assignment_requested(
	slot_index: int,
	item_id: String
) -> void:
	var result: Variant = _world.profile.assign_quick_item_slot(slot_index, item_id)
	if not bool(result.get("ok", false)):
		_sync_item_quick_slots_to_hud()
		hud.show_error_message(UIErrorFeedbackScript.user_message(str(result.get("message", "快捷物品绑定失败"))))
		return
	_sync_item_quick_slots_to_hud()
	hud.show_message(str(result.get("message", "快捷物品已绑定")))

func _on_item_quick_slot_use_requested(
	slot_index: int,
	item_id: String
) -> void:
	if not gameplay_input_is_enabled():
		return
	var result: Variant = _world.profile.use_quick_item_slot(slot_index, item_id)
	if not bool(result.get("ok", false)):
		hud.show_error_message(UIErrorFeedbackScript.user_message(str(result.get("message", "快捷物品使用失败"))))
		return
	# One player action owns one central result notice (R2). Only the
	# contract-approved uses report (skill books, blessing/repair oils,
	# timed 神水); instant potions stay silent by design.
	var used_item: Variant = _world.owner_services.GameData.get_entity_record(str(result.get("entity_id", "")))
	if UIPlayerNoticeScript.should_report_item_use(used_item):
		hud.show_success_message(str(result.get("message", "")))

func _drain_enemy_death_queue_for_logout() -> Dictionary:
	# Exit actions are the one deliberate synchronous boundary for the deferred
	# death pipeline.  A queued death must finish (or become an explicit,
	# diagnosable terminal failure) before PlayerState writes its logout record;
	# otherwise a successful logout can silently lose XP, respawn state, or loot.
	if not _last_death_logout_failure.is_empty():
		var early_latched_failure: Variant = _last_death_logout_failure.duplicate(true)
		early_latched_failure["death_queue"] = death_work_queue_snapshot()
		return early_latched_failure
	_flush_pending_enemy_death_signals_for_logout()
	var terminal_count_before: Variant = _enemy_death_terminal_jobs.size()
	var guard: Variant = 0
	while not _pending_enemy_deaths.is_empty() and guard < 4096:
		var progressed: Variant = _pump_enemy_death_work_queue(true)
		guard += 1
		if not progressed:
			break
	if not _pending_enemy_deaths.is_empty():
		var pending_result: Variant = {
			"success": false,
			"save_performed": false,
			"reason": "safe_logout_death_queue_pending",
			"pending_deaths": _pending_enemy_deaths.size(),
			"death_queue": death_work_queue_snapshot(),
		}
		# Pending is the current queue state, not a terminal failure. A later
		# receipt can finish this work, so the next exit request must drain again.
		# Only FAILED settlements enter the durable in-session failure latch.
		return pending_result
	# A bounded terminal ledger can evict the just-created record when it was
	# already full.  The failure latch is therefore authoritative for this
	# drain; do not rely only on array indices below.
	if not _last_death_logout_failure.is_empty():
		var latched_failure: Variant = _last_death_logout_failure.duplicate(true)
		latched_failure["death_queue"] = death_work_queue_snapshot()
		return latched_failure
	for index: int in range(terminal_count_before, _enemy_death_terminal_jobs.size()):
		var terminal: Dictionary = _enemy_death_terminal_jobs[index]
		if str(terminal.get("state", "")) != DEATH_STATE_FAILED:
			continue
		var failed_result: Variant = {
			"success": false,
			"save_performed": false,
			"reason": "safe_logout_death_queue_failed",
			"death_key": str(terminal.get("death_key", "")),
			"death_error": str(terminal.get("last_error", "")),
			"death_queue": death_work_queue_snapshot(),
		}
		_last_death_logout_failure = failed_result.duplicate(true)
		return failed_result
	return {
		"success": true,
		"save_performed": false,
		"reason": "",
		"death_queue_drained": true,
	}

func _drain_loot_collection_queue_for_logout() -> Dictionary:
	# A close request may arrive after a pickup emitted its signal but before
	# the deferred transaction flush.  Force the manager's final nearby query
	# and consume the deferred collection synchronously before logout save.
	var manager_result: Dictionary = {}
	if _loot_pickup_runtime_manager != null:
		manager_result = _loot_pickup_runtime_manager.flush_for_logout()
		if not bool(manager_result.get("success", false)):
			return {
				"success": false,
				"save_performed": false,
				"reason": "safe_logout_loot_manager_failed",
				"loot_queue": manager_result,
			}
		if int(manager_result.get("logout_retry_blocked_count", 0)) > 0:
			return {
				"success": false,
				"save_performed": false,
				"reason": "safe_logout_loot_retry_pending",
				"loot_queue": manager_result,
			}
	if _pending_loot_collections.is_empty() and _prepared_loot_collection.is_empty():
		return {
			"success": true,
			"save_performed": false,
			"reason": "",
			"loot_queue_drained": true,
		}
	var result: Variant = _flush_loot_collections()
	if not bool(result.get("success", false)):
		return {
			"success": false,
			"save_performed": false,
			"reason": "safe_logout_loot_collection_failed",
			"loot_queue": result,
		}
	if not _pending_loot_collections.is_empty():
		return {
			"success": false,
			"save_performed": false,
			"reason": "safe_logout_loot_queue_pending",
			"loot_queue": result,
		}
	return {
		"success": true,
		"save_performed": false,
		"reason": "",
		"loot_queue_drained": true,
	}

func _resolve_bich_home() -> Dictionary:
	if _world.profile.test_mode and _test_force_home_failure:
		return {
			"valid": false,
			"position_px": Vector2.ZERO,
			"source": "test_hook",
			"reason": "missing_bich_home_position",
		}
	var editor_home: Variant = _world.required_owner_service(&"WorldHomeSource").home_screen_position_px()
	if editor_home != Vector2.ZERO:
		return {"valid": true, "position_px": editor_home, "source": "runtime_bridge", "reason": ""}
	var profile: Dictionary = _world.required_owner_service(&"WorldHomeSource").get_map_profile(4)
	var runtime_home: Variant = profile.get("runtime_home_position")
	if runtime_home is Vector2 and (runtime_home as Vector2) != Vector2.ZERO:
		return {"valid": true, "position_px": runtime_home as Vector2, "source": "runtime_home_position", "reason": ""}
	var home_coord: Variant = profile.get("service_home_coordinate")
	var source_size: Variant = profile.get("source_size", null)
	if home_coord is Vector2i and source_size is Vector2i:
		return {"valid": true, "position_px": MapCoordinateMapperScript.source_to_world(Vector2(home_coord), source_size as Vector2i), "source": "service_home_coordinate", "reason": ""}
	push_error("no formal home position available from editor, catalog, or map profile for map 4")
	return {"valid": false, "position_px": Vector2.ZERO, "source": "", "reason": "missing_bich_home_position"}


# Read-only convenience for tests/debug/display only. Returns the formal Home
# position when resolvable, else Vector2.ZERO. Production side-effect paths must
# call _resolve_bich_home() and handle failure explicitly.

func _hide_system_menu() -> void:
	if _system_menu_panel != null:
		_system_menu_panel.close_menu()
	_release_system_menu_pause()

func _show_system_menu() -> void:
	if _system_menu_panel == null:
		return
	# The paused tree may never receive the matching Android UP/CANCEL. Revoke
	# each current owner before pausing; a later press must establish a new token.
	_cancel_player_input_boundary(&"system_menu_opened")
	_system_menu_pause_owned = _system_menu_pause_owned or not _world.profile_world_paused()
	_system_menu_panel.open_menu()
	_apply_original_host_pause(true)

func _release_system_menu_pause() -> void:
	if not _system_menu_pause_owned:
		return
	_cancel_player_input_boundary(&"system_menu_closed")
	_system_menu_pause_owned = false
	_apply_original_host_pause(false)

func _find_valid_random_teleport_position(origin_screen_px: Vector2) -> Vector2:
	return _world_skill_runtime()._find_valid_random_teleport_position(origin_screen_px)

func _release_gameplay_input_lock(reason: StringName) -> void:
	var _count: int = int(_gameplay_input_locks.get(reason, 0))
	if _count <= 0:
		push_warning("attempted to release missing gameplay lock: %s" % reason)
		return
	if _count == 1:
		_gameplay_input_locks.erase(reason)
	else:
		_gameplay_input_locks[reason] = _count - 1
	_refresh_gameplay_input_state()
	if _gameplay_input_locks.is_empty() and _world.skill_actors.is_runtime_present(player):
		# A completed bootstrap/map/death transition is a fresh movement
		# gesture. Never carry a pre-transition run-up into the ready world,
		# even when the player keeps a direction held through the lock.
		player.reset_locomotion()
	if _world.diagnostics.input_gate_enabled():
		print("[GameplayInputGate] enabled=", gameplay_input_is_enabled(), " locks=", _gameplay_input_locks)

func _on_passive_wake_emitter_changed(emitter_id: int) -> void:
	_mark_passive_monster_wakeup_dirty(emitter_id)

func _on_passive_wake_summon_state_changed(
	_previous_state: int,
	_current_state: int,
	emitter_id: int,
) -> void:
	_mark_passive_monster_wakeup_dirty(emitter_id)

func _on_passive_wake_emitter_exiting(emitter_id: int) -> void:
	_passive_wake_emitters.erase(emitter_id)
	if _passive_wake_active_emitter_id == emitter_id:
		_passive_wake_candidates.clear()
		_passive_wake_cursor = 0
		_passive_wake_query_pending = false
		_passive_wake_active_emitter_id = 0

func _flush_pending_enemy_death_signals_for_logout() -> void:
	# A lethal hit queues Enemy._begin_death() through call_deferred().  A WM
	# close can arrive before that deferred callback, so explicitly finish the
	# actor-side death boundary before draining the GameRoot queue.  This is an
	# exit-only scan; it is never part of gameplay or per-frame processing.
	var pending_actors: Array[Object] = []
	var seen_instance_ids: Dictionary = {}
	var candidates: Array = []
	if _world.is_inside_world():
		candidates.append_array(_world.skill_actors.actors_in_group(&"death_pending"))
	for raw_actor: Variant in _active_enemy_cache.values():
		candidates.append(raw_actor)
	for raw_actor: Variant in candidates:
		if not raw_actor is Object or not _world.skill_actors.is_kind(raw_actor,&"enemy") or not _world.skill_actors.is_runtime_present(raw_actor):
			continue
		var enemy: Object = raw_actor
		var instance_id: Variant = _world.skill_actors.runtime_actor_id(enemy)
		if seen_instance_ids.has(instance_id):
			continue
		seen_instance_ids[instance_id] = true
		if enemy._death_pending and not enemy._dying:
			pending_actors.append(enemy)
	for enemy: Object in pending_actors:
		if _world.skill_actors.is_runtime_present(enemy) and enemy._death_pending and not enemy._dying:
			enemy._begin_death()

func travel_to_service_home(force := false, staged := false, region := "") -> bool:
	return _world.required_owner_service(&"WorldBootstrapPipeline").travel_to_service_home(force,staged,region)
func _relocate_main_pets_after_map_arrival() -> void:
	_world.skills._relocate_main_pets_after_map_arrival()
func _apply_original_host_pause(paused: bool) -> void:
	var port: RefCounted = _world.required_owner_service(&"WorldPauseControl")
	if not port.apply_original_pause(paused,_world.current_clock_frame()):
		_world.fault("actual_original_pause_boundary_missing",{"paused":paused})
func _report_safe_logout_error(action: StringName, reason: String) -> void:
	# The original injectable reporter has only diagnostic output authority.
	if not _world.emit_original_main_event(&"safe_logout_error_report",[action,reason]):
		_world.fault("safe_logout_error_report_outbox_rejected",{})
func _wire_item_quick_slots_hud() -> void:
	if not source_hud_is_present(): return
	# Main connects its genuine UI signals to pure-value input publication.
	# S receives the matching method names; no Callable or live Node crosses.
	if not hud.register_original_input_routes(["item_quick_slot_assignment_requested","item_quick_slot_use_requested"]):
		_world.fault("actual_item_quick_slot_input_routes_missing",{})
		return
	_sync_item_quick_slots_to_hud()
	if not _world.profile.quick_item_slots_changed.is_connected(_sync_item_quick_slots_to_hud):
		_world.profile.quick_item_slots_changed.connect(_sync_item_quick_slots_to_hud)
