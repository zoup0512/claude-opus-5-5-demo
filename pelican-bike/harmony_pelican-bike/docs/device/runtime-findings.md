# Pura90 原生运行验证记录

## 已验证环境

- HarmonyOS Emulator：Pura90，HarmonyOS 6.1.1 / API 24，x86_64
- HDC：`127.0.0.1:10178`
- 分辨率：1320 × 2856
- 图形能力：OpenGL ES 3.2，GLSL ES 3.10
- 应用：`com.riba2534.pelicanbike/EntryAbility`

## 已完成的设备验证

最小 Stage + ArkTS + NAPI + XComponent + EGL ES3 + NativeVSync 骨架已在 Pura90 上完成：

1. 项目专属调试证书/profile 的 bundleName 与模拟器 UDID 校验通过。
2. signed HAP 安装成功。
3. Ability 前台启动成功。
4. XComponent 中的 EGL ES3 动画以约 59 FPS 呈现。
5. ArkUI HUD 与触控按钮叠加正常。
6. 点击控制、暂停/恢复、Home 后重新前台，进程 PID 保持不变，Surface 未黑屏。
7. `snapshot_display` 成功输出 1320 × 2856 JPEG。

设备截图：

- `emulator/screenshots/pelican-minimal.jpeg`
- `emulator/screenshots/pelican-minimal-after.jpeg`

## 发现并修复的平台陷阱

### N-API 模块必须静态聚合初始化

不要这样写：

```cpp
napi_module CreateModule();
napi_module gModule = CreateModule();

__attribute__((constructor)) void RegisterModule()
{
    napi_module_register(&gModule);
}
```

`constructor` 与 C++ 动态全局初始化的执行顺序可能导致注册时 `gModule` 仍为全零结构。Pura90 日志表现为：

```text
Name mismatch: default/pelican != default/
LoadNativeModule init module failed
```

必须使用官方模板式静态聚合初始化：

```cpp
static napi_module gModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "pelican",
    .nm_priv = nullptr,
    .reserved = {nullptr, nullptr, nullptr, nullptr},
};

extern "C" __attribute__((constructor)) void RegisterModule()
{
    napi_module_register(&gModule);
}
```

### 普通 ArkTS import 不一定带 XComponent 对象

同一个 `.so` 会先因 ArkTS import 初始化，此时 `exports` 未必包含 `OH_NATIVE_XCOMPONENT_OBJ`。直接 `napi_get_named_property` 后 `napi_unwrap` 会留下 pending exception，整个 Native 模块导出会变成 `undefined`。

必须先调用：

```cpp
bool hasNativeObject = false;
napi_has_named_property(env, exports, OH_NATIVE_XCOMPONENT_OBJ, &hasNativeObject);
if (!hasNativeObject) {
    return exports;
}
```

之后由 `XComponent({ libraryname: 'pelican' })` 的加载路径取得并注册 Surface 回调。

### ArkTS Native 模块使用默认导入

官方 Native C++ 模板采用：

```ts
import pelican from 'libpelican.so';
```

不要假设 namespace import 在所有 HarmonyOS 版本上的运行时行为都相同。

### Git Bash 与 HDC 路径转换

设备路径 `/data/...` 在 Git Bash 中可能被 MSYS 自动转换为 Windows 路径。对含设备绝对路径的命令使用：

```bash
MSYS_NO_PATHCONV=1 hdc ...
```

本机 API 24 的 `snapshot_display` 输出 JPEG：

```bash
hdc shell snapshot_display -f /data/local/tmp/pelican.jpeg
hdc file recv /data/local/tmp/pelican.jpeg D:\path\pelican.jpeg
```

## 日志说明

模拟器的 DGLES 服务会输出大量 `null gpu context` / `createimage with ctx null` 噪声，不能单独据此判断应用 EGL 失败。以以下证据为准：

- 应用进程持续存在；
- Ability 处于 FOREGROUND；
- XComponent 画面持续更新；
- App 自定义 error 事件/Tag 无错误；
- 截图中 Surface 与 ArkUI 同时正常显示。
