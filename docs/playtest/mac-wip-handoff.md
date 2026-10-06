# 2026-10-06 Mac WIP 交接

状态：作者要求停止 Mac 开发，迁往云端；本版本仅保存工作，不是可试玩交付或美术达标版本。视觉目标已明确为《STAR OCEAN THE SECOND STORY R》重制版的 3D 环境与 2D 像素人物融合。当前盒体几何港口被作者否定，不得据此宣称质量通过。

## 现存实现

- 单个 Godot 4.6 工程；3D 网格水面、港口木板、灯塔、船舱、渡船、碰撞、灯光与固定正交相机。
- 原创代码像素绘制：64×96 全身，四方向待机/行走各4帧、互动3帧；160×192 半身，5表情及眨眼。属于初步资源，尚未逐动画验收；不要将其称为最终美术。
- StateStore 是剧情、衣装、恢复锚点的写入口；隔离快照、幂等账本、revision/session epoch/interaction generation 校验。
- 同步单槽 JSON 存档：校验和、递增写序号、临时文件校验、上一有效备份、原子替换与正式槽回读。包含故障注入入口，测试尚未实施。
- 75 个第一章与可选对话节点；引灯改为剧情协作演出。主菜单、对白、表达分支、摘要、回看、衣柜、保存/恢复、3段可选听潮路线代码已接入。
- 衣装2种上衣、4种配色、3种外套状态、5种下装，全部直接可用。全身/半身从同一 appearance 读取；实际同步还未 GUI 验证。

## 实际证据

已通过：

- HTTPS 正规克隆；基础 main SHA `4687ce329e68be9aed5e574a36e7b53d0438a6cb`，通过 Git 与 GitHub 连接器只读回读一致。
- 官方便携 Godot `4.6.stable.official.89cea1439` 版本命令与项目导入。
- 本机 Apple M2、macOS 27.0；图形窗口真实启动，日志为 `OpenGL API 4.1 Metal - 91.7 - Compatibility - Using Device: Apple - Apple M2`。
- 使用本机图形工具实际看到第一版占位3D场景、四个像素人物、中文场景标签、投影和船体。截图仅显示于本任务工具结果，未保存为本机 PNG；不声称已上传 Library。
- 相机入树顺序错误已修正；最终 UI/状态/存档/75对白节点接入后只运行了无图形启动，退出码0且无错误输出。
- Library 参考图通过正规 materialize 助手下载，本机可读并实际看图；四人从左至右星遥/砚舟/知微/祁岚，保留灰蓝/深靛/铜绿/铁锈红。原图没有当作精灵或动画提交。

未通过/未执行：

- 美术质量：作者明确否定首个占位画面。之后代码中的降雾、灯光和镜头调整尚未重启图形验收。
- 没有完整第一章实际试玩；没有分支全路线、双击、旧回调、故障注入、存档恢复、衣装立绘同步自动测试或完整图形验证。
- 最终对白/衣柜/存读档 UI 没有运行图形窗口验证。没有 Mac 导出包、Windows 原生测试、Steam 接入或发布。
- 无 Blender 安装或使用；没有 GLB 环境素材、音频、手柄/重绑定/完整可访问性设置。
- 旧技术母本与叙事文档中“解谜”和授权状态尚未全面修订；后续应依据本次委托明确要求更新，保留关键衣物/镜前戏及成年边界。

## 云端续作入口

先读 AGENTS、MEMORY、AI_BOARD 与技术/叙事母本，再读本交接。禁止继续在作者 Mac 运行开发；现有源码可移往云端，港口美术需重新设计。

根目录 `project.godot`，入口 `scenes/main.tscn`，装配 `src/bootstrap/main.gd`。数据可用 Python 标准库运行 `python3 tools/build_story.py` 重建。已运行的无图形检查为 `Godot --headless --path . --quit-after 3`，不能代替图形试玩。

中文字体为 Google Fonts 官方 Noto Sans SC，OFL 许可在 `assets/licenses/NotoSansSC-OFL.txt`。17 MiB 字体未入 Git；云端需要从官方地址取得 `https://raw.githubusercontent.com/google/fonts/main/ofl/notosanssc/NotoSansSC%5Bwght%5D.ttf`，保存为 `assets/fonts/NotoSansSC.ttf` 后导入。许可证没有授予原创源码或叙事的开源许可。

角色参考 Library ID：`libfile_2ada0608059c8191b6ff90863405569c`。云端应在自己的执行器通过当前 Library 正规 materialize 消费，不使用 Mac 路径当云端路径。
