# B04 冗余候选与不可删除边界

固定源码：`172125ae99e3c4adf19af82da2720934a52f9537`。仅记录证据，无生产代码或资源删除。

1. **历史概率资料 ≠ 当前重复掉落算法**。`dpv2_direct_baseline_v2.json`、`dpv2_single_player_drop_boost_v1.json`、`dpv2_single_player_effective_probability_v1.json`、`dpv2_repair_v5_contract.gd`、`single_player_balance_v80*.json`和`user_additions_v81.json`在当前用户Sheet概率链中**没有二次倍率执行权**，但仍保留原验收、审计与生成来源。不得因“正式LootRuntime未调它们”直接删除，否则破坏溯源、fixture和历史闭包。
2. **Feature DeathBurst ≠ 第二个经验/掉落结算**。`scripts/features/handlers/death_burst_handler.gd::commands`仅在严格chain/fact约束下构造未来child-command；当前effect registry需发布与子请求端口，不能将它当作自动多次roll引擎；不能将未确认发布状态的类删除。
3. **Rune/SocketGem规则**：`scripts/items/rune_item_rules.gd`与`socket_gem_rules.gd`通过`default_enabled=false` fixture/source SHA检查，非本轮正式开放的血钻镶嵌玩法；保留兼容测试与物品编码器边界，不得仅凭类存在宣布玩法已上线。
4. **视觉名称含“死亡”的地图不是死亡奖励文件**：共68个地图runtime/visual/editor/chunk/plan路径被自动归入`death_revival_drops`；它们由MSE制作/发布，用户明确禁止本审计修改人工地图。已记录Git身份，转交地图B06而非判无用。
5. **LootFeedbackLayer的MAX_TOASTS=3与一次仅一条**：源码`_start_next_pickup_feedback`在已有toast时拒绝入显示队列，生产常规一次最多显示一条，另两套Panel仍被预分配。这是布局资源可优化候选，但UI也可能由测试/后续布局依赖。没有CPU/GPU对照、不在B04删除，不能把微小删节点当作60fps突破。
6. **LootPreparedFile与JsonPersistenceService**：前者准备隔离文件/校验字节，后者完成正式异步序号与提交promotion；职责不同，不能因都写JSON而认定第二个存档权威或删除。
7. **装备视觉目录/头盔sprite、历史只读证据** 保持正式source与fixture对应；本轮未校验每个pix/asset，不报告为“未引用即可删除”。

删除门禁：反射call、.tscn、preload、fixture、编辑器和旧存档引用都须在B07/B08补齐才可决定；本轮删除：**NONE**。
