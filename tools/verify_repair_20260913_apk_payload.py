import hashlib, json, pathlib, subprocess, zipfile

root = pathlib.Path(__file__).resolve().parents[1]
apk = pathlib.Path('C:/Users/Administrator/Desktop/HardCore-20260913-r4-ui-jp-debug.apk')
baseline = pathlib.Path('C:/Users/Administrator/Desktop/HardCore-20260913-repair-v76.apk')
commit = '59014144bd2730d39644db7853f479b94c5cebe7'
tested = '275e570b6a8b9b3aac53bd3f3f6b2478837b0945'
assert not subprocess.check_output(['git','-C',str(root),'diff','--name-only',tested,commit,'--','scripts','assets','tests']).strip()

def digest(data):
    return hashlib.sha256(data).hexdigest()

def json_bytes(data):
    return json.loads(data.rstrip(b'\x00').decode('utf-8-sig'))

with zipfile.ZipFile(apk) as current, zipfile.ZipFile(baseline) as old:
    build = json_bytes(current.read('assets/assets/generated/build_info.json'))
    assert build['git_head'] == commit and build['git_dirty'] is False
    assert build['version_code'] == 77 and build['version_name'] == '1.23.2-r4-ui-jp-20260913'
    critical = ['item_attribute_help','item_drop_affix_v3_rules','warehouse_prepared_transaction',
                'shop_panel','item_detail_presenter','item_detail_docked_presenter','player_state',
                'game_data','player','enemy','combat_resolution_rules']
    scripts = []
    for name in critical:
        entry = 'assets/scripts/' + name + '.gdc'
        blob = current.read(entry)
        assert blob, entry
        changed = entry not in old.namelist() or digest(blob) != digest(old.read(entry))
        assert changed, entry + ' unexpectedly equals the previous v76 package'
        scripts.append(dict(entry=entry,sha256=digest(blob),changed_from_v76=changed))
    # XP policy is in PlayerState. ProfessionRules is deliberately unchanged.
    old_commit = json_bytes(old.read('assets/assets/generated/build_info.json'))['git_head']
    assert subprocess.check_output(['git','-C',str(root),'show',old_commit+':scripts/profession_rules.gd']) == subprocess.check_output(['git','-C',str(root),'show',commit+':scripts/profession_rules.gd'])
    assert current.read('assets/scripts/profession_rules.gdc') == old.read('assets/scripts/profession_rules.gdc')
    assert b'GAMEPLAY_EXPERIENCE_CURRENT_THRESHOLD_RATIO := 0.70' in subprocess.check_output(['git','-C',str(root),'show',commit+':scripts/player_state.gd'])
    rules_entry = 'assets/assets/data/item_drop_affix_rules_v3.json'
    rules = json_bytes(current.read(rules_entry))
    source_rules = json_bytes(subprocess.check_output(['git','-C',str(root),'show',commit+':assets/data/item_drop_affix_rules_v3.json']))
    assert rules == source_rules and len(rules['records']) == 175
    frozen = []
    for path in ['equipment_attribute_master.json','ui/manual_layout_overrides.json','ui/item_name_rarity_v1.json',
                 'runtime/canonical_monster_catalog.json','vanilla_176/skills.json']:
        entry = 'assets/assets/data/' + path
        assert current.read(entry) == old.read(entry), entry
        frozen.append(dict(entry=entry,sha256=digest(current.read(entry))))
    assert not any(n.startswith(('assets/tests/','assets/docs/')) for n in current.namelist())
    report = dict(status='PASS',apk=str(apk),size_bytes=apk.stat().st_size,sha256=digest(apk.read_bytes()),
                  build_info=build,source_test_commit=tested,runtime_code_data_tests_identical_to_tested_commit=True,
                  critical_scripts=scripts,rules_count=175,rules_sha256=digest(current.read(rules_entry)),
                  frozen_against_v76=frozen,excluded_test_fixtures='PASS',device='NOT_RUN: no connected Android device')
(root/'outputs/test_logs/r4_apk_payload_verification.json').write_text(json.dumps(report,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
print(json.dumps({k:report[k] for k in ['status','size_bytes','sha256','rules_count']},ensure_ascii=False))
