# 初轮性能数据有效性裁定

运行器实际72/72 PASS，负载确实含真实数量、攻击、伤害、双宠、群死及掉落。原始文件保持原字节。

正式“同种子配对”验收：**FAIL**。测试固定了GameRoot与每个敌人的战斗RNG，但PlayerCharacter和SummonActor在_ready中各自randomize，未再固定。Enemy的独立出生朝向和音频RNG也未固定。不能把该数据集的CPU差值作为正式同种子性能验收，summary的PASS仅代表运行集合完整。

小怪10只早期轮次还与保护文件哈希扫描重叠。随后t6_quiet10的8轮确实在安静窗口完成，但随机输入缺口仍适用，不把复核冒充修好整个测量合同。

同一固定BASE 1381d283与同一生产CAND，测试探针v2补齐玩家、耐久、宠物、敌人出生朝向/音频及全局RNG输入。通过既有测试种子接口和真实SceneTree的node_added前_ready边界，保留正式GameRoot工厂。新证据独立写入t6_pairs_seeded_v2，生产源码不因测试输入修正而改变。
