from pathlib import Path
import json
import hashlib

root=Path(r'C:/Users/Administrator/Documents/HardCore')
base=Path(r'C:/Users/Administrator/.codex/worktrees/r4-fixed-baseline/HardCore')
p=root/'tests/hc_monster_combat_r4/t6_real_load_probe.gd'
s=p.read_text(encoding='utf-8-sig')
old='\tvar t6_cast_seed_inputs: Array = []\n'
new='''\tconst DROP_SESSION := "20260927000000000000000000000000"
\tvar t6_cast_seed_inputs: Array = []
\tvar t6_death_identity_inputs: Array = []
\tvar t6_item_identity_inputs: Array = []

\t# The native callback enqueues a unique identity and schedules deferred work.
\t# Pin this input while still QUEUED, before any transaction or affix consumer.
\t# Damage attribution continues to use the real actor ID; do not alter actors.
\tfunc _on_enemy_died(enemy: EnemyActor, monster_data: Dictionary) -> void:
\t\tvar previous_sequence := _enemy_death_sequence
\t\tsuper._on_enemy_died(enemy, monster_data)
\t\tassert(_enemy_death_sequence == previous_sequence + 1, "native death was not queued")
\t\tvar death: Dictionary = _pending_enemy_deaths.back()
\t\tassert(int(death.sequence) == _enemy_death_sequence and death.state == DEATH_STATE_QUEUED)
\t\tvar slot := str(enemy.get_meta("spawn_slot_id", ""))
\t\tassert(slot.begins_with("t6:") and slot.trim_prefix("t6:").is_valid_int())
\t\tvar ordinal := int(slot.trim_prefix("t6:"))
\t\tassert(ordinal > 0)
\t\tvar native_key := str(death.death_key)
\t\tvar fixed_key := "death:%d:%d:%d:%d" % [death.origin_map_id, death.origin_generation, death.sequence, ordinal]
\t\tdeath["death_key"] = fixed_key
\t\tt6_death_identity_inputs.append({"sequence": death.sequence, "spawn_ordinal": ordinal,
\t\t\t"map_id": death.origin_map_id, "generation": death.origin_generation,
\t\t\t"native_key": native_key, "fixed_key": fixed_key})

\t# Observe the actual native result; no filtering, rerolling or payload writes.
\tfunc _plan_enemy_death_item(death: Dictionary) -> bool:
\t\tvar completed := super._plan_enemy_death_item(death)
\t\tif str(death.state) == DEATH_STATE_PLANNED:
\t\t\tvar item_index := 0
\t\t\tfor request: Dictionary in death.drop_plan.requests:
\t\t\t\tif not request.has("item_record"):
\t\t\t\t\tcontinue
\t\t\t\tvar record: Dictionary = request.item_record
\t\t\t\tvar instance: Dictionary = record.get("item_instance", {})
\t\t\t\tif not instance.is_empty():
\t\t\t\t\tvar key := "%s:%s:item:%d" % [DROP_SESSION, death.death_key, item_index]
\t\t\t\t\tvar digest := ("item.drop.instance.v1|%d|%s" % [instance.item_id, key]).sha256_text().to_lower()
\t\t\t\t\tassert(str(instance.drop_key_digest) == digest, "native affix seed input drift")
\t\t\t\t\tt6_item_identity_inputs.append({"sequence": death.sequence, "item_index": item_index,
\t\t\t\t\t\t"item_id": instance.item_id, "stable_key": key, "digest": digest,
\t\t\t\t\t\t"instance_id": instance.instance_id, "modifiers": instance.modifiers.duplicate(true)})
\t\t\t\titem_index += 1
\t\treturn completed
'''
assert s.count(old)==1
s=s.replace(old,new)
s=s.replace('\tgame.name = "GameRoot"','\tgame._drop_instance_session_key = SeededGameRoot.DROP_SESSION\n\tgame.name = "GameRoot"')
s=s.replace('all_gameplay_actors_spawn_casts_production_hot.v4','all_gameplay_actors_spawn_casts_drop_identities_production_hot.v5')
s=s.replace('\t\t"canonical_cast_inputs": game.t6_cast_seed_inputs.duplicate(true),','\t\t"drop_session": SeededGameRoot.DROP_SESSION,\n\t\t"death_identity_inputs": game.t6_death_identity_inputs.duplicate(true),\n\t\t"equipment_identity_inputs": game.t6_item_identity_inputs.duplicate(true),\n\t\t"canonical_cast_inputs": game.t6_cast_seed_inputs.duplicate(true),')
s=s.replace('\tvar result := {"mode": mode,','\tif mode == "aoe_death_loot":\n\t\t_check(game.t6_death_identity_inputs.size() == death_signals, "death_identity_input_missing")\n\t\t_check(not game.t6_item_identity_inputs.is_empty(), "no_real_equipment_affix_work")\n\tvar result := {"mode": mode,')
p.write_text(s,encoding='utf-8',newline='\n')
(base/p.relative_to(root)).write_bytes(p.read_bytes())
# Explicit test overlay only; BASE production remains unchanged.
r=root/'tools/run_monster_r4_t6_pairs.ps1'
t=r.read_text(encoding='utf-8-sig').replace('all_gameplay_actors_spawn_casts_production_hot.v4','all_gameplay_actors_spawn_casts_drop_identities_production_hot.v5')
t=t.replace('All production dispatch and physics inherited; no BASE production modification.','Native death callback and planning inherited; test-only QUEUED identity input pinned before all persistence/affix consumers. All production dispatch/physics inherited; no BASE production modification.')
needle="    $expectedCasts=if ($Mode -eq 'large_pets')"
assert needle in t
t=t.replace(needle,"""    if ($data.random_inputs.drop_session -ne '20260927000000000000000000000000') {throw 'Drop session input not pinned'}
    if ($Mode -eq 'aoe_death_loot') {
        $deathInputs=@($data.random_inputs.death_identity_inputs)
        if ($deathInputs.Count -ne $data.death_signals -or @($deathInputs.fixed_key | Sort-Object -Unique).Count -ne $deathInputs.Count -or @($data.random_inputs.equipment_identity_inputs).Count -eq 0) {throw 'Death/affix identity input incomplete'}
    }
"""+needle)
r.write_text(t,encoding='utf-8',newline='\n')
fixtures=[]
for p in sorted((root/'tests/runner_fixtures').glob('*.tscn')):
    b=p.read_bytes()
    if b.startswith(b'\xef\xbb\xbf'):
        p.write_bytes(b[3:])
        fixtures.append({'path':p.relative_to(root).as_posix(),'before_sha256':hashlib.sha256(b).hexdigest(),'after_sha256':hashlib.sha256(b[3:]).hexdigest(),'change':'remove UTF8 BOM only'})
(root/'tests/runner_fixtures/.gdignore').write_bytes(b'')
(root/'docs/monster_combat_r4/sol_takeover/evidence/runner_fixture_bom_repair.json').write_text(json.dumps({'status':'NOT_RUN','files':fixtures,'import_exclusion':'intentional failure fixtures are loaded explicitly by runner self-test; editor should not pre-import them'},indent=2),encoding='utf-8')
print('Applied test-only input overlay and fixture encoding/import exclusions. Tests NOT_RUN.')
