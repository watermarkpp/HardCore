"""Exact ground-output inclusion probabilities for the queried production snapshot.

No game state, source authority or production data is modified. Python's arbitrary
precision integers and Fraction retain every digit. Output is a static audit
snapshot because Excel's numeric precision cannot represent these rationals.
"""
from __future__ import annotations

import argparse
from collections import Counter, defaultdict
from fractions import Fraction as F
from functools import lru_cache
from itertools import product, combinations
from math import comb
import hashlib
import json
from pathlib import Path
import random
import time


def ratio(p):
    return f"{p.numerator}/{p.denominator}"


@lru_cache(maxsize=None)
def pmf(probabilities):
    """Poisson-binomial PMF, formed as an integer polynomial then normalized."""
    weights = [1]
    denominator = 1
    for numerator, divisor in probabilities:
        updated = [0] * (len(weights) + 1)
        for count, weight in enumerate(weights):
            updated[count] += weight * (divisor - numerator)
            updated[count + 1] += weight * numerator
        weights = updated
        denominator *= divisor
    return tuple((k, F(w, denominator)) for k, w in enumerate(weights) if w)


@lru_cache(maxsize=None)
def no_target_transitions(target_probabilities, other_probabilities, remaining):
    """(additional seats used, probability of no selected target) transitions.

    When t target and o other slots succeed in a tied group, selecting r uniformly
    from t+o successful slots misses every target with C(o,r)/C(t+o,r).
    """
    result = defaultdict(F)
    for t, pt in pmf(target_probabilities):
        for o, po in pmf(other_probabilities):
            total = t + o
            if total <= remaining:
                if t == 0:
                    result[total] += pt * po
            elif o >= remaining:
                result[remaining] += pt * po * F(comb(o, remaining), comb(total, remaining))
    return tuple(sorted(result.items()))


@lru_cache(maxsize=None)
def inclusion_probability(group_specs, cap):
    """Track occupied seats conditional on no target selected so far."""
    last_target = max((i for i, (t, _) in enumerate(group_specs) if t), default=-1)
    state = {0: F(1)}
    for targets, others in group_specs[:last_target + 1]:
        next_state = defaultdict(F)
        for occupied, mass in state.items():
            remaining = cap - occupied
            if remaining == 0:
                next_state[occupied] += mass
            else:
                for used, probability in no_target_transitions(targets, others, remaining):
                    next_state[occupied + used] += mass * probability
        state = next_state
    return F(1) - sum(state.values(), F(0))


def brute_probability(slots, target, cap):
    """Independent small-case oracle: enumerate outcomes and selected subsets."""
    answer = F(0)
    for successes in product([False, True], repeat=len(slots)):
        weight = F(1)
        groups = defaultdict(list)
        for slot, success in zip(slots, successes):
            key, group, probability = slot
            weight *= probability if success else 1 - probability
            if success:
                groups[group].append(key)
        if not weight:
            continue
        states = [((), F(1))]
        for group in sorted(groups, reverse=True):
            candidates = groups[group]
            updated = []
            for chosen, mass in states:
                remaining = max(0, cap - len(chosen))
                count = min(remaining, len(candidates))
                subsets = list(combinations(range(len(candidates)), count))
                for subset in subsets:
                    updated.append((chosen + tuple(candidates[i] for i in subset), mass / len(subsets)))
            states = updated
        answer += weight * sum((mass for chosen, mass in states if target in chosen), F(0))
    return answer


def probability_for(slots, target, cap):
    groups = defaultdict(list)
    for key, group, probability in slots:
        groups[group].append((key, probability))
    specs = []
    for group in sorted(groups, reverse=True):
        selected = groups[group]
        targets = tuple(sorted((p.numerator, p.denominator) for k, p in selected if k == target))
        others = tuple(sorted((p.numerator, p.denominator) for k, p in selected if k != target))
        specs.append((targets, others))
    return inclusion_probability(tuple(specs), cap)


def test_math():
    cases = [
        ([("a", (0, 0), F(1, 2)), ("a", (0, 0), F(1, 3))], "a", 15),
        ([("a", (0, 0), F(1)), ("b", (0, 0), F(1))], "a", 1),
        ([("a", (0, 1), F(1)), ("b", (1, -100), F(1))], "a", 1),
        ([("a", (0, 1), F(1, 2)), ("a", (0, 0), F(1, 3)), ("b", (0, 1), F(1, 4))], "a", 1),
        ([("a", (0, 0), F(1))], "a", 0),
        ([], "a", 15),
    ]
    rng = random.Random(20260922)
    options = [F(0), F(1), F(1, 2), F(1, 3), F(2, 3)]
    for _ in range(70):
        n = rng.randrange(1, 8)
        slots = [(rng.choice(["a", "a", "b", "c"]), (rng.randrange(2), rng.randrange(3)), rng.choice(options)) for _ in range(n)]
        cases.append((slots, "a", rng.randrange(0, 5)))
    for i, (slots, target, cap) in enumerate(cases):
        actual = probability_for(slots, target, cap)
        expected = brute_probability(slots, target, cap)
        assert actual == expected, (i, actual, expected, slots)
    assert probability_for([("a", (0, 200), F(1))] + [("b", (0, 200), F(1))] * 15, "a", 15) == F(15, 16)
    assert probability_for([("a", (0, 100), F(1))] + [("b", (0, 200), F(1))] * 16, "a", 15) == 0
    return {"status": "PASS", "exhaustive_cases": len(cases), "explicit_cap_boundaries": 2}


def build(source, destination):
    started = time.monotonic()
    payload = json.loads(source.read_text(encoding="utf-8-sig"))
    assert not payload["failures"]
    assert payload["monster_count"] == len(payload["monsters"])
    cap = payload["ground_limit"]
    math_tests = test_math()
    result = {"source_sha256": hashlib.sha256(source.read_bytes()).hexdigest(), "ground_limit": cap,
              "source_path": str(source), "map_count": payload["map_count"], "spawn_points": payload["spawn_points"],
              "slot_count": payload["slot_count"], "math_tests": math_tests, "monsters": []}
    classification_labels = {"ordinary": "普通", "elite": "精英", "boss": "Boss", "special": "特殊"}
    for monster in sorted(payload["monsters"], key=lambda m: m["monster_id"]):
        mid = monster["monster_id"]
        normalized = []
        outputs = defaultdict(list)
        detailed = []
        for row in monster["slots"]:
            probability, reward, output = row["probability"], row["reward"], row["output"]
            assert probability["ok"] and reward["ok"]
            assert probability["canonical_monster_id"] == mid
            p = F(int(probability["final_numerator"]), int(probability["final_denominator"]))
            assert 0 < p <= 1
            if reward["kind"] == "gold":
                amount = int(probability["final_gold_amount"])
                assert amount == int(reward["gold_amount"]) and amount > 0
                key = ("gold", amount)
                name, item_id = f"金币 × {amount}", "金币"
            else:
                assert reward["kind"] == "item" and int(output["item_id"]) > 0
                key = ("item", int(output["item_id"]))
                name, item_id = output["name"], int(output["item_id"])
            group = (int(bool(probability["protected_drop"])), int(probability["overflow_priority"]))
            normalized.append((key, group, p))
            detail = {"slot_uid": probability["slot_uid"], "name": name, "item_id": item_id,
                      "source_item_id": probability.get("canonical_item_id"), "probability": ratio(p),
                      "protected": bool(group[0]), "priority": group[1], "source_sheet_row": int(row["slot"].get("source_sheet_row", 0))}
            detailed.append(detail)
            outputs[key].append(detail)
        main = []
        for key, slots in outputs.items():
            actual = probability_for(normalized, key, cap)
            pre_rng_any = 1
            for slot in slots:
                pre_rng_any *= 1 - F(slot["probability"])
            pre_rng_any = 1 - pre_rng_any
            assert 0 <= actual <= pre_rng_any <= 1
            p_counts = Counter(s["probability"] for s in slots)
            groups = Counter((s["protected"], s["priority"]) for s in slots)
            main.append({"name": slots[0]["name"], "item_id": slots[0]["item_id"], "key": list(key),
                         "actual_probability": ratio(actual), "pre_rng_any_probability": ratio(pre_rng_any),
                         "slot_count": len(slots), "slot_probabilities": "\n".join(f"{p} × {n}槽" for p, n in p_counts.items()),
                         "groups": "\n".join(f"{'保护' if protected else '常规'} / {priority} × {n}槽" for (protected, priority), n in groups.items()),
                         "affected_by_cap": actual < pre_rng_any})
        label = classification_labels[monster["classification"]]
        if monster["classification"] == "special" and monster.get("spawn_classification") == "special_normal":
            label = "特殊普通"
        result["monsters"].append({"monster_id": mid, "name": monster["name"], "classification": monster["classification"],
                                   "classification_label": label, "spawn_classification": monster.get("spawn_classification"),
                                   "spawn_points": monster["spawn_points"], "maps": monster["maps"],
                                   "outputs": main, "slots": detailed, "profile_present": monster["profile_present"]})
        if len(result["monsters"]) % 10 == 0:
            print(f"Calculated {len(result['monsters'])}/{len(payload['monsters'])}, elapsed={time.monotonic()-started:.1f}s", flush=True)
    all_rows = [r for m in result["monsters"] for r in m["outputs"]]
    result["summary"] = {
        "monster_count": len(result["monsters"]), "output_rows": len(all_rows),
        "classification_counts": dict(Counter(m["classification_label"] for m in result["monsters"])),
        "empty_monster_ids": [m["monster_id"] for m in result["monsters"] if not m["outputs"]],
        "zero_actual_rows": sum(r["actual_probability"] == "0/1" for r in all_rows),
        "cap_affected_rows": sum(r["affected_by_cap"] for r in all_rows),
        "max_probability_chars": max(len(r["actual_probability"]) for r in all_rows),
        "elapsed_seconds": round(time.monotonic() - started, 3),
    }
    dragon = next(m for m in result["monsters"] if m["monster_id"] == 124)
    assert any(m["map_id"] == 913207 for m in dragon["maps"])
    assert next(r for r in dragon["outputs"] if r["key"] == ["gold", 70000])["actual_probability"] == "0/1"
    assert sum(len(m["slots"]) for m in result["monsters"]) == payload["slot_count"]
    destination.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(result["summary"], ensure_ascii=False, indent=2), flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, default=Path("outputs/repair_v92/live_map_loot_authority.json"))
    parser.add_argument("--output", type=Path, default=Path("outputs/repair_v92/excel/exact_ground_probabilities.json"))
    args = parser.parse_args()
    build(args.source, args.output)
