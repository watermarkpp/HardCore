from __future__ import annotations
from fractions import Fraction
from pathlib import Path
import itertools
import json
import random
import sys
import unittest
from unittest.mock import patch
import copy

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import dpv2_repair_v5 as v5
from dpv2_repair_v5_simulate import select, simulate


def row(uid: str, item: int, protected: bool = False, priority: int = 200) -> dict:
    return {'slot_uid': uid, 'canonical_item_id': item, 'protected_drop': protected,
            'overflow_priority': priority, 'canonical_monster_id': 76}


class RationalTests(unittest.TestCase):
    def test_book_ordinary(self):
        self.assertEqual(v5.boosted(Fraction(1, 700), 5, Fraction(1, 100)), Fraction(1, 140))

    def test_book_cap(self):
        self.assertEqual(v5.boosted(Fraction(1, 700), 25, Fraction(1, 20)), Fraction(1, 28))
        self.assertEqual(v5.boosted(Fraction(1, 100), 25, Fraction(1, 20)), Fraction(1, 20))

    def test_never_nerf_above_cap(self):
        self.assertEqual(v5.boosted(Fraction(1, 2), 25, Fraction(1, 20)), Fraction(1, 2))

    def test_invalid(self):
        for n, d in [(0, 1), (1, 0), (2, 1), (True, 2), (1.0, 2), (1, 2147483648)]:
            with self.subTest(n=n, d=d), self.assertRaises(v5.RepairError):
                v5.checked_fraction(n, d)

    def test_draw_boundaries(self):
        for n, d in [(1, 1), (1, 60), (3, 19), (19, 19)]:
            draws = {1, n, d}
            if n < d:
                draws.add(n + 1)
            for draw in draws:
                self.assertTrue(1 <= draw <= d)
                self.assertEqual(draw <= n, draw in range(1, n + 1))

    def test_denominator_modifiers(self):
        self.assertEqual(v5.denominator_modifier('ordinary', 100, {100}), 3)
        self.assertEqual(v5.denominator_modifier('ordinary', 910001, {100}), 6)
        self.assertEqual(v5.denominator_modifier('boss', 920014, {100}), 2)
        self.assertEqual(v5.denominator_modifier('elite', 100, {100}), 1)
        self.assertEqual(v5.denominator_modifier('boss', 140, {140}), 1)


class SelectionTests(unittest.TestCase):
    def test_protected_beats_any_ordinary_priority(self):
        self.assertGreater(v5.rank(row('a', 1, True, 200)), v5.rank(row('b', 2, False, 100000)))

    def test_all_success_tie(self):
        rows = [row(str(i), 1 if i == 0 else 2) for i in range(10)]
        probabilities = {r['slot_uid']: Fraction(1) for r in rows}
        self.assertAlmostEqual(v5.no_equipment_after_selection(rows, probabilities, {1}), 0.1, places=13)

    def test_two_equipment_cannot_both_be_discarded(self):
        rows = [row(str(i), 1 if i < 2 else 2) for i in range(10)]
        self.assertEqual(v5.no_equipment_after_selection(rows, {r['slot_uid']: Fraction(1) for r in rows}, {1}), 0)

    def test_armor_worst_case(self):
        armor = row('target', 140, True, 2000)
        rows = [armor] + [row(str(i), 2, True, 1000) for i in range(80)]
        self.assertTrue(v5.always_retained(armor, rows))
        self.assertAlmostEqual(v5.no_equipment_after_selection(rows, {r['slot_uid']: Fraction(1, 60) if r is armor else Fraction(1) for r in rows}, {140}), 59 / 60)

    def test_eight_vs_nine_equal_competitors(self):
        armor = row('target', 1, True, 1000)
        self.assertTrue(v5.always_retained(armor, [armor] + [row(str(i), 2, True, 1000) for i in range(8)]))
        self.assertFalse(v5.always_retained(armor, [armor] + [row(str(i), 2, True, 1000) for i in range(9)]))

    def test_no_duplicates_merged(self):
        rows = [row('a', 1), row('b', 1)]
        probabilities = {'a': Fraction(1, 2), 'b': Fraction(1, 2)}
        self.assertAlmostEqual(v5.no_equipment_after_selection(rows, probabilities, {1}), 0.25)

    def test_exact_enumeration_independent_check(self):
        rows = [row('a', 1, True, 600), row('b', 2, True, 600), row('c', 2), row('d', 1)]
        probs = dict(zip(['a', 'b', 'c', 'd'], [Fraction(1, 3), Fraction(1, 4), Fraction(2, 5), Fraction(1, 2)]))
        answer = Fraction(0)
        for mask in itertools.product([0, 1], repeat=4):
            mass = Fraction(1)
            winners = [r for r, hit in zip(rows, mask) if hit]
            for r, hit in zip(rows, mask):
                mass *= probs[r['slot_uid']] if hit else 1 - probs[r['slot_uid']]
            if not winners:
                answer += mass
                continue
            best = max(v5.rank(r) for r in winners)
            top = [r for r in winners if v5.rank(r) == best]
            answer += mass * Fraction(sum(r['canonical_item_id'] != 1 for r in top), len(top))
        self.assertAlmostEqual(v5.no_equipment_after_selection(rows, probs, {1}, limit=1), float(answer), places=13)

    def test_small_monte_carlo(self):
        rows = [dict(row('a', 1, True, 600), effective_numerator=1, effective_denominator=4),
                dict(row('b', 2), effective_numerator=1, effective_denominator=2)]
        result = simulate(rows, {76: 'boss'}, {1}, set(), 10000, 77)
        self.assertEqual(result['failures'], [])

    def test_same_seed_and_tie_selection(self):
        self.assertEqual(select([[0, 1, 2]], {0, 1, 2}, random.Random(1), 2), select([[0, 1, 2]], {0, 1, 2}, random.Random(1), 2))


class SourceTests(unittest.TestCase):
    @staticmethod
    def html(name='邪恶毒蛇', chance='1/705', item='冰咆哮'):
        return f'<html><title>{name}_掉落资料</title><table><tr><th>物品</th><th>爆率</th><th>数量</th></tr><tr><td>{item}</td><td>{chance}</td><td>1</td></tr></table></html>'

    def test_parse(self):
        result = v5.parse_drop_table(self.html(), '邪恶毒蛇')
        self.assertEqual(result, [{'item': '冰咆哮', 'numerator': 1, 'denominator': 705, 'amount': 1}])

    def test_exact_suffix_identity(self):
        with self.assertRaises(v5.RepairError):
            v5.parse_drop_table(self.html(name='沃玛卫士1'), '沃玛卫士')

    def test_encoding(self):
        text = self.html()
        decoded, encoding = v5.decode_source(text.encode('gb2312'), 'gb2312')
        self.assertEqual(decoded, text)
        self.assertEqual(encoding, 'gb2312')

    def test_unknown_never_defaults(self):
        for token in ['unknown', '', '1/00', '0', '5%', '1/0']:
            with self.subTest(token=token), self.assertRaises(v5.RepairError):
                v5.parse_drop_table(self.html(chance=token), '邪恶毒蛇')

    def test_conflicting_tables_do_not_merge(self):
        with self.assertRaises(v5.RepairError):
            v5.parse_drop_table(self.html() + self.html(chance='1/1'), '邪恶毒蛇')

    def test_missing_table_is_not_zero_drop(self):
        with self.assertRaises(v5.RepairError):
            v5.parse_drop_table('<title>邪恶毒蛇</title><p>无数据</p>', '邪恶毒蛇')

    def test_duplicate_rows_retained(self):
        html = self.html().replace('</table>', '<tr><td>冰咆哮</td><td>1/705</td><td>1</td></tr></table>')
        self.assertEqual(len(v5.parse_drop_table(html, '邪恶毒蛇')), 2)

    def test_lf_hash_normalization(self):
        self.assertEqual(v5.text_hash('a\r\nb\r\n'), v5.text_hash('a\nb\n'))

    def test_duplicate_slot_rejected(self):
        baseline = {'profiles': [{'canonical_monster_id': 73, 'slots': [{'slot_uid': 'x'}, {'slot_uid': 'x'}]}]}
        with self.assertRaises(v5.RepairError):
            v5.slots_by_uid(baseline)



class FinalizationTests(unittest.TestCase):
    def test_k_once_and_armor_bypass_with_mocked_build_inputs(self):
        targets = [{'monster_id': m, 'slot_uid': f'dpv2.direct.m{m}.slot_054', 'source_item_id': m + 100} for m in range(235, 241)]
        gear = list(range(101, 110))
        p = {'book_ids': [], 'boss_ids': [76, 198, 199, 225],
             'boss_allowlist': [{'monster_id': 76, 'slot_uid': f'dpv2.direct.m76.slot_{i:03}', 'canonical_item_id': item} for i, item in enumerate(gear, 1)],
             'boss_no_equipment_target': [7, 20], 'boss_no_equipment_tolerance': 0.00005,
             'boss_per_slot_ceiling': [1, 4], 'boss_k_max_denominator': 10000,
             'armor_targets': targets}
        profiles = []
        records = []
        def add(mid, uid, item, n, d, protection, priority):
            r = dict(row(uid, item, protection, priority), canonical_monster_id=mid,
                     base_numerator=n, base_denominator=d, effective_numerator=n,
                     effective_denominator=d, formula_reason_code='TEST')
            records.append(r)
            return {k: v for k, v in r.items() if k != 'canonical_monster_id'}
        profiles.append({'canonical_monster_id': 76, 'slots': [add(76, f'dpv2.direct.m76.slot_{i:03}', item, 1, 20, True, 600) for i, item in enumerate(gear, 1)]})
        for target in targets:
            mid = target['monster_id']
            slots = [add(mid, target['slot_uid'], target['source_item_id'], 1, 60, True, 2000)]
            slots += [add(mid, f'dpv2.direct.m{mid}.slot_{i:03}', 999, 1, 1, False, 200) for i in range(1, 14)]
            profiles.append({'canonical_monster_id': mid, 'slots': slots})
        equipment = set(gear) | {t['source_item_id'] for t in targets}
        catalog = {'entries': [{'monster_id': mid, 'classification': 'boss'} for mid in [76, 198, 199, 225, *range(235, 241)]]}
        classifications = {'records': [{'canonical_item_id': item, 'classification': 'EQUIPMENT'} for item in equipment]}
        classifications['records'].append({'canonical_item_id': 999, 'classification': 'COMMON_RECOVERY'})
        def unchanged(path):
            return catalog if 'catalog' in path else classifications
        audit = {'verified_book_monster_ids': [], 'identities': [{'monster_id': mid, 'source_status': 'VERIFIED'} for mid in [76, 198, 199]], 'blockers': []}
        authority = {'source_bindings': {}, 'summary': {}, 'probability_contract': {'formula': 'BASE'}}
        effective = {'source_bindings': {}, 'summary': {}, 'records': records}
        reports = {}
        with patch.object(v5, 'policy', return_value=p), patch.object(v5, 'audited_source', return_value=audit), patch.object(v5, 'unchanged_json', side_effect=unchanged), patch.object(v5, 'file_hash', return_value='A' * 64), patch.object(v5, 'dump', side_effect=lambda path, value: reports.update({path: value})), patch.object(v5, 'write_retention_audit'):
            v5.finalize_spb(None, authority, effective, {'profiles': profiles})
        report = reports[v5.REPORT + 'balance.json']
        self.assertEqual(report['k_status'], 'CALIBRATED_POST_SELECTION')
        woma = [r for r in records if r['canonical_monster_id'] == 76]
        probabilities = {r['slot_uid']: Fraction(r['effective_numerator'], r['effective_denominator']) for r in woma}
        actual = v5.no_equipment_after_selection(woma, probabilities, equipment)
        self.assertAlmostEqual(actual, report['woma_no_equipment_after'], places=12)
        self.assertLess(abs(actual - 0.35), p['boss_no_equipment_tolerance'])
        k = Fraction(report['k'])
        for r in woma:
            self.assertEqual(probabilities[r['slot_uid']], Fraction(1, 20) * k)
        for r in records:
            if r['repair_v5_rule'] == 'ARMOR_BASE_1_OVER_60':
                self.assertEqual(Fraction(r['effective_numerator'], r['effective_denominator']), Fraction(1, 60))

if __name__ == '__main__':
    unittest.main()
