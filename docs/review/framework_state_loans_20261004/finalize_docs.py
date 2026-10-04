from pathlib import Path
import hashlib,json,shutil

root=Path.cwd();assert root==Path('C:/Users/Administrator/.codex/worktrees/pluggable-framework-v2/HardCore')
owned=root/'outputs/framework_v2/state_loan_20261004'
dest=root/'docs/review/framework_state_loans_20261004'
evidence=json.loads((dest/'SCOPED_EVIDENCE.json').read_text(encoding='utf-8-sig'))
assert evidence['final_unique_positive_scenes']==47 and evidence['delta_files']==9
readme=f'''# 有限子链状态驻留与原根预留槽归还

父固定提交 `800cca3cdb7cf21bc0802ae2650d982ec6cc0c9e`。第三树真实HEAD仍是 `5d9ceb0121980ca9636d9d1cc2e19982949fbf63`，保留继承dirty与真实index；受测内容 `{evidence['source_content_sha256']}`，{evidence['source_files']}文件，9源码/测试/作者数据增量。只有runtime和capacity proof两个生产文件修改；compiler仍与父字节相同，未开放periodic→death→child。

## 完成的限定实现

有限direct/child链预留N×S个驻留状态槽，每个状态保留唯一原根；刷新只增加chain_owners，仍保留原source/credit。状态终态将一个槽归还仍存活的原根，然后清理表现与所有共享根。根池耗尽且新生命需要状态时，只回收该原根下ActorRef已失效的一个旧状态；不删除合法状态、已提交死亡fact、子分支或去重receipt。不返还累计fact/child额度，不减目标、AOE、代数、period、duration或预算。

派发期间表现stop可能同步clear，所以回收后重验原代次、reservation和target资格；老命令不能在新世界/新所有者上恢复工作。详见PROTOCOL_SCOPE.md的守恒式、实际world闭包、接口边界和累计工作区分。

## 原生证据及边界

原有效runtime/真实HP单位RED为28检查6FAIL，原85槽拒绝child_state_capacity、旧生命状态尾部未复用以及共享根池计数均证伪；首GREEN为29检查，因为成功85准入会额外执行一个池大小断言，不能宣称完全相同检查总数。旧parse/registry/Player combat_epoch先决失败保留为fixture FAIL，不当作生产因果。后补真实stop端口clear：孩子HP已实际提交不能回滚，state/heap/cue/loan/receipt收尾，公共consumer退出；新增这些断言没有独立旧实现RED，不冒称已有。

刷新单位路径：A10、弱B1、强C20，共享状态保留三个已接受根与原A历史credit/source；A销毁、来源撤销后仍按原strongest_keep_phase实际周期HP20兑现，所有根到状态终态才收尾。它不是周期fact连锁或累计刷新tick额度证明。

另一个actual Root反例仅恢复父runtime及capacity-proof精确两文件字节，保持新Root测试相同：正式world bound85，真实Player接受前child_state_capacity，完整9检查1FAIL/native exit1，finally精确恢复候选。这是两文件父控制，不是全父checkout。候选沿真实Player windup→Root planner→释放时实际几何→唯一HP/fact/child链完成25检查；三个测试slot在接受前建立，合法queued同slot新life不增加bound，后代命中新life和晚进入范围的目标，旧无效状态在原服务边界退休。Root/AI过程显式冻结、内部fact消费观察点显式声明，这是受控生产API测试，不是自然战斗、OS输入或完整自然respawn。

纯容量补证仍保持原累计/serial-only API合同；新的returned-origin成本在N85/B1/G2/L2/S1保留621435累计facts/1242870累计receipts/621435潜在状态创建和7310子动作，驻留为170facts/340receipts/85states。恰好边界及少一state/frontier/receipt/fact槽都原生验证。

## 最终同源码

{evidence['final_unique_positive_scenes']}唯一场景，{evidence['final_framework_receipts']}完整framework回执，{evidence['final_framework_checks']}检查；DIRECT30秒/WORLD60秒。两个独立owned APPDATA、native退出0、无timeout、完整run/invocation/source/进程/用户根与本轮指定成功producer-cold关联；before/after源码相同。保留总{evidence['native_attempts']}次原生中的{evidence['preserved_failed_attempts']}次FAIL，ObjectDB告警原样保留，不称零泄漏或无限耐久。

SOURCE_MANIFEST/SOURCE_DELTA、TESTED_SOURCE/NATIVE_EVIDENCE/INDEX_OBSERVED_BYTES ZIP、全量Git字节映射和原始所有尝试关联共同固定本轮。PROTECTION验证主树/第二树HEAD/index/dirty、第三树真实HEAD/index及冻结MonsterStreaming/RFC/三个主媒体不变；历史index连续性FAIL和旧原件MISSING仍保留。原生期间没有改受测source。

## 父双审计已实际读取与口径更正

父800两份完整报告及来源在audit_parent_800cca3c。Pro完整消息已读取；小可爱完整自主撰写正文存在其原对话失败回传tool文本中，本次直接拉取完整读取，保存源身份/读取时间；原发送FAIL及turn interrupted保留，不伪称投递成功或本机重跑。两份都支持父两项窄修复，未提出本范围新增确证生产阻断。旧2b4平台失败/MISSING不因此关闭。

更正旧叙述：`formal_ordinary_slots_requiring_authored_policy=203`是待补政策的槽位总数203，不是地图ID203。自然`ticks >= 360`为至少360投递门禁，不是该自然场景恰好360次。旧报告和原始日志按原字节保留，本解释修正含糊措辞。地图formal policy FAIL继续开放，不改冻结地图或弱化测试。

## 后续继续

下一项是原周期致死事实→子动作→再点燃：先解决每tick独立身份、累计刷新grant与原credit/根义务，证明HP前已经有承诺，再开放正式compiler并做自然链反例；有限直接子链状态复用不能替代它。持续fact/due时child服务和最坏atomic quantum、实际cue/audio/子资源消费、模板/生成式组合、完整自然P6R3仍继续。原v97B MISSING、地图policy FAIL、强杀/掉电完整矩阵、Android/GPU及APK分项开放。本检查点不关闭整体架构目标、不合主树、不构建APK。
'''
(dest/'README.md').write_text(readme,encoding='utf-8')
(root/'docs/source176_r3/STATE_LOAN_WORKLOG_20261004.md').write_text(readme,encoding='utf-8')
addition=(f'\n\n2026-10-04 原根状态槽归还检查点：父800两份完整独立正文已实际读取，原小可爱发送FAIL保留但本次直接拉取全文，不重发。203为待补政策槽位总数，360是最低投递门禁。有限direct/child驻留池与原根归还已实施，原有效28/6FAIL→29PASS的计数差明确说明；真实Root两文件父控制85槽child_state_capacity的9/1FAIL→25检查路径完成。新增stop-clear及A/B/C共享owner/历史credit保留。最终同{evidence["source_content_sha256"]}内容47场景/{evidence["final_framework_checks"]}检查，见STATE_LOAN_WORKLOG_20261004.md及docs/review/framework_state_loans_20261004。未开放periodic child，累计刷新tickgrant、服务时效/量子、Task3实际资源消费/Task5自然P6R3/设备/APK继续；主树第二树及旧FAIL/MISSING保留。\n')
rows=[]
for name in ('docs/source176_r3/CHILD_CHAIN_PLAN_20261004.md','docs/source176_r3/FRAMEWORK_PUBLICATION_CLOSURE_PLAN.md','docs/source176_r3/PERIODIC_CHILD_CHAIN_PLAN_20261004.md'):
    path=root/name;before=path.read_bytes()
    assert '2026-10-04 原根状态槽归还检查点' not in before.decode('utf-8-sig')
    path.write_bytes(before+addition.encode('utf-8'))
    rows.append({'path':name,'preserved_prefix_bytes':len(before),'before_sha256':hashlib.sha256(before).hexdigest(),'after_sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
(dest/'APPEND_ONLY_DOCS.json').write_text(json.dumps(rows,indent=2)+'\n',encoding='utf-8')
for name in ('prepare_delivery.py','prepare_review.py','archive_increment.py','publish_increment.py','run_final_groups.py',
             'run_owned.py','run_parent_control.py','ROOT_PARENT_CONTROL.json','FINAL_TEST_GROUPS.json','FINAL_RUN_ASSOCIATION.json','finalize_docs.py','PROTOCOL_SCOPE.md','BEFORE.json'):
    shutil.copy2(owned/name,dest/name)
print(json.dumps({'status':'PASS','scenes':47,'framework_checks':evidence['final_framework_checks']}))
