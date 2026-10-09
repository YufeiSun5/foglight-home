# Tripo v3：请求契约与差异

核验日期 2026-10-09；以下均来自 Tripo 官方端点文档。基础地址 `https://openapi.tripo3d.ai/v3`，认证头为 Bearer（实际值只从获批的安全运行环境提供）。不要沿用 v2 的统一任务创建请求；文档响应示例的 type/积分有复用痕迹，按本次真实响应处理。

## 入口与版本

- [单图 H 系列](https://developers.tripo3d.ai/zh/docs/generation-image-to-model/standard)：`POST /generation/image-to-model`，必填 `input`、`model`。input 为上传 file_token、公开图片 URL 或支持的图像生成任务 ID 三选一。PNG/JPEG/WebP，20 MB；建议主体清晰、至少 256×256。
- [单图 P 系列](https://developers.tripo3d.ai/zh/docs/generation-image-to-model/p)：同端点，不同 model 与能力。`P1-20260311` 面数 50–20,000；`P2-20260801` 为 preview，三角面 48–50,000，quad 时 48–25,000。P1 不支持 quad。不要把 H 的 smart_low_poly/generate_parts 参数直接复制进 P。
- H 的明确版本为 `v3.1-20260211`、`v3.0-20250812`、`v2.5-20250123`。普通三角面标准上限分别 1,500,000 / 1,000,000 / 500,000；v3.0+ detailed 几何上限 2,000,000。这些是 API 能力，不是本工坊的性能预算。
- [概念页](https://developers.tripo3d.ai/zh/docs/models-and-versions)仍出现 tripo-v3.1/tripo-p1 别名，llms.txt 仍称 V 系列，而端点页称 H。优先采用具体端点列出的锁定版本，不自行推断别名等价。

## 单图生成多视图，再生成网格

[多视图图像](https://developers.tripo3d.ai/zh/docs/generation-image-to-multiview)：`POST /generation/image-to-multiview` 只列必填 `input`（file_token 或公开 URL）。成功输出 `front_view_url`、`left_view_url`、`back_view_url`、`right_view_url`。先检查四张图的屋顶、烟囱、门窗、主轴与尺寸是否一致；生成的不可见面是推断，不能说来自原图。

[多视图 H](https://developers.tripo3d.ai/zh/docs/generation-multiview-to-model/standard) / [多视图 P](https://developers.tripo3d.ai/zh/docs/generation-multiview-to-model/p)：`POST /generation/multiview-to-model`，必填 `inputs` 与 `model`。三种 inputs 格式不能混用：

- 推荐 view-key 对象数组，如 `[{"front":"FILE_TOKEN_FRONT"},{"back":"FILE_TOKEN_BACK"}]`。每项一个 front/left/back/right 键；至少两张且 front 必须存在。
- 旧式固定四字符串，顺序 **front, left, back, right**；缺失视角用空字符串占位。
- 直接复用成功的多视图图像任务，必须是单元素数组 `[{"task_id":"MULTIVIEW_TASK_ID"}]`，不是裸字符串。文档要求原任务类型 generate_multiview_image 或 edit_multiview_image 且 success。

## PBR 与几何陷阱

H/P 的 texture、pbr 默认均 true；pbr=true 会强制 texture=true。要先验纯几何必须显式设置两者 false。model_seed 与 texture_seed 分开记录，但种子可重现性仍以实际结果核验。

生成时用 `texture_version` 指定贴图模型；后处理贴图接口改用 `model`。`v3.5-20260815` 才支持 delight 与 fast；早期版本忽略 delight，fast 则会报 1004。为可重打光可选择该版本的 delight=true，但仍须检查底色里的固定阴影，不能凭开关宣称去光照成功。

H v3.0+ 的 smart_low_poly 范围：三角面 500–20,000；quad 500–10,000。H quad 强制 FBX。generate_parts 要 texture=false、pbr=false，且不与 quad/smart_low_poly 混用。不要用自动部件功能推断模型天然可拆装。生成阶段避免 export_orientation，后处理完成再调整朝向；官方警告错误朝向可能仍返回 success。

## 后处理

[贴图](https://developers.tripo3d.ai/zh/docs/models-texture)：`POST /models/texture`，input 可为模型 task_id/file_token/URL；支持 GLB/GLTF/FBX/OBJ/STL，150 MB。texture_prompt 中 text/image/images 互斥；images 必须四张、顺序正左背右。style_image 只能与 text 搭配。复用 task_id 时官方建议重新提供参考图。pbr=true；texture_quality 有 fast/standard/detailed/extreme。bake 默认 true，不应误称为几何减面或保证无光照底色。

[重拓扑](https://developers.tripo3d.ai/zh/docs/mesh-decimate)：`POST /mesh/decimate`，input、目标 face_limit，model 默认 `v2.0`（智能重拓扑），`v1.0` 为基础减面；两者支持 quad，v1.0 不支持 bake/part_names。input 概述只提 task_id/file_token，但展开列表亦列 URL，有不一致；稳妥采用获批上传后的 file_token 或明确支持的 task_id。目标面数不是输出三角形实测数。

[转换](https://developers.tripo3d.ai/zh/docs/models-convert)：`POST /models/convert` 必填 input 与 format；枚举 GLTF/FBX/USDZ/OBJ/STL/3MF，**未列 GLB 作为 format 值**。需要 GLB 时可在 Blender 本地导出，不猜 API 枚举。quad 强制 FBX；face_limit、texture_size、texture_format、scale_factor、pivot_to_center_bottom 等可能改变成本。pack_uv、bake、导出朝向也须逐项检查；不要为本地可完成的操作默认额外付费转换。

## 文件与查询

[上传](https://developers.tripo3d.ai/zh/docs/files)：`POST /files`，multipart/form-data 的 file 字段，返回 data.file_token。此上传页仅列 JPEG/PNG（生成页还列 WebP）；优先 PNG/JPEG，别推断 WebP 上传已验证。图片 20 MB，模型 150 MB；大于 60 MB 官方建议大文件上传流程，另见[预签名上传](https://developers.tripo3d.ai/zh/docs/files-presign)。上传同样需要授权，不能因其未列收费就自动上传。

[任务查询](https://developers.tripo3d.ai/zh/docs/task-query)与[生命周期](https://developers.tripo3d.ai/zh/docs/task-lifecycle)：`GET /tasks/{task_id}`。创建成功返回 data.task_id，不是资产。queued/running 为处理中；success 才读取 output；failed/cancelled/banned/expired 为停止状态。保存 error_code/error_message（如有）、progress、时间和实际返回字段。按官方节流建议轮询，超时只是本次查询暂停，不等于服务端取消或失败；保留 ID 再查，别重新付费提交。批量查询见[批量任务](https://developers.tripo3d.ai/zh/docs/task-batch-query)。

`output.model_url` 与预览图片是不同交付物；下载真实网格及全部材质依赖后检查哈希与可读性。不要把 rendered_image_url 当作 3D 资产。

大文件流程：`POST /files/presign` 传 format（不带点的扩展名），取得 presigned_url、file_token、expires_in；URL 有效 1800 秒，用 HTTP PUT 上传，不附 API Authorization 到存储域名。预签名链接属临时访问能力，不入源码或交付日志。上传后再把 file_token 交给后续获批任务。批量查询 `POST /tasks/list` 传 task_ids（最多 100），结果 data.tasks 为 ID→详情 map，data.missed 为缺失 ID；missed 不等于任务失败或收费为零。

## 单主屋程序请求计划（未执行、非费用授权）

API Key 直接 Bearer 认证即可，CLI/浏览器登录不是必要条件。认证实现仅接受已获准安全提供的凭据，不把密钥放入 JSON、仓库、日志或请求 URL。

候选最短路径：获批输入 PNG → `POST /files` 取得 file_token → `POST /generation/image-to-model` → 查询同一 task_id → 保存真实模型 → 本地 Blender/Godot 验收。首轮不叠加收费多视图、重拓扑、转换或重新贴图。以下 JSON 是待核预算的明确候选，不是已提交请求；20,000 faces 是拟议 API 上限，不是实测性能预算：

```json
{
  "input": "AUTHORIZED_UPLOAD_FILE_TOKEN",
  "model": "v3.1-20260211",
  "face_limit": 20000,
  "texture": true,
  "pbr": true,
  "texture_version": "v3.5-20260815",
  "texture_quality": "standard",
  "delight": true,
  "geometry_quality": "standard",
  "smart_low_poly": false,
  "quad": false,
  "generate_parts": false,
  "auto_size": false,
  "export_uv": true,
  "enable_image_autofix": false,
  "texture_alignment": "geometry"
}
```

此候选优先检验主屋轮廓与可重打光材质，保留原始几何供本地减面；不承诺 20k 面必然保住细节。若要改为 P1/P2 或 smart_low_poly，先核实相应参数、版本和价格，不静默替换。根据当前价目核算这一明确请求，不以示例 credits_consumed 当报价；不知道版本选择是否另有费用时写待核实。创建成功记录 ID，成功后取 model_url、credits_consumed 并与 usage 对账；不确定是否创建成功时禁止盲目重试 POST。
