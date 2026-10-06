# 第一章云端叙事试玩候选 0.1

## 运行

使用 Godot 4.6.3 打开 `project.godot`，或在仓库根目录运行 `godot --path .`。实际内容为离线单人第一章，不需要账号、API key、联网LLM或任务刷取。

WASD/方向键移动，Shift快走，E附近交谈/进出船舱，R继续故事，Space/Enter继续对白，1/2/3选择回应，C衣柜，J回顾，F5保存，F9读取，Esc关闭/暂放/暂停。暂停菜单有退出确认。已有进度启动后按F9恢复。

固定4衣色×4下装从开场直接可用。可选随机短途尚未实现，不影响故事与衣装。NPC为定点眨眼待机。主角四向待机，三方向实绘行走，左向由右向镜像。没有配乐、语音、手柄和按键重绑。

## 复验

```
bash tools/verify.sh
```

全部脚本有界执行。仅状态/内容核心CI使用 `bash tools/verify-core.sh`；完整资源与表现层由聚合入口检查，不能拿核心CI替代完整试玩。

导出使用官方4.6.3 release模板。当前预设指向本地未入库的 `.qa/tools-downloads/linux_release.x86_64` 和 `windows_release_x86_64.exe`；从Godot官方同版本export templates放置相应文件后：

```
mkdir -p builds/linux builds/windows builds/licenses
godot --headless --path . --export-release Linux builds/linux/FoglightHome.x86_64
godot --headless --path . --export-release Windows builds/windows/FoglightHome.exe
godot --headless --path . --script tools/engine_notices.gd
```

导出目录保留可执行文件与同名PCK，再附带字体OFL/版权、引擎MIT/组件版权/许可、素材来源。不要将source、缓存、测试存档、官方参考截图或临时日志放进发行归档。

## 证据范围

所有实现与实测发生在dot云端Linux。Godot4.6.3，Compatibility，Mesa llvmpipe CPU软件渲染，实际GUI窗口与渲染均960×540，音频Dummy。Windows文件为交叉导出，仅验证官方模板版本/字节、包内资源和许可，没有Windows实机执行证据。

真实输入完成：自由港口移动与遮挡、仓库门边尺度、木桥和坡道、船舱进出、NPC半身对白、16套衣柜、同状态换色、三组分支、连续快点、读档恢复另一分支、章节结束、正常退出再启动恢复章节/衣装。完整主线实际选择工作优先、拒绝衣装、保留私人事情，仍收束第一章；没有可选模式门槛。

自动化与当前状态仅以AI_BOARD为准。独立只读审计复现并验证修复了旧回调先写盘问题；对最终Linux解压包独立启动，以及两平台ZIP/PCK成员、哈希、必要资源、许可证进行检查。

当前PCK SHA-256：`bca331eb5407c43466bc506c230f93d74982263f17543db338a5715c6b1e12cf`。PCK内误带一份早期`builds/source-snapshot-sha256.json`，仅story_rules哈希早于最后出生点修正；不用它作最终版本证明。准确冻结源码清单放在包外和本目录，独立审计已直接加载包内编译规则确认出发段返回`[-1.2,3.4]`。该冗余待下轮打包排除，不影响当前玩法。

截图、10秒wall-clock帧率观察及Linux软件渲染都不能保证目标显卡性能，当前美术是可改进原型，不宣称复现商业预算或已完成Steam审核。
