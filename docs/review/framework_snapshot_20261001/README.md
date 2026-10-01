# HardCore 框架独立审查快照

这是第三树的施工中版本，用于独立源码审查；不是集成、发布或最终验收。

- 原施工HEAD：5d9ceb0121980ca9636d9d1cc2e19982949fbf63；审查分支：codex/framework-review-20261001。实际不可变提交由Git链接/外部SNAPSHOT_REF.json给出；施工HEAD与暂存区保留。
- 当前真实受测源码：3439文件，内容集合SHA256 5b864af12061f457648a84e9de8bafed888568097d87cf1b7fb92b01305f68fb。
- 引擎：4.7.stable.official.5b4e0cb0f；console引擎SHA256 d8055fb8c7e7f5010d7439ec69be051554055dae55a265f8647bd7301c34161c。引擎二进制不上传。
- 原始源码字节包：SOURCE_BYTES.zip，17123223字节，SHA256 27ee6cecfad2c7bccc69984fbacfe5425689a13e3643723502bed0445960402a；其中source/是完整受测文件字节，另有两轮native证据与九份历史范围证据。
- 当前类别范围：49项直接检查、27项生成器校验、21项唯一专项/回归PASS。首次组合20PASS/1FAIL；唯一后续文件差异为旧掉落保存fixture读取正式槽位，精确两项复测PASS。生产与引擎字节完全相同，原FAIL保留。每个native场景有真实退出状态、前后指纹和适用receipt。
- 新增32类别ID；旧1206实体不变，总1238。旧范围证据各有自己的历史指纹，不能用历史PASS覆盖本快照后续变化。
- 待办：INDEPENDENT_REVIEW_INCREMENT.md六项风险反例、P6组合和时效、旧价格候选/itemBps名称身份；R3性能仍FAIL。主树/APK/GPU/设备验收NOT_RUN。

仓库源码适合逐文件审查；Git既有换行规范可能将CRLF转LF。GIT_SOURCE_MAPPING.json逐文件证明审查blob与真实受测字节完全相同或仅CRLF/LF规范化。若需要按原生指纹重新运行，先在独立候选目录展开SOURCE_BYTES.zip的source/恢复原始字节，并按TESTED_SOURCE_MANIFEST.json复核；不得在主树/现有施工树恢复。source/不含本地Godot工具、素材联接、用户存档、.godot缓存、密钥或glm配置。

精确取样范围为测试指纹定义的scripts/tests/scenes/assets/data/shaders以及项目、runner、validator/receipt脚本，另加正式生成器/工具、AGENTS和相关状态文档。其他dirty包括生成.translation、无关untracked和机器配置均不收录。测试原始证据保留原字节。此分支只固定审查，不接入codex/integration，也不修改v97。
