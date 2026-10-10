# Windows Android Java 构建环境

## 固定入口

Android 构建使用 `tools/build_android_isolated.ps1`。它调用
`tools/android_java_environment.ps1`，在本次构建进程及其子进程中将 `TEMP`、
`TMP` 指向实际存在的 `outputs/android_java_temp`。构建结束或异常退出时恢复原值。
不修改系统或用户级环境变量，不更改防火墙、代理、JDK，也不停止其他 Gradle 进程。

导出前执行 `tools/android_java_loopback_probe.java`：32 次真实 Selector 就绪通知
和 Pipe 字节传输。原生退出必须为 0，并出现完整通过标记，才允许开始导出。
证据在构建 stage 的 `outputs/android_java_preflight`，包括实际 Java、检测源码和
环境助手的 SHA256、退出码以及原始标准输出/错误。每个新构建进程验证自己的实际
环境；这不要求重跑已经通过且源码未变的游戏回归。

## 故障原因和修复范围

2026-10-09 对照确认：本机用户临时目录中的 Java 17 Windows 本地套接字连接失败，
导致 `WEPollSelectorImpl -> PipeImpl -> UnixDomainSockets.connect0` 报
`Unable to establish loopback connection / Invalid argument: connect`。
默认 DOS 短路径和对应完整路径均失败；单独修改短路径不能解决。
工程自有临时目录下 Selector、Pipe 和实际本地套接字连接通过。
Gradle 的普通 127.0.0.1 TCP 监听和连接已成功，不能据此故障去修改 TCP 网络设置。

历史多次导出使用临时进程环境后成功，但正式入口未保存这条接线，因此新构建复发。
固定修复保留实际可用的本地套接字通路，不使用不存在目录强制 TCP 回退，不靠重试。
当前证据没有确定 Windows 用户 Temp 下连接失败的系统级机制；不声称已修复 Windows
所有 Java 程序。修复覆盖 HardCore 正式 Android 构建入口。

如果继承的 `JAVA_TOOL_OPTIONS` 等变量显式覆盖临时目录或其他 Java 配置，真实预检
仍会前置拒绝失败；助手不偷偷删除调用者的 Java 选项。检查原始错误后再处理实际冲突。

## 本轮证据

`outputs/release_v108_20261009` 保留原始 Gradle 失败、默认目录/完整目录/工程目录
对照日志及 `java_fixed_preflight/java-loopback.json`。108 原始失败结果不覆盖，恢复
构建单列 `RESUME_BUILD_RESULT.json` 和独立封装目录，最终 APK 校验及设备状态另列。
