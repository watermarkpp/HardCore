# 功能资源闭包施工设计

范围：沿用用户RFC v2 §16.3、§17及已授权FRAMEWORK_PUBLICATION_CLOSURE_PLAN Task3；不是新的玩法、资源画面或准入产品规则。只在第三树施工，保持默认关闭、唯一HP/planner/writer，冻结既有MonsterStreaming与源素材。此文是后续内部实现接口记录，当前资源闭包仍FAIL，不能当作已实现证明。

## 当前已证伪边界

- e9c3ac005bc3e079eab6602375abfcd9c1bf3cc9中资源目录诊断3检查/1FAIL：Authority.resource_paths为空，真实疗伤药图标无法声明。
- 后续feature_resource_readiness_red_022600_279575，内容6d8d7ab5f4fa98f7459e4b32d75e990a2dc6d18ab3fb5de18ac316e9811fd104，5检查/2FAIL。真实路径res://assets/art/items/service/inventory/client.classic_raw_complete/Items_00014.png存在、ResourceLoader.has_cached=false。受控编译authority明确允许该路径后目录编译成功，实际PlayerState._prepare_feature_configuration仍返回success=true，根本没有资源准备或持有凭据。这是受控正式准备API反例，没有扩大ContentLayers信任，也没有发布候选或触碰真实存档。

所需不变量：路径/定义验证成功、引擎实际资源就绪、资源存活所有权是三个不同边界；不可用其中一个替代另一个。

## 接入与所有权

1. 新增功能资源声明目录，使用登记的稳定resource_id、精确项目路径及受控类型。只接受打包的声明与资源，明确拒绝脚本/场景执行资源、user/远程/越界路径、未知类型、重复或身份冲突。声明复用原数据路由与来源证明，不能把所有res路径加入白名单或复制现有物品属性主源。
2. 目录compiler继续只编译不可变plain数据。resource_paths来自验证后的声明目录；声明/依赖错误在整个候选发布前拒绝。实际准备单独持有typed Resource，不能把Resource/Node/Callable塞进plain graph、存档或伤害事实。
3. 资源准备对象按catalog revision和精确启用模块依赖集合创建。解析requires闭包及其资源集合，去重共享路径，加载就绪后逐项验证真实类型及可用性。Godot ResourceLoader是共享加载/缓存权威，复用load_threaded_request/status/get；没有第二个永久纹理缓存，没有冷加载同步fallback，未LOADED时不调用可能阻塞的get。
4. 同一准备generation保存请求、就绪待应用与持有项，FrameBudget沿用原process epoch/1200us总账；请求、轮询、绑定、释放以有界量子计费。任何await必须在scope关闭之后。取消不能假定引擎线程请求已经停止，仍须有完成/释放收尾。未激活、无准备和无待释放资源时不新增逐帧工作。
5. 维持同步旧接口的空资源路径。非空候选采用显式异步准备/发布：准备阶段保留旧目录和人物装配，最终提升重新核验目录代次、请求身份、profile和原合法生命周期边界，然后同步提交目录和人物；过时/失败/取消候选不发成功通知。不允许live任意目录/脚本/资源热替换，不延后已经锁定的正式攻击投递时刻。
6. 真正就绪的资源租约绑定该候选的revision与精确资源集合；PlayerState准备入口拒绝无凭据、未就绪、错误集合或旧候选凭据。装配candidate_copy保留资源引用，ActionConfigLease在接受时持有不可变配置对应的资源；DamageBatch及队列entry/持续state分别在既有交接处接过引用。未来停用撤新来源，不能丢掉已接受工作的资源。
7. 批次容量新协议保留：reserved归action、producing归batch、queued归consumer。资源跟随同一明确终态而不是TTL/LRU；资源最后所有者退休时通过现有预算准备/释放流程收尾。跨世界取消依既有世界合同，不把Actor退出误当作全世界退休。

## 原生验证次序

- 先建立正式异步准备正例和缺依赖/未准备负例，再实施声明/prepare/ready lease；新API缺失是明确RED，不把握手或单marker当完成。
- 冷路径记录请求前缓存/线程状态、实际请求、LOADED、取得与类型/尺寸；热路径单列cache命中，不声称新线程完成。缺文件、错误声明、类型不符、失败和取消均保持旧发布。
- 依赖/子依赖闭包、共享路径去重；两个装配/接受动作共享同一真实引擎资源，退休其中一个不能使另一个失效。
- 生命周期或profile在等待中变化、较新候选替换、暂停、退出、目录失败：旧候选不得提升；请求与强引用必须有终态。
- 真实Root/Player接受非空票据攻击，准备前不增加MP/RNG/HP变化，准备后沿原时序完成；卸装/停用/源死亡后已接受批次和until_expired状态继续拥有资源，到终态释放，不重开旧身份。
- FrameBudget同epoch、量子/在途/关闭及内存有限观测；最终同源码跑资源直接专项、相关发布/lease/容量/receipt/live-cold，再固定SHA双审计。CPU、纹理可用性与PC原生证据不替代首次GPU绘制或Android检测。

Task3状态：FAIL，尚未实现上述声明/准备/租约完整链。Task4异构机制、Task5整体模板/生成组合/设备交付、职业预览cache和原B缺失各自跟踪，不以本设计或既有658项PASS关闭。
