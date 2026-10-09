# 独立机械工坊主屋：多视图设计合同 v1.1（控制体冻结版）

日期：2026-10-09。状态：**控制体几何冻结为 v1.1，五个同模型正交视图已检查；仍为设计尺寸，不是参考图测量值或用户已确认尺寸。**

唯一有效的本轮几何基准为本目录 `workshop_multiview_control.blend` 与 `build_control.py`：主脊 Z=5.55m、烟囱帽顶 Z=7.15m。本文件与 `dimension-check.json` 对齐。早期 imagegen 使用的主脊5.2m/帽顶6.3m等试拟值作废，不与此版并存。生成四视图 `exec-4ddcf043-e760-4b76-b315-5983ff89753d.png`、`exec-828cf913-04df-4acc-89ce-8153a2a71449.png` 均仅保留为美术探索，未通过严格多视图几何输入验收；不得直接用作已合格重建输入。高质量单张概念只保留为材质/风格目标。

## 1. 输入、观察与范围

已实际检查像素的输入：
- 原机械工坊参考：`/workspace/scratch/b756fd48b088/town-reference-20261009/ChatGPT 圖片 2026年10月9日 下午09_48_25-4.png`
- 新单屋概念：`/workspace/scratch/b756fd48b088/generated_images/exec-ed5b752d-cdad-477a-950d-1239588bf52d.png`

原图可辨认：青绿色弯曲双坡金属屋面，长屋脊，近侧一个老虎窗；参考左侧山墙有深色木构和浅色填充；山墙附近有浅石烟囱和黑色开口帽。原图正面大量区域被棚布、货物、木构、机械遮挡，不能从原图确定一扇完整门或所有底层开口。新概念提供了封闭正面、单门和右窗，是再设计，不是原图逐像素复原。

只保留独立主屋、基础、门前两级踏步、主屋木构、一个老虎窗、一个烟囱。不含低棚、棚布、侧翼、外挂小屋面、机械、齿轮、水车、人物、工具架、货物、灯笼、招牌、地景和植被。**新概念左外缘的小片低斜屋面是排除项，不得沿用成附属体或误认成后檐。**

不可见的背面与右山墙均属推断设计，不能称为从原图还原。新概念的装饰、门窗位置同样是暂定设计选择。此文档不调用服务、不提交生成任务、不修改现有工坊场景或资产。

## 2. 唯一坐标、面名和投影

使用设计坐标，单位 m，Z 向上。建筑原点位于主屋底面中心的地面；长轴 X，深度 Y。这不要求改变游戏引擎的轴系，导入时统一转换。

| 唯一面名 | 法向/位置 | 相机位置及方向 | 该正交图的画面向右 |
|---|---|---|---|
| FRONT 正面 | Y=-2.10，带主门的长檐面 | 从 -Y 看向 +Y | +X |
| BACK 背面 | Y=+2.10，另一个长檐面 | 从 +Y 看向 -Y | -X |
| LEFT 左面 | X=-3.00，参考可见山墙 | 从 -X 看向 +X | -Y（正面侧在画面右边） |
| RIGHT 右面 | X=+3.00，另一山墙 | 从 +X 看向 -X | +Y（正面侧在画面左边） |
| TOP 顶面 | +Z | 从 +Z 看向 -Z，画面上方为 +Y | +X |

所有正/背/左/右均指对象坐标，绝不随观察者或图片镜像而改名。“正面”不是山墙。输出按 FRONT、LEFT、BACK、RIGHT、TOP 唯一命名，不使用含糊的“侧面1/侧面2”。另外保留 FRONT-LEFT 与 BACK-RIGHT 三分之四视角，仅用于核对遮挡关系。

## 3. 暂定可执行尺寸

这些数值是建立同一个对象的约束，不是从画面推算的精确尺寸。后续若更改一项，必须整套视图同步修订。

| 部件 | 尺寸/位置 |
|---|---|
| 主墙矩形平面 | X 长 6.00；Y 深 4.20；X∈[-3,3]、Y∈[-2.1,2.1] |
| 地面/石基础 | 地面 Z=0；连续石基顶 Z=0.45；石基外缘 X±3.10、Y±2.20 |
| 立墙 | 木构从 Z=0.45 至檐部 Z=3.55；侧山墙继续填充至曲线屋面 |
| 主屋屋面 | X∈[-3.35,3.35]，Y∈[-2.45,2.45]；侧端悬挑0.35，前后悬挑0.35 |
| 屋脊 | X 长轴、Y=0、Z=5.55；除轻微材质磨损，整条脊不扭转、不横向弯、不纵向塌陷 |
| 屋面厚度 | 0.12；金属板与铆钉为表面细节，不改变主轮廓 |
| 主门 D1 | 仅 FRONT；中心 X=-0.90；宽1.15；底 Z=0.45、顶 Z=2.85；深棕竖木板、黑铁横铰链、一个环形把手 |
| 前窗 W1 | 仅 FRONT；中心 X=+1.65；宽0.85；底 Z=1.30、顶 Z=2.35；深木框、十字窗棂四格 |
| 背窗 W2（推断） | 仅 BACK；中心 X=0；与 W1 同宽高和离地高度；背面无门 |
| 老虎窗 DW1 | 仅 FRONT 屋坡；中心 X=+0.65；墙体宽1.05（X=0.125..1.175），小屋面含悬挑宽1.19（X=0.055..1.245）；前立面 Y=-1.95；前立面底 Z=4.20；小双坡顶峰 Z=5.40；墙体延伸至 Y=-0.80，小屋面Y=-2.02..-0.76并与主坡相交；小屋面板厚0.07，内部填充低于屋面以避免共面穿插 |
| 老虎窗玻璃 | 宽0.60、高0.65；中心 X=+0.65、Z=4.65；一个十字四格窗；主屋另一坡没有老虎窗 |
| 烟囱 C1 | 中心 X=-1.65、Y=+0.45；石砌截面0.60×0.60；石身至 Z=6.70，开口黑铁帽顶 Z=7.15；穿过后坡靠近屋脊，根部含小灰石泛水座 |
| 两级门阶 | 对齐门中心 X=-0.90；宽1.55；沿 -Y 向外0.70；两级高度各0.225；不是大平台 |

墙体浅暖米灰抹灰，深棕厚木柱、横梁、斜撑；金属连接片深灰。基础不规则灰石但轮廓连续。屋面青铜绿/蓝绿板材，长板从屋脊顺坡至檐口，细铆钉和少量磨损。不得用夸张凹凸材质替代屋顶真实曲率。

前后长墙主立柱共享 X=-3.00、-1.60、+0.40、+3.00 的结构节奏；左右山墙共享 Y=-2.10、0、+2.10 的结构节奏。门窗所在格内不允许斜撑穿过洞口。背面木构是这一框架的推断延续，不额外添加门、烟囱或屋檐。

## 4. 屋脊与屋面曲线合同

**弯的是山墙方向的屋面横截面，不是长屋脊在平面或立面里的走向。**

可执行主屋面上表面基准：

`z(y) = 3.55 + 2.00 × [1 - (|y| / 2.45)^1.70]`，`|y|≤2.45`，沿 X 方向等截面延伸。

该横截面在脊附近圆缓，向檐部逐渐变陡，具有参考的柔和弧形双坡轮廓。不得变成普通直线A字屋顶、平顶、尖塔、桶形整半圆、四坡屋顶、反翘中式飞檐或三段折线棚顶。主脊高度、檐口高度、左右曲线在两张山墙正交图必须一致。烟囱和老虎窗不改变主屋脊基准。

该数学横截面是供后续几何落地的设计基准。生成图只能近似表现；不得因单张生成图画错而分别改动每个视角的几何。

## 5. 开口和附属物跨视图对应

| ID | 全对象数量 | 正面 | 背面 | 左面 | 右面 | 顶面 |
|---|---:|---|---|---|---|---|
| D1 主门 | 1 | 画面偏左 X=-0.90 | 无 | 不可画成山墙门 | 不可画成山墙门 | 前沿偏左，对齐两级踏步 |
| W1 前窗 | 1 | 画面右侧 X=+1.65 | 无 | 不可复制 | 不可复制 | 前墙开口位置保留 |
| W2 背窗 | 1 | 无 | 画面居中，推断 | 不可复制 | 不可复制 | 后墙居中 |
| DW1 老虎窗 | 1 | 画面稍偏右 X=+0.65 | 被主坡遮挡时不显示前窗，不补一个后窗 | 位于画面右侧的前屋坡 | 位于画面左侧的前屋坡 | 位于前半坡 Y<0、X>0 |
| C1 烟囱 | 1 | 画面偏左 X=-1.65 | 画面偏右（因为背视横轴为-X） | 靠画面左侧的后半坡 | 靠画面右侧的后半坡 | 位于 X<0、Y>0 |

遮挡可能只显示局部，不能为了让每张图“完整好看”移动部件。烟囱应有相同高度、石身比例和四立柱开口帽；不会随视角跳到另一屋坡。后视可能不见前坡老虎窗，属于正确遮挡，不能因此把对象数量改为零或二。

## 6. 多视图制作与检查流程

1. 先以这份尺寸合同锁定形体和命名；新概念作为材质/风格参考，不作为未知背面的事实依据。
2. 先产生同一个对象的 FRONT、LEFT、BACK、RIGHT 正交视图；等比例、相同相机距离等效尺度、纯浅灰背景、柔和中性照明、无透视、无地面透视网格、主体完整留白。各视图中心可平移对齐，不允许各自独立缩放。
3. TOP 和两张三分之四视图用于消除烟囱所在坡、老虎窗深度、悬挑和左右手性的歧义；三视图不能完整证明背面一致。
4. 设计审查板可拼版展示，但送入多图重建时须使用裁出的独立干净图。标签和尺寸箭头留在审查板，不烧进输入主体图。是否支持多图、图数与视角顺序必须以届时实际工具能力为准，本文不保证服务支持。
5. 逐视图核对上表。生成图是设计候选；在通过以下检查前，不提交付费/积分重建，不替换游戏资产。

### 必须通过的几何/一致性检查

- 同一尺度下四个立面的地面线、基础顶、前后檐口、主脊、烟囱帽顶应对齐。容许可视草图轮廓约3%图像高度差；超过则退回。最终几何遵守数字合同而非图像误差。
- FRONT/BACK 主屋宽度相同；LEFT/RIGHT 深度相同。屋面投影长6.70、深4.90；不同面宽深不能互换。
- FRONT 的 D1 在左、W1 在右、DW1 稍右、C1 偏左；BACK 的 C1 必须偏画面右。反向即镜像错误。
- LEFT/RIGHT 都是同样曲线山墙，无门无窗；不得把 FRONT 误画成一个开门山墙。
- 只允许 D1、W1、W2、DW1、C1 对应的五类固定对象，按表计数；禁止补成对烟囱/对称老虎窗/第二扇门。
- 单屋体块必须是一个矩形主墙体及一个弧形双坡主屋顶；不得残留左侧低棚、后侧小屋面、棚布或外接工作间。
- 所有视图中的屋脊必须沿同一长轴；不得出现脊线方向转90度、主坡陡缓互换、山墙换面。
- 两侧屋坡为同一横截面的镜像；屋脊长向不得在一张图里下垂、另一张里平直。材料做旧不能伪装成几何形变。
- 看不见的部件按遮挡处理，不移动、不复制、不凭空补全。三分之四视图必须能由四立面和顶面同时解释。
- 背面 W2 及背/右木构明确保留“推断设计”标签在配套说明中；不可向用户声称其为参考已有细节。

### 冲突处理顺序

对象数量/方位合同 > 主体尺寸与屋面曲线 > 可见参考主轮廓 > 新概念材质风格 > 单张生成图装饰细节。若生成图违反数量、镜像、屋脊或附属棚排除规则，判该图不合格，重新生成/修订该图；不要修改合同来迁就互相矛盾的候选。若用户改设计，升级文档版本并同步全套。

## 7. 可直接用于 imagegen 的固定对象说明

Produce a consistent multi-view reference of ONE standalone stylized medieval timber-frame workshop house. The same immutable object appears in every view. Rectangular main wall footprint 6.0 m along X by 4.2 m along Y; warm cream plaster, heavy dark brown oak beams and braces, dark iron joints, continuous gray stone foundation 0.45 m high. FRONT is the long eave wall at Y=-2.1, never a gable. LEFT is the gable at X=-3.0. Main teal patinated metal roof is an extruded gently curved double-pitched roof: straight lengthwise ridge at Y=0, height5.55 m, eaves3.55 m, roof footprint6.70×4.90 m. Curvature occurs only in the cross-section, never by bending or twisting the lengthwise ridge. One front door centered X=-0.90, one four-pane front window centered X=+1.65. One four-pane dormer ONLY on the FRONT slope, centered X=+0.65, its face at Y=-1.95. One pale stone chimney with open black iron cap centered X=-1.65, Y=+0.45 on the BACK slope near ridge, top7.15 m. Back wall is a proposed unseen design with one centered small four-pane window and no door. Both gable end walls have no windows or doors. Two small stone steps only at the front door. NO side shed, NO lean-to roof, NO small protruding roof on left, NO canopy, NO machines, NO waterwheel, NO people, NO props, NO landscape. Show true orthographic FRONT, LEFT, BACK, RIGHT views at identical scale with aligned ground and height levels; neutral pale-gray background, soft neutral lighting, generous margins. Back-view chimney is on image RIGHT; front-view chimney is image LEFT. Left-view FRONT roof slope is on image RIGHT; right-view FRONT slope is image LEFT. Do not mirror, add, delete, or reposition any architectural element between views. Use the supplied concept only for materials and stylization; remove its leftover low roof projection.
