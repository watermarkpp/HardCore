"""Extract primary client WORDER; no image generation or equipment mutation."""
import argparse
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'dev_art_sources/reference/original_gameofmir/MirClient/Actor.pas'
OUT = ROOT / 'assets/data/equipment_weapon_frame_order.json'


def build():
    text = SOURCE.read_text(encoding='gbk', errors='replace')
    block = text.split('WORDER: Array[0..1, 0..599] of byte = (', 1)[1].split(');', 1)[0]
    block = re.sub(r'//[^\n]*', '', block)
    values = [int(s) for s in re.findall(r'\b[01]\b', block)]
    assert len(values) == 1200
    assert 'm_nWpord := WORDER[m_btSex, m_nCurrentFrame]' in text
    return dict(schema_version=1, contract_id='equipment.weapon.primary_frame_order.v1',
                source=dict(lane='client_rules', tier='primary', distribution='source.original_gameofmir.mirclient',
                            path=SOURCE.relative_to(ROOT).as_posix(), sha256=hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
                            declaration_line=465, consumer_line=3788),
                direction_stride=8, behind_value=0,
                action_starts=dict(idle=0, walk=64, run=128, attack=200, cast=392, hit=472, death=536),
                genders=[values[:600], values[600:]])


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    result = json.dumps(build(), ensure_ascii=False, indent=2) + '\n'
    if args.check:
        assert OUT.read_text(encoding='utf-8') == result
    else:
        OUT.write_text(result, encoding='utf-8', newline='\n')
    print('WEAPON_PRIMARY_FRAME_ORDER_PASS entries=1200')
