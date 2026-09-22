# hardcore 1.0 正式版 · v80 交付

- 源码提交：`fa4a1ffa88f7d2ec20d83a8548afc2d4b99d1393`，已快进合并至 `codex/integration`。后续交付文档提交不改变 APK 源码。
- 版本：80 / `hardcore 1.0 正式版`；包名 `com.personal.mafaoffline`，显示名 `HardCore`，arm64-v8a。
- 桌面成品：`C:/Users/Administrator/Desktop/HardCore-1.0-v80-release.apk`。
- 大小：465,996,946 bytes。
- SHA256：`D8B9E5FF0C395F354997A0F0ED8E7E4F996C1433191D07C04CA5C7F76746F52D`。
- 沿用已安装版本的兼容 debug 签名/导出方式；证书 SHA256 `C62D0F8239B926F819038845C302143FD24DCFD75ED8D877ED846C430C6F3FCC`。版本高于 v79，同包名同签名覆盖安装资格 PASS。旧 v78/v79 APK 保留。
- 源码里程碑：`milestone-hardcore-1.0-v80`，固定以上 APK 源码，旧标签不移动。

## 验证

| 项目 | 结果 | 证据 |
|---|---|---|
| 本轮实现及相邻回归 | PASS | 26 个不同场景最终通过，历次原始失败与修正原因保留于 IMPLEMENTATION.md 和 evidence |
| 固定源码复验 | PASS | `runner_results_adhoc_20260914_005922_488_23732.json`，3/3，0 engine errors |
| 原掉率数据审计 | PASS | 7611 行完整比对，源与优先级保留 |
| 新倍率生成器 | PASS | 765 条原槽调整、17 条新增、7628 生产槽；原上限15不变 |
| 隔离 APK 构建 | PASS | 固定源码、git_dirty=false；无生产导入/导出错误 |
| Android身份/签名/资源 | PASS | verify_android_build、运行时资源 probe、verify_r3_apk_resources |
| 包内固定源码对比 | PASS | `apk_payload.json`；18个新增/变化脚本（含5新增），6项数据，其他221脚本与8979资源项保持字节一致 |
| 校准布局保护 | PASS | 包内 SHA `0EA858C9FE5867B8B7057DFC16FF32FB06DF68A7A6862992A702E45D470CBF10` |
| 历史 V505 整表生成器 | BLOCKED | 更早提交的目录哈希锁与已正式修改的基线不一致；未改变冻结目录去适配旧锁 |
| 安卓实机/多怪帧率验收 | NOT_RUN | ADB 无设备；桌面功能/CPU 证据不代替手机表现 |

完整根因、三职业主源、存档兼容、掉率分层和已知延迟边界见 [IMPLEMENTATION.md](IMPLEMENTATION.md)。已接受的人物布局、装备主属性、地图与素材冻结。Excel 只核对旧台账的“生效概率”，未用于任何修改，文件 SHA 仍为 `875A24D1B940C328BAF8CC1E2A077352CEFFC62FFCED289EE42FF4BB98AFC613`。

构建目录保留供复核：`C:/Users/Administrator/Documents/HardCore-android-staging/fa4a1ffa88f7-20260914-005937-5b4a2ea5`。导入日志的16条错误均来自原有故障夹具 `tests/runner_fixtures/`；它们不进入APK。导出错误0。

用户 AGENTS.md 和此前未跟踪文件未提交、未清理。发布前后用 `git diff --check`、源码目录无额外差异及 `git ls-remote` 核对主分支和里程碑。
