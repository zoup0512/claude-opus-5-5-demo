# Native integration staging

本目录说明 `integration-staging/native` 的可替换集成结果。实现保持 `native-staging/coregame`、`native-staging/audio`、`native-staging/scene` 为唯一算法源，不修改它们。

## 1. 交付内容

`integration-staging/native` 可整体作为 `entry/src/main/cpp` 的候选替换源：

- `CMakeLists.txt`：以相对路径 `add_subdirectory` 复用 coregame/audio，以 scene 暴露的源清单直接编译 scene；最终迁入 `entry/src/main/cpp` 后，相对根目录会从 `../..` 变为 `../../../..`，见下方合入清单。
- `engine.*`：持有 `pelican::GameSimulation`、`pelican::scene::RenderScene`、按需创建的 `pelican::audio::AudioEngine`。
- `engine_types.*`：HUD、事件路由、14 项中文成就、嘴部屏幕投影、音频参数映射。
- `pelican_renderer.*`：XComponent/EGL/NativeVSync、线程安全 surface generation/in-flight 协调、下一帧截图、TSFN、PEL_PERF。
- `touch_tracker.*`：基于 `steady_clock` 的 tap/drag/pinch；直接连接 scene 的 orbit/pick。
- `napi_init.cpp`：完整 ArkTS bridge 协议。
- `types/libpelican/index.d.ts`：包含截图 ArrayBuffer 和新增事件的建议声明。
- `tests/engine_tests.cpp`：纯 C++ host 测试，不要求真实 EGL/GLES。

## 2. CMake 复用方式

当前 staging 位置下，`CMakeLists.txt` 通过：

```cmake
get_filename_component(PELICAN_REPO_ROOT "${CMAKE_CURRENT_LIST_DIR}/../.." ABSOLUTE)
add_subdirectory("${PELICAN_REPO_ROOT}/native-staging/coregame" ...)
add_subdirectory("${PELICAN_REPO_ROOT}/native-staging/audio" ...)
include("${PELICAN_REPO_ROOT}/native-staging/scene/CMakeLists.txt")
```

因此 simulation、DSP、几何、shader、scene 逻辑不会复制到 integration 目录。scene 的 CMake 本身仅导出 `PELICAN_SCENE_SOURCES`，所以 integration target 用 `target_sources` 等价方式编译原文件。

## 3. 复制/合入清单

1. 备份现有 `entry/src/main/cpp`。
2. 将 `integration-staging/native` 中除 `build-*` 外的源码、`CMakeLists.txt`、`types` 复制到 `entry/src/main/cpp`。
3. 修改复制后的 CMake 根定位：

   ```cmake
   get_filename_component(PELICAN_REPO_ROOT "${CMAKE_CURRENT_LIST_DIR}/../../../.." ABSOLUTE)
   ```

   这是从 `entry/src/main/cpp` 回到项目根的路径；integration staging 原位则仍使用 `../..`。
4. 保留 entry `build-profile.json5` 的 `arm64-v8a`、`x86_64` ABI 配置，无需改根配置。
5. 用本目录 `types/libpelican` 覆盖 entry 的同名类型目录。
6. ArkTS 若要消费真实截图，按 `ScreenshotEvent.pixels/width/height` 处理，不再读取旧的 `path` 字段。
7. ArkTS 可选择消费 `achievement`、`cameraFlash`、`seaJumper`；不消费时不会影响 simulation/render。
8. 页面前后台继续调用 `setPaused(true/false)`。Surface 销毁还会单独暂停音频，Surface 重建后按逻辑暂停状态恢复。
9. 合入后执行两个 ABI 的完整 native build，再在设备/模拟器验证 Surface 重建、前后台、截图和音频。

## 4. Bridge 行为

- `initialize(options)`：接收 `resourceManager`，并支持 quality/camera/night/hour 及完整设置集作为初始值。
- `start(withSound)`：只有 `withSound === true` 才构造并启动 `AudioEngine`；静音启动不创建音频对象。
- `setInput`：支持 `left/right/up/down`，兼容现有 `pedal/brake/accelerate`。
- `triggerAction`：支持 `jump/trick/bell/honk/night/flow/pick`。
- `setCamera`：支持 coregame 的 `orbit/chase/side/cine/pov`，兼容 `follow` 与 `firstPerson` 别名。
- `setSetting`：支持 cruise/autopilot/autoGear/hour/night/dayRate/timeFlow/cloud/waveAmp/fog/quality/bloom/bloomBoost/exposure/showFps/helmet/glasses/scarf/lookMouse/volume/music/musicVolume。
- `getSnapshot`：字段与 d.ts 一致；gear 对 UI 输出为 1-based；fish 沿用 Web HUD 语义表示分数。
- HUD 事件以 100 ms 周期发送。
- score 事件带 top-left normalized `x/y`，由 core camera 快照投影嘴部锚点；投影不可用时回退到 `(0.56, 0.34)`。
- 14 项 achievement 事件映射 Web 版中文 icon/title/detail。
- screenshot 在请求后的下一次 render frame、swap 前调用 `RenderScene::screenshotPixels()`；scene 已将 GLES bottom-left 数据翻转成 top-left RGBA8。

## 5. Scene 设置映射与 staging 限制

直接映射：

- `quality` -> `RenderScene::initialize(..., Quality)`；变化时在 render thread、当前 EGL context 下 destroy/reinitialize。
- `cloud` -> `RenderState.cloudCover`。
- `waveAmp` -> coregame setting 与 `RenderState.waveAmplitude`。
- `helmet/glasses` -> `RenderState` 对应字段。
- camera snapshot -> `RenderState.cameraPosition/cameraTarget/FOV`；orbit 使用 scene 内部 orbit camera。

已存储但 staging scene 暂无公开运行时入口：

- `fog`：scene 当前使用内部固定 fog density。
- `bloom`、`bloomBoost`、`exposure`：scene 当前由 quality 和天空 palette 内部决定。
- `scarf`：scene 当前总是更新/绘制 scarf。
- `lookMouse`：触摸 orbit 已接通，但 scene 没有眼球目标公开 API。
- `showFps`：桥接保存，HUD 始终提供 fps，由 ArkTS 决定是否显示。

这些值不会被丢弃；adapter 保持协议稳定，待 staging scene 暴露字段后只需补 `RenderState` 映射。

另一个 staging 限制是 coregame 的 fish 数据尚未传入 `RenderScene`；当前 scene 使用自己的视觉 fish 动画，而得分、成就与音效严格来自 coregame。

## 6. Touch、pick 与音效

- 单指移动超过阈值会切到 orbit，并调用 `RenderScene::orbitDrag`。
- 双指使用相邻距离比例调用 `RenderScene::orbitZoom`。
- tap 调用 `RenderScene::pick`：bell/bicycle -> bell，pelican -> honk，sea -> `seaJumper` 事件并播放 splash。
- coregame 事件映射：bell/honk/gulp/golden gulp/jump-trick whoosh/landing thump。
- 连续音频参数按 20 Hz 更新；暂停和 Surface 丢失会暂停 OHAudio。

## 7. EGL/VSync/线程安全

每帧严格执行：

1. 检查 surface generation 与生命周期状态。
2. `eglMakeCurrent`。
3. `GameSimulation::advance`、scene update/render、可选 screenshot。
4. `eglSwapBuffers`。
5. `eglMakeCurrent(...EGL_NO_*)` 解绑。
6. 仅在 generation 未变且仍 active 时请求下一帧。

Surface resize/destroy 与 `dispose()` 会先递增 generation、停止续订、等待 `inFlightRenders == 0`，随后在旧 context current 时销毁 scene，再销毁 EGL/VSync。所有创建失败路径都回收已创建资源。

TSFN 为 bounded/nonblocking 队列。未注册回调或 `napi_queue_full` 等入队失败时，native payload 会立即释放。

N-API 模块严格使用官方模板式静态聚合初始化：`static napi_module g = {..., "pelican", ...};`，constructor 只执行 `napi_module_register(&g)`，不使用返回结构体的动态全局初始化。`AttachXComponent` 先调用 `napi_has_named_property(OH_NATIVE_XCOMPONENT_OBJ)`；普通 ArkTS import 缺少该属性时无异常返回，后续 `XComponent({ libraryname: 'pelican' })` 加载时再注册 Surface 回调。

## 8. PEL_PERF

每秒 hilog 一行：

```text
PEL_PERF {"v":1,"event":"sample",...}
```

至少包含 `fps`、`frameCpuMs`、`drawCalls`、`triangles`、`resources`；当前 scene 未实现 GPU timer query，因此不写 `frameGpuMs`，符合现有 schema 的可选字段约定。

## 9. rawfile asset 可选钩子

`initialize` 已安全持有 `NativeResourceManager`，`PelicanRenderer::ReadRawFile` 提供完整 open/read/close 钩子。当前 scene/audio 都是程序化资源，不要求 rawfile 包。

若以后加入纹理、mesh 或采样音频：

1. 放入 `entry/src/main/resources/rawfile/pelican/...`。
2. 只在非音频回调线程读取。
3. 将字节传给 integration adapter 或新增 scene/audio decode 层。
4. 保持 `resourceManager_` 的 read 与 release 在 renderer mutex 保护下，避免 dispose 竞态。

## 10. 已执行验证

- Windows host，mock GLES，纯 C++：`pelican_engine_tests` 通过。
- Harmony clang x86_64：完整编译并链接 `libpelican.so` 通过。
- Harmony clang arm64-v8a：完整编译并链接 `libpelican.so` 通过。

构建输出目录是临时验证产物，不应复制进 entry。
