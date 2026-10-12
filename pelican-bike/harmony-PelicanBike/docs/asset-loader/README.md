# Pelican Assets Native Loader

本目录说明 `generated-assets` 到 Harmony Native C++ / OpenGL ES 的完整打包与加载路径。实现文件只位于：

- `tools/asset-packer`
- `native-staging/assets`
- `packed-assets`
- `docs/asset-loader`

没有修改 `entry`、`native-staging/scene` 或根配置，也没有把 PAK 复制到 `entry`。

## 已生成文件与体积

| 项目 | 字节数 |
| --- | ---: |
| 原始 manifest JSON | 532,044 |
| manifest 引用的 geometry / RGBA8 texture / instances payload | 15,340,540 |
| `packed-assets/pelican_assets.pak` | 15,429,392 |
| PAK 索引、字符串、对齐与校验开销 | 88,852 |
| PAK 相对 payload 开销 | 0.58% |

PAK 不含辅助 PNG，也不含 532 KB JSON。设备端只解析固定宽度小型二进制索引；几何、RGBA8 和实例矩阵保持原始 little-endian payload，可零拷贝暴露给 CPU，上传 GPU 时只发生 GLES 所需的一次复制。

当前 PAK SHA256：

```text
b9a8423a3d0d11211d93209004e2f86206c41b5e3fd6b19ae24abf8960adbf83
```

源 manifest SHA256 被写入 PAK header，供构建产物追踪。

## 打包

无需 npm 依赖：

```powershell
node D:\workspace\My\harmony\harmony-PelicanBike\tools\asset-packer\pack.mjs
```

也可显式指定路径：

```powershell
node D:\workspace\My\harmony\harmony-PelicanBike\tools\asset-packer\pack.mjs `
  --manifest D:\workspace\My\harmony\harmony-PelicanBike\generated-assets\manifest.json `
  --output D:\workspace\My\harmony\harmony-PelicanBike\packed-assets\pelican_assets.pak
```

打包器会：

1. 读取 manifest，验证 `files[]` 中全部 153 个引用（143 个运行时 buffer + 10 个辅助 PNG）。
2. 检查路径不逃逸 manifest 目录、精确 byteLength 与 SHA256，并交叉核对 `buffers[]`/texture raw/PNG 元数据。
3. 检查几何 slice、float finite、uint32 index 范围、group/draw range、纹理 RGBA8 尺寸、实例矩阵、节点与材质引用。
4. 由 anchors、层级、对称关系、位置与 morph 关系生成 stable role 表。
5. 原子写入一个 `pelican_assets.pak`。

## PAK v1 格式

所有整数与 IEEE-754 float32 均为 little-endian。包要求至少 4 字节对齐的内存起点。

### Header（96 bytes）

| Offset | 类型 | 含义 |
| ---: | --- | --- |
| 0 | char[8] | magic `PELICAN\0` |
| 8 | u16 | container version = 1 |
| 10 | u16 | binary index version = 1 |
| 12 | u16 | header size = 96 |
| 14 | u16 | section record size = 32 |
| 16 | u32 | endian tag `0x01020304` |
| 20 | u32 | section count = 13 |
| 24 | u64 | section table offset |
| 32 | u64 | section table byte length |
| 40 | u64 | exact file size |
| 48 | u32 | section table CRC32 |
| 52 | u32 | flags/reserved |
| 56 | byte[32] | source manifest SHA256 |
| 88 | u32 | header CRC32（计算时 88..95 清零） |
| 92 | u32 | whole-file CRC32（计算时 92..95 清零） |

### Section table（每项 32 bytes）

| Offset | 类型 | 含义 |
| ---: | --- | --- |
| 0 | u32 | section type |
| 4 | u32 | fixed record size；DATA/STRINGS 为 1 |
| 8 | u64 | file offset |
| 16 | u64 | byte length |
| 24 | u32 | record/byte count |
| 28 | u32 | section CRC32 |

Section 类型：`STRINGS`, `BLOBS`, `GEOMETRIES`, `TEXTURES`, `MATERIALS`, `ASSETS`, `NODES`, `CHILDREN`, `NODE_MATERIALS`, `ANCHORS`, `ROLES`, `INSTANCES`, `DATA`。解析器拒绝缺失、重复、越界、重叠、record size 不匹配和 CRC 错误的 section。每个 payload blob 另有 CRC32，header 保存 source manifest SHA256；打包阶段仍对所有输入执行 SHA256。

## C++17 API

主要头文件：

```cpp
#include <pelican/assets/AssetBundle.h>
#include <pelican/assets/SceneAssetGpu.h>
```

### 从已有内存加载

```cpp
pelican::assets::AssetBundle assets;
std::string error;
if (!assets.LoadFromMemory({pakBytes, pakSize}, &error)) {
    // 记录 error；拒绝继续渲染
}

const auto bicycle = assets.find_asset("bicycle");
const auto rearWheel = bicycle.find_role("wheel.rear.spin").node();
const auto geometry = rearWheel.geometry();
const auto positions = geometry.position();   // zero-copy float view
const auto normals = geometry.normal();       // zero-copy float view
const auto uv = geometry.uv();                 // optional
const auto colors = geometry.color();          // optional
const auto indices = geometry.indices();       // zero-copy uint32 view
const auto morph = assets.find_geometry("geometry_107").morph_position();
```

`LoadFromMemory` 不持有输入；内存必须在 bundle 生命周期内有效。输入起点必须至少 4 字节对齐，以保证 typed view 合法。

### 通过回调 `ReadFile` 加载

`LoadFromReadFile` 接收 `GetSize` + `ReadAt`，将 PAK 读取到 bundle 自有的一块连续内存：

```cpp
pelican::assets::AssetBundle::ReadFileCallbacks io;
io.GetSize = [](std::string_view path, std::uint64_t& size, std::string& error) {
    // 查询 path 长度，写 size
    return true;
};
io.ReadAt = [](std::string_view path, std::uint64_t offset,
               pelican::assets::MutableByteSpan dst, std::string& error) {
    // 必须恰好填满 dst
    return true;
};
assets.LoadFromReadFile("pelican_assets.pak", io, &error);
```

解析器不依赖第三方 JSON、PNG 或哈希库。

## Harmony rawfile 示例

`RawFileLoader.cpp` 使用 Harmony `rawfile` API 提供名为 `ReadRawFile` 的示例：

```cpp
#include <pelican/assets/RawFileLoader.h>

pelican::assets::AssetBundle assets;
std::string error;
if (!pelican::assets::LoadPelicanAssetsFromRawFile(nativeResourceManager, assets, &error)) {
    // 处理 error
}
```

集成时由应用构建系统把 **唯一文件** `packed-assets/pelican_assets.pak` 放进模块 rawfile，运行时名字保持 `pelican_assets.pak`。本任务按约束没有复制到 `entry`。集成侧可执行：

```powershell
New-Item -ItemType Directory -Force D:\workspace\My\harmony\harmony-PelicanBike\entry\src\main\resources\rawfile | Out-Null
Copy-Item -Force `
  D:\workspace\My\harmony\harmony-PelicanBike\packed-assets\pelican_assets.pak `
  D:\workspace\My\harmony\harmony-PelicanBike\entry\src\main\resources\rawfile\pelican_assets.pak
```

## SceneAssetGpu 集成

`SceneAssetGpu` 不改现有 scene；调用方在当前 GLES 3 context 中显式接入：

```cpp
pelican::assets::SceneAssetGpu gpu;
pelican::assets::VertexLocations locations;
locations.position = 0;
locations.normal = 1;
locations.uv = 2;
locations.color = 3;
locations.morphPosition = 4;
locations.instanceMatrix = 8; // 占 8..11

if (!gpu.Upload(assets, locations, &error)) {
    // GLES 上传失败
}

gpu.UpdateWorldMatrices(
    [&](pelican::assets::NodeView node, pelican::assets::Transform& local) {
        // 用 stable role 找到的 node index 覆盖 wheel/steer/crank/head/jaw/wing/leg TRS。
        // 可直接修改 local；回调 bool 返回值保留给调用方标记，适配层会忽略。
        return false;
    },
    &error);

const auto draws = gpu.BuildDrawList(assets.find_asset("bicycle"));
pelican::assets::DrawUniforms uniforms;
uniforms.beforeDraw = [&](const pelican::assets::DrawItem& item) {
    // 绑定自有 shader/program，上传 item.world、uniforms.viewProjection、材质、
    // item.morphInfluence；baseColor 使用 texture unit 0，bump 使用 unit 1。
};
gpu.DrawBatch(draws, uniforms);
```

适配层完成：

- 每个 Geometry 的 VAO/VBO/EBO 上传；position/normal/uv/color/morph 独立 buffer。
- RGBA8 纹理上传；sRGB base color 使用 `GL_SRGB8_ALPHA8`，线性纹理使用 `GL_RGBA8`。
- 节点层级 `world = parentWorld * T * R * S`。
- geometry groups、材质、多纹理槽与 renderOrder 的批量 draw list。
- `glDrawElementsInstanced` 链条实例。
- `UpdateInstanceMatrices` 动态更新链条矩阵。

纹理像素保持 top-to-bottom。`TextureView::flip_y()` 与每个 `TextureBindingView::sampler().flipY` 都可读；shader 集成必须统一执行 `v = 1-v` 或在上传前自行翻转，不能两者同时做。

## Stable role mapping

PAK 中有 49 个 role，API 为：

```cpp
asset.find_role("wheel.front.spin")
asset.find_role("front.steer")
asset.find_role("crank")
asset.find_role("jaw")
asset.find_role("pouch")
asset.find_role("wing.left.elbow")
asset.find_role("leg.right.foot")
```

关键角色：

- Bicycle：`wheel.rear.root/spin`, `wheel.front.root/spin`, `front.steer`, `crank`, `pedal.left/right`, `chain.instances`, `basket`, `bell`, `grip.left/right`。
- Pelican：`body`, `tail`, `neck.dynamicMesh`, `head`, `beak.root`, `beak.upperPivot`, `jaw`, `pouch`, 左右 wing shoulder/elbow/wrist，以及左右 leg thigh/knee/shin/ankle/foot。
- 所有原 manifest anchors 也以 `anchor.<name>` role 保留，并继续通过 `find_anchor()` 暴露。

每条 role 保存 `confidence`（0..100）与 `basis` 说明。

### 无法完全可靠恢复的语义

当前打包运行没有缺失必须角色（`0 unresolved roles`），但以下信息不是静态导出可完全恢复的动画语义，应由现有游戏 simulation 驱动：

1. `neck.dynamicMesh` 只保存导出瞬间的网格。源 H5 每帧重建 DynamicTube 顶点；PAK 不含曲线控制器或 neck skinning rig。
2. 车链初始 101 个矩阵已保存，后续随曲柄转动的链路采样算法不在资产内；应通过 `UpdateInstanceMatrices` 更新。
3. 腿和翅膀导出时是世界空间独立关节对象，不是骨架父子链。role 能稳定找到 thigh/knee/shin/ankle/foot 与 shoulder/elbow/wrist，但 IK/展翅求解仍由 simulation 设置各节点 TRS。
4. blink eyelids、helmet/glasses 可见性、headlight/SpotLight 强度、wheel blur opacity 属于运行时状态，不由静态 role 自动推断。

## 构建和测试

Host：

```powershell
cmake -S native-staging/assets -B native-staging/assets/build-host `
  -G "Visual Studio 17 2022" -A x64 `
  -DPELICAN_ASSETS_BUILD_GLES=OFF `
  -DPELICAN_ASSETS_BUILD_RAWFILE=OFF
cmake --build native-staging/assets/build-host --config Release
ctest --test-dir native-staging/assets/build-host -C Release --output-on-failure
```

测试加载实际 PAK，并核对：

```text
3 assets / 195 nodes / 132 geometries / 10 textures
35631 vertices / 39814 triangles
```

还遍历全部 slice、index、finite、层级、实例矩阵、纹理尺寸与 stable roles；对 0/1/95/半包/少 1 byte 截断和 header/payload 篡改确认失败。

Harmony Clang x86_64：

```powershell
cmake -S native-staging/assets -B native-staging/assets/build-ohos-x86_64 `
  -G "Unix Makefiles" `
  -DCMAKE_TOOLCHAIN_FILE="$env:LOCALAPPDATA\OpenHarmony\Sdk\23\native\build\cmake\ohos.toolchain.cmake" `
  -DOHOS_ARCH=x86_64 -DOHOS_STL=c++_shared -DCMAKE_BUILD_TYPE=Release `
  -DPELICAN_ASSETS_BUILD_HOST_TESTS=OFF
cmake --build native-staging/assets/build-ohos-x86_64 --parallel 4
```

已成功产出：

- `libpelican_asset_bundle.a`
- `libpelican_scene_asset_gpu.a`
- `libpelican_asset_rawfile.a`

外层 native target 可选择链接三个 target，或包含本目录后链接 `pelican::asset_bundle`、`pelican::scene_asset_gpu`、`pelican::asset_rawfile`。应用最终还需链接 `GLESv3` 和 Harmony `rawfile.z`；本目录 CMake 在 OHOS build 中已声明。

`SceneAssetGpu` 是可选层：只链接 `pelican::asset_bundle` 就能解析 CPU views。`LoadFromMemory` 或 `SceneAssetGpu::Upload` 返回失败时，集成 Engine 应保留现有低模 renderer 作为 fallback，而不是中止 XComponent/EGL/VSync 主循环。
