# 2026-09-05 经验、升级表现与城镇音乐 hotfix

## 版本身份

- 源码：`0abc83e94a58ba4f71b0e15485d384935ab4dd56`。
- 导出：`930c17aaa269da02e3313713b7c2604ccc70172f`。后续工具/证据提交不改变该补丁源码身份。
- Android 基包：70 / `1.19.0-audit-milestone`；源码 `52ae0565856c2d99a28639b2bf0c6278186e0858`。
- APK SHA-256：`26584B871F61B2F6EC2DDDAF52432263E7D68A6B8BEA35B2A3196D59D5B21664`。
- 首次候选补丁（禁止安装）：`hotfix-20260905-xp-town.pck`，62,207,592 bytes，SHA-256 `B5811F685A4CF8BC55A3FEA39AF1A6F7837A53AAA57A0C280EBFCE993A695839`。导出成功但安全验收失败：包含 `_cl_` / `assets.sparsepck` 两项基包删除，以及 3,898 项非目标重叠资源变化。原包保留作失败证据，不进入手机；必须重新打包精确闭包。

## 内容和验收

1. 原始升级经验表不改，运行时门槛取原值 10%，四舍五入、最低 1；不放大经验奖励。
2. 经验条覆盖第一至第四物品快捷槽的外框区间，保留原样式。
3. 一次成功经验结算无论升几级仅触发一次动画；保存失败不触发。光柱 75% 大小并随旋转动态进入人物前后层，用户已批准，脚下光圈保持冻结。
4. 当前技能/普攻音效关闭。一级库核查不足以证明全部技能准确完整，按用户条件不恢复，背景音乐不受影响。
5. 五个主城仅在安全区内触发统一音乐，Loading 结束后 10 秒播放一次；离区/切图取消计时并停止，重新进入可再次触发。不是整张主城地图播放。

干净源码提交专项 7/7 PASS，0 engine errors，见 `evidence/source_0abc83e9_seven_tests.json`。视觉批准截图：`evidence/approved_level_up_depth_75.png`。此记录不能替代手机操作/听感验收。

## 安装前现场

手机实际 APK 已是上述精确 SHA 的版本 70，无需重装或清数据。旧 active patch 为 `r3x9-map-fast-c97a08b4-enemy-only`，基于旧提交；新包应原子替换它，而不是叠加其上。

主机只读备份 `outputs/hotfix_20260905/device_before/files.tar`：2,927,549,440 bytes，SHA-256 `5F061C23DDA01D136C08525979E5AB6B7F98FACA99D66C4F53DFDF59E65781DD`。归档 175 项，包含角色存档、active/previous manifest 和旧补丁。私人存档归档不进入 Git。

## 最终补丁与设备加载

最小补丁 `hotfix-20260905-xp-town-minimal.pck`：1,404,188 bytes、12 项，SHA-256 `1643D8D05276D4DF45A823697645173C6D27A654C37B60238F024086BA501434`。仅保留六个编译脚本、两个新增 remap、音乐导入闭包及在基包 180 类基础上仅增加两类的 class cache；无 UID cache 覆盖，无 removal/delta/encryption，payload MD5 全匹配。

使用基包与最小补丁的独立进程加载验证通过，无源码 fallback：原表 100 → 游戏阈值 10，技能音效播放开关 false，光焰尺寸 0.75，音频解码时长 48.181404 秒。证据见 `evidence/minimal_repack.json` 和 `evidence/minimal_resource_loader.json`。

已安装并启动手机游戏。Device Lab 实际回执 `loadedPatchId=hotfix-20260905-xp-town-minimal`，`loadedPatchSha256` 与上述一致，`loadError` 为空；手机文件 SHA 独立复核一致。回执：`evidence/device_loaded_status.json`。旧 manifest 自动保存在 previous.json，未清数据、未重装 APK。首次角色选择界面发起的 status 请求超时，进入游戏后重试成功；不隐瞒首次超时，也不将它误报为补丁崩溃。

桌面保留 `HardCore-hotfix-20260905` 文件夹中的最小 PCK 和 manifest。主观音乐听感、实际杀怪多级动画及行走进出安全区仍待用户手机验收；当前结论是源码专项、包内加载和设备补丁加载通过，不是全部手动场景已验收。
