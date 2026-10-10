# B09 静态 / Native / Android 验证缺口

source_commit: 267890c88477c0b1afaaaea612780c131c86736d

## 真实状态
固定Git 22/22 blobs原始sha及source_commit验证PASS；383/383区间完整读取与哈希PASS；R67/67旧body逐字一致；272目标区间仅完成边界静审，111区间只完成body/控制流索引。全文件/所有真实caller与生产语义全绿MISSING。B09引擎、109APK、设备、真实存档NOT_RUN。

## 新缺失负例
1. B09-001：隔离丢失或损坏 personal_expansion_001 manifest与其一条必需maps/items tables，必须由ContentLayers返回明确源错误，GameModes/Profile admission拒绝且旧activeExpansions、catalog/数据、signal和存档不可部分提交。later_176_content无data与user_equipment元数据合法正例保留。
2. B09-002：严格相同Git LF字节与Windows CRLF工作树，用真实CodeGuard.source verified→Shader valid_asset→Script valid_target→租约保留scene；同时内容改一字节、错instance、epoch和cancel负例全部拒绝。须保留完整native exit/engine/source/scene/run/invocation/failure receipt，不能只看静态HASH或中途PASS。
3. B09-003：真实CharacterSelect大厅A→B、DeviceLab当前GameRoot在场/异常rollback、同一PlayerVisual前后数据库通知与equipment_changed的最终纹理/角色字段；没有真正可观察问题不能报功能BUG或随意延后正式通知。

## 资源及地图仍未闭合
FeatureResourcePreparation共享native同路径多客、FAILED/INVALID/ERR_BUSY、IN_PROGRESS取消、请求与Get次数、service shutdown与场景替换、callback重入、retire重复提交、strong-resource缓冲、CodeGuard变化、旧owner与新owner严格隔离：缺少同源原生故障矩阵。
MonsterVisualStreamingCoordinator旧地图未完成的五动作Texture2D requests、转交ContentLayers退休、缓存W/L waiter身份、same-key重用、map pin和decoded RGBA8预算、具体帧延迟/30真怪CPU：仍NOT_RUN，不以减少怪数、延长攻击来优化。
StartupLoading首个真实CG画面/authoritative steps/失败retry，CharacterSelect场景变更前opaque覆盖、旧generation/ResourceLoader ERR_BUSY、主场景预取/异步handoff与正在加载时用户退出、GameRoot/WorldBootstrap READY/失败到安全点、UI输入/音频恢复：原生及真机缺口MISSING/NOT_RUN。
AndroidExportRepresentationVerifier检查实际APK sealed representation，但runtime_native_image_sha=MISSING、native_token_device_acceptance=NOT_RUN不可提升；109包必须由主控核验原com.personal.mafaoffline签名、版本、完整内容/引擎源指纹、设备升级及用户旧存档兼容。

## 审查非BUG与人类决策
ContentLayers的resource registry缓存跨mode换源需要证明确有来源override后才升级为生产BUG。旧B08 Native69只复用相同源码/输入的读档admission，原始stage FAIL不覆盖。玩家 HP/技能/碰撞/移动/概率/ID127非掉落角色选择保持原合同。ID127仍BLOCKED人类选择；本批不恢复26退役网格文件。

逐文件/函数剩余具体责任在COVERAGE.json，383条任务及15条跨链在CROSS_BATCH_CLOSURE.json；静态不能授予全项目/Android或109正式上线PASS。
