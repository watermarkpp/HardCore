# Headless 预加载与死亡测试时钟

本次只在 DisplayServer=headless 时，将 world manifest 与 UI item texture 两条已观察到的预取入口改为主线程创建资源。正常窗口和 Android 保留异步入口；monster streaming / summon 的专项异步合同不改。仍读取相同 imported 资源，保留 required 失败门、缓存、代次释放，不放宽 runner 日志规则。

Godot 4.7 dummy renderer 纹理 RID 并发问题的上游记录：[issue 121949](https://github.com/godotengine/godot/issues/121949)、[PR 121958](https://github.com/godotengine/godot/pull/121958)。本地引擎未升级，此变更不是引擎全面修复，也不证明全部 headless 路径无竞态。兼容测试的显式 async override 只覆盖原分支合同，不替代正常渲染/设备验证。

修正前固定 3 场景各 3 次的完整基线保存在 evidence/rev08_baseline；包含失败、allowlisted texture 错误和退出资源告警，不是严格零错误的 9/9。最终候选固定矩阵仍需独立记录。

smoke 原先以墙钟 5 秒等待生产 SceneTreeTimer。失败现场死亡队列已 COMMITTED、requests=[]，Actor 等待死亡展示；ID18 动画与尸体保留合计约 2.833 秒游戏时间。同窗口 UI prewarm 阻塞约 3.217 秒，墙钟与帧时钟不同。测试改为同样的 5 秒累计 process delta，runner 60 秒保留总墙钟 watchdog；Enemy 生命周期未改。两次原失败证据保留在 evidence/smoke_death_clock_failure。

当前未提交工作区验证：runner_results_adhoc_20260909_142921_097_7992.json，2/2 PASS，自然退出、无断言/超时/非 allowlisted 引擎错误。smoke 记录 game_seconds=2.858019、wall_seconds=4.587；stderr 仍有退出资源占用告警，不能称原始日志零 ERROR。证据在 evidence/headless_prefetch_compatibility。后续性能 A/B 必须两侧应用相同 headless 策略。
