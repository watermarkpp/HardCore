6aab18ff 独立复审完整结果
请求身份：resource-followup-6aab18ff-20261004
固定 SHA：6aab18ff1588b879e1fad659fba4b71fff6f6c75
父 SHA：1a3e6263a094b9ed004465be12b5a9c22b97ca9c

结论：持续服务公平性、声明失败拒绝、音频主源与required资源闭包，以及既有THREAD_LOAD_FAILED负例的实测证据可按范围接受。取消发布仍有两个窗口未关闭；负例监督脚本另有安全复用问题。这些应分别处理，不推翻已成立的成果，也不标整套Task3通过

1. P1：被取消等待者恢复后再次取消，仍可把已提交A改报失败

新代码正确跳过正在执行的应用，也把其他取消续体推迟到Budget.end之后；但结束scope之后的通知顺序仍留了窗口：
- A已完成配置和人物提交。其通知中有等待者B被取消，B进入deferred completions，A被跳过
- apply回调返回后，_applying_request已清零，ContentLayers提交保护也已退出
- service先恢复B的取消续体，此时A仍在_requests，成功结果还未送达
- B的取消处理再调用一次正式cancel_feature_resource_preparation或cancel_all，会把A完成为false并从集合移除
- 稍后送达A=true时，因A不存在而忽略

结果仍是“配置已经提交，但原调用返回false”。这不是旧1a3原样重报，而是新修复把窗口移到了deferred取消续体中

最小原生反例：在现有service模式的_capture_other等待返回后，再调用一次正式取消。要求A保持true、B为false、每个请求只完成一次，所有续体恢复时scope=0

最小修复：在发出任何外部completion回调前，先让已经执行的应用具有不可撤销的终态，并退出可取消集合。不能靠延长预算scope包住观察者回调

[新完成顺序](https://github.com/watermarkpp/HardCore/blob/6aab18ff1588b879e1fad659fba4b71fff6f6c75/scripts/features/runtime/feature_resource_preparation.gd#L120-L142)

2. P2：ready已排队时直接取消service，会遗留publication guard

准备已成功，apply_ready进入队列后，直接service.cancel_all令该请求返回false。两个公开异步入口直接return await apply_ready，没有该退出路径的operation清理；队列之后因请求不存在跳过apply回调，原本由回调释放的guard就一直保留

随后正常reload/enable会持续得到feature_publication_in_progress，直到额外正式取消。这是父版已有、此次尚未覆盖的直接服务取消边界

分别补catalog reload与module enable的queued-ready取消反例：取消后能立即发起新的合法发布，pending和scope排空；退出清理必须只清理本次operation，不能让旧调用清掉较新调用的锁

[reload异步返回](https://github.com/watermarkpp/HardCore/blob/6aab18ff1588b879e1fad659fba4b71fff6f6c75/scripts/layers/runtime/content_layer_registry.gd#L113-L128)
[module异步返回](https://github.com/watermarkpp/HardCore/blob/6aab18ff1588b879e1fad659fba4b71fff6f6c75/scripts/layers/runtime/content_layer_registry.gd#L314-L343)

上述两项为源码确定性推导，未由我运行Godot。当前16项取消PASS没有涵盖这两条，不能当作已关闭

3. 原持续队列饥饿可以关闭

三个内部类别现在轮转，持续非空类别至多三个获准量子取得一次机会；frame_budget.gd与父版同blob，1200us没有增加，也没有绕过Budget.begin拒绝

原RED日志保留176次完成、ready epoch7却未完成、退休峰174；最终实测89次完成、ready epoch9→10、峰1，8项通过。32共享和有限批次回归仍保留

这个结论是内部已获准量子层面的进展，不是全局争用下无条件墙钟6帧保证。无需为该已成立修复重做整个资源调度器

4. 音频主源与声明拒绝符合限定范围

新hc.resource.sound.fire_sword.attack通过精确来源边界连接既有player.skill.fire_sword、sound137：authoring的EXACT映射、generated事件、client_assets primary策略、实际WAV路径与SHA一致

原音频/美术目录tree及原authoring/runtime映射与父版一致，没有换媒体字节或另造音频权威。AudioStream类型校验包含其子类，检查资源路径与正长度，不能用Texture2D冒充。required子模块纳入闭包、依赖撤销拒绝、subset保留和旧合法lease持有都有对应检查

声明缓存有错误时，resource-free候选现在也在FeatureAuthority构造/发布之前拒绝。控制缓存注入被准确描述为测试控制，不是自然生产文件损坏

原8项/4FAIL→8PASS；音频原6项/2FAIL→17PASS；声明25项为23个非法输入加合法基线与缓存保持检查，不是25种独立坏声明

[音频来源校验](https://github.com/watermarkpp/HardCore/blob/6aab18ff1588b879e1fad659fba4b71fff6f6c75/scripts/features/compilation/feature_resource_registry.gd#L79-L107)
[声明失败门禁](https://github.com/watermarkpp/HardCore/blob/6aab18ff1588b879e1fad659fba4b71fff6f6c75/scripts/layers/runtime/content_layer_registry.gd#L156-L172)

这证明typed非空音频准备与持有，不证明实际AudioStreamPlayer播放。测试没有消费正式cue/子效果；自然链也未因此覆盖新音频闭包。声音听感、非空资源自然混合、render/device仍未验收

5. 真实THREAD_LOAD_FAILED的这一份记录可接受

负例run 4a68bdb5-21dd-4c78-a102-4ea06d7838dd、invocation 16800799-dcaa-4c2b-af3d-7a7fce424b2a，与最终7acfe4ae…内容对应

15项业务检查全PASS，包括真实FAILED、等待发布者拒绝、旧配置保持、一次terminal get、队列/scope排空、字节恢复和新正式请求返回Texture2D。原始日志恰有约定的三条ERROR；native正常退出0、未超时，通用runner仍保留FAIL。没有新加allowlist，也没有把负例混进41个正常通过场景

归档原缓存独立解码为578字节、GST2头，SHA与注入前、native结束后、恢复记录一致。受测源码表和引擎console指纹保持。可关闭此前“缺少真正THREAD_LOAD_FAILED原生负例”的这个限定缺口，不扩成任意崩溃恢复

[该次原始负例](https://github.com/watermarkpp/HardCore/tree/6aab18ff1588b879e1fad659fba4b71fff6f6c75/docs/review/framework_resource_followup_20261004/native/feature_resource_terminal_failure_negative_051309_781002)

6. P2：监督脚本安全复用还需要修整

这不否定第5节已经发生并有证据的正常恢复，但不能把脚本当作任意异常下都可靠的可重放工具：

- 归档位置改变后parents[3]解析到repo/docs，不是repo；原运行目录深度才正确。应使用显式校验的项目根，或与位置无关的根定位。仅修归档启动路径不需要重跑旧负例
- 备份发生在启动runner之前，恢复发生在runner锁释放之后；锁没有覆盖整个破坏/恢复窗口。第二个监督者可能备份到临时坏缓存，子runner被锁拒绝后又把坏字节恢复回去。应由一个所有权锁覆盖备份、注入、子进程终止确认和恢复核验，避免嵌套非重入锁
- finally先read_bytes诊断，再write_bytes恢复；缓存丢失或不可读时，诊断异常会跳过恢复。诊断应best-effort，恢复在独立finally中执行，两类错误都记录并失败关闭
- GDScript从.import派生目标并检查前后缀，监督者备份固定文件名。安全复用前需确认两者指向同一个已校验目标；当前普通符号链接检查不等于Windows junction/hardlink/路径替换防护

[监督脚本](https://github.com/watermarkpp/HardCore/blob/6aab18ff1588b879e1fad659fba4b71fff6f6c75/docs/review/framework_resource_followup_20261004/negative_supervisor/run_terminal_failure.py#L10-L45)

已记录的是正常监督收尾，不是监督进程被强杀或物理掉电的恢复保证。源码指纹也不包含PNG/.import，不能仅凭这份源码表声称独立证明它们前后字节未变

7. 正常采用证据与字节身份

- 41个正常采用场景：35直接、6自然live/cold；40完整framework回执共926项
- 61次总尝试、6条FAIL保持，其中4业务反例、2故障注入；负例与正常采用分开
- 40份采用回执的检查数组、计数、run/invocation/source、runner终态和handoff哈希一致，before/after源码表对应最终清单
- native ZIP 4456195字节，314成员均符合manifest且与已提交Git文件原字节一致
- source ZIP 15331549字节，3668清单文件与固定Git身份一致；798份原字节相同、2870份仅CRLF→LF表示差异，与声明集合一致
- 重算内容指纹：7acfe4aef78a10a3a258fa53b6e63a60a58602478487ff239fcdaf079ae0bb4b
- 分页提交核对356唯一路径：20源码/测试/数据、334本轮证据、2相关文档。2870换行表示差异不是2870个施工改动

正常场景零engine ERROR的口径成立，但13个采用场景仍保留“8 ObjectDB instances were leaked at exit”警告，不能叫无警告或零泄漏日志。源码ZIP另含PNG、WAV、RFC三个范围外附带成员，不算3668源码清单中的额外条目

[证据入口](https://github.com/watermarkpp/HardCore/blob/6aab18ff1588b879e1fad659fba4b71fff6f6c75/docs/review/framework_resource_followup_20261004/RUN_INDEX.json)

8. 下一步

先用现有取消夹具补第1节链式取消和第2节ready队列取消的原生RED，修复完成终态与operation锁的所有权；监督脚本在下一次破坏性负例执行前补安全边界。保留已经成立的内部公平性、音频闭包、声明拒绝和已记录FAILED负例，不把这些再退回未做

Task3真实cue/子效果消费、非空资源自然/render/device、Task4异构机制、Task5模板/生成组合/全最终收尾，以及原B、主树/APK等仍按原范围开放

本次为远端源码与归档只读审计，没有执行引擎、改缓存/工程、发队列消息或启动第二施工主控
