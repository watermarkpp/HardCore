e9c3ac00 独立复审完整结果
请求身份：publication-validation-e9c3-20261004
固定 SHA：e9c3ac005bc3e079eab6602375abfcd9c1bf3cc9
父 SHA：f765d249f7f6128028ce882b13643302b8d75b75

结论：本次非法创建候选拒绝、binding.kind 校验、DamageBatch 票据所有权三个限定整改可接受，未发现需要阻断这些整改的新问题。下面保留准确的验证范围、一个相邻待测输入，以及原失败退出记录的表述要求。资源诊断仍 FAIL，不在这次接受范围

1. 非法创建候选能在写入新角色之前拒绝

recalculate_stats 的两条失败出口现在返回 false，成功只在 computed_stats 赋值后返回 true。与父版机械比较，属性公式没有另写，主体除返回值和错误报告控制外保持不变

create_character 在两个候选阶段都检查结果，失败走统一恢复与 character_stats_rejected，位置均在保存候选 B 之前。新增 base_stats 快照/恢复；旧 computed_stats、pre-feature 缓存、原 loadout 对象、feature_errors 等同步恢复。reset_progress 的中间默认人物重算/通知也被避免

原生反例确实是正常 I/O 的法师 MP18→合法 −16 后 MP2→创建战士非法候选：旧版17项/8FAIL，错误返回为空、base_mp15而computed_mp2；新版17项全过，恢复base_mp18/computed_mp2、feature_errors为空并返回character_stats_rejected。专属目录与index字节保持检查通过

应准确写“在写入候选B/index前拒绝”，不要扩成入口完全没有I/O，前置流程仍可能处理旧存档。装备装配后的第二条拒绝路径、候选通知抑制在本轮是源码覆盖，17项测试没有独立通知观察者，也没有该第二阶段的专门原生负例

[属性重算](https://github.com/watermarkpp/HardCore/blob/e9c3ac005bc3e079eab6602375abfcd9c1bf3cc9/scripts/player_state.gd#L3725-L3740)
[创建拒绝路径](https://github.com/watermarkpp/HardCore/blob/e9c3ac005bc3e079eab6602375abfcd9c1bf3cc9/scripts/player_state.gd#L9379-L9421)

2. binding.kind 的六类反例已关闭

类型检查在枚举比较之前；未知 kind 明确积累错误，整候选在发布前拒绝。六类输入都检查旧目录、authority、bindings、启用集合、stats、bundle、编译次数及通知保持

同一测试正文为31项/18FAIL→31PASS。旧版数字/数组输入确实产生了类型比较 SCRIPT ERROR，新版没有把它们继续传入错误比较

一个相邻静态待测项：kind合法为skill，但skill_id给数字或数组时，当前字段存在检查之后仍直接进入字符串数组成员比较，尚未见String门禁。建议后续以正式入口补这类字段类型负例，确认失败时保留旧发布；我没有原生复现，不把它说成本轮新增RED，也不否定本轮kind修复

[绑定入口](https://github.com/watermarkpp/HardCore/blob/e9c3ac005bc3e079eab6602375abfcd9c1bf3cc9/scripts/layers/runtime/content_layer_registry.gd#L133-L166)

3. 票据所有权交接符合此次同步重入修复目标

源码状态转移核验：
- 成功claim把runtime记录从reserved改为producing，并交给batch持有；这段没有yield或回调
- action取消只收回仍reserved的记录，不夺走已经producing或queued的容量
- 构造拒绝发生在成功claim之前；失败claim不会消耗别的reservation。成功返回的batch强引用自己的ticket
- Root在封口错误、空batch、提交失败和提交完成分支显式finish_production；batch最后引用销毁还覆盖“claim后未封口就放弃”的收尾
- 提交校验通过后同步从producing转queued；batch或旧ticket收尾不能回收queued记录，consumer终态负责释放
- 世界清理不重置递增reservation序号，旧析构不会关闭后来同世界的新票据
- begin_release、begin_plan的单次保护没有放宽；旧timer再次收尾只产生幂等关闭，不重新取得释放资格

在当前已检查生产路径中，没有找到新泄漏、提前释放、双claim或第二次ticketed派发反例

[reservation与producer关闭](https://github.com/watermarkpp/HardCore/blob/e9c3ac005bc3e079eab6602375abfcd9c1bf3cc9/scripts/features/contracts/effect_reservation.gd#L14-L43)
[batch持有与析构](https://github.com/watermarkpp/HardCore/blob/e9c3ac005bc3e079eab6602375abfcd9c1bf3cc9/scripts/features/runtime/damage_batch.gd#L24-L156)
[runtime提交与消费](https://github.com/watermarkpp/HardCore/blob/e9c3ac005bc3e079eab6602375abfcd9c1bf3cc9/scripts/features/runtime/effect_runtime.gd#L98-L249)

4. 重入和销毁证据不是只测一个布尔值

死亡重入场景走真实生产链：HP写入→事实捕获→既有吸血资源通知→受控观察者调用正式take_damage死亡。检查死亡前后仍为producing、随后恰好一个queued事实、四次真实周期投递及最终排空。它是受控生产API同步重入，不是自然UI复现

原19项/7FAIL→19PASS；batch所有权原11项/1FAIL→11PASS。后者保留旧closed ticket引用，最后batch销毁仍让容量归零且旧ID不能重开

空/失败提交、queued析构、世界退出后的旧析构等组合，本次有源码路径核验，不能全部说成各自独立原生复现。此结论只覆盖本次同步producing/queued所有权边界，不等于全部生命周期或异构组合验收

5. 采用记录和原始字节能对应

- 最终采用26唯一场景，25份完整framework回执共658项PASS，另1个普通starter-loadout场景
- 分组为4个直接场景78项、16个相关场景333项framework检查、6个live/cold场景247项，合计658
- 35次已启动原生尝试：27PASS、8FAIL；其中一个较早PASS是旧内容，正确排除在最终26之外
- 另有一次错路径wrapper启动前失败，没有原生行，不计作一次已运行场景
- 最终同内容resource测试仍3项/1FAIL，未混入采用集合

源码、命令、run/invocation/source、完整回执、超时、退出观察和handoff哈希均能对应。26个采用进程均正常退出0，未超时、运行前后内容稳定

两个ZIP尺寸/哈希符合清单；208个native成员、3626个源码成员逐项哈希通过。源码与固定Git tree匹配，包括正常CRLF→LF映射；重算内容身份为：
73fdf0241ad837ab781efc802d73195917cc6076b219cdfe5a12312e7d5b96fc

20个源码/测试/作者数据差量的父/子blob对应。源码ZIP另含一份未变RFC，不把它误算成第3627个源码清单条目。四组直接RED/GREEN使用相同对应测试正文，没有通过减少检查制造通过

[运行索引](https://github.com/watermarkpp/HardCore/blob/e9c3ac005bc3e079eab6602375abfcd9c1bf3cc9/docs/review/framework_publication_validation_20261004/RUN_INDEX.json)
[范围与清单入口](https://github.com/watermarkpp/HardCore/blob/e9c3ac005bc3e079eab6602375abfcd9c1bf3cc9/docs/review/framework_publication_validation_20261004/SCOPED_EVIDENCE.json)

6. 两处记录口径需要明确

旧binding失败发生两个SCRIPT ERROR后被强制终止，原始记录的process_exited=false、native_exit_observed_utc=null。RUN_INDEX中的native_exit=1对应有效失败码，不能描述成“观察到进程正常退出1”，更不能叫正常业务拒绝。原始记录已保留区别；建议索引/报告明确标成effective failure与退出未观察

DIFF_REVIEW记录241个当时staged路径，最终父→提交实际242路径。这两者需保留阶段标签，不能当同一个计数。20个受测源差量仍一致，不是源码身份不匹配

7. 施工建议

可关闭本轮三个目标整改及对应容量所有权反例，保留上述原生/静态覆盖区分。不要重新施工已通过的创建失败回滚、默认依赖或A/B延迟producer专项

后续在现有目录入口负例中补合法kind搭配非法skill_id的类型检查；同时保持资源、异构组合、模板和职业preview缓存等施工独立推进。资源FAIL、ObjectDB警告、child二进制声明的逐进程映射限制，以及原B/Android/GPU/掉电/主树/APK边界均未被本轮关闭

以上为远端固定源码和归档独立复核，没有重新运行Godot、修改工程或启动第二个施工主控
