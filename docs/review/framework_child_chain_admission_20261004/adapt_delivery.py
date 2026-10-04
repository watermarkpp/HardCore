from pathlib import Path

root = Path.cwd()
old = root/'outputs/framework_v2/child_execution_20261004'
owned = root/'outputs/framework_v2/child_chain_admission_20261004'
parent = '1f6ca7a78e2163c3365bbcb38710018e6eee4dbf'
scope = ('Continuous live-chain fact promises remain charged while batches are partially drained; '
         'the same runtime has one consumer even through synchronous callbacks; Root explicitly reports '
         'child batch transfer, legal empty work or owner retirement. Controlled real HP/API probes '
         'cover partial drain, heal reentry, after-HP clear and two sibling branches. '
         'The preserved periodic-chain fixtures are RED, not completed implementation. '
         'Full periodic child/state chains, Task3-5/P6/APK/device remain NOT_RUN.')
for name in ('archive_increment.py', 'publish_increment.py'):
    text = (old/name).read_text()
    text = text.replace('171bffbb69aa7d59b7f0ab30238e8032d67a6ad7', parent)
    text = text.replace('outputs/framework_v2/child_execution_20261004', 'outputs/framework_v2/child_chain_admission_20261004')
    text = text.replace('docs/review/framework_child_execution_20261004', 'docs/review/framework_child_chain_admission_20261004')
    text = text.replace('framework_child_planner_20261004/SOURCE_MANIFEST.json', 'framework_child_execution_20261004/SOURCE_MANIFEST.json')
    text = text.replace("prefixes = ('child_execution_',)", "prefixes = ('child_chain_admission_', 'periodic_child_')")
    text = text.replace('outputs/framework_v2/child_planner_20261004/audit_171bffbb', 'outputs/framework_v2/child_execution_20261004/audit_1f6ca7a7')
    text = text.replace('audit_parent_171bffbb', 'audit_parent_1f6ca7a7')
    text = text.replace('CHILD_EXECUTION_WORKLOG_20261004.md', 'CHILD_CHAIN_ADMISSION_WORKLOG_20261004.md')
    text = text.replace("assert 'Another Godot test runner owns this worktree' in log, source.name",
                        "assert 'TestPaths entry does not exist: tests/framework/frame_budget_fair_turn_test.tscn' in log, source.name")
    text = text.replace('runner_mutex_rejection_before_native_scenes', 'missing_requested_test_path_before_native_scenes')
    text = text.replace('Final controlled Root child execution/direct and existing world live-cold only; raw fixture parse, missing Root entry, cumulative-vs-resident admission, negative map and wrong parent qualification failures remain preserved. This does not close periodic child/state chains or whole architecture.',
                        'Final chain-admission/direct and existing world live-cold only. Partial-drain/reentry/transfer RED and incomplete periodic-chain compiler/admission RED remain preserved under their original fingerprints. Earlier malformed periodic fixtures and one incorrect requested test path remain FAIL. This does not close periodic implementation or whole architecture.')
    old_scope = 'Actual Root consumes typed branch tickets through its existing single planner/query/HP path. Finite immediate two-generation chain reserves cumulative work separately from serial resident storage; old branch receipts retire after producer and consumers close. Wrong parent cannot steal qualification. Declared-slot replacement and late movement are tested under the real 85-slot world bound. Negative map is rejected by child factory only. Periodic child/state chains, full Task3-5/P6/APK remain NOT_RUN.'
    text = text.replace(old_scope, scope)
    text = text.replace('actual Root finite immediate child execution/owned branch qualification/serial residency and branch retirement; periodic state chains/Task3-5/full framework/APK/device NOT_RUN', scope)
    text = text.replace("'Task4 death child chains/self-excitation/dynamic admission/generated combinations'", "'Task4 periodic child/state chains/A-B refresh/self-excitation/generated combinations'")
    text = text.replace("ROOT/'docs/source176_r3/FRAMEWORK_PUBLICATION_CLOSURE_PLAN.md']",
                        "ROOT/'docs/source176_r3/FRAMEWORK_PUBLICATION_CLOSURE_PLAN.md',ROOT/'docs/source176_r3/PERIODIC_CHILD_CHAIN_PLAN_20261004.md']")
    text = text.replace('Execute admitted finite child branches through the existing Root\\n\\nReserve the complete immediate chain frontier before acceptance and distinguish cumulative work from resident batch slots. Validate owned child requests before planning, query targets at actual release, and retire only sealed consumed branch identities. Periodic state chains and full architecture remain open.\\n',
                        'Preserve admitted chain capacity through partial drain and reentry\\n\\nKeep consumed fact storage charged to live roots, serialize runtime consumers across synchronous callbacks, and propagate child batch transfer or retirement outcomes. Preserve incomplete periodic-chain RED evidence without enabling its unsupported compiler path. Full framework and APK remain open.\\n')
    (owned/name).write_text(text)
print('Prepared this increment archive/publication helpers; no source or real index mutation.')
