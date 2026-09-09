#!/usr/bin/env python3
"""V505 post-merge acceptance v2: bound, closed-coverage, negative-testable.

Fixes from author review (e0ffd538 -> this revision):
  R01: BOOK_ELITE_BOSS per-kill counts use the CURRENT row's own
       repair_v5_rule, never a global item-id set; 'any book' uses the approved
       policy book_ids; top-grade books use policy explicit_high_book_ids as a
       separate identity set. Invariant: a monster with zero BOOK_ELITE_BOSS
       slots must have elite distribution {0: trials}.
  R02: the six new-cloth targets are locked from policy.armor_targets by
       (monster_id, source_item_id); each target must be unique, UID-bound,
       rule ARMOR_BASE_1_OVER_60, exact 1/60 fraction (no tolerance),
       always_retained with the full candidate set, selected==hits, discarded=0,
       then Monte-Carlo 6-sigma. The found target identity set must EXACTLY
       equal the policy six-target set (no missing, no duplicate, no extra).
  R03: coverage is a hard completeness condition, not a report: expected
       drop-enabled identities and per-identity slot UID sets are taken from the
       independent baseline; effective must match exactly; global slot UIDs are
       unique; every row's canonical_item_id and base fraction must mirror the
       baseline slot by UID; every drop-enabled identity must have an authority
       record (NO_AUTHORITY_ROW -> failure); origin counts must match the
       baseline-derived distribution. Per-slot invariants for ALL slots:
       0 <= selected <= hits <= trials, hits == selected + discarded,
       always_retained -> discarded == 0.
  R04: top_slots sorted numerically by the Fraction actually used in the
       simulation (effective / runtime denominator modifier), with
       effective_probability and observed selected-rate reported separately and
       labelled. No string sorting.

Scope boundary (F04): Python RNG + selection model only; not Godot, not node
spawn, not device/APK.
"""
from __future__ import annotations
from collections import defaultdict, Counter
from fractions import Fraction
import hashlib
import json
import math
import random
import subprocess
import sys
import time
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS))
import dpv2_repair_v5 as v5  # noqa: E402
from dpv2_repair_v5_simulate import select  # noqa: E402

ROOT = TOOLS.parent
DATA = str(ROOT / 'assets' / 'data' / 'drop') + '/'
AUTHORITY = DATA + 'dpv2_21cq_verified_profile_authority_v1.json'
CATALOG = 'assets/data/runtime/canonical_monster_catalog.json'
DATA_COMMIT = '275eef8b9455c7f3ef63daaf59dfff3c06e26069'

ARMOR_RULE = 'ARMOR_BASE_1_OVER_60'

# Approved female-to-male clothing output mapping (author ruling 2026-09-09):
# the draw stays on the source identity (1/60), then the output identity is
# mapped once (loot_runtime_service.gd FEMALE_EQUIPMENT_DROP_OUTPUT_BY_ITEM_ID).
# key: (monster_id, source_item_id) -> output_item_id
FEMALE_TO_MALE_OUTPUT = {
    (235, 140): 140, (236, 144): 144, (237, 142): 142,
    (238, 141): 140, (239, 145): 144, (240, 143): 142,
}


def sha256_of(path: str) -> str:
    h = hashlib.sha256()
    with open(ROOT / path, 'rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest().upper()


def git_head() -> str:
    out = subprocess.run(['git', '-C', str(ROOT), 'rev-parse', 'HEAD'],
                         capture_output=True, text=True, check=True)
    return out.stdout.strip()


def data_matches_commit(paths) -> bool:
    """Return True iff the given repo-relative paths equal DATA_COMMIT."""
    out = subprocess.run(['git', '-C', str(ROOT), 'diff', '--quiet', DATA_COMMIT, '--'] + paths,
                         capture_output=True, text=True)
    return out.returncode == 0


def within(observed: int, expected: float, trials: int) -> bool:
    tolerance = 6 * math.sqrt(expected * (1 - expected) / trials) + 1 / trials
    return abs(observed / trials - expected) <= tolerance


def always_retained_wrapper(row, rows):
    return v5.always_retained(row, rows)


def simulate_monster(rows, classes, equipment, book_item_ids, trials, seed,
                     explicit_high_item_ids=None):
    """Simulate one monster. Returns draws + per-kill distributions.

    Book counting is per-row-rule (R01): elite/boss books are rows whose own
    repair_v5_rule == BOOK_ELITE_BOSS; any-book is canonical_item_id in the
    approved policy book_item_ids; high-grade books are explicit_high_item_ids.
    """
    explicit_high_item_ids = explicit_high_item_ids or set()
    rng = random.Random(seed)
    grouped = defaultdict(list)
    probs = {}
    nd = []
    for i, row in enumerate(rows):
        grouped[v5.rank(row)].append(i)
        m = v5.denominator_modifier(classes[row['canonical_monster_id']],
                                    row.get('canonical_item_id', -1), equipment)
        fraction = Fraction(row['effective_numerator'], row['effective_denominator']) / m
        probs[row['slot_uid']] = fraction
        nd.append((fraction.numerator, fraction.denominator))
    groups = [grouped[k] for k in sorted(grouped, reverse=True)]
    hits = [0] * len(rows)
    selected_counts = [0] * len(rows)
    any_equipment = any_book = protected_discarded = 0
    book_total_dist = defaultdict(int)
    book_elite_dist = defaultdict(int)
    book_high_dist = defaultdict(int)
    for _ in range(trials):
        succeeded = set()
        for i, (n, d) in enumerate(nd):
            if rng.randrange(1, d + 1) <= n:
                hits[i] += 1
                succeeded.add(i)
        selected = select(groups, succeeded, rng)
        for i in selected:
            selected_counts[i] += 1
        any_equipment += int(any(rows[i].get('canonical_item_id') in equipment for i in selected))
        book_hits = [i for i in selected if rows[i].get('canonical_item_id') in book_item_ids]
        elite_hits = [i for i in selected if rows[i].get('repair_v5_rule') == 'BOOK_ELITE_BOSS']
        high_hits = [i for i in selected if rows[i].get('canonical_item_id') in explicit_high_item_ids]
        any_book += int(bool(book_hits))
        book_total_dist[len(book_hits)] += 1
        book_elite_dist[len(elite_hits)] += 1
        book_high_dist[len(high_hits)] += 1
        protected_discarded += sum(rows[i]['protected_drop'] for i in succeeded.difference(selected))
    exact_eq = 1 - v5.no_equipment_after_selection(rows, probs, equipment)
    exact_book = 1 - v5.no_equipment_after_selection(rows, probs, book_item_ids)
    return {
        'hits': hits, 'selected_counts': selected_counts, 'probs': probs,
        'any_equipment_observed': any_equipment / trials,
        'any_equipment_analytic': exact_eq,
        'any_book_observed': any_book / trials,
        'any_book_analytic': exact_book,
        'protected_discarded': protected_discarded,
        'book_total_dist': dict(sorted(book_total_dist.items())),
        'book_elite_dist': dict(sorted(book_elite_dist.items())),
        'book_high_dist': dict(sorted(book_high_dist.items())),
    }


def run_acceptance(effective_records, classification_records, authority_records,
                   policy_data, catalog_entries, baseline_profiles,
                   data_commit, tool_sha256, input_shas, generator_head,
                   trials_high=100000, trials_low=20000, seed_base=None,
                   expected_female_to_male=None):
    """Pure core: no file IO / git beyond the caller's bindings.

    Returns (result_dict, exit_code). exit_code == 1 if any failure.
    """
    failures = []
    seed_base = seed_base if seed_base is not None else policy_data.get('test_seed', 20260907)
    ftm = expected_female_to_male if expected_female_to_male is not None else FEMALE_TO_MALE_OUTPUT
    book_ids = set(policy_data['book_ids'])
    explicit_high_ids = set(policy_data.get('explicit_high_book_ids', []))
    armor_targets = policy_data.get('armor_targets') or []
    classes = {r['monster_id']: r['classification'] for r in catalog_entries}
    equipment = {r['canonical_item_id'] for r in classification_records
                 if r['classification'] == 'EQUIPMENT'}

    # ---- baseline-derived expected sets (R03) ----
    baseline_by_mid = {p['canonical_monster_id']: p for p in baseline_profiles}
    drop_enabled = [p for p in baseline_profiles if p.get('drop_enabled')]
    expected_ids = {p['canonical_monster_id'] for p in drop_enabled}
    expected_slot_uids = {}
    for p in drop_enabled:
        expected_slot_uids[p['canonical_monster_id']] = {s['slot_uid'] for s in p['slots']}
    expected_origin_record_counts = Counter(
        s['baseline_origin'] for p in drop_enabled for s in p['slots'])
    baseline_slot_by_uid = {}
    for p in drop_enabled:
        for s in p['slots']:
            baseline_slot_by_uid[s['slot_uid']] = (p['canonical_monster_id'], s)
    authority_by_mid = {r['canonical_monster_id']: r for r in authority_records}

    # ---- effective grouping (R03) ----
    by_monster = defaultdict(list)
    for r in effective_records:
        by_monster[r['canonical_monster_id']].append(r)
    actual_ids = set(by_monster)
    actual_uid_count = Counter(r['slot_uid'] for r in effective_records)
    actual_origin_record_counts = Counter(r['baseline_origin'] for r in effective_records)

    # completeness conditions (hard failures):
    if actual_ids != expected_ids:
        failures.append('COVERAGE_IDENTITY_SET_MISMATCH:missing=%s extra=%s' % (
            sorted(expected_ids - actual_ids), sorted(actual_ids - expected_ids)))
    for mid in sorted(expected_ids):
        eff_uids = {r['slot_uid'] for r in by_monster[mid]}
        base_uids = expected_slot_uids[mid]
        if eff_uids != base_uids:
            failures.append('COVERAGE_SLOT_SET_MISMATCH:%d:missing=%s extra=%s' % (
                mid, sorted(base_uids - eff_uids), sorted(eff_uids - base_uids)))
        for uid in base_uids - eff_uids:
            failures.append('COVERAGE_MISSING_SLOT:%d:%s' % (mid, uid))
    dup_uids = [u for u, c in actual_uid_count.items() if c > 1]
    if dup_uids:
        failures.append('COVERAGE_DUPLICATE_SLOT_UID:%s' % sorted(dup_uids)[:10])
    if actual_origin_record_counts != expected_origin_record_counts:
        failures.append('ORIGIN_RECORD_COUNTS_MISMATCH:actual=%s expected=%s' % (
            dict(actual_origin_record_counts), dict(expected_origin_record_counts)))
    for mid in sorted(expected_ids):
        if mid not in authority_by_mid:
            failures.append('NO_AUTHORITY_ROW:%d' % mid)
    # per-UID mirror of reward identity + base fraction (R03)
    for r in effective_records:
        base = baseline_slot_by_uid.get(r['slot_uid'])
        if base is None:
            failures.append('UID_NOT_IN_BASELINE:%s' % r['slot_uid'])
            continue
        bmid, bslot = base
        if bmid != r['canonical_monster_id']:
            failures.append('UID_MONSTER_MISMATCH:%s:base=%d eff=%d' % (
                r['slot_uid'], bmid, r['canonical_monster_id']))
        if bslot.get('canonical_item_id') != r.get('canonical_item_id'):
            failures.append('UID_ITEM_MISMATCH:%s:base=%s eff=%s' % (
                r['slot_uid'], bslot.get('canonical_item_id'), r.get('canonical_item_id')))
        if (bslot.get('base_numerator') != r.get('base_numerator')
                or bslot.get('base_denominator') != r.get('base_denominator')):
            failures.append('UID_BASE_FRACTION_MISMATCH:%s' % r['slot_uid'])
    # ledger book labels must stay within the approved book authority (R01)
    for r in effective_records:
        rule = r.get('repair_v5_rule') or ''
        if rule.startswith('BOOK') and r.get('canonical_item_id') not in book_ids:
            failures.append('BOOK_LABEL_OUTSIDE_AUTHORITY:%s:%s' % (
                r['slot_uid'], r.get('canonical_item_id')))

    # ---- R02: six new-cloth targets locked from policy ----
    expected_targets = {}
    for t in armor_targets:
        expected_targets[(t['monster_id'], t['source_item_id'])] = t
    found_targets = {}
    armor_rows = [(r, by_monster[r['canonical_monster_id']])
                  for r in effective_records if r.get('repair_v5_rule') == ARMOR_RULE]
    for (mid, item_id), t in sorted(expected_targets.items()):
        matches = [r for r in by_monster[mid] if r.get('canonical_item_id') == item_id]
        if len(matches) != 1:
            failures.append('ARMOR_TARGET_NOT_UNIQUE:%d:%d:count=%d' % (mid, item_id, len(matches)))
            continue
        row = matches[0]
        if row['slot_uid'] != t['slot_uid']:
            failures.append('ARMOR_TARGET_UID_MISMATCH:%d:expected=%s actual=%s' % (
                mid, t['slot_uid'], row['slot_uid']))
        if row.get('repair_v5_rule') != ARMOR_RULE:
            failures.append('ARMOR_TARGET_RULE_MISMATCH:%d:%s:%s' % (
                mid, row['slot_uid'], row.get('repair_v5_rule')))
        if not (row['effective_numerator'] == 1 and row['effective_denominator'] == 60):
            failures.append('ARMOR_TARGET_NOT_EXACT_1_OVER_60:%d:%s:%d/%d' % (
                mid, row['slot_uid'], row['effective_numerator'], row['effective_denominator']))
        found_targets[(mid, item_id)] = row['slot_uid']
    # extra armor rows not in the policy set -> drift (R02)
    for r, rows in armor_rows:
        if (r['canonical_monster_id'], r.get('canonical_item_id')) not in expected_targets:
            failures.append('ARMOR_EXTRA_TARGET_OUTSIDE_POLICY:%s:%s' % (
                r['slot_uid'], r.get('canonical_item_id')))
    # Approved female-to-male output mapping (author ruling 2026-09-09): the
    # draw stays on the source identity at 1/60, then the output identity is
    # mapped once. Validate the exact pairs; unexpected pairs FAIL.
    armor_output_mapping = []
    for t in armor_targets:
        expected_out = ftm.get((t['monster_id'], t['source_item_id']))
        if expected_out is None or t['output_item_id'] != expected_out:
            failures.append('ARMOR_OUTPUT_MAPPING_UNEXPECTED:%d:source=%d:output=%d:expected=%s' % (
                t['monster_id'], t['source_item_id'], t['output_item_id'], expected_out))
        armor_output_mapping.append({
            'monster_id': t['monster_id'], 'source_item_id': t['source_item_id'],
            'output_item_id': t['output_item_id'], 'expected_female_to_male': expected_out,
        })
    # Also require the mapping table to be exactly the approved pairs.
    if len(armor_output_mapping) != len(ftm):
        failures.append('ARMOR_OUTPUT_MAPPING_COUNT:%d!=%d' % (
            len(armor_output_mapping), len(ftm)))

    # ---- simulate all monsters ----
    high_risk = set([76, 198, 199, 225]) | set(range(235, 241))
    high_risk |= {t['monster_id'] for t in armor_targets}
    high_risk |= {mid for mid in by_monster
                  if any(r.get('repair_v5_rule', '').startswith('BOOK') for r in by_monster[mid])}
    high_risk |= {75, 123}
    trials_map = {mid: (trials_high if mid in high_risk else trials_low) for mid in by_monster}
    monsters_out = {}
    started = time.perf_counter()
    for mid in sorted(by_monster):
        rows = by_monster[mid]
        trials = trials_map[mid]
        data = simulate_monster(rows, classes, equipment, book_ids, trials,
                                seed_base + mid, explicit_high_item_ids=explicit_high_ids)
        status = authority_by_mid[mid]['source_status'] if mid in authority_by_mid else 'NO_AUTHORITY_ROW'
        origins = Counter(r['baseline_origin'] for r in rows)
        n_elite_slots = sum(1 for r in rows if r.get('repair_v5_rule') == 'BOOK_ELITE_BOSS')
        n_book_slots = sum(1 for r in rows if r.get('canonical_item_id') in book_ids)
        entry = {
            'trials': trials,
            'slots': len(rows),
            'source_status': status,
            'origin_groups': dict(origins),
            'any_equipment_observed': data['any_equipment_observed'],
            'any_equipment_analytic': data['any_equipment_analytic'],
            'any_book_observed': data['any_book_observed'],
            'any_book_analytic': data['any_book_analytic'],
            'protected_discarded': data['protected_discarded'],
            'book_slots': n_book_slots,
            'book_elite_boss_slots': n_elite_slots,
        }
        reward_kinds = Counter(r['reward_kind'] for r in rows)
        entry['reward_summary'] = {
            'slots_by_reward_kind': dict(reward_kinds),
            'equipment_slots': sum(1 for r in rows if r.get('canonical_item_id') in equipment),
            'top_slots_by_draw_probability': sorted(
                [{'item_id': r.get('canonical_item_id'), 'slot_uid': r['slot_uid'],
                  'draw_probability': float(Fraction(r['effective_numerator'], r['effective_denominator'])
                                            / v5.denominator_modifier(classes[mid],
                                                                      r.get('canonical_item_id', -1), equipment)),
                  'effective_probability': '%d/%d' % (r['effective_numerator'], r['effective_denominator']),
                  'rule': r['repair_v5_rule']} for r in rows],
                key=lambda x: x['draw_probability'], reverse=True)[:6],
        }
        # per-kill distributions
        if n_book_slots:
            entry['book_per_kill_total_dist'] = data['book_total_dist']
        else:
            entry['book_per_kill_total_dist'] = {0: trials}
        if n_elite_slots:
            entry['book_per_kill_elite_boss_dist'] = data['book_elite_dist']
        else:
            entry['book_per_kill_elite_boss_dist'] = {0: trials}
        if explicit_high_ids:
            entry['book_per_kill_explicit_high_dist'] = data['book_high_dist']
        # R01 invariant: zero elite slots -> elite dist exactly {0: trials}
        if n_elite_slots == 0 and data['book_elite_dist'] != {0: trials}:
            failures.append('BOOK_ELITE_DIST_POLLUTION:%d' % mid)
        # per-slot details + invariants (R03)
        details = []
        for i, row in enumerate(rows):
            prob = float(data['probs'][row['slot_uid']])
            hits_i, sel_i = data['hits'][i], data['selected_counts'][i]
            disc = hits_i - sel_i
            if not (0 <= sel_i <= hits_i <= trials):
                failures.append('SLOT_INVARIANT_ORDER:%d:%s' % (mid, row['slot_uid']))
            if disc < 0:
                failures.append('SLOT_INVARIANT_DISCARD:%d:%s' % (mid, row['slot_uid']))
            ar = always_retained_wrapper(row, rows)
            if ar and disc != 0:
                failures.append('ALWAYS_RETAINED_DISCARDED:%d:%s' % (mid, row['slot_uid']))
            if not within(hits_i, prob, trials):
                failures.append('%d:hit_rate:%s' % (mid, row['slot_uid']))
            if mid in high_risk:
                details.append({
                    'slot_uid': row['slot_uid'], 'item_id': row.get('canonical_item_id'),
                    'roll_probability': str(data['probs'][row['slot_uid']]),
                    'hits': hits_i, 'selected': sel_i, 'discarded': disc,
                    'always_retained': ar, 'origin': row['baseline_origin'], 'rule': row['repair_v5_rule'],
                })
        if mid in high_risk:
            entry['per_slot'] = details
        if not within(data['any_equipment_observed'] * trials, data['any_equipment_analytic'], trials):
            failures.append('%d:any_equipment_6_sigma' % mid)
        if not within(data['any_book_observed'] * trials, data['any_book_analytic'], trials):
            failures.append('%d:any_book_6_sigma' % mid)
        monsters_out[str(mid)] = entry

    # ---- R02 new-clothes boundary (draw + retention + Monte-Carlo stage) ----
    new_clothes = []
    for (mid, item_id), t in sorted(expected_targets.items()):
        if (mid, item_id) not in found_targets:
            continue  # already failed above
        uid = found_targets[(mid, item_id)]
        rows = by_monster[mid]
        idx = next(i for i, r in enumerate(rows) if r['slot_uid'] == uid)
        row = rows[idx]
        trials = trials_map[mid]
        det = monsters_out[str(mid)]['per_slot'][idx]
        obs = det['hits']
        draw = (Fraction(row['effective_numerator'], row['effective_denominator'])
                / v5.denominator_modifier(classes[mid], row.get('canonical_item_id', -1), equipment))
        if draw != Fraction(1, 60):
            failures.append('ARMOR_TARGET_DRAW_NOT_1_OVER_60:%d:%s:%s' % (mid, uid, draw))
        exp = trials * float(draw)
        sigma = abs(obs - exp) / math.sqrt(exp * (1 - float(draw)))
        # Author R02 (3rd review): the target MUST be always-retained and its
        # retention must be loss-free. A 1/60 draw that is then squeezed out by
        # 9 equal-or-higher competitors is a REJECTED input, not a pass.
        if not det['always_retained']:
            failures.append('ARMOR_TARGET_NOT_ALWAYS_RETAINED:%d:%s' % (mid, uid))
        if det['selected'] != obs or det['discarded'] != 0:
            failures.append('ARMOR_TARGET_RETENTION_LOSS:%d:%s:hits=%d:selected=%d:discarded=%d' % (
                mid, uid, obs, det['selected'], det['discarded']))
        entry = {
            'monster_id': mid, 'item_id': item_id, 'slot_uid': uid,
            'policy_output_item_id': t['output_item_id'],
            'rule': ARMOR_RULE,
            'draw_probability': str(draw),
            'expected_hits': exp, 'observed_hits': obs,
            'deviation_sigma': sigma, 'within_6_sigma': sigma <= 6.0,
            'always_retained': det['always_retained'],
            'selected_eq_hits': det['selected'] == obs,
            'discarded': det['discarded'],
        }
        new_clothes.append(entry)
        if sigma > 6.0:
            failures.append('NEW_CLOTHES_SIGMA:%d:%s' % (mid, uid))

    elapsed = time.perf_counter() - started
    status_counts = Counter(authority_by_mid.get(m, {}).get('source_status', 'NO_AUTHORITY_ROW')
                            for m in expected_ids)
    result = {
        'schema': 'hardcore.dpv2.v505.acceptance_run.v2',
        'data_commit': data_commit,
        'generator_head': generator_head,
        'tool_sha256': tool_sha256,
        'generated_at': time.strftime('%Y-%m-%dT%H:%M:%S%z'),
        'scope': 'PYTHON_RNG_SELECTION_MODEL_NOT_GODOT_NOT_NODE_SPAWN_NOT_DEVICE',
        'inputs': input_shas,
        'selector': {'protected_first': True, 'same_group_priority_desc': True, 'cap': 9,
                     'rng': 'inclusive_integer_randrange_1_to_d', 'python_mirror_of_runtime_contract': True},
        'trials_policy': {'high_risk': trials_high, 'other': trials_low},
        'coverage': {
            'expected_drop_enabled_ids': len(expected_ids),
            'actual_distinct_ids': len(actual_ids),
            'identity_set_closed': actual_ids == expected_ids,
            'slot_uid_closed': all(actual_uid_count[u] == 1 for u in actual_uid_count),
            'origin_record_counts': dict(actual_origin_record_counts),
            'expected_origin_record_counts': dict(expected_origin_record_counts),
            'drop_enabled_source_status_counts': dict(status_counts),
        },
        'armor_targets_found': {('%d:%d' % k): v for k, v in found_targets.items()},
        'armor_output_mapping': armor_output_mapping,
        'monsters': monsters_out,
        'new_clothes_boundary': new_clothes,
        'elapsed_seconds': elapsed,
        'failures': failures,
    }
    return result, (1 if failures else 0)


def main() -> int:
    head = git_head()
    tool_sha = sha256_of('tools/dpv2_repair_v505_acceptance.py')
    p = v5.policy()
    effective = v5.read(v5.EFFECTIVE)
    classification = v5.unchanged_json(v5.CLASSIFICATION)['records']
    authority = v5.read(AUTHORITY)['records']
    baseline = v5.read(v5.BASELINE)
    catalog = v5.unchanged_json(CATALOG)['entries']
    data_paths = [v5.EFFECTIVE, v5.CLASSIFICATION, AUTHORITY, v5.BASELINE, v5.POLICY, CATALOG]
    if not data_matches_commit(data_paths):
        raise SystemExit('DATA_MISMATCH_FROM_%s' % DATA_COMMIT)
    input_shas = {
        'effective': {'path': v5.EFFECTIVE, 'sha256': sha256_of(v5.EFFECTIVE)},
        'classification': {'path': v5.CLASSIFICATION, 'sha256': sha256_of(v5.CLASSIFICATION)},
        'authority': {'path': AUTHORITY, 'sha256': sha256_of(AUTHORITY)},
        'baseline': {'path': v5.BASELINE, 'sha256': sha256_of(v5.BASELINE)},
        'policy': {'path': v5.POLICY, 'sha256': sha256_of(v5.POLICY)},
        'catalog': {'path': CATALOG, 'sha256': sha256_of(CATALOG)},
    }
    result, code = run_acceptance(
        effective_records=effective['records'],
        classification_records=classification,
        authority_records=authority,
        policy_data=p,
        catalog_entries=catalog,
        baseline_profiles=baseline['profiles'],
        data_commit=DATA_COMMIT,
        tool_sha256=tool_sha,
        input_shas=input_shas,
        generator_head=head,
    )
    v5.dump(v5.REPORT + 'V505_ACCEPTANCE_RUN.json', result)
    print('ACCEPTANCE_RUN data_commit=%s monsters=%d failures=%d elapsed=%.1fs' % (
        DATA_COMMIT, len(result['monsters']), len(result['failures']), result['elapsed_seconds']))
    if result['failures']:
        for f in result['failures'][:30]:
            print('FAIL:', f)
    return code


if __name__ == '__main__':
    raise SystemExit(main())
