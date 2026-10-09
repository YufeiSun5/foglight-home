# 预算、计费与真实账单

核验日期：2026-10-09。来源：[官方计费说明](https://developers.tripo3d.ai/zh/docs/billing)、[官方价目](https://developers.tripo3d.ai/zh/pricing)、[账户](https://developers.tripo3d.ai/zh/docs/account)。执行当天重查，以下不是费用授权，也不是本项目实测。

## 官网所示价目快照

1 credit = USD 0.01。此次可直接核实的 H 系列默认价目：

| 操作 | credits |
| --- | ---: |
| 单图或多视图→3D，无贴图 | 20 |
| 单图或多视图→3D，标准贴图 | 30 |
| 单图→多视图图像 | 10 |
| 独立贴图 fast / standard / detailed / extreme | 10 / 10 / 20 / 30 |
| 重拓扑 v1.0 / v2.0 | 10 / 30 |
| 基础 / 高级格式转换 | 5 / 10 |

H 生成的附加价：高清贴图 +10，8K +20，超清几何 +20，quad +5，smart low poly +10，分部件 +20。并非任意组合都合法；先看接口兼容性。P 系列价目需切换对应标签再次核实；不得把这里的 H 价目套到 P1/P2。

转换以下任一非默认设置触发高级价：quad、face_limit、flatten_bottom、flatten_bottom_threshold、texture_size、texture_format、pivot_to_center_bottom、scale_factor。即使只是改变导出轴心或贴图尺寸，也可能收费升级。能在 Blender 合法本地完成时先比较是否确需调用。

估算方法为逐个获批任务相加，附加选项分列。每次成功的候选即使美术验收失败仍可能计费。不得把官网 JSON 样例中的 100 credits、余额 10000 等当本次报价或真实账户状态；不要臆测套餐、税费、账户折扣或免费额度。

## 冻结与实际扣费

- 创建任务冻结对应积分；success 后转为消耗；官方说明 failed/cancelled 退回冻结额。不要自行扩展到其他状态或承诺到账时间。
- `GET /v3/account/balance` 的 data.balance 是可用余额，data.frozen 是进行中冻结额；冻结额不能再从 balance 二次扣除。
- `GET /v3/account/usage` 的逐任务 credits_consumed 是实际消耗记录；任务查询也可能返回同名可选字段。按 task_id 对账，字段缺失写“未取得”，不要补成 0。
- 记录请求前后余额与冻结额只是辅助；账户可能有并行任务，余额差不能直接认作单任务费用。

## 每轮审计与停止条件

记录：批准上限与币种/积分、端点、参数、版本、task_id、开始/结束时间、终态、真实 credits_consumed、用量核对时间、输出本地哈希、是否验收。不得保存 Authorization 或预签名上传链接。

未有预算/安全认证则停在计划。余额不足、预计超过上限、未知加价项、授权变更、输入或生成质量不合格且需再收费时，先问用户。API 超时、HTTP 错误或 lost response 不自动触发新收费任务；先查已知 task_id 与用量。查询重试和创建新任务是两回事。默认不充值、不改变套餐、不自动连跑候选。
