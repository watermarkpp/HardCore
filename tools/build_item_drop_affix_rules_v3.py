"""Build versioned original JP rolls; never import candidate base attributes.

Only selected accessory Stdmode fields are read from the user-routed candidate.
Each selected ordinary record must reproduce the formal primary record's combat
ranges, secondary byte meaning, weight, durability and requirements. The whole
custom server is NOT designated a standard source or a gameplay authority.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets/data/item_drop_affix_rules_v3.json'
RULES_DOC = ROOT / 'docs/repair_20260913/JP_EQUIPMENT_RULES.md'
CANDIDATE = 'dev_art_sources/reference/mir2_database_candidates/mylgd_mir2server_176/Mud2/DB/StdItems.DB'
MASTER = 'assets/data/equipment_attribute_master.json'
PRIMARY = 'dev_art_sources/reference/original_gameofmir/M2Server/'
# Explicit identity inventory, reviewed against the selected row IDs, primary
# catalog and original ApplyItemParameters. Runtime never infers a type by name.
SPECIAL_TYPES = {159: 19, 164: 19, 229: 19, 221: 21, 225: 21,
                 174: 24, 176: 24, 180: 24, 181: 24, 230: 24,
                 208: 23, 209: 23, 222: 23, 227: 23}


def source(path, **extra):
    return dict(path=path, sha256=hashlib.sha256((ROOT / path).read_bytes()).hexdigest(), **extra)


def candidate_rows():
    data = (ROOT / CANDIDATE).read_bytes()
    count, header, block = data[33], struct.unpack('>H', data[2:4])[0] * 256, data[5] * 1024
    start = data[:header].find(b'Idx\0Name\0Stdmode\0')
    assert start == 733 and count == 58 and header == 4096
    names = data[start:header].split(b'\0')[:count]
    fields = [(names[i].decode('ascii'), data[120+i*2], data[121+i*2]) for i in range(count)]
    assert all(t in [1, 3, 4] for _, t, _ in fields)
    width, rows = sum(size for _, _, size in fields), []
    for block_start in range(header, len(data), block):
        for offset in range(block_start + 6, min(block_start + block, len(data)) - width + 1, width):
            raw = data[offset:offset + width]
            if not raw.strip(b'\0'):
                break
            cursor, row = 0, {}
            for name, kind, size in fields:
                value = raw[cursor:cursor+size]
                cursor += size
                row[name] = (value.rstrip(b'\0').decode('gbk') if kind == 1 else
                             int.from_bytes(value, 'big') - (1 << (size*8-1)) if value.strip(b'\0') else None)
            rows.append(row)
    assert len(rows) == 371
    return rows


def validate_selected(item, row, mode):
    assert row['Stdmode'] == mode
    for stat in ['dc', 'mc', 'sc']:
        for bound, suffix in [('min', ''), ('max', '2')]:
            assert row[stat.title() + suffix] == item['stats'].get(stat, {}).get(bound, 0), (item['itemId'], stat)
    assert row['Weight'] == item['weight'] and row['DuraMax'] == item['durability'] * 1000
    assert row['Need'] == item['legacyNeed']
    # The user intentionally raised two zero-level accessories to level one.
    assert row['NeedLevel'] == item['legacyNeedLevel'] or (item['itemId'] in [152, 260] and row['NeedLevel'] == 0 and item['legacyNeedLevel'] == 1)
    if mode in [20, 24]:
        assert row['Ac2'] == item.get('accuracy', 0) and row['Mac2'] == item.get('agility', 0)
    elif mode == 19:
        assert row['Ac2'] == item.get('magicEvasionPoints', 0) and row['Mac2'] == item.get('luck', 0)
    elif mode in [22, 26]:
        for stat in ['ac', 'mac']:
            for bound, suffix in [('min', ''), ('max', '2')]:
                assert row[stat.title() + suffix] == item['stats'].get(stat, {}).get(bound, 0)
    if mode in [21, 23]:
        assert row['Ac'] == item.get('attackSpeedTier', 0)
        assert row['Ac2'] == 0 and row['Mac2'] == 0


def roll(stat, trials, rate, gate, *, accept=1, divisor=1, add_before=1, add_after=0, scale=1, signed=False, excluded=False):
    return dict(stat=stat, trials=trials, trial_denominator=rate,
                gate_denominator=gate, gate_accept_count=accept,
                add_before_division=add_before, divisor=divisor, add_after_division=add_after,
                scale=scale, original_speed_sign=signed, excluded=excluded)


def rolls_for(mode):
    if mode == 5:
        return [roll('attack_max',12,15,15), roll('attack_speed_tier',12,15,20,divisor=3,signed=True),
                roll('magic_max',12,15,15), roll('tao_max',12,15,15),
                roll('accuracy',12,15,24,add_before=0,divisor=2,add_after=1),
                roll('durability_bonus_raw',12,12,3,accept=2,scale=2000),
                roll('weapon_strong',12,15,10,add_before=0,divisor=2,add_after=1)]
    if mode in [10, 11]:
        return [roll(s,6,15,30) for s in ['defense_max','magic_defense_max']] + [roll(s,6,20,40) for s in ['attack_max','magic_max','tao_max']] + [roll('durability_bonus_raw',6,10,8,accept=6,scale=2000)]
    secondary = {15: [('defense_max',20,40),('magic_defense_max',20,30)],
                 19: [('anti_magic_points',20,40),('luck',20,40)],
                 20: [('accuracy',30,60),('agility',30,60)],
                 21: [('health_recovery',30,60),('spell_recovery',30,60)],
                 22: [], 23: [('anti_poison',20,40),('poison_recovery',20,40)],
                 24: [('accuracy',30,60),('agility',30,60)],
                 26: [('defense_max',20,20),('magic_defense_max',20,20)]}[mode]
    result = [roll(s,6,r,g,excluded=s.endswith('_recovery')) for s,r,g in secondary]
    result += [roll(s,6,20,30) for s in ['attack_max','magic_max','tao_max']]
    gate, accept = (20,15) if mode in [20,21,24,26] else (4,3)
    return result + [roll('durability_bonus_raw',6,10 if mode == 19 else 12,gate,accept=accept,scale=1000)]


def build():
    master = json.loads((ROOT / MASTER).read_text(encoding='utf-8-sig'))
    assert len(master['records']) == 175
    text = (ROOT / (PRIMARY + 'ItmUnit.pas')).read_text(encoding='gbk')
    assert 'procedure TItem.RandomUpgradeItem' in text and 'UserItem.btValue[6] := nIncp + 10' in text
    assert 'nMonRandomAddValue: 10' in (ROOT / (PRIMARY + 'M2Share.pas')).read_text(encoding='gbk')
    rows, records = candidate_rows(), []
    for item in master['records']:
        category, item_id = item['category'], item['itemId']
        if category in ['项链', '手镯', '戒指']:
            mode = SPECIAL_TYPES.get(item_id, {'项链':20,'手镯':26,'戒指':22}[category])
            matches = [r for r in rows if r['Name'] == item['name']]
            if item_id in [181,196]:
                assert not matches
                assert (item_id == 181 and item.get('agility') == 2) or (item_id == 196 and item['stats']['ac']['max'] == 6)
                evidence = dict(kind='primary_attribute_type_semantics', fields=['category','agility'] if item_id == 181 else ['category','stats.ac'],
                                reason='Original ApplyItemParameters: agility bracelet=24, AC bracelet=26; selected candidate record missing')
            else:
                assert len(matches) == 1
                row = matches[0]
                validate_selected(item, row, mode)
                evidence = dict(kind='user_routed_selected_type_only', source_row_id=row['Idx'], source_field='Stdmode',
                                primary_signature_check='all DC/MC/SC, typed AC/MAC, weight, raw durability, Need and NeedLevel',
                                allowed_master_difference='NeedLevel 0 to 1' if item_id in [152,260] else None)
        else:
            mode = 5 if category == '武器' else 15 if category == '头盔' else 11 if item.get('genderRestriction') == 'female' else 10
            assert category == '武器' or category == '头盔' or category.startswith('盔甲')
            evidence = dict(kind='primary_category_rule_family', fields=['category'], reason='Weapon/armor/helmet original switch; weapon StdMode 5 and 6 share identical rolls')
        records.append(dict(item_id=item_id, item_name=item['name'], original_rule_mode=mode, type_evidence=evidence,
                            supporting_references=item.get('supportingReferences',[]), rolls=rolls_for(mode)))
    return dict(schema_version=3, contract_id='item.drop.affix.rules.v3', record_count=175,
                original_outer_gate=dict(numerator=1,denominator=10), single_player_outer_gate=dict(numerator=1,denominator=2),
                single_player_authorization='User request 2026-09-13: more frequent single-player JP; five times original entry gate, unchanged inner rolls',
                excluded_stats=['health_recovery','spell_recovery','poison_recovery'],
                exclusion_authorization='User 2026-09-13 explicitly excludes three unverified recovery attributes; consume but do not apply their draws',
                maximum_durability_raw=65000,
                source_policy=dict(rule_lane='server_rules',rule_tier='primary',rule_distribution='source.original_gameofmir.server_suite',
                                   type_candidate_scope='100 exact accessory Stdmode fields only; not whole custom database authority'),
                higher_source_missing_evidence=[
                    source(MASTER, result='175 formal records have category; legacy StdMode field missing'),
                    source('assets/data/equipment_service_rules.json',result='concreteStdItemsRecords=0; actual StdItems records explicitly missing'),
                    source('dev_art_sources/reference/mir2_sources/suprcode_crystal/Shared/Data/ItemData.cs',result='ItemInfo serialization uses modern ItemType/RandomStatsId; legacy StdMode field missing'),
                ] + higher_database_evidence(),
                sources=[source(PRIMARY+n,distribution='source.original_gameofmir.server_suite',tier='primary') for n in ['ItmUnit.pas','UsrEngn.pas','M2Share.pas','ObjBase.pas']] +
                        [source('dev_art_sources/reference/original_gameofmir/MirClient/FState.pas',distribution='source.original_gameofmir.mirclient',tier='primary',rule='AntiMagic and AntiPoison raw points display as points * 10 percent')] +
                        [source(CANDIDATE,distribution='user_routed.mylgd_mir2server_176.selected_stdmode',tier='explicit_selected_candidate',
                                restriction='Custom GEE server is rejected as a whole. Only cross-checked ordinary accessory type fields are selected; no base attributes, shapes, extensions or custom rules are imported.')],
                records=records)


def higher_database_evidence():
    policy = json.loads((ROOT / 'assets/data/source_priority_policy.json').read_text(encoding='utf-8-sig'))
    result = []
    for entry in policy['lanes']['server_data']['sources']:
        if not entry['eligible']:
            continue
        root = ROOT / 'dev_art_sources' / entry['rootPrefix']
        # Only item/database filename inventories, no database writes or broad
        # content reads. Crystal serialization is evidenced by ItemData.cs.
        paths = sorted(p for p in root.rglob('*') if p.is_file() and (p.suffix.lower() in ['.db','.mirdb'] or 'stditem' in p.name.lower()))
        assert not any('stditem' in p.name.lower() for p in paths)
        result.append(dict(distribution=entry['distribution'], tier=entry['tier'], root=str(root.relative_to(ROOT)).replace('\\','/'),
                           query='database extensions .DB/.MirDB and exact StdItems filename candidates',
                           result='No legacy StdItems records. Crystal ItemInfo Type/RandomStatsId is not the original StdMode field.' if paths else 'No database or StdItems filename candidates in this source',
                           matches=[source(str(p.relative_to(ROOT)).replace('\\','/')) for p in paths]))
    return result


STAT_LABELS = {'attack_max':'攻击上限','magic_max':'魔法上限','tao_max':'道术上限','defense_max':'防御上限',
               'magic_defense_max':'魔防上限','attack_speed_tier':'速度（可正可负）','accuracy':'准确','agility':'敏捷',
               'weapon_strong':'强度','durability_bonus_raw':'随机持久','anti_magic_points':'远程与魔法躲避',
               'luck':'幸运','anti_poison':'毒物躲避'}


def render_rules_doc(data):
    lines = ['# 小极品装备位置与类型规则', '',
             '本表由 `tools/build_item_drop_affix_rules_v3.py` 与运行时同源生成；包含全部 175 件正式装备。', '',
             '这里的限制只约束新生成的小极品追加属性，不删除装备基础属性，也不重新随机旧存档。狂风戒指、狂风项链自带速度，不意味着戒指或项链可以随机追加速度。', '',
             '- 所有类型只能从各自白名单取属性；列表以外的属性禁止随机出现。攻击、魔法、道术及防御类只增加上限。',
             '- 武器随机速度、强度和准确；盔甲与头盔不能随机得到速度、强度、幸运、准确或敏捷。',
             '- 项链 19 型随机幸运与远程／魔法躲避；20 型随机准确与敏捷；21 型的两种恢复属性暂不启用。',
             '- 手镯 24 型随机准确与敏捷；26 型随机防御与魔防。同一个“手镯”位置仍有两种类型，不能混用。',
             '- 戒指 23 型可随机毒物躲避；22 型不随机这些次要属性。两型都不能随机速度、幸运或远程／魔法躲避。',
             '- 强度减少武器耐久消耗；随机持久增加新装备耐久上限。随机上限增加后仍可正常磨损、维修与存档。',
             '- 生命恢复、魔法恢复、中毒恢复按用户决定排除。', '',
             '概率：原版外层进入率 1/10，单机调整为 1/2（5 倍）；内部独立判定和追加点数分布保留原版。进入判定不代表必有追加属性。不同属性可以同时出现，追加不再限定 +1。随机持久也属于追加结果。', '',
             '原版依据是优先源 `ItmUnit.RandomUpgradeItem`、`ApplyItemParameters` 和耐久结算；候选库只选取经主表逐字段校验的 100 条首饰类型，不采用改版库的基础数值或扩展规则。远程／魔法躲避和速度作用于法术是用户本次单机规则。完整逐来源缺失与哈希证据见生成的规则 JSON。', '',
             '| 装备 ID | 装备 | 类型 | 允许随机追加 |', '|---:|---|---:|---|']
    for record in data['records']:
        allowed = [STAT_LABELS[r['stat']] for r in record['rolls'] if not r['excluded']]
        lines.append(f"| {record['item_id']} | {record['item_name']} | {record['original_rule_mode']} | {'、'.join(allowed)} |")
    return '\n'.join(lines)+'\n'


if __name__ == '__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--check',action='store_true')
    args=parser.parse_args()
    data=build()
    rendered=json.dumps(data,ensure_ascii=False,indent=2)+'\n'
    rules_doc=render_rules_doc(data)
    if args.check:
        assert OUT.read_text(encoding='utf-8') == rendered
        assert RULES_DOC.read_text(encoding='utf-8') == rules_doc
    else:
        OUT.write_text(rendered,encoding='utf-8',newline='\n')
        RULES_DOC.write_text(rules_doc,encoding='utf-8',newline='\n')
    print('ITEM_DROP_AFFIX_RULES_V3_PASS')
