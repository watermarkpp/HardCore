# v92 手机验收交付

2026-09-22 22:49。v92 实机候选 APK 已完成构建和包内验证，已放在桌面。源码已推送并以 `git ls-remote` 核对；交付资料随后追加至同一分支。用户明确要求当前优化后打包继续实机验证，手机流畅度尚未验收。

## 安装包身份

| 项目 | 值 |
|---|---|
| 桌面文件 | `C:\Users\Administrator\Desktop\HardCore-v92-20260922-abbb5ef-debug.apk` |
| 构建源码 | `abbb5efbaba3b4d3f539f674b52b27ca2dc9f16e` |
| 远端分支 | `origin/codex/integration`；源码提交已推送并核对，最终交付资料提交 SHA 见任务最终答复 |
| 包名 | `com.personal.mafaoffline` |
| 版本 | versionCode **92**；versionName `hardcore 1.0 正式版` |
| 大小 | **480,221,108 bytes**，约 **457.97 MiB** |
| SHA-256 | `3A7E3D8CAF00743CCE27C82072C05792A3FEF72D1E53FCFEB0C287DAF0800A3F` |
| 签名证书 SHA-256 | `C62D0F8239B926F819038845C302143FD24DCFD75ED8D877ED846C430C6F3FCC` |
| 覆盖 v91 | PASS：与已交付 v91 文件同包名、同证书，92 > 91；直接覆盖安装，无需卸载 |
| 平台 | arm64-v8a；minSdk 24，targetSdk 36 |
| 设备验证 | **NOT_RUN**；本次 ADB 没有连接设备 |

后续核验工具和文档提交不改变 APK 内源码；包内 build_info 的 git_dirty=false、源码 SHA、版本号全部通过验证。版本号只注入隔离构建目录，正式 project.godot、export_presets.cfg 和人工数据保持冻结。

## 构建及核验

- `tools/build_android_isolated.ps1 -Commit abbb5efbaba3b4d3f539f674b52b27ca2dc9f16e -VersionCode 92 -KeepStage`，OutputApk 为上表路径，BaselineApkPath 为此前 v91 包。首次导出因 Windows JDK PipeImpl / UnixDomainSockets.connect 回环连接错误 FAIL，没有 APK。
- 先用 Gradle `--offline help --stacktrace` 复现；仅构建子进程指定 `JAVA_TOOL_OPTIONS=-Djdk.net.unixdomain.tmpdir=C:/Windows/Temp` 后检查 PASS。同一隔离源码和缓存重新导出 PASS，没有更改全局网络或生产源码；本机 portable editor 设置已恢复原字节。
- `verify_android_build.ps1` 和原构建器启动主题核验 PASS：包名、版本、签名、build_info、586 个施法动画帧导入均通过。
- `tools/map_assets/verify_formal_map_apk_closure.py` PASS：67 正式地图、445 地面引用、208 唯一地面贴图。
- `tools/verify_v92_apk_payload.py` PASS：60 计划的包内 runtime 字节哈希全部匹配；807 相关贴图导入及其编译资源与 staging 一致；48 新墙体贴图齐全；34 本轮修改脚本编译内容相对 v91 确实更新；6042 正式掉落槽/168 overlay/102 衣服去重，冻结装备和怪物分类与 v91 一致。CRC 与 tests/docs/tools/outputs 排除均 PASS。
- 固定源码 `abbb5ef` 再验六项 PASS、零运行错误、完整退出：人物成长、本地监测、DeviceLab、空安全区、索敌预算、闲置扫描。原始结果 `evidence/apk_v92/runner_results_adhoc_20260922_224703_880_19644.json`。

构建初次扫描有八个既有 BOM 测试夹具报错：其 baseline/source blob 相同，最终 APK 确认不包含 tests。包内核验初次因 ZIP 未标 UTF-8 导致 Python 误按 CP437 解码“3×3”目录而 FAIL；改用明确 UTF-8 元数据解码后原全部资源断言 PASS，APK 未修改。原始失败与分类保存在 `evidence/apk_v92/manifest.json`，未隐藏或归为生产 PASS。

完整构建身份、原始重试日志、六项复验和文件哈希见 `evidence/apk_v92/manifest.json`。隔离目录暂保留以便复核，用户原有未知 UID、源素材、存档及历史产物未清理。

## 手机记录方法

1. 先按正常方式体验黑暗地带、蜈蚣洞/赤月密集怪和火墙。
2. 游戏菜单 → 游戏设置 → 记录帧率30秒；菜单自动关闭，在同一区域复现，30秒后提示已保存。
3. 再选择记录CPU30秒，尽量重复同一地图、位置、拉怪数量和火墙操作。详细计时本身有开销，不能只凭这一轮感受判断正常性能。
4. 暂停时间不计入30秒。返回人物选择会保存一份complete=false的未完成报告。
5. 报告仅在本机user://device_lab/outbox/result_local_*.json，默认不上传；保留最多32份/16MiB。USB连接电脑并允许调试后，运行 `tools/collect_android_performance.ps1` 只读取这些报告至桌面。当前无设备，传输NOT_RUN。

报告含真实墙钟帧间隔分位/长帧计数、源码和补丁身份、机型、地图、CPU各段累计计时、物理更新/参战/休眠怪、火墙/视觉、绘制与资源统计。引擎process监控是约秒级缓存值，不当作逐帧CPU；GPU真实帧时间无可靠接口，明确不可用，后续必要时另接Android系统跟踪。

## 已核查范围与边界

见USER_REQUEST_RECONCILIATION、FINAL_VERIFICATION、CHARACTER_GROWTH_REVIEW。实际普通衣服单槽、15件落地筛选、168精英装备概率、三职业成长及Excel以本轮正式数据为准。地图60个优化计划绑定已重新生成，包内检查 PASS。

自动测试通过不代表手机性能已验收。旧M30存在真实时间/物理帧混用带来的可比性限制，两组不匹配保留BLOCKED；旧Windows退出引擎崩溃保留FAIL，未宣称修复。DEVICE TEST: NOT_RUN。
