# v96 完整 APK 交付

- 状态：源码与针对性验证 PASS；APK 构建、签名、版本、内容及桌面复制核验 PASS。
- 构建源码：`b0119a18a346e7919d5b2d6657329b910b1746af`。
- APK：`C:/Users/Administrator/Desktop/HardCore-v96-full-fixes-debug.apk`。
- 大小：488711677 bytes（466.072 MiB）。
- SHA256：`1B985BC897BAE4213F61D124F5BB7FC88E68D890B03F8E32EE770199A3EA8189`。
- 包名：`com.personal.mafaoffline`；可见名：HardCore；versionCode：96；versionName：`hardcore 1.0 正式版`；arm64-v8a debug。
- 签名证书 SHA256：`C62D0F8239B926F819038845C302143FD24DCFD75ED8D877ED846C430C6F3FCC`，与v95一致，直接升级身份通过。
- 基线v95、已包含的v94热补丁祖先核验PASS。新包原热补丁功能由完整源码提供，手机只读检查没有加载旧补丁。

## 精确源码与内容证据

- 59项专项场景最新均PASS；矩阵在 `evidence/matrix.json`。提交前证据的源码LF SHA256已逐项与构建提交核对一致。
- 提交后再次运行工作台任意格、比奇真实卡点、198组合技能说明：3/3 PASS，见 `evidence/final_commit_runner.json`，其HEAD即构建源码。
- 11个变更脚本的提交文本、构建目录文本与入包字节码核验PASS。
- 287个未变更脚本字节码与v95完全相同。
- 9684项入包数据和导入贴图与v95逐项一致，无素材/地图回退；详见 `evidence/apk_verification.json`。
- 586个施法特效帧导入项验证PASS；包CRC、重复项、测试/工具/文档排除验证PASS。
- Android启动页样式、包ID、版本、签名验证PASS。
- 当前已知专项失败：无。历史失败保留在矩阵与STATUS分类中。

## 构建环境记录

受管理独立检出：`C:/Users/Administrator/.codex/worktrees/apk-v96/HardCore`，创建于精确提交，无旧Godot缓存。
首轮9539项资源导入完成后，Godot原生进程退出码为-1073740940；依照既有构建流程，在同一新导入缓存上重试一次正常退出，然后完成Android导出与独立包校验。未忽略脚本错误，也未使用旧APK替换产物。构建原始日志保存在 `evidence/android_build.log` 等文件中。

`assets/**`、`map_editor_workspace/**`、`project.godot`、跟踪的`export_presets.cfg`均未改变。版本96仅注入构建目录。用户原有AGENTS和沧月测试改动、其余未跟踪文件保留。未安装到手机、未覆盖手机存档。旧v95桌面包保留。

DEVICE TEST: NOT_RUN。用户需在新包实际安装后检验锻造/合成手感与地图接触情况，本地通过不等于实机已验收。

按先前授权在APK完成后普通推送integration。SSH通道返回administratively prohibited，已用同一GitHub仓库HTTPS只读取回远端，确认旧远端4123abdc是本地祖先；使用HTTPS普通快进推送，不修改仓库远端配置，不强推。推送结果以最终工具回执与远端SHA为准。
