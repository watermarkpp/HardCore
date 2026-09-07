#!/usr/bin/env python3
"""DPV2 V5 build-time repair helpers. No runtime file guessing or hidden overrides.

This module is called explicitly by the existing two DPV2 builders. Its policy
and evidence are versioned build inputs, not a second gameplay probability table.
"""
from __future__ import annotations

from collections import Counter, defaultdict
from fractions import Fraction
from html.parser import HTMLParser
from pathlib import Path
from typing import Any
import copy
import datetime as dt
import hashlib
import json
import math
import re
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
BASE = 'ffcdc76b360d5976eef2ce17a45664ddaf550590'
DATA = 'assets/data/drop/'
POLICY = 'tools/dpv2_repair_v5_policy.json'
REPORT = 'docs/drop/v5/'
SOURCE = 'assets/data/canonical_monster_drop_source_v2.json'
CORRECTIONS = DATA + 'dpv2_21cq_source_corrections_v1.json'
OVERFLOW = DATA + 'dpv2_21cq_overflow_authority_v1.json'
BASELINE = DATA + 'dpv2_direct_baseline_v2.json'
PROVENANCE = DATA + 'dpv2_21cq_source_provenance_v1.json'
EFFECTIVE = DATA + 'dpv2_single_player_effective_probability_v1.json'
AUTHORITY = DATA + 'dpv2_single_player_drop_boost_v1.json'
CLASSIFICATION = DATA + 'dpv2_single_player_item_boost_classification_v1.json'
SOURCE_AUDIT = REPORT + 'source_audit.json'
SOURCE_SEAL = REPORT + 'source_audit.sha256'
INT_MAX = 2147483647
HISTORICAL_SOURCE_HASH = '59338A7E5CAACCC82661E942908CAEA0A4A06CF56402961E4C3E55FB123E4013'


class RepairError(RuntimeError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RepairError(message)


def read(path: str) -> Any:
    return json.loads((ROOT / path).read_text(encoding='utf-8-sig'))


def text_hash(text: str) -> str:
    return hashlib.sha256(text.replace('\r\n', '\n').replace('\r', '\n').encode('utf-8')).hexdigest().upper()


def file_hash(path: str) -> str:
    return text_hash((ROOT / path).read_text(encoding='utf-8-sig'))


def raw_hash(path: str) -> str:
    return hashlib.sha256((ROOT / path).read_bytes()).hexdigest().upper()


def dump(path: str, value: Any) -> None:
    target = ROOT / path
    target.parent.mkdir(parents=True, exist_ok=True)
    tmp = target.with_name(target.name + '.v5tmp')
    tmp.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8', newline='\n')
    tmp.replace(target)


def historical(path: str, sha: str = BASE) -> Any:
    data = subprocess.check_output(['git', 'show', f'{sha}:{path}'], cwd=ROOT)
    return json.loads(data.decode('utf-8-sig'))


def unchanged_json(path: str) -> Any:
    value = read(path)
    require(value == historical(path), f'UNAUTHORIZED_SOURCE_DRIFT:{path}')
    return value


def verified_source_raw_hash() -> str:
    # Legacy builders require checkout-byte hashes; authorize their value only
    # AFTER proving the document equals the pinned immutable Git object.
    unchanged_json(SOURCE)
    return raw_hash(SOURCE)


def verified_global_raw_hash() -> str:
    path = DATA + 'dpv2_global_drop_rate_authority_v1.json'
    unchanged_json(path)
    return raw_hash(path)


def policy() -> dict[str, Any]:
    p = read(POLICY)
    require(p['base_sha'] == BASE and p['review_only'] is True, 'POLICY_CONTRACT')
    require(p['boss_ids'] == [76, 198, 199, 225], 'BOSS_ID_DRIFT')
    return p


def slots_by_uid(baseline: dict[str, Any]) -> dict[str, dict[str, Any]]:
    out = {}
    for profile in baseline['profiles']:
        for slot in profile['slots']:
            uid = slot['slot_uid']
            require(uid not in out, f'DUPLICATE_SLOT:{uid}')
            out[uid] = {'canonical_monster_id': profile['canonical_monster_id'], **slot}
    return out


def checked_fraction(n: Any, d: Any) -> Fraction:
    require(type(n) is int and type(d) is int, 'NON_INTEGER_RATIONAL')
    require(0 < n <= d <= INT_MAX, f'INVALID_RATIONAL:{n}/{d}')
    return Fraction(n, d)


def boosted(base: Fraction, multiplier: int, cap: Fraction) -> Fraction:
    return base if base >= cap else min(base * multiplier, cap)


def rank(row: dict[str, Any]) -> tuple[int, int]:
    return int(row['protected_drop']), int(row['overflow_priority'])


def always_retained(target: dict[str, Any], candidates: list[dict[str, Any]], limit: int = 9) -> bool:
    # All eligible slots have positive probability. Count every possible equal
    # or higher-ranked competitor, not just competitors seen in a simulation.
    return sum(row['slot_uid'] != target['slot_uid'] and rank(row) >= rank(target)
               for row in candidates) < limit


def probability_distribution(probabilities: list[float]) -> list[float]:
    result = [1.0]
    for probability in probabilities:
        nxt = [0.0] * (len(result) + 1)
        for i, value in enumerate(result):
            nxt[i] += value * (1 - probability)
            nxt[i + 1] += value * probability
        result = nxt
    return result


def no_equipment_after_selection(rows: list[dict[str, Any]], probabilities: dict[str, Fraction],
                                 equipment_ids: set[int], limit: int = 9) -> float:
    """Analytic Poisson-binomial + hypergeometric calculation for the real cap.

    The only approximation is IEEE-754 evaluation of this finite analytic sum.
    All probabilities emitted to the game remain positive integer rationals.
    """
    groups = defaultdict(list)
    for row in rows:
        groups[rank(row)].append(row)
    states = [1.0] + [0.0] * limit  # selected non-equipment, no equipment yet
    for key in sorted(groups, reverse=True):
        group = groups[key]
        ep = probability_distribution([float(probabilities[r['slot_uid']]) for r in group
                                       if r.get('canonical_item_id') in equipment_ids])
        np = probability_distribution([float(probabilities[r['slot_uid']]) for r in group
                                       if r.get('canonical_item_id') not in equipment_ids])
        nxt = [0.0] * (limit + 1)
        nxt[limit] = states[limit]
        for used, state in enumerate(states[:-1]):
            if state == 0:
                continue
            remaining = limit - used
            for e, pe in enumerate(ep):
                if pe == 0:
                    continue
                for n, pn in enumerate(np):
                    joint = state * pe * pn
                    if joint == 0:
                        continue
                    if e + n <= remaining:
                        if e == 0:
                            nxt[used + n] += joint
                    elif n >= remaining:
                        keep_none = math.comb(n, remaining) / math.comb(e + n, remaining)
                        nxt[limit] += joint * keep_none
        states = nxt
    return min(1.0, max(0.0, sum(states)))


def denominator_modifier(monster_class: str, item_id: int, equipment_ids: set[int]) -> int:
    if monster_class == 'ordinary':
        if item_id in range(910001, 910007):
            return 6
        if item_id in equipment_ids:
            return 3
    if monster_class in ('elite', 'boss') and item_id in (920014, 920016):
        return 2
    return 1


class TableParser(HTMLParser):
    """Preserve individual table cells; do not flatten unrelated site tables."""
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.tables: list[list[list[str]]] = []
        self.stack: list[dict[str, Any]] = []
        self.headings: list[str] = []
        self.heading: list[str] | None = None

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag in ('title', 'h1', 'h2'):
            self.heading = []
        if tag == 'table':
            self.stack.append({'rows': [], 'row': None, 'cell': None})
        elif self.stack and tag == 'tr':
            self.stack[-1]['row'] = []
        elif self.stack and tag in ('td', 'th'):
            self.stack[-1]['cell'] = []
        elif self.stack and tag == 'br' and self.stack[-1]['cell'] is not None:
            self.stack[-1]['cell'].append('\n')

    def handle_data(self, data: str) -> None:
        if self.heading is not None:
            self.heading.append(data)
        if self.stack and self.stack[-1]['cell'] is not None:
            self.stack[-1]['cell'].append(data)

    def handle_endtag(self, tag: str) -> None:
        if tag in ('title', 'h1', 'h2') and self.heading is not None:
            self.headings.append(''.join(self.heading).strip())
            self.heading = None
        if not self.stack:
            return
        t = self.stack[-1]
        if tag in ('td', 'th') and t['cell'] is not None:
            if t['row'] is not None:
                t['row'].append(re.sub(r'\s+', ' ', ''.join(t['cell'])).strip())
            t['cell'] = None
        elif tag == 'tr' and t['row'] is not None:
            t['rows'].append(t['row'])
            t['row'] = None
        elif tag == 'table':
            self.tables.append(self.stack.pop()['rows'])


def decode_source(raw: bytes, declared: str) -> tuple[str, str]:
    # 21CQ's existing attribute importer documents GB2312/GB18030 fallback.
    choices = list(dict.fromkeys([declared, 'gb2312', 'gb18030', 'utf-8']))
    for encoding in choices:
        try:
            text = raw.decode(encoding, errors='strict')
        except (LookupError, UnicodeError):
            continue
        if '\ufffd' not in text:
            return text, encoding
    raise RepairError('SOURCE_ENCODING_UNVERIFIED')


def parse_drop_table(text: str, expected_name: str) -> list[dict[str, Any]]:
    parser = TableParser()
    parser.feed(text)
    # Exact title/name token, never a prefix match that merges suffix variants.
    title_tokens = [re.split(r'[_|｜\-—]', h)[0].strip() for h in parser.headings]
    require(expected_name in parser.headings or expected_name in title_tokens,
            f'SOURCE_IDENTITY_UNVERIFIED:{expected_name}')
    candidates = []
    for table in parser.tables:
        if not table:
            continue
        header_at = next((i for i, row in enumerate(table[:5])
                          if any(x in ' '.join(row) for x in ('爆率', '掉率', '掉落概率'))
                          and any(x in ' '.join(row) for x in ('物品', '名称', '名字'))), None)
        if header_at is None:
            continue
        header = table[header_at]
        pi = next((i for i, x in enumerate(header) if any(k in x for k in ('爆率', '掉率', '掉落概率'))), None)
        ni = next((i for i, x in enumerate(header) if any(k in x for k in ('物品', '名称', '名字'))), None)
        ai = next((i for i, x in enumerate(header) if x in ('数量', '个数')), None)
        require(pi is not None and ni is not None and pi != ni, 'UNSUPPORTED_DROP_HEADER')
        parsed = []
        for row in table[header_at + 1:]:
            if not any(row):
                continue
            require(max(pi, ni) < len(row), 'INCOMPLETE_DROP_ROW')
            match = re.fullmatch(r'([1-9]\d*)\s*/\s*([1-9]\d*)', row[pi])
            require(match is not None, f'UNSUPPORTED_DROP_PROBABILITY:{row[pi]}')
            n, d = map(int, match.groups())
            checked_fraction(n, d)
            label = row[ni].strip()
            require(bool(label), 'EMPTY_SOURCE_LABEL')
            amount = 1
            if ai is not None:
                require(ai < len(row) and re.fullmatch(r'[1-9]\d*', row[ai]) is not None,
                        'SOURCE_AMOUNT_UNVERIFIED')
                amount = int(row[ai])
            parsed.append({'item': label, 'numerator': n, 'denominator': d, 'amount': amount})
        require(bool(parsed), 'EMPTY_DROP_TABLE_NOT_A_NO_DROP_PROOF')
        candidates.append(parsed)
    require(len(candidates) == 1, f'DROP_TABLE_UNVERIFIED:count={len(candidates)}')
    return candidates[0]


def get_page(monster_id: int, name: str) -> dict[str, Any]:
    relative = REPORT + f'source/monster_{monster_id}.json'
    raw_path = REPORT + f'source/monster_{monster_id}.bin'
    if (ROOT / relative).exists():
        meta = read(relative)
        require(meta.get('monster_id') == monster_id and meta.get('name') == name, 'CACHED_PAGE_IDENTITY_DRIFT')
        if meta.get('status') == 'PARSED':
            require(raw_hash(raw_path) == meta['raw_sha256'], 'CACHED_PAGE_HASH_DRIFT')
        return meta
    url = policy()['source_url_template'].format(monster_id=monster_id)
    meta = {'monster_id': monster_id, 'name': name, 'url': url,
            'retrieved_utc': dt.datetime.now(dt.timezone.utc).isoformat(),
            'status': 'UNVERIFIED', 'parser': 'dpv2-drop-strict-table-v5.0', 'rows': []}
    raw = b''
    try:
        request = urllib.request.Request(url, headers={'User-Agent': 'HardCore-DPV2-audit/5.0'})
        with urllib.request.urlopen(request, timeout=20) as response:
            actual = urllib.parse.urlparse(response.geturl())
            query = urllib.parse.parse_qs(actual.query)
            require(actual.hostname == 'www.21cq.com' and actual.path.lower() == '/mir/mob.aspx'
                    and (query.get('ID') or query.get('id')) == [str(monster_id)], 'SOURCE_REDIRECT_IDENTITY')
            meta['http_status'] = int(response.status)
            meta['declared_charset'] = response.headers.get_content_charset() or 'gb2312'
            raw = response.read(4 * 1024 * 1024 + 1)
            require(len(raw) <= 4 * 1024 * 1024, 'SOURCE_PAGE_TOO_LARGE')
        text, encoding = decode_source(raw, meta['declared_charset'])
        meta['actual_encoding'] = encoding
        meta['rows'] = parse_drop_table(text, name)
        meta['status'] = 'PARSED'
    except (OSError, ValueError, RepairError, urllib.error.URLError) as exc:
        meta['blocker'] = str(exc)
    finally:
        if raw:
            path = ROOT / raw_path
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(raw)
            meta['raw_sha256'] = hashlib.sha256(raw).hexdigest().upper()
            meta['raw_path'] = raw_path
        dump(relative, meta)
    return meta


def source_audit() -> dict[str, Any]:
    """Network read/audit only. No gameplay files are changed here."""
    p = policy()
    source = unchanged_json(SOURCE)
    baseline = unchanged_json(BASELINE)
    unchanged_json(CORRECTIONS)
    mapping = unchanged_json(DATA + 'dpv2_21cq_item_mapping_v1.json')
    labels = {r['source_item_label']: r for r in mapping['records']}
    profiles = {r['canonical_monster_id']: r for r in baseline['profiles']}
    source_records = {r['stable_monster_id']: r for r in source['records']}
    books = set(p['book_ids'])
    result = {'schema': 'hardcore.dpv2.source_audit.v5', 'base_sha': BASE,
              'identities': [], 'slots': [], 'proposed_corrections': [], 'verified_book_monster_ids': [],
              'blockers': [], 'raw_source_sha256': raw_hash(SOURCE)}
    for mid, profile in sorted(profiles.items(), key=lambda x: (x[0] != 141, x[0])):
        if not profile['runtime_allowed']:
            continue
        old = source_records[mid]
        identity = {'monster_id': mid, 'name': profile['canonical_monster_name'],
                    'drop_enabled': profile['drop_enabled'], 'slot_count': len(profile['slots']),
                    'source_status': 'UNVERIFIED'}
        result['identities'].append(identity)
        if profile['baseline_origin'] == 'PROJECT_EXTENSION':
            identity['source_status'] = 'PROJECT_EXTENSION'
            continue
        if not profile['drop_enabled']:
            identity['source_status'] = 'EXPLICIT_NON_LOOT'
            continue
        print(f'DPV2_V5_SOURCE monster={mid} name={old["name"]}', flush=True)
        page = get_page(mid, old['name'])
        identity['source_url'] = page['url']
        if page['status'] != 'PARSED':
            identity['blocker'] = page.get('blocker', 'UNVERIFIED')
            result['blockers'].append({'monster_id': mid, 'status': 'UNVERIFIED', 'reason': identity['blocker']})
            for row in old['rows']:
                result['slots'].append({'monster_id': mid, 'slot_index': row['slot_index'],
                                        'item': row['item'], 'status': 'UNVERIFIED'})
            continue
        local = defaultdict(list)
        remote = defaultdict(list)
        def reward_key(label: str, amount: int, source_gold: int | None = None) -> tuple[str, int, int]:
            m = labels.get(label)
            require(m is not None, f'UNMAPPED_SOURCE_ITEM:{mid}:{label}')
            if m['reward_kind'] == 'gold':
                return 'gold', 0, source_gold if source_gold is not None else amount
            require(amount == 1, f'UNSUPPORTED_ITEM_AMOUNT:{mid}:{label}:{amount}')
            return 'item', int(m['canonical_item_id']), 1
        try:
            for row in old['rows']:
                local[reward_key(row['item'], 1, row.get('gold'))].append(row)
            for row in page['rows']:
                remote[reward_key(row['item'], row['amount'])].append(row)
        except RepairError as exc:
            identity['blocker'] = str(exc)
            result['blockers'].append({'monster_id': mid, 'status': 'UNVERIFIED', 'reason': str(exc)})
            continue
        all_complete = set(local) == set(remote)
        books_complete = True
        for key in sorted(set(local) | set(remote)):
            left, right = local[key], remote[key]
            if len(left) != len(right):
                all_complete = False
                if key[1] in books:
                    books_complete = False
                status = 'DUPLICATE_COUNT_DIFFERENCE' if left and right else ('EXTRA_LOCAL_REWARD' if left else 'MISSING_SOURCE_REWARD')
                result['slots'].append({'monster_id': mid, 'reward_key': list(key), 'status': status,
                                        'local_count': len(left), 'source_count': len(right)})
                result['blockers'].append({'monster_id': mid, 'reward_key': list(key), 'status': status})
                continue
            # Identical occurrences may be permuted without changing the multiset.
            # First consume exact probability matches, then only one unambiguous
            # residual pair is auto-corrected. Multiple residual pairs are BLOCKED.
            remaining = list(right)
            mismatches = []
            for row in left:
                match = next((r for r in remaining if row['chance'] == f"{r['numerator']}/{r['denominator']}"), None)
                if match is not None:
                    remaining.remove(match)
                    result['slots'].append({'monster_id': mid, 'slot_index': row['slot_index'], 'status': 'MATCH'})
                else:
                    mismatches.append(row)
            if not mismatches:
                continue
            if len(mismatches) != 1 or len(remaining) != 1:
                all_complete = False
                if key[1] in books:
                    books_complete = False
                result['blockers'].append({'monster_id': mid, 'reward_key': list(key), 'status': 'AMBIGUOUS_OCCURRENCE_MATCH'})
                continue
            row, replacement = mismatches[0], remaining[0]
            prior = next((c for c in historical(CORRECTIONS)['corrections'] if c['stable_monster_id'] == mid and c['source_slot_index'] == row['slot_index']), None)
            if prior is not None:
                if Fraction(prior['corrected_base_numerator'], prior['corrected_base_denominator']) == Fraction(replacement['numerator'], replacement['denominator']):
                    result['slots'].append({'monster_id': mid, 'slot_index': row['slot_index'], 'status': 'MATCH_EXISTING_CORRECTION'})
                    continue
                all_complete = False
                if key[1] in books:
                    books_complete = False
                result['blockers'].append({'monster_id': mid, 'slot_index': row['slot_index'], 'status': 'SOURCE_CONFLICT_WITH_PRIOR_CORRECTION'})
                continue
            correction = {
                'correction_id': f"v5.21cq.m{mid}.{row['slot_index']}",
                'stable_monster_id': mid, 'source_monster_name': old['name'],
                'source_line_number': row['line_number'], 'source_slot_index': row['slot_index'],
                'source_item_label': row['item'], 'original_chance': row['chance'],
                'corrected_base_numerator': replacement['numerator'],
                'corrected_base_denominator': replacement['denominator'],
                'reason': 'SOURCE_CORRECTION_21CQ_VERIFIED_EXACT_REWARD_OCCURRENCE',
                'evidence': {'url': page['url'], 'retrieved_on': page['retrieved_utc'],
                             'raw_path': page['raw_path'], 'raw_sha256': page['raw_sha256'],
                             'reported_rule': f"{replacement['numerator']}/{replacement['denominator']} {row['item']}",
                             'authority': 'FROZEN_21CQ_COMPLETE_TABLE'}
            }
            result['proposed_corrections'].append(correction)
            result['slots'].append({'monster_id': mid, 'slot_index': row['slot_index'], 'status': 'WRONG_PROBABILITY',
                                    'old': row['chance'], 'new': f"{replacement['numerator']}/{replacement['denominator']}"})
        identity['source_status'] = 'VERIFIED' if all_complete else 'PARTIAL'
        if books_complete and any(k[1] in books for k in local):
            result['verified_book_monster_ids'].append(mid)
        time.sleep(0.20)
    require(len(result['identities']) == 153, 'RUNTIME_IDENTITY_COVERAGE_DRIFT')
    result['summary'] = dict(Counter(r['source_status'] for r in result['identities']))
    dump(SOURCE_AUDIT, result)
    (ROOT / SOURCE_SEAL).write_text(file_hash(SOURCE_AUDIT) + '\n', encoding='ascii')
    return result


def audited_source() -> dict[str, Any]:
    require((ROOT / SOURCE_AUDIT).exists(), 'SOURCE_AUDIT_NOT_RUN')
    require(file_hash(SOURCE_AUDIT) == (ROOT / SOURCE_SEAL).read_text().strip(), 'SOURCE_AUDIT_SEAL_DRIFT')
    result = read(SOURCE_AUDIT)
    require(result['base_sha'] == BASE, 'SOURCE_AUDIT_BASE_DRIFT')
    for correction in result['proposed_corrections']:
        evidence = correction['evidence']
        require(raw_hash(evidence['raw_path']) == evidence['raw_sha256'], 'SOURCE_EVIDENCE_HASH_DRIFT')
    return result


def approved_corrections() -> dict[str, Any]:
    original = historical(CORRECTIONS)
    result = copy.deepcopy(original)
    existing = {r['correction_id'] for r in result['corrections']}
    for row in audited_source()['proposed_corrections']:
        require(row['correction_id'] not in existing, 'DUPLICATE_CORRECTION_ID')
        result['corrections'].append(row)
        existing.add(row['correction_id'])
    source = {r['stable_monster_id']: r for r in unchanged_json(SOURCE)['records']}
    for target in policy()['armor_targets']:
        mid = target['monster_id']
        slot_index = target['slot_uid'].split('.')[-1]
        row = next(r for r in source[mid]['rows'] if r['slot_index'] == slot_index)
        require(row['item'] == target['source_item_name'], f'ARMOR_SOURCE_IDENTITY:{mid}')
        # Explicit project override is separate from any 21CQ correction.
        result['corrections'] = [r for r in result['corrections']
                                 if not (r['stable_monster_id'] == mid and r['source_slot_index'] == slot_index)]
        result['corrections'].append({
            'correction_id': f'v5.user_armor.m{mid}.{slot_index}', 'stable_monster_id': mid,
            'source_monster_name': source[mid]['name'], 'source_line_number': row['line_number'],
            'source_slot_index': slot_index, 'source_item_label': row['item'], 'original_chance': row['chance'],
            'corrected_base_numerator': 1, 'corrected_base_denominator': 60,
            'reason': 'USER_AUTHORIZED_OVERRIDE_NEW_ARMOR_INDEPENDENT_1_OVER_60',
            'evidence': {'authority': 'USER_V4_SECTION_15', 'policy_path': POLICY, 'policy_sha256_lf': file_hash(POLICY)}
        })
    return result


def load_corrections_for_builder(module: Any, source: dict[str, Any]) -> dict[tuple[Any, ...], dict[str, Any]]:
    unchanged_json(SOURCE)
    actual = read(CORRECTIONS)
    require(actual == approved_corrections(), 'CORRECTION_NOT_IN_APPROVED_LEDGER')
    require(actual['source']['sha256'] == HISTORICAL_SOURCE_HASH, 'HISTORICAL_SOURCE_BINDING_CHANGED')
    result = {}
    for row in actual['corrections']:
        key = (row['stable_monster_id'], row['source_line_number'], row['source_slot_index'],
               row['source_item_label'], row['original_chance'])
        require(key not in result, 'DUPLICATE_CORRECTION_KEY')
        checked_fraction(row['corrected_base_numerator'], row['corrected_base_denominator'])
        result[key] = row
    return result


def approved_overflow() -> dict[str, Any]:
    p = policy()
    result = historical(OVERFLOW)
    names = {str(r['canonical_item_id']): r['canonical_item_name'] for r in result['records']}
    for dictionary in ('book_names', 'progression_equipment_names'):
        for item, expected in p[dictionary].items():
            require(names.get(item) == expected, f'EXACT_ITEM_ID_NAME_MISMATCH:{item}:{expected}')
    armor = {r['source_item_id'] for r in p['armor_targets']}
    changes = []
    for row in result['records']:
        item = row['canonical_item_id']
        before = [row['protected_drop'], row['overflow_priority']]
        after = before[:]
        reason = ''
        if item in armor:
            after = [True, 2000]
            reason = 'USER_TARGET_ARMOR_ROLL_MUST_SURVIVE_9_SLOT_CAP'
        elif item in p['ordinary_recovery_ids']:
            after = [False, 200]
            reason = 'COMMON_RECOVERY_MUST_NOT_EVICT_PROGRESSION'
        elif item in p['book_ids']:
            # Preserve already stronger protection; give low books no promotion.
            if row['protected_drop'] or item in p['explicit_high_book_ids']:
                after = [True, max(800, row['overflow_priority'])]
                reason = 'EXISTING_PROTECTED_BOOK_RETENTION_FLOOR'
        elif item in p['progression_equipment_ids']:
            after = [True, max(600, row['overflow_priority'])]
            reason = 'EXACT_PROGRESS_EQUIPMENT_RETENTION_FLOOR'
        if after != before:
            row['protected_drop'], row['overflow_priority'] = after
            row['reason'] = reason
            changes.append({'canonical_item_id': item, 'name': row['canonical_item_name'],
                            'before': before, 'after': after, 'reason': reason})
        require(row['probability_effect'] == 'NONE', 'PRIORITY_PROBABILITY_COUPLING')
    result['summary']['protected_item_records'] = sum(r['protected_drop'] for r in result['records'])
    result['summary']['priority_counts'] = {str(k): v for k, v in sorted(Counter(r['overflow_priority'] for r in result['records']).items())}
    result['repair_v5'] = {'policy_path': POLICY, 'policy_sha256_lf': file_hash(POLICY), 'changes': changes}
    return result


def overflow_for_builder(module: Any, item_mapping: dict[str, Any]) -> dict[str, Any]:
    actual = read(OVERFLOW)
    expected = approved_overflow()
    require(actual == expected, 'OVERFLOW_AUTHORITY_NOT_APPROVED')
    ids = {r['canonical_item_id'] for r in item_mapping['records'] if r['reward_kind'] == 'item'}
    require(ids == {r['canonical_item_id'] for r in actual['records']}, 'OVERFLOW_IDENTITY_CLOSURE')
    return actual


def expected_repaired_slots(frozen: dict[str, Any]) -> dict[str, dict[str, Any]]:
    out = slots_by_uid(frozen)
    correction_by_uid = {f"dpv2.direct.m{r['stable_monster_id']}.{r['source_slot_index']}": r
                         for r in approved_corrections()['corrections']}
    retention = {r['canonical_item_id']: r for r in approved_overflow()['records']}
    for uid, row in out.items():
        if uid in correction_by_uid:
            c = correction_by_uid[uid]
            row['base_numerator'] = c['corrected_base_numerator']
            row['base_denominator'] = c['corrected_base_denominator']
        if 'canonical_item_id' in row:
            item = retention[row['canonical_item_id']]
            row['protected_drop'], row['overflow_priority'] = item['protected_drop'], item['overflow_priority']
    return out


def compare_existing_for_builder(module: Any, current_slots: list[dict[str, Any]]) -> dict[str, Any]:
    frozen = module.load_baseline_at_freeze()
    original = module.flatten_slots(frozen)
    require(len(original) == module.BASELINE_FREEZE_SLOT_COUNT, 'HISTORICAL_CARDINALITY_DRIFT')
    require(module.slot_set_hash(original) == module.BASELINE_FREEZE_SLOT_SHA256, 'HISTORICAL_FREEZE_HASH_DRIFT')
    expected = expected_repaired_slots(frozen)
    current = {r['slot_uid']: r for r in current_slots}
    original_by_uid = {r['slot_uid']: r for r in original}
    changes = 0
    for uid, allowed in expected.items():
        allowed = {k: v for k, v in allowed.items() if k != 'canonical_monster_id'}
        require(current.get(uid) == allowed, f'UNAUTHORIZED_OLD_SLOT_DRIFT:{uid}')
        changes += int(original_by_uid[uid] != current[uid])
    full_expected = expected_repaired_slots(historical(BASELINE))
    require(set(current) == set(full_expected), 'FULL_BASE_SLOT_UID_DRIFT')
    for uid, allowed in full_expected.items():
        require(current[uid] == {k: v for k, v in allowed.items() if k != 'canonical_monster_id'}, f'UNAUTHORIZED_SLOT_DRIFT:{uid}')
    return {'base_sha': module.BASELINE_FREEZE_SHA, 'base_slot_count': len(original),
            'base_slot_sha256': module.slot_set_hash(original), 'existing_slot_drift': 0,
            'drift_semantics': 'UNAUTHORIZED_DRIFT_ONLY', 'authorized_repair_changed_slots': changes,
            'repair_reference_sha': BASE}


def validate_spb_inputs(module: Any, baseline: dict[str, Any], current_slots: list[dict[str, Any]]) -> dict[str, Any]:
    unchanged_json(SOURCE)
    require(slots_by_uid(baseline) == expected_repaired_slots(historical(BASELINE)), 'REPAIRED_BASELINE_NOT_APPROVED')
    old_profiles = historical(BASELINE)['profiles']
    require([{k: v for k, v in r.items() if k != 'slots'} for r in baseline['profiles']] ==
            [{k: v for k, v in r.items() if k != 'slots'} for r in old_profiles], 'PROFILE_IDENTITY_DRIFT')
    provenance = read(PROVENANCE)
    original = historical(PROVENANCE)
    expected = copy.deepcopy(original)
    fixes = {(r['stable_monster_id'], r['source_slot_index']): r for r in approved_corrections()['corrections']}
    for r in expected['records']:
        c = fixes.get((r['source_monster_id'], r['source_slot_index']))
        if c:
            r['correction_id'] = c['correction_id']
            r['effective_base_numerator'] = c['corrected_base_numerator']
            r['effective_base_denominator'] = c['corrected_base_denominator']
    require(provenance['records'] == expected['records'], 'PROVENANCE_RECORD_DRIFT')
    require(len(current_slots) == 6809, 'SPB_SLOT_COUNT_DRIFT')
    old = slots_by_uid(historical(BASELINE))
    changed = sum(r != old[u] for u, r in slots_by_uid(baseline).items())
    return {'base_sha': BASE, 'source_sha256_raw': HISTORICAL_SOURCE_HASH,
            'direct_baseline_sha256_raw': file_hash(BASELINE), 'source_provenance_sha256_raw': file_hash(PROVENANCE),
            'direct_slot_count': 6809, 'direct_slot_ledger_sha256': module.ledger_sha256(current_slots),
            'direct_slot_ledger_fields': list(module.LEDGER_FIELDS),
            'source_drift': 0, 'base_probability_drift': 0, 'slot_uid_drift': 0,
            'reward_identity_drift': 0, 'provenance_drift': 0, 'protected_priority_origin_drift': 0,
            'duplicate_slot_collapse': 0, 'repair_authorized_changed_slots': changed,
            'repair_drift_semantics': 'UNAUTHORIZED_DRIFT_ONLY', 'repair_hash_normalization': 'UTF8_LF',
            'repair_policy_sha256_lf': file_hash(POLICY), 'source_audit_sha256_lf': file_hash(SOURCE_AUDIT)}


def finalize_spb(module: Any, authority: dict[str, Any], effective: dict[str, Any], baseline: dict[str, Any]) -> None:
    p = policy()
    audit = audited_source()
    classes = {r['monster_id']: r['classification'] for r in unchanged_json('assets/data/runtime/canonical_monster_catalog.json')['entries']}
    classifications = unchanged_json(CLASSIFICATION)['records']
    item_classes = {r['canonical_item_id']: r['classification'] for r in classifications}
    equipment_ids = {i for i, c in item_classes.items() if c == 'EQUIPMENT'}
    profiles = {r['canonical_monster_id']: r for r in baseline['profiles']}
    records = {r['slot_uid']: r for r in effective['records']}
    base_slots = slots_by_uid(baseline)
    verified = set(audit['verified_book_monster_ids'])
    source_status = {r['monster_id']: r['source_status'] for r in audit['identities']}
    allow = {}
    for entry in p['boss_allowlist']:
        uid = entry['slot_uid']
        require(uid in records and records[uid].get('canonical_item_id') == entry['canonical_item_id']
                and records[uid]['canonical_monster_id'] == entry['monster_id'], f'BOSS_ALLOWLIST_SLOT_DRIFT:{uid}')
        require(entry['canonical_item_id'] in equipment_ids and entry['monster_id'] in p['boss_ids'], 'BOSS_ALLOWLIST_KIND')
        allow[uid] = entry
    effective_probs = {}
    for uid, row in records.items():
        initial = checked_fraction(row['effective_numerator'], row['effective_denominator'])
        mid, item = row['canonical_monster_id'], row.get('canonical_item_id', -1)
        rule = 'NONE'
        final = initial
        if item in p['book_ids'] and mid in verified and mid not in range(235, 241):
            role = classes[mid]
            if role in ('ordinary', 'elite', 'boss'):
                final = boosted(checked_fraction(row['base_numerator'], row['base_denominator']),
                                5 if role == 'ordinary' else 25, Fraction(1, 100 if role == 'ordinary' else 20))
                rule = 'BOOK_ORDINARY' if role == 'ordinary' else 'BOOK_ELITE_BOSS'
        row['repair_v5_rule'] = rule
        row['repair_v5_pre_numerator'], row['repair_v5_pre_denominator'] = initial.numerator, initial.denominator
        effective_probs[uid] = final
    woma_rows = [r for r in effective['records'] if r['canonical_monster_id'] == 76]
    k = Fraction(1)
    k_status = 'BLOCKED_SOURCE_UNVERIFIED'
    target = Fraction(*p['boss_no_equipment_target'])
    cap = Fraction(*p['boss_per_slot_ceiling'])
    calibration_input = dict(effective_probs)  # Never recalibrate on already-multiplied rows.
    # No K is applied to any of the four bosses until all three direct-source
    # target tables are verified. 225 is a user-authorized project extension.
    def evaluate(multiplier: Fraction) -> float:
        probabilities = {}
        for r in woma_rows:
            uid = r['slot_uid']
            initial = calibration_input[uid]
            current = min(initial * multiplier, max(initial, cap)) if uid in allow else initial
            probabilities[uid] = current / denominator_modifier(classes[76], r.get('canonical_item_id', -1), equipment_ids)
        return no_equipment_after_selection(woma_rows, probabilities, equipment_ids)
    before = evaluate(Fraction(1))
    if all(source_status.get(i) == 'VERIFIED' for i in (76, 198, 199)):
        if before < float(target) - p['boss_no_equipment_tolerance']:
            k_status = 'BLOCKED_TARGET_ALREADY_EXCEEDED_NO_NERF_AUTHORIZED'
        elif evaluate(Fraction(1000)) > float(target) + p['boss_no_equipment_tolerance']:
            k_status = 'BLOCKED_TARGET_UNREACHABLE_UNDER_EXISTING_ALLOWLIST_AND_CAP'
        else:
            low, high = 1.0, 1000.0
            for _ in range(60):
                middle = (low + high) / 2
                if evaluate(Fraction(middle)) > float(target):
                    low = middle
                else:
                    high = middle
            candidate = Fraction((low + high) / 2).limit_denominator(p['boss_k_max_denominator'])
            if abs(evaluate(candidate) - float(target)) <= p['boss_no_equipment_tolerance']:
                k, k_status = candidate, 'CALIBRATED_POST_SELECTION'
            else:
                k_status = 'BLOCKED_RATIONAL_CALIBRATION_TOLERANCE'
    if k_status == 'CALIBRATED_POST_SELECTION':
        for uid in allow:
            initial = effective_probs[uid]
            product = initial * k
            require(product.numerator <= INT_MAX and product.denominator <= INT_MAX, f'BOSS_INTERMEDIATE_INT32:{uid}')
            effective_probs[uid] = min(product, max(initial, cap))
            records[uid]['repair_v5_rule'] = 'BOSS_K'
    armor_proofs = []
    for target_row in p['armor_targets']:
        uid = target_row['slot_uid']
        row = records[uid]
        require(row.get('canonical_item_id') == target_row['source_item_id'], 'ARMOR_IDENTITY_DRIFT')
        require(Fraction(row['base_numerator'], row['base_denominator']) == Fraction(1, 60), 'ARMOR_BASE_NOT_1_OVER_60')
        candidates = profiles[target_row['monster_id']]['slots']
        require(always_retained(row, candidates), f'ARMOR_RETENTION_NOT_PROVEN:{uid}')
        row['repair_v5_rule'] = 'ARMOR_BASE_1_OVER_60'
        effective_probs[uid] = Fraction(1, 60)
        armor_proofs.append({'slot_uid': uid, 'canonical_item_id': target_row['source_item_id'],
                             'draw': '1/60', 'max_equal_or_higher_competitors': sum(
                                 r['slot_uid'] != uid and rank(r) >= rank(row) for r in candidates),
                             'selected_given_hit': '1', 'final': '1/60'})
    for uid, fraction in effective_probs.items():
        row = records[uid]
        modifier = denominator_modifier(classes[row['canonical_monster_id']], row.get('canonical_item_id', -1), equipment_ids)
        require(0 < fraction.numerator <= fraction.denominator <= INT_MAX // modifier,
                f'RUNTIME_INT32_RATIONAL_OVERFLOW:{uid}:{fraction}')
        row['effective_numerator'], row['effective_denominator'] = fraction.numerator, fraction.denominator
        row['repair_v5_final_numerator'], row['repair_v5_final_denominator'] = fraction.numerator, fraction.denominator
        if row['repair_v5_rule'] != 'NONE':
            row['formula_reason_code'] += '|' + row['repair_v5_rule']
    contract = {'revision': 5, 'policy_sha256_lf': file_hash(POLICY), 'source_audit_sha256_lf': file_hash(SOURCE_AUDIT),
                'book_item_ids': p['book_ids'], 'verified_book_monster_ids': sorted(verified),
                'boss_allowed_monster_ids': p['boss_ids'], 'boss_allowed_slot_uids': sorted(allow),
                'boss_k_enabled': k_status == 'CALIBRATED_POST_SELECTION',
                'boss_k_numerator': k.numerator, 'boss_k_denominator': k.denominator,
                'boss_slot_cap_numerator': 1, 'boss_slot_cap_denominator': 4,
                'armor_slot_uids': [x['slot_uid'] for x in p['armor_targets']],
                'base_stage_metadata': 'boost_policy, multiplier, ceiling_applied and legacy invariants describe the original SPB stage; repair_v5_rule describes the explicitly validated final stage',
                'hash_normalization': 'UTF8_LF'}
    authority['repair_v5_contract'] = copy.deepcopy(contract)
    effective['repair_v5_contract'] = copy.deepcopy(contract)
    for document in (authority, effective):
        document['source_bindings']['item_boost_classification_sha256_raw'] = file_hash(CLASSIFICATION)
        document['source_bindings']['global_drop_rate_sha256_raw'] = file_hash(DATA + 'dpv2_global_drop_rate_authority_v1.json')
        document['summary']['repair_v5_rule_counts'] = dict(Counter(r['repair_v5_rule'] for r in records.values()))
        document['summary']['repair_v5_formula_mismatch'] = 0
    authority['probability_contract']['formula'] += '; then explicit repair_v5_contract per-slot book/boss/armor rules'
    balance = {'k_status': k_status, 'k': str(k), 'woma_no_equipment_before': before,
               'woma_no_equipment_after': evaluate(k), 'armor_retention_proof': armor_proofs,
               'source_blockers': audit['blockers'], 'books_enabled_monsters': sorted(verified),
               'rule_counts': authority['summary']['repair_v5_rule_counts'],
               'SPB_OFF_definition': 'GameData base probability at global1x; existing loot-service class denominator modifiers remain active and are tested separately.'}
    dump(REPORT + 'balance.json', balance)
    write_retention_audit()


def render_import_audit_v5(module: Any, audit: dict[str, Any]) -> str:
    m = audit['metrics']
    return ('# DPV2 V5 logical-source compile report\n\n'
            'This is not a claim that all external 21CQ pages were verified.\n'
            f"Raw source rows: {m['logical_source_rows']}\n\n"
            f"Applied explicit corrections (including user armor overrides): {m['explicitly_corrected_rows']}\n\n"
            f"Malformed tokens: {m['source_invalid_probability_rows']}\n\n"
            f"Uncorrected malformed tokens: {m['uncorrected_invalid_probability_rows']}\n\n"
            'Historical raw source is retained. External coverage and blockers: docs/drop/v5/source_audit.json.\n')


def write_retention_audit() -> None:
    old = {r['canonical_item_id']: r for r in historical(OVERFLOW)['records']}
    revised = approved_overflow()
    slots = slots_by_uid(read(BASELINE))
    classification = {r['canonical_item_id']: r for r in unchanged_json(CLASSIFICATION)['records']}
    policy_data = policy()
    medicine_ids = set(policy_data['ordinary_recovery_ids'])
    new_by_id = {r['canonical_item_id']: r for r in revised['records']}
    relevant = set(policy_data['progression_equipment_ids']) | {
        item for item in policy_data['book_ids'] if old[item]['protected_drop'] or item in policy_data['explicit_high_book_ids']}
    records = []
    for item, updated in new_by_id.items():
        appears = [r for r in slots.values() if r.get('canonical_item_id') == item]
        before_bad = item in relevant and any(rank(old[m]) >= rank(old[item]) for m in medicine_ids)
        after_bad = item in relevant and any(rank(new_by_id[m]) >= rank(updated) for m in medicine_ids)
        require(not after_bad, f'FORCED_VALUE_PRIORITY_FAILURE:{item}')
        records.append({'canonical_item_id': item, 'name': updated['canonical_item_name'],
                        'classification': classification[item]['classification'],
                        'before': [old[item]['protected_drop'], old[item]['overflow_priority']],
                        'after': [updated['protected_drop'], updated['overflow_priority']],
                        'appears_in_monsters': sorted({r['canonical_monster_id'] for r in appears}),
                        'slot_count': len(appears),
                        'rarest_base_fraction': str(min(Fraction(r['base_numerator'], r['base_denominator']) for r in appears)),
                        'ordinary_recovery_can_evict_before': bool(before_bad),
                        'ordinary_recovery_can_evict_after': bool(after_bad),
                        'probability_effect': 'NONE',
                        'test_semantics': 'one key reward against any number of ordinary recovery candidates; equal high-value competition remains allowed'})
    require(len(records) == 233, 'RETENTION_AUDIT_NOT_233')
    dump(REPORT + 'overflow_audit.json', {'items_audited': 233, 'records': records,
                                        'changed_items': revised['repair_v5']['changes']})


def render_parity_report_v5(*arguments: Any, **keywords: Any) -> str:
    values = list(arguments) + list(keywords.values())
    baselines = [value for value in values if isinstance(value, dict) and value.get('schema') == 'hardcore.dpv2.direct_monster_drop_baseline.v2']
    require(len(baselines) == 1, 'PARITY_REPORT_BASELINE_ARGUMENT')
    compiled = slots_by_uid(baselines[0])
    before = slots_by_uid(historical(BASELINE))
    expected = expected_repaired_slots(historical(BASELINE))
    require(compiled == expected, 'PARITY_REPORT_UNAUTHORIZED_DRIFT')
    source_changed = sum((r['base_numerator'], r['base_denominator']) != (before[uid]['base_numerator'], before[uid]['base_denominator']) for uid, r in compiled.items())
    retention_changed = sum(rank(r) != rank(before[uid]) for uid, r in compiled.items())
    return ('# DPV2 V5 compiled baseline parity\n\n'
            f'Pinned task source commit: `{BASE}`.\n\n'
            f'Compiled slots: {len(compiled)}; authorized probability changes: {source_changed}; authorized retention changes: {retention_changed}.\n\n'
            'Unauthorized slot, reward, duplicate-count and profile drift: 0. This is NOT a claim that no authorized change occurred.\n\n'
            'Only frozen 21CQ corrections and six explicitly authorized clothing rules alter source probabilities.\n\n'
            'External verification coverage: `docs/drop/v5/source_audit.json`.\n\n'
            'Runtime SPB-OFF and selector tests have separate statuses; a compiler parity check is not an APK test.\n')
