# 2026-09-05 审计升级里程碑 APK

## 交付身份

- 构建提交：`52ae0565856c2d99a28639b2bf0c6278186e0858`，独立 detached stage，build-info `git_dirty=false`。
- 版本：`70 / 1.19.0-audit-milestone`；包 ID `com.personal.mafaoffline`，arm64-v8a，minSdk 24 / targetSdk 36。
- 文件：`C:/Users/Administrator/Desktop/HardCore-20260905-audit-milestone-debug.apk`。
- 项目副本：`outputs/hardcore/HardCore-20260905-audit-milestone-debug.apk`；桌面副本逐字节 SHA 校验一致。
- 大小：449,193,057 bytes。
- SHA-256：`26584B871F61B2F6EC2DDDAF52432263E7D68A6B8BEA35B2A3196D59D5B21664`。
- 用户已拔下手机并明确要求回来再安装。**本包尚未安装，未做本版本实机验收**；旧手机存档、补丁及 UI 设置未改动。

## 自动验证

- APK Signature Scheme v2 验证通过（不宣称 v3/v4）；Android 可见品牌、版本、架构、启动屏主题与 runtime resource probe 通过。
- 包内 build-info 精确指向上述构建提交；12 个核心编译脚本、装备预览导入资源、586 个法术帧导入由现有探针验证。
- 正式地图闭包：实际构建 stage 为参照，67 maps、445 chunk refs、208 unique chunks、208 非空 CTEX，通过。
- 主目录原始字节参照有 126 个 JSON SHA 不同，保留 FAIL 报告；逐项证明只是 Git checkout 的 CRLF 转换，APK bytes = stage bytes，规范化换行后 = 主目录 = 固定提交 blob，JSON 语义全部一致。没有放宽原校验器，没有改写人工地图。构建 stage 为 `C:/Users/Administrator/Documents/HardCore-android-staging/52ae0565856c-20260905-172022-d8fe8765`。
- 干净 `43c8ea2e` 全量 critical 为 295/298 PASS；余下三项在干净构建提交上 3/3 PASS，零失败计数、正常退出、无超时。两项仅修测试异步预取退出时序；近战初始化超时原样复验通过。不得写成一次 298/298 全绿。
- 构建 import 中 8 个历史 `tests/runner_fixtures/*.tscn` 在两轮扫描中各报一次 BOM 解析错误（共 16 条）；属于测试夹具缺陷，不是有意失败场景的统一判定。测试目录被导出规则排除，APK 测试/fixture 条目为 0，export stderr 为空。保留日志，不伪称 import 零错误。

## 范围与保全

已验收的怪物密度性能基线合入主树；本轮审计修复见 `../../AUDIT_UPGRADE_20260905.md`。用户精确授权的比奇老兵去重仅删除 `npc_000008`，保留 `npc_000005`，82 条怪物刷新及其余地图内容不变。原有 391 项用户文件再次检查，存在状态和 SHA 差异 0。

没有借本次审计启用 Monster Streaming（仍 HOLD）、改变怪物频率/伤害/碰撞，或重做 UI/素材。地图删除中断恢复 journal、文件路径再次打开的 TOCTOU 边界、历史 VRAM 导入策略和测试夹具 BOM 属于已记录限制，不冒充全部技术债清零。

## 后续设备动作

用户回来重新连接手机后，再安装这个精确 SHA 的 APK。安装前备份并停用旧 active patch，防止旧 overlay 覆盖新代码；只保留可恢复记录，不清 UI 设置。现有三职业主档/备份与索引已为 40 级，优先只规范化圣物/徽章的空名占位，逐角色正式 checkpoint/apply/export 后核验等级、赤月装备、技能、备份与冷启动。不得无故运行 50 级或九人 QA 重建。

构建与测试证据位于本目录 `evidence/`；完整导入/导出日志保留在 `outputs/audit_upgrade_20260905/final_build/`。里程碑标签、远端与清理结果在主树状态页及最终清理记录中记录，不把本页的包完成等同设备安装完成。
