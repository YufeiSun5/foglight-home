# 星遥 v2 运行时人物与衣柜

日期：2026-10-06（UTC）。原创虚构成年人岑星遥26岁。v1程序像素版未获视觉认可；本版本全部由内置 image_gen 新绘/编辑，不以v1回退或程序梯形覆盖代替衣装。

## 资产与动作接口

稳定目录：`cen_xingyao/outfits/<bottom_id>/`，其中 bottom_id 为 `trousers`、`culottes`、`long_skirt`、`short_skirt`。

每套包含：

- `walk_down.png`、`walk_right.png`、`walk_up.png`：480×80，6列，每帧80×80，建议8fps
- `idle.png`：160×320，2列4行；行依次down、left、right、up；列为睁眼中性与闭眼/局部放松。建议中性2.6秒、眨眼0.12秒，不要两帧等时循环成频繁抽动
- 各图同名 `_topmask.png`：RGBA二值alpha，与主图尺寸、UV及帧排布完全对应
- `manifest.json`：该套衣装的机器可读接口

有效人物高度约64px，帧内脚底锚点为(40,75)。单帧文件也保留供排查，运行入口优先使用图集。

上衣配色统一 `coat_color`：0 blue、1 indigo、2 green、3 cream，四种下装与四种配色组成16套组合。颜色不增加游戏能力、好感或身体评分。

## 已知限制

- 本轮实绘三方向walk；向左暂由right水平翻转，图袋、发饰及其他不对称细节会随之镜像。这是第一版限制，不称为已独立绘制的四向walk
- 四向idle是独立视图。背面看不到眨眼，第二态只提供手指、肩部等局部变化
- 步态整体较轻快，右行passing pose抬膝较高；长裙自然遮住部分膝部，但可见鞋跟交换和相应裙褶变化。场景运动速度应与8fps附近步频协调
- 衣装由逐张生成式编辑完成，维持相同设计和主要动作，仍可能有个别1px装饰/折褶差异。并非手绘逐像素完全锁定的商业最终美术
- 已实际查看原生64px人物的放大近邻预览和项目960×540实机截图；文件检查不代替最终16组合的场景内换色、遮挡、镜像和性能验收

## 配色材质

- `palette_world.gdshader`：spatial、unshaded、Y轴billboard；保留 `character_texture`、`top_mask`、`coat_color`、`recolor_enabled`、`billboard_enabled`。`minimum_light`默认0，不用额外发光洗淡像素
- `palette_preview.gdshader`：canvas_item，仅用于衣柜全身像；`coat_color`、`top_mask`、`recolor_enabled`、`use_top_mask`接口相同，默认启用mask
- `palette_shared.gdshaderinc`：两材质共用同一源/目标色阶，避免world与衣柜预览自行漂移
- 高精半身像仍用原portrait色域材质；本v2预览材质不能拿来直接染半身像

代表性源蓝RGB暗/中/亮：28,37,70 / 92,109,156 / 128,148,192。靛目标：32,38,51 / 86,100,125 / 165,177,186；铜绿目标：38,59,54 / 120,151,131 / 206,211,179；暖白目标：104,94,85 / 208,195,166 / 255,245,223。原蓝保持原像素。其余颜色按同一色阶比值保留织物明暗。

遮罩是与该图集逐像素对齐的确定性源蓝布色域+躯干分区提取，排除头部/皮肤/暖金/皮革及下装主体。背面有更低的起始区域，避免染到发间蓝带。腰线下方采用更严格亮度与色相选择，避免把深靛下装染色。不是把整个角色乘以染色色值。极暗衣缘与中性高光保留原样，最终视觉覆盖仍应在四颜色实机遍历中复核。

## 来源、重建与验收记录

- 人物身份/服装识别来自作者认可的原创四人概念设定；本轮是新的runtime美术，不裁概念图当动画
- SO2R官方截图仅用作比例、像素簇及2D/3D组合的视觉研究，没有将其像素用于本资产；官方截图已移出工程源目录，不能收入发行包
- `art_source/characters_v2/wardrobe_generation_record.json`记录各次生成/定点修正prompt与真实输出回执
- `package_outfits.py`仅做技术裁切、近邻缩放、头部注册、图集打包与mask提取，不绘制或覆盖人物。生成式美术编辑均使用image_gen
- `*_walk_review_4x.png`与`*_idle_review_4x.png`是实际runtime像素的近邻放大检查图
- `wardrobe_validation.json`记录16图集及16mask尺寸、alpha与暖色误染检查、SHA-256。先前已接入的15个候选文件保持原哈希，可回退比较

本清单不授予开源许可证、不保证独占版权或第三方权利清除，不表示Steam/Windows发行审核完成。未添加LICENSE；远端提交与运行验收状态见项目AI_BOARD。
