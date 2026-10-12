# Pelican Bike 程序化资产导出

本目录说明 `tools/asset-exporter` 生成的 Harmony Native C++ / OpenGL ES 资源。导出器实际构建并运行原 H5 页面，通过 Playwright 驱动 Chromium，在临时入口中暴露原页面未公开的 `scene`、鱼几何与纹理工厂；临时文件位于系统临时目录，不改动源仓库跟踪文件。

## 已生成资源

当前 `generated-assets/manifest.json` 使用 `PEL_ASSET_BIN` v1：

| 项目 | 数量 |
| --- | ---: |
| 顶层资产 | 3 |
| 节点 | 195 |
| 独立 BufferGeometry | 132 |
| 材质 | 30 |
| 程序化纹理 | 10 |
| 顶点（按独立几何累计） | 35,631 |
| 三角形（按独立几何累计） | 39,814 |
| raw/geometry/instance 二进制 | 15,340,540 bytes |
| 辅助 PNG | 2,735,488 bytes |

按顶层资产统计：

| 资产 | 节点 | 几何引用 | 顶点 | 三角形 | 关键 anchors |
| --- | ---: | ---: | ---: | ---: | --- |
| bicycle | 97 | 73 | 21,596 | 20,516 | `basket`, `bell`, `gripL`, `gripR`, `pedalL`, `pedalR` |
| pelican | 96 | 59 | 14,035 | 19,298 | `body`, `head`, `beakTip`, `mouth`, `scarfKnot` |
| fish | 2 | 1 | 2,844 | 948 | `origin` |

鱼几何也被车篮内的两条鱼复用，因此三个资产逐项统计相加会重复计算该共享几何；manifest 总数按独立几何统计。鹈鹕喉囊几何 `geometry_107` 含一个 position morph target，并在对应节点保存初始 morph influence。

## 程序化纹理

每张纹理同时导出：

- `textures/<id>.rgba8`：紧密排列的 RGBA8，按行从上到下；推荐 Native 直接加载。
- `textures/<id>.png`：人工查看和工具链备用。

| ID | 尺寸 | 色彩空间 | 用途 | raw bytes |
| --- | ---: | --- | --- | ---: |
| `road_color` | 2048×512 | sRGB | 路面颜色 | 4,194,304 |
| `road_bump` | 2048×512 | linear | 路面高度/凹凸 | 4,194,304 |
| `feather_bump` | 512×512 | linear | 羽毛凹凸 | 1,048,576 |
| `wicker` | 256×256 | sRGB | 藤编篮颜色 | 262,144 |
| `sprite` | 128×128 | sRGB | 粒子/光晕 sprite | 65,536 |
| `decal_pelicano` | 1024×128 | sRGB | 车架贴花 | 524,288 |
| `sign_crossing` | 512×512 | sRGB | 鹈鹕过街牌 | 1,048,576 |
| `sign_speed` | 512×512 | sRGB | 限速牌 | 1,048,576 |
| `sign_fish` | 512×512 | sRGB | 前方有鱼牌 | 1,048,576 |
| `lighthouse_stripes` | 256×256 | sRGB | 灯塔红白条纹 | 262,144 |

manifest 还保存 `wrapS/wrapT`、过滤方式、`flipY`、repeat、offset、center、rotation，以及 raw 与 PNG 的 SHA256。

## 运行命令

导出器不要求在目标仓库提交 `node_modules`。优先复用源项目已安装依赖：

```powershell
cd D:\workspace\My\harmony\harmony-PelicanBike\tools\asset-exporter
$env:PELICAN_SOURCE = 'D:\workspace\My\h5\claude-opus-5-5-demo\pelican-bike'
node .\export.mjs
node .\validate.mjs
```

如果源项目没有 `node_modules`，可临时安装到目标仓库之外，并用 `PELICAN_DEPS` 指向 npm prefix：

```powershell
$deps = Join-Path $env:TEMP 'pelican-asset-exporter-deps'
npm install --prefix $deps --no-save esbuild@0.28.2 playwright-core@1.63.0 three@0.186.0 lil-gui@0.21.0
$env:PELICAN_DEPS = $deps
node D:\workspace\My\harmony\harmony-PelicanBike\tools\asset-exporter\export.mjs
node D:\workspace\My\harmony\harmony-PelicanBike\tools\asset-exporter\validate.mjs
Remove-Item -Recurse -Force $deps
```

可选环境变量：

- `PELICAN_SOURCE`：源 H5 仓库，默认已设为本任务给定路径。
- `PELICAN_ASSET_OUTPUT`：输出目录，默认 `generated-assets`。
- `PELICAN_CHROMIUM`：Chrome、Edge 或 Chromium 可执行文件。
- `PELICAN_DEPS`：含 `node_modules` 的临时 npm prefix。

导出过程可重复执行，成功后以 staging 目录原子式替换 `generated-assets`。校验器会重新读取所有引用的二进制，检查 SHA256、边界、finite、属性布局、索引范围、节点/材质/纹理引用、morph target 和统计值。

## `PEL_ASSET_BIN` v1

唯一入口为 `generated-assets/manifest.json`。主要数组：

- `buffers`：每个分块文件的路径、用途、字节数和 SHA256。
- `geometries`：属性/index/morph 的 buffer slice、groups、draw range 和 bounds。
- `textures`：RGBA8 与 PNG 元数据。
- `materials`：基础颜色、发光、透明、PBR 标量和纹理槽；每个纹理槽单独保存 repeat/offset/rotation/wrap/filter，避免同一像素资源在不同材质中的采样状态互相覆盖。
- `assets`：节点层级、局部 TRS、几何/材质引用与 anchors。

### 几何二进制

每个 `geometry/*.bin` 内依次存储已有属性：

1. `position`: float32，itemSize 3。
2. `normal`: float32，itemSize 3。
3. `uv`: float32，itemSize 2，可选。
4. `color`: float32，itemSize 3/4，可选。
5. `index`: uint32，itemSize 1。原非索引几何会生成顺序索引。
6. morph attributes：float32，可选。

每段按 4 字节对齐，准确位置以 `byteOffset`、`byteLength`、`count`、`itemSize` 为准。所有数字均 little-endian；float 为 IEEE-754 float32，索引固定 uint32。绘制模式当前为三角形。

### 节点与实例

每个节点保存局部：

- `position[3]`
- `quaternion[4]`，顺序 `(x,y,z,w)`
- `scale[3]`

坐标系为右手系，源场景约定 `+X` 前进、`+Y` 向上、`+Z` 为骑手左侧，单位为米。实例矩阵在 `instances/*.bin` 中按 16 个 float32 连续存储，采用 Three.js/OpenGL 列主序，可直接作为 GLES column-major mat4；实例颜色紧随矩阵分块，仍以 manifest offset 为准。

父子世界矩阵：

```cpp
world = parentWorld * Translate(position) * Mat4(quaternion) * Scale(scale);
```

### C++ 读取要点

1. 解析 manifest，检查 `format == "PEL_ASSET_BIN"` 且 `version == 1`。
2. 加载每个 `buffers[].path`，校验精确字节数和 SHA256。
3. 对每个 slice 检查 `byteOffset + byteLength <= fileSize`，不要假设属性之间无 padding。
4. HarmonyOS 常见 ARM 设备是 little-endian；若运行于 big-endian 平台，必须交换每个 32 位值。
5. GLES attribute 示例：position/normal/color 用 `GL_FLOAT`，uv 用 `GL_FLOAT`，index 用 `GL_UNSIGNED_INT`。OpenGL ES 3.x 原生支持 32 位 element index。
6. 纹理 raw 数据用 `GL_RGBA8` / `GL_RGBA` / `GL_UNSIGNED_BYTE`。由于 `rowOrder` 是 top-to-bottom，而 OpenGL UV 原点习惯在左下，按 manifest 的 `flipY` 策略统一处理：可以上传前垂直翻转，或在 shader/UV 中使用 `v = 1 - v`。整个项目只能选一种一致策略。
7. `colorSpace == "srgb"` 的 base-color 纹理可使用 `GL_SRGB8_ALPHA8`，height/bump 纹理保持线性 `GL_RGBA8`。
8. 材质参数只覆盖源 Three.js 基础/PBR 参数；Harmony shader 可按需映射 roughness、metalness、clearcoat、sheen、emissive、alphaTest、side 和 blending。纹理采样状态从 `materials[].textures.<slot>` 读取，而不是只看纹理记录中的默认值。
9. morph position 默认是绝对目标（`morphTargetsRelative == false`）：`position = mix(base, target, influence)`。如果以后 manifest 标记为 relative，则改为 `base + target * influence`。
10. 不应依赖几何或节点数组顺序表达语义；通过稳定 ID、父子 ID 和 `anchors` 查找关键节点。

## 输出完整性

当前 manifest 为每个生成文件记录 SHA256。运行：

```powershell
node D:\workspace\My\harmony\harmony-PelicanBike\tools\asset-exporter\validate.mjs
```

预期摘要：

```text
validated 3 assets, 195 nodes, 132 geometries, 10 textures
35631 vertices, 39814 triangles, 15340540 binary bytes
```
