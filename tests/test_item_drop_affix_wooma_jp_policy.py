"""Exact finite-distribution checks; native seeded/save checks live in the GDScript scene."""
import importlib.util
import itertools
import json
import subprocess
import unittest
from fractions import Fraction
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('jp_builder', ROOT/'tools/build_item_drop_affix_wooma_jp_policy.py')
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


class JPPolicyTest(unittest.TestCase):
    def test_finite_conditional_distribution_contract(self):
        data = builder.build()
        self.assertEqual(data.get('contract_id'), 'item.drop.affix.rules.v4')
        self.assertEqual(len(data['records']), 92)
        for row in data['records']:
            q = Fraction(row['inner_nonzero_probability_exact'])
            old = Fraction(row['current_event_probability_exact'])
            target = Fraction(row['target_event_probability_exact'])
            self.assertEqual(target, min(1, 3*old))
            self.assertEqual(old, q/2)
            zero = Fraction(1)
            for roll in row['rolls']:
                unconditional = {o['value']:Fraction(o['probability_exact']) for o in roll['outcomes']}
                if roll['event_eligible']:
                    zero *= unconditional.get(0,0)
                self.assertEqual(sum(unconditional.values()), 1)
                suffix = Fraction(roll['suffix_zero_probability_exact'])
                remaining = 1-unconditional.get(0, 0)*suffix
                conditional = {o['value']:Fraction(o['prefix_zero_probability_exact']) for o in roll['outcomes']}
                self.assertEqual(sum(conditional.values()), 1)
                for value, prob in unconditional.items():
                    expected = prob*(1-suffix if value == 0 else 1)/remaining if roll['event_eligible'] else prob
                    self.assertEqual(conditional[value], expected)
            self.assertEqual(q,1-zero,'JP event follows nonempty modifiers, never durability-only')

    def test_authoring_scope_has_exact_full_master_classification(self):
        data = builder.build()
        tiers = builder.read(builder.TIERS)
        master = builder.read(ROOT/'assets/data/equipment_attribute_master.json')['records']
        expected = sorted(r['itemId'] for r in master if tiers['exact_id_overrides'][str(r['itemId'])] in {'wooma','zuma','redmoon','ultra_rare'})
        self.assertEqual([r['canonical_item_id'] for r in data['records']], expected)

    def test_conditional_joint_distribution_and_signed_support(self):
        # Exhaustively enumerate a small independent rule family, including
        # zero, two signs, and an excluded rule. This tests joint law, not marginals.
        base = dict(trials=1, trial_denominator=3, gate_denominator=4, gate_accept_count=1,
                    add_before_division=0, divisor=1, add_after_division=0, scale=1,
                    original_speed_sign=False, excluded=False)
        originals = [dict(base,stat='speed',original_speed_sign=True),
                     dict(base,stat='excluded',excluded=True), dict(base,stat='durability_bonus_raw')]
        rolls,q = builder.finite_rolls(originals)
        distributions = [builder.outcome_distribution(r) for r in originals]
        total = Fraction(0)
        for values in itertools.product(*(d.keys() for d in distributions)):
            original = Fraction(1)
            conditional = Fraction(1)
            prefix_zero = True
            for value,distribution,roll in zip(values,distributions,rolls):
                original *= distribution[value]
                outcome = next(o for o in roll['outcomes'] if o['value']==value)
                conditional *= Fraction(outcome['prefix_zero_probability_exact'] if prefix_zero else outcome['probability_exact'])
                prefix_zero = prefix_zero and (value==0 or not roll['event_eligible'])
            self.assertEqual(conditional, 0 if prefix_zero else original/q)
            total += conditional
        self.assertEqual(total, 1)
        self.assertEqual(distributions[0][-1],2*distributions[0][1])
        self.assertEqual(distributions[1],{0:1})

    def test_integer_cdf_precision_and_finite_support(self):
        data = builder.build()
        for row in data['records']:
            target = Fraction(row['target_event_probability_exact'])
            self.assertLessEqual(abs(Fraction(row['runtime_gate_numerator'],builder.RUNTIME_DENOM)-target),Fraction(1,2*builder.RUNTIME_DENOM))
            for roll in row['rolls']:
                for pfield,cfield in [('probability_exact','cdf_tick'),('prefix_zero_probability_exact','prefix_zero_cdf_tick')]:
                    cumulative = Fraction(0)
                    last = 0
                    for outcome in roll['outcomes']:
                        probability = Fraction(outcome[pfield])
                        cumulative += probability
                        tick = outcome[cfield]
                        self.assertEqual(int(float(tick)),tick, 'JSON binary64 integer precision')
                        self.assertGreaterEqual(tick,last)
                        self.assertLessEqual(abs(Fraction(tick,builder.RUNTIME_DENOM)-cumulative),Fraction(1,2*builder.RUNTIME_DENOM))
                        if probability == 0:
                            self.assertEqual(tick,last,'zero support cannot acquire a runtime tick')
                        else:
                            self.assertGreater(tick,last,'every legal outcome retains nonzero runtime support')
                        last = tick
                    self.assertEqual(last,builder.RUNTIME_DENOM)
            # Last eligible modifier cannot remain zero if preceding modifiers are zero.
            last = next(r for r in reversed(row['rolls']) if r['event_eligible'])
            zero = next(o for o in last['outcomes'] if o['value']==0)
            self.assertEqual(zero['prefix_zero_cdf_tick'],0)

    def test_no_jp_outer_mixture_retains_original_conditional_distribution(self):
        for row in builder.build()['records']:
            q = Fraction(row['inner_nonzero_probability_exact'])
            z = 1-q
            outer = Fraction(row['no_jp_outer_pass_probability_exact'])
            self.assertEqual(outer,z/(1+z))
            self.assertLessEqual(abs(Fraction(row['no_jp_outer_pass_gate_numerator'],builder.RUNTIME_DENOM)-outer),Fraction(1,2*builder.RUNTIME_DENOM))
            durability = next(r for r in row['rolls'] if r['stat']=='durability_bonus_raw')
            for outcome in durability['outcomes']:
                p = Fraction(outcome['probability_exact'])
                # Exact old v3 P(durability=value, no JP), including outer failure.
                old_mass = z*p/2 + (Fraction(1,2) if outcome['value']==0 else 0)
                new_conditional = outer*p + (1-outer if outcome['value']==0 else 0)
                self.assertEqual(new_conditional,old_mass/(1-q/2))

    def test_frozen_v3_source_and_runtime_bytes(self):
        for path in ['scripts/item_drop_affix_v3_rules.gd','assets/data/item_drop_affix_rules_v3.json']:
            committed = subprocess.check_output(['git','show','HEAD:'+path],cwd=ROOT)
            current = (ROOT/path).read_bytes()
            self.assertEqual(current.replace(b'\r\n',b'\n'), committed.replace(b'\r\n',b'\n'))

    def test_generated_evidence_and_reproducibility(self):
        data = builder.build()
        self.assertEqual(data,builder.build())
        self.assertEqual(builder.read(builder.OUT),data)
        for key,path in [('source_authority',builder.SOURCE),('classification_authority',builder.TIERS),('frozen_v3_authority',builder.V3),('master_authority',builder.MASTER)]:
            self.assertEqual(data[key]['sha256_lf'],builder.fingerprint(path))


if __name__ == '__main__':
    unittest.main()
