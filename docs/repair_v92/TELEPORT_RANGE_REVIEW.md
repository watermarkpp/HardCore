# 瞬息移动范围来源与共享采样回归复核

日期：2026-09-22。工作树：`C:/Users/Administrator/Documents/HardCore`，分支 `codex/integration`。复核基线 HEAD：`b961cedff8040c9fc81534e094241ad9fa2330ad`，现场包含主控未提交修改。

本次只读生产、技能权威、本地原始来源与指定符号历史；按主控分工修改独占的新测试及本报告。未运行 Godot，未修改生产、人工地图、正式技能权威或已有测试，未 stage/commit/push。没有联网。

## 结论与主控裁决

用户最新明确要求瞬息移动保持局部范围，不能与随机传送卷一起全图。历史证据支持恢复已有范围，而不是另行发明数值：

- `wizard.teleport` 恢复相对施法时玩家位置的 **3.0～16.25 GU 欧氏圆环**，最多 **96** 次采样。
- 保持历史采样序列：先均匀角度 `randf_range(0.0, TAU)`，再均匀半径 `randf_range(3.0, 16.25)`。这是半径均匀的圆环采样，不是面积均匀分布，也不是方形或格点半径。
- 技能范围不随 rank 改变。现有 rank 合同只改变成功概率 `(2 * rank + 4) / 11`，上限为 1。
- 随机传送卷继续全图单元中心抽样，最多 256 次。两者保留各自的范围与采样 RNG；合法落点、精确 GU、碰撞/占用检查及应用结果可以共享。

上述为主控根据用户纠正与历史实现作出的恢复裁决，不声称 3.0～16.25 GU 是原始官方数值。主控负责生产实现与动态 RED/GREEN。

## 可复核的历史链

1. `c628509c47ab48b9962e401d3d4e3e7323d35c49`，2026-08-02，标题“迁移传送位移与落点到GU”：将旧屏幕空间 `randf_range(96.0, 520.0)` 改为 `RANDOM_TELEPORT_MIN_DISTANCE_GU := 3.0`、`RANDOM_TELEPORT_MAX_DISTANCE_GU := 16.25`。采样为 `origin_ground_gu + Vector2.from_angle(angle) * distance_gu`，96 次，随后检查真实环境与敌人占用。它证明项目既有 GU 行为，不证明原始历史技能数值。
2. `36bfb5f8` 的父提交为 `7c3019da4d3732766bdea2655abfedbea84e5b7b`。在该父提交的 `scripts/game_root.gd:7251-7254`，`wizard.teleport` 明确调用 `_find_valid_random_teleport_position(origin)`；同文件 `148-150` 是 3.0/16.25/0.25 常量；`12237-12257` 是上述局部圆环采样。卷轴 `12223` 同样调用该 helper。技能确实曾受这个局部范围约束。
3. `36bfb5f8e8c0c18269fbc2fd8e8b9dae4d700b9f`，2026-09-06，标题 `feat: integrate gameplay fixes and exact-source audio upgrade`：删去 3.0/16.25 常量，将共享 helper 改为地图宽高内随机单元中心，尝试上限改为 256。提交后的技能调用仍在 `scripts/game_root.gd:7308-7311`，没有拆分技能与卷轴，因此技能也随共享 helper 扩大为全图。
4. 同提交 `docs/UPGRADE_20260906.md:12` 的范围第 6 项明确为“随机传送卷全图合法位置抽样，保留碰撞/边界/占位校验”；`32` 记录旧 3..16.25 GU 和采用地图尺寸的实现；`39` 记录越过旧 16.25 GU 的全图测试。范围文档没有把瞬息移动列为全图修改对象。
5. 已用 JSON 精确比较 `36bfb5f8^` 与 `36bfb5f8` 的 `wizard.teleport` SOT 完整对象，完全相同。该次提交没有通过技能权威增加全图范围规则。回归来自共享 helper 被扩大，技能调用仍共用它。

## 当前正式权威和本地原始来源

- `assets/data/source_priority_policy.json:165-218` 将技能公式、几何、时序等 lane 指向用户授权的 `assets/data/vanilla_176/skills_source_of_truth_v1.json`，并排除 server_rules 对技能几何的反向覆盖。
- 当前 SOT 的 `wizard.teleport` 位于 `1933` 起；`1981` 只声明 `random_valid_map_destination`；`2006` 要求遵从 map teleport policy，`2014` 明示 `source_formula_reference_plus_project_destination_policy`。没有 radius/min/max/范围随 rank 变化的数值字段。
- 附件归档 `assets/data/vanilla_176/skill_source_package_v1_0_1/MIR2_176_33技能_Codex施工规格_v1.0.1.md:728-768` 同样只规定随机合法目标、成功概率和失败留原地，没有半径。不得从字符串中的 “map” 推断全图。
- `scripts/skills/runtimes/wizard_skill_runtime.gd:294-325` 按 rank 计算成功概率，再消费 `destination_valid` 和服务端提供的目标。它没有范围参数或按 rank 扩大范围的逻辑。
- `assets/data/vanilla_176/skill_rank_extension_policy.json:13-31` 的扩展字段没有 teleport radius/range；概率封顶为 1。`push_distance` 属于位移推挤数值，不能借此为瞬息移动发明半径递增。
- 本地 server_rules primary 实体位于 `dev_art_sources/reference/original_gameofmir/M2Server`，不是工作树根的 `reference`。`Magic.pas:951-969` 的 `MagSaceMove` 成功判定为 `Random(11) < nLevel * 2 + 4`，成功后调用 `MapRandomMove(m_sHomeMap, 1)`，没有相对施法者的半径。
- `ObjBase.pas:9810-9828` 的 `MapRandomMove` 根据目标地图高度选边缘参数 2/20/50，再从宽高抽样，不是局部欧氏圆环。该文件 SHA256 为 `65d59610b8a1f7f4dcf76058a753651d1a97997ad273fc4df8e468e65a989262`，与 2026-09-06 报告记录完全相同。这能解释当时卷轴修改所引的源机制，但不能越过技能 lane 用户覆盖和用户本轮明确要求。

因此：正式技能主表本身没有可直接抄用的半径；**3..16.25 GU 的确定来源是项目已实施历史**。用户要求恢复局部行为后，主控已选定恢复该既有合同。无需把原服 home-map 抽样、旧前冲 220 px 或随机卷轴的全图规则移植到瞬息移动。

## 新测试修订

文件：`tests/random_teleport_destination_contract_test.gd/.tscn`。本轮仅修改 `.gd`，场景入口未变。

- 删除技能与卷轴使用同一采样点/RNG 的假设。
- 增加真实局部 helper `_find_valid_skill_teleport_position(origin)` 的 64 个固定 seed：每次必须得到不同于原点的合法落点，欧氏 GU 距离位于 3..16.25，玩家足迹通过真实碰撞检查。
- 真实技能入口与该局部 helper 对照同一 seed，落点与采样结束 RNG 状态一致，证明精确落点传递且没有重复抽样。
- 随机卷轴独立对照原全图 helper，并从固定 seed 集中找到超过 16.25 GU 的合法单元中心，证明技能范围恢复不会把卷轴一起缩回局部。
- 旧半格 roundtrip 撞墙反例仍用正式比奇目标 `(78.5, 30.5)`，起点改为 `(70.5, 30.5)`，距离恰为 8 GU。
- 合法 screen ZERO 目标仍为 `(39.5, 39.5)`，起点改为 `(47.5, 39.5)`，距离恰为 8 GU。
- 墙体负例 `(79, 31)` 使用墙边合法起点，保证它在范围内，只因真实碰撞拒绝。
- 新增目标本身合法但离起点超过 16.25 GU 的拒绝用例：即使调用者传入 `destination_valid=true`，不得移动、不得报告 `effect_success`、不得创建 arrival。
- 保留精确 GU、canonical action、冻结快照、实际位移、arrival 与计划不可变检查。

固定三个起点和目标的几何先经只读数值核对，无 authored polygon overlap；运行时测试仍将通过真实 `WorldSpatialRules.environment_blocks_actor_screen_px` 重验前提，不把离线几何复核当作 Godot PASS。

## 状态

- SOT/历史/原始来源和原修改范围复核：**PASS**。
- 新测试静态差异、文件与空白复核：**PASS**。
- Godot RED/GREEN、相关回归：**NOT_RUN**，由主控串行执行。
- DEVICE TEST：**NOT_RUN**。
