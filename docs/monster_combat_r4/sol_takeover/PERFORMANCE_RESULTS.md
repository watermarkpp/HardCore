# 原 R4 性能证据裁定

当前正式性能矩阵状态：NOT_RUN。待固定最终源码后执行 v4 全部 72 个串行样本。

## 比较合同

- BASE：1381d2838a3736f4a06699dd24a8cf4a10714950，独立缓存及用户数据，仅叠加同字节探针和 runner。
- 当前候选源码：257d50bd006b02c606b964c44fa947f92efc48e3。最终矩阵身份以实际 identity.json 为准。
- small / large_pets / aoe_death_loot，每类活怪 10/20/30；每样本真实 90 帧预热、600 帧采样，每采样回调维持声明活怪数。
- 每条件两次 BASE A/A 估计噪声，三对 BASE/CAND，AB/BA/AB 串行顺序。每样本独立进程，禁止同时 Godot、源码变化或重哈希/提交。
- 相同只读引擎和原素材，独立已导入缓存。没有强制清 OS 文件缓存；不宣称冷启动或手机 GPU 结果。
- actor/player/durability/facing/audio/global RNG 与实际 canonical cast 的 seed 输入完整固定、保存。测试子类仅固定原函数的 wall-time/profile hash 输入，保留原 serial 递增与全部正式玩法/物理调度。
- bootstrap 结束后 PlayerState.test_mode=false；独立测试 profile 通过真实 save_game(false) 初始化，正式死亡时钟、掉落预算和后台队列开启。每样本必须有真实声明负载；终态 FAILED 作负载无效，不以 runner marker 掩盖。
- 记录真实敌人 callback CPU、callback 间隔 P95/P99、超过 33/50ms 数量、physics tick 差异和实际伤害/宠物/死亡/掉落/队列规模。引擎窗口平均值不冒充逐帧耗时。

## 保留的旧数据

| 数据集 | 裁定 | 原因 |
| --- | --- | --- |
| t6_pairs / t6_quiet10 | FAIL | runner 通过负载门，但 player/pet/facing/audio 随机输入未完整固定；初轮 small10 又与保护哈希扫描重叠。不能作为正式同种子性能结论。 |
| t6_pairs_seeded_v2 | FAIL | 72 个实际 runner 通过；canonical cast seed 仍含 wall-time，技能/宠物跨树输入不等同。small 非施法样本只作局部参考。 |
| t6_v3_validation | PASS | 3 个实际探针完成并保存 canonical seed；test_mode=true 绕过正式后台掉落限额，所以仅验证 seed 夹具，不是正式热态性能。 |
| t6_v4_validation/aoe_death_loot-10-BASE | FAIL | 正式热态死亡 56，但独立 profile 未初始化，save_failed 导致 0 正式 roll/commit；原流水保留。精确失败探针完整源码身份 MISSING，仅保留后续 patch，不能补造。 |
| t6_v4_profile_validation | PASS | BASE AoE10、CAND AoE10、CAND 双宠10 均实际正常退出、热态 false、完整 seed 输入；CAND AoE55 roll/54 commit/40节点/56死亡且 FAILED=0。属于三项负载预检，不能替代最终72轮。 |

v2 AoE10 的敌人CPU差值约 +0.03019ms，三次均超过当时 A/A 噪声约 0.015765ms，原警告保留。它既不能被静默忽略，也不能用输入不完整数据作最终退化裁定。待 v4 的有效完整配对复核。

## 当前外部验证

GPU：NOT_RUN。手机：NOT_RUN。APK：NOT_RUN。不得据 headless 平均值承诺手机丝滑。
