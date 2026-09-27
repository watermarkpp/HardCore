# c046 固定源码累计回归失败（原始完整结果）

固定HEAD `c0461f25ab2d02f2ea304dcf43be36cb868ab9d0`。完整542项已实际完成：539 PASS / 3 FAIL，进程退出1，expected/actual精确集合一致，1626份原始日志均核验。completion.json、exact_execution_check.json 记录实际身份与退出。

以下保留执行期间的原始诊断和候选，不能把历史候选直接当作根因。后续真实反例及关闭证据分别在 ../portal_shape_closure/CLOSURE.md 与 ../classic_boss_closure/CLOSURE.md；旧完整结果不改写为 PASS。最终新源码 full critical 仍 NOT_RUN。

## map_release_identity_matrix_test

原生退出1、stderr/engine失败各1，1351 checks/1 failure：要求 one_way shape violations 精确等于旧C5集合 `[[916004,916006],[916005,916007]]`，当前实际为空。不是中途PASS或timeout。

原测试第26–32行把这两项缺陷写为必须保持的集合，以便修复时触发复核。它们正是授权修复的A/B→祭坛/巢穴两条单向连接；a1f已将one_way=true及明确原因进入作者文档，正式发布器 `_configure_one_way_endpoint`按正式网络配置导出正确role/flag。所以旧预期被真实修复触发，不能为恢复旧测试而恢复传送缺陷。

后续：完成整套后保留RED，按明确新合同要求形状违例为空，并补真实负例确保flag/role/reason丢失仍被拒绝。原身份/build/source revision/双向/发布隔离全部断言保留。

另外发现作者A/B的旧 `portal_role`仍写bidirectional（正式发布器在准备阶段转换正确role）。要核对该原作者文档是否在地图编辑器直接校验路径仍失败；先原生验证权威源与正式准备链，不能只改测试或手改生成结果。若确认作者政策缺口，精确修这两条作者元数据，再正式单目标发布；不改坐标/地图/碰撞/spawn。

## classic_boss_order_test

原生assert错误第104行：触龙神范围攻击没有结算主目标伤害；进程未正常退出，effective=-1。所有之前release/snapshot形状/ID/ground_exact断言已通过，但这不证明投递或扣血正确。

下一步保留该原始FAIL并实际追踪 `last_magic_attack_resolution`、冻结目标代际/实际投递及HP前后，不能先假设身体准入问题或用旧PASS跳过。源码提示：夹具只固定Player物理防御/HP，未固定 PlayerState.computed_stats 的法术闪避/MAC；真实 take_direct_spell_damage 使用后者，且玩家RNG默认randomize，合法magic_evaded会使无条件HP下降断言失败。该提示目前仅候选，需要实际确定性RED/trace证明。禁止改生产闪避概率、过滤观察记录或吞伤害；若确为夹具前置不足，明确成功用例与合法miss反例，保留真实范围和伤害断言。

## 全门点地形补查（只读候选）

当前67个正式运行地图的132端点：全部整数格坐标、design范围内、中心格均不在blocked_tiles。原始结果 endpoint_terrain_cell_candidates.json。仍需使用实际polygon collision消费者检查既定18px人物身体；不能把这个格中心扫描写成完整碰撞PASS，也不能自动移动人工门点。

地图编辑器生产路径 map_editor_app._on_build_candidate_pressed 直接将current_document传给approve_for_runtime/build_candidate，两者调用ConnectionPolicyService.validate_document；正式publish工具则先prepare_formal_document。A/B两旧role因此是可复现候选，应原生RED后修精确作者元数据。当前等待固定c046完整回归结束，未修改任何生产或测试文件。

## 注册集合补查

比对当前542实际期望与R4目录场景发现5项不在critical：body_radius_bucket_boundary、body_radius_index_consistency、natural_cadence_fault_variants、r3_common_natural_probe、t6_real_load_probe。后两者依赖明确BASE/CAND/env矩阵，保留专用runner；natural_cadence_fault_variants仅继承已注册damage_attribution_counterexamples的历史别名，无独立测试逻辑。前两者是独立实际工厂/跨桶反例，最终必须正式注册并执行，不以先前专项PASS替代累计注册。当前固定执行中不改runner，结束后处理。

## wall_render_binding_test

新增实际FAIL，原生退出1。真实消费者检查60个已优化地图，恰好ChoiceLand/PassageA/PassageB三项 source_runtime_json_sha256 仍绑定旧运行JSON，报 runtime json sha mismatch。前一传送重发布遗漏派生墙计划更新；不能以地图传送PASS替代绑定验收。

根因路径已核对：map_editor_app._on_publish_runtime_pressed 在成功runtime发布后会检查既有wall_render_plan并调用共享MapEditorWallRenderPublishService.publish_map；本轮新增exact single formal CLI工具遗漏这个既有步骤。应只补齐工具对既有plan的正式共享发布，原CLI/编辑器服务保持同一生成器，不手工改派生hash，不放松消费者校验。

只读比对原始portal_intake.before_publication与当前三运行地图：design、instances、visual_asset_snapshot均deep-equal。待原生重新发布后必须证明三plan除runtime binding外内容保持、引用PNG和其余57plan不变，再实际wall_binding60及publisher_snapshot回归。当前整套仍运行，生产及测试未改。
