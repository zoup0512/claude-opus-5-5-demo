# PelicanBike 视觉回归

该工具比较网页基线 PNG 与 HarmonyOS 模拟器/真机 PNG。它只依赖 Python 标准库和 Pillow，不需要 NumPy、OpenCV 或浏览器运行时。

## 目录约定

默认配置位于：

```text
tools/visual-regression/config.pura90.json
```

默认输入和输出：

```text
docs/web-baseline/       网页基线 PNG（当前可不存在）
emulator/screenshots/    未来设备/模拟器 PNG（当前可不存在）
docs/visual-regression/latest/
  report.json
  report.md
  <scene>/side-by-side.png
  <scene>/alpha-overlay.png
  <scene>/heatmap.png
```

输入目录或某个场景图片缺失时，普通比较仍返回成功并生成 JSON/Markdown 报告，场景状态为 `missing`。CI 若要求缺图失败，增加 `--strict-missing`。

## 安装与检查

在项目根目录运行：

```powershell
python -m pip install -r tools/visual-regression/requirements.txt
python tools/visual-regression/visual_compare.py doctor
```

要求 Pillow 10–12；缺少 Pillow 时脚本会输出明确的安装命令。

## 运行

使用 Pura90 默认配置：

```powershell
python tools/visual-regression/visual_compare.py compare
```

Windows 也可使用：

```powershell
tools\visual-regression\run-compare.cmd
```

只比较一个命名场景：

```powershell
python tools/visual-regression/visual_compare.py compare --scene ride-chase
```

覆盖输入/输出路径：

```powershell
python tools/visual-regression/visual_compare.py compare `
  --baseline-dir docs/web-baseline `
  --actual-dir emulator/screenshots `
  --output-dir docs/visual-regression/local
```

退出码：

- `0`：比较通过，或仅缺少输入且未启用严格缺图。
- `1`：至少一个场景超出阈值；`--no-fail` 可仅生成报告而返回 0。
- `2`：配置、图片读取、依赖等错误，或 `--strict-missing` 下缺图。

## 场景映射

`scenes` 的键是稳定场景名。`baseline` 和 `actual` 接受按优先级排列的 glob；第一个有匹配的文件用于比较。glob 可匹配文件名，也可写带 `/` 的相对路径。

```json
{
  "scenes": {
    "ride-chase": {
      "baseline": ["ride-chase.png", "*chase*.png"],
      "actual": ["pura90-ride-chase.png", "*chase*.png"]
    }
  }
}
```

如果同一个模式匹配多个文件，工具按稳定排序选择第一个，并在报告中警告。推荐最终统一使用 `<scene>.png`。

默认示例映射当前网页基线的 12 个命名场景：`day-orbit`、`sunset-orbit`、`night-orbit`、`ride-chase`、`ride-side`、`ride-cine`、`ride-pov`、`jump`、`trick`、`fish-normal-gulp`、`fish-golden-gulp`、`offshore-jumping-fish`。可以复制配置并添加场景；无需修改脚本。

三个事件场景分别匹配 `10-fish-normal-gulp.png`、`11-fish-golden-gulp.png` 和 `12-offshore-jumping-fish.png`，设备图可使用相同编号名、稳定场景名，或 `pura90-<scene>.png`。

## 对齐模式

画布默认是 Pura90 竖屏 `1320 × 2856`，网页基线也建议直接截成同尺寸。当前仓库中的 `1440 × 900` 网页基线会先通过默认 `letterbox` 等比放入竖屏画布；若未来改为同尺寸网页基线，则无需更改配置。

`alignment.mode` 支持：

- `resize`：非等比拉伸到画布。
- `letterbox`：等比完整放入，剩余区域填充背景色。
- `crop`：等比覆盖画布，超出部分裁剪。
- `none`：拒绝尺寸不一致。

`anchor: [x, y]` 控制 letterbox/crop 的定位，范围 0–1；`filter` 支持 `nearest`、`box`、`bilinear`、`bicubic`、`lanczos`。场景可使用 `alignment` 覆盖全局，也可用 `baseline_alignment` 和 `actual_alignment` 分别处理两侧。

## 安全区和动态区域

默认配置遮罩 Pura90 顶部/底部安全区，并定义 FPS、粒子和时间区域：

```json
{
  "mask": {
    "safe_area": {"unit": "px", "top": 126, "bottom": 126},
    "default_ignore": ["fps", "particles", "time"],
    "ignore_region_sets": {
      "fps": [{"unit": "normalized", "rect": [0.69, 0.025, 0.30, 0.075]}]
    }
  }
}
```

矩形格式是 `[x, y, width, height]`，`unit` 可为 `normalized` 或 `px`。也支持多边形：

```json
{
  "unit": "normalized",
  "polygon": [[0.0, 0.55], [1.0, 0.48], [1.0, 0.9], [0.0, 0.9]]
}
```

场景可通过 `ignore` 加入命名动态区域，通过 `ignore_regions` 加入临时区域。若希望场景不继承 `default_ignore`，设置 `replace_default_ignore: true`。

新增事件场景还使用以下命名遮罩：`event_hud_values` 忽略速度、计数和时钟等变化数值；`event_notifications` 忽略短暂事件提示；`gulp_cloth_motion` 忽略吞鱼时围巾摆动；`ambient_birds` 忽略远海随机飞鸟；`offshore_splash_particles` 只忽略跳鱼下方的随机水花粒子。鱼体本身不会被遮罩，仍由专用 ROI 评分。事件遮罩与 ROI 同时覆盖当前横屏基线经 `letterbox` 后的坐标，以及未来原生 `1320 × 2856` 基线坐标。

遮罩仅影响指标和热图；side-by-side 保留原图，overlay/heatmap 将忽略区域显示为灰色。

## ROI

默认示例包含：

- `sky`
- `ocean`
- `road`
- `rider`
- `HUD`
- `topbar`
- `controls`

每个 ROI 与全局有效遮罩相交后独立计算指标。三个事件场景另定义 `gulp_fish`/`golden_fish`、`beak_and_gulp`、`basket_fish`、`jumping_fish` 与 `offshore_action`，用于把吞鱼颜色、嘴部姿态、篮筐鱼和远海跳鱼从大面积背景差异中单独检查。

`roi_thresholds` 可用 `*` 设置通用阈值，再按 ROI 名覆盖。默认 `comparison.fail_on_rois` 为 `false`，ROI 失败用于定位而不改变场景结论；改为 `true` 后任一 ROI 失败都会使场景失败。

场景可覆盖 ROI，或禁用不适用的 ROI：

```json
{
  "scenes": {
    "ride-pov": {
      "rois": {
        "rider": {"enabled": false}
      }
    }
  }
}
```

## 指标与产物

每个场景和 ROI 输出：

- RGB 像素 `MAE`，0 为相同。
- RGB 像素 `RMSE`，0 为相同。
- `PSNR`（dB），越高越好；完全相同在 Markdown 中为 `∞`，JSON 中为 `null`。
- 简化全局 `SSIM`：亮度/对比度/结构得分，计算前限制最长边以控制内存和耗时。
- `edge_structure_score`：Pillow 边缘图的结构相似度，越高越好。
- `histogram_distance`：三通道归一化颜色直方图差异，0 为相同。
- `changed_pixel_ratio`：RGB 任一通道差异超过 `changed_pixel_threshold` 的像素比例。
- `visual_score`：0–100 的排查用混合分，不替代原始指标。

图像产物：

- `side-by-side.png`：左右原图。
- `alpha-overlay.png`：50% 叠加。
- `heatmap.png`：绝对差异热图。
- `report.json`：机器可读明细、输入哈希、变换、遮罩和阈值检查。
- `report.md`：汇总表、ROI 表和图片链接。

默认阈值是首轮移植的宽松起点。获得稳定的网页与设备截图后，应根据真实结果收紧，而不是只依赖混合分。

## 自检

自检用程序生成两张 `160 × 120` 小图，并在内存中构造中等差异图，验证 MAE/RMSE/变化率单调上升，PSNR/SSIM/综合分单调下降，同时验证边缘、直方图、三种图像产物和缺图报告：

```powershell
python tools/visual-regression/visual_compare.py selftest
```

默认在 `tools/visual-regression` 下创建临时目录并在结束后清理。需要保留自检图片与产物时：

```powershell
python tools/visual-regression/visual_compare.py selftest `
  --keep-output docs/visual-regression/selftest
```
