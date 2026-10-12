# Pelican Bike 参考向量

本目录保存 Harmony 端移植时使用的确定性 golden vectors。数据源为只读源项目：

`D:\workspace\My\h5\claude-opus-5-5-demo\pelican-bike`

生成器默认按上述同级工作区布局定位源项目；若目录不同，可设置环境变量 `PELICAN_BIKE_SOURCE_ROOT` 指向源项目根目录。

## 产物

- `pelican-bike-golden.json`：完整参考值。
- `../../tools/reference-vectors/generate.mjs`：从源文件重新提取算法并生成 JSON。
- `../../tools/reference-vectors/verify.mjs`：重新执行源算法并与已提交 JSON 做逐值、逐序列化字节验证。

JSON 覆盖：

- `clamp`、`lerp`、`damp`、`smoothstep`；
- `mulberry32(0)` 前 32 个值，另含四个补充种子；
- 五组 Gerstner 波参数、`wavePhases` 的多组距离/时刻，以及 `waveHeight` 的多组坐标/时刻/振幅；
- `terrainHeight` 在道路边界、沙滩、丘陵、正负坐标和最高 `±1e12` 横向长距离坐标上的样本；
- `solveTwoBone` 的可达、不可达、最小伸距、pole 平行回退、三维和零目标差等样本；
- 固定 `dt = 1/60 s`、600 帧、10 秒的加速、刹车、巡航、横移、跳跃完整逐帧轨迹；
- 五档自动变速在 68/102 rpm 边界前、边界点、边界后的判定；
- `mulberry32(2024)` 驱动的 32 次鱼生成序列；
- 14 项成就定义及其事件/数值阈值。

## 算法口径与复用方式

生成器读取而不修改以下源文件：

- `src/util.js`
- `src/ocean.js`
- `src/world.js`
- `src/main.js`
- `src/bicycle.js`

能独立执行的算法不是手工重写：生成器在运行时从源文本提取原声明/原函数体，并在受控 Node 上下文中执行。直接提取执行的内容包括：

- `clamp`、`lerp`、`damp`、`smoothstep`、`mulberry32`、`solveTwoBone`；
- `wavePhases`、`waveHeight`；
- `fbm2`、`terrainHeight`；
- `updateRide`、`jump`；
- `spawnFish`。

`main.js` 不能作为模块整体导入，因为顶层会立即初始化 DOM、WebGL、音频和动画循环；因此这里提取其原函数体，并只提供这些函数实际访问的最小状态和无副作用桩对象。骑行状态初值 `S`、`GEARS`、`WHEEL_R` 和数学辅助函数也直接从源声明提取。

地形算法依赖 Three.js 的 `ImprovedNoise`。工具目录固定使用源项目锁文件对应的 `three@0.186.0`，从 `three/addons/math/ImprovedNoise.js` 直接导入，未另行翻译噪声算法。

成就对象 `ACH` 直接从源声明提取；阈值判断分散在事件函数和 HUD/收鱼更新中，无法脱离浏览器副作用整体调用，因此阈值表按源条件逐字转录为结构化数据，并在每项 `sourceCondition` 中保留判断式。涉及严格比较的夜骑条件仍记录为 `info.night > 0.8 && S.started && S.time > 5`，不改写为大于等于。

## 数值口径

- JavaScript 普通数值为 IEEE-754 binary64。
- `wavePhases` 同时保存：
  - `float64`：函数写入普通数组时的双精度结果；
  - `float32`：与应用中 `Float32Array` uniform 一致的量化结果。
- 骑行轨迹严格每帧调用一次源 `updateRide(1/60)`。每帧调用前先将 `S.t` 与 `S.time` 增加 `1/60`，与源主循环一致。
- 自动变速边界通过源 `updateRide(0)` 执行，因此只观察变速决策，不引入速度积分；自动变速等待条件通过 `S.time = 9`、`S.lastGearManual = -99` 满足。
- 鱼序列每次复用同一个槽位并将其设回非 active，仅用于连续消费源 RNG；第 1 条使用源首次生成的 `ahead=32`，后续使用 `ahead=85`。
- JSON 不做小数截断，保留 `JSON.stringify` 可表达的完整 Number 值。

## 容差建议

同一 Node/JavaScript 算法重新生成时，验证脚本要求 JSON 逐值且序列化字节完全一致。跨语言消费时建议：

| 数据 | 建议判定 |
|---|---|
| 布尔、整数、档位、索引、成就 ID | 精确相等 |
| Mulberry32 输出 | 若完全复刻 32 位位运算与 unsigned 转换，应精确相等；否则绝对误差 `<= 1e-15` |
| 普通数学、波高、IK | `abs <= 1e-12` 或 `rel <= 1e-12` |
| `wavePhases.float32` | 绝对误差 `<= 2e-6` |
| `terrainHeight` | 绝对误差 `<= 1e-9`；必须使用同版 ImprovedNoise 排列与插值 |
| 600 帧骑行轨迹 | 每列每帧绝对误差 `<= 1e-9`；不要先对中间状态转 float32 |

若 Harmony 实现有意使用 float32 作为中间状态，应另建平台口径，不应放宽本 binary64 golden 直至掩盖算法差异。

## 运行命令

在工具目录运行：

```bash
cd D:/workspace/My/harmony/harmony-PelicanBike/tools/reference-vectors
npm install --ignore-scripts
npm run generate
npm run verify
```

或从任意目录运行：

```bash
npm install --prefix D:/workspace/My/harmony/harmony-PelicanBike/tools/reference-vectors --ignore-scripts
npm run generate --prefix D:/workspace/My/harmony/harmony-PelicanBike/tools/reference-vectors
npm run verify --prefix D:/workspace/My/harmony/harmony-PelicanBike/tools/reference-vectors
```

源项目位于其它位置时：

```bash
PELICAN_BIKE_SOURCE_ROOT=/path/to/pelican-bike npm run generate
PELICAN_BIKE_SOURCE_ROOT=/path/to/pelican-bike npm run verify
```

`verify` 会重新读取五个源文件、重新执行算法、比较完整对象和 JSON 文本，并输出 `pelican-bike-golden.json` 的 SHA256。JSON 的 `provenance.sourceFiles` 同时记录五个输入源文件的 SHA256，源算法发生变化后必须显式重新生成。
