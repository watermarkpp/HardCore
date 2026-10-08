# 串行近战内核研究设计

状态：设计候选；50% 目标尚未达到。研究基线 fixed107 edae6fdef6a6551a951fab1ea8c6ade43359d603，主树新战斗合同不得被该旧基线覆盖。

## 目标与证据

在相同 34 存活怪（30 入战）、48 掉落、移动玩家、300 物理 tick 的正式负载下，将完整 Enemy CPU 中位数从 2057.2785ms 降到不超过 1028.63925ms。原生 profiler 有观察开销；其 inclusive 数值只用于定位，不能作为优化收益。局部 getter、桶池和剪枝试验没有达到目标。

采用官方 godot-cpp/GDExtension 的串行数值内核，先证明 ABI、数值等价和实际接口开销，再逐段接入完整执行域。C++ 不创建另一套 HP、攻击计时、移动位置或预算权威。每个 actor 在原顺序、原 tick 中同步执行；外部效果前写回，之后重读。

## 第一阶段接口

`CrowdMeleeKernel` 为研究专用 RefCounted。`get_abi_version()` 返回 1。初始接口 `core_crossed(a,b,c,self_radius,other_radius)` 严格对应现有 policy，不接入生产；`motion_clear_batch` 只接受已准备的 typed geometry，返回首个阻挡索引。其输入转换成本必须纳入后续 Enemy 总计时。这个阶段是扩展运行和数值合同验证，不代表 50% 覆盖。

完整内核后续按 Retarget、TickDecision、StepSelection、AdvancePreMove、AdvancePostMove 切段。同步 yield 类型为 NeedTargetGrid、NeedObservation、NeedBudget、NeedBodyQuery、NeedWorldQuery、NeedTerrainQuery、NeedNativeMove、NeedAttackAdmission、Done。每段使用即时输入及正式写回；没有跨帧快照或持久影子 action clock。

输入包括当前 actor/target 的 life、map、generation、parent、环境修订；真实当前位置、已观测目标位置、当前 step legs/index/speed/remaining budget；typed candidate/body positions/radii/eligibility。目标实际位置不能替代 last-known observed position。

## 边界

- 原始 actor 串行顺序和同 tick 最多 16 subleg 保留。
- 原 native ZERO recovery、sweep/slide、方向保护、WORLD、安全区回退及每次实际移动/回退后的即时 spatial index 发布保留。
- 攻击准入、伤害、release record、动画/音频回调由 Enemy owner 执行。回调前写回；回调后重读 life/map/generation/parent/position/action/target。
- 预算 FIFO、grant/reject、观察/决策 cadence 和调用顺序保留；不通过降频、减少怪物、碰撞或效果达到目标。
- 原屏幕 delta 的浮点运算顺序保留，不换成两个绝对 ground 坐标相减。
- 未知 actor、provider、子类或可覆写 hook 必须在任何状态写入前走原路径。
- full diagnostics、输入准备、桥接、状态写回全部留在原 Enemy CPU 测量范围内。关闭计数只用于独立因果诊断。
- SDK/编译中间物在 research outputs/native_kernel_sdk；固定官方 SDK commit，不提交下载依赖或凭据。Windows 原型先验；Android build/设备均单独验收。

## 晋级标准

ABI 和数值专项通过不等于游戏修复。每一接入段必须对同输入原路径逐项等价，再跑真实正式链；最终以同负载完整 CPU、实际移动/攻击/HP、预算等待、帧间隔和队列判定。保留每次失败原始 receipt。性能不足则不合入主树，不出包。
