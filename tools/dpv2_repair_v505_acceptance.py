#!/usr/bin/env python3
"""V505 post-merge acceptance: Monte Carlo bound to the CURRENT committed data.

Reads the committed V505 baseline/effective/classification/authority/policy at
the current worktree HEAD, binds the output to that commit and to the SHA256 of
every input file, and exercises the current nine-slot selector (protected first,
same-group priority descending, cap 9) exactly as the runtime contract mirrors it.

Scope boundary (per author review F04): this is a Python RNG + selection model.
It does NOT execute Godot, instantiate ground-item nodes, or test devices/APK.
Runtime/device acceptance must be collected separately.

Close-condition coverage (per author review F01):
  - coverage of all identities actually participating in drops, grouped by
    baseline_origin (VERIFIED_21CQ_PROFILE_V505 / LEGACY_21CQ_MONITEMS /
    PROJECT_EXTENSION) and by authority source_status;
  - high-risk monsters (bosses 76/198/199/225, new clothes 235-240, verified
    book monsters, legacy exceptions 75/123): per-slot hits/selected/discarded
    plus always_retained boundary;
  - book per-kill distributions (all books and elite/boss books);
  - new-clothes deterministic retention boundary tests for the six exact 1/60
    slots (analytic expectation, 6-sigma observed check, always_retained);
  - output supersedes the stale pre-migration simulation.json as the evidence
    for the new baseline (old file's failures=[] no longer used).
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
MANIFEST = DATA + 'dpv2_direct_baseline_manifest_v2.json'
CATALOG = 'assets/data/runtime/canonical_monster_catalog.json'


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


def simulate_monster(rows, classes, equipment, book_item_ids, elite_book_item_ids, trials, seed):
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
        elite_hits = [i for i in selected if rows[i].get('canonical_item_id') in elite_book_item_ids]
        any_book += int(bool(book_hits))
        book_total_dist[len(book_hits)] += 1
        book_elite_dist[len(elite_hits)] += 1
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
    }


def within(observed: int, expected: float, trials: int) -> bool:
    tolerance = 6 * math.sqrt(expected * (1 - expected) / trials) + 1 / trials
    return abs(observed / trials - expected) <= tolerance


def main() -> int:
    head = git_head()
    p = v5.policy()
    effective = v5.read(v5.EFFECTIVE)
    classification = v5.unchanged_json(v5.CLASSIFICATION)['records']
    authority = v5.read(AUTHORITY)['records']
    catalog = v5.unchanged_json(CATALOG)['entries']
    classes = {r['monster_id']: r['classification'] for r in catalog}
    equipment = {r['canonical_item_id'] for r in classification if r['classification'] == 'EQUIPMENT'}
    books = {r['slot_uid'] for r in effective['records'] if r.get('repair_v5_rule', '').startswith('BOOK')}
    book_item_ids = {r['canonical_item_id'] for r in effective['records'] if r.get('repair_v5_rule', '').startswith('BOOK')}
    elite_book_item_ids = {r['canonical_item_id'] for r in effective['records'] if r.get('repair_v5_rule') == 'BOOK_ELITE_BOSS'}
    elite_books = {r['slot_uid'] for r in effective['records'] if r.get('repair_v5_rule') == 'BOOK_ELITE_BOSS'}
    book_monsters = {r['canonical_monster_id'] for r in effective['records'] if r['slot_uid'] in books}

    inputs = {
        'effective': {'path': v5.EFFECTIVE, 'sha256': sha256_of(v5.EFFECTIVE)},
        'classification': {'path': v5.CLASSIFICATION, 'sha256': sha256_of(v5.CLASSIFICATION)},
        'authority': {'path': AUTHORITY, 'sha256': sha256_of(AUTHORITY)},
        'policy': {'path': v5.POLICY, 'sha256': sha256_of(v5.POLICY)},
        'catalog': {'path': CATALOG, 'sha256': sha256_of(CATALOG)},
    }

    by_monster = defaultdict(list)
    for r in effective['records']:
        by_monster[r['canonical_monster_id']].append(r)
    all_ids = sorted(by_monster)
    status_of = {r['canonical_monster_id']: r['source_status'] for r in authority}

    high_risk = set([76, 198, 199, 225]) | set(range(235, 241)) | book_monsters | {75, 123}
    trials_map = {mid: (100000 if mid in high_risk else 20000) for mid in all_ids}
    seed_base = p['test_seed']

    failures = []
    monsters_out = {}
    started = time.perf_counter()
    for mid in all_ids:
        rows = by_monster[mid]
        trials = trials_map[mid]
        data = simulate_monster(rows, classes, equipment, book_item_ids, elite_book_item_ids, trials, seed_base + mid)
        origins = Counter(r['baseline_origin'] for r in rows)
        status = status_of.get(mid, 'NO_AUTHORITY_ROW')
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
        }
        reward_kinds = Counter(r['reward_kind'] for r in rows)
        entry['reward_summary'] = {
            'slots_by_reward_kind': dict(reward_kinds),
            'equipment_slots': sum(1 for r in rows if r.get('canonical_item_id') in equipment),
            'book_slots': sum(1 for r in rows if r['slot_uid'] in books),
            'book_elite_boss_slots': sum(1 for r in rows if r['slot_uid'] in elite_books),
            'top_slots': sorted(
                [{'item_id': r.get('canonical_item_id'), 'slot_uid': r['slot_uid'],
                  'probability': '%d/%d' % (r['effective_numerator'], r['effective_denominator']),
                  'origin': r['baseline_origin'], 'rule': r['repair_v5_rule']}
                 for r in rows],
                key=lambda x: x['probability'], reverse=True)[:6],
        }
        if any(r['slot_uid'] in books for r in rows):
            entry['book_per_kill_total_dist'] = data['book_total_dist']
            entry['book_per_kill_elite_boss_dist'] = data['book_elite_dist']
        if mid in high_risk:
            details = []
            for i, row in enumerate(rows):
                prob = float(data['probs'][row['slot_uid']])
                if not within(data['hits'][i], prob, trials):
                    failures.append('%d:hit_rate:%s' % (mid, row['slot_uid']))
                details.append({
                    'slot_uid': row['slot_uid'],
                    'item_id': row.get('canonical_item_id'),
                    'roll_probability': str(data['probs'][row['slot_uid']]),
                    'hits': data['hits'][i],
                    'selected': data['selected_counts'][i],
                    'discarded': data['hits'][i] - data['selected_counts'][i],
                    'always_retained': v5.always_retained(row, rows),
                    'origin': row['baseline_origin'],
                    'rule': row['repair_v5_rule'],
                })
            entry['per_slot'] = details
        if not within(data['any_equipment_observed'] * trials, data['any_equipment_analytic'], trials):
            failures.append('%d:any_equipment_6_sigma' % mid)
        if not within(data['any_book_observed'] * trials, data['any_book_analytic'], trials):
            failures.append('%d:any_book_6_sigma' % mid)
        monsters_out[str(mid)] = entry
        print('ACCEPTANCE monster=%d trials=%d slots=%d failures=%d' % (mid, trials, len(rows), len(failures)), flush=True)

    new_clothes = []
    for mid in range(235, 241):
        rows = by_monster[mid]
        for row in rows:
            if row['effective_numerator'] == 1 and row['effective_denominator'] == 60:
                trials = trials_map[mid]
                prob = 1 / 60
                exp_hits = trials * prob
                observed = None
                for i, r in enumerate(rows):
                    if r['slot_uid'] == row['slot_uid']:
                        observed = monsters_out[str(mid)]['per_slot'][i]['hits']
                        selected = monsters_out[str(mid)]['per_slot'][i]['selected']
                        discarded = monsters_out[str(mid)]['per_slot'][i]['discarded']
                        break
                sigma = abs(observed - exp_hits) / math.sqrt(exp_hits * (1 - prob))
                always = v5.always_retained(row, rows)
                new_clothes.append({
                    'monster_id': mid, 'item_id': row['canonical_item_id'], 'slot_uid': row['slot_uid'],
                    'rule': row['repair_v5_rule'],
                    'expected_hits': exp_hits, 'observed_hits': observed,
                    'deviation_sigma': sigma, 'within_6_sigma': sigma <= 6.0,
                    'always_retained': always, 'selected_eq_hits': (selected == observed),
                    'discarded': discarded,
                })
                if sigma > 6.0 or not always or selected != observed:
                    failures.append('NEW_CLOTHES:%d:%s' % (mid, row['slot_uid']))

    elapsed = time.perf_counter() - started
    origin_counts = Counter(r['baseline_origin'] for r in effective['records'])
    result = {
        'schema': 'hardcore.dpv2.v505.acceptance_run.v1',
        'commit': head,
        'generated_at': time.strftime('%Y-%m-%dT%H:%M:%S%z'),
        'scope': 'PYTHON_RNG_SELECTION_MODEL_NOT_GODOT_NOT_NODE_SPAWN_NOT_DEVICE',
        'inputs': inputs,
        'selector': {'protected_first': True, 'same_group_priority_desc': True, 'cap': 9,
                     'rng': 'inclusive_integer_randrange_1_to_d', 'python_mirror_of_runtime_contract': True},
        'trials_policy': {'high_risk': 100000, 'other': 20000, 'book_bosses_new_clothes': 'high_risk'},
        'coverage': {
            'distinct_monster_ids': len(all_ids),
            'total_records': len(effective['records']),
            'origin_counts': dict(origin_counts),
            'source_status_counts': dict(Counter(status_of.get(m, 'NO_AUTHORITY_ROW') for m in all_ids)),
        },
        'monsters': monsters_out,
        'new_clothes_boundary': new_clothes,
        'elapsed_seconds': elapsed,
        'failures': failures,
    }
    v5.dump(v5.REPORT + 'V505_ACCEPTANCE_RUN.json', result)
    print('ACCEPTANCE_RUN commit=%s monsters=%d failures=%d elapsed=%.1fs' % (head, len(all_ids), len(failures), elapsed))
    return 1 if failures else 0


if __name__ == '__main__':
    raise SystemExit(main())
