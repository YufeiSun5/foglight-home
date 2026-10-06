# 协作入口

## 阅读顺序与唯一来源

1. [README](README.md) 了解项目，再读 [AI_BOARD](AI_BOARD.md) 确认当前阶段、授权范围和下一步
2. [MEMORY](MEMORY.md) 只记录已确认决定和变更原因；活动任务、阻塞和验收状态只维护在 AI_BOARD
3. 任何改动前必读 [执行与画面硬约束](.ai/instructions/execution-and-visual-constraints.md)，这是云端执行、画风、玩法及衣装规则的唯一母本；[技术母本](.ai/docs/architecture.md) 定义实现契约，[核验约定](.ai/instructions/verification.md) 定义检查方法
4. 涉及叙事时读 [纲要](docs/narrative/outline.md)、[人物](docs/narrative/characters.md)、[首章台本](docs/narrative/scripts/chapter-01.md) 与 [关键场景](docs/narrative/scripts/key-scenes.md)，按各文件职责维护，避免重复全文

## 工作方式

作者已授权持续实施至可交付试玩版、提交和推送，并要求小步提交、频繁合并；无需重复申请初始化或实现批准。全部开发、构建、运行、调试与测试只在 dot 云端电脑进行，不依赖用户 Mac。具体边界以硬约束母本为准；超出已授权范围时再确认，不自行改剧情。

计划路径不等于已存在的实现，不创建无用途的空目录，不假设计划脚本已经存在；当前可核实进展见 AI_BOARD。采用单 Godot 工程的模块化单体；依赖边界、唯一状态写入口与存档流程以技术母本为准。

保护现实经历和私人原始材料，只公开获准的原创内容与项目实现。不得提交凭据、私人记录、源 DOCX/PDF、大型二进制文件或临时审计产物；不得擅加 LICENSE、付费服务、外部运行依赖或发布承诺。

## 交付要求

报告实际变更、已通过/失败/未执行/受阻的检查及证据、剩余风险和必要下一步；不得把文档检查、版本命令或无图形测试当成游戏运行、GPU 画面或 Windows 导出通过。涉及远端提交时回读目标分支、提交和每个文件，核对 UTF-8 字节与哈希后再声称完成。

