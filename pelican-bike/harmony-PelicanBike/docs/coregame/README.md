# Pelican Bike Coregame

`native-staging/coregame` 是从 H5 原型抽离出的 C++17、零第三方依赖核心库。它只负责确定性的数学、环境采样与玩法状态；不包含 Three.js、DOM、音频、粒子、网格或 Harmony entry 代码。

## 目录与集成

- 公共头文件：`native-staging/coregame/include/pelican`
- 实现：`native-staging/coregame/src`
- Host 测试：`native-staging/coregame/tests`
- CMake target：`pelican::coregame`
- 聚合头文件：`#include <pelican/coregame.hpp>`

最小 host 调用方式：

```cpp
pelican::GameSimulation game;

pelican::InputState input;
input.startPressed = true;
game.advance(0.0, input);

input = {};
input.accelerate = true;
game.advance(frameSeconds, input);  // 内部只执行 1/60 固定步

const pelican::GameSnapshot snapshot = game.snapshot();
const std::vector<pelican::GameEvent> events = game.consumeEvents();
```

`GameState` 是模拟内部的双精度世界状态。累计量 `distance`、`time`、`hour` 以及速度、车道和环境计算均为 `double`，不得从渲染结果回写。`GameSnapshot` 保留双精度 HUD/世界累计值，同时把鱼和相机转换成以骑手为原点的局部 `float` 坐标，便于渲染器直接上传。

`advance()` 的累积器每次 host 调用最多补 4 个固定步，并丢弃更老的 backlog，避免应用从后台恢复时无限追帧。未 `start` 以及 `pause` 时不会推进 tick、时间、昼夜、相机排程、鱼或骑行状态。若平台层已有固定 tick，也可以直接调用 `step()`；不要同时在外层和库内重复累积同一段时间。

## 源公式映射

| C++ 实现 | H5 来源 | 映射说明 |
|---|---|---|
| `clamp` / `lerp` / `damp` / `smoothstep` | `src/util.js:2-10` | 指数阻尼仍为 `1 - exp(-lambda * dt)`；`smoothstep` 支持反向边界。 |
| `Mulberry32` | `src/util.js:12-20` | 保持 JS `|0`、`>>>`、`Math.imul` 的 32 位环绕语义；`nextU32()` 是原始整数结果，`nextDouble()` 除以 `2^32`。 |
| `solveTwoBone` | `src/util.js:180-198` | 采用同样的 reach `0.999` 限制、余弦定理和 pole 投影；同时提供结构体与 out 参数接口。 |
| Gerstner 参数、phase、height | `src/ocean.js:3-13, 175-202` | 五组方向/陡度/波长完全迁移。`gerstnerWavePhasesSourceParity` 保留源表达式用于 golden；生产 `gerstnerWavePhases` 在 CPU `double` 中分别缩减 distance/time phase 再组合，避免长距离 float 相位跳变。岸边振幅衰减与 CPU 波高一致。 |
| `ImprovedNoise` | `three/examples/jsm/math/ImprovedNoise.js`，由 `src/world.js:1,15` 使用 | 内置 Ken Perlin 2002 permutation/fade/grad，不依赖 three。 |
| `terrainHeight` | `src/world.js:17-42` | `fbm2` 的振幅、频率 `2.03`、seed 偏移 `7.31`、山丘/沙滩 smoothstep 与 dunes 公式迁移。 |
| 五档齿比、轮径 | `src/bicycle.js:6-13` | `WHEEL_R=0.3`，齿比 `44/28, 44/22, 44/18, 44/15, 44/12`。 |
| 速度、巡航、刹车、踏频和自动变速 | `src/main.js:546-583` | 空中 `-0.15`、刹车 `-6`、加速 `2.4`、巡航回归 `0.7`、最高 `15.5 m/s`；自动档以约 `86 rpm` 为目标并用 `68/102 rpm` 门限逐档切换。 |
| 横移与自动驾驶 | `src/main.js:585-603` | 手动目标速度 `2.4`、车道范围 `[-2.15,2.15]`、临界阻尼弹簧 `k=10`、4 秒后追最近鱼，否则使用正弦巡航线。 |
| 跳跃与特技 | `src/main.js:605-647` | 起跳 `vy=3.6`、重力 `13`；特技时长 `3.4s`、加速上限 `0.2`、trick/wheelie 阻尼一致。 |
| 鱼对象池与计分 | `src/main.js:663-739` | 固定 12 槽、四鱼道、生成间隔、`12%` 金鱼、普通 `+1`/金鱼 `+5`。`score` 对应原 H5 `S.fish`，另有实际捕获条数 `fishCaught`。 |
| 14 成就 | `src/main.js:830-854, 933-937` | ID、触发阈值和只解锁一次语义迁移；事件携带 `Achievement` 枚举。 |
| 昼夜 | `src/main.js:466-470` 与 `src/sky.js:213-234` | hour 流速、太阳方向、太阳高度与 night factor 公式迁移。 |
| 相机调度 | `src/main.js:309-441` | 提供 Orbit/Chase/Side/Cine/Pov 五模式和八段电影镜头时长/轨迹/FOV；快照输出渲染局部 pose。 |

## RNG 约束

- `gameplayRandom_` 默认种子为 `2024`，只用于会影响鱼生成、鱼道、金鱼与自动驾驶目标的随机数。
- `visualRandom_` 是独立流，只通过 `nextVisualU32()` / `nextVisualRandom()` 暴露给渲染特效。
- 测试会在大量消费 visual RNG 后比较两份模拟，确保 gameplay 状态、鱼池与 gameplay RNG state 完全一致。
- 若需要回放或联网校验，记录设置、输入 tick 序列和 gameplay seed；不要把 visual seed 作为玩法同步条件。

## 快照与事件

`snapshot()` 返回值拷贝，不暴露可变内部容器，因此渲染线程可以把它作为不可变帧数据。鱼快照带池索引、金鱼标记、捕获动画状态、局部位置、phase 和 scale。

`consumeEvents()` 以 move/swap 方式一次性取走事件。事件有单调 `sequence`、fixed `tick`、模拟时间，以及按类型使用的整数、标记、局部位置、成就或相机枚举。当前事件覆盖：开始、暂停/继续、换档、起跳/落地、特技、铃/鸣叫、鱼生成/捕获、成就和相机切换。

## 构建与测试

Windows/Clang 示例：

```sh
cmake -S native-staging/coregame -B native-staging/coregame/build -G Ninja \
  -DCMAKE_CXX_COMPILER="C:/Program Files/LLVM/bin/clang++.exe" \
  -DCMAKE_RC_COMPILER="C:/Program Files/LLVM/bin/llvm-rc.exe"
cmake --build native-staging/coregame/build
ctest --test-dir native-staging/coregame/build --output-on-failure
```

Harmony Clang 交叉编译示例：

```sh
cmake -S native-staging/coregame -B native-staging/coregame/build-ohos -G Ninja \
  -DCMAKE_TOOLCHAIN_FILE="C:/Users/<user>/AppData/Local/OpenHarmony/Sdk/23/native/build/cmake/ohos.toolchain.cmake" \
  -DOHOS_ARCH=arm64-v8a -DOHOS_STL=c++_shared \
  -DPELICAN_COREGAME_BUILD_TESTS=OFF
cmake --build native-staging/coregame/build-ohos
```

验证时还以 `OHOS_ARCH=x86_64`、`PELICAN_COREGAME_BUILD_TESTS=ON` 完整编译了测试 executable；交叉产物只验证编译/链接，golden executable 在 host Clang 上运行。

测试 executable 为 `pelican_coregame_tests`。CMake 优先读取已有的 `docs/reference-vectors/pelican-bike-golden.json`，若该文件不存在才回退到 `tests/reference-vectors.json`。测试内置零第三方、递归下降的 JSON 定向解析器，支持该 golden schema 所需的 object/array/string/number/bool/null 与标准字符串转义，但它仍只作为测试读取器，不作为运行时 JSON API。

完整 golden 校验覆盖：

- 27 个 `clamp/lerp/damp/smoothstep` primitive case；
- `mulberry32.first32` 32 项，以及 4 个补充 seed × 8 项，共 64 个精确 uint32 输出；
- 8 组 Gerstner phase、共 40 个 double/float 项，float32 容差 `2e-6`；
- 12 个 waveHeight、21 个 terrainHeight、7 个 solveTwoBone case；
- 5 条骑行轨迹 × 601 帧，共 3005 帧、51085 个数值列检查与 6010 个布尔列检查；
- 5 档 × 高低边界 × `-epsilon/0/+epsilon`，共 30 个自动变速 probe；
- `mulberry32(2024)` 的前 32 次鱼生成 lane/y/golden/phase；
- 14 个成就 definition ID/三元文本结构，以及 14 个 threshold/kind/严格比较结构。

骑行、自动变速与鱼序列通过测试专用 source-parity helper 校验，严格复现原 `main.js` 的更新时间顺序和 `updateRide(dt)` 公式；这样不会因生产 `GameSimulation` 有意加入开始/暂停冻结、4 步补帧上限、RNG 分流、落地 `vy` 清零等行为修正而掩盖公式偏差。生产行为仍由独立固定断言覆盖。

`gerstnerWavePhasesSourceParity()` 保留源表达式顺序供 golden 校验，并使用从 V8 执行 `ocean.js` 得到的 binary64 phase 系数，隔离不同 libc 的 `hypot/sqrt` 最后位差异；因此 8 组 × 5 波的 float64 值按绝对误差 `1e-12` 直接比较，随后按应用的 `Float32Array` 量化口径以 `2e-6` 比较。`gerstnerWavePhases()` 仍是生产用长距离稳定版本，会在 binary64 中分别缩减 distance/time phase 后组合。即使 reference 文件缺失，executable 仍保留编译内固定断言，覆盖数学、Mulberry32、ImprovedNoise、环境公式、冻结规则、4 步上限、玩法事件和 RNG 隔离。

## 已知偏差

1. **原 H5 不是固定步长。** H5 主循环将 render delta 截到 `1/20` 后直接模拟；核心库按需求改为严格 `1/60`，因此阻尼积分、起跳落地时间、鱼碰撞 tick 和自动档切换时刻会有小幅但确定的差异。
2. **碰鱼口部锚点是核心近似。** H5 每帧从完整鹈鹕骨架取得 `mouth.getWorldPosition()`；核心不持有渲染骨架，使用固定的骑手局部嘴部锚点。渲染器可以按 snapshot 做表现，但玩法碰撞不应依赖动画骨骼回写。
3. **相机是调度 pose，不含 OrbitControls。** 电影镜头轨迹、模式、时长和 FOV 已迁移；鼠标轨道惯性、用户拖拽、地形防穿透和模式间 quaternion blend 属于 renderer/host。核心的 orbit 模式用确定性自动环绕 pose。
4. **视觉随机效果不属于玩法。** 跃海鱼、灰尘、火花、彩纸、音频和原 H5 中由同一 `rnd` 驱动的视觉粒子没有进入核心；这是 gameplay/visual RNG 分流所必需的行为变化。
5. **成就按固定 tick 检查。** H5 速度/距离/夜骑成就在 HUD 的约 0.1 秒节流更新中检查；核心每个 1/60 tick 检查，因此最多提前约 0.1 秒。
6. **`score` 与捕获条数拆分。** 原 `S.fish` 同时显示积分且金鱼加 5；核心保留同口径 `score`，并新增 `fishCaught`，避免集成方误把 10 分当成 10 条实际鱼。
7. **浮点跨平台。** 状态和环境使用 IEEE-754 `double`，Mulberry32 整数流严格可复现；`sin/cos/exp/sqrt` 的最后几位仍可能因标准库实现不同而变化，不承诺逐 bit 的跨 libc 浮点回放。
