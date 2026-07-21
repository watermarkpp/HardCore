# MSE Stage 4 装饰物、障碍物与建筑实例语义验收报告

任务：`MSE-STAGE-4`  
结论：通过，允许进入 Stage 5。

## 首批正式对象素材

| 素材 | 类型 | 占地 | 默认碰撞 | 用途 |
|---|---|---:|---|---|
| 石环篝火 | large_prop | 2×2 | none | 装饰/后续光效 |
| 木制宝箱 | small_prop | 1×1 | preset | 可交互障碍物 |
| 哥特营帐 | building | 3×2 | solid_footprint | 建筑 |
| 铁匠炉 | building | 3×2 | solid_footprint | 建筑 |

四项均从用户提供的本地切分素材复制原图、去除绿幕、保持比例缩放、记录来源与输出哈希后进入正式素材目录；对象没有被压缩成64×32。

## 实例结构

每个对象实例具备：

```text
instance_id / asset_id / object_role / scene_intent / gameplay_role
placement_rule / tile / offset_px / layer / anchor / footprint
collision_policy / navigation_policy / occlusion / runtime_export
content_layer / rotation_deg / scale / flip_x / flip_y
```

默认写入 `personal_expansion`。地面、装饰、障碍物、建筑和交互物的语义不再依赖名称猜测。

## 编辑器行为

- 素材面板现可显示地面和对象缩略图。
- 选中地面时继续绘制地面；选中对象时点击画布创建实例。
- 对象Ghost和校验直接使用有效anchor、footprint和碰撞策略。
- 建筑/障碍物相交时拒绝放置。
- 服务层支持移动、复制、删除和保存重开；批量框选UI列入后续交互增强，不阻塞语义与数据闭环。

## 验收

- 篝火实例识别为 `decoration / visual_detail / none`。
- 营帐识别为 `building / landmark / solid_footprint`。
- 铁匠炉与营帐重叠放置被拒绝。
- 营帐移动后释放原占地；宝箱可复制、删除。
- 三个实例保存后重开数量与语义保持。
- 素材目录158项，错误0、警告0；MSE回归6/6通过。
- 未构建APK，未写入运行时目录。

## 下一阶段

`MSE-STAGE-5：地貌印章、手工碰撞与 Walkable 预览`

目标：建立山壁、洞壁、水岸等 terrain stamp 的语义与自动碰撞；支持矩形、椭圆和多边形手工碰撞；在编辑器中预览可走格，但继续不接入游戏运行时。
