# v105 Android 修复包交付与实际验证

日期：2026-10-07。范围：第三树 Android 启动、创建角色、进入地图及相关回归。不是全项目、自然性能或物理手机的总体验收。

## 实际产物

- 构建源码：`f6b70d55def70d98639003da5b90d6d0b7cd3587`。
- 桌面文件：`C:\Users\Administrator\Desktop\HardCore-v105-pro-debug.apk`。
- 原构建文件：`outputs/hardcore/HardCore-v105-pro-debug.apk`。
- 大小：491805682 bytes。
- SHA256：`e65366c437c1d2778a45083ad4448eed4647c21ca024d4c2cc22fe18fe10064c`。
- 包名：`com.personal.mafaoffline`；versionCode：105；versionName：`hardcore 1.0 正式版`。
- 类型：development/debug 手机测试包，不是正式发布裁决。
- 签名证书 SHA256：`c62d0f8239b926f819038845c302143fd24dcfd75ed8d877ed846c430c6f3fcc`，与提供的旧v97兼容包一致。
- Godot：4.7.stable.official.5b4e0cb0f；arm64-v8a。

桌面副本、构建文件、模拟器实际安装的base.apk三者哈希一致。桌面同时放置`.sha256`校验文件。没有卸载应用或清除应用数据。

## 本次已核验的主要修复

原v101建角失败并非疗伤药图片身份应当被替换：Android故意延后GameData加载，资源声明却在数据未就绪时缓存了origin mismatch，随后正常建角继续读到旧失败。当前实现不缓存NOT_READY，PlayerState也不在该时点编译不完整配置；真正就绪后的错误仍拒绝。

此前还修复了Android校验器零引用析构调用自身方法、ZIP非ASCII成员名称编码破坏、stage生成catalogue未安装、构建引用错误，以及原生工具退出值/UTF-8输出/PowerShell函数返回值混杂。没有通过取消源哈希、Android封印、出生/HP/planner/writer权威来取得通过。

## 同一最终源码的原生回归

实际单项执行14个原生场景，13份完整framework receipt合计672检查；initial_world_bootstrap为原断言式场景。所有本轮采用行退出0、无timeout、源码前后相同。

受测内容：`0c62df34f4fddd24ca26b171e37074418c316fb74df0b4054bd9b5cf8e213f7a`。

覆盖：启动资源就绪、Android verifier退休、保存升级启动、非法建角和失败回滚、真正资源拒绝/准备/音频/取消、双角色圣物生产live/cold、宝石/符文事务、初始世界启动。双角色live327和cold32具有本轮成功producer与隔离输入对应；不是原v97故障B的因果复现。

另在最终工具字节运行UTF-8 inspector三项及two-pass返回/失败传播三项，均通过。这些工具测试不代替真实导出。

## 实际导出与包校验

干净stage正式导入、两次正式导出均有真实退出值；两次export退出0，整次构建退出0。实际最终seal/closure/native/context验证和原APK签名/版本/资源校验通过。

额外只读检查：19435个ZIP成员CRC与重复名检查、15/15身份源原字节、三份声明源媒体、375个直接remap、8918个import记录至少一个实际导出变体，均通过。这个范围不等于所有未来资源选择路径实测。

旧占位seal字节已经被真正生成的封印替换。最终seal gdc SHA256：`ae389c4165c57fb50eeefd45733206630c8c2475a3254639b7e0f6c14835cae5`。

## 实际Android模拟器UI

仅使用已授权测试模拟器emulator-5554，升级前归档其应用文件。原测试角色3个保留；在v105真实人物大厅输入Pro105Dao、选择道士并点击创建，新增成功，角色总数4。

随后点击“进入HardCore”，进入真实比奇营地，摇杆移动、打开人物/背包/装备面板，再通过游戏菜单“保存并退出”。第一进程PID25064正常消失。

再次正常启动形成独立进程PID25473；四个人物保留，新角色和装备正常加载，再次进入营地并打开背包，最后再次通过菜单保存退出。未调用测试专用create/HP接口，不清数据、不重新安装第二次来伪装冷启动。

两次本轮应用进程日志未出现Godot ERROR、SCRIPT ERROR或FATAL EXCEPTION。保留shader缓存重编译WARNING，以及Loading结束时非关键物品图标仍在后台预热WARNING；Android模拟器SurfaceSync等平台诊断亦保留。不声明零警告。

这是模拟器功能smoke PASS，不是用户物理手机、GPU/热机或持续战斗性能PASS。模拟器采用x86_64系统执行arm64应用，不把其时长外推手机表现。

## 证据与历史边界

本轮完整本地证据：`outputs/pro_v105_final_20261007/`；两遍构建证据在相邻`HardCore-android-staging/seal-evidence-pro105-f6b70d55def7-105827/`。

`FINAL_NATIVE_SUMMARY.json`、`DEVICE_SMOKE_RESULT.json`、`APK_STATIC_CHECK.json`、`APK_REMAP_DETAILS.json`、clean_build结果、各run完整receipt/log、截图和设备操作记录均保留。私人模拟器文件备份不进入公共仓库。

此前失败构建和旧反例保留。第一次v105尝试因为预复制cache不满足clean-stage合同，在import前拒绝；随后仅把这份尚未执行的cache移到明确未采用目录，再按原严格合同冷导入。没有将该失败重标PASS。一次远端CMD启动测试的引用错误发生在Python/native启动前，单列0-native；后续用参数向量运行真实场景。

全项目自然35秒/完整P6R3、长期内存、GPU/热机、物理掉电、原v97 B输入MISSING等旧范围没有在本轮结案。没有合并第一/第二树或主树。后续文档提交不会改变本APK内部构建SHA。

## 用户手机测试

将桌面v105 APK复制到手机，按同签名升级方式覆盖安装。不要卸载旧游戏、清数据或改用v101旧包。若系统提示签名冲突，应停止覆盖并记录提示，不通过卸载绕过。

先验证创建角色、进入地图、背包与保存冷启动，再进行用户自己的实际玩法测试。手机结果必须绑定上述APK SHA，不能将模拟器smoke替代设备验证。
