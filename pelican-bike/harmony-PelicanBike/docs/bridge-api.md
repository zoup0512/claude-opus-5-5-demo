# 鹈鹕骑行 ArkTS / Native 桥接协议

原生模块名为 `libpelican.so`，ArkTS 使用：

```ts
import * as pelican from 'libpelican.so';
```

## 生命周期

1. `initialize(options?)`：初始化桥接状态。ArkTS 应将 `getContext(this).resourceManager` 放入 `options.resourceManager`，供 Native rawfile 读取。
2. `start(withSound)`：启动模拟与渲染状态。
3. `setPaused(paused)`：暂停或恢复。暂停后 NativeVSync 不再续订；恢复后有可用 Surface 时重新请求帧。
4. `dispose()`：释放事件回调、NativeResourceManager 与运行状态。Surface/EGL 生命周期仍由 XComponent 回调安全收尾。

## 控制 API

- `setInput(name, pressed)`：设置持续输入，例如 `pedal`、`brake`、`left`、`right`。
- `triggerAction(action, x?, y?)`：触发离散动作；`x/y` 为可选归一化坐标，原生触摸 tap 会以 `pick` 动作进入同一语义。
- `setCamera(camera)`：切换镜头，例如 `follow`、`orbit`、`firstPerson`。
- `setSetting(name, value)`：设置布尔、数值或字符串选项。
- `getSnapshot()`：同步读取 HUD 快照。
- `requestScreenshot()`：请求截图；当前骨架通过 `screenshot` 事件返回占位结果，后续可接真实像素导出。

## HUD 快照

`HudSnapshot` 至少包含：

- `speedKmh`
- `cadence`
- `gear`
- `gearCount`
- `distanceKm`
- `fish`
- `achievements`
- `achievementTotal`
- `hour`
- `fps`
- `quality`
- `camera`
- `night`
- `started`
- `paused`

## 事件

`setEventCallback(callback)` 注册单一事件回调。事件 `type` 为：

- `hud`：携带 `snapshot`
- `toast`：携带 `message`
- `score`：携带 `score`、`delta`
- `screenshot`：携带 `path`、`success`
- `error`：携带 `code`、`message`

回调通过 N-API threadsafe function 从 Native 线程投递，Native 不在持有渲染状态锁时调用 ArkTS。

## XComponent 与渲染

ArkTS 页面创建 `XComponent({ id: 'pelicanSurface', type: 'surface', libraryname: 'pelican' })`。原生模块读取 `OH_NATIVE_XCOMPONENT_OBJ` 并注册 `OnSurfaceCreated`、`OnSurfaceChanged`、`OnSurfaceDestroyed` 与 `DispatchTouchEvent`。

默认帧循环使用与 Surface ID 关联的 NativeVSync。每帧显式绑定 EGL context，完成 render/swap 后解绑，再请求下一帧。暂停、Surface 销毁或 EGL 初始化错误时停止续订。
