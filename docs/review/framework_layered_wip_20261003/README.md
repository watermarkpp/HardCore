# 分层移动与最终回归：施工中审查快照

2026-10-03，第三棵候选树。用户授权将当前困难固定推送，请 dots 一起研究。**状态 FAIL；最终验收 NOT_RUN。** 本快照不是主树集成、APK 或设备验收。

审查父提交 `dc1ebf3fea1d047d4e18b352140a50b593223cea`；施工树 HEAD 仍为 `5d9ceb0121980ca9636d9d1cc2e19982949fbf63`。使用独立 Git index 构造审查提交，保留第三树既有未提交现场，保护主树 v97、第二树和真实存档。

当前原生内容指纹 `d615e31c07d3cd6ac14dee5e9f1a2889aa77ff85c490928f0390add9f7c5f86f`，3566 个源码/数据/场景/工具文件，73 个父版本增量。引擎 `4.7.stable.official.5b4e0cb0f`；console SHA256 `d8055fb8c7e7f5010d7439ec69be051554055dae55a265f8647bd7301c34161c`。原生字节与 Git 行尾的关系见 `NATIVE_GIT_TRANSPORT_MAP.json`，完整原生字节在 `WIP_NATIVE_SOURCE.zip`。

## 当前困难及可复核入口

1. 实时运行下，玩家起手后的正式 `SceneTreeTimer` 与 Root 的 physics 模拟钟不是同一时钟。`stage_f_final_layered_critical` 的首次效果于 583333us 开始，到期于 4583333us。第二次输入于 4000000us 发起，按第一次实测起手延迟预测应命中到期 tick，但实际第二次释放在 4600000us；相差 16667us。因此“严格同一 tick”断言 FAIL。其余死亡身份/收益检查没有因此被重标失败；cold 明确拒绝失败 producer。这是先观察到的测试边界不稳定，尚未证明自然 UI 故障。
2. 为精确构造同 tick，当前试验仅对 `death_burst_lifecycle_test.tscn` 和 `death_expiry_overlap_test.tscn` 使用官方引擎参数 `--fixed-fps 60 --max-fps 60`。三个实际 process delta 均为 1/60；physics TPS=60、time_scale=1。没有替换 Root pump/时钟、原600ms起手、周期、持续时间、HP、planner、writer或预算。
3. 固定步进下同 tick 成立，却触发原有实际投递迟到门禁。`boundary_fixed_step_paced60` 原生 **0 PASS / 4 FAIL**，无超时，源码在运行前后相同。burst 360 次投递、90 状态到期，最大实际投递迟到 **2966667us**；overlap 182 次投递、90 状态失效，最大迟到 **1966667us**。两个 live 各只有“小于一个原周期”检查失败；两个 cold 都因 producer FAIL 正确拒绝。
4. 先前不带 `--max-fps` 的 `boundary_fixed_step_clock_probe` 也得到同样的最大迟到。官方 `--fixed-fps` 会关闭实时同步；`max_fps=60` 和固定 delta 本身不能证明墙钟已按60帧限速。因此当前尚不能将这组迟到直接归因于自然战斗调度或宣称性能回退。固定步进 wall_usec 仅保存观察值，不用于实时性能、GPU或Android结论。

请 dots 优先独立核对：实际模拟钟推进与墙钟服务预算的关系、Godot fixed-fps 与 max-fps 的实际限速语义，以及怎样通过完整生产输入稳定构造到期/死亡同 tick，又不替换生产调度、不削弱迟到门禁。若认为是生产缺陷，请给出实际消费处与预算申请的因果链及可证伪反例；不要增加预算、任意延迟、减少目标或改周期来制造 PASS。

直接源码入口：

- `tools/run_godot_tests.ps1`：仅上述两个静态边界场景的引擎参数；cold、自然场景、R3、ABBA保持原实时环境。
- `tests/framework/death_burst_lifecycle_test.gd`：正式输入、30个非重叠静态receiver、首次延迟观测、第二次起手、同 tick 和原迟到门禁；`death_expiry_overlap_test.tscn` 使用其 overlap 分支。
- `scripts/player.gd`：`_emit_attack_after_windup`、`_emit_magic_after_windup` 的正式 Timer。
- `scripts/game_root.gd`：physics 内模拟钟推进/效果 pump、process 内同一 runtime 的补充 pump。physics pump 已位于该处理段前部，不应凭猜测再调顺序。
- `scripts/features/runtime/effect_runtime.gd`：`pump`、实际周期消费及实际投递迟到统计。
- `scripts/layers/runtime/execution/frame_budget.gd`：同一 process epoch 的墙钟额度、在途外层开销和公平调度。

原始失败、receipt、runner native exit、invocation/run/source关联、trace和原命令见 `RUN_INDEX.json` 对应目录。`boundary_fixed_step_direct` 的引擎参数字符串 guard 失败单独保留；Godot 会消费已识别的引擎参数，后来改用实际 delta 检查，这次早期 FAIL 没有被擦除。

## 已保留的阶段成果，不外推为当前全部通过

E 源码指纹 `fff09f90078c59d9cc6bb89cf45a0d21dbf937e46e7f692fa5e9fe192b093501`：80项重点、29项边界/存档/原反馈/围堵、4项即时死亡、77项剩余R3，共 **190次成功原生尝试**（不是190个唯一场景）。完整 DeviceLab runtime 在该阶段 PASS；旧基线 FAIL 保留。R3/反馈清单覆盖和逐次结果可按 `FINAL_R3_COMPLETION_LIST.json` 与 `RUN_INDEX.json` 核对。

E 的同 tick 专项曾 PASS，但随 F 重跑出现上述16667us偏移，不能据此前通过宣称边界稳定。E 的独立重算在 `STAGE_E_FRAME_RECOMPUTED.json`：自然4373帧，P95/P99/max 14698/18437/29322us；指定30目标各3来源，921次周期投递，最大实际迟到683333us；四轮对象/资源/owner观察只限定该有界运行，不证明无限运行内存上界。

F 源码指纹 `db50a12ee1deb2a25eb4f0ffe807f9da1bd6539dfe5b1e1b982680a8102c1c66`：仅修正 R4 夹具把8秒 READY观察窗口错误包含同步场景加载的起点，并在未READY时停止构造战斗夹具。原总窗口、20次起手、攻击间隔与通过断言不变。三项重场景使用用户条件授权的90秒窗口，**3 PASS**；24场景20次起手/20次结算，战斗采样59161ms、退出72257ms。此后80重点为 **78 PASS / 2 FAIL**，失败为上述 overlap live 与正确拒绝的 cold。90秒性能与60秒的可比分析仍未最终关闭，不能用更长窗口宣称提速。

当前 G 相对 F 只增加静态边界固定步进试验的 runner 与夹具观测。E/F/G 原生before/after各自保留；不同内容不混为同字节最终回归。没有任何 current-G 全套最终采用行，`final_accepted_rows=0`。

## 此轮生产增量及范围

生产文件只有四个：`scripts/enemy.gd`、`scripts/game_data.gd`、`scripts/inventory_panel.gd`、`scripts/player_state.gd`。

- 怪物分层接近：远处先沿合法方向和既有有界路段接近，近处使用玩家周围8个合法攻击站位。保留真实地形/body检查，拒绝非法整段；真正受阻报告阻塞原因并维持移动动作。没有降低怪物数、速度、攻击节拍或碰撞合同。
- 稳定物品身份/显示字段与空装备槽测试payload修正：严格使用既有稳定 ID，保持单一主源。新业务 ID：无。其余为生产路径夹具及验证工具增量，详见 `SOURCE_INCREMENT.zip` 中的原始 diff。
- 怪物死亡碰撞同步消失通过原生Physics2D、占位/邻怪通路在无await同栈检查补证；未通过延迟或第二碰撞服务规避。
- 同名角色创建在正式入口已拒绝，测试检查实例、角色数和保存链不变。没有自行增加模糊相似度名称规则。

## 独立开放项

- 当前固定边界与原迟到门禁 **FAIL**，根因裁决尚未完成；最终当前同源码回归 **NOT_RUN**。
- 分层移动最终ABBA与自然持续P6/R3完整性能结论 **NOT_RUN**；以前CPU、frame interval描述性比较及旧V4失败仍按原范围保存。
- 真机、Android/GPU/热机 **NOT_RUN**；关机 ObjectDB warning 仍需按证据分类。
- 原始 v97 第二角色 B 存档输入 **MISSING**，新角色/v90不能替代因果验收。
- 掉电、内部写入边界强杀及外部有效旧primary整体替换矩阵 **NOT_RUN**。此前有界进程强杀结果不能扩大成全故障矩阵。
- 主树合并、APK、签名、安装及发布不在本次快照授权范围。

所有场景使用仓库 runner、console/headless、项目日志和隔离 APPDATA；没有触碰真实用户数据。推送完成后向用户指定 dots 发出精确SHA与研究问题，施工主控继续处理独立事项。
