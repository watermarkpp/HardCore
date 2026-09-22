# 构建工作树清理完成

2026-09-05，先推送并核对 `codex/integration=2bd4bb36e4f1e8bd1510e62f0a7c8ece96c7e8bc`，里程碑标签 `milestone-20260905-audit-upgrade` 解引用为 APK 构建源 `52ae0565856c2d99a28639b2bf0c6278186e0858`，再执行删除。

## 实际移除

- `CLEANUP_PREFLIGHT.md` 列出的 12 个精确 detached 旧构建工作树全部移除，无独有提交、tracked dirty 为 0。执行前和每树删除前核验内容及身份，所有检查通过。
- 本次新建的 `HardCore-android-staging/52ae0565856c-20260905-172022-d8fe8765` 另行预检并移除。源码已在主树、最终 APK 两处同 SHA，build-info、日志和 migration matrix 已独立保留。
- 没有删除主树、专业领域工作树、专项审计恢复树、人工地图、源素材或手机数据。未登记的零字节 `device-hotfix-45ebf844` 空壳未处理，不能把它混记为一个已删工作树。
- 6 个旧树的共享 Godot junction 仅移除链接条目，未沿链接删除。主树 `tools/godot-4.7` 与 console executable 复核存在。

## 保全与可恢复性

旧树 3,749 个源条目（3,304,852,226 bytes）按哈希归档为 3,746 个唯一文件（1,965,071,811 bytes），6 份 APK 去重保留 3 个内容。归档包含 outputs、测试 userdata、UID/translation、补丁 PCK/JSON、日志和 migration matrix；未知条目为 0。全量源与归档哈希核对通过，主控另外抽检 5 项通过。

归档根：`outputs/audit_upgrade_20260905/cleanup_archive/`。原始 manifest SHA-256：`6bd29d7b29479e96be4c714665d25fb78012754fb0ffe647b368c380cba8b33e`。本次构建保全在 `outputs/audit_upgrade_20260905/final_build/`。

删除未进入回收站；源码可从保留的 Git 历史恢复，重要产物可从上述归档恢复，Godot/Gradle 导入与编译缓存可重建。旧目录本身及未保留的生成缓存不承诺逐字节恢复。没有将归档本身计作“已删除”。

## 空间口径

| 阶段 | 删除前可用 bytes | 删除后可用 bytes | 净增 bytes |
|---|---:|---:|---:|
| 12 个旧构建树 | 79,930,961,920 | 126,286,782,464 | 46,355,820,544 |
| 本次临时 stage | 126,288,830,464 | 131,983,101,952 | 5,694,271,488 |
| 两次测量净增合计 | — | — | 52,050,092,032 |

约 **48.475 GiB**（52.05 GB 十进制）。这是两次 Windows 可用空间采样净增，可能含文件系统分配和同期系统活动影响，不等同逻辑文件字节总和或排他性性能测量。

机器证据：`evidence/cleanup_executed.json`、`evidence/stage_cleanup_preflight.json`、`evidence/stage_cleanup_executed.json`。此后只补交付文档并同步远端，APK 源码和标签不变；设备安装仍按用户要求延期。
