e22fe095 窄范围复审完成：上一轮 P1 未来资产保护、P2 取出目标槽销毁问题均可关闭；当前版本的 APPDATA 关联证据也已补齐。子链准备模块保持未启用，接入生产前还应补一项根技能身份校验

请求 ID：rune-guards-e22fe095-20261004
固定 SHA：e22fe0951f28c55620399b453f116cb09120af4b
父版本：37612de204c42fe3b4fd6a89137e90f3449bc0c2
[本轮审查入口](https://github.com/watermarkpp/HardCore/blob/e22fe0951f28c55620399b453f116cb09120af4b/docs/review/framework_rune_guard_20261004/README.md)

1. P1 未来 Rune／Gem 所有者识别顺序：通过

codec 现在先识别明确不支持的 Rune／Gem 合同及未知 Rune 身份，再进行当前容器分类和私有运行字段检查。未来 Rune 携带 _hc_item_extension、base、extensions、format_version 等字段，不再被当前格式规则提前判为可恢复损坏

OPAQUE_UNSUPPORTED 在 profile／shared 聚合验证中继续成为 terminal；启动预检和正式读取在选择备份、隔离／提升文件之前退出。已知 v1 的非法字段仍判 INVALID，正常旧备份恢复没有被一概关闭

[修复位置，第26–60行](https://github.com/watermarkpp/HardCore/blob/e22fe0951f28c55620399b453f116cb09120af4b/scripts/items/item_extension_codec.gd#L26-L60)，[恢复终态分支](https://github.com/watermarkpp/HardCore/blob/e22fe0951f28c55620399b453f116cb09120af4b/scripts/player_state.gd#L5641-L5736)

有效反例的因果隔离成立：独立比较 isolated RED 与 GREEN 的3722份源码清单，只有 item_extension_codec.gd 改变；754检查的夹具字节相同

RED为754检查、117失败，恰好是新增候选12–20各13个失败；102项独立健康加载／启动预检控制全部通过。GREEN和最终回执保持同样754个断言标签，全部通过

夹具先恢复健康主备并验证健康状态，再注入唯一未来输入；profile／shared 的实际读取、混合普通损坏、原始主备字节不变，以及已知 v1 正常恢复对照均有覆盖。早期535／631项的夹具或路径干扰继续作为历史失败，不充当此次有效 RED

[有效 RED 回执](https://github.com/watermarkpp/HardCore/blob/e22fe0951f28c55620399b453f116cb09120af4b/docs/review/framework_rune_guard_20261004/native/rune_future_order_isolated_red_110329_137699/framework/future_item_ownership_terminal_test.result.json)，[最终754项回执](https://github.com/watermarkpp/HardCore/blob/e22fe0951f28c55620399b453f116cb09120af4b/docs/review/framework_rune_guard_20261004/native/rune_guard_final_direct_111614_807975/framework/future_item_ownership_terminal_test.result.json)

接受范围是明确未来 Rune／Gem 合同及未知 Rune 身份，不能泛化成所有当前固定合同里的任意陌生 ID 都代表未来所有者。既有 Gem v1 明确只允许单一990001记录，不需要为本轮另行放宽

2. P2 remove 预留输出槽：通过

destroy_inventory_indices 在 drain 前调用 slot_reserved，且不要求索引小于当前 inventory.size，所以已存在空位和未来追加位都得到保护；原有 record_reserved 检查保留。负索引仍走原无效选择逻辑，没有误用预留查询的通配语义

拒绝发生在 barrier、清空、保存和信号之前，不创建另一 writer，也不完成已有 writer

[销毁入口修复](https://github.com/watermarkpp/HardCore/blob/e22fe0951f28c55620399b453f116cb09120af4b/scripts/player_state.gd#L1448-L1479)

六种真实 Port／writer 用例覆盖 Rune／Gem × 空位／追加位／混合选择。有效 RED119项中38失败，原始日志实际出现完成取出后销毁1件、混合情况销毁2件；最终119/119，六种调用均 destroyed=0、inventory_unchanged=true、writer_finished=false

拒绝后 inventory、equipment、journal、原 pending.job、预留、主备字节及无关物品保持。随后原 writer 正常完成一次，原资产只出现一份，另一 namespace 保留；重交 cached quote 走 durable replay，不增加 writer 或资产

[拒绝与后续提交断言](https://github.com/watermarkpp/HardCore/blob/e22fe0951f28c55620399b453f116cb09120af4b/tests/framework/rune_transaction_test.gd#L107-L178)，[原生 RED 日志](https://github.com/watermarkpp/HardCore/blob/e22fe0951f28c55620399b453f116cb09120af4b/docs/review/framework_rune_guard_20261004/native/rune_remove_destination_owned_red_111046_543026/raw/rune_transaction_test.stdout.log#L5-L11)

两点范围修正：
- 这六种新场景是在同一进程中进行持久化 load_save，不是六次独立进程冷启动。另有独立 Rune cold 和世界 cold，不能替代这里的逐场景冷启动证据
- 普通销毁后半段未改，兼容性有源码支持；最终42场景未包含已有的普通成功销毁测试，不能称该正向操作本轮又独立实跑了一次

这些限定不影响本次精准缺口关闭，也不把受控 API 反例说成自然 UI 丢物复现

3. 当前 APPDATA 隔离关联：补证通过

已经逐份核对38份 framework 原生回执：
- 启动请求的目录
- runner 设置的 APPDATA、项目目录和进程信息
- wrapper 的运行身份
- 原生实际读取的 APPDATA、user_data_dir、project、PID
- run／invocation／source
- handoff 中完整回执哈希

上述关联全部吻合，38个不同 run 对应四个不同的原生观察根目录。helper 确实调用 OS.get_environment、OS.get_user_data_dir、ProjectSettings.globalize_path 和 OS.get_process_id，未拿 wrapper 声明冒充原生观察

seed／cold／restart 按设计在所属组内共享目录；8份 expectation 都关联本组指定成功 producer。另4个普通场景只有 wrapper 的环境／启动证据，没有 framework 原生环境回执，报告应继续保留这一区别

[最终运行关联](https://github.com/watermarkpp/HardCore/blob/e22fe0951f28c55620399b453f116cb09120af4b/docs/review/framework_rune_guard_20261004/FINAL_RUN_ASSOCIATION.json)

父37612de2历史 APPDATA 关联仍为 MISSING。本轮是带完整观察字段重新运行后的当前证据，不能回填旧运行的环境

4. 子链准备模块：可保留，但还有发布前身份边界

有限成本助手没有发现阻断性的算术错误。它使用保守完整链成本，饱和加乘在操作前检查，以容量上界之外一位判断超限；几何级数计算为对数复杂度，最大允许代数下循环仍有界。N=0、B=0、G=0和刚好容量边界与公式一致

这些成本结论依赖可信的 receiver、fan-out、binding 上界，还没有证明动态目标、异步所有权或真正的整链容量预留

[成本助手](https://github.com/watermarkpp/HardCore/blob/e22fe0951f28c55620399b453f116cb09120af4b/scripts/features/compilation/child_capacity_proof.gd#L6-L70)

death_burst_handler 对请求做递归复制和只读冻结，没有 HP、planner、RNG、信号或队列权威；有限数值和 Vector2 可表示性检查成立。尚未检查未来 AABB、距离、范围运算的完整数值边界。periodic 测试只修改纯 fixture 的 source_class，不代表真实周期生产者执行了死亡子链

需要在接入前补的一项：generation=0、direct 的 fact.skill_id 未被交叉校验。将合法夹具的该字段改成烈火技能或删除它，当前 helper 仍可根据 chain.root_skill_id 构造原技能的子请求

请明确 generation=0 的根技能身份由谁提供并验证，对矛盾／缺失事实补负例。后续 generation>0 的 child 技能与 root 技能可能合法不同，不应一刀切要求全部相等

[该检查位置，第32–38行](https://github.com/watermarkpp/HardCore/blob/e22fe0951f28c55620399b453f116cb09120af4b/scripts/features/handlers/death_burst_handler.gd#L32-L38)

这是尚未启用的纯助手完善项，不能称当前游戏已发生错技能子链。handler仍不在可发布 IDS／CONTRACTS，compiler和DamageBatch拒绝其正式接入，EffectRuntime也没有 RequestChildAction 执行路径。因此不阻断本轮两个生产 guard 的关闭，但实际接链前应解决

5. 最终字节、采用范围与日志

独立复核结果：
- 3722份源码，较父版6新增＋8修改＝14路径，before／after与SOURCE_DELTA一致
- 内容指纹8d6d10f179f364584f0928cb76f16d45b777fe4019b6a8ce1aff7b9821bcd812
- 全量 Git 对照843份字节一致、2879份仅CRLF，零其他差异
- 源码 ZIP15778734字节，SHA256 24a6b56efba9aef9819b4e4875d620c74321ee7cd4fa2a9f659190e81f6561e9
- 原生 ZIP8554113字节，SHA256 d09c67eee9a77fd8665838f7f7076d5f1900874e50f4361f8978204f2ac405ce；446份原生成员哈希及长度匹配
- 21组共79次原生尝试＝67 PASS＋12 FAIL，全部历史失败保留
- 最终42唯一场景＝30直接＋1 journal单组＋3 journal链＋8世界；38完整receipt、2150项检查
- 所有最终原生退出0、无超时；全部组前后源码清单保持，各最终运行与receipt／handoff相符
- 原始最终日志未发现 ERROR／SCRIPT ERROR；11个场景仍有ObjectDB退出告警，10个为8实例、summon为10实例，不能称无告警或零泄漏

原生反例、解析失败、夹具／路径干扰和身份失败继续按原标签保留，没有把中途 marker 当完成依据。[运行索引](https://github.com/watermarkpp/HardCore/blob/e22fe0951f28c55620399b453f116cb09120af4b/docs/review/framework_rune_guard_20261004/RUN_INDEX.json)

结论：本轮两个生产缺陷及当前 APPDATA 证据缺口已闭合，可以继续原定串行施工，不必重做已闭专项。子链身份完善项纳入后续接链门禁

本审查只读取固定远端源码及已有原生证据，没有重新运行引擎。完整Task3、死亡子链与动态完整承诺、生成组合、Task5／P6、supervisor安全复用、Android／GPU／APK及原v97B仍开放；历史index连续性FAIL／旧原件MISSING也不变。完整报告留在本对话供施工方直接读取
