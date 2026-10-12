# Harmony GLES 性能与稳定性方案

## 1. 范围与依据

本方案只新增 `tools/perf` 与 `docs/performance`，不修改根配置、`entry` 或其他目录。设计依据：

- 原 H5 `README.md`：鹈鹕骑行包含 5 种镜头、自适应画质、昼夜循环；历史说明提到 320 秒快进 soak、36 km 边界与资源稳定验证，但这些是原 Web 项目的历史描述，**不是 Harmony 真机结果**。
- 原 `main.js`：四档画质、HDR/Bloom 后期、阴影、动态分辨率、5 镜头、昼夜推进、环境贴图刷新与截图路径。
- 原 `world.js`：每块 `CHUNK=72 m`、7 个循环块、按实例密度生成树/松树，距离持续累积。
- 原 `ocean.js`：海面相位用 JS 双精度计算并取模后传给 shader，避免长距离精度跳变。
- 原 `effects.js`：动态粒子缓冲、实例化彩纸、速度线和每帧更新法线的围巾，是 CPU/上传压力来源。
- Harmony staging：固定 1/60 s 模拟步长、`kWorldChunkLength=72`、`kWorldChunkCount=7`、GLES3 RAII 资源封装、实例缓冲、Framebuffer/Texture/Buffer 对象，以及 1320×2856 Pura 90 视觉回归画布。

本目录提供**可执行框架、日志协议、阈值和样例自检**；当前任务没有 HAP、bundle/ability 实值和已连接设备，因此没有生成、也不宣称任何 Harmony/Pura 90 实测结论。

## 2. 四档画质目标

画质档位是 GLES 首版目标，不是已经在设备上证实的最优值。Render scale 作用于 1320×2856 的游戏渲染目标；ArkUI/HUD 若由 UI 层绘制，应保持物理分辨率。动态分辨率可在档位目标以下降档，但不得超过目标值。

| 档位 | Render scale | 渲染尺寸（向上取整） | 阴影 | Bloom | AA | 实例密度 | 目标 / 最低 FPS |
| --- | ---: | ---: | --- | --- | --- | ---: | ---: |
| 流畅 low | 0.60 | 792×1714 | 1024²，单图，28 m caster | 关 | FXAA，MSAA 1× | 0.50 | 60 / 50 |
| 均衡 medium | 0.72 | 951×2057 | 1536²，单图，40 m | 半分辨率 5 级 | FXAA，MSAA 1× | 0.80 | 60 / 54 |
| 精美 high | 0.85 | 1122×2428 | 2048²，单图，55 m | 半分辨率 5 级 | MSAA 2×，FXAA 关 | 1.00 | 60 / 54 |
| 极致 ultra | 1.00 | 1320×2856 | 3072²，单图，70 m | 半分辨率 5 级 | MSAA 4×，FXAA 关 | 1.25 | 45 / 40 |

约束：

1. `MSAA 1×` 表示没有多采样附件，不是调用 1-sample multisample API。
2. FXAA 与 MSAA 默认互斥，避免无收益的双重成本；若极细线仍闪烁，应先评估 TAA/几何方案，不直接叠加。
3. Bloom 输入前必须保留 H5 的 finite/范围清理思想：shader 输出非有限值或过大 HDR 值时计数并截断，`glErrors/contextLosses` 仍必须为 0。
4. 画质切换必须销毁并重建相关 FBO/texture/renderbuffer，资源计数在稳定窗口内回落；不可只覆盖句柄。
5. low 的 0.50 密度对应 H5 `world.js` 的 `34/26` 树木基数缩放；棕榈、岩石、伞等固定小集合可保持最低可读数量。
6. 默认推荐 high；若高档 p95 GPU 超阈值，先降 render scale/Bloom，再降实例密度，最后才关闭阴影。

机器可读版本见 `tools/perf/perf_config.json`。

## 3. 1320×2856 显存预算

### 3.1 格式和计算假设

下表只计算主要渲染目标，不含 mesh、实例、纹理资产、shader、驱动元数据和压缩收益。采用保守线性布局：

- 默认颜色缓冲：RGBA8，4 B/px，并按 3 个 swapchain buffer 估算。
- 深度/模板：D24S8，4 B/px。
- HDR：RGBA16F，8 B/px。
- high/ultra：MSAA RGBA8 + MSAA D24S8，resolve 到单采样 RGBA16F；另有一个 RGBA16F post target。
- medium：单采样 RGBA16F scene + RGBA16F post。
- Bloom：从半分辨率开始，5 级 RGBA16F ping-pong；每级两张纹理。
- `MiB = bytes / 1,048,576`。驱动 tiling、AFBC、隐式中间面和 swapchain 数量都可能改变实值，所以真机必须用 RenderService/厂商工具复核。

### 3.2 预算表

| 档位 | 默认 color | scene color/resolve | depth | HDR/post | Bloom | 小计 | +20% guard | RT 上限 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| low | 15.54 MiB | 0 | 0 | 0 | 0 | 15.54 | 18.64 | **32 MiB** |
| medium | 22.39 | 7.46 | 7.46 | 22.39 | 9.96 | 69.66 | 83.59 | **96 MiB** |
| high | 31.18 | 41.57 | 20.78 | 20.78 | 13.86 | 128.17 | 153.80 | **160 MiB** |
| ultra | 43.14 | 86.29 | 57.52 | 28.76 | 19.16 | 234.88 | 281.85 | **320 MiB** |

说明：表中 `scene color/resolve` 将 medium 的单采样 scene color 与 high/ultra 的多采样 color + HDR resolve 按职责归类；精确可复算字段在 `perf_config.json` 中拆分保存。

全局硬上限：

- 活跃 GLES 资源估算总量：**384 MiB**。包括上述 render targets、约 15.34 MB 导出二进制和约 15.9 MiB RGBA8 原始纹理，再留资源/驱动空间。
- 进程 RSS：**768 MiB**。
- 任何质量档的实际 render-target 估算超过自身 RT 上限：FAIL；资源总量超过 384 MiB：FAIL。
- Ultra 的 4× MSAA 成本很高；若设备测得驱动还有额外 resolve/中间面导致越界，Ultra 应降为 2× MSAA 或 0.9 render scale，而不是提高预算。

## 4. `PEL_PERF` 单行 JSON 协议

### 4.1 传输规则

主引擎通过 HiLog 输出一行：

```text
PEL_PERF {JSON_OBJECT}
```

要求：

- `PEL_PERF ` 前允许有任意 hilog 时间/PID/tag 前缀；前缀后必须是**完整单行 JSON**。
- 协议版本 `v` 当前必须是 `1`。
- 一行不超过 HiLog 限制；禁止 pretty-print、换行和私密字段。Harmony HiLog 格式字符串应使用 public 可见口径，否则 release 日志会变成 `<private>`。
- 数字必须 finite；不能输出 `NaN`、`Infinity`。发现非有限状态时应输出 `event="error"`，并在 `end.result="fail"` 中结束。
- 一个场景只允许一个 engine `begin` 和一个 engine `end`。主机编排器使用 `host_begin/host_end`，不能伪造引擎通过。
- `runId` 在前后台重建、surface 重建和 Ability 重启参数传递期间保持一致。

### 4.2 事件

开始：

```json
{"v":1,"event":"begin","runId":"p90-high-001","scenario":"soak10m","quality":"high","tsMs":0,"targetFps":60,"surfaceWidth":1122,"surfaceHeight":2428,"renderScale":0.85}
```

周期采样（建议每 1 秒聚合一次；frame CPU/GPU 为这一秒的帧统计，可额外输出窗口 p95）：

```json
{"v":1,"event":"sample","runId":"p90-high-001","scenario":"soak10m","quality":"high","tsMs":1000,"frame":60,"fps":59.4,"frameCpuMs":7.2,"frameGpuMs":11.4,"frameMs":12.0,"drawCalls":184,"triangles":618000,"heapMiB":96.2,"rssMiB":301.5,"gpuMiB":151.4,"distanceM":75.0,"hour":17.75,"surfaceWidth":1122,"surfaceHeight":2428,"resources":{"textures":34,"buffers":169,"framebuffers":9,"renderbuffers":4,"programs":18,"vaos":71,"glErrors":0,"contextLosses":0}}
```

场景结束：

```json
{"v":1,"event":"end","runId":"p90-high-001","scenario":"chunkBoundaries","quality":"high","tsMs":150000,"result":"pass","checks":{"crossed_36000m":true,"crossed_72m":true,"chunk_slots_unique":true,"finite_state":true,"resources":true,"errors":true}}
```

失败：

```json
{"v":1,"event":"end","runId":"p90-high-001","scenario":"surfaceResizeRotate","quality":"high","tsMs":42000,"result":"fail","reason":"surface_ready_timeout","checks":{"completed_cycles":false,"resize_latency":false,"finite_viewport":true,"resources":true,"errors":true}}
```

### 4.3 字段定义

| 字段 | 必需事件 | 单位/语义 |
| --- | --- | --- |
| `v` | 全部 | 协议版本，当前 1 |
| `event` | 全部 | `begin` / `sample` / `end` / `error`；主机保留 `host_begin/host_end` |
| `runId` | 全部 | 一次场景的稳定 ID |
| `scenario` | 全部 | `scenarios.json` 中名称 |
| `quality` | 全部 | low/medium/high/ultra |
| `tsMs` | 全部 | 相对 begin 的单调时间，毫秒 |
| `fps` | sample | 聚合窗口 FPS |
| `frameCpuMs` | sample | 应用更新+提交 CPU 帧时间；不要填系统 CPU 百分比 |
| `frameGpuMs` | sample | GPU timer query 或可信 profiler 值；不可用时缺省，不能用 CPU 值伪装 |
| `frameMs` | sample | 完整帧/呈现间隔，毫秒 |
| `drawCalls` | sample | 本窗口每帧最大或明确的当前帧值，整个项目统一口径 |
| `triangles` | sample | 本窗口每帧最大或当前帧提交三角形 |
| `heapMiB` | sample | 应用管理堆/native allocator 已用量，需在实现中注明来源 |
| `rssMiB` | sample | 可由应用或外部 hidumper 补充 |
| `gpuMiB` | sample | 引擎跟踪的 GLES 分配字节，含 RT/纹理/buffer；不能仅填 RenderService 全局值 |
| `resources.*` | sample | 当前存活 GLES 名称计数和累计错误计数 |
| `distanceM` | sample | 双精度绝对里程，边界场景必需 |
| `hour` | sample | 游戏时刻 `[0,24)` |
| `surfaceWidth/Height` | begin/sample | 实际游戏渲染目标尺寸，不是只报物理屏幕 |
| `result/reason/checks` | end | 引擎场景判定与可机器校验的结束条件 |

GPU 资源计数必须在所有 RAII `create/destroy` 路径增减，覆盖：Texture、Buffer、Framebuffer、Renderbuffer、Program、VAO。计数器自身不等于驱动真实显存，但能可靠检测生命周期泄漏；字节数与 RenderService/厂商工具交叉验证。

## 5. Pass/Fail 阈值

机器判定以 `perf_config.json` 为准。核心门槛：

### 帧率与帧时间

- 至少 20 个 sample；标准 10 分钟场景建议 600 个 1 秒 sample。
- median FPS ≥ 目标的 95%。
- p05 FPS ≥ 目标的 80%。
- 低于档位最低 FPS 的样本比例 ≤ 5%。
- CPU p95：low/medium ≤ 13.0 ms，high ≤ 13.5 ms，ultra ≤ 18.0 ms。
- GPU p95：low/medium ≤ 15.5 ms，high ≤ 16.0 ms，ultra ≤ 21.5 ms。
- frame p99 ≤ 1.5× 帧预算；超过 2× 帧预算的 hitch 比例 ≤ 1%。

### 负载与内存

- draw calls 最大值：170 / 210 / 260 / 320。
- triangles 最大值：350k / 550k / 850k / 1.2M。
- heap ≤ 256 MiB；净增长 ≤ 24 MiB；线性趋势 ≤ 1 MiB/min。
- RSS ≤ 768 MiB；净增长 ≤ 64 MiB；趋势 ≤ 2 MiB/min。
- GPU tracked memory ≤ 384 MiB；净增长 ≤ 32 MiB；趋势 ≤ 1 MiB/min。
- 稳定窗口资源净增长：texture ≤ 2、buffer ≤ 4、FBO/RBO ≤ 2、program ≤ 1、VAO ≤ 4。
- GL error、context loss、crash、ANR、fatal event：0。

### 恢复

- 前台恢复可绘制 ≤ 2000 ms。
- surface 重建可绘制 ≤ 1500 ms。
- resize/旋转后尺寸稳定并可绘制 ≤ 1200 ms。
- 20 次截图失败数：0。

如果必需指标缺失，报告为 FAIL（required group incomplete）；非必需指标缺失则总体为 `INCOMPLETE`，绝不提升为 PASS。

## 6. 自动测试场景

### 6.1 `soak10m`

- 正常时间、自动骑行、所有动态系统开启 600 秒。
- 覆盖粒子、围巾、海面、分块回收、鱼生成、灯塔/船/鸟、Bloom 和阴影。
- 需要完整性能、heap/RSS/GPU 与资源趋势。

### 6.2 `dayNight24h`

- 固定 1/60 模拟保持，游戏小时以 480× 推进：180 秒完成 24 h。
- 必须跨日落、午夜、日出，检查环境/Bloom/阴影状态切换以及环境资源不重复创建。
- `end.checks.completed_cycles`、`finite_state`、`resources`、`errors` 必须为真。

### 6.3 `chunkBoundaries`

- 从 35,856 m 推进到 36,144 m，覆盖 `36,000 = 500 × 72 m` 及前后多个 72 m seam。
- 每次回收后 7 个 slot 对应 7 个不同 chunk index；transform、地形、波相位必须 finite。
- 检查跨界前后相机/海面/地形没有大跳变；视觉结果可另接现有 visual-regression 工具，但本性能脚本不伪造像素判定。

### 6.4 `cameraSwitch`

- 250 ms 一次，在 orbit/chase/side/cine/pov 间连续切换 400 次。
- 不重载场景；相机矩阵、FOV、near/far 与 look target 必须 finite。
- 资源计数不应随镜头增长；统计切换窗口 frame p99/hitch。

### 6.5 `background100`

- 主机使用 `uitest uiInput keyEvent Home`，再用 `aa start` 回前台，共 100 次。
- 主机只能证明 HOME/aa 命令完成；引擎必须记录 `onForeground/onBackground`、surface 销毁/创建、首个 present 的延迟并在 end.checks 中确认 `resume_latency`、`surface_recovery`。
- 如果 Ability 每次被系统杀死，也要按 runId 恢复测试状态并明确记录 process restart；不能把重新启动成功当作 surface 恢复通过。

### 6.6 `surfaceResizeRotate`

- 40 次 portrait/landscape 或等价 surface resize。
- OpenHarmony 命令行 `uinput -P -r` 是 touchpad 旋转手势，文档明确当前可能不生效，**不能用于显示旋转通过判定**。
- 正式执行须二选一：
  1. 在现有/未来 ohosTest HAP 中调用 `Driver.setDisplayRotation(ROTATION_0/ROTATION_90)`；或
  2. 把经过目标设备验证的显示旋转 shell 命令写入 `scenarios.json.rotationCommand`（含 `{rotation}`）。
- 默认命令为空，框架会显式失败，避免假执行。

### 6.7 `screenshots20`

- 游戏持续渲染时执行 `uitest screenCap -p /data/local/tmp/...`，拉回并验证 20 个非空 PNG。
- 引擎仍须记录截图期间性能与资源，结束时确认 `completed_captures` / `capture_success` / `resources` / `errors`。

## 7. 采集与报告

### 无设备自检

```powershell
cd D:\workspace\My\harmony\harmony-PelicanBike\tools\perf
pwsh -File .\run_perf.ps1 -Mode self-test
```

执行内容：生成 `sample_hilog.txt`，严格解析 60 个 synthetic sample，写入 `out/self-test/report.json` 和 `report.md`。这只说明解析链路可用。

### 真机采集

```powershell
pwsh -File .\run_perf.ps1 -Mode scenario -Scenario soak10m `
  -Bundle <bundleName> -Ability <abilityName> -Module <moduleName> `
  -Hap <signed.hap> -Install -Quality high -ClearHilog -Strict -RequireDevice
```

原始材料保留于场景目录：

- `raw/hilog-device.txt`、`raw/hilog-combined.txt`
- 定期 `hidumper --mem`、`--cpuusage`、RenderService GLES/表面内存文本
- `raw/faults-after.txt`
- 截图场景的 20 个 PNG
- `report.json`、`report.md`

`hidumper` 输出目前作为伴随证据保存，因为不同系统版本字段格式可能变化。主引擎必须自报协议规定的可比较指标；后续若锁定 Pura 90 系统版本，可再添加版本化 hidumper adapter，不应写脆弱的通用正则并误报。

## 8. 已完成的本地验证

本次只执行了无需设备的验证：

- Node 语法检查。
- Bash `-n` 语法检查。
- PowerShell `run_perf.ps1 -Mode self-test`。
- 解析器结果：62 条 `PEL_PERF` 记录，其中 60 个 sample，synthetic report 为 PASS。

上述 PASS 是**工具自检 PASS**，不是游戏、HAP、Harmony 设备或 Pura 90 的性能 PASS。
