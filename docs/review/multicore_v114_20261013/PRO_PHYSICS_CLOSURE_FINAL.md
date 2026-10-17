# HardCore：独立模拟的最终物理闭合补充设计

日期：2026-10-13  
状态：设计裁决；未修改引擎或游戏，未构建，未运行原生、对照、性能或设备实验。  
本补充覆盖前两轮总设计中笼统的 PhysicsPort：此后不得以“线程安全服务器接口”代替下面的主循环、控制器和生命周期闭合要求。

## 0. 最终选择

**选择 B：维护范围受控的 Godot 引擎／内建 C++ module 适配，将原单一 GodotPhysics2D 后端的唯一同步、查询服务与 step 所有权移交唯一模拟线程 S。**

更具体地说：

- 保留同一套 GodotPhysics2D 后端、形状、broadphase、接触求解、body motion test 和 ray intersection 算法。
- 不创建第二个 GodotPhysicsServer2D，不在运行中交换 singleton，不做两个线程各 step 一个 space 的隐式混用。
- 运行模式下，**整个进程的这一个 2D 物理服务器由 S 独占**；全部活动游戏 space 都归 S 调度。不是只声明某个地图“归 S”，同时让 Main 继续 step 同一个服务器。
- M（画面／输入线程）不执行这些游戏物理调用，不接战斗回调，不用表现代理 transform 回写物理。
- 将 PhysicsBody2D／CharacterBody2D 的运动控制逻辑抽成同源、显式 delta、无活动 Node 依赖的内部控制器；这不等于另复制一套物理求解器。
- W（工作池）承担已批准的纯数据批处理；**不并发调用活动 space 的 motion test 或 LOS**。Godot 原 step 中已有的内部并行继续由原 step 管理。
- **必须自编引擎运行时和 Android export templates。官方未修改模板＋普通 GDExtension 不能交付这一路线。**

A 不选：把当前所用物理彻底抽成第二个独立库，需要自行维护 broadphase、形状生命周期、接触状态及若干 singleton／ObjectDB 依赖的隔离，验证面比保留原后端更大。

C 不作为目标：旧版保守运行可以作为未达到切换门禁时的发布备份，但不能把“仍由 Main 服务实时物理”称为独立模拟已经完成。

这里的“范围受控”不意味着“改两行就完成”。引擎钩子、控制器去 Node、回调闭包及地图资源所有权都是真实施工内容。

## 1. 本轮证据边界

### 1.1 实际核对的官方来源

本轮通过官方 raw 源码页面和 GitHub 文件分段读取核对 Godot `4.7-stable`。GitHub tag 查询在本次读取中返回：

```text
refs/tags/4.7-stable
commit: 5b4e0cb0fd279832bbdd69fed5354d4e5ad26f88
```

关键读取包括 `main/main.cpp` 的真实物理循环、PhysicsServer2D 声明／绑定区／包装层、GodotPhysics2D 注册与后端、运动控制器、space 查询、body／area 回调、SceneTree 和 World2D。

`main/main.cpp` 已通过 GitHub 原始行区间 4870–5060 补读，确认用户指出的 4992–4997、5036–5037 附近次序。web 的 raw 页面会压缩空行，下面主要以文件＋函数定位，不把网页显示行号伪装成原文件行号。

本轮没有得到完整引擎本地克隆或逐文件 SHA256 清单，不声称做了完整引擎哈希审计。没有读取当前 114 完整源码；Player／Enemy／LOS 的生产调用情况、当前 enemy.gd 指纹和身份合同按用户本轮提供的源码核对事实使用。

当前 `enemy.gd` 指纹（用户提供，不是本轮自行下载核验）：

```text
d8f73dc3c9dcc17f81a4031d19154544ce3f89b5a3e945c51f9caa10b01653f3
```

查阅 `4.7-stable` 不等于已证明现有 APK 使用了同一引擎 commit／编译配置；投产门禁必须把实际引擎身份补齐，不得借物理迁移顺便升级求解器。

### 1.2 已核实的决定性事实

| 文件／函数 | 源码支持的事实 | 设计含义 |
|---|---|---|
| `main/main.cpp :: Main::iteration()` | `sync → flush_queries → main_loop.physics_process`；随后 `end_sync → step`，还穿插消息队列、导航和 iteration 边界 | 改线程必须搬完整相位，不是只搬 step |
| `servers/physics_2d/physics_server_2d.h/.cpp` | step/sync/flush_queries/end_sync 是内部 virtual；公开绑定区没有这四个直接驱动口 | 普通 GDExtension 不能当默认世界的手动 step 驱动器 |
| `modules/godot_physics_2d/register_types.cpp` | 标准工厂创建一个后端并包一层 WrapMT | 包装层与后端是正常的一套服务器，不是两个独立世界 |
| `physics_server_2d_wrap_mt.cpp :: init()` | 非内建独立线程模式仍将 `server_thread` 设为 MAIN_ID | 关掉 separate-thread 后直接从 S 调用仍不成立 |
| `physics_server_2d_wrap_mt.h` | motion test、direct state、shape collide 等有明确主线程检查；异步分派也特殊允许 sync 期间的 Main | 必须改为显式 owner/phase 门禁，不能只删断言 |
| `godot_physics_server_2d.cpp :: step()` | 遍历全部 active_spaces；sync/flush 状态属于该后端 | 不能 Main 和 S 共享后端、各自以为只管自己空间 |
| `character_body_2d.cpp :: move_and_slide()` | 读取 Engine 当前相位与 Node process delta，读取平台 direct state | 需要显式 StepContext 的非 Node 控制器 |
| `physics_body_2d.cpp :: move_and_collide()` | motion test 后还有 recovery/cancel-sliding 修正及 transform 提交 | 只调用 body_test_motion 不能等价替代 move_and_collide |
| `godot_space_2d.h/.cpp` | 查询写 space 内公共 scratch；ray 命中后会 ObjectDB resolve | “查询只读”不代表可多 worker 并发；需原生身份返回适配 |
| `godot_body_2d.cpp` | kinematic 写 transform 通常先写 new_transform；step 后阶段再积分 | 游戏逻辑位置与物理内部时态不能强行抹平 |
| `godot_space_2d.cpp :: call_queries()` | 原次序服务 body state queries，再服务 area monitor queries | 玩法回调须在 S 同相位执行，不能整包延后到 M |
| `godot_step_2d.cpp :: step()` | 锁 space，并已有 constraint setup／island solve 的工作池任务和完成屏障 | 保留成熟内部并行；不是另起一个不知何时完成的 step |

来源见文末 S0–S16。

## 2. 唯一服务器、space 与线程所有权

### 2.1 一套服务器，不做第二实例

标准创建链仍只调用一次，保持 `PhysicsServer2D::singleton` 指向统一外层服务对象、`GodotPhysicsServer2D::godot_singleton` 指向其内部原后端。两个指针不应被改成指向两个世界。

`new GodotPhysicsServer2D` 会改变全局后端 singleton；`step()` 也不是 space-local API。因此本方案明确不用：

```text
Main：默认后端/space A
S：另 new 同类后端/space B
```

也不用：

```text
Main 和 S 都持有同一个 PhysicsServer2D，轮流或者同时对不同 space 调 step
```

### 2.2 运行所有权表

| 资源或操作 | owner |
|---|---|
| 原服务器实例、RID 表、形状／body／area／joint／space 的运行期修改 | S |
| live body motion test、direct body state、LOS | S，且处于规定可查询相位 |
| backend step、sync、flush_queries、end_sync | S，每个合法逻辑步按原次序一次 |
| step 内已存在的约束并行 | Godot 原 step 在其内部管理；不向业务 W 暴露 space |
| 独立数值规划、已冻结自定义几何、表现参数 | W，输入和输出生命周期受控 |
| 画面节点、纹理和 UI | M |
| 主线程性能监视／物理调试显示 | 读取 S 发布的数值快照，不现场读 live backend |

物理空间可以多于一个，但所有活动空间仍由同一 S 按原服务器机制步进。第一版不增加 per-space 独立 step API。若还有未迁移的活动 2D 游戏场景，它必须纳入 S，或整个会话继续旧模式；不能形成混合权威。

### 2.3 不伪造“主线程”身份

新增的只是物理所有权状态，例如：

```text
BOOTSTRAP_MAIN → HANDOFF_QUIESCENT → OWNED_BY_S → STOPPING_S → FINISHED
```

这是执行门禁，不是新的角色／世界身份 schema。

禁止让 S 假冒 `Thread::MAIN_ID`，禁止 S 修改引擎共享 `_in_physics` 或 `_process_step` 来欺骗 CharacterBody。控制器需要的 delta／相位从 S 的 StepContext 显式传入。

## 3. 最小引擎补丁面：具体文件与钩子

以下新方法／文件名是施工建议，不是已有 API。

### 3.1 `main/main.cpp`

- `initialize_physics()`：仍只创建和初始化一套原服务器；登记 external-owner 模式和启动握手。
- `Main::iteration()`：external-owner 模式下，Main 不再调用 2D 的 `sync/flush_queries/end_sync/step`；同时覆盖 physics_process 提前退出分支里的 end_sync。
- 不把 Main 的整个 SceneTree::physics_process 搬到 S。M 可以处理无战斗权威的画面/UI 回调，但游戏物理、计时、移动和伤害回调必须已经移除／转接。
- `finalize_physics()`：必须与 S 的 finish/join 状态协调，禁止二次 finish；服务器销毁发生在 S 已停止、无人再访问之后。
- 主线程的物理统计、调试和生命周期控制改读发布值／发控制命令，不绕开 owner 门禁直读后端。

这些入口不能只在正常帧路径打补丁，退出和异常路径同样要覆盖。

### 3.2 `physics_server_2d_wrap_mt.h/.cpp`

新增 external-owner 执行方式，复用现有后端，但不再启动 WrapMT 自己那条 command-pump 线程。S 承担 driver；GodotStep2D 原有内部 worker 并行不因此删除。

必须同时修改：

1. `init` 或受控 handoff 中的 server_thread 绑定，不再固定 MAIN_ID。
2. `ASYNC_COND_PUSH*` 及相关生成调用的 owner 处理。
3. `shape_collide`、`body_test_motion`、`space_get_direct_state`、`body_get_direct_state`、debug contact 等手写入口的线程检查。
4. 所有 live 查询与修改的 owner／phase 检查；普通 W 无权进入。
5. Main 在 sync 时可直达的旧特例，在 external-owner 模式必须关闭。
6. 非法 M 调用不能进入队列后同步等 S，以免重新制造画面依赖；应显式报错并使该会话不能被标记为闭合。

必要时在 `servers/server_wrap_mt_common.h` 增加可选的访问门禁 hook，默认行为保持原样，仅由本 2D external-owner 包装启用；不能修改共享宏而无意影响其他服务器。

bootstrap 时可以沿原 Main 创建链完成初始化，然后在队列为空、没有在途 step、没有场景物理调用时一次性移交 S。也可让新初始化入口在 S 上执行，但必须二选一实现并有一次性状态机；不允许 init 两遍。**推荐前者，以保留原工厂及全局设置初始化位置。**

### 3.3 `modules/godot_physics_2d/register_types.cpp`

保留原后端工厂，只为新模式选择带 external-owner 能力的同一包装层。不另登记并同时实例化第二个后端。

内建 pump 是否启动与后端查询同步检查须明确分离；不能通过关闭所有检查来适配 S。S 外部模式必须由包装层额外保证“owner 正确＋query phase 正确＋space 未锁”，保留原 backend 锁和 flush 限制。

### 3.4 同源运动控制器

处理这些文件中的真实逻辑：

- `scene/2d/physics/physics_body_2d.cpp/.h`
- `scene/2d/physics/character_body_2d.cpp/.h`
- 拟新增 `scene/2d/physics/character_motion_2d.cpp/.h`，或者模块内等价的共同内部实现。

推荐将原运动代码重构为共同实现，让传统 Node adapter 与 S adapter 都调用同一份控制逻辑，而不是复制后分别维护两个近似版本。

内部访问面至少包含：

```text
读取/写入控制器逻辑 transform
执行原 PhysicsServer2D::body_test_motion
取得平台的原 direct body state
按原分类判断命中的对象是不是 CharacterBody2D 类型
显式 double delta、原 motion settings 和历史控制状态
```

S 版本不调用 Node getter、不访问活动 SceneTree、不从 Engine 读取 M 当前是否在 physics frame。

保留原 grounded/floating 分支、safe margin、max slides、snap、floor/wall/ceiling 标志、平台过滤和离台速度、previous_position、real_velocity、MotionResult 次序，以及原 move_and_collide 的 recovery/cancel-sliding 修正。当前未用分支不能靠猜测删除；可在明确配置封闭后限制支持范围，未支持配置必须拒绝启动新模式。

**零位移不跳过。**原用户路径中的零位移分离依旧调用原测试和恢复；不能用 motion==0 提前返回，也不能把多次分离合并。

### 3.5 `CollisionObject2D`、`World2D`、`SceneTree` 侧适配

涉及：

- `scene/2d/physics/collision_object_2d.cpp` 的 transform 通知、入树／退树与 callback 行为。
- `scene/resources/world_2d.cpp` 的惰性 space 创建、默认 area 参数和销毁。
- `scene/main/scene_tree.cpp` 的变换 flush、暂停／suspend 对 `PhysicsServer2D::set_active()` 的写入。
- 若旧输入确实使用 physics picking，还涉及 `scene/main/viewport.cpp` 的 picking 调用链；不能让它回到 M live query。

M 的世界仅用于 canvas/呈现，不再拥有运行期游戏 physics space。M 不应通过 World2D.get_space 惰性创建第二个活动空间。必要的 picking 在原输入位置由 S 服务，UI 的 Control 路由仍由 M 处理。

暂停和 suspend 由 M 发送有序控制命令，S 在原合同边界改变后端活动与模拟时间；不能由 M 并发调用全局 set_active。物理状态恢复、超时补偿等沿原规则，不因迁移增减 tick。

地图显示代理、TileMap/TileMapLayer 等不得再次自动建立同一套碰撞；地图碰撞由原序几何描述交给 S 建立。运行期改变 shape／transform／mask 也经 S 的唯一入口。

## 4. 物理与查询的正式相位

### 4.1 保留原骨架，不前移 step

每个 tick k 的 S 主链是：

```text
原有 prepare / 已登记前置命令边界
    ↓
sync()
    ↓
flush_queries()                 # 服务上一次 step 产生的原回调
    ↓
原 physics_process 等价相位
    ├─ 原输入/physics_frame 等玩法观察点
    ├─ 原 actor 执行次序
    │    ├─ 原位置/分离/move_and_collide/move_and_slide
    │    ├─ 原逻辑位置与自定义索引发布
    │    ├─ 原 LOS 查询位置
    │    └─ 原立即攻击、HP、同步触发
    ├─ 原 deferred/group-call/timer/tween/transform 边界中属于玩法的部分
    └─ 原删除/退役边界
    ↓
原 pre-step 命令边界（包括实际适用的导航/消息关系）
    ↓
end_sync()
    ↓
step(原 physics_delta × 原 time_scale)
    ↓
原 post-step / iteration_end 等价边界
    ↓
发布完成状态；准备下一逻辑步
```

这里是相位合同，不是建议直接复制 SceneTree::physics_process 到 S。相关 gameplay timer、deferred command 和回调要变成 S 所有的等价实现；不能让 S flush 引擎全局 MessageQueue，从而在后台执行 M 的 Node 回调。

不一概把所有 deferred 动作挪到 tick 末。原来在哪个 barrier 变得可见，就保留在哪个 barrier；回调中的同步写入仍同步。当前项目具体的 `force_update_transform`、显式 transform flush 和 deferred 调用清单尚未附上，它们是这一固定设计的映射输入，不是可忽略事项。

### 4.2 phase 门禁

- S 可以在原允许的 sync/query window 内调用 live motion/LOS。
- step 锁住 space 时不进行业务查询。
- flush_queries 中的回调是否允许某项修改，保留原 flushing restrictions；原应 deferred 的仍 deferred。
- 不在发布状态前额外 flush 一轮碰撞回调，否则会把本应下一次服务的事件提前。
- tick 是否完成必须包含原对应的物理推进和必要收尾，不把“actor 已算完，step 还没完成”冒充完整 tick。
- M 不参与逐 tick 握手来许可 S 前进；帧渲染迟到不能成为下一物理步的 release 条件。

### 4.3 最容易被改坏的三份 transform 语义

需要区分的是既有系统中的时态，而不是建立第二位置 authority：

1. **控制器逻辑 transform**：原 Node 的位置读取与当次运动 from 所用值；迁移后由 S 控制器唯一维护。
2. **提交到后端的 transform 请求**：原通知/flush 何时向服务器发出写入。
3. **后端内部 transform/new_transform**：由原 body mode 和 step 在原阶段处理。

当前 Godot kinematic 的 BODY_STATE_TRANSFORM 写入通常先写 new_transform；integrate_velocities 才将其更新到后端当前 transform。原 PhysicsBody move_and_collide 的入口又可以使用控制器提供的 from。

因此，“前一个 actor 已移动，后一个 actor 的自定义索引读取新位置”，**不证明同一时刻所有 Godot ray/motion broadphase 都已观察到同一个新 transform**。

S adapter 必须重现原调用链：逻辑位置更新、相同通知去重与 flush 顺序、原 body_set_state、原积分阶段。禁止为方便或所谓修正，直接改 backend `_set_transform()` 或强制 broadphase 每 actor 更新。

父子／形状局部变换也保持原组合次序。对 current_node_position 与 backend_position 的比较，必须记录相位，不能拿不同相位的值强制“同步一致”。

## 5. LOS、碰撞返回与事件闭包

### 5.1 LOS 原位执行，不用预测替代

原攻击链在 S 的原执行点，调用同一活跃 space 的同一 `GodotPhysicsDirectSpaceState2D::intersect_ray` 数值实现。保留 from/to、mask、exclude、body/area 选择、hit_from_inside、shape 顺序和最近命中判定。

不要将 raycast 全部移到 tick 开始快照，亦不要用自定义地图点线判断替换正式 LOS。

### 5.2 ObjectDB 不是可以忽略的尾巴

官方 ray 实现会在命中尾部 `ObjectDB::get_instance(collider_id)`；CharacterBody 的某些平台分类也依赖 ObjectDB 类型判断。

必须新增内部数值返回适配：复用同一求交循环与分支，允许 S 接收 RID、原 collider_id、shape、position、normal，而不 resolve 活动 M Node。`collider` 对象返回由 S registry 的适配消费者处理；不得把 collider_id 全清零或改变过滤含义。

CharacterBody 的“命中对象是否为 CharacterBody2D”在 S 使用原类型/能力登记重现，不能一律当普通静态障碍。

### 5.3 碰撞回调不是画面通知

原 `flush_queries → GodotSpace2D::call_queries` 的顺序保留。body state／force integration 和 area monitor 的 gameplay 回调改为 S-owned 原生回调端点，在原遍历位置立即执行。

不能先把所有 area/body 事件装包，再末尾统一应用；前一个回调可能改变后一个观察到的资格或世界生命期。

也不能将这些回调 `call_deferred()` 到 M，或者保留指向 M Node 的 Callable。纯声音、特效和 UI 通知才进入有序表现输出。

新模式注册时必须拒绝未迁移的活动 Node 回调。回调触发死亡、换图或 runtime 退休时，仍按原重入检查和延期销毁边界退出；不要在正在遍历/锁定的 space 中直接释放世界。

## 6. 身份、HP、来源和存档合同不变

唯一 ActorRef 继续是：

```text
{ world, runtime_id, life_generation }
```

world_context 继续保留：

```text
contract_id
world_runtime_id
world_epoch
runtime_map_id
profile_id
```

`release_id`、`fact_id`、credit、chain 以及死亡去重键，不因线程迁移改字段、重编号或另生成一份平行命名空间。

S registry 改变的是 resolve 的后端：由活动 Node/WeakRef 查询，改为原 ActorRef 身份对应的唯一 S record。原 alive、退休、map/world 匹配与生命期检查不能因为不再有 `is_inside_tree()` 而被省略，要映射为原生命周期的注册/激活/退休状态。

内部 `RID → 原 ActorRef` 和 `array_slot → 原 ActorRef` 只是查找关系，不成为第二 gameplay 身份；RID 不写回 runtime_id。静态物理对象使用其原地图/几何归属，不伪造成角色。

既有被接受的 ActorRef 不重编。新出生角色继续使用既有 runtime_id 发放/退役合同；若旧发号入口必须创建 Object 才取得原 ObjectID，可以将同域载体改为 S-owned 的非 Node record，而不是另建一个“sim_actor_id”。该 record 不持有第二份 HP，不把同一身份重新发给下一生命。

权威 HP、技能与死亡提交全部留在 S 同一调用链。表现可晚显示一帧，但不得晚扣血或重复提交。存档仍从这一权威的明确事务边界获得一致数据，保留原 schema、落盘确认与兼容路径。

## 7. 初始化、换图、暂停和关停

### 7.1 初始化

1. 固定与原物理规则相符的引擎 commit、后端、real_t、编译设置和项目物理配置。
2. 在 bootstrap 创建唯一原后端／包装层并完成原初始化。先不运行游戏物理，也不允许另一线程访问正在转移的对象。
3. 在 quiescent 边界移交服务线程 ID 与主循环责任给 S；Main 的 2D 自动 phase 分支随模式关闭。
4. S 接收数值化地图／形状／actor 描述，按原创建和插入顺序建立 RID 与空间。World2D 原来设置的默认 area 参数、mask、shape 局部变换、one-way 参数、异常表及初始 body state 一并保留。
5. 注册 S-owned 回调，绑定原 ActorRef registry。M 只创建不会重复生成碰撞的表现节点。
6. 确认 gameplay producer 已停止旧 Node 写入，物理与表现各自 ready 后才开放会话。

这不是要求后台实例化整棵旧 PackedScene 并调用 _ready。碰撞资源运行期由 S 创建/修改；Main 的资源加载不能悄悄从 Shape2D/TileMap 回调写同一批 live RIDs。必须使用描述数据或受控 bootstrap 移交。

### 7.2 换图与退休

- 换图请求进入 S 的原事件位置，沿现有 world_context/world_epoch 规则退休旧运行域，不新增业务世代 schema。
- 停止向旧域派发新任务；已经接受的历史事实、来源和清理规则按原合同结束，不能简单清空全部队列来伪造顺利退出。
- 正在执行的回调先按原规则返回到安全边界。旧 space 不再参与后续 step，旧回调不再能写入新世界。
- worker 不持 live RID/space 指针。仍持有旧不可变输入的任务有限完成后回收，再释放对应输入。
- S 在合法相位断开回调、退役原对象与索引，释放 joint/body/area/shape/space。space 的默认 area 由原后端的 space 释放流程处理，避免二次 free。
- 保持同一 backend singleton，建立新 space/世界；不是每张地图 new 一次 PhysicsServer2D。
- 不增加额外 step/flush 来“帮助清干净”，否则可能产生原本不该发生的碰撞或伤害事件。

### 7.3 暂停／Android 后台

M 把暂停、恢复和退出作为有序控制命令发送。S 在原安全相位停放或恢复，原时钟补偿规则显式适配。不得继续让 SceneTree 在 M 并发 set_active，也不得因 Android 渲染停止而无限积压逻辑 tick。

### 7.4 关停

S 停止新输入和派发，完成当前合法退出边界，回收有限在途任务，退休物理资源，在正确 owner 上执行一次 finish。M 在 S 完成并 join 后，才销毁外层包装与其包含的后端。

`finalize_physics()` 必须知道 finish 已执行，不再调用第二遍。程序关闭时允许有限 join；正常战斗不能每 tick 等 M。

## 8. 多核边界的修正

本轮对前两轮方案作一项重要收缩：

> **不能把活动 Godot space 的 motion test／LOS 作为普通“只读几何任务”直接分散给 W。**

原查询使用共享 scratch；body_test_motion 还可能触发 shape 更新。它们在 B 的首个闭合版本中由 S 原序执行。纯数值候选、自定义空间规则的已冻结计算、命中准备和表现准备可以继续用 W；真实物理消费点仍在 S。

另一方面，`GodotStep2D::step` 已有 constraint setup 与 island solve 的工作池任务，并在相应位置等待完成；pre-solve 留在原串行路径。这是保留的成熟实现，不需要自制并行求解器。

S 作为独立线程调用 step，避免自己占住工作池槽后再等待该池；也不让不相关长任务占满池，使原 step 的任务迟迟无法执行。业务 W 的同 tick 准备需有界，并给原 step 的关键任务留出服务机会。

物理关键路径的必要成本仍包括：

```text
T_sync/flush
+ T_原序运动与live LOS
+ T_原序战斗提交
+ T_物理step及其内部barrier
+ T_必要收尾
+ 新增交接/修复
```

可重叠的纯数值和表现准备另按真实依赖计入。将这些重工作搬离 M 可以真正关闭显示线程负担，但**若 S 本身超出逻辑期限，不能用高呈现帧率或八条worker掩盖模拟迟到**。本设计不承诺手机60FPS，也不在本轮推算提升比例。

## 9. 模板与维护成本：明确需要自编

### 9.1 标准模板能否继续使用

**不能作为新物理owner模式的运行模板使用。**标准模板缺少 Main 物理所有权分支、WrapMT owner/phase 修改、共同运动控制器与原生回调接入。只替换一个 GDExtension .so 不会改变这些内部行为。

可继续使用 Godot 原导出/Gradle流程，但必须换成同源自编的：

- Android debug/release native libraries 与模板；
- 按现有导出方式配套的 `android_debug.apk`、`android_release.apk`、`android_source.zip`/Gradle构建材料；
- 同补丁集的桌面运行时，用于源码与语义回归；
- 若编辑器要识别新增 module 类并直接运行该模式，还需要配套自编编辑器。只做纯资源编辑的官方编辑器不能充当新模式运行验收器。

官方构建文档说明了 custom templates 与 Android 产物的构建/使用方式；实际命令、NDK/JDK与Gradle版本以锁定引擎树为准，不照抄其他版本参数。

### 9.2 必须承担的成本

| 成本 | 范围 |
|---|---|
| 引擎补丁维护 | 主循环、WrapMT、控制器、回调和生命周期钩子随引擎更新复核 |
| 构建矩阵 | Debug/Release、arm64-v8a及原产品实际支持的其他ABI、配套桌面运行时 |
| 调试可追溯 | 引擎提交、补丁提交、构建选项、native符号、模板哈希与APK映射 |
| 行为验证 | 物理与游戏两层顺序回归，不只看“能启动” |
| 资源/平台适配 | 不允许旧Node代理重复注册碰撞，输入/暂停/关停链闭合 |

包名继续 `com.personal.mafaoffline`；签名、存档目录、schema、升级安装路径不变。不通过更换包名、清档或卸载旧版来规避问题。

## 10. 同算法、同结果的验收门

**本节是后续正式施工验收规范，不是本轮要求运行实验。**

### G0：真实引擎与资源基线

绑定生产实际引擎二进制、源码提交、后端名称、项目物理设置、real_t、编译器/浮点选项、地图与形状配置。`4.7-stable` 是本轮核查基线；若实际交付使用别的引擎字节，先对齐，不能在架构迁移中暗含升级。

### G1：owner 与相位

每个 tick 的 sync/flush/end_sync/step 次数、顺序和执行线程有记录；Main 的游戏物理调用计数必须为零。覆盖提前退出、暂停、换图、后台、shutdown。

非法线程/相位调用必须显式失败并判新模式不可交付，不能被转换为“未碰撞”“LOS畅通”等普通 gameplay 返回值。

### G2：运动调用迹线

从完整 Player/Enemy 原链比较，不仅测单个 kernel。比较每次零分离、move_and_collide、move_and_slide 的：

- from/motion/delta，safe margin、test_only、recovery_as_collision、cancel-sliding等；
- 原空间/shape顺序、mode、mask、exception、one-way和平台参数；
- bool、travel、remainder、safe/unsafe fraction、normal、depth、collider/shape；
- 每次 slide 结果顺序、floor/wall/ceiling、平台状态、velocity、real_velocity；
- 逻辑位置、通知/flush写入和后端积分各相位的值；
- 后续原Index、绕路首选、立即攻击与HP事实。

包括零位移重叠恢复、斜墙/墙角、窄口、多体接触、同bucket移动、出生/消失、平台/one-way（凡当前正式配置能到达的分支）及重入。

### G3：LOS

比较完整query参数、无命中/命中、命中对象与shape、交点/normal、起点在形状内部、exclude和相同距离候选。不能只比较最终bool，更不能用“两个障碍反正都挡住”忽略命中身份变化。

### G4：回调与命令可见性

比较 flush_queries 的body/area服务次序、回调内同步写入、原deferred边界、死亡与换图重入、timer/group-call等实际参与玩法的次序。不得把事件排序成更整齐的新顺序或把同步回调搬到M。

### G5：身份和事实

ActorRef schema、world_context字段、release_id/fact_id/credit/chain、死亡去重和存档收据不变。允许对照工具显式映射纯内部RID地址，但不得排序/归一化掉真实动作次序或篡改业务ID。新生命不能消费旧结果。

### G6：算法与数值

先让传统Node入口与S入口共享同源运动实现，以减少双实现漂移。相同平台、同编译选项、同输入和同创建顺序下优先要求数值与离散决定一致；不先放宽epsilon，不把FMA/fast-math重排当无害。

原后端本身的分配/遍历和浮点跨平台差异不能凭口头承诺消失。同距离碰撞、shape插入次序和接触结果必须纳入对照；“同算法”是必要条件，不是免验收许可证。

### G7：生命周期与模板

确认无Main proxy回写、无另一活动碰撞世界、无重复init/finish/step、无残留Node Callable、无悬空RID/缓冲。自编模板中确实包含新驱动，不能用官方模板的成功导出冒充新模式运行。

### G8：最终目标

必须同时报告M呈现链、S完整tick、原step内部任务、业务worker、查询/修复、输入服务和已提交状态年龄。S持续落后时不以画面帧率单独签收。PC通过不等于荣耀REA-AN00验收。

## 11. 最小施工顺序与停止条件

1. **固定引擎补丁分支与身份基线。**先完成上述owner模式、共同运动实现及关闭Main物理路径所需钩子，保留可整体启动的旧运行模式用于对照。
2. **真实战斗闭包迁移。**Player、Enemy及参与其碰撞/LOS/伤害的当前对象和回调整体进入S；不是只搭一个空循环。原算法、原索引和原提交在S中跑通。
3. **接原后台批处理。**只对有严格纯数据边界的较大任务并行；活动space live查询仍在S，原step内部并行不重写。
4. **完成生命周期、模板、同序结果和期限验收后再切换生产。**当前会话不可热切出两份权威；模式切换只在冷启动/完整世界重建边界执行。

任何门未闭合，发布保持旧模式，状态明确为“独立物理未交付”；不能静默把LOS/运动送回M之后继续标注已独立。

## 12. 封口结论

**本项目采用 B，而不是 A，也不是把 C 包装成目标。**

成熟部分保留原GodotPhysics2D、原运动/查询算法、原step内部并行、引擎线程机制与导出构建链。专用新增部分是唯一owner驱动、同源非Node控制器、原相位队列、S回调端点、RID与既有ActorRef映射、地图与模板适配。

需要自编模板，也需要持续维护一个范围受控的引擎补丁集。它不是“标准模板线程安全设置”，但可以把当前决定性的主循环依赖真正移除。

本轮结论是**已选定可施工的物理所有权与相位设计**；不是实现完成、同结果已通过或手机性能已证明。

---

## 官方来源索引

以下为本轮实际读取的主要来源。代码链接指向指定 `4.7-stable`；施工应将其锁到上文tag解析提交。

- S0：[官方tag身份](https://api.github.com/repos/godotengine/godot/git/ref/tags/4.7-stable)。
- S1：[main/main.cpp](https://github.com/godotengine/godot/blob/4.7-stable/main/main.cpp#L4870-L5060)：Main::iteration、initialize_physics、finalize_physics。
- S2：[PhysicsServer2D声明](https://github.com/godotengine/godot/blob/4.7-stable/servers/physics_2d/physics_server_2d.h)；[实现与绑定](https://github.com/godotengine/godot/blob/4.7-stable/servers/physics_2d/physics_server_2d.cpp)。
- S3：[WrapMT头文件](https://github.com/godotengine/godot/blob/4.7-stable/servers/physics_2d/physics_server_2d_wrap_mt.h)；[实现](https://github.com/godotengine/godot/blob/4.7-stable/servers/physics_2d/physics_server_2d_wrap_mt.cpp)。
- S4：[GodotPhysics2D注册](https://github.com/godotengine/godot/blob/4.7-stable/modules/godot_physics_2d/register_types.cpp)。
- S5：[GodotPhysicsServer2D](https://github.com/godotengine/godot/blob/4.7-stable/modules/godot_physics_2d/godot_physics_server_2d.cpp)。
- S6：[PhysicsBody2D](https://github.com/godotengine/godot/blob/4.7-stable/scene/2d/physics/physics_body_2d.cpp)。
- S7：[CharacterBody2D](https://github.com/godotengine/godot/blob/4.7-stable/scene/2d/physics/character_body_2d.cpp)。
- S8：[CollisionObject2D](https://github.com/godotengine/godot/blob/4.7-stable/scene/2d/physics/collision_object_2d.cpp)。
- S9：[World2D](https://github.com/godotengine/godot/blob/4.7-stable/scene/resources/world_2d.cpp)。
- S10：[SceneTree](https://github.com/godotengine/godot/blob/4.7-stable/scene/main/scene_tree.cpp)。
- S11：[GodotSpace2D实现](https://github.com/godotengine/godot/blob/4.7-stable/modules/godot_physics_2d/godot_space_2d.cpp)；[共享查询缓冲声明](https://github.com/godotengine/godot/blob/4.7-stable/modules/godot_physics_2d/godot_space_2d.h)。
- S12：[GodotBody2D](https://github.com/godotengine/godot/blob/4.7-stable/modules/godot_physics_2d/godot_body_2d.cpp)。
- S13：[GodotArea2D](https://github.com/godotengine/godot/blob/4.7-stable/modules/godot_physics_2d/godot_area_2d.cpp)。
- S14：[GodotStep2D](https://github.com/godotengine/godot/blob/4.7-stable/modules/godot_physics_2d/godot_step_2d.cpp)。
- S15：[Godot官方Android编译／自定义模板文档](https://docs.godotengine.org/en/stable/engine_details/development/compiling/compiling_for_android.html)：只作构建方式依据，实际工具链以锁定引擎树为准。
- S16：[官方构建系统与export templates](https://docs.godotengine.org/en/latest/engine_details/development/compiling/introduction_to_the_buildsystem.html)：说明模板/构建关系，不用于替代4.7代码事实。

本次执行状态：SOURCE_REVIEW=已进行定点核对；DESIGN=B已裁决；IMPLEMENTATION/BUILD/NATIVE_TEST/PERFORMANCE/DEVICE_TEST=NOT_RUN。
