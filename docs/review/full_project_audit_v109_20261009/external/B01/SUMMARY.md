# HardCore 109 · B01 启动/预算/资源生命周期独立审查

**只读固定源：** `dbd78d3301c2af6cfd9e070abe8cc847e6353175`（parent `61d5b03f...`）；仓库 `watermarkpp/HardCore`；分支 `codex/v108-runtime-bug-review-20261009`。这不是MAIN旧HEAD和用户先前v108 APK的运行证据。**审查过程没有修改源码、没有构建APK、没有原生或Android重新运行。**

**状态：`B01_SOURCE_REVIEW_WITH_FINDINGS`，不授予产品/发布PASS。** 当前不能证明Android60FPS，DEVICE TEST仍`NOT_RUN`。本批对应`bootstrap_runtime`、`resource_streaming`和`diagnostics_budget_observability`，其他17个manifest模块不在本批范围。`game_root.gd`等大文件只审查本批入口，非全量文件覆盖。

## 主要阻塞与证据

- **B01-001（P1，源码控制流缺口）**：初始化超时通过`WorldBootstrapCoordinator.finish(false)`标FAILED，但不使generation失效。`GameRoot._run_world_build_pipeline`资源等待循环仅检查generation，旧资源晚完成后仍可能执行`background.submit_staged_build`/地图碰撞构建，外层transition ID检查在其返回之后。修复：取消权属要封死旧协程在所有副作用点；用受控晚到prefetch验证，无须手机回放一次60秒。
- **B01-002（P1，条件性资源生命周期缺陷）**：怪物图集5个ResourceLoader线程请求在局部失败、后续动作失败/错代时，`_mark_job_failed`丢弃局部数据但不完整结算已OK接受的各动作token。Godot4.7 `load_threaded_get`才减少token的user_rc。修复：每job实际accepted的动作路径单独计数并终态消费；不在战斗中强制join。
- **B01-003（P1，条件性资源生命周期缺陷）**：`WorldBootstrapCoordinator.poll_threaded_prefetch`失败状态只标记、不get；`_internal_begin`清掉旧generation manifest及已加载资源，使未消费的accepted tokens失去追踪。修复：保留旧generation仅用于退役的token ledger，禁止晚到写当前map。
- **B01-004（P2，条件性资源生命周期缺陷）**：`StartupLoading`角色选择场景加载FAILED与`MonsterSourceFrames`贴图加载FAILED路径没有和已OK接受的token形成对称get；主场景预取却已实现失败终态get，提供可复用模式。
- **B01-005（P2，确认的fixture BUG）**：`tests/safe_logout_pending_retry_repair_20261009.gd`调用`LootRuntimeScript.new().roll_monster_drops(...)`，该Service`extends Node`，预览对象无free/树所有者。测试runner`PASS`与stderr `13 ObjectDB leaked / 3 resources still in use`同时存在；**这里只能确认至少1个夹具Node漏，不能把所有告警归因于它**。

## 性能策略/发布前缺口（不是已证Bug）

- **B01-006**：人物移动事件的即时唤醒会以`FrameBudget.begin(..., true)`必要计账，补步和重复移动可能造成同process多个同步空间查询。用户已授权即时激活且无需optional/8候选上限；不得据此恢复分页。提供的10次移动回调13,847us最大2,113us仅观测压力，不是全Android帧耗时。
- **B01-007**：仓库`export_presets.cfg`固定版本`version/code=82`；既有v108 APK通过独立打包命令得到版本108，不代表109一定错误。109构建前必须核对真实覆盖及最终包`versionCode=109`、包名`com.personal.mafaoffline`、签名和存档兼容。

## 证据约束与保护

B01没有把已修的`PERSISTING→SETTLING`、`pending`退出重试、投影失败后事件恢复、释放owner拒绝复述为现行BUG。已读followup direct05 / direct06 / direct09数据，旧直接runner确有相应专项PASS，但没有代替静态发现的缺失场景。固定JSON manifest过大，GitHub文件接口返回空正文；通过授权设备**只读** `git show dbd78...:AUDIT_SCOPE_MANIFEST.json`解析完整20模块/6168路径，仅提取B01模块，**37个未上传local-only文件一律MISSING，不算已审**。

## 主控最小处置顺序

1. **先锁定地图加载超时/取消的generation与transition双重权属**，做一项受控晚到资源合同。
2. **分别修正三个ResourceLoader owner的accepted/terminal-get收尾**，用故意失败、部分成功/失败和转图取消的正式合同验证。若需要先复现才能修改，直接留`BLOCKED_PENDING_REPRO`，不可凭当前退出告警认定是生产token漏。
3. **修正固定测试中临时Node生命周期**，复跑这一项必要退出测试并保存原始stderr；余下对象/资源仍泄漏再用`--verbose`列ID/类型追所有权。
4. **发布109之前**做完整source/输入指纹核对与Android签名/包名/versionCode/设备实测；不准因为B01静态审查或单项PASS提前导出。

具体每项触发条件、最短链、修复及最小验证见`FINDINGS.json` / `.csv`；逐文件阅读状态和SHA见`COVERAGE.json`与`SOURCE_BINDING.json`。该包不附私人Page：当前会话没有经过验证的私人Page创建接口，不存在真实PageID。
