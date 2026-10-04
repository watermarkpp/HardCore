from pathlib import Path
import json

root=Path.cwd()
assert root==Path('C:/Users/Administrator/.codex/worktrees/pluggable-framework-v2/HardCore')
old=root/'outputs/framework_v2/chain_state_pool_20261004'
owned=root/'outputs/framework_v2/state_loan_20261004'
parent='800cca3cdb7cf21bc0802ae2650d982ec6cc0c9e'
scope=('Returned origin-owned state loans reserve N*S resident storage for supported direct/child finite chains, '
       'while keeping original cumulative facts/receipts/child frontier unchanged. Invalid old-life states '
       'return one loan only to a live origin before accepted new-life work needs it; shared refresh roots '
       'and original source/credit remain held until terminal. Controlled real HP/life/refresh/clear and '
       'real Player windup/Root planner/late-life child API probes are separate evidence scopes. '
       'Periodic fact/death-child compiler remains closed. Full Task3-5/natural P6R3/framework/APK remain NOT_RUN.')
old_scope=('Declared base spawn slots reject an overlapping still-owned life before serial/HP changes, '
       'including a dead body removed from the enemy group; queued retirement permits the replacement. '
       'A periodic HP callback that clears its runtime cannot reinsert its retired tick; actual committed '
       'damage metrics survive and the outer scope closes. Normal ignite reserved/unreserved RED/GREEN '
       'are native controlled API/HP tests. Parent-only Root control retains the unrelated formal map '
       'respawn audit FAIL. No state-pool reuse or periodic-child feature is enabled. Full framework/APK remain NOT_RUN.')
groups=json.loads((old/'FINAL_TEST_GROUPS.json').read_text(encoding='utf-8-sig'))
groups[0]['label']='state_loan_final_direct';groups[1]['label']='state_loan_final_world'
groups[0]['tests']+=['tests/framework/feature_state_loan_lifetime_test.tscn','tests/framework/feature_state_loan_root_test.tscn']
assert sum(len(g['tests']) for g in groups)==47
assert len({p for g in groups for p in g['tests']})==47
assert all((root/p).is_file() for g in groups for p in g['tests'])
(owned/'FINAL_TEST_GROUPS.json').write_text(json.dumps(groups,indent=2)+'\n',encoding='utf-8')
for name in ('prepare_review.py','run_final_groups.py','archive_increment.py','publish_increment.py'):
    content=(old/name).read_text(encoding='utf-8-sig')
    content=content.replace('2b4ab20a142fe09117b9b996c2d85bc1d6d742f9',parent)
    content=content.replace('outputs/framework_v2/chain_state_pool_20261004','outputs/framework_v2/state_loan_20261004')
    # Change destination literals separately from the parent manifest location.
    content=content.replace("docs/review/framework_periodic_retirement_20261004'","docs/review/framework_state_loans_20261004'")
    content=content.replace('docs/review/framework_child_chain_admission_20261004/SOURCE_MANIFEST.json',
                            'docs/review/framework_periodic_retirement_20261004/SOURCE_MANIFEST.json')
    content=content.replace("prefixes = ('chain_state_pool_',)","prefixes = ('state_loan_',)")
    assert old_scope in content or name in ('prepare_review.py','run_final_groups.py')
    content=content.replace(old_scope,scope)
    if name=='archive_increment.py':
        start=content.index("audit=ROOT/'outputs/framework_v2/child_chain_admission_20261004/audit_2b4ab20a'")
        end=content.index("observed=ROOT/'outputs/framework_v2/heterogeneous_20261004'",start)
        content=content[:start]+'''audit=ROOT/'outputs/framework_v2/chain_state_pool_20261004/audit_800cca3c'
for name in ('PRO_REPORT.md','PRO_READ_MANIFEST.json','DOT_REPORT.md','DOT_READ_MANIFEST.json'):
    original=audit/name
    assert original.is_file(),name
    target=DEST/'audit_parent_800cca3c'/name
    target.parent.mkdir(exist_ok=True);shutil.copy2(original,target)
write(DEST/'AUDIT_PARENT_STATUS.json',{'fixed_sha':PARENT,'pro_full_report_read':True,
      'dot_full_report_read':True,'dot_original_outbound_status':'FAIL','dot_turn_status':'interrupted',
      'scope':'Both complete scoped bodies actually read. Dot body is its own complete authored outbound tool text retrieved directly from original thread; original failed delivery retained, not a successful relay or native rerun.'})
''' + content[end:]
    if name=='publish_increment.py':
        content=content.replace('PERIODIC_RETIREMENT_WORKLOG_20261004.md','STATE_LOAN_WORKLOG_20261004.md')
        content=content.replace('audit_parent_2b4ab20a/','audit_parent_800cca3c/')
        content=content.replace('Retire periodic ticks after HP callbacks and protect declared base spawn ownership\\n\\nPreserve committed HP metrics after synchronous runtime retirement without rescheduling stale states. Reject overlapping base slot bodies before birth serial allocation, retaining queued replacement semantics. Full periodic chains and framework remain open.\\n',
            'Return origin state loans across finite child-chain lifetimes\\n\\nReserve resident state storage separately from cumulative work, preserve shared root and historical credit ownership, and retain old-life/clear native counterexamples. Periodic child production and complete framework/APK remain open.\\n')
    (owned/name).write_text(content.rstrip()+'\n',encoding='utf-8')
print(json.dumps({'status':'PASS','parent':parent,'scenes':47}))
