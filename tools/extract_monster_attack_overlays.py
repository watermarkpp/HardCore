"""Exact additional monster spell layers; preserve every body/animation atlas."""
import argparse
import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools/vendor'))
from extract_wil import read_library, decode_sprite

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    combat = json.loads((ROOT / 'assets/data/canonical_monster_combat_source_v1.json').read_text(encoding='utf-8-sig'))['records_by_monster_id']
    # Source library, base, directions, frames, RaceImg, canonical IDs.
    recipes = {
        'maggot_gas': ('Mon3.wil', 1444, 8, 6, 16, [46,60]),
        'wooma_flame': ('Mon4.wil', 1800, 8, 7, 20, [70]),
        'wooma_lightning': ('Mon4.wil', 1900, 8, 6, 21, [76,77,235,236,239]),
        'moth_gas': ('Mon4.wil', 3590, 8, 6, 52, [128]),
        'zombie_lightning': ('Mon5.wil', 350, 16, 6, 40, [79]),
        'zuma_flame': ('Mon7.wil', 1680, 8, 9, 49, [160]),
        'elf_flame': ('Mon18.wil', 821, 8, 5, 55, [146]),
    }
    profiles, bindings = {}, {}
    libraries = {}
    for key, (library, base, directions, count, race, ids) in recipes.items():
        source = ROOT / 'dev_art_sources/reference/mir2_client_raw/Data' / library
        assert source.exists(), f'primary missing: {source}'
        if library not in libraries: libraries[library] = read_library(source)
        data, palette, offsets, _ = libraries[library]
        frames = []
        for direction in range(directions):
            for frame in range(count):
                index = base + direction * 10 + frame
                image, m = decode_sprite(data, offsets[index], palette)
                path = ROOT / f'assets/art/monsters/effects/attack_overlays_v2/{key}_{direction:02}_{frame}.png'
                if args.check:
                    from PIL import Image
                    assert Image.open(path).convert('RGBA').tobytes() == image.tobytes()
                else:
                    path.parent.mkdir(parents=True, exist_ok=True)
                    image.save(path)
                frames.append(dict(path='res://' + path.relative_to(ROOT).as_posix(), source_index=index,
                                   x=m['x'], y=m['y'], empty=image.getbbox() is None,
                                   rgba_sha256=hashlib.sha256(image.tobytes()).hexdigest()))
        for item_id in ids:
            assert combat[str(item_id)]['image'] == race
            bindings[str(item_id)] = key
        profiles[key] = dict(direction_count=directions, frame_count=count, frames=frames,
                             source=dict(path=source.relative_to(ROOT).as_posix(), sha256=hashlib.sha256(data).hexdigest(),
                                         tier='primary', distribution='client.classic_raw_complete',
                                         rule='MirClient/AxeMon.pas TGasKuDeGi.LoadSurface, TSculptureMon.LoadSurface, TWarriorElfMonster.RunFrameAction',
                                         frame_formula=f'{base} + direction * 10 + frame'))
    # King spell: primary lacks both the active mt13 constructor and Mon21.
    # Its precise release remains at primary AxeMon:1577-1578; auxiliary_1
    # Client/PlayScn:1613 and magiceff:441 resolve the missing implementation.
    primary_missing = ROOT / 'dev_art_sources/reference/mir2_client_raw/Data/Mon21.wil'
    assert not primary_missing.exists()
    source = ROOT / 'dev_art_sources/external/mir2opensource_full/Data/Mon21.wil'
    data, palette, offsets, _ = read_library(source)
    king_frames = []
    for frame in range(20):
        image, m = decode_sprite(data, offsets[3580 + frame], palette)
        assert image.getbbox()
        path = ROOT / f'assets/art/monsters/effects/attack_overlays_v2/cow_king_{frame:02}.png'
        if args.check:
            from PIL import Image
            assert Image.open(path).convert('RGBA').tobytes() == image.tobytes()
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            image.save(path)
        king_frames.append(dict(path='res://' + path.relative_to(ROOT).as_posix(), source_index=3580+frame,
                                x=m['x'], y=m['y'], rgba_sha256=hashlib.sha256(image.tobytes()).hexdigest()))
    rule_paths = [ROOT / 'dev_art_sources/reference/original_gameofmir' / part for part in ['MirClient/AxeMon.pas','MirClient/PlayScn.pas','MirClient/magiceff.pas','Client/PlayScn.pas','Client/magiceff.pas']]
    rule_evidence = [dict(path=p.relative_to(ROOT).as_posix(),sha256=hashlib.sha256(p.read_bytes()).hexdigest()) for p in rule_paths]
    fallback = dict(rule_evidence=rule_evidence, primary_missing_path=primary_missing.relative_to(ROOT).as_posix(), primary_query='missing exact Mon21.wil',
                    primary_rule_missing='MirClient/magiceff.pas:461 mt13 constructor and PlayScn.pas:1724 dispatch commented out; active AxeMon.pas:1578 still requests mt13 number 32',
                    auxiliary_rule_paths=['dev_art_sources/reference/original_gameofmir/Client/PlayScn.pas','dev_art_sources/reference/original_gameofmir/Client/magiceff.pas'])
    profiles['cow_king'] = dict(monster_id=224, direction_count=1, frame_count=20, frame_ms=20, frames=king_frames,
                               source=dict(path=source.relative_to(ROOT).as_posix(),sha256=hashlib.sha256(data).hexdigest(),
                                           tier='auxiliary_1', distribution='client.mir2opensource_2013_complete',fallback_evidence=fallback))
    result = dict(contract_id='monster.attack.exact_overlay.v2', client_rule_evidence=rule_evidence, profile_by_monster_id=bindings, profiles=profiles,
                  body_only_ids=[18,62,103,104,168,185], body_only_rule='primary canonical RaceImg19 -> TCatMon; source has no independent spell layer')
    path = ROOT / 'assets/data/monster_attack_overlay_sources_v2.json'
    rendered = json.dumps(result, ensure_ascii=False, indent=2) + '\n'
    if args.check: assert path.read_text(encoding='utf-8') == rendered
    else: path.write_text(rendered,encoding='utf-8',newline='\n')
    print('MONSTER_ATTACK_OVERLAY_SOURCES_PASS profiles=%d body_atlases_unchanged=true' % len(profiles))

if __name__ == '__main__':
    main()
