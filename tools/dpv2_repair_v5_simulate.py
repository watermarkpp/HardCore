#!/usr/bin/env python3
"""Offline Monte Carlo of exact integer draws and the unchanged nine-slot selector.

This does not execute Godot or instantiate ground-item nodes. Runtime and APK
statuses must be collected separately by RUN_V5.ps1 and device acceptance.
"""
from __future__ import annotations
from collections import defaultdict
from fractions import Fraction
import math
import random
import time
import dpv2_repair_v5 as v5


def select(groups: list[list[int]], successful: set[int], rng: random.Random, cap: int = 9) -> list[int]:
    selected = []
    for group in groups:
        candidates = [i for i in group if i in successful]
        remaining = cap - len(selected)
        if remaining <= 0:
            break
        if len(candidates) > remaining:
            rng.shuffle(candidates)
        selected.extend(candidates[:remaining])
    return selected


def simulate(rows: list[dict], classes: dict[int, str], equipment: set[int], books: set[int], trials: int, seed: int) -> dict:
    rng = random.Random(seed)
    grouped = defaultdict(list)
    probs = {}
    nd = []
    for i, row in enumerate(rows):
        grouped[v5.rank(row)].append(i)
        m = v5.denominator_modifier(classes[row['canonical_monster_id']], row.get('canonical_item_id', -1), equipment)
        fraction = Fraction(row['effective_numerator'], row['effective_denominator']) / m
        probs[row['slot_uid']] = fraction
        nd.append((fraction.numerator, fraction.denominator))
    groups = [grouped[k] for k in sorted(grouped, reverse=True)]
    hits, selected_counts = [0] * len(rows), [0] * len(rows)
    any_equipment = any_book = protected_discarded = 0
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
        any_book += int(any(rows[i].get('canonical_item_id') in books for i in selected))
        protected_discarded += sum(rows[i]['protected_drop'] for i in succeeded.difference(selected))
    exact_eq = 1 - v5.no_equipment_after_selection(rows, probs, equipment)
    exact_book = 1 - v5.no_equipment_after_selection(rows, probs, books)
    def within(observed: int, expected: float) -> bool:
        tolerance = 6 * math.sqrt(expected * (1 - expected) / trials) + 1 / trials
        return abs(observed / trials - expected) <= tolerance
    failures = []
    if not within(any_equipment, exact_eq):
        failures.append('any_equipment_6_sigma')
    if not within(any_book, exact_book):
        failures.append('any_book_6_sigma')
    details = []
    for i, row in enumerate(rows):
        probability = float(probs[row['slot_uid']])
        if not within(hits[i], probability):
            failures.append('hit_rate:' + row['slot_uid'])
        details.append({'slot_uid': row['slot_uid'], 'item_id': row.get('canonical_item_id'),
                        'roll_probability': str(probs[row['slot_uid']]), 'hits': hits[i],
                        'selected': selected_counts[i], 'discarded': hits[i] - selected_counts[i]})
    return {'trials': trials, 'seed': seed, 'rng': 'inclusive_integer_randrange_1_to_d',
            'any_equipment_observed': any_equipment / trials, 'any_equipment_analytic': exact_eq,
            'any_book_observed': any_book / trials, 'any_book_analytic': exact_book,
            'protected_discarded': protected_discarded, 'failures': failures, 'slots': details}


def main() -> int:
    p = v5.policy()
    v5.validate_spb_inputs  # Generation and --check run before this tool.
    effective = v5.read(v5.EFFECTIVE)
    catalog = v5.unchanged_json('assets/data/runtime/canonical_monster_catalog.json')['entries']
    classes = {r['monster_id']: r['classification'] for r in catalog}
    classification = v5.unchanged_json(v5.CLASSIFICATION)['records']
    equipment = {r['canonical_item_id'] for r in classification if r['classification'] == 'EQUIPMENT'}
    targets = [73, 74, 75, 76, 89, 90, 91, 135, 141, 198, 199, 225, 235, 236, 237, 238, 239, 240]
    result = {'scope': 'PYTHON_RNG_SELECTION_MODEL_NOT_GODOT_NOT_NODE_SPAWN_NOT_DEVICE', 'monsters': {}, 'failures': []}
    started = time.perf_counter()
    for mid in targets:
        rows = [r for r in effective['records'] if r['canonical_monster_id'] == mid]
        v5.require(bool(rows), f'SIMULATION_ID_HAS_NO_ROWS:{mid}')
        data = simulate(rows, classes, equipment, set(p['book_ids']), p['simulation_trials'], p['test_seed'] + mid)
        result['monsters'][str(mid)] = data
        result['failures'].extend(f'{mid}:{failure}' for failure in data['failures'])
        print(f'DPV2_V5_SIMULATION monster={mid} trials={p["simulation_trials"]} failures={len(data["failures"])}', flush=True)
        v5.dump(v5.REPORT + 'simulation.json', result)
    result['elapsed_seconds'] = time.perf_counter() - started
    v5.dump(v5.REPORT + 'simulation.json', result)
    return 1 if result['failures'] else 0


if __name__ == '__main__':
    raise SystemExit(main())
