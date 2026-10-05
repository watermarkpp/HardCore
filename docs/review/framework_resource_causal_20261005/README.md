# 资源请求退休、退出后准入与持续输入证据

本增量以 `fffadd21f608d7cc759744fc53eb64e161b1e5ef` 为父版本，只有两个生产文件变化。主控继续在第三树施工，主树、第二树及真实存档保持保护。本文是局部修复与诊断交接，整体架构升级、R3/P6、APK和设备验收仍未完成。

最终受测内容指纹：`77af4cd4a4a3abea001b5d3c76751052f354cf501f5afc13282f3562a06fe3db`，3892文件。相对父轮受测3855文件增加37个测试文件、修改2个生产文件和3个测试文件，删除0个。完整路径与原字节哈希见 [SOURCE_DELTA.json](SOURCE_DELTA.json)、[SOURCE_MANIFEST.json](SOURCE_MANIFEST.json)。

引擎：`4.7.stable.official.5b4e0cb0f`；console SHA256：`d8055fb8c7e7f5010d7439ec69be051554055dae55a265f8647bd7301c34161c`。每次实际命令、run/invocation/source、原生退出和隔离数据路径见 [RUN_INDEX.json](RUN_INDEX.json)。

## 生产改动与反例

### HUD FAILED 请求退休

`scripts/hud.gd` 正式轮询和退出路径都取得自有的 FAILED 请求结果一次；INVALID 不增加 get，原有失败记录和后续合法重试保持。非 background 的 opaque Loading 分支没有变化，原分支字节 SHA256 为 `d51cde070366fe97f2145af6a54dd345f199ca1f6b514efeb53bcfd354980e28`。

受控测试由真实 ResourceLoader 接受测试拥有的损坏 Script 资源；分别让 HUD 在 FAILED 后轮询，或尚未轮询直接退出。测试向 HUD 所有权容器登记本次真实请求，未宣称生产 UI 自然触发。

旧实现71项检查、4项失败；修复后相同业务71项全部通过。正式收尾后 native token 为 INVALID，fixture 补收为0，原字节恢复后同路径重试可用。生产 get 调用次数没有独立计数仪表，保持 `MISSING`，不能把 fixture 计数冒充生产调用计数。

最终同指纹的两个负例仍是官方 runner `FAIL`：各保留两条本轮 owned `user://hud_failed_native_<run_id>...res` 的原生加载错误，native exit0、wrapper exit0、完整业务 receipt PASS。没有成功 producer handoff。主控核对了确切错误文本和身份，不屏蔽日志或修改 runner 判定。

### 大厅退出后的原 deferred 回调

`scripts/character_select.gd` 在请求入口前检查 `is_inside_tree()` 和 queued-free 状态。原退出 get/清理逻辑没有改变。

新场景使用正式 Hall `_ready` 排入原 deferred 回调，在同栈移出活节点，观察原回调不得建立新的 native 请求；随后合法重新入树仍取得正确 PackedScene。旧实现22项检查、6项失败；新实现22项通过，原角色启动资源生命周期14项同时通过。最终同指纹重复这两场仍为36项通过。

这是接口生命周期反例，不把直接受控操作写成正常用户点选复现。大厅请求是否耗时最坏有界仍须单独测量，所有权回收不是退出延迟保证。

## 最终同源码回归

两个最终 runner 共13场：10场正常 PASS /157项完整检查；另3场故障注入的95项业务检查通过，官方 runner 全部保持 FAIL。其中HUD两场71项，既有大厅损坏资源合法重试24项。每场30秒上限，无超时。

| 范围 | 场景 | 检查 | 完整 runner |
|---|---:|---:|---|
| Hall deferred、角色资源生命周期、持续目标选择反例 | 3 | 50 | PASS |
| 同步/后台/后台子线程面板 Script 退休 | 3 | 71 | PASS |
| 主线程资产 warm 与首次使用取得资产 | 4 | 36 | PASS |
| HUD损坏资源轮询/退出 | 2 | 71 | FAIL，业务PASS |
| 大厅损坏资源同路径重试 | 1 | 24 | FAIL，业务PASS |

阶段原始证据另有42场，和最终13场合计55次正式 native；verbose caster 诊断另1次，不计正式回归数量。不同源码指纹不合并为最终 PASS。旧 RED、缓存前提失败、自然期限失败以及 cold 拒绝均原样归档。

## Script/非Script资产加载警告诊断

所有选中 Script 诊断均没有创建该 Script 的实例，没有世界/角色/地图施工。`can_instantiate()` 仅用于确认 Script 可用，不代表调用 `new()`。

1. 六个空Node、内建Ref和自定义Script Ref对照36项通过，没有同类警告。
2. 冷线程 main PackedScene 与直接 Root Script，在 request/get/释放/等待后各报告161个 ObjectDB 实例；主线程预载 Root Script 再请求 main 的对照没有同类警告。这是阶段结果，不是最终完整Root修复。
3. 八个直接依赖 Script 的诊断中，三场缓存前提检查失败：frame_budget、combat_runtime_service、map_editor_runtime_bridge 已由测试进程依赖加载。三场保持 FAIL，不能称冷加载对照成立。其他冷依赖中 coordinator4、firewall5、caster5个退出警告。
4. caster verbose原生证据列出5个零引用 RefCounted，实际日志列出两个Shader和三个纹理加载。尚未给每个零引用对象绑定内部类身份，不能据数量直接宣布5个对象均是纹理或具体引擎token。
5. 最小Script仅包含一项真实Shader或Texture const preload，后台请求后各报告1个零引用对象。把首次资产取得放在主线程、保留后台Script编译，两场20项通过且无警告。
6. 同一最终源码上，保持原 const Script 不变，先在主线程取得并持有其一个冷资产，再后台请求该 Script，两场16项通过且无警告；相同源码的两场冷常量对照14项通过但各有1个退出警告。

当前结论是有限触发条件与候选规避方式，不是完整Root/Android故障已修。未修改正式常量、没有引入完整同步Root预载或任意资产清单。正式完整依赖闭包、导出兼容与加载延迟仍开放。

核对当前固定引擎源码发现 `GDScriptParser::get_dependencies()` 返回空列表，不能拿 `ResourceLoader.get_dependencies()` 作为已完整覆盖 Script preload 的证据。[固定引擎解析器](https://github.com/godotengine/godot/blob/5b4e0cb0fd279832bbdd69fed5354d4e5ad26f88/modules/gdscript/gdscript_parser.h#L1560-L1563)。ResourceLoader后台内部任务与零引用对象之间的具体因果尚未原生身份绑定，不据静态阅读直接修改引擎或清除未知对象。

## 持续自然战斗：保留当前FAIL

测试原有35秒毫秒循环保持；新增严格单调微秒检查，冻结真正业务排空时刻。完成口径包括死亡、效果、预留、receipt、子动作、Cue、持久化和资源队列；之后的检查点与证据IO不算业务完成。延迟药水恢复有自己的对账，不冒充战斗完成。

测试驱动原先仅在历史 `round_peak_states<90` 时优先没有活动状态的目标，达到过90后即永久偏向密集组。14项受控生产释放反例中，旧驱动只在跨过历史峰值后失败1项；移除这一历史条件后14项通过。它仅修改测试输入选择，没有修改玩法AI、HP、RNG、250ms输入、1200ms移动、技能周期、伤害量或35秒门槛，不是性能提速比较。

新的自然 resource live/cold 在同一阶段指纹 `caf161d6059684b9779dbacd205eb4e7a4a90a4bea6e6bbfdbbe028cdea1f2f8` 上344项通过：两轮各30死亡/90状态，实际周期投递1256/1229，业务完成28,389,753/33,714,686us，最大实际tick迟到116667us。

相同阶段指纹的 chain live/cold仍FAIL：live332项、6失败；cold3项、1失败，正确拒绝失败producer。首轮30死亡、25,520,377us；第二轮29死亡，原期限末剩余slot1:29，HP98/1703、3个真实状态，第二轮1300次投递、23次真实接受，运行时failed0、最大实际tick迟到466667us。输入/位置/状态与完整原始trace均保留。没有延长期限、降低HP、减少目标、重置资源或重跑挑PASS。

旧输入驱动下 chain343项PASS和 resource期限FAIL也保留，它们不替代当前chain失败；当前不能宣布持续期限可靠。natural live/cold没有在最新77af指纹再次运行，以上均标阶段证据。

## 边界及下一步

- 已固定：两项资源生命周期生产修复、目标选择小反例、严格完成时刻和有限警告诊断。
- 继续施工：当前自然chain35秒期限、完整Root后台加载退出警告、自然持续P6/R3及可比CPU/帧间隔/队列时效/内存证据。
- 等产品选择：超密1us扩展周期的接受与服务合同；冻结地图203300的刷新密度政策。没有默认采用改变玩法的方案。
- 原v97第二角色B故障原始输入 `MISSING`；新角色结果不关闭原故障。
- Android执行环境、GPU/热机以及手机同版本设备证明保持独立；`APK: NOT_RUN`，`DEVICE TEST: NOT_RUN`。本增量不授权主树合并或发布。

真实index SHA256 `df5a01dd0d87c14620e0021d70c25a830eb2cc37aa7b012eeb14ee1f2c58c5fb` 保持。主树和第二树分支/HEAD/dirty字节在ROOT_STAGE_VERIFICATION中核对，冻结coordinator字节SHA256保持 `757da0597ab78aded642a98cf1e7433b9da06a6be5fb0684923ca6686282809d`。正式新增ID：无。

审查入口按最终固定提交读取本目录；[EVIDENCE_MANIFEST.json](EVIDENCE_MANIFEST.json) 保存原证据与归档路径、长度和SHA256。完整receipt/native/handoff共同决定各场结果，中途PASS与诊断候选不代替验收。
