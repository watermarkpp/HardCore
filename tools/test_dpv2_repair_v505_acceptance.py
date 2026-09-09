#!/usr/bin/env python3
"""Negative / unit tests for dpv2_repair_v505_acceptance.run_acceptance.

Author review R01-R04 require: correct fixtures PASS, malformed fixtures must be
REJECTED, sorting/distribution assertions must match exactly. All fixtures are
in-memory; no production data is touched.
"""
from __future__ import annotations
import json
import sys
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS))
from dpv2_repair_v505_acceptance import run_acceptance  # noqa: E402

VERIFIED = 'VERIFIED_21CQ_PROFILE_V505'
COMMIT = 'test-data-commit'
TOOL = 'test-tool-sha'
SHAS = {'fixture': {'path': 'fixture', 'sha256': 'FIXTURE'}}

POLICY = {
    'test_seed': 7,
    'book_ids': [920001, 920002],
    'explicit_high_book_ids': [920002],
    'armor_targets': [
        {'monster_id': 5, 'slot_uid': 'dpv2.direct.m5.slot_001',
         'source_item_id': 140, 'output_item_id': 140},
    ],
}
CLASSIFICATION = [{'canonical_item_id': i, 'classification': 'EQUIPMENT'}
                  for i in (101, 102, 103, 104, 105, 106, 107, 108, 140)]
CATALOG = [{'monster_id': m, 'classification': 'elite' if m == 4 else ('boss' if m == 5 else 'ordinary')}
           for m in range(1, 8)]
AUTHORITY = [{'canonical_monster_id': m, 'source_status': 'FULL_21CQ_VERIFIED'}
             for m in range(1, 7)] + [
    {'canonical_monster_id': 7, 'source_status': 'EXPLICIT_NON_LOOT'}]


def slot(uid, mid, item, n, d, rule='NONE', origin=VERIFIED):
    return {
        'slot_uid': uid, 'canonical_monster_id': mid, 'canonical_item_id': item,
        'base_numerator': n, 'base_denominator': d,
        'effective_numerator': n, 'effective_denominator': d,
        'protected_drop': False, 'overflow_priority': 100,
        'baseline_origin': origin, 'reward_kind': 'ITEM',
        'repair_v5_rule': rule,
    }


def make_fixture():
    profiles = [
        {'canonical_monster_id': 1, 'drop_enabled': True, 'baseline_origin': VERIFIED,
         'slots': [slot('dpv2.direct.m1.slot_001', 1, 101, 1, 1),
                   slot('dpv2.direct.m1.slot_002', 1, 102, 1, 1)]},
        {'canonical_monster_id': 2, 'drop_enabled': True, 'baseline_origin': VERIFIED,
         'slots': [slot('dpv2.direct.m2.slot_001', 2, 103, 1, 1),
                   slot('dpv2.direct.m2.slot_002', 2, 104, 1, 2)]},
        {'canonical_monster_id': 3, 'drop_enabled': True, 'baseline_origin': VERIFIED,
         'slots': [slot('dpv2.direct.m3.slot_001', 3, 105, 1, 1),
                   slot('dpv2.direct.m3.slot_002', 3, 106, 1, 6000)]},
        {'canonical_monster_id': 4, 'drop_enabled': True, 'baseline_origin': VERIFIED,
         'slots': [slot('dpv2.direct.m4.slot_001', 4, 920001, 1, 2, 'BOOK_ELITE_BOSS'),
                   slot('dpv2.direct.m4.slot_002', 4, 107, 1, 1)]},
        {'canonical_monster_id': 5, 'drop_enabled': True, 'baseline_origin': VERIFIED,
         'slots': [slot('dpv2.direct.m5.slot_001', 5, 140, 1, 60, 'ARMOR_BASE_1_OVER_60'),
                   slot('dpv2.direct.m5.slot_002', 5, 108, 1, 1)]},
        {'canonical_monster_id': 6, 'drop_enabled': True, 'baseline_origin': VERIFIED,
         'slots': [slot('dpv2.direct.m6.slot_001', 6, 920001, 1, 2, 'BOOK_ORDINARY')]},
        {'canonical_monster_id': 7, 'drop_enabled': False, 'baseline_origin': VERIFIED, 'slots': []},
    ]
    eff = [s for p in profiles if p['drop_enabled'] for s in p['slots']]
    return {'effective': eff, 'baseline': profiles}


def run(effective, baseline, classification=None, ftm=None, **kw):
    return run_acceptance(
        effective_records=effective,
        classification_records=classification if classification is not None else CLASSIFICATION,
        authority_records=AUTHORITY,
        policy_data=POLICY,
        catalog_entries=CATALOG,
        baseline_profiles=baseline,
        data_commit=COMMIT,
        tool_sha256=TOOL,
        input_shas=SHAS,
        generator_head='test-head',
        trials_high=10000,
        trials_low=3000,
        expected_female_to_male=ftm if ftm is not None else {(5, 140): 140},
        **kw,
    )


def with_competitors(fx, priority):
    """Add 9 always-hit competitor slots to monster 5 (armor target) at the
    given overflow_priority, in both baseline and effective."""
    profs = [dict(p, slots=list(p['slots'])) for p in fx['baseline']]
    eff = [dict(r) for r in fx['effective']]
    for i in range(1, 10):
        uid = 'dpv2.direct.m5.comp_%02d' % i
        base = {'slot_uid': uid, 'canonical_item_id': 200 + i,
                'base_numerator': 1, 'base_denominator': 1, 'baseline_origin': VERIFIED}
        profs[4]['slots'].append(base)  # monster 5 is index 4
        eff.append({'slot_uid': uid, 'canonical_monster_id': 5,
                    'canonical_item_id': 200 + i,
                    'base_numerator': 1, 'base_denominator': 1,
                    'effective_numerator': 1, 'effective_denominator': 1,
                    'protected_drop': False, 'overflow_priority': priority,
                    'baseline_origin': VERIFIED, 'reward_kind': 'ITEM',
                    'repair_v5_rule': 'NONE'})
    return {'effective': eff, 'baseline': profs}


def has_any(result, *needles):
    joined = '|'.join(result['failures'])
    return any(n in joined for n in needles)


def main():
    failures_total = 0
    fx = make_fixture()

    # 1) correct fixture must PASS
    res, code = run(fx['effective'], fx['baseline'])
    print('T01 correct: code=%d failures=%d' % (code, len(res['failures'])))
    failures_total += 0 if code == 0 and not res['failures'] else 1
    if res['failures']:
        print('   unexpected:', res['failures'][:6])

    # R01 pollution: monster 6 (BOOK_ORDINARY sharing item 920001 with elite
    # monster 4) must have elite dist exactly {0: trials}
    m6 = res['monsters']['6']
    ok6 = m6['book_elite_boss_slots'] == 0 and m6['book_per_kill_elite_boss_dist'] == {0: m6['trials']}
    print('T02 R01 pollution guard: elite_slots=%d dist=%s ok=%s' % (
        m6['book_elite_boss_slots'], m6['book_per_kill_elite_boss_dist'], ok6))
    failures_total += 0 if ok6 else 1

    # R04 numeric sort: monster 3 has 1/1 and 1/6000 (draw after modifier);
    # numeric desc must put the bigger fraction first, regardless of string form.
    tops = res['monsters']['3']['reward_summary']['top_slots_by_draw_probability']
    ok4 = (tops[0]['slot_uid'] == 'dpv2.direct.m3.slot_001'
           and tops[0]['draw_probability'] > tops[1]['draw_probability']
           and tops[0]['draw_probability'] == 1 / 3.0)  # (1/1)/3 for ordinary equipment
    print('T03 R04 numeric sort: first=%s p=%s ok=%s' % (tops[0]['slot_uid'], tops[0]['draw_probability'], ok4))
    failures_total += 0 if ok4 else 1

    # 2) R02 wrong cloth probability 1/60 -> 1/61
    bad = [dict(r) for r in fx['effective']]
    for r in bad:
        if r['slot_uid'] == 'dpv2.direct.m5.slot_001':
            r['effective_numerator'], r['effective_denominator'] = 1, 61
    res, code = run(bad, fx['baseline'])
    ok = code == 1 and has_any(res, 'ARMOR_TARGET_NOT_EXACT_1_OVER_60')
    print('T04 R02 wrong prob 1/61: code=%d caught=%s' % (code, ok))
    failures_total += 0 if ok else 1

    # 3) R02 wrong cloth item id 140 -> 206
    bad = [dict(r) for r in fx['effective']]
    for r in bad:
        if r['slot_uid'] == 'dpv2.direct.m5.slot_001':
            r['canonical_item_id'] = 206
    res, code = run(bad, fx['baseline'])
    ok = code == 1 and has_any(res, 'ARMOR_TARGET_NOT_UNIQUE', 'UID_ITEM_MISMATCH')
    print('T05 R02 wrong item id: code=%d caught=%s' % (code, ok))
    failures_total += 0 if ok else 1

    # 4) R02 missing target (remove armor row)
    bad = [r for r in fx['effective'] if r['slot_uid'] != 'dpv2.direct.m5.slot_001']
    res, code = run(bad, fx['baseline'])
    ok = code == 1 and has_any(res, 'ARMOR_TARGET_NOT_UNIQUE', 'COVERAGE_SLOT_SET_MISMATCH')
    print('T06 R02 missing target: code=%d caught=%s' % (code, ok))
    failures_total += 0 if ok else 1

    # 5) R02 duplicate target (second armor row for m5 item 140)
    dup = [dict(r) for r in fx['effective']]
    extra = slot('dpv2.direct.m5.slot_003', 5, 140, 1, 60, 'ARMOR_BASE_1_OVER_60')
    dup.append(extra)
    res, code = run(dup, fx['baseline'])
    ok = code == 1 and has_any(res, 'ARMOR_TARGET_NOT_UNIQUE', 'UID_NOT_IN_BASELINE')
    print('T07 R02 duplicate target: code=%d caught=%s' % (code, ok))
    failures_total += 0 if ok else 1

    # 6) R03 missing monster (remove monster 3 from effective)
    bad = [r for r in fx['effective'] if r['canonical_monster_id'] != 3]
    res, code = run(bad, fx['baseline'])
    ok = code == 1 and has_any(res, 'COVERAGE_IDENTITY_SET_MISMATCH', 'COVERAGE_SLOT_SET_MISMATCH')
    print('T08 R03 missing monster: code=%d caught=%s' % (code, ok))
    failures_total += 0 if ok else 1

    # 7) R03 missing slot (remove m2.slot_002)
    bad = [r for r in fx['effective'] if r['slot_uid'] != 'dpv2.direct.m2.slot_002']
    res, code = run(bad, fx['baseline'])
    ok = code == 1 and has_any(res, 'COVERAGE_SLOT_SET_MISMATCH', 'COVERAGE_MISSING_SLOT')
    print('T09 R03 missing slot: code=%d caught=%s' % (code, ok))
    failures_total += 0 if ok else 1

    # R02 retention (author 3rd review): a 1/60 target that is squeezed out by
    # 9 higher/equal-priority competitors must be REJECTED, not PASS.
    comp_class = CLASSIFICATION + [{'canonical_item_id': 200 + i, 'classification': 'EQUIPMENT'}
                                   for i in range(1, 10)]

    # T10: 9 higher-priority competitors -> target drawn but never retained
    fx10 = with_competitors(fx, 200)
    res, code = run(fx10['effective'], fx10['baseline'], classification=comp_class)
    ok = code == 1 and has_any(res, 'ARMOR_TARGET_NOT_ALWAYS_RETAINED', 'ARMOR_TARGET_RETENTION_LOSS')
    print('T10 R02 9 higher-priority competitors: code=%d caught=%s' % (code, ok))
    failures_total += 0 if ok else 1

    # T11: 9 same-priority competitors -> partial retention loss must fail
    fx11 = with_competitors(fx, 100)
    res, code = run(fx11['effective'], fx11['baseline'], classification=comp_class)
    ok = code == 1 and has_any(res, 'ARMOR_TARGET_RETENTION_LOSS')
    print('T11 R02 9 same-priority competitors: code=%d caught=%s' % (code, ok))
    failures_total += 0 if ok else 1

    # T12: 9 lower-priority competitors -> target always retained, PASS
    fx12 = with_competitors(fx, 50)
    res, code = run(fx12['effective'], fx12['baseline'], classification=comp_class)
    ok = code == 0 and not res['failures']
    print('T12 R02 9 lower-priority competitors: code=%d failures=%d ok=%s' % (
        code, len(res['failures']), ok))
    failures_total += 0 if ok else 1

    # T13: unexpected female-to-male output mapping must fail
    res, code = run(fx['effective'], fx['baseline'], ftm={(5, 140): 206})
    ok = code == 1 and has_any(res, 'ARMOR_OUTPUT_MAPPING_UNEXPECTED', 'ARMOR_OUTPUT_MAPPING_COUNT')
    print('T13 R02 unexpected output mapping: code=%d caught=%s' % (code, ok))
    failures_total += 0 if ok else 1

    print('TOTAL_FAILURES=%d' % failures_total)
    return 1 if failures_total else 0


if __name__ == '__main__':
    raise SystemExit(main())
