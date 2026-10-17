extends "res://tests/framework/helpers/main_visual_qualification_source_20261016.gd"
## Native journal transport scope, not a fabricated Caster ticket/WorldCore.
func _append_fixture_events(boot: Dictionary,site: Dictionary) -> void:
	for case_id: int in range(4):
		var identity := {"world":boot.world,"runtime_id":_actor_id.get_instance_id(),"life_generation":2 if case_id == 3 else 1}
		var source := {"actor_identity":identity,"monster_id":1234,"position_screen_px":Vector2(40,60) if case_id != 1 else Vector2(-100000,-100000),"source_present":true,"source_inside_world":true,"source_retiring":false}
		var command := {"world_context":boot.world,"operation":&"monster_audio" if case_id % 2 == 0 else &"player_physical_contact_audio","payload":{"actor_identity":identity,"source_pose":source,"arguments":[],"fixture_case":case_id}}
		_check(_journal.append({"kind":"original_world_presentation","operation":&"caster_presentation","arguments":[command],"source_site":site}),"same Native journal carries actual Source pose input:"+str(case_id))
	_expected_through = 8
