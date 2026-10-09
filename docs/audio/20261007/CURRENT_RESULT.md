# 音频及连续拾取继续修复

2026-10-08 01:24 后续特装/HUD实现与专项结果见docs/review/special_equipment_20261008/FINAL_RESULT.md。新旧所有native epoch已追加NATIVE_PROGRESS_RECEIPTS.json，逐阶段保持源码/命令/退出绑定；已闭合音频/拾取不因交接重复检测。探测项链唯一UID移除后，正式当前掉落表6083槽，覆盖下方改动前6084数。技巧项链/神秘装备由data_only转为真实随机实例消费者；特戒新行为和HUD居中以新交接为准。群怪及设备体感仍未验收，未出新APK。

## 2026-10-07 23:32 当前结论与工作顺序

用户追问“这些不是都做过了吗／到底做过没有”：音频和连续拾取已经修复并完成正式链专项，不再将它们列作尚未执行。`audio_pickup_drop_current_232907_517994` 的药品实际播放、PCM 生命周期、发现提示退役、连续21来源真实持久化/FIFO、生产掉落回归5 PASS，源码稳定、原生退出0。此前专项及失败仍逐阶段保留，不合并宣称最终整合通过。

售价19个精确身份报价及5种实际出售/金币到账已在 `sale_quantity_contract_fixed_231015_448034` 通过；原报价权威通过，旧身份专项仅因固定31条候选计数过时失败。按用户新增19条迁移后 `pricing_identity_provenance_fixed_231637_354992` 131项身份检查 PASS。原31条候选保持，未知/冲突身份拒绝及其它任务物品、绑定保护保留；祖玛头像 hc.item.920032 只开放精确任务物品出售例外。

祝福油5倍概率已有直接/穷举/真实消耗与事务专项 PASS；沃玛以上小极品3倍已有7项Python精确校验及 `probability_price_business_fixed_225658_913418` 的1400实例生成/校验/wire专项 PASS。小极品事件为至少一项真实属性modifier，不计单独耐久增加；92个登记目标用v4，83个低阶及旧v1/v2/v3验证保持。

掉落完整当前6084槽和历史7611槽分开核验，`drop_complete_authority_fixed_232329_737041` PASS，历史太阳水650槽检查包含后续冻结用户平衡覆盖，不将历史概率当作当前生产表。当前白怪6/精英9/Boss12及原保护保持。原生产专项清理补齐后已在上述5场复验通过。

Loading overlay与正式地图显示专项2 PASS。比奇经单目标正式发布链更新至“比奇省”，发布原生退出0；精确差异证明布局/碰撞/导航图/82刷怪点、地面素材和其余66条发布记录保持，仅标签、发布指纹/版本及当前canonical目录来源指纹变化。证明在 outputs/monster_upgrade_20261007/map_name_publish_proof/after.json。当前代码准备目录经3场正式隔离元数据采集PASS和原编译/目录生成工具刷新，未手改生成物。`character_loading_parse_fixed_232830_788382` PASS：冷大厅真实覆盖准备、正式请求/缓存、点击首帧与错误恢复均通过；保留独立25秒代码准备及600帧场景交接边界，不修改生产期限。该场退出有44 ObjectDB清理告警，不能称零告警。

特殊装备完整清单已完成：40装备与1材料；25项找到正式消费者，6项只有数据/描述，祈祷5件和记忆4件明确延期。`special_ring_existing_current_233016_797740` 的既有特效专项本轮 PASS；麻痹真实动作→命中→控制生命周期仍 MISSING，其他专项未执行不得冒称全验收。详见 docs/review/monster_system_20261007/SPECIAL_EQUIPMENT_CONNECTION_LIST.md 及 SPECIAL_RING_CONNECTION_AUDIT.md。

用户已接受右侧加粗金边，名称字号20→18、属性14保持。群怪卡顿明确放最后；新候选尚未行为/性能/设备验收，加载专项暴露的 enemy.gd Vector2 类型推断解析错误已仅补显式类型。由用户在手机复现，届时同步监测该次现场数据并按体感验收。前面已闭合项不重复跑；不提前全量整合或封装。当前所有本轮修复仍未出新APK，v106不包含这些改动，DEVICE TEST: NOT_RUN。下文是各施工阶段记录，较早“待跑/施工中”由本节更新。

基线：codex/integration，215f0b2f651a51e6855ee813ddd99221690311a1。用户明确优先音频，随后连续拾取。群怪卡顿仍未解决，当前手机安装版本尚未绑定。

## 吃药接线：FAIL 已复现

正式身份登记service658→item920045等49条alias。GameData通过登记转换，PlayerState成功扣药后向GameRoot发item:920045；audio runtime仅有service:658，实际播放器返回missing_item_route。旧事件单测仅检查发出身份，旧audio单测只调用service:658，均PASS但没有覆盖二者之间正式接线。

新正式方法链红测：audio_canonical_red_formal_205852_215248，原生退出1，source稳定；明确断言成功canonical药品必须实际播放一次失败。首次新测试缺少EntityRegistry显式preload的解析失败另保留，不作为业务红测。完整证据位于outputs/r3_takeover/20260930/validation/。

## BGM播放链

GameRoot创建单个TownMusicController；Loading前创建播放器和资源。地图切换带transition ID令旧计时无效；set_map_context使用正式安全区；Loading结束事件只接受当前ID、只处理一次；结束后6秒Timer启动。每帧音乐在场判定复用已计算的玩家安全区缓存，没有第二次地形/世界扫描。离安全区和跨图不停止正在播放的曲目，新入城等待旧曲自然结束后计时；显式世界退出停止。

现有PreparedMusicStream只是提前instantiate原生Vorbis decoder。原生AudioStreamPlaybackOggVorbis.start仍会seek和begin_resample，seek执行Vorbis synthesis；prepare并不消除真正play起点的解码。主线程建decoder仍在初次/再次入城时发生。用户确认开始播放时明显，轻微持续后恢复。该机制有源码证据，但手机现场耗时和全部体感因果尚未测定，不作设备归因PASS。

针对该机制：构建时从冻结原OGG生成44100Hz双声道PCM16；保持2124800帧/48.18140589569161秒、6秒延迟、0.70播放器音量、Music bus与一次播放生命周期，运行时使用原生WAV播放器消除压缩音频实时解码及PreparedMusicStream构造回调。原OGG SHA256 c750b7ee2c6a3baaa326d1dbcfaaa6bca853df5c00c6adb6d444b2bbac1e71c6保持。PCM额外8499244字节，不能隐瞒包/内存开销。

引擎依据：[固定5b4e0cb0f版本Vorbis源码](https://github.com/godotengine/godot/blob/5b4e0cb0f/modules/vorbis/audio_stream_ogg_vorbis.cpp)。

## 怪物发现/追逐音效

用户确认只移除发现玩家以后、处于战斗状态时不停播放的提示，不要求关闭正常攻击声音。旧walk/turn ambient已停；当前W4又接了一次入战ambient提示，所以仍违背删除合同。移除Enemy target/tick调用，兼容入口直接no-op；服务prompt入口在创建session、取资源、RNG和声部准入前返回combat_prompt_disabled，直接事件入口也封闭。attack_start/frame及固定24声部池、6怪物并发与12/s攻击预算保留；不触碰AI/HP/移动/攻击动作时序。

预热只跳过当前生产已经禁用的怪物语义，522条原映射保存；event sample references从525降到213，所有可播放事件仍在Loading初始化预热。Summon appear旧hook已按现有禁用合同移出physics loop；旧实现在服务可用且可听时call后return true会封存，不是拒绝后无限重试，只有不可听/服务缺失时继续检查。不得将这项清理夸大为全部群怪卡顿根因。

## 连续拾取

入队时一次检查正式来源、范围和路径；已接受交易在后台写入期间不因玩家继续走动重查路径、取消和重排。地图/代次、节点pending和正式持久化receipt门禁保留。库存批量计算与单批持久化保持原权威，成功入账后回收地面节点、提交HUD结果。

提示改为完整FIFO，同一时刻一条、固定原控件复用；不再倒序插入并截断成最新三条。下一条只在当前条到期后开始，长帧不while跳过未显示条目。30条顺序UI与10个真实来源/一次入队/玩家移动/后台持久化55金币/10条HUD结果已通过，不能外推手机长帧消除。

第二轮真实链发现并复现两项业务 FAIL：等待存档的已接受节点仍在每次 manager 移动检查中重复地形射线；旧批次因正式存档边界取消未批准准备后重试，会被追加在新候选之后。现在 manager 对已接受来源直接交给交易所有者，重试及未确认尾部保留在新候选之前，不改变源节点代次、容量和持久化提交权威。

`loot_cohorts_receipt_fixed_221613_896826` 原生 PASS、退出0、源码稳定：一个真实存档边界取消未批准准备，接着连续拾取21个来源（10个药品/11个金币来源），合并为一次成功持久化；金币66、canonical item920045数量10、所有来源无误拒绝、提示21条原序、已接受来源20次移动检查零新增地形准入查询。`loot_manager_related_221655_416567` 管理器原回归 PASS；`loot_pending_lifecycle_related_221725_748657` 过期保护/回执生命周期2 PASS。不是手机流畅度证明。

所有中间失败保留：槽位施工半完成阶段引起的 loader 解析 FAIL、两项业务红测、测试使用不存在的 catalog `entity_id` 以及误将 wire 存档和 runtime 记录直接等同的夹具 FAIL。夹具修正使用正式 GameData.item_entity_id，并严格核验存档稳定ID/数量/名称；没有改变生产预期或削弱入账断言。

## Loading及地图名称继续接入

用户追加反馈角色选择进入比奇时60%跳0；现有CharacterSelect先报25/60/100，随后HUD新world overlay重置0。前置角色准备仅呈现阶段文字，世界Loading仍按正式阶段显示0到READY，避免两个不同总量的百分比连续出现，不加等待或另一份加载权威。

当前正式名称源map_identity_registry使用“比奇省（单机重制）”；按用户要求改为“比奇省”，通过精确目标authoring/生成链更新，稳定ID、人工地图内容、几何与素材保持。施工/最终回归进行中。

## 验证边界

独立source epochs和完整receipt见NATIVE_PROGRESS_RECEIPTS.json，原失败证据保留：

- 正式canonical药品红测FAIL；修复候选6 PASS/0 FAIL，9种真实canonical药品播放一次、49alias精确等价、原生PCM自然结束与再入城通过。
- 连续拾取两个红测FAIL；修复候选7 PASS/0 FAIL，真实持久化/地图代次/库存/地面/提示均通过。
- 发现提示红测FAIL；修复候选7 PASS/0 FAIL，30 owners×120旧入口无声部/取资源/会话/RNG，实际攻击、旧帧不重播通过。
- 扩展相关回归15 PASS/1 FAIL：player_core_audio_hook旧夹具未在正式sealed base plan发布目标，被unpublished spawn门禁拒绝。保留该FAIL，仅迁移夹具到既有正式地图发布/创建链，保持monster38及命中/闪避/魔法/致死contact断言；单场复验1 PASS。
- Python alias strict registry/重复service/未知target/冲突不修改/幂等5 PASS；PCM离线生成--check PASS，原OGG与source记录字节保持。

以上是中间范围。用户明确先完成连续拾取，再继续群怪卡顿，暂停最终整合回归和封装。拾取继续检查在途批次、新来源入队、存档状态变化重试的稳定顺序和已接受节点的重复碰撞查询，不能用此前七场 PASS 声称全链完成。

用户最新掉落槽合同：白怪（ordinary）6、精英（elite）9、Boss 12；全部源槽仍先进行 RNG，掉落保护及保护内优先级、同级无偏选择保持。分组由正式 canonical monster classification 决定。drop_group_functional_222339_996459 四场原生 PASS、退出0、源码稳定；历史与当前概率数据未改。该阶段有一场既有测试清理泄漏告警，已补 service.free()，待直接复验；没有把告警删除或把此阶段作为新整合验收。

## 用户追加概率、售价和名称显示调整

黑铁矿各纯度出售90000，远古圣物碎片100000，合成圣物与徽章200000。用户已确认“祖玛雕像”指祖玛教主掉的既有物品祖玛头像（hc.item.920032），售价1000000；不新增物品身份或用途。正式报价/交易专项待跑。

祝福油最终提升幸运概率为当前5倍，保持原不幸、诅咒、消耗与存档事务。幸运1–2两个条件分支简单各扩大5倍不能得到总概率5倍，已要求按完整两draw联合空间精确计算；该实现及专项进行中。

小极品最新要求为3倍（覆盖早先2倍）：以最终至少一项真实非零bonus为事件，不能将外层1/2 gate简单封顶。按已认可完整装备分级登记精确沃玛及以上ID，有限条件采样保持出现后的原有联合属性分布；需版本化保留已有v3装备/存档验证。施工中，尚无原生通过证据。

最高级红字金边在正式展示authoring中将outline_size从2增至4，当前字体描边路径的可视宽度加倍；保留红色字心、金边颜色、字体、完整名称与所有物品分组。[Godot 4.7固定字体源码](https://github.com/godotengine/godot/blob/5b4e0cb0f/modules/text_server_adv/text_server_adv.cpp#L1425)中FreeType stroke使用outline_size×16/64，描边后独立绘制文字，不能把参数值直接宣称手机物理像素。装备属性面板名称20→18号，属性仍14号。只改上述展示参数，经正式build_item_name_rarity.py生成248项。隔离原生Godot OpenGL渲染预览成功，用户看过左右对比后明确答复“很好，金边用现在的”，已接受加粗金边；设备可读性未验收。截图在outputs/monster_upgrade_20261007/name_outline_preview/rare_name_outline_comparison.png，未启动真实存档或改变真实游戏状态。

用户要求确认复活、麻痹等特殊戒指的正式接线，当前只读审计进行中；不依据物品描述推断功能已生效。

群怪流畅度未解决，按用户手机体感验收，不重复性能采集。DEVICE TEST: NOT_RUN；当前修复未出新APK，v106不包含本轮音频/拾取/Loading/文案改动。
