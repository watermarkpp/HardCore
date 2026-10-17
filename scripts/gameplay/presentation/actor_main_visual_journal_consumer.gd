extends RefCounted

## Compose into the existing Main dispatcher used by the sole PrefixConsumer.
## This object does not acquire/ACK any prefix or append a second journal.
const PLAYER_FACTS := ["redraw","play_hit","play_death","play_action","refresh_profession","stats_changed","resources_changed"]
const ENEMY_OPERATIONS := [&"enemy_configure_y_sort",&"enemy_overhead_create",&"enemy_overhead_health",&"enemy_overhead_anchor_y",&"enemy_overhead_visible",&"enemy_overhead_retire",&"enemy_redraw"]
var _registry: RefCounted
var _existing: RefCounted
func configure_main(registry: RefCounted, actual_existing_dispatcher: RefCounted) -> bool:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _registry != null or registry == null or registry.owner_thread_id() != OS.get_main_thread_id() or actual_existing_dispatcher == null or not actual_existing_dispatcher.has_method("apply_original_main_journal_event"): return false
	_registry = registry; _existing = actual_existing_dispatcher
	return true

func apply_original_main_journal_event(event: Dictionary) -> Variant:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _registry == null: return false
	if event.get("kind") == "enemy_visual":
		if not event.get("event") is Dictionary: return false
		# Production injects the S streaming coordinator/SourceFrames owner.
		# These legacy requests are not completed facts and must not be replayed
		# by a second Main coordinator or accepted as empty acknowledgements.
		var visual: Dictionary = event.event
		if str(visual.get("operation","")).begins_with("coordinator_") or visual.get("operation") in [&"source_request_profile",&"projectile_prewarm"]:
			return {"status":"INVALID","error":"obsolete_Main_visual_replay_in_Source_owned_world","operation":visual.get("operation"),"ordinal":event.get("ordinal"),"source_site":event.get("source_site"),"visual_event":visual}
		return _registry.apply_original_enemy_visual_event(visual)
	if event.get("kind") == "original_world_presentation":
		var operation: Variant = event.get("operation")
		if operation in [&"create_loot_view",&"loot_filter",&"loot_visual_tick",&"place_loot_name",&"retire_loot_view"]:
			return _registry.apply_original_loot_event(event)
		if operation==&"enemy_input_pickable": return _registry.apply_original_enemy_input_pickable_event(event)
		if operation in [&"enemy_create_effect",&"enemy_effect_tick",&"retire_enemy_effect",&"spawn_target_aligned_melee_visual"]: return _registry.apply_original_enemy_effect_event(event)
		if operation in [&"ACTOR_HEADER",&"VISUAL_HEADER"]:
			return _registry.apply_original_enemy_structural_header(event)
		if operation == &"actor_visual_projection":
			if not event.get("arguments") is Array or event.arguments.size() != 1 or not event.arguments[0] is Dictionary: return false
			if event.arguments[0].get("kind") == "player" and not _registry.ensure_original_player_presentation(event.arguments[0]): return false
			return _registry.apply_source_projection(event.arguments[0])
		if operation == &"set_actor_stealth_alpha":
			return _registry.apply_original_actor_stealth_event(event)
		if operation in ENEMY_OPERATIONS:
			if not event.get("arguments") is Array: return false
			return _registry.apply_original_enemy_actor_operation(operation,event.arguments)
	if event.get("event") in PLAYER_FACTS and event.get("payload") is Dictionary and event.payload.get("visual_projection") is Dictionary:
		if not event.get("runtime_id") is int or not event.get("actor_ordinal") is int: return false
		if not _registry.ensure_original_player_presentation(event.payload.visual_projection): return false
		if not _registry.apply_original_player_presentation_fact(event.runtime_id,event.actor_ordinal,str(event.event),event.payload): return false
		# This fact owns the physical Player health bar only. The original
		# Source Root signal subscribers append their actual HUD view calls in
		# this same journal; forwarding here would replay no original callback
		# and reaches the deliberately rejecting unknown-event tail.
		return true
	return _existing.apply_original_main_journal_event(event)

# Preserve the sole prefix consumer's actual ACK and pending Map reply route
# through this projection wrapper. No prefix acquisition or inferred ACK.
func confirm_original_main_prefix_acknowledged(prefix: Dictionary, actual_native_receipt: Dictionary) -> bool:
	if _existing==null or not _existing.has_method("confirm_original_main_prefix_acknowledged"): return false
	return _existing.confirm_original_main_prefix_acknowledged(prefix,actual_native_receipt)
func flush_original_main_replies() -> Dictionary:
	if _existing==null or not _existing.has_method("flush_original_main_replies"): return {"status":"INVALID","error":"actual_Main_reply_dispatcher_missing"}
	return _existing.flush_original_main_replies()
func has_pending_original_main_replies() -> bool:
	return _existing==null or not _existing.has_method("has_pending_original_main_replies") or _existing.has_pending_original_main_replies()
