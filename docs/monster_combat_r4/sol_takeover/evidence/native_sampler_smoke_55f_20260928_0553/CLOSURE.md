# 原生性能采样边界

旧八份 quiet full AoE 数据每份记录 600 行，实际却跨越约 618–674 个物理 tick；其 CPU 警告保留。原因已用真实慢帧反例证明：先等 physics_frame 再等 process_frame 会漏采原生 catch-up tick。

探针现在只在最后优先级的测试节点观察每个原生物理回调；生产 actor 优先级、时钟、动作、公式、伤害、掉落和存档路径保留。另记录独立有界 process 回调间隔，首间隔为空，不能把部分间隔当完整帧。pairs 及 summary 工具要求恰好 600 个连续 tick。

原生单位反例 PASS：scoped_sampler_warehouse_red_55f_20260928_0548/native_physics_sampling_test，正常退出 0、无错误。普通/真实 50ms idle 阻塞各 48 个连续物理回调，观察时 actor 已执行；同条件下旧探针漏采 23 个回调。首轮类型推断错误原始日志保留。

实际生产路径冒烟：small 10、aoe_death_loot 30 均 PASS，正常退出 0、无超时、无引擎错误，每项恰好 600 连续 tick。AoE 实际 127 次死亡及 106 个掉落节点，后台写盘与实际生产结算开启。两个子目录保留原始 load/runner/stdout/stderr。此处仅验证测量工具和有效负载，不是 AA/AB 性能验收。

后续 BASE 必须先保护旧测试 overlay，再同步相同探针/场景/runner 字节；生产 BASE 固定 1381d2838a3736f4a06699dd24a8cf4a10714950。旧性能接纳 FAIL 未关闭；GPU/DEVICE NOT_RUN。
