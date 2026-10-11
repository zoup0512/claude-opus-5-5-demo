# 运输船CF · HarmonyOS 原生版

穿越火线经典地图「运输船」3D 团队竞技 FPS 的 HarmonyOS NEXT 原生复刻。
移植自 Web 版项目 `cf-transport-ship`（Three.js + WebAudio），本工程为 **ArkTS + C++(NDK OpenGL ES 3)** 原生实现。

## 玩法

- 团队竞技：潜伏者（BL）vs 保卫者（GR），率先达到目标击杀数（30/50/100）或 10 分钟结束时比分高者获胜
- 武器：AK-47 / M4A1 / AWM（狙击，需开镜）/ MP5 + 沙漠之鹰 + 军刀（轻/重击，背刺加倍）+ 高爆手雷
- CF 手感：首发精准、连射上跳后左右摆、蹲下更稳、移动/跳跃散布增大、木箱可穿射（伤害衰减）
- 机器人 AI：四种难度（反应时间/瞄准误差/压枪/走位），架点、游走、绕后、听声辨位、手雷压制
- 地图：运输船全船复刻——出生舱壁双门、两侧集装箱管道（单向）、二楼架枪位、中路 V 形斜放集装箱、吊机与悬挂集装箱（随风摆动）、驾驶室上层建筑、船体与海浪（Gerstner 波 + 泡沫尾迹）
- 系统：出生保护 3 秒（开火解除）、连杀播报（双杀~超神）、爆头/穿墙/刀杀徽章、击杀信息流、旋转雷达（队友箭头/敌人红点需开火暴露）、计分板、死亡镜头、蹲跳上箱

## 触屏操作

| 区域 | 操作 |
|---|---|
| 屏幕左 42% | 虚拟摇杆移动（按住任意位置出现） |
| 屏幕右侧滑动 | 转视角 |
| 右下大按钮 | 开火（按住连发） |
| 镜 / 跳 / 蹲 | 开镜（狙击）/ 跳跃 / 蹲下切换 |
| 换弹 / 切枪 | R 换弹 / Q 快速切换上一把 |
| 左上 ≡ / 榜 / 换枪 | 暂停菜单 / 计分板 / 更换主武器 |

## 工程结构

```
harmony-cf-transport-ship/
├── AppScope/                        应用级配置与图标
├── build-profile.json5              根构建配置（SDK 5.0.0(12)+，C++ 选项）
├── entry/
│   ├── src/main/cpp/                C++ 渲染层
│   │   ├── napi_init.cpp            NAPI 模块注册 + XComponent surface 生命周期
│   │   ├── renderer.cpp/.h          EGL + GLES3 前向渲染管线（含全部着色器）
│   │   └── types/libgameRenderer/   ArkTS 侧类型声明
│   └── src/main/ets/
│       ├── pages/Index.ets          主页面：XComponent + HUD + 触控
│       ├── pages/Menus.ets          菜单/暂停/结算/换枪面板
│       └── game/                    游戏逻辑（全部 ArkTS）
│           ├── math3d.ets           Vec3/Mat4 数学库（列主序）
│           ├── physics.ets          OBB 碰撞世界 + A* 寻路网格（与原版一致）
│           ├── weapons.ets          武器数据/散布/后坐模型（数值与原版一致）
│           ├── actor.ets            角色基类：移动/武器状态机
│           ├── player.ets           玩家输入状态
│           ├── bots.ets             机器人 AI
│           ├── character.ets        士兵模型（19 骨骼刚性蒙皮）+ 程序动画 + 命中盒
│           ├── guns.ets             7 种枪械程序化建模
│           ├── geometry.ets         盒/圆柱/球/胶囊/ear-clipping 几何生成
│           ├── textures.ets         全程序化纹理（像素运算生成）
│           ├── mapdata.ets          运输船地图构建（几何合批 + 碰撞体）
│           ├── effects.ets          粒子/贴花/曳光/枪口火焰/爆炸
│           ├── viewmodel.ets        第一人称武器动画（弹簧后坐/换弹/近战/投掷）
│           ├── audio.ets            程序化音效合成 + AudioRenderer 混音
│           └── game.ets             对局主控：流程/战斗/帧打包/渲染提交
└── tools/check.js                   开发期静态自检脚本
```

## 架构说明

**ArkTS 负责 100% 游戏逻辑**，C++ 只做 GPU 绘制。每帧 ArkTS 把场景快照打包进一个 `Float32Array`（相机矩阵、19×16 骨骼矩阵、公告板、粒子），通过 NAPI 零拷贝传给原生层 `renderFrame`：

```
ArkTS 游戏循环(setInterval 60Hz)
  ├─ 模拟：输入→移动/物理→AI→武器→伤害
  ├─ 打包：相机/太阳/雾 + 士兵骨骼 + 动态网格(手雷/吊箱) + 公告板 + 粒子
  └─ nrender.renderFrame(frame)
C++ 渲染管线
  天空(渐变+太阳+云) → 静态网格(按材质合批) → 蒙皮士兵+第三人称枪
  → 动态网格 → 海洋(Gerstner+泡沫) → 透明公告板(按纹理分桶) → 第一人称武器层(独立清深度)
```

- 士兵为 19 骨骼刚性蒙皮，骨骼矩阵在 ArkTS 侧计算，GPU 用 `uBones[24]` 数组蒙皮
- 命中判定（头/胸/腹/臂/腿）在 CPU 侧用骨骼世界矩阵 + OBB slab 测试
- 音效全部由噪声/扫频/金属泛音合成 PCM，AudioRenderer 流式输出，按距离衰减+声像+低通
- 为规避手写几何的三角形绕向差异，渲染层统一双面绘制（此场景复杂度下开销可接受）

## 构建与运行

1. 使用 **DevEco Studio 5.0.5 及以上** 打开工程根目录（需 HarmonyOS NEXT SDK，API 12+）
2. 首次打开等待 hvigor 同步（会拉取 `libgameRenderer.so` 本地依赖并配置 CMake）
3. 连接真机（建议 Mate/P 系列等较新机型保证 GLES3 性能），点击 Run
4. 无需签名即可在真机调试运行（Debug 自动签名）

命令行构建：

```bash
hvigorw assembleHap --mode module -p product=default
```

## 与 Web 版的差异（简化项）

- 材质简化：无法线/粗糙度贴图，靠程序纹理 + 顶点色 + 着色器近似（无阴影贴图、无泛光后处理，屏幕特效由 ArkUI 叠加层实现）
- 枪械为单网格整体动画（弹匣/枪栓不再分离动画）；武器图标未做 3D 渲染
- 语音播报（Go go go / Headshot）以提示音 + 文字横幅代替
- 远景集装箱堆场数量略微精简；海鸥/雷达天线旋转等装饰动画未移植

## 致谢

本工程基于 [riba2534](https://github.com/riba2534) 的网页版 [claude-opus-5-5-demo（运输船 3D）](https://github.com/riba2534/claude-opus-5-5-demo)移植，玩法设计、地图布局、武器数值与 AI 行为均源自原项目，在此致谢。移植过程对渲染与音频层做了原生重写（见上文差异说明），按 Apache-2.0 许可开源。

## 已知注意事项

- 首次加载需生成全部纹理与几何（约 2~4 秒），加载进度条提示当前步骤
- 若 XComponent surface 尚未就绪，渲染调用会被原生层安全跳过
- 帧率显示在比分栏右侧；中端机型如帧率偏低，可在设置中降低对战规模
