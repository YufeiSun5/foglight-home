# 短途局内规则与固定步长战斗 API

产品方向、输入默认值与冲突约定统一见[可选航路短途母本](optional-route-combat.md)。本文只记录模块技术契约；验收状态由 [AI_BOARD](../../AI_BOARD.md) 统一维护。`tower` 是兼容模块名，不要求场景是实体塔楼。所有数值为原型校准值，不表示完成平衡或手感验收。

## 边界

- `src/domain/tower_run_rules.gd`：注入卡定义与局内状态，纯计算候选状态、抽样、属性和预览
- `data/tower_cards.json`：9张数据卡，效果白名单，不含任意脚本；应用可在建局前注入当前实际支持的卡子集
- `src/domain/combat_rules.gd`：固定60 Hz的一敌近战/远程蓄力遭遇规则；位置、朝向与视线由场景采样，规则不移动节点
- 两者没有文件、节点树、全局随机数或持久剧情写入口。调用者必须将返回候选状态原子提交到本局唯一写入口，并对重放结果避免重复发布事件
- 不把本局状态交给主线 `StateStore`，不增加主线存档schema。保存主线期间无需序列化本局。新局身份及应用会话代次由应用生成，不能反复复用旧ID

## 卡牌与局内 API

`validate_catalog(data) → {ok, cards}` 校验JSON解码值，返回以稳定ID索引的隔离副本。`fresh(run_id, epoch, seed_value, cards, stages=8) → {ok, state}` 创建临时局。默认8关只是可调函数默认值，24关是防止状态/账本无界增长的技术上限，不是已定地图或游戏关数。支持1关，最后一关不会产生无后续用途的抽卡。

局内状态：`run_id / epoch / catalog_hash / seed / rng_state / revision / phase / stage / max_stages / ranks / offer / selections / ledger / end_reason`，另有schema。建局为第1关 `stage_active`，无卡也有基础普攻、蓄力、防御和精准反斩。

`make_command(state, id, action, payload={}, source="player")` 构造值命令。`reduce(state, command, cards)` 返回 `{ok, state, result, events, replay}`，失败只返回 `{ok:false,error}`：

- `choose`：player来源，载荷 `{stage, card_id}`；只能选当前 `awaiting_choice` 提供的卡，一关一次
- `clear_stage`：application来源，载荷 `{stage}`；只能提交当前活动遭遇的胜利。还有下一关时stage递增，再提供至多3张卡；选卡后该关活动。末关结束为 `completed`
- `exit`：player来源，空载荷；`fail`：application来源，空载荷。结束时清掉 `ranks` 与 `offer`，不修改任何主线对象
- 有效卡不足3张时合法降量；没有卡时下一关直接活动，无必须点选的空面板

身份先校验，再查已提交命令账本，最后查当前修订。相同ID/相同指纹重试返回原 `result`、当前状态隔离副本及空 `events`；相同ID改载荷、旧局/旧代次、新ID旧修订被拒。每次新提交只推进一次revision；事件携带稳定event_id。账本最多49条，选择历史最多24条；不剪掉仍可能重试的账本。

抽样对有效卡ID排序，使用显式整数PRNG状态（Park–Miller，乘数48271、模2147483647），无放回采样，并通过拒绝采样消除取模偏差。相同种子、定义与命令序列产生相同状态；JSON数组顺序不影响结果。内容哈希锁定同一局的定义，不能中途热换数值。

`stats(state,cards) → {ok,stats}` 返回normal、charge、defense与effects四组派生值。`preview(state,card_id,cards)` 只预览当前提供卡，返回卡定义、当前/下一等级、`before / after / changes`；提交结果与预览相同。满级或最终派生值完全不变的卡都过滤。

蓄力模式为 `melee_charge / ranged_charge / chain_charge`。远程与链式形态本局互斥，选其一后过滤另一张，不依赖读取顺序静默覆盖。普通范围始终是近战；蓄力范围卡在已有远程形态时只适度延长有限射程。瞬凝卡与蓄力速率、链式可以组合；单张卡本身也有可预览的效果。

## 战斗 API

`Combat.fresh(run_id, stats) → {ok,state}` 复制已派生属性，建立玩家100HP/机关60HP的临时遭遇。当前 `SUPPORTED_CHARGE_MODES` 为 `melee_charge` 与 `ranged_charge`；链式仍返回 `unsupported_charge_mode`，不能静默当近战。应用在建局前过滤未接入模式卡，不向玩家发实际无效的卡。

`Combat.step(state, frame) → {ok,state,events,replay}` 每次代表一个1/60秒逻辑步，不接任意dt。frame精确包含：

- `run_id, tick`：tick必须为上次+1；同tick同帧重发无事件，相同tick改载荷拒绝；旧局/跳号拒绝
- `player_position:[x,z], player_facing:[x,z], enemy_position:[x,z]`：有限二维世界坐标，单位米，绝对值不超过100；方向需非零且接近单位长度。首帧初始化位置，随后每步玩家位移≤0.65米、敌人≤0.35米，仅防止异常样本，不替代物理碰撞
- `line_of_sight`：场景基于实际遮挡射线提供bool；false时双方不能隔墙命中，也不会新起敌方预警。该单敌接口没有多目标列表；弹体另走下一节的连续扫掠采样
- `attack_pressed / attack_released / defend_pressed / defend_released / dodge_pressed`：按键边沿bool，按住不重复提交press；规则仍防范重复press重开格挡窗
- `focused / paused / exit`：失焦、暂停或退出清掉挂起动作、蓄力与短无敌，不会恢复一记旧释放

本局临时Combat schema2（不改变主线存档）顶层有 `schema, run_id, tick, sim_tick, status, end_reason, stats, player, enemy, hitstop_ticks, hitstop_log, last_frame_hash, projectiles`。`tick`是帧命令序号；`sim_tick`只在有效活动步增长。内部上限36000帧用于限制单遭遇状态计数，达到时以time_limit结束。

player与enemy均公开 `hp, position, phase, phase_tick, phase_duration, attack_id`，可使用 `phase_tick/phase_duration` 做有上限的动画归一化。player另有朝向、蓄力/格挡时钟、输入锁存、已命中位与闪避/短攻速时钟。敌人公开 `reach_m, arc_degrees, telegraph_ticks, active_ticks, recovery_ticks, aim_direction`，预警和命中使用同一数值。

玩家phase：idle、windup、charge、release、guard、counter、dodge、hurt、dead。敌人phase：idle、telegraph、active、recovery、dead。逻辑事件有 `attack_started, enemy_telegraph, hit, blocked, counter, dodge_started, dodged, ended`；每个事件有event_id，命中有攻击来源/实例与目标。

## 当前冲突、命中和预算细节

- 攻击press开始准备；release按已累计逻辑tick决定普攻或蓄力；不先打普攻再偷偷追加蓄力。攻击press/release同帧作为一次短按；防御press/release同帧以解除为准
- 普攻、蓄力和反斩各有独立恢复时间；格挡或闪避可打断尚未释放的准备，不能直接取消已释放攻击的恢复。同帧释放与格挡/可用闪避冲突时，也先依据帧前准备状态处理取消，不能先释放再忽略取消；格挡优先于新攻击，闪避优先于新格挡
- 精准窗口从一次有效defend press开始，重复press/长按不刷新。窗口内正面受击发一次反斩；窗口外仍普通减伤。反斩不附带无敌，衍生反斩不递归触发自身
- 当前每个攻击实例只有一个有效命中检查tick；命中或挥空均消费该检查，不允许同次攻击持续贴住敌人反复结算。范围、正面弧与视线共同判断
- 敌人进入攻击范围外加0.10米余量内才起预警，较远时交给场景的idle追踪继续接近；预警时锁定攻击方向。展示层应在telegraph/active阶段停止敌人追踪移动；如想允许移动攻击，需要另改契约并验收
- 闪避事件只声明方向和时长，实际位移/墙阻挡交给场景。短无敌固定8tick、动作12tick、冷却48tick，不受卡叠加
- 临时反斩攻速与普攻卡合算后仍限2.7次/秒；近战普攻范围≤1.70米、蓄力≤2.00米。准备/恢复使用向上量化的整tick；最短蓄力0.06秒会量化为至少4tick
- hitstop仅视觉计时，逻辑、输入窗和敌人阶段照常推进。请求按最近整数tick量化；每攻击≤4tick，滑动60tick总预算≤7tick，同tick不累加剩余停顿
- 暂停/失焦取消当前敌方预警并重置为30tick空闲，恢复给短保护时间；这是当前可调整的恢复策略，可能被用于规避一次预警，不能宣称已完成战斗平衡
- effects中的粒子、发射器与尾迹是展示预算；纯规则不创建特效。展示层仍须独立验证预警无遮挡、攻击图形与判定一致、真实帧动画以及低特效/无闪烁选项

## 独立核验入口与未接入边界

两个测试脚本需实际Godot运行，不能以语法检查代替。为防止接触已有试玩槽，局内规则测试的存档夹具拒绝非独立HOME/XDG环境：

```sh
root=$(mktemp -d /tmp/foglight-tower-XXXXXX)
mkdir -p "$root"/{home,data,config,cache}
export HOME="$root/home" XDG_DATA_HOME="$root/data"
export XDG_CONFIG_HOME="$root/config" XDG_CACHE_HOME="$root/cache"
export FOGLIGHT_TOWER_TEST_ROOT="$root"
godot --headless --path . --script tests/domain/run_tower_rules.gd
godot --headless --path . --script tests/domain/run_combat_rules.gd
```

局内脚本检查真实既有Story/StateStore/FileSave API：建立含叙事选择、衣装和HRT事实的测试快照，写入隔离的正式槽/备份，结束短局后核对两文件字节和完整读档状态。它不读取用户现有主槽，也不表示整个场景往返已测。

战斗脚本检查tap/hold、防御方向与时机、多hit去重、固定逻辑时间、有限闪避、重放/旧帧、失焦/暂停/退出清理、视线/距离/朝向拒绝与临时属性。它不验证真实按键延迟、敌人移动、墙体射线正确性、真实命中视觉、GPU性能、动画或场景切换。

链斩的多目标搜索、目标消失、跨目标位移和可中断性仍待实现。远程已接连续飞行/墙阻挡与单敌命中，当前只有一个真实敌人，不能以此声称已测两目标穿透；GUI与手感仍独立验收。主线与应用/场景接线由集成层单独核验。

精准防御原型追加15tick（0.25秒）重新武装间隔：间隔内按防御仍可普通格挡，但不重开精准窗；快速松按会推后重新武装。长按和暂停恢复均不自动重开窗口。这是可调防输入抖动规则，不是耐力系统。

## 应用会话接线

`ExpeditionSession` 是一次可丢弃遭遇的唯一写入口，持有run、combat与卡定义隔离副本，不接收SavePort。命令附本局ID、generation及revision；非连续帧命令使用有限幂等账本。每次新遭遇推进generation，界面只读view。

暂停、失焦和衣柜开启须即时取消挂起输入，不等下一物理帧。包括取消在内的每个Combat.step结果走同一提交与终态收束：技术限时/失败不能只结束combat而让run停在stage_active。达到结束时发布一次返回主线事件，重复命令不再发。

当前卡池先完整校验类型和内容，再过滤未支持的形态卡。场景须先隐藏创建、验证必要角色/敌人资源，再发主线离场保存；失败仍保留可操作的主场景。活动期间主线菜单回调与非衣柜命令被隔离，玩家明确打开衣柜后的衣装变更仍由StateStore提交。

## 远程蓄力与场景扫掠

选取far_charge后只有充分蓄力的释放变成远程；普攻与反斩仍近战。释放时锁定朝向，active tick4在角色当时位置生成一发；出生帧没有飞行或命中，下一帧才需要碰撞采样。场景转身不改变弹体方向。弹体半径0.10米，当前敌人核心代理半径0.30米；飞行速度/射程/寿命由派生值限定，同时弹体最多4个。

`ExpeditionSession.projectile_sweeps()` 返回只读 `[{attack_id, from:[x,z], to:[x,z], radius_m}]`，终段按剩余射程/寿命裁短。展示适配器对与步行一致的真实矩形/圆形solid计算第一个接触比例；矩形圆角按圆形弹体精确膨胀，不能用方角扩大盒代替。帧附 `projectile_collisions:[{attack_id,wall_fraction:null或0..1}]`，每个既存弹体必须一项，不允许未知ID/重复/非有限比例。暂停、失焦或退出可省略采样并同步清空弹体。

规则对弹体与敌人上一帧→当前帧做相对运动扫掠，取目标与墙的先后；墙齐平优先。场景Vector2为float32，在已限定±100米坐标域只对该排序使用0.00005米容差，覆盖几项坐标ULP；不改变状态、射程或寿命校验的epsilon。误差带以外确实更早的目标仍可命中。

projectiles项有attack_id、source、origin、position、direction、age_ticks、travelled_m、hit_targets与hitstop_used_ticks。命中source=`player_projectile`、target=`enemy`（本遭遇稳定身份），同攻击对同身份只一次；不产生递归效果。`projectile_spawned/projectile_ended`携带生成及wall/range/lifetime/targets/canceled原因。应用退出也必须提交Combat退出、发取消事件并清空只读视图，再结束run，不能仅等场景queue_free。
