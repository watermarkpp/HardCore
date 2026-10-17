extends "res://tests/framework/helpers/main_visual_qualification_source_20261016.gd"
var _actor_without_visual: Object
func _append_fixture_events(boot: Dictionary, site: Dictionary) -> void:
	_actor_without_visual = Object.new()
	var ordinal: int = _journal.next_original_event_identity().event_ordinal
	var header := {"contract_id":Header.CONTRACT,"header_kind":"ACTOR_HEADER","actor_identity":{"world":boot.world,"runtime_id":_actor_without_visual.get_instance_id(),"life_generation":1},"event_identity":{"bridge_generation":int(_host.capabilities().bridge_generation),"journal_generation":1,"event_ordinal":ordinal},"sequence":ordinal,"source_site":site}
	_check(_journal.append({"kind":"original_world_presentation","operation":&"ACTOR_HEADER","arguments":[Header.capture(header)],"source_site":site}),"a second genuine actor header has no invented visual service")
	_expected_through = ordinal
func close_session() -> bool:
	if not super.close_session(): return false
	_actor_without_visual.free(); _actor_without_visual = null
	return true
