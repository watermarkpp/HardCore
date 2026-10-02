# HardCore 当前施工 review 快照（2026-10-02）

仅供用户指定 Pro 远端独立审查；不合入主树、不发布 APK，不表示 P0—P6 或 v97 故障已完成。

- 施工分支 codex/pluggable-framework-v2，施工 HEAD 5d9ceb0121980ca9636d9d1cc2e19982949fbf63，活动暂存区保留。此 review 以旧 review SHA 723972322b837da1a287172c85412076df0e118d 为父提交，使新增范围可直接比较。
- 最近第三树原生受测字节 3454 文件，SHA256 a70edc8917c07b87bd3ccaf60c522076ca8c85044e37fac43590918a1d5e0af8；冻结前逐项复算零差异，冻结后再次核验。
- 引擎 4.7.stable.official.5b4e0cb0f，SHA256 d8055fb8c7e7f5010d7439ec69be051554055dae55a265f8647bd7301c34161c。未上传引擎、用户数据、真实存档、缓存、密钥或 GLM 配置。
- 第三树真实 test_mode=false 的 A→B 工作台/入包/装备/销毁/异步保存/冷重启，327+32 检查 PASS。固定 v97 新角色 500+49、v90 历史副本接 v97 523+74 检查 PASS，均是独立范围，不覆盖用户准确 B 角色故障。
- v97 报告故障仍未复现，准确触发输入 MISSING，修复 NOT_RUN。历史 false-PASS 和 fixture FAIL 按原报告保留。
- 增量1：烈火有效冷却33检查/8场景 PASS；增量3：未来所有权209检查/16场景 PASS。手机覆盖升级源码/启动/冷进程已有13相关场景 PASS，APK/设备 NOT_RUN。现有证据各有自身固定指纹，不能泛化为当前全量通过。
- 未完成：HP提交前 pending/receipt/state 容量预留；死亡回调前切profile等历史credit窄时序；receipt安全退休；journal64安全满额拒绝限制及恢复协议；P6真实90状态/360投递、并发死亡/掉落/资源/持久化排空、公平性/业务延迟/P95/P99；价格身份剩余范围和完整最终回归。第二树25 FAIL及性能 FAIL保留。
- 点燃、数值扩展和测试宝石仍默认关闭，旧HP/死亡/掉落/单planner/物品/保存权威及地图保持。

按当前 Git 源码审查。GIT_SOURCE_MAPPING.json 逐项核验 blob 与受测原字节完全一致或仅 CRLF/LF。复现原生字节时在独立候选目录先展开旧快照 SOURCE_BYTES.zip 的 source/，再覆盖本快照 NATIVE_DELTA_FROM_7239723.zip 的 source/，按 NATIVE_DELTA_MANIFEST 清除仅明确列出的旧路径并复核 TESTED_SOURCE_MANIFEST。禁止在主树/活动施工树恢复。原始 v90 存档未纳入；历史测试只保存范围摘要与哈希。

最新交接为 docs/source176_r3/USER_SCOPE_LEDGER.md。手机交付按 MOBILE_UPGRADE_MIGRATION_HANDOFF.md：同包名同签名覆盖升级，之前并行安装材料不再作为当前授权。
