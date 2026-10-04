from pathlib import Path
import hashlib, json, shutil

root = Path.cwd()
owned = root/'outputs/framework_v2/child_chain_admission_20261004'
dest = root/'docs/review/framework_child_chain_admission_20261004'
evidence = json.loads((dest/'SCOPED_EVIDENCE.json').read_text())
index = json.loads((dest/'RUN_INDEX.json').read_text())
assert evidence['final_unique_positive_scenes'] == 42
readme = f'''# 活链容量持续记账、单消费者及子批次结果传播

父固定提交 `1f6ca7a78e2163c3365bbcb38710018e6eee4dbf`。第三树仍以真实 HEAD `5d9ceb0121980ca9636d9d1cc2e19982949fbf63` 加保留的工作内容施工；审查使用独立 index。最终受测内容 `{evidence['source_content_sha256']}`，{evidence['source_files']}源文件、{evidence['delta_files']}增量。

## 原生反例与最小修复

1. 同一真实85槽世界，根85个实际HP事实与94个合法85事实生产者共承诺8160。消费53事实时旧实现把仍存活的根承诺暂借给另一85事实动作，最终承诺超容量，已接受子动作在HP提交后转移失败。逐事实把已消费槽立即归还给原根，而非整批完后退款；消费后的承诺与pending之和持续8160，竞争动作在新资源/HP前拒绝。
2. 实际Player治疗通知同步调用同一runtime的pump，旧实现第二消费者消耗最后事实并提前退休根，外层死亡订阅丢失。pump入口的一实例单消费者所有权覆盖同步回调、clear与外层预算收尾；configure也不得抢走在途所有者。嵌套调用返回0，外层承诺完整兑现。
3. test-owned Root在子HP提交并冻结事实后、转移前clear同一runtime。旧Root仍返回success；现在finish返回明确的transferred/empty/owner_retired/rejected，子入口传播实际结果。owner_retired不伪报成功，不回滚已经提交HP，也不将正常退休写成引擎错误。
4. 补两个合法兄弟分支：第一个合法空命中、第二个实际命中并转移；第一个未封口时尝试同步pump，不开始另一个生产者，两分支各执行一次。此第四项在GREEN阶段新增覆盖，没有独立的同断言旧版RED，不冒充前三项旧版证伪。

初次原生34检查8FAIL中1项是夹具实际84槽却预期85，补真实第三个声明slot后，正式RED35检查7FAIL保留。对应最小修复后35检查全部通过；随后新增兄弟分支覆盖，并纳入最终同源码回归。原记录和失败原因以RUN_INDEX及原生完整回执为准。

## 夹具与证据范围

容量反例的85事实由一次真实致死和84次同一存活怪的实际HP提交组成，不是85唯一被击目标。94票据是受控runtime API压力，不是自然Player同时94次起手。部分消费用明确的53/32内部消费观察边界，后续子动作使用实际public pump、Root、原planner、实际释放几何与唯一HP。同步重入由真实Player通知触发；显式clear由测试Root注入，不宣称自然UI复现。默认关闭的新验证模块不投放新玩法。

本轮另保留周期链施工前的全部失败：错误registry字段及缺max_ticks是夹具先决条件FAIL；修正后正式目录返回unsupported_trigger_chain是真实功能RED；临时开放编译端口后真实85槽接受返回child_state_capacity。该实验编译hunk已撤回到父提交精确字节，以免发布不完整周期端口。四个周期fixture保留在源码包，但不在最终采用PASS场景中，也不称周期功能完成。

最终采用{evidence['final_unique_positive_scenes']}唯一场景、{evidence['final_framework_receipts']}完整框架回执、{evidence['final_framework_checks']}检查，直接/世界两组为独立本轮owned APPDATA。native退出0、完整receipt、run/invocation/source以及本轮producer/cold关联一起验证；受测期间源码稳定。原始native尝试{evidence['native_attempts']}，其中{evidence['preserved_failed_attempts']}个FAIL保留；另{evidence['preserved_wrapper_rejections']}次错误请求不存在测试路径导致wrapper启动前FAIL，未启动native场景，未并入native计数。ObjectDB warning原样保留，不称泄漏或总内存全部闭合。

## 保护、关联与审查边界

父Pro和小可爱完整报告及来源身份原样保存于audit_parent_1f6ca7a7。Pro父报告中的WORLD invocation文字UUID与原始关联不符；父FINAL_RUN_ASSOCIATION原记录为DIRECT b673e3fa-58ac-4d03-9e78-df77470b5ccf、WORLD 8aa110f5-6f87-4f04-9cd4-0eac3618cad4。本轮不改独立报告正文，也不改原生身份；原始关联是权威依据。

PROTECTION核对主树/第二树HEAD、index及dirty字节清单，第三树观察index和冻结MonsterStreaming保持。历史index连续性FAIL、原始备份MISSING继续保留。主源媒体和用户RFC保持。源码diff-check通过；原始日志/报告空白按DIFF_CHECK_BOUNDARY记录。受测源码ZIP及Git原字节/仅换行映射分别给出，未宣称干净checkout执行。

## 尚未完成

完整周期致死→子动作→再点燃、状态槽回收/来源刷新A-B/credit/资源持有、延迟与换世界及旧分支重交、持续fact/due对child服务时效、最坏原子quantum、Task3真实表现消费、Task5模板/生成组合/自然P6R3仍继续。原v97 B输入MISSING，APK与设备NOT_RUN；没有主树接入或发布。本轮局部PASS不关闭整体架构。
'''
(dest/'README.md').write_text(readme, encoding='utf-8')
worklog = root/'docs/source176_r3/CHILD_CHAIN_ADMISSION_WORKLOG_20261004.md'
worklog.write_text('# 活链容量与单消费者增量\n\n'+readme.split('## 原生反例与最小修复\n\n', 1)[1].split('## 夹具与证据范围', 1)[0]+
                  f'最终同内容{evidence["source_content_sha256"]}的42唯一场景/{evidence["final_framework_checks"]}检查。详情docs/review/framework_child_chain_admission_20261004。周期链仍RED，沿PERIODIC_CHILD_CHAIN_PLAN继续，不关闭Task4、Task3/5/P6/APK。\n', encoding='utf-8')
addition = f'\n\n2026-10-04 活链容量/单消费者续施工：父1f6两份完整独立报告已读。正式35检查7FAIL原生证伪后，同35项通过，并补未封口兄弟分支/合法空命中/真实转移。逐事实连续记账、同runtime同步pump重入返回0、Root传播转移与owner_retired均已实施；最终同{evidence["source_content_sha256"]}内容42唯一场景/{evidence["final_framework_checks"]}检查，见CHILD_CHAIN_ADMISSION_WORKLOG_20261004.md及docs/review/framework_child_chain_admission_20261004。周期链有效unsupported_trigger_chain与child_state_capacity RED均保留，临时开放端口已恢复父字节，不发布不完整功能。Task3/4/5、自然P6R3、APK仍未完成。\n'
records = []
for name in ('docs/source176_r3/CHILD_CHAIN_PLAN_20261004.md', 'docs/source176_r3/FRAMEWORK_PUBLICATION_CLOSURE_PLAN.md'):
    path = root/name
    before = path.read_bytes()
    assert '2026-10-04 活链容量/单消费者续施工' not in before.decode('utf-8-sig')
    path.write_bytes(before+addition.encode())
    records.append({'path': name, 'preserved_prefix_bytes': len(before), 'before_sha256': hashlib.sha256(before).hexdigest(), 'after_sha256': hashlib.sha256(path.read_bytes()).hexdigest()})
(dest/'APPEND_ONLY_DOCS.json').write_text(json.dumps(records, indent=2)+'\n')
for name in ('adapt_delivery.py','archive_increment.py','publish_increment.py','prepare_review.py','prepare_final.py','run_final_groups.py','run_owned.py','FINAL_TEST_GROUPS.json','FINAL_RUN_ASSOCIATION.json','finalize_docs.py'):
    shutil.copy2(owned/name, dest/name)
print(json.dumps({'status':'PASS', 'final_scenes':42, 'framework_checks':evidence['final_framework_checks']}))
