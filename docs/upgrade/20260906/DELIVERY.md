# 2026-09-06 玩法与音频升级交付

## 版本身份

- 分支：`codex/integration`。
- APK 源码锚点：`e6939a74fb091db24683c738fb85fb977d580cd0`。
- 正式版本：`71 / 1.20.0-gameplay-audio`，包 ID 保持 `com.personal.mafaoffline`。
- APK：`C:/Users/Administrator/Desktop/HardCore-20260906-gameplay-audio-debug.apk`。
- 大小：461,365,538 bytes；SHA-256：`A759922572001C43B00C329C7FE398BDF979B70F07B20B53137B32A05898772F`。桌面副本与 `outputs/hardcore` 原件哈希一致。
- 版本、HardCore 品牌、arm64、包内 build_info/运行时资源、v2 签名及黑底透明启动主题验证通过。签名证书 SHA-256：`c62d0f8239b926f819038845c302143fd24dcfd75ed8d877ed846c430c6f3fcc`。见 `evidence/apk_verify.log`、`apk_signature_verify.log`、`apk_splash_verify.log`。
- 未安装手机，未声称实机听感或玩法验收通过；不修改或删除手机存档。

## 本次完成范围

1. 主城安全区触发音乐延迟改为 6 秒；开始后不因出区、遇怪或地图切换截断，保留 70% 音量及每次进入只播放一次。
2. 7 个 NPC 对应 14 条用户音频，随机变体；快速切换 NPC 替换上一语音，与音乐独立。其他音效按精确主源接入，522 个运行事件、363 个唯一 WAV；无确切来源/对应关系的项目留空，不猜配。
3. 召唤物 AC/MAC 与增益参与伤害；补直接法术受击接口、恢复状态；跟随人物最终合法传送落点。
4. 第一册技能书为 1 级、三册满级，保留等级条件、旧 rank 0 存档兼容及失败回滚。
5. 疾风药水等掉落经地面、背包、合堆、排序、保存重载保留正式物品身份；920xxx 技能书使用明确 ID 桥。
6. 随机卷轴按正式完整可玩地图范围采样，保留碰撞、边界与占位过滤。
7. 按主源修正远程/法术怪物射程，不改 AI 节拍、仇恨规则、地图或刷怪数量。
8. 刺杀 3 GU，末端 1.5 GU 忽视防御；半月 2 GU / 120°。
9. 各职业普攻及烈火 2 GU；烈火无有效目标不消耗，保留普通攻击 fallback。攻杀作用于战士伤害模式，技能不额外播放攻杀动画。
10. 升级门槛为此前三分之一（原始表的 1/30）；死亡扣本级完整门槛 10%，不超已有经验。
11. 掉落身份链修复，233 个运行物品身份/名称组合通过核查；保留人工原始概率与倍率。当前尸王十只零掉落概率约 16.96%，未擅自改成保底。

## 验证边界

- 完整 critical：`36bfb5f8` 上 317 项，310 PASS / 7 FAIL，原失败证据保留。
- 7 项均完成有原因的测试夹具返工后分别通过：3 项玩法 + 4 项启动/火墙，无生产规则回退或 runner 白名单扩张。
- 玩家音频补充：核心 3/3、相邻 6/6 PASS。
- APK 源码锚点 `e6939a74` 最终最小专项 3/3 PASS，无超时、零未白名单 engine errors。不是一次全套全绿。
- JSON 见本目录 `evidence/`；完整分析见 [升级记录](../../UPGRADE_20260906.md)。
- 已批准升级动画哈希未变；本轮无 `assets/art`、地图或地图编辑器人工数据变更。

## 明确保留的空音效

- 原始声音 10110（lightning cast）与 943（monster 112 attack frame）的源文件缺失。
- 脚步地表、UI 材质尚无精确运行时映射，不默认配声；买卖按主源保持静音。
- 不接入会打断城镇音乐的源客户端死亡背景音乐。详情见 `../../audio/20260906/AUDIO_HANDOFF.md`。

## 构建环境与提交边界

- 首次 Gradle 导出失败于 JDK 17 的 `WEPollSelectorImpl -> PipeImpl -> UnixDomainSockets.connect0`（`Invalid argument: connect`）。仅 IPv4 设置仍失败。
- 仅为本次构建子进程将 `jdk.net.unixdomain.tmpdir` 指向隔离 stage 内不存在目录，触发 JDK 自带 TCP fallback 后导出成功。未改源码、JDK、全局网络或安全配置；复用已导入资源，未重跑整套测试。
- 构建 stage 与失败/恢复日志保留于 `C:/Users/Administrator/Documents/HardCore-android-staging/e6939a74fb09-20260906-165256-405e0871`，未进行额外清理。
- APK 固定代码锚点 `e6939a74`；其后交付提交仅含文档与验证证据，不冒充 APK 构建锚点。源码锚点已推送并由 `git ls-remote` 核对，交付记录继续同步到同一分支。
