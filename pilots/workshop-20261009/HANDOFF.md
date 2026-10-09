# 工坊试点：云端 → Mac 交接

冻结日期：2026-10-09。独立交接分支 `handoff/workshop-pilot-20261009`，基于 `main` 精确提交 `5aad11eb90366692862ba9c11659b193faa5d48e`。本目录与旧生产工程隔离；不合并 main、不替换旧工程、不发布安装包。

## 已完成、当前中断位置

- 新建可编辑工坊及近景；当前手工建模候选为 material-r3 / refined3。源代码、程序纹理、历史失败候选、当前三个 GLB 和角色依赖保全。
- `evidence/material-r3/engine_frame.png` 是真实 Godot 4.6.3 Compatibility GUI 运行画面，1672×941；不是概念图。原环境为软件渲染，4× MSAA、双倍每轴内部 3D 分辨率。不等于 Mac/Windows GPU 性能验收。
- `references/town/` 为 9 张用户提供的外部/地图参考原 PNG；`references/interior/` 为 6 张室内原 PNG。未重采样，逐文件 SHA-256 见 `SHA256SUMS.txt`。
- `art_source/references/workshop_single_asset_input_concept.png` 为 2D 概念输入；`art_source/tripo_workshop/` 的五正交图来自同一个自建 Blender 控制体。两者都不是 Tripo 输出，均未接入当前运行场景。
- 源自 Source-M3（153 个工程文件）及 Runtime-M2 归档。两份原归档清单保存在 `docs/*-archive-manifest.json`；相同文件保留 Source-M3 字节，仅从 Runtime-M2 补齐缺失依赖。原归档哈希见 `docs/archive-sha256.txt`。

## 未完成与禁止误认

旧 r24 草地/场景源已丢失，本工程是新试点，不能称恢复。当前画面仍有简化屋顶、地面/岩石、树冠及背景层次，未达到参考图高质量表面和灯光，也非已获认可最终美术。未完成完整可玩整合、全地图性能、Mac GUI、Windows 实机验收。

Tripo：实际 API 调用 0，实际 API 花费 0；用户已批准单模型最多 100 API 积分 / $1，但安全认证未完成，尚未提交任务。Mac 迁移不解除凭据限制。下一步是安全认证后，核对上传范围与官方版本/费用，冻结一条单模型输入路线，生成一次，再与手工 r3 对照。不得把控制体视图当实生成结果，不自动充值或批量重试。已有聊天密钥不得搜取、复制、写入源码/命令/日志。官方接口、可选 CLI 设备授权、计费和验收流程见 `.agents/skills/tripo-game-assets/`。

## Mac 拉取与启动

在单独目录克隆，避免覆盖现有工作区：

```sh
git clone --branch handoff/workshop-pilot-20261009 --single-branch https://github.com/YufeiSun5/foglight-home.git foglight-workshop-handoff
cd foglight-workshop-handoff/pilots/workshop-20261009
shasum -a 256 -c SHA256SUMS.txt
python3 restore-assets.py
GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot
"$GODOT_BIN" --headless --editor --path . --import --quit
"$GODOT_BIN" --path . --rendering-method gl_compatibility --resolution 1672x941 -- --out=res://.qa/mac-first-run
```

请使用已安装 Godot 4.6.3 或先核对兼容版本。Mac 尚未执行以上命令；路径按实际安装调整。首次 GUI 帧须和保全证据比较，不把无头 import 通过当画面通过。当前 GLB 已齐全，启动不需要 Blender 重建。

## 完整资产重建（原云端方式）

原源保持字节，脚本仍有 `/workspace/shared/foglight-town-pilot-20261009`、`/usr/local/bin/godot` 和 Linux `flock`，不能直接声称 Mac 一键重建。Mac 后续应先把根路径改为相对工程路径，并使用适用的串行构建锁；改动另提交、重跑检查。

云端原根路径、Blender 4.3.2、Python（含原环境依赖）下：

```sh
cd /workspace/shared/foglight-town-pilot-20261009
bash rebuild-assets.sh
godot --headless --editor --path . --import --quit
bash run-pilot.sh material-r3-rebuild
```

生成器已分别成功运行；完整干净解包重建尚未重跑。已有检查与边界见 `docs/CHECKPOINT_VALIDATION.json`、`docs/REPRODUCE.md`。静态依赖及清单检查不替代完整重建。

## 权利、发布与隐私

保留角色出处、固定提交和原权利说明于 `assets/character/`。CC0 仅适用于对应候选材料许可，候选下载失败且未使用；不把它当项目许可证。参考 PNG 为用户授权本次上传的视觉参考，不作为背景纹理，不复制其角色/游戏资产。没有为整个项目新增开源许可，也不作第三方权利清除保证。仓库为公开仓库。

排除缓存、凭据、个人笔记、旧备份 ZIP、原 .git 和未经筛查日志；只保留指定 GUI PNG 和有用的源/验证记录。此分支不改变 main 的既有文件与生产入口。项目 AGENTS/AI_BOARD 的早期“禁止上传”是历史试点边界，本次用户明确授权独立 GitHub 交接；它不授权部署、合并、安装、付费超额或后续自动公开新内容。

## 大资源传输说明

GitHub插件单请求限制16 MiB。两个大GLB采用普通Git二进制分片保存在 asset-parts/，不是LFS指针、不依赖远程下载；运行 python3 restore-assets.py 可按manifest逐字节重组并核对SHA-256。第三个GLB直接保存在assets。重组会拒绝覆盖不同字节的已有文件。原GLB哈希与尺寸不变。
