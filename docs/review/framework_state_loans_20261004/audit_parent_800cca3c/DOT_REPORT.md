800cca3c 独立只读复审结论：本轮两个限定修复可采纳，未在本次范围发现新的阻断缺陷。地图policy门禁仍FAIL，完整状态池／周期子链和整体架构仍未验收

请求：periodic-retirement-800cca3c-20261004
固定SHA：800cca3cdb7cf21bc0802ae2650d982ec6cc0c9e
父SHA：2b4ab20a142fe09117b9b996c2d85bc1d6d742f9
[本轮入口](https://github.com/watermarkpp/HardCore/blob/800cca3cdb7cf21bc0802ae2650d982ec6cc0c9e/docs/review/framework_periodic_retirement_20261004/README.md)

1. 周期HP回调clear后的旧tick：限定修复通过

_tick_one在进入HP端口前记录delivery generation；端口返回后，同时检查代次未变、handle仍存在、字典仍是同一个state对象。已提交的HP损失与成功tick／delivery统计仍保留，但旧tick失去所有权后不再推进next_due、重排heap或清理替代state

失败端口也只有current_owner仍成立才_stop旧handle，避免对新state误清理。未修改period、随机种子、时钟、预算或has_work来隐藏孤立heap

[修复代码](https://github.com/watermarkpp/HardCore/blob/800cca3cdb7cf21bc0802ae2650d982ec6cc0c9e/scripts/features/runtime/effect_runtime.gd#L472-L510)

原生回执已实际读取：32检查RED失败第11、15、26、30项；同32 GREEN和最终回执均通过。两个分支分别有／无admission ticket，真实Enemy四参数override调用super后执行一次clear。首次实际损失5HP保留，nested公共pump返回0，state／heap／cue／promise清空，Budget和consumer闭合；再过一个原period不再写HP，也没有heap mismatch

这里是测试拥有的同步观察者，不是声称自然UI已触发；失败端口和替代state防误清理由源码支持，没有把它们说成另做过独立原生负例。此结论只覆盖正常ignite回调退休，不代表所有child／换世界回调都已验收

2. 同Root声明base slot重叠life：限定修复通过

_spawn_enemy在birth serial增长、actor分配之前，对显式base slot检查同Root直属、同zone generation、尚未queued的Enemy身体。检查不再依赖enemies group，因此真实致死后已经清碰撞、移出group但仍持有延迟回调的旧身体，不会被误当成槽位空闲

旧身体queue_free后，该槽可以立即创建新的实际actor；旧ActorRef因queued状态失效。不同Root／generation不会互相占槽，summoner路径仍走原独立闭包

[出生门禁](https://github.com/watermarkpp/HardCore/blob/800cca3cdb7cf21bc0802ae2650d982ec6cc0c9e/scripts/game_root.gd#L5023-L5046)，[原生夹具](https://github.com/watermarkpp/HardCore/blob/800cca3cdb7cf21bc0802ae2650d982ec6cc0c9e/tests/framework/feature_birth_slot_identity_test.gd)

原生阶段核对：最初9项RED的第4、5项失败；9项GREEN通过。加入死亡窗口后的11项RED及早期不完整修复均在第8项失败；最终11/11。最终断言包含拒绝不增长serial／actor、不改原HP与bound，真实死亡立即清碰撞，queued后合法新life以及旧引用失效

这证明明确factory API的旧身体／替代出生窗口，不证明所有地图自然复活计时或地图policy已经正确

3. 保留的地图policy失败，不能被专项PASS覆盖

已读取monster_formal_respawn_policy_audit_test源码：它扫描正式地图，经Bridge、Policy及WorldState验证，没有实例化Root。候选与只恢复父2b4精确Root字节的控制运行都保留原生FAIL／exit1。控制记录声明finally恢复候选原字节

这是单文件控制，不是全父checkout实跑；没有据此改地图作者数据或旧预期。authoring 203等缺policy和special_normal／normal_cave的差异，仍属于开放的数据门禁

[单文件控制记录](https://github.com/watermarkpp/HardCore/blob/800cca3cdb7cf21bc0802ae2650d982ec6cc0c9e/docs/review/framework_periodic_retirement_20261004/RESPAWN_PARENT_CONTROL.json)

4. 当前源码／原生证据的实际复核范围

本轮直接读取了两个生产文件、两个新测试脚本及相关旧端口／Presentation／地图policy代码；没有重新运行Godot

独立字节复算：
- 3746份清单源码逐项SHA256一致，聚合指纹复算为d94ee4b474239cd21ccdc07080ea713db712cbb69122708b3e3527b164ebe0ba
- 与父清单正好6个delta，4新增测试文件、2修改生产文件，before／after哈希一致
- 固定Git对象对照867份原字节一致、2879份仅CRLF，无其他差异
- 源码ZIP15818972字节，SHA256 453d0184031bf0fe90724e94781e98a1be4969e66c94bcb553c051a3dfa2ef1d
- 原生ZIP4361931字节，SHA256 6d9e9f894087bb38436fafcbdbd397a42a7fef6a2acd782d10c8e1ac64f3a449；315份成员长度、SHA256和固定Git blob一致，无重复／遗漏
- 观察index ZIP的外层大小及SHA256一致；本轮没有重新解析内部index全部条目，不把此前轮次的内部复算冒充本轮新操作

原生记录复核：
- 10组64次尝试＝58 PASS＋6 FAIL，与各组原始runner逐项相符
- 最终45唯一场景，39份framework receipt／1420个通过检查，另6项普通场景按原runner合同
- 39份完整回执的检查数组、编号、run／invocation／source、实际APPDATA／project／user-data与runner和handoff对应，回执原字节哈希匹配
- 两组不同owned APPDATA；最终退出0、无超时，before／after全量源码一致
- 六份expected文件均指向本轮同调用／同源码的指定成功producer；未把旧expectation当成本轮来源
- 原始最终日志未见ERROR／SCRIPT ERROR；18份stderr仍有ObjectDB告警，其中16份8实例、2份10实例，不能称零泄漏

[运行索引](https://github.com/watermarkpp/HardCore/blob/800cca3cdb7cf21bc0802ae2650d982ec6cc0c9e/docs/review/framework_periodic_retirement_20261004/RUN_INDEX.json)

这些是远端字节和生产方原生档案的独立核对，不是我在用户电脑重跑，也不独立证明现场保护操作。历史index连续性FAIL／旧原件MISSING继续保持

5. 1420检查的数量变化有依据，不能称优化

natural脚本与父清单SHA相同。当前resource-backed回执为139，仍包含至少360次投递门禁，实际奖励497＝本次唯一观测死亡的预期497，fixture部分450；旧阶段141项／512记录由FINAL_CHECK_COUNT_CHANGE明确保留

这里差两项来自总观测死亡34→33时逐死亡追加的两项检查，不是把固定30个目标或各3个来源的断言删掉。该变化不构成性能改善，也不能用旧512替换当前497

[检查数量说明](https://github.com/watermarkpp/HardCore/blob/800cca3cdb7cf21bc0802ae2650d982ec6cc0c9e/docs/review/framework_periodic_retirement_20261004/FINAL_CHECK_COUNT_CHANGE.json)

6. N×S证明还缺什么

出生guard只证明同一声明base slot不会同时存在两个未queued身体。旧身体queue_free后，旧life的周期state仍可能等到调度才失效；新life可以合法出生并建立新state。因此“一个活身体／slot”本身不足以证明“最多一套state／slot”

下一增量应分别证明：旧life失效state何时终态并返还credit；返还只能给仍有权的root且恰好一次；多个root刷新同一状态时谁持有未来child义务、历史credit和资源lease；state驻留复用不能重置累计tick／child工作配额。需要用合法换life、逾期服务、A／B刷新、撤来源和clear交错反例验证，而不是从此次11项出生PASS推出整个N×S池正确

本轮未修改child_capacity_proof或开放未完成的periodic child compiler，不能验收致死tick→child→再点燃。完整Task3—5、自然P6R3、地图门禁、原v97B、强杀掉电矩阵、Android／GPU／APK仍各自开放

旧2b4请求仍是中断／未交付状态，本报告没有把它补写成双审计通过。本次结论只针对800cca3c固定范围
