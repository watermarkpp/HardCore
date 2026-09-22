# v92 收口缺口候选核对

> 历史采样说明：以下保留调查时点的候选与验证状态。主控后续生产修复、动态结果和剩余边界见 [CONTROLLER_REVIEW.md](CONTROLLER_REVIEW.md) 与 [USER_REQUEST_RECONCILIATION.md](USER_REQUEST_RECONCILIATION.md)；本文的旧 NOT_RUN/旧数量不代表最终当前状态。

核对时间：2026-09-22 16:49 +08:00。范围：`PLAN.md`、本目录专项报告及证据、当前任务相关 Git 差异、已完成 runner 汇总与指定调用点。状态：PASS（有界只读核对完成）；**本轮整体交付尚未 PASS**。这是提供给主控的候选清单，不是独立最终验收，也不是新的施工授权。

本子任务仅新增本报告；未修改生产、测试或人工地图，未执行 Git 写操作，未启动 Godot、构建、远端查询或设备操作。工作树持续由主控施工，以下状态只对采样时刻有效。用户要求依据为 `PLAN.md`、当前任务继承的明确指令，以及主控转述的最新追加范围；没有重新读取不可见的完整用户会话，也不声称已独立核对全部历史原话。

## 当前可靠结论

- 当前 `codex/integration` 与本地 `main` 均为 `b961cedff8040c9fc81534e094241ad9fa2330ad`，修复仍在工作树。该 HEAD 是基线，不能作为尚未提交修改的唯一内容身份。
- 完整 critical 已结束：`outputs/test_logs/runner_results_critical_20260922_164713_635_6132.json`，429 项中 425 PASS、4 FAIL。通过 marker 不能覆盖错误日志或进程未正常退出。
- 其后追加的 RED：`outputs/test_logs/runner_results_adhoc_20260922_164831_945_16188.json`，0 PASS、3 FAIL。主控正在分类与修复，不重复另行根因调查。
- 性能、编辑器、提示、地图分类、相机和净化并非没有工作；已有相应生产差异和局部证据。主要缺口是最新追加范围、已知失败复验、编译/Excel 更新和最终交付身份闭环。

## 待主控收口的明确项目

| 编号 | 状态 | 候选缺口与当前证据 | 最窄收口动作 |
| --- | --- | --- | --- |
| C01 | NOT_RUN | 用户最新要求深入重测蜈蚣洞系列和赤月系列密集战斗；当前本目录性能证据主要是黑暗地带 62 怪、26 近场、6 片 9 格火墙、240 帧固定场景。14.92% 是该场景 enemy physics CPU 改善，不能覆盖两系列全部追加要求。 | 将最新范围加入主计划；按真实地图和相同负载保留基线/修复后的可比证据，分别记录 CPU、渲染和设备状态。不要降低怪数、命中频率或碰撞规模来满足指标。 |
| C02 | NOT_RUN | 用户最新点名火墙高度压缩后反复出问题，要求全部 AOE 纳入公共管理，并硬性区分物理攻击与法术各自的命中、防御、伤害、硬直、释放。现有火墙/canonical 技能测试 PASS 不能证明新范围已完成；本次有界核对未得到全部 AOE 入口清单及分层验收矩阵。 | 主控沿本次明确范围核对实际消费者、公共生命周期与物理/法术独立规则，给出每个 AOE 的入口/管理者/测试对应关系；火墙高度问题须有具体触发和前后行为证据。不要把现有伤害入口统一等同于所有规则统一。 |
| C03 | FAIL | 完整 critical 的四项失败为 `map_transition_input_lock_test`、`canonical_skill_production_entry_test`、`unbuilt_planned_map_not_playable_test`、`map_release_identity_matrix_test`。前三项至少涉及真实运行/退出失败，最后一项为已定位的 ground provenance 检出换行问题。 | 用主控正在实施的最窄修复逐项复验，并记录最终完整/相关回归来源。不要将原 425/429 改称全部通过，也不要仅靠 source diff 或中途 marker 关闭失败。 |
| C04 | FAIL | 16:48 追加 RED 为 `random_teleport_destination_contract_test`、`magic_shield_map_lifecycle_test`、`player_combat_release_lifecycle_test`。这批结果晚于原完整 critical；后两项对应已有技能相机报告候选，当前仍未见 GREEN。 | 主控继续既定 RED→修复→GREEN；瞬移必须保持技能 3～16.25 GU、96 次历史采样，与卷轴全图 256 次分离，并证明精确 GU、碰撞、冻结 snapshot、arrival 与实际位置一致。生命周期测试失败先分类，不能把全部解释成旧债。 |
| C05 | NOT_RUN | 已完成的 429 项清单不含后来加入 runner 的 `wall_render_publisher_snapshot_test`、`hud_script_prefetch_exit_test`、`magic_shield_map_lifecycle_test`、`random_teleport_destination_contract_test`。`armor_single_slot_authority_test` 也不在该次结果中；采样时未见其正式 suite 登记。 | 至少获得这些场景的最终明确 runner 结果，或纳入最终合适套件。已经在完整 critical 通过的旧测试不必因子代理报告写 NOT_RUN 而无意义重跑；是否受后续修改影响由主控裁决。 |
| C06 | NOT_RUN | 用户追加衣服单槽要求已有 compiler/test 改动，但旧交付 Excel 仍绑定 authority SHA `6314ea67e689a1d65862b6d0c23e92499529dc06f62e454f17fa0b9a1ce690d3`、5897 个实际地图槽；净化报告静态核对仍为全表 6144 槽。正式 102 组去重预期 6144→6042 尚需最终编译/真实 RNG 证据。 | 使用正式 compiler 生成，检查六暗 Boss 例外、其余槽和原值保持、真实 roll 次数及 RNG；重做实际地图导出并刷新桌面与项目 Excel、单元格文本/有理数/15 件上限验证及 SHA。不要将旧 Excel 快照直接称为追加要求完成后的“当前表”。 |
| C07 | NOT_RUN | 旧概率 helpers 已从生产摘除，但 `LOOT_CLEANUP.md` 的三份历史适配测试动态结果由主控负责；compiler source-only 重建报告明确未证明整条最终生产编译。旧 critical 启动早于这些修改，不能仅凭旧测试同名 PASS 证明新 adapter/最终 compiler。 | 对现有 `loot_runtime_item_policy_test`、`progression_loot_20260913/drop_balance_test`、`loot_ui_20260914/runtime_followup_test`、P1A 动态入口及最终 compiler 输出取得相应证据，绑定最终文件身份。保留历史来源材料、命运之刃路径和动态 `_chance_denominator`。 |
| C08 | NOT_RUN | 还没有本轮固定源码提交、v92+ APK 身份/签名/内容/哈希及远端同 SHA 的交付证据。当前 `export_presets.cfg:40` 为 versionCode 82；正式 builder 支持 `-VersionCode` 覆盖，因此不把未改 preset 本身当缺陷。 | 所有授权范围和已知失败处理后，固定源 SHA；通过正式隔离 builder 显式设置大于 91 的版本，核对同包名同证书、build-info、实际打包资源、包路径/大小/SHA；完成获授权的推送并查询远端 SHA。设备保持单独 NOT_RUN，不能用导出成功替代。 |
| C09 | MISSING | 主计划除最初两项外均未勾选；部分“正在进行/等待测试”陈述已被新的结果推进，报告散落且没有最终逐项证据索引。此时仍缺一个能区分最终 PASS、保留风险与 NOT_RUN 的统一交付记录。 | 由主控在结束时更新 PLAN 和最终报告，逐项指向最终 runner/编译/Excel/APK/远端证据；保留早期 RED 和旧快照作为历史，不把它们覆写成当时就已通过。 |

## 重点范围已有覆盖及剩余边界

| 范围 | 当前证据 | 不能额外推出的结论 |
| --- | --- | --- |
| 地图编辑器原有流程 | 16:47 critical 中 `map_editor_save_path_isolation_test`、`publish_promotes_candidate_test`、`publish_failure_rollback_test`、`map_publish_restart_recovery_test`、`future_map_build_publish_no_code_edit_test`、`rv14_multi_map_publish_sibling_invariance_test`、`map_editor_workspace_delete_safety_test` 均 PASS。 | 不应误报编辑器保存/发布/重启整体缺测，也不能把这些通过自动等同于新 publisher snapshot 专项通过。 |
| 编辑器新优化渲染调用 | `map_editor_app.gd:2317` 正式 runtime 事务，`:2336` 后只对已有 plan 调共享 publisher；派生失败提示“地图已发布；优化渲染构建失败”。CLI 已只保留编排，共享实现有测试隔离目录。 | `mse_publish_entry_wired_test.gd:24` 起是源码 contains 检查，不是点击编辑器按钮的行为测试；`wall_render_publisher_snapshot_test` 是真实 service 隔离输出测试。最终报告应准确命名覆盖范围，不写成 GUI 发布全链已实操。若主控要关闭该新调用边界，可用隔离 fixture 覆盖成功/派生失败，不重建冻结人工地图。 |
| 正式渲染与 provenance | `wall_render_binding_test` 在完整 critical PASS；构建工具对实际 stage 加入 hash gate。ground 66 LF/比奇 CRLF 已有明确报告和精确 attributes 修复。 | source/png gate 的静态通过不等于隔离导出已通过；`map_release_identity_matrix_test` 的旧失败仍需正式复验。不得扩大 KNOWN 白名单或忽略 provenance。 |
| 怪物分类/地图入口 | `formal_map_spawn_policy_test`、`formal_map_destination_regression_test`、`boss_respawn_map_reentry_test` PASS；证据覆盖 67 图、2645 点及 202 个原策略拒绝请求，保留 canonical 身份。 | 不把 ID 74 的 canonical elite 与刷新 special_normal 混写；不把生成策略桥接当作修改人工地图或怪物数值。五城市成功不等于已复现并解释用户设备苍月岛回退比奇。 |
| UI 与提示 | 已有 HUD 字号按 orb 尺寸计算、数值无变化不重绘；提示 dedupe 升级可触发抢占、非法时长有校验。critical 的 HUD authority、notice overlay/item style/dedupe/action result、实际装备成功/技能学习提示、UI error scope/leak、仓库/商店测试均 PASS。 | 这些证明逻辑和结构；不证明 Android 异形屏、0.8 缩放实机可读性、多点触摸和最终包视觉手验。新增 HUD prefetch 退出边界仍见 C05。 |
| 相机与受击 | camera black budget、diamond constraint、strict edge、game_root diamond 四项及受击链相关测试在 critical PASS；镜头静态链只写 camera，不拥有 map 身份或技能时钟。 | 不需要为“有改动才算工作”修改镜头；通过测试不能证明设备镜头触感，或关闭新增跨图盾/离树动作 RED。相机 settle 测试仍保留 ≤1px 断言，不应将基于单调时间等待误报为删断言。 |
| 冗余净化 | loot service 移出 5 个历史倍率函数/旧初始化，test adapter 承接历史检验；CLI 523→46 行，共享发布 service。生成物报告发现本轮新增孤儿 0，48 个新 PNG 均被当前 plan 引用。 | 不应宣布“全仓净化完成”；67 个当前零引用旧 PNG 有基线/历史回滚归属，396641 bytes 原始数据，按本轮裁决保留。它们不是必须删除的遗漏，也不能宣称相同 APK 节省量。 |

## 文档和证据应避免的过度声称

1. `evidence/protected_source_invariance.json` 使用的是 **tracked_unchanged**。ground manifest 为恢复正式 provenance 而改变了本机检出换行；语义和 Git blob 不变，不等于所有原始工作树字节始终零变化。人工几何/碰撞未变与派生 plan/store 重生成应分别说明。
2. `PLAN.md` 的“168 overlay 改动、5976 其余槽零差异”、`LOOT_CLEANUP.md` 的 6144 槽、旧 Excel 的 5897 槽，是衣服单槽追加之前的证据。保留其阶段身份；最终衣服去重后须补新数量与逐项差异，不能继续把旧数字当作最终全表。
3. 子代理报告中的“Godot NOT_RUN”表示该子任务没有启动引擎。主控后来运行的结果应由最终索引补充，不应改写为从未验证，也不能因报告静态 PASS 就当作动态 PASS。`SKILL_CAMERA_REVIEW.md` 的两个候选已有后续 RED，须补主控裁决/复验结论。
4. `MAP_EDITOR_REVIEW.md` 的 snapshot 权威缺陷、READY 同图凭证、`GROUND_PROVENANCE_REVIEW.md` 的换行根因均已交主控；本报告不要求再做一次根因调查。收口缺的是对应最终结果与内容身份。
5. `TELEPORT_RANGE_REVIEW.md` 和用户最新范围优先：技能本地环形范围，不是全图随机卷轴的同一采样器；不能恢复此前 sampler==scroll 的错误验收假设。
6. 苍月岛原始设备投诉未复现，性能没有实机 FPS 结论，原生 Excel 交互和 APK 设备运行均未证明。正确的交付方式是明确这些边界，而不是制造根因或为补测试重置用户存档。

## 提交与交付身份注意事项

采样时本地远端跟踪 ref 为：`origin/main=b961cedff8040c9fc81534e094241ad9fa2330ad`，`origin/codex/integration=85d37077704c1083c85ee9d79f14081fff2c4dba`。这些只是本地缓存，**没有访问网络验证远端当前状态**，不能用作最终推送验收。主控应在实际推送后读取对应目标远端。

`docs/repair_v92/`、共享 publisher、部分新源文件/测试及新派生资源仍在新增/未跟踪集合；普通 `git diff --stat` 不包含全部未跟踪内容。最终主控自审需把明确属于本轮的源、fixture、导入配对、报告和必要证据一并纳入，同时保留原有未知 23 个 `.uid`，不执行宽泛清理。输出目录中的临时日志不能充当未保存的唯一最终证据。

静态 `git diff --check` 本次退出 0，仅有现有 Git LF/CRLF 提示；它不证明未跟踪新文件解析通过，也不代替最终主控对全部实际提交内容的检查。本报告未引入稳定 ID、未创建提交。

本子任务运行状态：只读核对与报告写入 PASS；Godot、APK、远端实时校验、DEVICE TEST 均 NOT_RUN。
