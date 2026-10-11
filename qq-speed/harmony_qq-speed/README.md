# 飞车 3D · HarmonyOS 原生版

QQ飞车同人 3D 竞速游戏的 **鸿蒙（HarmonyOS）原生 App** 复刻，由 H5/Three.js 版本（`qq-speed`）移植而来。
无任何外部资源：全部模型、地形、贴图效果、音乐与音效均由程序实时生成，与原版理念一致。

## 玩法（与 H5 版一致）

- **4 张赛道**：11城（塔桥/摩天楼/蓝色霓虹加速带）、情迷爱琴海（白墙蓝顶/发卡弯/隧道）、法老金字塔（沙丘跳台/神殿隧道/绿洲）、雪地大冒险（8 字立交/冰雪隧道/雪场飘雪）
- **2 种模式**：竞速（漂移集气/小喷/双喷/氮气）、道具（导弹/香蕉皮/天使/磁铁/氮气，按名次加权抽取）
- **6 个 AI 对手**：三档水平（新手/熟练/车神），赛车线走内线、弯前压速、直道放氮气、橡皮筋机制
- **车辆物理**：漂移角度/抓地回正/腾空与落地喷/坡度影响/护栏碰撞与刮擦/加速带，手感参数 1:1 保留原版
- 3 种追尾视角、起步加速、倒计时 GO、圈速与最佳圈、结算统计（漂移/小喷/完美/双喷/氮气/最高时速/碰撞）

### 触屏操作

| 按钮 | 作用 |
| --- | --- |
| ◀ ▶ | 转向（比赛中自动油门，与 H5 触屏版一致） |
| 漂移 | 按住 + 方向漂移集气，松开回正瞬间点「小喷」触发小喷（越早越「完美」） |
| 氮气/道具 | 竞速：放氮气；道具模式：使用当前道具 |
| 小喷 | 漂移结束窗口/落地窗口内点按 |
| 换位 | 道具模式下交换两个道具槽 |
| 刹 | 刹车/倒车 |
| 复位 / 视角 | 复位到赛道中心 / 切换 3 种镜头 |
| ⏸ | 暂停（继续/重新开始/返回大厅） |

小喷 + 氮气叠加 = **双喷**；倒计时 GO 出现瞬间点「小喷」= 起步加速。

## 工程结构

```
harmony-QQSpeed/
├─ AppScope/                     应用级配置与图标
├─ entry/src/main/
│  ├─ ets/
│  │  ├─ entryability/           EntryAbility
│  │  ├─ pages/Index.ets         主页面：菜单 / HUD / 触控 / 结算（原生 ArkUI）
│  │  ├─ common/                 Util（数学/RNG/噪声）、Config（赛道/车漆/模式数据）
│  │  ├─ game/                   游戏逻辑（与渲染无关，纯 ArkTS）
│  │  │  ├─ Track.ets            赛道中心线（闭合向心 Catmull-Rom + 弧长均匀重采样 + 空间哈希投影）
│  │  │  ├─ Vehicle.ets          玩家车物理（TUNE 手感参数 1:1）
│  │  │  ├─ AI.ets               AI 车手
│  │  │  ├─ Items.ets            道具系统
│  │  │  ├─ Effects.ets          粒子池 / 轮胎印 / 飘字 / 速度线
│  │  │  ├─ Audio.ets            程序化音频（PCM 合成 → AudioRenderer 回调写入）
│  │  │  └─ GameApp.ets          引擎：状态机/主循环/相机/碰撞/排名/渲染编排
│  │  └─ render/                 自研 Canvas 3D 渲染器
│  │     ├─ Renderer.ets         视锥投影 + 近裁剪 + 背面剔除 + 画家排序 + 调色板雾化；天空/远山/水面/粒子
│  │     ├─ Mesh.ets             面 soup 网格与 3x4 矩阵（盒/棱柱/锥便捷构建）
│  │     ├─ Palette.ets          颜色 × 光照档 × 雾档 字符串缓存（渲染期零字符串拼接）
│  │     ├─ Terrain.ets          高度场（基础地形 + 赛道削填压平）+ 环形 LOD 网格
│  │     ├─ TrackMesh.ets        路面/标线/护栏/路缘/起点线/加速带/桥墩/隧道/路肩（分块两级 LOD）
│  │     ├─ CarModel.ets         低多边形赛车（部件层级矩阵 + 车轮转向/滚动）
│  │     └─ Props.ets            四图布景（楼群/塔桥/飞艇/热气球/白房/帆船/风车/金字塔/狮身人面像/雪松…）
│  └─ resources/                 字符串/颜色/图标/页面注册
├─ tools/                        gen_icons.js（图标生成）、sim_check.ts（逻辑仿真测试）
└─ build-profile.json5 等        hvigor 工程配置（API 12）
```

## 渲染方案说明

H5 版基于 three.js/WebGL；本工程在纯 ArkTS 环境下实现了一套**软件级 3D 渲染器**，绘制在 ArkUI `Canvas` 上：

- 世界 → 视图 → 透视投影手写实现；近平面 Sutherland-Hodgman 裁剪、屏幕空间背面剔除、包围球/距离剔除
- 画家算法按视深排序填充多边形；静态面烘焙世界坐标与光照（平行光 + 环境光），活动物体（车辆/道具）按朝向旋转法线做动态光照
- 调色板把「基色 × 光照档 × 雾档」预生成为字符串缓存，渲染循环内只查表，避免每帧字符串拼接
- 地形用环形 LOD（近 20m 格 → 远 180m 格），赛道分块 + 远近两级 LOD，保证手机上 ~30-60fps（三档画质可调绘制距离与分辨率）
- 程序化贴图（沥青噪点/石板砖缝等）以平直色块 + 标线几何 + 明暗节奏近似，保持原版低多边形画风

音频同样全程序化：引擎（锯齿+方波过 LowPass 换挡模拟）、胎噪/风噪（滤波噪声）、一次性音效（双二阶包络振荡器）、4 首 BGM（前瞻调度 16 分音符步进音序器），合成 PCM 后经 `AudioRenderer` 回调直写。音频初始化失败时游戏照常运行（静音）。

## 构建

### 方式一：DevEco Studio（已在 DevEco 26.0 / HarmonyOS SDK 26 API26 上验证通过）

1. 安装 **DevEco Studio**，`File → Open` 选择本目录 `harmony-QQSpeed`
2. 登录华为账号后 **File → Project Structure → Signing Configs → 勾选 Automatically generate signature**
   （生成调试证书到 `~/.ohos/config/`，同时自动填充 `build-profile.json5` 的 `signingConfigs`）
3. 连接手机（开发者模式 + USB 调试授权），Run 'entry' 即可安装启动
4. 注意：`compatibleSdkVersion` 需与安装的 SDK 匹配（当前为 `6.1.1(24)`，随 DevEco 版本可能需调整）；
   **不要**显式写空的 `targetSdkVersion`（会报「值不正确」）

命令行等价操作（DevEco 自带工具链）：

```bash
export DEVECO_SDK_HOME='C:\Program Files\Huawei\DevEco Studio\sdk'
export PATH="/c/Program Files/Huawei/DevEco Studio/tools/node:$PATH"
'/c/Program Files/Huawei/DevEco Studio/tools/hvigor/bin/hvigorw.bat' \
  --mode module -p module=entry@default -p product=default -p buildMode=debug assembleHap --no-daemon
# 产物（已用 signingConfigs 里的 AGC 证书签好）:
#   entry/build/default/outputs/default/entry-default-signed.hap

bash tools/install_device.sh   # hdc 安装 → 启动 → 进程/日志检查
```

### 方式二：纯命令行（无需 DevEco，适合 OpenHarmony 设备/模拟器）

工具链落在 `D:\harmonyos-tools`（OpenHarmony 5.0.0 公共 SDK + HarmonyOS commandline-tools 5.0.5，均来自公开镜像）：

```bash
# 编译（hvigor 5.10.3 + HarmonyOS SDK API 13，自动使用自带 Node 18）
export PATH="/d/harmonyos-tools/cli/command-line-tools/bin:$PATH"
cd /d/Code/workspace/harmony/harmony-QQSpeed
cmd //c "hvigorw.bat --mode module -p module=entry@default -p product=default -p buildMode=debug assembleHap --no-daemon"
# 产物: entry-default-unsigned.hap

# 签名（工具链自带 OpenHarmony 官方签名材料）
bash tools/sign_official.sh entry/build/default/outputs/default/entry-default-unsigned.hap com.riba2534.qqspeed3d

# 部署真机（需先在手机上允许 USB 调试）
bash tools/install_device.sh
```

> **签名结论**（实测）：
> - 官方 OpenHarmony 材料签名的包 → 可装 OpenHarmony 设备（Dayu200 等开发板）；
>   **HarmonyOS NEXT 商用手机（实测 7.0.0/API 26）拒装**：`fail to verify pkcs7 file`
> - NEXT 手机必须用 DevEco 自动签名（AGC 调试证书，绑定设备 UDID + 华为账号），或到
>   AppGallery Connect 手动创建（CSR 已备好：`tools/sign/agc/app-debug.csr`，配合 `tools/sign_agc.sh`）。

### hdc 与工具位置

| 工具 | 路径 |
| --- | --- |
| hdc.exe | `D:\harmonyos-tools\sdk\windows\extracted\toolchains\toolchains\hdc.exe` |
| DevEco 26 hvigor/SDK | `C:\Program Files\Huawei\DevEco Studio\tools\hvigor`、`...\sdk`（API 26） |
| commandline-tools | `D:\harmonyos-tools\cli\command-line-tools`（hvigor 5.10.3 / SDK API 13） |
| hap-sign-tool | `D:\harmonyos-tools\sdk\windows\extracted\toolchains\toolchains\lib\hap-sign-tool.jar` |
| OpenHarmony 官方签名材料 | 同 `lib/` 下 `OpenHarmony.p12`（口令 123456，需显式传 `-keyPwd`）等 |

### 真机验证记录（JUY-AL50 · HarmonyOS 7.0.0 · API 26 · 2406×1080）

安装启动 ✓ · 菜单/滚动/选择 ✓ · 倒计时→比赛 ✓ · 排名/圈数/计时/小地图/集气/N₂O HUD ✓ ·
触控按钮 ✓ · 暂停菜单 ✓ · hilog 无 JS 异常 ✓

### 性能优化（畅享90 Plus 实测，hilog `[PERF]` 采样）

左上角常显 `FPS/面数/填充数` 叠层；每 120 帧 hilog 输出各阶段耗时。首轮实测瓶颈为
几何+背景绘制 39~73ms/帧（约 12~18fps），经以下优化后 **流畅档 20~32fps（典型 24~28）**：

| 优化项 | 效果 |
| --- | --- |
| 深度量化 256 桶计数排序（替代比较排序）+ 桶内按色分组合批 fill | flush 阶段 fills 1900+→300~860 |
| 远山/云按朝向 6° 分桶缓存 Path2D，俯仰/高度用 translate 补偿 | sky 阶段 18~23ms → 3.8~4.9ms |
| 天空/水面渐变对象按地平线 48px 分桶缓存 | 消除每帧 createLinearGradient |
| 地形色量化 6 级/通道 + 视锥余弦剔除 | 地形面大量同色可合批，剔除 ~50% 格子 |
| 赛道标线 8 采样/护栏路肩 4 采样合段；远层 10 采样 | 赛道面数 ≈3× 削减 |
| 道具按 260m 空间瓦片分块 + 视距按画质分级(550/900/1300m) | 城区瓦片整片剔除 |
| 车辆：远车简化车身(18面)/车轮 6 边形/矩阵就地复用/名牌限距隔帧 | car 阶段 14 → 2~8ms |
| 粒子矩形化、轮胎印单路径、速度线合批 | parts <2ms |
| 画质→Canvas 分辨率缩放(62%/80%/100% 组件尺寸 + scale 放大) | 像素填充量按档降低 |
| 帧率自动降档：8 秒后慢帧(>33ms)占比 >55% 持续 3s 自动降一档画质并提示 | 低端机免设置稳定运行 |
| 音频：正弦查表/包络乘法衰减/复用混音缓冲 | 合成热点降载 |

> 已到 ArkTS + Canvas 软渲染的实用上限（帧循环纯 JS 解释执行）。如需 60fps，
> 需将渲染器热循环（投影/地形/光栅化）迁移到 NDK C++（XComponent + NativeWindow），
> 工程结构已按渲染/逻辑分离，迁移点集中在 `render/` 目录。

## 逻辑验证（无 SDK 环境下）

`tools/sim_check.ts` 将纯逻辑模块（赛道几何/车辆物理/AI/道具）打包后在 Node 中仿真：

```bash
cd tools && npx esbuild sim_check.ts --bundle --platform=node --format=cjs \
  --loader:.ets=ts --resolve-extensions=.ets,.ts,.js --outfile=sim.cjs && node sim.cjs
```

已验证：四图曲线穿过全部控制点（偏差 < 0.8m）、无 NaN、AI 90s 完整跑 ~2 圈（均速 ~52m/s）、
玩家自动驾驶含漂移/集气/小喷/氮气均速 ~60m/s、道具拾取/隐匿/重生/消耗正确。

## 致谢

非官方同人作品，致敬《QQ飞车》。原 H5 版本来自 [riba2534/claude-opus-5-5-demo](https://github.com/riba2534/claude-opus-5-5-demo)。
所有模型、贴图、音乐均为程序实时生成，不含任何官方资源。
