# 下一阶段 APK 交付

日期：2026-09-09。定位：下一阶段测试包；性能门槛及手机实测尚未通过。

| 项目 | 结果 |
|---|---|
| 桌面文件 | `HardCore-20260909-r3-closure-debug.apk` |
| 生产源码 | `909821c928ddb66e5fd48f7cef718baa2e8bfe03` |
| 包内 build-info | 上述源码，`git_dirty=false`，development |
| 版本 | `72 / 1.21.0-r3-closure` |
| 包名 / 显示名 | `com.personal.mafaoffline` / `HardCore` |
| 架构 / Android | arm64-v8a，min SDK 24，target SDK 36 |
| 文件大小 | 461,847,634 bytes |
| SHA-256 | `5DA03DEDDF8D64A019091C16AA887C9A63EC6BB68B1BE08E4BA087A6B23FF6A6` |
| 签名证书 SHA-256 | `C62D0F8239B926F819038845C302143FD24DCFD75ED8D877ED846C430C6F3FCC` |
| 对照旧包 | 桌面 `HardCore-20260906-gameplay-audio-debug.apk`，v71 |
| 旧包 SHA-256 | `A759922572001C43B00C329C7FE398BDF979B70F07B20B53137B32A05898772F` |

## 安装

直接打开新版 APK 覆盖安装，无需先卸载。已验证旧包与新包包名、证书一致且版本递增。替换程序及内置资源，保留应用数据；首次启动仅定向退役版本失配的旧热补丁，不清空人物、背包、装备或共享仓库。身份未知时保守拒载并保留文件。

软件专项验证了人物/仓库内容保留；没有连接手机，实际覆盖安装、旧存档兼容及故障手机是否停止持续攻击仍需实测。

## 核验与可复现性

- `tools/verify_android_build.ps1 -ApkPath <新包> -BaselineApkPath <桌面旧包> -ExpectedVersionCode 72 -ExpectedVersionName '1.21.0-r3-closure' -ExpectedCommit 909821c928ddb66e5fd48f7cef718baa2e8bfe03`：exit 0，v2 签名、直接更新资格、运行时资源与包身份 PASS。
- `tools/verify_r3_apk_resources.ps1 -ApkPath <新包>`：exit 0，25 个脚本及 4 个 SVG 导入资源闭包 PASS。
- 按隔离构建脚本执行启动主题等价检查：exit 0，透明启动图标、黑色背景及无 launcher icon 的主题符合合同。
- 原始核验日志、构建日志及逐文件 SHA-256 位于 `evidence/v3_main_integration/apk_909821c9/`。导入日志含用于测试 runner 的故意损坏场景解析错误；原始日志空白保持原样，不改写为无错误记录。
- 主控独立重算桌面 SHA-256，读取实际 APK `assets/assets/generated/build_info.json`，与上表一致。
- 原隔离构建脚本首次因 JDK Windows 本地管道临时目录错误退出 1；不是成功脚本运行。保留导入缓存，以构建进程 `JAVA_TOOL_OPTIONS=-Djdk.net.unixdomain.tmpdir=C:/Windows/Temp` 重试导出成功；不修改游戏生产代码或全局网络设置。APK稳定且日志出现 `[ DONE ] export` 后按原脚本规则结束遗留导出进程。原始失败与成功日志同存，隔离构建现场暂保留。
- 构建后源码未改动；后续远端提交包含文档和证据，不能将文档 HEAD 冒充包内源码。

## 未完成验收

最终性能比较在 `8bf77a34` 上执行，12/12 条整帧 p95 门槛 FAIL。30 怪持续近战 23.451ms、密集拥堵 25.443ms，旧版分别 11.962ms、11.720ms。8 次 runner 运行成功不代表性能通过；没有额外更改怪物数量、碰撞、玩法频率来降低要求。详见 [最终审查](FINAL_REVIEW.md) 和 [施工列表](CONSTRUCTION_CONTENTS.md)。
