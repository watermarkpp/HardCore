"""Exact primary WMon3 TFlyingAxe/THORNBASE frames, source pixels unchanged."""
import argparse
import hashlib
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools/vendor'))
from extract_wil import read_library, decode_sprite

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    source = ROOT / 'dev_art_sources/reference/mir2_client_raw/Data/Mon3.wil'
    data, palette, offsets, _ = read_library(source)
    source_hash = hashlib.sha256(data).hexdigest()
    profiles = {}
    for key, base, ids in [('axe', 447, [42, 50, 145]), ('thorn', 2967, [174])]:
        frames = []
        for direction in range(16):
            for frame in range(3):
                index = base + direction * 10 + frame
                image, metadata = decode_sprite(data, offsets[index], palette)
                assert image.getbbox(), (key, index)
                path = ROOT / f'assets/art/monsters/effects/projectile_primary_v2/{key}_{direction:02}_{frame}.png'
                if args.check:
                    from PIL import Image
                    assert Image.open(path).convert('RGBA').tobytes() == image.tobytes()
                else:
                    path.parent.mkdir(parents=True, exist_ok=True)
                    image.save(path)
                frames.append(dict(path='res://' + path.relative_to(ROOT).as_posix(), direction=direction, frame=frame,
                                   source_index=index, hot_x=metadata['x'], hot_y=metadata['y'],
                                   rgba_sha256=hashlib.sha256(image.tobytes()).hexdigest()))
        profiles[key] = dict(monster_ids=ids, frame_ms=50, frames_per_direction=3,
                             source=dict(path=source.relative_to(ROOT).as_posix(), sha256=source_hash,
                                         distribution='client.classic_raw_complete', tier='primary',
                                         formula=f'{base} + Dir16 * 10 + frame',
                                         rule='MirClient/AxeMon.pas:608-619; magiceff.pas:554-561,909-941'), frames=frames)
    output = dict(contract_id='monster.projectile.exact_source.v2', profiles=profiles,
                  body_only_monster_ids=[62],
                  body_only_evidence='ID62 canonical race_img=19 -> PlayScn.pas:2174 TCatMon; no flying-effect dispatch. Retain formal attack body; do not invent an arrow.',
                  preserved_arrow_monster_ids=[150,151,152,186,194,206,207])
    path = ROOT / 'assets/data/monster_projectile_exact_sources_v2.json'
    rendered = json.dumps(output, ensure_ascii=False, indent=2) + '\n'
    if args.check:
        assert path.read_text(encoding='utf-8') == rendered
    else:
        path.write_text(rendered, encoding='utf-8', newline='\n')
    print('MONSTER_EXACT_PROJECTILE_PRIMARY_PASS frames=96 axe_ids=42,50,145 thorn_id=174 body_only_id=62')

if __name__ == '__main__':
    main()
