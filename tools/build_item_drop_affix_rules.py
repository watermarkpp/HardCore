"""Extract the ordinary primary-stat JP lane; never overwrite item attributes."""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets/data/item_drop_affix_rules_v2.json'


def build():
    source = ROOT / 'dev_art_sources/reference/original_gameofmir/M2Server'
    paths = [source / n for n in ['ItmUnit.pas', 'UsrEngn.pas', 'M2Share.pas']]
    texts = [p.read_text(encoding='gbk', errors='replace') for p in paths]
    assert 'GetRandomRange' in texts[0] and 'Random(g_Config.nMonRandomAddValue' in texts[1]
    assert 'nMonRandomAddValue: 10' in texts[2]
    master = json.loads((ROOT / 'assets/data/equipment_attribute_master.json').read_text(encoding='utf-8-sig'))
    records = []
    for item in master['records']:
        cat = item['category']
        weapon = cat == '武器'
        armor = cat.startswith('盔甲') or cat == '盔甲'
        # All three damage maxima can roll even when the base item has no value.
        rolls = [dict(source_stat=s, stat=t, trials=12 if weapon else 6,
                      trial_denominator=15 if weapon else 20,
                      gate_denominator=15 if weapon else (40 if armor else 30))
                 for s, t in [('dc', 'attack_max'), ('mc', 'magic_max'), ('sc', 'tao_max')]]
        if armor or cat == '头盔':
            for s, t, gate in [('ac', 'defense_max', 30 if armor else 40), ('mac', 'magic_defense_max', 30)]:
                rolls.insert(0, dict(source_stat=s, stat=t, trials=6, trial_denominator=15 if armor else 20, gate_denominator=gate))
        # A formal bracelet AC/MAC record represents the defense-bearing lane.
        # Non-defense accessory bytes have different meanings, never infer them.
        if cat == '手镯' and any(s in item['stats'] for s in ['ac', 'mac']):
            for s, t in [('ac', 'defense_max'), ('mac', 'magic_defense_max')]:
                rolls.insert(0, dict(source_stat=s, stat=t, trials=6, trial_denominator=20, gate_denominator=20))
        records.append(dict(item_id=item['itemId'], rolls=rolls))
    return dict(schema_version=2, contract_id='item.drop.affix.rules.v2',
                scope='ordinary primary combat maxima; independent per-stat binomial increments',
                original_outer_gate=dict(numerator=1, denominator=10),
                single_player_outer_gate=dict(numerator=1, denominator=2),
                single_player_authorization='2026-09-13 user request 4; five times original entry chance, inner rates unchanged',
                source_policy=dict(lane='server_rules', tier='primary', distribution='source.original_gameofmir.server_suite'),
                sources=[dict(path=p.relative_to(ROOT).as_posix(), sha256=hashlib.sha256(p.read_bytes()).hexdigest()) for p in paths],
                record_count=len(records), records=records)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    rendered = json.dumps(build(), ensure_ascii=False, indent=2) + '\n'
    if args.check:
        assert OUT.read_text(encoding='utf-8') == rendered
    else:
        OUT.write_text(rendered, encoding='utf-8', newline='\n')
    print('ITEM_DROP_AFFIX_RULES_V2_PASS')
