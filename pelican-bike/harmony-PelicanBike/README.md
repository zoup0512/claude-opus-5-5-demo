# 鹈鹕骑行 · HarmonyOS 原生版

将 [pelican-bike](https://github.com/riba2534/claude-opus-5-5-demo)（Three.js/WebGL 网页 3D 游戏）完整复刻为 **原生 HarmonyOS 手机 App**。

- **不使用 WebView / Web 组件**：3D 画面由 C++ / OpenGL ES 3 / NativeVSync 直接渲染到 XComponent Surface。
- **架构**：ArkTS/ArkUI（界面/HUD/触控/系统能力）+ Native C++17（EGL/GLES3 渲染、固定步长玩法模拟、OHAudio 实时合成音频）。
- **工程**：`D:\workspace\My\harmony\harmony-PelicanBike`，HarmonyOS Stage 模型，API 24（6.1.1），bundleName `com.riba2534.pelicanbike`，双 ABI `arm64-v8a` / `x86_64`。

---

## 快速开始

### 环境

- DevEco Studio 6.1.1（自带 Node 18 / OHPM / Hvigor / JBR / SDK API 24）
- Pura90 模拟器（HarmonyOS 6.1.1, x86_64）或真机

### 构建

```bash
cd D:\workspace\My\harmony\harmony-PelicanBike

# 一键构建 unsigned HAP（使用 DevEco 自带工具链）
powershell -File tools\device\device.ps1 build -PackageMode unsigned

# 产物
# entry\build\default\outputs\default\entry-default-unsigned.hap  (约 20 MB)
```

### 本地调试签名并安装（Pura90 模拟器）

模拟器需要 debug 签名的 HAP 才能安装。项目提供脚本生成**仅属于本 bundle** 的本地调试签名（不复用任何其他应用材料）：

```powershell
# 首次：生成项目专属密钥/证书/profile（绑定当前模拟器 UDID）
powershell -File tools\device\local-debug-sign.ps1 prepare -Serial 127.0.0.1:10178

# 签名 + 验证 + 安装 + 启动
powershell -File tools\device\local-debug-sign.ps1 all `
  -UnsignedHap entry\build\default\outputs\default\entry-default-unsigned.hap `
  -Serial 127.0.0.1:10178
```

> 也可在 DevEco Studio 中打开本工程，File → Project Structure → Signing Configs 勾选 Automatically generate signature 使用官方自动签名。两条路径互不冲突。

真机发布请使用 DevEco 官方自动签名/AGC 发布证书；本地 OpenHarmony 调试链仅用于模拟器开发。

### 启动模拟器

```bash
"C:\Program Files\Huawei\DevEco Studio\tools\emulator\Emulator.exe" -start Pura90 -bootmode coldboot -hdcPort 10178
hdc tconn 127.0.0.1:10178   # SDK toolchains 下的 hdc.exe
```

---

## 已在 Pura90 实测通过

| 验证项 | 结果 |
| --- | --- |
| 安装/启动/前台运行 | ✅ 进程稳定，长时间运行无崩溃 |
| 开场页（插画/标题/标签/按钮） | ✅ 居中布局，静音/有声两种进入 |
| 3D 世界（海/天/路/山/路灯/植被） | ✅ GLES3 渲染，昼夜循环推进 |
| 五镜头切换 | ✅ 自由环绕/追随/侧面/电影/鹈鹕视角 |
| HUD（速度表/踏频/档位/里程/鱼/成就/时钟） | ✅ 实时刷新 |
| 触控按钮（左右/加速/刹车/跳/特技/铃） | ✅ 多点触控 |
| 帮助弹层 | ✅ 玻璃拟态双列键位说明 |
| 参数设置抽屉 | ✅ 原版 lil-gui 全部参数原生映射 |
| 昼夜循环（17:35 黄昏 → 夜间路灯 → 黎明） | ✅ 天空色板/路灯/月光渐变 |
| Home 后台/恢复 | ✅ Surface 不黑屏，进程保持 |
| 深链 `pelicanbike://ride?time=&cam=` | ✅ 编译通过（scheme 已注册） |

设备截图存于 `emulator/screenshots/`。

---

## 工程结构

```
harmony-PelicanBike/
├── entry/                          # HarmonyOS entry 模块（最终交付工程）
│   └── src/main/
│       ├── cpp/                    # Native C++17（完整引擎）
│       │   ├── CMakeLists.txt      # 引用 native-staging 源（单一算法源）
│       │   ├── engine.cpp/.h       # 引擎：模拟+场景+音频编排
│       │   ├── RenderScene.cpp/.h  # GLES3 场景（覆盖版：fog/bloom/exposure/scarf 开关）
│       │   ├── pelican_renderer.cpp/.h  # XComponent/EGL/VSync/TSFN
│       │   ├── napi_init.cpp       # ArkTS 桥接（静态聚合 NAPI 模块注册）
│       │   ├── touch_tracker.cpp/.h
│       │   ├── engine_types.cpp/.h  # 事件路由/成就文案/嘴部投影/音频参数
│       │   └── types/libpelican/   # ArkTS 类型声明
│       ├── ets/
│       │   ├── pages/              # PelicanBikeNativePage(@Entry) / PelicanBikePage
│       │   ├── components/         # 开场/HUD/触控/帮助/设置/Toast/特效
│       │   ├── bridge/             # libpelican.so 适配 + PNG 截图保存 + 窗口指标
│       │   ├── model/              # GameModels（设置/遥测/事件模型）
│       │   └── theme/              # 颜色/尺寸/断点
│       └── resources/rawfile/
│           └── pelican_assets.pak  # 高保真模型资源包（15.4 MB）
├── native-staging/                 # 算法单一源（被 entry 引用）
│   ├── coregame/                   # 玩法模拟（golden 全量对照通过）
│   ├── audio/                      # OHAudio 合成器（20s soak 无 NaN）
│   ├── scene/                      # GLES3 场景基座（host 测试通过）
│   └── assets/                     # PAK 加载器/SceneAssetGpu
├── ui-staging/                     # UI 开发稿（与 entry 同步）
├── integration-staging/            # 引擎整合开发稿
├── packed-assets/                  # pelican_assets.pak 源
├── generated-assets/               # 从原 H5 导出的几何/纹理（manifest+二进制）
├── tools/
│   ├── device/                     # doctor/build/install/launch/冒烟 + 本地签名
│   ├── asset-exporter/             # H5 → generated-assets（Playwright）
│   ├── asset-packer/               # generated-assets → pelican_assets.pak
│   ├── web-baseline/               # 原版 12 场景截图采集
│   ├── reference-vectors/          # golden 数值基准（SHA256 锁定）
│   ├── visual-regression/          # 网页/模拟器截图对比（12 场景）
│   └── perf/                       # PEL_PERF 协议 + soak/昼夜/36km 场景框架
├── docs/                           # 各模块文档
└── emulator/                       # 实测截图/布局/崩溃日志（开发证据）
```

---

## 玩法复刻清单

| 系统 | 状态 |
| --- | --- |
| 骑行物理（速度/巡航/刹车/横移临界阻尼/侧倾） | ✅ 逐公式移植，600帧×5场景 golden 对照 ≤1e-9 |
| 五档自动变速（86rpm 目标，68/102 边界） | ✅ 边界 probe 全对 |
| 跳跃（3.6m/s, g=13）/ 3.4s 特技 | ✅ |
| 鱼：4 车道 / 12 池 / 12% 金鱼 / +1/+5 | ✅ RNG 序列 golden 精确 |
| 14 项成就（中文 icon/title/detail） | ✅ 阈值结构全对 |
| 自动驾驶（追鱼/蛇形） | ✅ |
| 五镜头 + 8 段电影运镜 + 1.3s 混合 | ✅ |
| 昼夜循环（0.025 时/秒，七档色板） | ✅ |
| Verlet 围巾（16 段，NaN 恢复） | ✅ 10 分钟 soak |
| Gerstner 海浪（5 波，双精度取模） | ✅ 1e12 距离稳定 |
| 无限世界（7×72m 循环块） | ✅ |
| OHAudio：环境音/事件音效/生成式音乐 | ✅ 48kHz F32LE，夜去鼓，BPM 跟踏频 |
| 触控：单指 orbit/双指缩放/tap 拾取 | ✅ steady_clock 计时 |
| 截图 → PixelMap → PNG → 图库 | ✅ RGBA 翻转在 C++ 完成 |
| 深链分享 `pelicanbike://ride` | ✅ |
| 暂停/前后台生命周期 | ✅ userPaused 与 lifecycle 分离 |
| 静音进入 → 后续音乐/音量交互按需启动音频 | ✅ 与 Web 语义一致 |
| 特技同时触发 whoosh + honk | ✅ |

## 与原版的已知差异

1. 角色使用场景内程序化低模（`RenderScene` 生成），PAK 高保真模型（35,631 顶点）的 `AssetCharacterRenderer` 已完成但**未在渲染循环启用**——加载/上传/角色绑定/绘制 API 齐备，可在 `engine.cpp` 接入。
2. fog/bloom/exposure/scarf 设置已在引擎与 shader 中生效；`lookMouse`（目光跟随触点）存储但场景未消费。
3. 开场插画 Canvas 矢量绘制只完成部分形状（车轮/道路可见），完整插画待补。
4. 生成式音乐在 host 上通过 DSP 测试；模拟器上音频未做听感回归（模拟器音频设备受限）。
5. PEL_PERF 每秒采样已实现（fps/frameCpuMs/drawCalls/triangles/resources），hilog 采样框架就绪但未跑完整 soak 报告。

## 测试资产

- Golden 数值基准：`docs/reference-vectors/pelican-bike-golden.json`（SHA256 `62ab8b28…`，5×601 帧轨迹 + 51,085 数值列）
- 网页基线：`docs/web-baseline/`（12 场景 1440×900）
- 视觉对比工具：`tools/visual-regression/`（MAE/RMSE/PSNR/SSIM/ROI）
- 各模块 host 测试：coregame（1/1）、audio（2/2）、scene（通过）、assets（1/1）、integration engine（PASS）

## 文档索引

- 桥接协议：`docs/bridge-api.md`
- 设备构建/签名：`docs/device/README.md`、`docs/device/signing.md`
- 平台陷阱实录：`docs/device/runtime-findings.md`
- 资源导出格式：`docs/asset-export/README.md`、`docs/asset-loader/README.md`
- 玩法映射：`docs/coregame/README.md`
- 场景集成：`docs/scene/README.md`、`docs/integration-native/README.md`
- UI 映射：`docs/ui/README.md`
- 性能协议：`docs/performance/README.md`
