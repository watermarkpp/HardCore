# v95 完整 APK 交付 — 2026-09-29

## 结果

APK BUILD: PASS（首次环境失败后，同一固定stage重试）。APK VERIFY: PASS。39个相关场景最后结果PASS。DEVICE TEST: NOT_RUN。没有自动安装、覆盖手机存档或推送远端。

| 字段 | 已核验值 |
|---|---|
| 分支 | codex/integration |
| 本轮基线/已安装Sol补丁源码 | 21b40ddae663997f8e9f267585988e6a7c63db6a |
| APK固定构建源码 | 7076bc465dbf7dc837381f267fa8eb9e151bf001 |
| v94 APK源码祖先 | 4123abdc99388ec3fe83776f9b3e7029b14428d1 |
| Desktop APK | C:/Users/Administrator/Desktop/HardCore-v95-full-fixes-debug.apk |
| 项目副本 | outputs/hardcore/HardCore-v95-full-fixes-debug.apk |
| 大小 | 488710512 bytes |
| SHA256 | 6B1222403A0711A07769199B7A3A7CA38A97089D33EC3BCEBAE9F5D862C10826 |
| 包名/显示名 | com.personal.mafaoffline / HardCore |
| versionCode / versionName | 95 / hardcore 1.0 正式版 |
| 构建类型 / ABI | development debug / arm64-v8a |
| 签名证书SHA256 | C62D0F8239B926F819038845C302143FD24DCFD75ED8D877ED846C430C6F3FCC |

桌面副本与项目副本SHA256相同；旁附 `.sha256`。原v94 APK保留。新包同签名且95>94，可直接覆盖安装保留应用数据，无需卸载。交付证据提交在构建源码之后，不改变包内build_info身份。

## 本轮实际修复

- 物品使用、工作台放取和结算立即更新权威状态，人物档顺序后台写；处理与旧存档/拾取回执交错，正常退出等待完成。保持药效、受击硬直、毒、减速与圣物事件时机。
- 工作台允许任意先后顺序；错放、多放、材料或金币不足时按钮禁用，合法组合才启用。既有槽位角色、费率、概率、动画与取回交互保留。
- 仓库最终提交后台化、前置等待跨帧化，保留共享仓库双文件一致性；背包与仓库只重写变更格子。
- 玩家与怪物在Ground GU中实际严格八方向，完整脚印校验保持；镜头每帧只进行一次平滑。
- 圣物、徽章、碎片统一32px显示边界，仓库遵循该显示尺寸；loading文字与logo共中线。

性能及所有失败裁定见 `VERIFICATION.md`。500物品/100件仓库存取场景最长帧间隔由86–115ms降到19.5–24.9ms；整体完成仍约0.3秒，不宣称总交易变快。20次立即使用本地循环约1.37ms。全部为本地结果，不是手机帧率承诺。

## Sol热补丁及冻结资源

旧补丁 `v94-loading-save-forge-21b40dda-slim` 的六脚本在本轮父提交内，两个祖先关系已核验。新增APK包含其加载/预热/HUD等工作；已修改四项按新源码验证，未改两项编译字节与实际旧PCK逐字节相同。

新APK的build_info在挂载补丁前读取。旧补丁声明的APK基线与新包不匹配时拒绝挂载并清理补丁文件，不碰人物/仓库存档；真实旧PCK回归PASS。用户无需重装旧补丁。

`evidence/apk_payload.json` 保存包内逐项哈希：18项相对v94有改动的运行脚本存在且不是旧缓存；新后台提交与镜头脚本存在；各stage源码与固定Git提交相同；**9684条冻结数据与编译纹理和v94逐字节相同**。标准包检验同时核验586个技能帧导入；APK CRC、启动主题、版本、签名均PASS。tests/docs/tools未进入APK。

接管前AGENTS.md、cangyue_area_test.gd及无关未跟踪内容保留，未进入源码提交。没有新增物品/技能稳定ID，没有更改存档schema、人工地图、技能素材、脚点或选取圈。

## 正式构建及环境裁定

```powershell
& .\tools\build_android_isolated.ps1 -Commit 7076bc465dbf7dc837381f267fa8eb9e151bf001 -OutputApk C:/Users/Administrator/Documents/HardCore/outputs/hardcore/HardCore-v95-full-fixes-debug.apk -BaselineApkPath C:/Users/Administrator/Desktop/HardCore-v94-monster-audit-debug.apk -VersionCode 95 -KeepStage
```

隔离stage：`C:/Users/Administrator/Documents/HardCore-android-staging/7076bc465dbf-20260928-233839-e4c9d142`。从固定SHA干净提取，60图/867文件绑定核验与完整导入成功，版本只在stage覆盖。

第一次导出FAIL：JDK Gradle daemon的UnixDomainSockets/PipeImpl报 `Unable to establish loopback connection / Invalid argument`，原正式脚本正确返回非0。使用当前构建进程 `JAVA_TOOL_OPTIONS=-Djdk.net.unixdomain.tmpdir=C:/Windows/Temp` 后，offline gradle help成功；同一stage、同一源码和导入缓存重试Godot headless Android导出，native exit0且产物完整。不改全局Java、网络或安全设置。

导出后运行 `tools/verify_android_build.ps1`、原正式脚本启动主题检查及 `verify_apk.py`，均PASS。原始首次失败、环境探测、重试及验证日志原样打包于 `evidence/apk_build_raw_logs.zip`，逐文件大小与SHA256见 `apk_build_log_hashes.json`；本地展开副本在 `evidence/apk_build/`。压缩归档保留Godot输出的原始空格与换行。

## 设备验收待办

用户自行覆盖安装桌面新包，检查跑动吃药、工作台放取/按钮、仓库、实际八方向/碰撞、镜头跟随，以及loading与图标。当前DEVICE TEST: NOT_RUN；不为获得验收结果自动启动、安装或回写设备存档。完整critical按用户要求NOT_RUN，仅执行直接与相关39项。
