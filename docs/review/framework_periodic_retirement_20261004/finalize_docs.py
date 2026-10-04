from pathlib import Path
import hashlib,json,shutil

root=Path.cwd()
owned=root/'outputs/framework_v2/chain_state_pool_20261004'
dest=root/'docs/review/framework_periodic_retirement_20261004'
evidence=json.loads((dest/'SCOPED_EVIDENCE.json').read_text())
assert evidence['final_unique_positive_scenes']==45
readme=f'''# 周期HP回调退休与声明出生槽所有权

父固定提交 `2b4ab20a142fe09117b9b996c2d85bc1d6d742f9`。第三树真实HEAD仍为 `5d9ceb0121980ca9636d9d1cc2e19982949fbf63`，保留继承dirty现场，固定审查提交使用独立index。受测内容 `{evidence['source_content_sha256']}`，{evidence['source_files']}源文件、{evidence['delta_files']}源码/测试增量；没有修改compiler或启用未完成周期子链。

## 两个原生反例

1. 同一正式Root的声明base slot允许同时产生两个活receiver，原9检查2FAIL；加入提前拒绝后9PASS。扩充死亡/复活窗口后11检查1FAIL：真实死亡立即清碰撞并离开enemies group，尚未queue_free的身体仍拥有回调资格，因此只查活group仍遗漏。最后按该Root实际直属身体检查slot/generation/queued状态，重复出生在serial及actor分配前拒绝；旧身体queue_free后即允许同slot新life。最终11检查通过。召唤子槽仍走既有独立summon闭包，没有新增怪物/AOE数量上限。
2. 正常hc.ignite的一秒周期通过真实Combat与Enemy四参数HP端口完成伤害，在super返回后测试观察者一次clear同runtime，并尝试nested公共pump。旧tick继续重放heap，32检查4FAIL（两条带/不带ticket路径的heap残留与后续mismatch），实际5HP损失及单消费者检查通过。最小修复在HP返回后重验派发代次及state对象所有权，已提交损失和一次delivery/tick统计保留；无资格的旧tick不能推进或重排状态，也不能在拒绝收尾误停替代状态。对应同32检查GREEN，随后相关周期/迟到/子承诺五场景通过。

这里是受控生产API和真实HP回调反例，测试拥有的观察者明确注入clear，不宣称正常UI已自然触发。Runtime不新增HP、时钟、planner、writer或预算，原period/raw/expiry/strongest_keep_phase/RNG及死亡碰撞语义保持。新测试没有启用periodic→death→child功能。

## 保留的独立FAIL

出生相关回归中monster_formal_respawn_policy_audit_test原FAIL：地图authoring 203等缺policy、special_normal与旧normal_cave预期不同。对照只临时切回父2b4的精确Root字节，同场景仍原生FAIL/exit1，finally精确恢复当前Root；这是单文件父对照，不是全父版本实跑。该测试本身不实例化Root，使用Bridge/Policy/WorldState。原始失败不改标签，地图数据/预期未修改；不能以本轮专项PASS关闭这项数据门禁。

RESPAWN_PARENT_CONTROL.json保留原控制身份、Root前/控制哈希及restored_exact_current_bytes，SOURCE_DELTA确认未修改authoring/policy。所有RED、早期部分修复仍FAIL、parent control均在RUN_INDEX和原生日志中保留。

## 最终同源码关联

最终{evidence['final_unique_positive_scenes']}唯一场景，{evidence['final_framework_receipts']}完整framework回执/{evidence['final_framework_checks']}检查；DIRECT显式30秒、WORLD显式60秒，无延长。每组独立owned APPDATA，native退出0，run/invocation/source/本轮producer-cold以及完整receipt和真实用户数据根关联检查。源before/after一致。总{evidence['native_attempts']}原生尝试中的{evidence['preserved_failed_attempts']}FAIL仍保留，wrapper启动前FAIL {evidence['preserved_wrapper_rejections']}。旧阶段PASS不冒充最终字节结果，ObjectDB warning原样保留。

父Pro完整正文/来源在audit_parent_2b4ab20a，已实际读到并采纳周期回调反例。父小可爱请求远端执行被平台过滤终止，仅有FAIL/MISSING，没有完整报告，不称双审计通过，也不自动重发同请求。既有定时拉取已官方PAUSED；下一固定增量可按已授权策略重新提出新范围请求。

PROTECTION、INDEX_CONTINUITY_BOUNDARY、原字节源码/native/indexZIP和Git源码映射保留。主树/第二树HEAD/index/dirty、冻结MonsterStreaming、RFC和主资源不变。历史index连续性FAIL和旧备份MISSING不补造或恢复。源码diff-check通过，原始日志/独立报告空白边界另记录。

## 继续施工的范围

N×S状态驻留复用尚未实现：同slot跨life的旧状态终态、并发根和A/B刷新chain_owners/credit/资源lease、累计periodic工作配额及真正致死tick的独立身份仍须证明。此次出生guard只补factory不重叠life的一个前提，不能外推为完整状态上界。

完整周期致死→子动作→再点燃、持续fact/due时child服务机会、最坏atomic quantum、Task3资源实际cue/audio/子资源及自然渲染、Task5模板/生成式组合、自然P6R3仍继续。原v97 B MISSING、原生地图policy门禁FAIL、强杀/掉电完整矩阵、Android/GPU和APK分别保留；没有主树合入或打包。本增量通过不关闭整体架构。
'''
(dest/'README.md').write_text(readme,encoding='utf-8')
worklog=root/'docs/source176_r3/PERIODIC_RETIREMENT_WORKLOG_20261004.md'
worklog.write_text(readme,encoding='utf-8')
addition=(f'\n\n2026-10-04 周期回调与出生槽检查点：父2b4 Pro完整报告已实际读取；小可爱该请求平台终止FAIL/报告MISSING，不宣称双通过。正式周期HP回调clear原32检查4FAIL→32PASS；同base slot重复出生原9/2FAIL→9PASS，补死亡离group的身体窗口11/1FAIL→11PASS。最终同{evidence["source_content_sha256"]}内容45场景/{evidence["final_framework_checks"]}检查，见PERIODIC_RETIREMENT_WORKLOG_20261004.md及docs/review/framework_periodic_retirement_20261004。地图formal respawn audit FAIL和父Root单文件对照同FAIL保留，未改authoring。N*S池/完整periodic child、Task3/4/5/P6/设备/APK均继续，不关闭整体目标。\n')
records=[]
for name in ('docs/source176_r3/CHILD_CHAIN_PLAN_20261004.md','docs/source176_r3/FRAMEWORK_PUBLICATION_CLOSURE_PLAN.md','docs/source176_r3/PERIODIC_CHILD_CHAIN_PLAN_20261004.md'):
    path=root/name;before=path.read_bytes()
    assert '2026-10-04 周期回调与出生槽检查点' not in before.decode('utf-8-sig')
    path.write_bytes(before+addition.encode())
    records.append({'path':name,'preserved_prefix_bytes':len(before),'before_sha256':hashlib.sha256(before).hexdigest(),'after_sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
(dest/'APPEND_ONLY_DOCS.json').write_text(json.dumps(records,indent=2)+'\n')
for name in ('prepare_delivery.py','prepare_review.py','archive_increment.py','publish_increment.py','run_final_groups.py','run_owned.py','run_respawn_parent_control.py','RESPAWN_PARENT_CONTROL.json','FINAL_TEST_GROUPS.json','FINAL_RUN_ASSOCIATION.json','finalize_docs.py'):
    shutil.copy2(owned/name,dest/name)
print(json.dumps({'status':'PASS','scenes':45,'framework_checks':evidence['final_framework_checks']}))
