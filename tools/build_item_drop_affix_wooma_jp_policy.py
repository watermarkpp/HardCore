#!/usr/bin/env python3
"""Generate v4 JP event gate and bounded conditional sampling from frozen v3 rolls."""
from __future__ import annotations
import argparse, hashlib, json
from collections import defaultdict
from fractions import Fraction
from math import comb
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT/'assets/data/item_drop_affix_wooma_jp_policy.source.json'
V3=ROOT/'assets/data/item_drop_affix_rules_v3.json'
TIERS=ROOT/'assets/data/ui/item_name_rarity_policy_v2.json'
MASTER=ROOT/'assets/data/equipment_attribute_master.json'
OUT=ROOT/'assets/data/item_drop_affix_wooma_jp_policy.runtime.json'
# Exact binary64/JSON integers and int64, using independent 26+27 bits.
RUNTIME_DENOM=1<<53

def read(path): return json.loads(path.read_text(encoding='utf-8-sig'))
def fraction_text(value): return f'{value.numerator}/{value.denominator}'
def fingerprint(path): return hashlib.sha256(path.read_bytes().replace(b'\r\n',b'\n')).hexdigest().upper()
def rounded_tick(probability):
    value=probability*RUNTIME_DENOM
    return (2*value.numerator+value.denominator)//(2*value.denominator)

def outcome_distribution(rule):
    """Aggregate binomial, gate and speed sign; excluded outcomes stay zero."""
    if rule['excluded']: return {0:Fraction(1)}
    n,d=rule['trials'],rule['trial_denominator']
    gate=Fraction(rule['gate_accept_count'],rule['gate_denominator'])
    result=defaultdict(Fraction); result[0]=1-gate
    for k in range(n+1):
        value=((k+rule['add_before_division'])//rule['divisor']+rule['add_after_division'])*rule['scale']
        probability=Fraction(comb(n,k)*(d-1)**(n-k),d**n)*gate
        if value != 0 and rule['original_speed_sign']:
            result[value]+=probability/3
            result[-value]+=probability*2/3
        else: result[value]+=probability
    return dict(sorted(result.items()))
def rule_nonzero(rule): return 1-outcome_distribution(rule).get(0,Fraction(0))
def event_eligible(rule): return not rule['excluded'] and rule['stat']!='durability_bonus_raw'

def finite_rolls(rules):
    distributions=[outcome_distribution(rule) for rule in rules]
    suffix_zero=[Fraction(1)]*(len(rules)+1)
    for i in range(len(rules)-1,-1,-1):
        suffix_zero[i]=(distributions[i].get(0,Fraction(0)) if event_eligible(rules[i]) else 1)*suffix_zero[i+1]
    result=[]
    for i,(rule,distribution) in enumerate(zip(rules,distributions)):
        remaining_nonzero=1-suffix_zero[i]
        assert remaining_nonzero>0 or not event_eligible(rule), 'all-zero modifier suffix cannot satisfy conditioned JP event'
        outcomes=[]; cumulative=conditional_cumulative=Fraction(0)
        for value,probability in distribution.items():
            conditional=(probability*(1-suffix_zero[i+1] if value==0 else 1)/remaining_nonzero
                         if event_eligible(rule) else probability)
            cumulative+=probability; conditional_cumulative+=conditional
            outcomes.append(dict(value=value,probability_exact=fraction_text(probability),
                prefix_zero_probability_exact=fraction_text(conditional),cdf_tick=rounded_tick(cumulative),
                prefix_zero_cdf_tick=rounded_tick(conditional_cumulative)))
        assert cumulative==conditional_cumulative==1
        for field in ['cdf_tick','prefix_zero_cdf_tick']:
            ticks=[o[field] for o in outcomes]
            assert ticks==sorted(ticks) and ticks[-1]==RUNTIME_DENOM
        result.append(dict(stat=rule['stat'],excluded=rule['excluded'],event_eligible=event_eligible(rule),
            suffix_zero_probability_exact=fraction_text(suffix_zero[i+1]),outcomes=outcomes))
    return result,1-suffix_zero[0]

def build():
    src,v3,tiers=read(SOURCE),read(V3),read(TIERS)
    master=read(MASTER)['records']; allowed=set(src['tier_source']['allowed_styles'])
    overrides,evidence=tiers['exact_id_overrides'],tiers['equipment_classification_evidence']
    assert len(master)==len(evidence)==175
    ids=src['canonical_item_ids']
    expected=sorted(r['itemId'] for r in master if overrides[str(r['itemId'])] in allowed)
    assert ids==expected and len(ids)==len(set(ids))==92 and src['multiplier']==3
    assert src['generation_contract']['rules_contract_id']=='item.drop.affix.rules.v4'
    assert src['generation_contract']['affix_contract_id']=='item.drop.affix.v4'
    assert src['saturation_policy']=='min(1, multiplier * current_true_nonzero_event_probability)'
    assert src['canonical_item_styles']=={str(i):overrides[str(i)] for i in ids}
    records={r['item_id']:r for r in v3['records']}
    assert v3['contract_id']=='item.drop.affix.rules.v3'
    assert v3['single_player_outer_gate']=={'numerator':1,'denominator':2}
    rows=[]
    for iid in ids:
        rolls,q=finite_rolls(records[iid]['rolls']); old=q/2; target=min(Fraction(1),Fraction(3,2)*q)
        gate=rounded_tick(target)
        no_jp_outer=(1-q)/(2-q)
        assert abs(Fraction(gate,RUNTIME_DENOM)-target)<=Fraction(1,2*RUNTIME_DENOM)
        item=next(r for r in master if r['itemId']==iid)
        assert item['durability']*1000<v3['maximum_durability_raw']
        rows.append(dict(canonical_item_id=iid,name_style=overrides[str(iid)],
            inner_nonzero_probability_exact=fraction_text(q),current_event_probability_exact=fraction_text(old),
            target_event_probability_exact=fraction_text(target),runtime_gate_numerator=gate,
            runtime_gate_denominator=RUNTIME_DENOM,
            no_jp_outer_pass_probability_exact=fraction_text(no_jp_outer),
            no_jp_outer_pass_gate_numerator=rounded_tick(no_jp_outer),
            runtime_no_jp_outer_absolute_error_bound=fraction_text(abs(Fraction(rounded_tick(no_jp_outer),RUNTIME_DENOM)-no_jp_outer)),
            runtime_event_absolute_error_bound=fraction_text(abs(Fraction(gate,RUNTIME_DENOM)-target)),rolls=rolls))
    def authority(path): return dict(path=str(path.relative_to(ROOT)).replace('\\','/'),sha256_lf=fingerprint(path))
    return dict(schema_version=4,contract_id='item.drop.affix.rules.v4',affix_contract_id='item.drop.affix.v4',
        record_count=len(rows),identity_key='canonical_item_id',maximum_durability_raw=65000,
        source_authority=authority(SOURCE),classification_authority=dict(**authority(TIERS),
            role='authoring evidence only; runtime consumes independent canonical ID registration'),
        frozen_v3_authority=authority(V3),master_authority=authority(MASTER),multiplier=3,contract=src['contract'],
        saturation_policy=src['saturation_policy'],generation_contract=src['generation_contract'],
        runtime_denominator=RUNTIME_DENOM,numeric_contract=dict(draw='independent 26+27 uniform integer bits',
            cdf='nearest exact rational cumulative tick',cdf_absolute_error_bound=f'1/{2*RUNTIME_DENOM}',
            maximum_integer=RUNTIME_DENOM,conditional_joint_total_variation_error_bound='sum(outcome_count-1)/2^53'),
        records=rows,generator='tools/build_item_drop_affix_wooma_jp_policy.py')
def main():
    ap=argparse.ArgumentParser(); ap.add_argument('--write',action='store_true'); ap.add_argument('--check',action='store_true')
    args=ap.parse_args(); assert args.write != args.check
    data=build(); rendered=json.dumps(data,ensure_ascii=False,indent=2)+'\n'
    if args.write: OUT.write_text(rendered,encoding='utf-8',newline='\n')
    else: assert OUT.read_text(encoding='utf-8')==rendered
    print(f'ITEM_DROP_WOOMA_JP_POLICY_PASS records={len(data["records"])} multiplier=3 runtime_denominator={RUNTIME_DENOM}')
if __name__=='__main__': main()
