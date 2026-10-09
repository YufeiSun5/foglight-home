---
name: tripo-game-assets
description: Plan and validate Tripo v3 image or multiview generation of a relightable game asset, then prepare it in Blender and verify it in Godot. Use for Tripo API parameters, costs, mesh/PBR processing, and this project's single workshop pilot.
---

# Tripo 游戏资产管线

官方接口核验日期：2026-10-09。本 skill 记录可复用知识，不证明本项目已调用 Tripo 或取得合格资产。

## 范围与执行门槛

先读项目 `AGENTS.md` 和 `AI_BOARD.md`。本项目仅做参考图中的单个机械工坊主屋及已有授权前景；不恢复旧项目，不把参考图贴成背景，不复制图中角色资产。早期本地试点未含付费 API；用户最新已请求 Tripo 单模型测试。新增测试应按最新用户授权核对上传范围、预算与安全接入，本文不自动授权收费。

实际调用前结合用户最新请求核对相应上传与 Tripo 生成范围，取得明确费用上限并完成安全接入。项目内早期试点说明不能否定用户后续明确授权。没有预算上限或安全认证则只做本地准备、请求计划和文档。凭据由用户通过受支持的安全方式设置；不索取/复述聊天密钥，不写进源码、skill、日志、命令行示例、交付包或截图。不自动充值，不批量试错，不循环提交收费任务。

## 按阶段阅读

- 安装与安全接入：[references/cli-access.md](references/cli-access.md)。API Key 可直接 Bearer 调用，CLI 浏览器设备授权只是可选路线，不强制再次登录。安装与建立持续访问仍须分别取得适用授权。

- 查请求契约、模型、异步状态和已知文档不一致：[references/api-v3.md](references/api-v3.md)。调用前重新核对所用端点与版本。
- 列账与审批：[references/billing.md](references/billing.md)。区分官网价目、计划估算、冻结额和已结算实际扣费。
- 从参考图到真实可重打光资产：[references/workshop-validation.md](references/workshop-validation.md)。参数预算不能替代 Blender 与 Godot 实测。

## 最小闭环

1. 检查输入像素与授权。提取主屋轮廓、相机、尺度和遮挡，标出背面为推断。先决定单图或多视图路径，不默认两条都收费跑。
2. 保存无凭据的请求计划：端点、锁定版本、输入哈希、参数、预估积分、批准上限、停止条件。首轮只提交获批的一条路径。
3. 记录创建返回的 task_id，查询同一任务至终态；网络不确定时先核实是否已经创建，禁止盲目重提。成功仅代表 API 完成，不代表游戏质量合格。
4. 原始结果保留不覆盖，记录文件哈希、实际收费字段与来源；失败候选同样保留诊断，不擅自追加收费重试。
5. Blender 检查/整理后导出独立网格、材质和简化碰撞；在实际 Godot 场景验收相机、人物尺度、重打光、LOD 与性能。提交原始结果、编辑源、导出物和实测证据，未测项明确写未测。
