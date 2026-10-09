# Batch 01 — 启动、预算与资源生命周期

状态：NOT_RUN。固定提交由主控正常推送后的派发收据给出；不能使用主工作区旧HEAD。

本批覆盖 `bootstrap_runtime`、`resource_streaming` 与 `diagnostics_budget_observability`，并追踪必要消费者。其它模块保持未审查。先读同目录标准提示词和范围清单，以实际指定提交为准。

## 本批正式入口

- `project.godot` / `export_presets.cfg` / `scenes/main.tscn`：autoload、process配置、场景绑定、导出过滤与当前版本。
- `scripts/game_root.gd`：`_ready`、`_process`、`_physics_process`、`_exit_tree`、bootstrap/map READY/转图/取消、暂停与安全退出、资源准备与激活事件泵送。这个大文件会在其它批次继续审查其它职责，不能因本批读了部分函数就算整个文件已覆盖。
- `scripts/world_bootstrap_coordinator.gd`、`scripts/game_data.gd`：阶段、配置就绪、失败/重入和唯一资料权威。
- `scripts/layers/runtime/execution/frame_budget.gd`、`time_domains.gd`、`world_context.gd`、`paused_receipt_pump.gd`：每帧epoch、必要/optional账目、FIFO服务、scope闭合、暂停后回执和取消。
- `scripts/features/runtime/feature_resource_preparation.gd`、`scripts/features/contracts/feature_resource_lease.gd`、`scripts/features/compilation/feature_resource_registry.gd`、`scripts/skills/skill_resource_service.gd`：预备、共享、去重、lease释放、失败和退出边界。
- `scripts/monster_visual_streaming_coordinator.gd`、`scripts/prepared_music_stream.gd`及实际调用到的资源服务：异步完成身份、退场后回调、refcount与Node/Callable持有。
- `scripts/runtime_diagnostics.gd`：观测开关、计时嵌套、正式性能与observer成本区分。不要因没有设备测试而报源码bug。

## 已知重点与未闭合项

1. 范围内全部合格冷怪必须即时激活，不能恢复8候选限流或300ms入战等待。当前十次同process真实movement信号在30怪上有10次空间查询；本地回调总计约14.1ms（direct06，observer开启，激活专项冻结后续actor physics）。这是有限调用压力，不是真实补步或107/Android FPS。请审查可缓存的候选范围与身份、revision失效、重复事件，以及必要工作峰值能否降低而不漏新进入的怪物。
2. 一次投影暂时失败保留当前地图/代际的去重事件，站住不动在正式process pump恢复后仍应激活；不能引入tight retry/world scan。
3. 退出的临时pending与真正FAILED已经分开。安全退出不能重复奖励或绕过真实保存失败。
4. `safe_logout_pending_retry_repair_20261009` 44个功能断言/退出0，但stderr有13 ObjectDB泄漏和3 resources still in use；旧death_queue_lifecycle同样有8/3。请找实际资源/Callable/对象循环的所有者与释放边界；不能因runner聚合错误数0便写“无引擎错误”。区分fixture持有与生产生命周期缺陷。
5. 主控刚修typed owner身份的`int(null)`边界；非法/缺失current_map_id或_zone_generation应拒绝，有效Player/Summon归属必须保留。不要把已修点重新当当前bug，若仍有释放实例访问给出当前精确控制流。

## 交付与覆盖

按标准提示词输出本批 `SUMMARY.md`、`FINDINGS.json/csv`、`COVERAGE.json`、`REDUNDANCY.md`、`VALIDATION_GAPS.md`、`SOURCE_BINDING.json`；可生成文件时提供ZIP，同时在主回复保留可读取的完整发现摘要。

逐文件写实际读取状态，大文件按已覆盖函数/职责记录；没有源码权限或读不到指定SHA就停止作判断并标BLOCKED。后续root核对已修正中文路径转义清单错误：B01含十个中文authoring输入。26个退役格子试验路径与两个Android build/preflight助手不在B01，不能假称从远端审过；后两者另行固定，格子试验不恢复运行时。B01派发原文保留原清点数字用于追溯，以本次实际SHA访问结果为准。

只读，不改源码、不构建APK、不改变玩法。主控核实发现后修复，必要验证后再派下一批。
