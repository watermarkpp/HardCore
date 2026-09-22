# 本轮生成物净化只读审查

审查日期：2026-09-22。状态：PASS（静态引用闭包与候选分类）。本报告不授权删除。仅写本文件；没有删除、重命名、改源码、改生成物、启动 Godot 或执行 Git 写操作。

## 结论

- **本轮新增孤儿：0。** 当前新增的48张内容寻址PNG全部被现行正式wall plan引用，48个配套.import也应保留。
- **当前未引用历史资源：67张PNG＋67个.import。** PNG合计396641 bytes。67张全部由基线旧plan引用，且在2026-09-17历史GC回滚manifest中标记referenced=true；本轮应保留，不能仅凭当前零引用将它们归为试验垃圾。
- 旧CLI从523行收敛为46行，仅保留_init调用/报告/退出入口；发布实现已集中到490行共享服务，没有留下第二套_store_png、plan staging、commit或candidate verification。
- 现行计划引用PNG缺失、哈希命名错误、记录尺寸错误、.import缺失、.import源/目标错配均为0。计划目录无.tmp，publisher staging目录存在但为空。当前store无32ef6前缀遗留文件。

## 范围与复核方式

基线为 `b961cedff8040c9fc81534e094241ad9fa2330ad`。使用只读 `git show` 读取该基线60张plan原文，读取工作树同一60张plan，以atlas_pages和shadow_chunks中的path建立旧/新引用集合。使用只读git ls-files区分本轮未跟踪新增PNG与历史文件；主控确认当前新增PNG来源为本轮publisher。

只读取wall_render_plans/store、publisher和必要调用点。PNG只读取精确store目录中的457个文件，检查SHA-256、PNG签名及IHDR尺寸，未解码图片、未扫描其他二进制、.godot导入缓存或外部素材库。

对67个未引用候选，另外精确搜索其完整内容哈希和67个.import UID。文本扩展覆盖gd/tscn/tres/json/md/ps1/py/mjs/js/ts/txt/csv/yaml/yml/toml/xml/ini/bat/gdshader/godot/cfg，遵循rg默认忽略，并显式排除.git、.godot、outputs、dev_art_sources、已单独核对的plan/store及本报告。项目其他可见文本中命中0。输出目录未作无界搜索，仅单独读取已存在的历史GC manifest。

该结果是当前已枚举生产路径及文本约定的闭包证据，不是对未读外部备份、封存包或未来回滚需求的不存在证明。审计读取前后60张现行plan字节哈希一致。

## 集合核对

| 项目 | 数量/结果 |
| --- | ---: |
| 正式wall plan | 60 |
| 现行atlas/shadow记录引用总数 | 823 |
| 现行唯一PNG引用 | 390 |
| 基线唯一PNG引用 | 409 |
| 磁盘PNG / .import | 457 / 457 |
| 磁盘全部PNG字节 | 10657358 |
| 新引用集合减旧引用集合 | 48，全部为本轮新增PNG |
| 旧引用集合减新引用集合 | 67，全部仍在磁盘且有旧plan归属 |
| 旧/新引用并集 | 457，恰好等于当前store PNG全集 |
| 当前未引用的新PNG | 0 |
| 当前未引用的历史PNG | 67 |
| 缺失的已引用PNG / 无PNG的.import | 0 / 0 |
| SHA、IHDR尺寸、导入配对问题 | 0 |

其中341张为旧/新引用交集，48张为当前新引用，67张为旧引用退役候选。不能按单地图差集直接删资源：同一PNG可以被其他地图共享，最终候选必须以全部60张计划的全局集合计算。

## 发生引用集合变化的地图

以下10张地图的PNG集合变化。其余50张即使plan文本/绑定哈希有变化，PNG引用集合未变化。表中的每图新增/移除可与其他地图共享，不能直接相加当全局唯一数。

| map_key | 旧唯一PNG | 新唯一PNG | 此图移除 | 此图新增 |
| --- | ---: | ---: | ---: | ---: |
| bich_mine_f1 | 47 | 47 | 8 | 8 |
| bich_mine_f2 | 47 | 47 | 16 | 16 |
| bich_orc_tomb_f1 | 29 | 28 | 8 | 7 |
| bich_orc_tomb_f2 | 30 | 28 | 8 | 6 |
| bich_orc_tomb_f3 | 29 | 29 | 12 | 12 |
| mengzhong_stone_tomb_f1 | 42 | 43 | 7 | 8 |
| mengzhong_stone_tomb_f2 | 53 | 53 | 12 | 12 |
| mengzhong_stone_tomb_f3 | 44 | 51 | 23 | 30 |
| mengzhong_stone_tomb_f4 | 58 | 53 | 24 | 19 |
| snake_mine_passage_1 | 54 | 54 | 8 | 8 |

## 动态路径、导入与打包保留依据

- `scripts/world_background.gd:1396`从正式runtime文件名取得map_key，并在1398构造wall_render_plans/{map_key}.wall_render_plan.json。1414调用运行时validator；1423和1425遍历plan的atlas_pages/shadow_chunks注册派生贴图。生产加载由plan记录给出准确PNG路径，没有扫描store随机挑图。
- `scripts/map_editor/map_editor_wall_render_plan_runtime_service.gd:24`固定store前缀，227起验证目录、64位小写sha及文件名一致，252把记录路径转换为res路径；不以另一个静态PNG清单作为权威。
- `scripts/map_editor/map_editor_wall_render_publish_service.gd:15`定义正式plan目录，16定义store目录，20至22允许隔离验证目录。204起_store_png按PNG字节SHA生成{sha}.png，225把真实目录和SHA写入plan路径。该动态构造约定已纳入引用审查。
- `scripts/map_editor/map_editor_app.gd:2336`按map_key定位既有优化plan，2338至2339调用同一共享publisher；编辑器不另建一套派生PNG算法。
- 每张PNG对应的.import中source_file精确指向本PNG，remap path和dest_files相同。这是导入元数据关系，不是独立玩法引用。保留PNG时必须保留对应导入元数据；不将.import自身的source_file误判为当前plan消费。
- `export_presets.cfg:9`为all_resources，13包含wall plans。派生PNG作为导入资源进入打包；因此未被当前plan引用的历史PNG仍可能随全资源导出进入包。此处只测得原始PNG396641 bytes，未测导入后纹理或APK实际节省量，不能将原始大小直接当包体节省。
- `tests/wall_render_publisher_snapshot_test.gd:90`附近将plan/store/staging指向唯一outputs/test_logs子目录，验证后清理自己的精确夹具。测试隔离目录不应与正式store一起清理。

## 67个历史退役候选：本轮保留

公共目录为 `assets/data/runtime/map_editor/wall_render_store/`。下表每个SHA精确对应 `{SHA}.png` 和 `{SHA}.png.import` 两个文件，文件名SHA已与实际PNG字节核对。全部满足：当前60个plan引用=0；基线引用>0；其他可见文本/UID引用=0；配套.import存在；历史manifest referenced=true。

保留理由：它们是已被替换的正式历史生成物，旧plan回滚需要原像素；用户没有在本只读任务中授权删除或放弃回滚。将来若主控明确选择退役，需要先封存旧plan＋对应PNG/.import和哈希，再复核全局引用及精确目录，按成对文件处理。本报告没有进行该操作。

| SHA256（文件名） | PNG bytes | 基线引用地图 |
| --- | ---: | --- |
| `01ff8d401adfc88fa703ae0c67d50eb4e3a185d0e5dd98f1ffdc0561953bc6da` | 5658 | bich_orc_tomb_f1, bich_orc_tomb_f2 |
| `05262a25eea43421d8ffb191d6544a5833ae708764718826d517bb6c5da184c6` | 1392 | mengzhong_stone_tomb_f3 |
| `106ded596f3a949958dc5ef3bc4559f87393c3721a5f495a64f9cc32db156c99` | 4789 | mengzhong_stone_tomb_f3 |
| `2727273a28d9259beaaa76447ebef6cba2ec5c5693cdb68f7806fff7f4055588` | 2185 | mengzhong_stone_tomb_f3 |
| `27643af910cc12884d8410008561a4d1379dadf145f96a06180d6dce6b525547` | 5387 | bich_mine_f1, bich_mine_f2 |
| `2812c12d38c17dcee8aba623718215da9353c4aada53fa79a5e1f2b1890cac6c` | 5754 | bich_orc_tomb_f3 |
| `2d1f37118c635a5af3e8bed68bcff5ae46f9e15c01085425ae6ccd3cbe1dac8c` | 5024 | bich_orc_tomb_f1 |
| `2f9db87c0c37819961a6b7e7aed52b809504b3b6487ee9152e470b3bafb25437` | 9926 | mengzhong_stone_tomb_f4 |
| `30e8c8fc04c479408c7e35837a70bf8428fc5800a4690105b157342af7dd2f6e` | 242 | mengzhong_stone_tomb_f4 |
| `3423febabf4bb70207c43cb3277960b622f7c55c485232cb8ed0d0222a1612eb` | 1175 | mengzhong_stone_tomb_f3 |
| `44d3c4fb37cfbaecaaba4c3669a46ce33aafc54f051804680e5d9d2634ee5f2e` | 4858 | bich_orc_tomb_f2 |
| `45d31c33dca76cfa6aa41d298ff4f1c4c7261068f1623c86e63d9e05204cc909` | 16205 | bich_orc_tomb_f3 |
| `472c6b150c044d2de98f578c56e2704e4ec04ab49d1bd26358a7465d12c3bef7` | 13722 | bich_orc_tomb_f3 |
| `4d6b0a5d0d3e4bd1a621b79f51b3b9e43dea13aac7584f123d02e823a71137ee` | 4784 | bich_mine_f1, bich_mine_f2 |
| `4e88bb12821d425af8fdd1d91ee3c17dc8c83284a0d2368f362f05fbab0d41f7` | 9581 | mengzhong_stone_tomb_f3 |
| `56d48e8f4f1027913f2bd9384570bf0f8058e7d499bfae4d425cd825dd9bb394` | 3080 | mengzhong_stone_tomb_f3 |
| `583979ac957248a350b3dc2c223ada2237a86541d4e882484e0a3947bedb30e0` | 2094 | bich_orc_tomb_f1 |
| `5b3c87e986d13b814786b331241f75fbd8f7b70f58d0de07c44b336dfa2230f3` | 1703 | bich_mine_f1, bich_mine_f2 |
| `5bf5dcdc41f2c16e43fe8d1ec0356747139a1a891038ca138e5e0eec90ae8be2` | 2464 | bich_mine_f1, bich_mine_f2 |
| `5c4699637fa335ea9b3318a3f096b1dd07085d0d3186beb8f3e233b1a89d7cac` | 15069 | mengzhong_stone_tomb_f3 |
| `66fcdf7d270c4708468be889c3441f70075bb3d9189c989ede7ed343766cc2cf` | 1951 | mengzhong_stone_tomb_f3 |
| `695d3f3d79e9180783670715c3c7644b59cabac3ca03baf7e9cad261d3369376` | 3981 | bich_orc_tomb_f1, bich_orc_tomb_f2 |
| `699081ac37d5079961a4a24c5ae33239e74abcc64b0131ef7d25abd6b81d03f1` | 3956 | bich_orc_tomb_f3 |
| `6f0e424adf506d74c0e7a795503b26d648a3c7cf787a330508fe064a5da17099` | 2532 | mengzhong_stone_tomb_f4 |
| `6f36120935040401caefa7b762c1e6abaa9f08c9d4fdfd6858005b9297910741` | 418 | mengzhong_stone_tomb_f4 |
| `720472c72722826883346bda972219ade7555cd07c239b3e6e734e1f07a82d45` | 1087 | mengzhong_stone_tomb_f4 |
| `72e4dee49cf9d3460644bd72cf98bca6626bdc581c6248e0b3d6ca0c8bdcb247` | 1961 | bich_orc_tomb_f3 |
| `74bdcc0c0d2cc551da0ce5f592912cbd9bead003afd8f5adab44795029ecb0cd` | 30188 | mengzhong_stone_tomb_f3 |
| `7516b5c41b4525c3e4bfb169d134e94034b56f60f40058a659e44584a1b93ff2` | 5248 | bich_orc_tomb_f1, bich_orc_tomb_f2 |
| `7779cb1d12f6b9cb1e90d84f7010f5feeb8e5c5da55bb9889bb4e40cb40781b3` | 3004 | mengzhong_stone_tomb_f3 |
| `7ecd73ca1e3e743212ca194befaa922e49a04ded3d3eb136b33f4b319628ec4c` | 930 | mengzhong_stone_tomb_f4 |
| `83734ea60473c93c29f29b437f6c553c7f8c5bcacefc7123ea781be81d0ba3f1` | 2281 | bich_orc_tomb_f3 |
| `84c75686f4a51f09da36d6fd15fbf6f402f276356c7803871dfe5937467b10e7` | 2443 | mengzhong_stone_tomb_f4 |
| `8628f6c998fd8d0c4976d2401f13b694a5229f6af192004782b15e621cc5d80f` | 781 | mengzhong_stone_tomb_f1 |
| `89e70dc1714844846f1eeab2940a5890060d47597ca862ecf3d7f098e5214744` | 11497 | mengzhong_stone_tomb_f3 |
| `8b5dd2a4944351c403c33eb29b0e72c41ebc13c5319290af037a4802036e1799` | 12269 | mengzhong_stone_tomb_f1 |
| `8b75d8b9cf1cde5c0806bcd7b02ebc4e46520bd394a24c2a7e81e1a089e534cd` | 1775 | mengzhong_stone_tomb_f2, mengzhong_stone_tomb_f4 |
| `8bf95a710bf9b23d531bc63fd7c0d516c0501b73224e0d48cd90ca99ca1cd0f7` | 11283 | bich_mine_f1, bich_mine_f2 |
| `8e444018427df6019613dbdf8c2720bf70af82bb6186b2b8d89cc4223fbbcdd8` | 684 | bich_mine_f1, bich_mine_f2 |
| `90ad68239d993f58abeae8e70f19440b06523e47422dee0b43e3712a45114109` | 2169 | mengzhong_stone_tomb_f4 |
| `90d58e39c157a581a0fab1c00449ea6d5ecd56ae5608fd5a0d72b33b34a0900e` | 2290 | mengzhong_stone_tomb_f4 |
| `939574346399b48a275832b553b9282667f588f25922d91a651760ebf233f1a3` | 1646 | mengzhong_stone_tomb_f2, mengzhong_stone_tomb_f4 |
| `98850a620cc31e87447c81f95b06f1363f133f4b450547ed78b718813ed418d3` | 304 | bich_mine_f1, bich_mine_f2 |
| `9c2f6f87d4e26b74441a668d855bfccf7add6e23172ba85aae5ced62895c01a8` | 14257 | mengzhong_stone_tomb_f1 |
| `9d9f254c3b42aee6e538a7dc9686ae921566f643bb5b7fabd767c291251ffa1f` | 2116 | bich_mine_f1, bich_mine_f2 |
| `9e440abccce386b8d224329dc11be6eb6bb686ab5707cc3e3028adb5896dbc59` | 4628 | mengzhong_stone_tomb_f1 |
| `ab3a555777c2b0c5b9041054b9076f2530a6428ac42f6eb9a21f77e3ca48fa02` | 6723 | mengzhong_stone_tomb_f1 |
| `abb368ef492321be5a1fef848887b9ebc1b4506d8677fdb2e044797221503cc2` | 1356 | mengzhong_stone_tomb_f3 |
| `af396a86edecc0e150f33234cb3818a310abc1e6c18a19f66545dfa331736c8f` | 6036 | bich_orc_tomb_f3 |
| `af95e18053d23632c6b9853a9931ffd3762a15fa0080aef7b16d1f13ffe344f3` | 5149 | bich_orc_tomb_f3 |
| `b6eac0e33beceea402b03cd25b5975a0e5bbaa8790f0915a3662be512e8ba855` | 5855 | mengzhong_stone_tomb_f3 |
| `b865b4f1b631a02145e071d8003edb134438b571f80f2a7661eab6eba27639cb` | 2514 | mengzhong_stone_tomb_f3 |
| `b9f85a48f061a0cdfff11f0931b8241f54536a70d2a2e4b5df475b8f864c3f62` | 3230 | bich_orc_tomb_f3 |
| `bc305790be16bd5c3b5f1e033a0f0efc8d9014998eaf02ed4e5ca4fa98264729` | 4230 | mengzhong_stone_tomb_f4 |
| `bd6301e46e83b6b0de8031c67dec331ae5466d75d8552a041ef1297b66b4a51d` | 7060 | mengzhong_stone_tomb_f2 |
| `bdfcc479821e78e92435f59cec066bb8b1e6cdec94736aeb6237ec3791a589cd` | 8015 | mengzhong_stone_tomb_f2 |
| `bf14cbcdd7c37ea3fb9c268c8e1df8f5412a250c68e1b6ec0e71d79a6c5dd9a5` | 6351 | mengzhong_stone_tomb_f4 |
| `bff17b34c5b21827561d0c3bedb60f4ce715ec3ba2b4b40aa2d651e6bfce6d60` | 11326 | mengzhong_stone_tomb_f2 |
| `c58014e9abc225b09ae5c5ec419759af7639b4bf3e50769776a750921de8ff70` | 1347 | mengzhong_stone_tomb_f1 |
| `c640c8cc02bdc3fde79f809a145153f72206114b69dc64b2d72e4792c181e6af` | 5270 | mengzhong_stone_tomb_f3 |
| `d250e0b066fec182a501620cd2082cc7244e2465aaf2f7e0698c828ed65ef6af` | 2377 | bich_orc_tomb_f1, bich_orc_tomb_f2 |
| `d8374a79e82ad1fa0c0aa4ef6213d1235673de5d6691ebda2cd337afa1861ea9` | 11589 | mengzhong_stone_tomb_f2 |
| `dc368666a910ecc59eee0b9c5fc5fe9b3e2536009b6ddca7131b3c55b1a6fb0b` | 1926 | bich_orc_tomb_f2, bich_orc_tomb_f3 |
| `df9697c58ca5f799ec36d16cd8d1a7fa0acc85946d98413de5790a72ddb94fe3` | 10089 | mengzhong_stone_tomb_f3 |
| `edf898d419df7492848a14916214d0dcbe0a69fb5e9b394abfd2060dc33ee76a` | 9402 | mengzhong_stone_tomb_f4 |
| `f4c7b2db05541e475333c4eb53253f3847cd10b992d286eb1e459d7225d05175` | 44005 | mengzhong_stone_tomb_f3 |
| `f87ed85fa54ebdc4ec2a31230b9bc654482c6d3a4c04ada525898012ce199f82` | 2020 | mengzhong_stone_tomb_f3 |

历史manifest：`outputs/wall_perf/wall_store_gc_manifest.json`，文件时间2026-09-17，SHA-256 `58ED2369028A546D98DBCB5A88EDAFA39122771D81E49F5F6C8D4372E944444D`。67个候选在其中均有旧地图归属且referenced=true。

## 48个新增资源：全部保留

这些文件同时属于“新plan全局新增引用集合”和“本轮新增未跟踪PNG集合”，没有新增孤儿。同名.import均存在。完整精确文件名如下，公共目录同上：

- `02d311ce2571142f1e10ab642032ecdb90f0c1f9c73b82e4999ee6ca4db62b41.png`
- `050446cc1957b63c0710b4d06a4504d881b049696e55889b16f6b25ba79c7fe7.png`
- `077e945f189f1d692e3eb18b9b7060d9e6d0dab2abaf2858892c8957bb73f3d2.png`
- `098f5d8ab69812e0e92683c79754130a66ed9487b3df5bb43b7ebf51673546fd.png`
- `0aee2adb748b673eae97a36cb2d04fe1ca0bd0a86719b7c963f514fb4dce0fe6.png`
- `1afbb16df5106506108fb58af487e6d3dc2751eb94b3dc246f948832f81a0c16.png`
- `1eded6b4d2c2b8828cfb060ba1e5c0245ce62d1c86931b661bccc89077ed8469.png`
- `20066cd9a44a6c383f1d728a925acd60b8ec550e7fe74689a77a071a24e6dd0b.png`
- `2e1e5133135077bca70f4b7dc5278220e8929f93a1719140bcf0efd214c19682.png`
- `303a3aa5381fbca87a579122cf372a152dd5b969bedb6e5d3dd69cd35b0bf5b1.png`
- `4b1b242cd2ade189ec014473406c774b8db0fcc5b81203b62d3e5f73f9a3a6b9.png`
- `4d18345b442491cfa32dbf545f09610cccc4e488eb951ffe5db4a9b948c13ba2.png`
- `4f3e9c2bcdfbfe007050ea4443ec4ec46d612a617cddc084fa2acd2953daca68.png`
- `510f13032b59c462109fd7ffff68b448aad73a0e2eadc3c9f770d8616efbfab0.png`
- `51b3f913e42e46514448d8f08df330eb5385ce882eebd77d2b34778c21d6c710.png`
- `545b2c63df5450e78461a903cd9d23f6fbdf91d921d33eb94bcfadb403c123bd.png`
- `5bf7ceebb6286e7adb41f75273dc5476cba1484b5cb77f8f4eb22a82063aa6bd.png`
- `5fad80250a9eefbfa88b2a8af8aba18c7be48c7381c3b3d91030a2b4de5abb51.png`
- `69bbbe2c8214efc00cafb041d5a841e8fc9c5c4d0d0505b87f91eefde029a863.png`
- `6a6771dc2e61f871b0451e58b7cc8439456e82f25ea698afeca5a5419d262a8c.png`
- `6d30a8c1b227c627eb51639375a65354663084887fd1a3c9bb2b1573a85e5e34.png`
- `72e2850c2fe71cb53250355b40ebd4541e8e7f31c6e012b9c57c64a3819c5c2d.png`
- `796c5265217d0f1693a899b7b6ef46b752e508e253d9422a25d30c3bb3b483d4.png`
- `84121348f7fc96ee8ec9b5dd5c1138a2ac5968cbd725ed2d0deb6e7a152ac6b1.png`
- `87a0020b64226c351a9799baebb3d4b9afc206f49c8059de43f48b6b6ccdd15e.png`
- `8f68c3d06d3f13511773eac566eb2b2536649ea46accb61a4089fd9700f945a1.png`
- `a05cc5cc74b7a269c57b6f2feb27b58bc00326b8b23aacc81a9e7381c669db39.png`
- `ab42df8a6c4642893ea9230b886051b4939ab75543cbb49b652afcd8a058c9ef.png`
- `ad4ef1b04b9042e13d61ab5ace213231478f505c9f2c6f27f49609427d8a39b0.png`
- `b52d1e31ff8815185033b35a0bb0c785a9dc03d03568e546c3597011aa403020.png`
- `b72ee7c910e6c4f9a5633fb1b06fa5630a340d743fc5cc012e01c8c214cbc786.png`
- `bb01f710e27610e9d1ba2c992242cd465a85062d68a4a1d4bea015d89824d27e.png`
- `bc89a73bf61271478076b5715cba430cb3c101135a71cebcbdbdadc11b23dbb1.png`
- `bd9287ca4cb1f8774bc4ff7573327eb1d99d0bfa012fa5e38c31223eb44601f4.png`
- `c2cd37c10dacd3af9018c59929f138852e36c0bf3fa8c4d23c3fc2dcb0af093a.png`
- `c8318fcae85c7aa32db18faa64a4749a0cacf231409d5218049bc080faaff55f.png`
- `c910524f4310e14968d543d4db4b7a0b44889292bab3991def890fda4db1d1ac.png`
- `c9ac20ee4b618ac734872247032909dbff0441a72e5f4593467278475b258f32.png`
- `cb0bce9f7cf36fd27e8083bb689845252cbbf7c99f5219f9fd07ff9460251359.png`
- `cc2010db3f5adad2297c29e7bf344aea8978a7d4e402b5c9f771f6765b16638b.png`
- `cebb5b0fb3d7d9c0a6ce521d6c4da0a04ae010ccc1b88d09d633919303c1a5ae.png`
- `dfe7ad0978cf7412b2b5585a11f2e7765edfe6a4ea5454c65850cec7991fdc03.png`
- `e13c107e34b045a2bba7c77fb49af7c4df5d4c8993be69f216f377e297efc0a2.png`
- `e5385bed8398f15a7591e5e11000f5cc6b2b5b6f3528b98b4c8ac20509b72156.png`
- `f0a39aa7aba534a922cefdb965483c10a84d7f2f79603de98d61c9aeb1b3a6ca.png`
- `f3b0969f192c61592aced5cb75de307730a7745fb8e422f2d3624c1549c4aea2.png`
- `fc9bc353863349b390e387997f188737f7475018ef4c56dc391484dac24f6d86.png`
- `fffea5084c2a6c7c4cbfa2956d2ca7825950184cad6a1ee805a88502e4127903.png`

## Publisher提取后的重复实现审查

| 对象 | 证据 | 结论 |
| --- | --- | --- |
| 旧CLI `tools/map_editor/publish_wall_render_plans.gd` | 基线523行/11函数；当前46行，只有_init；3行preload共享服务，14行调用publish_map | 保留兼容构建入口，没有旧实现重复 |
| 新共享service | 490行，10个发布函数集中于此；publish_map及_store_png/_stage_plan_document/_commit_plan_document/_verify_candidate_plan在tools/map_editor和scripts/map_editor精确符号搜索中只有这一份 | 保留，为编辑器/CLI共同生产实现 |
| Runtime validator | 明确只做运行时结构与ResourceLoader验证，不重读源/派生PNG字节；publisher在发布前验证原始哈希与来源 | 职责不同，不因部分字段检查相似判为重复 |
| Compiler | 编译、materialize图像职责由publisher调用，publisher负责写出、验证和原子提交plan | 两层均保留 |
| GC工具 | 全局计划集合驱动审计和删除功能 | 本轮未执行，不能当可随意删除的冗余旧工具 |

当前源码原始字节SHA-256：

- `tools/map_editor/publish_wall_render_plans.gd`：`736E9C1FA5C2AA26D6AB4BBDCBA915E9FD7834DAA8BA9F6F3A3B99EBA95ADFB3`。
- `scripts/map_editor/map_editor_wall_render_publish_service.gd`：`75ABBD8773E7046F4B2BD110459CB36E0CC52808D353B7735849DE21571ACB00`。

## 需避免的误删入口与验证边界

`tools/wall_store_gc.gd:205`至211会写固定outputs/wall_perf/wall_store_gc_manifest.json，即使mode=audit也会覆盖该路径；256之后才区分是否删除，263至267在gc模式逐个删除未引用PNG/.import。因现有9月17日manifest是本次保留判断证据，不能把重新运行audit视为完全无写入的调查，也不能未经封存直接执行gc。

本报告未运行该工具。Godot资源解码/ResourceLoader及设备打包：NOT_RUN（遵守本次只读、禁止Godot要求）。已完成的PASS仅限原始文件哈希、PNG头尺寸、导入文本、正式plan集合和源码调用关系。后续生产发布/接受回滚策略由主控独立裁决。

## 最小复核命令

```powershell
git show b961cedff8040c9fc81534e094241ad9fa2330ad:assets/data/runtime/map_editor/wall_render_plans/bich_mine_f1.wall_render_plan.json
git diff --stat b961cedff8040c9fc81534e094241ad9fa2330ad -- assets/data/runtime/map_editor/wall_render_plans tools/map_editor/publish_wall_render_plans.gd
git ls-files --others --exclude-standard -- assets/data/runtime/map_editor/wall_render_store
rg -n 'wall_render_store|wall_render_plans|store_directory' scripts tools tests -g '*.gd'
rg -n 'func (_publish_map|publish_map|_store_png|_stage_plan_document|_commit_plan_document|_verify_candidate_plan)' tools/map_editor scripts/map_editor -g '*.gd'
```

本报告只提供可复核候选与保留理由，删除数量为0。
