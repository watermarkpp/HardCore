from pathlib import Path
import json

root=Path.cwd()
assert root==Path('C:/Users/Administrator/.codex/worktrees/pluggable-framework-v2/HardCore')
old=root/'outputs/framework_v2/child_chain_admission_20261004'
owned=root/'outputs/framework_v2/chain_state_pool_20261004'
parent='2b4ab20a142fe09117b9b996c2d85bc1d6d742f9'
scope=('Declared base spawn slots reject an overlapping still-owned life before serial/HP changes, '
       'including a dead body removed from the enemy group; queued retirement permits the replacement. '
       'A periodic HP callback that clears its runtime cannot reinsert its retired tick; actual committed '
       'damage metrics survive and the outer scope closes. Normal ignite reserved/unreserved RED/GREEN '
       'are native controlled API/HP tests. Parent-only Root control retains the unrelated formal map '
       'respawn audit FAIL. No state-pool reuse or periodic-child feature is enabled. Full framework/APK remain NOT_RUN.')
groups=json.loads((old/'FINAL_TEST_GROUPS.json').read_text())
groups[0]['label']='chain_state_pool_final_direct'
groups[1]['label']='chain_state_pool_final_world'
groups[0]['tests'] += ['tests/framework/feature_birth_slot_identity_test.tscn',
    'tests/framework/periodic_callback_retirement_test.tscn','tests/monster_summon_hard_cap_test.tscn']
assert sum(len(g['tests']) for g in groups)==45
assert len({p for g in groups for p in g['tests']})==45
assert all((root/p).is_file() for g in groups for p in g['tests'])
(owned/'FINAL_TEST_GROUPS.json').write_text(json.dumps(groups,indent=2)+'\n')
for name in ('prepare_review.py','run_final_groups.py','archive_increment.py','publish_increment.py'):
    text=(old/name).read_text()
    text=text.replace('1f6ca7a78e2163c3365bbcb38710018e6eee4dbf',parent)
    text=text.replace('outputs/framework_v2/child_chain_admission_20261004','outputs/framework_v2/chain_state_pool_20261004')
    text=text.replace('docs/review/framework_child_execution_20261004/SOURCE_MANIFEST.json',
                      'docs/review/framework_child_chain_admission_20261004/SOURCE_MANIFEST.json')
    text=text.replace('docs/review/framework_child_chain_admission_20261004\'','docs/review/framework_periodic_retirement_20261004\'')
    text=text.replace("prefixes = ('child_chain_admission_', 'periodic_child_')", "prefixes = ('chain_state_pool_',)")
    old_scope=('Continuous live-chain fact promises remain charged while batches are partially drained; '
               'the same runtime has one consumer even through synchronous callbacks; Root explicitly reports '
               'child batch transfer, legal empty work or owner retirement. Controlled real HP/API probes '
               'cover partial drain, heal reentry, after-HP clear and two sibling branches. '
               'The preserved periodic-chain fixtures are RED, not completed implementation. '
               'Full periodic child/state chains, Task3-5/P6/APK/device remain NOT_RUN.')
    assert old_scope in text or name in ('prepare_review.py','run_final_groups.py')
    text=text.replace(old_scope,scope)
    if name=='archive_increment.py':
        start=text.index("audit=ROOT/'outputs/framework_v2/child_execution_20261004/audit_1f6ca7a7'")
        end=text.index("observed=ROOT/'outputs/framework_v2/heterogeneous_20261004'",start)
        text=text[:start]+'''audit=ROOT/'outputs/framework_v2/child_chain_admission_20261004/audit_2b4ab20a'
for name in ('PRO_REPORT.md','PRO_READ_MANIFEST.json'):
    original=audit/name
    assert original.is_file(), name
    target=DEST/'audit_parent_2b4ab20a'/name
    target.parent.mkdir(exist_ok=True); shutil.copy2(original,target)
dot_failure=ROOT/'outputs/framework_v2/child_chain_admission_20261004/DOT_READ_FAILURE_2B4AB20A.json'
assert dot_failure.is_file()
shutil.copy2(dot_failure,DEST/'audit_parent_2b4ab20a'/dot_failure.name)
write(DEST/'AUDIT_PARENT_STATUS.json',{'fixed_sha':PARENT,'pro_full_report_read':True,
      'dot_full_report_read':False,'dot_execution_status':'FAIL','dot_full_report_status':'MISSING',
      'scope':'Pro full original report and Dot terminal platform failure actually read; no automatic retry or dual PASS claim.'})
''' + text[end:]
        text=text.replace("'Final chain-admission/direct and existing world live-cold only. Partial-drain/reentry/transfer RED and incomplete periodic-chain compiler/admission RED remain preserved under their original fingerprints. Earlier malformed periodic fixtures and one incorrect requested test path remain FAIL. This does not close periodic implementation or whole architecture.'",repr(scope))
    if name=='publish_increment.py':
        text=text.replace("ROOT/'docs/source176_r3/CHILD_CHAIN_ADMISSION_WORKLOG_20261004.md'", "ROOT/'docs/source176_r3/PERIODIC_RETIREMENT_WORKLOG_20261004.md'")
        text=text.replace('audit_parent_1f6ca7a7/PRO_REPORT.md','audit_parent_2b4ab20a/PRO_REPORT.md')
        text=text.replace('audit_parent_1f6ca7a7/DOT_REPORT.md','audit_parent_2b4ab20a/DOT_REPORT.md')
        text=text.replace('Preserve admitted chain capacity through partial drain and reentry\\n\\nKeep consumed fact storage charged to live roots, serialize runtime consumers across synchronous callbacks, and propagate child batch transfer or retirement outcomes. Preserve incomplete periodic-chain RED evidence without enabling its unsupported compiler path. Full framework and APK remain open.\\n',
            'Retire periodic ticks after HP callbacks and protect declared base spawn ownership\\n\\nPreserve committed HP metrics after synchronous runtime retirement without rescheduling stale states. Reject overlapping base slot bodies before birth serial allocation, retaining queued replacement semantics. Full periodic chains and framework remain open.\\n')
    (owned/name).write_text(text.rstrip()+'\n')
print(json.dumps({'status':'PASS','parent':parent,'scenes':45}))
