# ArkUI 页面实现稿

本目录说明如何把 `ui-staging` 中的完整 ArkTS/ArkUI 页面合入 HarmonyOS API 24 工程。实现没有使用 WebView、HTML 或 SVG DOM；开场鹈鹕插画由 ArkUI `CanvasRenderingContext2D` 绘制，游戏画面由全屏 `XComponent` 承载。

## 文件布局

将以下目录复制到 `entry/src/main/ets/`，目录名保持不变：

- `ui-staging/pages/`
- `ui-staging/components/`
- `ui-staging/model/`
- `ui-staging/theme/`
- `ui-staging/bridge/`

入口选择：

- 真机/模拟器 Native 页面：把 `pages/PelicanBikeNativePage` 加入 `main_pages.json` 并由 Ability 加载。
- ArkUI Preview 页面：使用 `pages/PelicanBikePreview`。它显式传入 `previewMode: true`，显示 XComponent 占位说明并使用 `MockGameBridge`/Preview 系统能力。
- 复用页面容器：`pages/PelicanBikePage` 可注入任意 `GameBridge` 和 `SystemCapabilityAdapter`。

不要把 `previewMode` 在设备入口设为 `true`。设备端 `GameSurface` 使用：

```ts
XComponent({
  id: 'pelican-game-surface',
  type: 'surface',
  libraryname: 'pelican',
  controller
})
```

`libraryname: 'pelican'` 是必须项，Native 模块依赖它注入 `OH_NATIVE_XCOMPONENT_OBJ`。

## 与原 CSS 的映射

| Web 选择器/区域 | ArkUI 实现 | 说明 |
| --- | --- | --- |
| `#app, #app canvas` | `components/GameSurface.ets` | 全屏 Stack + XComponent Surface |
| `#intro` | `components/IntroOverlay.ets` | 全屏开场层、安全区与可滚动短屏布局 |
| `.intro-art` | `components/PelicanIntroArt.ets` | Canvas 矢量绘制；车轮、路面和上下浮动动画 |
| `h1`, `.sub`, `.chips`, `.cta` | `IntroOverlay` | 标题、副标题、7 标签、开始/静音按钮 |
| `.brand` | `components/BrandPanel.ets` | 左上品牌玻璃面板 |
| `.cams` | `components/CameraBar.ets` | 5 镜头横向不换行滚动栏 |
| `.tools` | `components/ToolBar.ets` | 8 工具按钮；最窄 360vp 内容不换行并允许横向滚动 |
| `.dash`, `.gauge`, `.stats` | `components/RideDashboard.ets` | Gauge 速度仪表、踏频、档位、里程、镜头 |
| `.score`, `.timebar` | `components/ScorePanel.ets` | 鱼数、成就、时刻、时间流动 |
| `.touch` | `components/TouchControls.ets` | 多点触控：左右、刹车、加速、铃、特技、跳跃 |
| `.hints` | `components/HudHints.ets` | 宽屏键盘提示 |
| `#help` | `components/HelpDialog.ets` | 原生帮助弹层 |
| `#guiHost` | `components/SettingsDrawer.ets` | 原生右侧设置抽屉，覆盖原 lil-gui 全部参数 |
| `#toasts`, `.pop` | `TransientEffects.ets`, `SystemToast.ets` | 成就 Toast、系统提示、加分飘字 |
| `.bars`, `#cut` | `components/TransientEffects.ets` | 电影黑边和闪切覆盖层 |

## 原参数完整映射

`SettingsDrawer` 覆盖源 `main.js` 的全部 GUI 参数：

- 骑行：`cruise`、`autopilot`、`autoGear`
- 时间与天气：`hour`、`timeFlow`、`dayRate`、`cloud`、`waveAmp`、`fog`
- 画面：`quality`、`bloom`、`bloomBoost`、`exposure`、`showFps`
- 鹈鹕：`helmet`、`glasses`、`scarf`、`lookMouse`
- 声音：`volume`、`music`、`musicVolume`

手机默认画质为 `medium / 均衡 / 1.25x`。

## 输入与桥接

### 持续输入

UI 语义与现有 Native 名称由 `LibPelicanPort` 映射：

- `ControlKey.ACCELERATE` → `pedal`
- `ControlKey.BRAKE` → `brake`
- `ControlKey.LEFT` → `left`
- `ControlKey.RIGHT` → `right`

触控按钮使用 `onTouch` 的 Down/Up/Cancel，彼此独立，可左右变道和加速/刹车同时按下。

### 离散动作

UI 发出 `jump`、`trick`、`bell`、`honk`、`night`、`pause`。完整 integration 使用同名动作；兼容旧骨架时，尚未实现的动作由 Native 安全忽略，不影响 UI。

事件 adapter 处理 `hud`、`toast`、`score`、`achievement`、`cameraFlash`、`seaJumper`、`screenshot`、`error`；得分事件直接使用 Native 的 `golden/x/y`，电影闪切使用 Native 的 `durationMs`。

### 相机名

- 自由环绕 → `orbit`
- 追随 → `chase`
- 侧面跟拍 → `side`
- 电影运镜 → `cine`
- 鹈鹕视角 → `pov`

adapter 读取旧骨架快照时仍兼容 `follow` / `firstPerson`，但向完整 integration 统一发送 `chase` / `pov`。

### Native 接入

`bridge/LibPelicanApiAdapter.ets` 直接导入 `libpelican.so`，再经 `LibPelicanPort` → `NativeGameBridgeAdapter` 提供给页面。它与现有 `docs/bridge-api.md` 及 `entry/src/main/cpp/types/libpelican/index.d.ts` 对齐：

- `initialize({ resourceManager, quality, camera, night })`
- `setEventCallback`
- `start`
- `setInput`
- `triggerAction`
- `setCamera`
- `setSetting(name, value)`
- `getSnapshot`
- `requestScreenshot`
- `setPaused`
- `dispose`

XComponent Surface 不做手动 NAPI 绑定；`libraryname` 自动完成原生对象注入。

## 系统能力 adapter

`HarmonySystemCapabilityAdapter` 使用 API 24 接口：

- 复制：`@kit.BasicServicesKit` 的 `pasteboard.getSystemPasteboard().setData(pasteboard.createPlainTextData(text))`
- 外链：`common.UIAbilityContext.openLink(link)`
- 沉浸式：`window.getLastWindow(context)`，然后 `setWindowLayoutFullScreen` + `setWindowSystemBarEnable`
- 截图：委托 `PngScreenshotSaver`

Preview 使用 `PreviewSystemCapabilityAdapter`，不依赖真机系统能力。

## 截图数据链

UI 不把 PixelMap 或 RGBA `ArrayBuffer` 放进 `@State`。流程是：

1. UI 调用 `GameBridge.requestScreenshot()`，`includeOverlay=false`，保持与原版一致只截 3D 游戏画面。
2. Native 的 `screenshot` 事件返回轻量元数据；目标格式为 `success/path/width/height/pixels`。adapter 同时容忍尚未附带像素的 `path/success` 事件。
3. RGBA 由回调直接传给 `PngScreenshotSaver`。`glReadPixels` 原点在左下，推荐在 C++ 生成事件前完成垂直翻转。
4. `image.createPixelMap(buffer, { size, srcPixelFormat: RGBA_8888, pixelFormat: RGBA_8888, editable: false })`
5. `image.createImagePacker().packToData(pixelMap, { format: 'image/png', quality: 100 })`
6. `@kit.CoreFileKit` 写入 `context.cacheDir` 临时 PNG。
7. `photoAccessHelper.showAssetsCreationDialog([uri], configs)` 由用户确认保存到图库。

## 分享深链

工具栏“分享”复制：

```text
pelicanbike://ride?time=17.35&cam=orbit
```

Entry 合入时，在 `module.json5` 增加 `action.system.browsable` 和 scheme/host：

- scheme: `pelicanbike`
- host: `ride`

在 `onCreate` 与 `onNewWant` 解析 `want.uri`，将参数写入：

- `AppStorage.pendingHour`
- `AppStorage.pendingCamera`

Entry 写入键名使用 `pelicanPendingHour`（无值 `-1`）和 `pelicanPendingCamera`（无值空串）。页面通过 StorageLink/Watch 消费并立即重置，未开始游戏时也会更新初始设置和镜头，避免 Watch 重入。该配置属于 Entry 集成步骤，本任务没有改动主工程配置。

## 前后台生命周期

`PelicanBikePage` 监听 `AppStorage.pelicanAppForeground`。后台会释放四个持续输入并强制暂停；前台按 `userPaused` 恢复，不会覆盖用户主动暂停。页面销毁时同样释放输入、暂停、断开 bridge 并清理定时器。

## 安全区与自动旋转

`PelicanBikeNativePage` 使用 `WindowMetricsBinder`：

- 读取主窗尺寸，写入 `AppStorage.windowWidth/windowHeight`
- 读取/监听 `TYPE_SYSTEM`、`TYPE_CUTOUT`、`TYPE_NAVIGATION_INDICATOR`
- 写入 `safeTop/safeBottom/safeLeft/safeRight`
- 页面根节点同时通过 `onAreaChange` 更新宽高

布局规则与原 CSS 一致：

- 宽度 `< 900vp`：相机栏移到第二行，仪表缩小，时间条隐藏。
- 宽度 `< 560vp`：品牌只留徽标，统计隐藏，工具按钮缩小；工具栏内容仍保持 360vp 不换行，可横向滚动。
- 宽度 `< 1180vp`：键盘提示隐藏，触控控制显示。
- 高度 `< 620vp`：开场插画缩到 150vp、标题 30vp、chips 隐藏、按钮压缩，次要 HUD 隐藏。
- 高度 `< 420vp`：开场插画和按键提示隐藏，触控垫隐藏，避免遮挡主画面。
- 横屏左右刘海/挖孔通过 `safeLeft/safeRight` 叠加到品牌、工具栏和触控区。

建议 Entry Ability 使用 `auto_rotation_restricted`，让系统自动旋转并保留受限旋转策略。

## 交互尺寸

- 工具按钮：38vp；紧凑模式 34vp；工具栏最低内容宽 360vp。
- 触控圆键：60vp，大键 72vp；紧凑模式 54/62vp。
- 开始按钮：标准高度 50vp，短屏 42vp。
- 玻璃面板圆角：14–18vp；原 CSS 主面板为 16px。
- 所有核心触控目标按不小于约 48vp 设计；紧凑工具按钮属于横向高密度工具栏，外层滚动区避免换行。

## ArkTS/API24 约束

实现刻意避免：

- `any` / `unknown`
- 无类型 JSON 透传
- 把大 `ArrayBuffer`、PixelMap 放进响应式状态
- 依赖 Web DOM/WebView
- 通过对象字面量猜测 Native 事件

桥接使用具名 class、enum、显式回调类型和逐字段复制。若主工程的 `libpelican` 声明升级，先同步 `ui-staging/bridge/libpelican.d.ts` 与 `LibPelicanApiAdapter`，再编译。
