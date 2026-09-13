"""Read-only full-table audit; optional report writes stay outside production data."""
import argparse
from collections import Counter
from fractions import Fraction
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
DROP = 'assets/data/drop/'


def read(path):
    return json.loads((ROOT / path).read_text(encoding='utf-8-sig'))


def sha(path, lf=False):
    data = (ROOT / path).read_bytes()
    if lf:
        data = data.replace(b'\r\n', b'\n').replace(b'\r', b'\n')
    return hashlib.sha256(data).hexdigest().upper()


def audit():
    errors, notes = [], []
    def check(ok, code, evidence):
        if not ok:
            errors.append({'code': code, 'evidence': evidence})
    def unique(rows, key, label):
        counts = Counter(r[key] for r in rows)
        check(all(v == 1 for v in counts.values()), 'duplicate_' + label, {str(k): v for k, v in counts.items() if v != 1})
        return {r[key]: r for r in rows}

    baseline = read(DROP + 'dpv2_direct_baseline_v2.json')
    authority = read(DROP + 'dpv2_single_player_drop_boost_v1.json')
    effective = read(DROP + 'dpv2_single_player_effective_probability_v1.json')
    manifest = read(DROP + 'dpv2_direct_baseline_manifest_v2.json')
    source = read(DROP + 'dpv2_21cq_verified_profile_authority_v1.json')
    legacy = read('assets/data/canonical_monster_drop_source_v2.json')
    classes = unique(read(DROP + 'dpv2_single_player_item_boost_classification_v1.json')['records'], 'canonical_item_id', 'item_classification')
    monsters = unique(read('assets/data/runtime/canonical_monster_catalog.json')['entries'], 'monster_id', 'monster_catalog')
    profiles = unique(baseline['profiles'], 'canonical_monster_id', 'profiles')
    unique([p for p in baseline['profiles'] if p['drop_enabled']], 'drop_profile_id', 'profile_names')
    source_profiles = unique(source['records'], 'canonical_monster_id', 'source_profiles')
    provenance = unique(read(DROP + 'dpv2_21cq_source_provenance_v1.json')['records'], 'compiled_slot_uid', 'provenance')
    slots = [dict(s, canonical_monster_id=p['canonical_monster_id']) for p in baseline['profiles'] for s in p['slots']]
    by_uid = unique(slots, 'slot_uid', 'slots')
    ledger = unique(effective['records'], 'slot_uid', 'effective')
    check(set(by_uid) == set(ledger) == set(provenance), 'uid_sets', {'slots': len(by_uid), 'ledger': len(ledger), 'provenance': len(provenance)})
    check(set(profiles) == set(monsters) == set(source_profiles), 'profile_sets', list(set(profiles) ^ set(monsters)))
    check(len(slots) == baseline['summary']['compiled_slots'] == 7611, 'slot_count', len(slots))
    check(len(legacy['records']) == 217 and sum(len(r['rows']) for r in legacy['records']) == 9590, 'logical_source_census', '217/9590')

    hashes = []
    for name, binding in manifest['artifacts'].items():
        path = binding['path']
        actual = sha(path, binding.get('hash_normalization') == 'lf_text')
        hashes.append({'path': path, 'actual': actual, 'expected': binding['sha256']})
        check(actual == binding['sha256'], 'manifest_hash', path)
    tracked = manifest['tracked_logical_source']
    check(sha(tracked['path']) == tracked['sha256_raw'], 'logical_source_hash', tracked['path'])
    for row in source['records']:
        capture = row.get('source_evidence', row)
        if capture.get('raw_path') and capture.get('raw_sha256'):
            check((ROOT / capture['raw_path']).is_file() and sha(capture['raw_path']) == capture['raw_sha256'], 'source_capture_hash', row['canonical_monster_id'])
    migration = json.loads(subprocess.check_output(['git', 'show', source['migration_base_sha'] + ':' + DROP + 'dpv2_direct_baseline_v2.json'], cwd=ROOT))
    migration_profiles = {p['canonical_monster_id']: p for p in migration['profiles']}

    contract = effective['repair_v5_contract']
    check(contract == authority['repair_v5_contract'], 'repair_contract_parity', 'authority/effective')
    exclusion = {r['canonical_monster_id'] for r in authority['manual_boss_exclusions']}
    rules = Counter()
    potions = []
    for s in slots:
        uid, mid = s['slot_uid'], s['canonical_monster_id']
        r, prov = ledger[uid], provenance[uid]
        for field in ['canonical_monster_id', 'canonical_item_id', 'gold_amount', 'base_numerator', 'base_denominator', 'protected_drop', 'overflow_priority', 'source_provenance_id', 'baseline_origin']:
            check(s.get(field) == r.get(field), 'ledger_base_drift', [uid, field])
        check(prov['source_monster_id'] == mid and prov['source_provenance_id'] == s['source_provenance_id'], 'provenance_join', uid)
        check(prov['effective_base_numerator'] == s['base_numerator'] and prov['effective_base_denominator'] == s['base_denominator'], 'source_base_probability', uid)
        if source_profiles[mid]['source_status'] == 'FULL_21CQ_VERIFIED':
            check(prov.get('canonical_item_id') == s.get('canonical_item_id') and prov.get('gold_amount') == s.get('gold_amount'), 'source_reward_identity', uid)
        else:
            # These three explicitly retained profiles predate reward fields in
            # provenance. Compare complete slots to their frozen migration source.
            original = next((x for x in migration_profiles[mid]['slots'] if x['slot_uid'] == uid), {})
            check(original == {k: v for k, v in s.items() if k != 'canonical_monster_id'}, 'legacy_source_reward_identity', uid)
        n, d = s['base_numerator'], s['base_denominator']
        if not (isinstance(n, int) and isinstance(d, int) and 0 < n <= d):
            check(False, 'invalid_base_rational', uid)
            continue
        base = Fraction(n, d)
        item = s.get('canonical_item_id')
        check(('gold_amount' in s) != ('canonical_item_id' in s), 'ambiguous_reward', uid)
        check(item is None or item in classes, 'missing_item_id', [uid, item])
        classification = classes.get(item, {}).get('classification')
        policy = ('BYPASS_NEW_ARMOR_BOSS' if mid in exclusion else
                  'BYPASS_GOLD' if item is None else
                  'BYPASS_COMMON_RECOVERY' if classification == 'COMMON_RECOVERY' else
                  'AUTO_BOOST' if classification in ['RARE_FUNCTIONAL_CONSUMABLE', 'EQUIPMENT'] else 'BYPASS_UNCLASSIFIED')
        check(r['boost_policy'] == policy, 'classification_precedence', uid)
        pre = min(base * 25, Fraction(1, 20)) if policy.startswith('AUTO_BOOST') and base < Fraction(1, 20) else base
        check(pre == Fraction(r['repair_v5_pre_numerator'], r['repair_v5_pre_denominator']), 'stage_1_formula', uid)
        expected, rule = pre, 'NONE'
        mc = monsters[mid]['classification']
        if uid in contract['armor_slot_uids']:
            expected, rule = Fraction(1, 60), 'ARMOR_BASE_1_OVER_60'
            check(base == expected and mid in range(235, 241), 'armor_target', uid)
        elif contract['boss_k_enabled'] and uid in contract['boss_allowed_slot_uids']:
            expected = min(pre * Fraction(contract['boss_k_numerator'], contract['boss_k_denominator']), max(pre, Fraction(1, 4)))
            rule = 'BOSS_K'
        elif item in contract['book_item_ids'] and mid in contract['verified_book_monster_ids'] and mid not in range(235, 241) and mc in ['ordinary', 'elite', 'boss']:
            cap, multiplier = (Fraction(1, 100), 5) if mc == 'ordinary' else (Fraction(1, 20), 25)
            expected = min(base * multiplier, cap) if base < cap else base
            rule = 'BOOK_ORDINARY' if mc == 'ordinary' else 'BOOK_ELITE_BOSS'
        check(rule == r['repair_v5_rule'], 'stage_2_rule', uid)
        check(expected == Fraction(r['effective_numerator'], r['effective_denominator']) == Fraction(r['repair_v5_final_numerator'], r['repair_v5_final_denominator']), 'stage_2_formula', uid)
        check(0 < r['effective_numerator'] <= r['effective_denominator'] <= 2147483647, 'invalid_effective_rational', uid)
        rules[rule] += 1
        if classification == 'COMMON_RECOVERY' and mc in ['elite', 'boss']:
            modifier = 2 if item in [920014, 920016] else 1
            potions.append({'uid': uid, 'monster_id': mid, 'monster': monsters[mid]['canonical_name'], 'item_id': item, 'item': classes[item]['canonical_item_name'], 'base': str(base), 'effective': str(expected), 'runtime_draw': str(expected / modifier), 'priority': s['overflow_priority'], 'protected': s['protected_drop']})

    profile_rows = []
    for mid, p in profiles.items():
        src = source_profiles[mid]
        check(p['runtime_allowed'] == monsters[mid]['runtime_allowed'], 'runtime_eligibility', mid)
        check(bool(p['slots']) == p['drop_enabled'], 'disabled_slots', mid)
        expected_count = src['legacy_slot_count'] if mid in [75, 123, 225] else len(src['source_rows'])
        check(len(p['slots']) == expected_count, 'source_profile_count', mid)
        check(p['drop_enabled'] or p['drop_profile_id'] is None, 'disabled_profile_reference', mid)
        profile_rows.append({'id': mid, 'name': p['canonical_monster_name'], 'class': monsters[mid]['classification'], 'slots': len(p['slots']), 'enabled': p['drop_enabled'], 'runtime_allowed': p['runtime_allowed']})

    preserved = []
    preservation = read('docs/repair_20260913/evidence/drop_preservation.json')
    for entry in preservation['files']:
        path = entry['path']
        old = json.loads(subprocess.check_output(['git', 'show', preservation['baseline'] + ':' + path], cwd=ROOT))
        current = read(path)
        left, right = old, current
        keys = entry['unchanged_except'].split('.')
        for key in keys[:-1]:
            left, right = left[key], right[key]
        left.pop(keys[-1], None); right.pop(keys[-1], None)
        check(old == current, 'frozen_drop_data_changed', path)
        preserved.append({'path': path, 'unchanged_except': entry['unchanged_except'], 'equal': old == current})
    check(baseline['probability_policy']['post_rng_ground_slot_limit'] == 15, 'ground_cap', baseline['probability_policy'])
    notes.append('The inactive overflow seed retains cap=9; production GameData reads cap=15 from direct_baseline. Semantic source_accounting retains pre-V505 6809 while migrated baseline has 7611. Both require production-path interpretation, not data replacement.')
    return {'status': 'PASS' if not errors else 'FAIL', 'scope': 'Full static data, exact rational and preservation audit; not device acceptance', 'counts': {'profiles': len(profiles), 'runtime_allowed': sum(p['runtime_allowed'] for p in profiles.values()), 'enabled': sum(p['drop_enabled'] for p in profiles.values()), 'slots': len(slots), 'effective_records': len(ledger), 'provenance_records': len(provenance), 'classes': len(classes), 'elite_boss_potion_slots': len(potions)}, 'rule_counts': dict(rules), 'errors': errors, 'notes': notes, 'hashes': hashes, 'preservation': preserved, 'profiles': profile_rows, 'elite_boss_potions': potions}


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    result = audit()
    if args.report:
        args.report.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    compact = {k: v for k, v in result.items() if k not in ['hashes', 'preservation', 'profiles', 'elite_boss_potions', 'errors']}
    compact['error_counts'] = dict(Counter(e['code'] for e in result['errors']))
    compact['first_errors'] = result['errors'][:20]
    print(json.dumps(compact, ensure_ascii=False, indent=2))
    raise SystemExit(0 if result['status'] == 'PASS' else 1)
