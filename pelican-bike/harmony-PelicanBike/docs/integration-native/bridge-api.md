# Integrated native bridge API

模块仍以 `libpelican.so` 导入：

```ts
import * as pelican from 'libpelican.so';
```

权威类型建议位于 `integration-staging/native/types/libpelican/index.d.ts`。

## 生命周期

```ts
pelican.setEventCallback(callback)
pelican.initialize({ resourceManager, quality, camera, hour, ...settings })
pelican.start(withSound)
pelican.setPaused(paused)
pelican.dispose()
```

`start(false)` 不创建 OHAudio。`setPaused(true)` 同时暂停模拟、VSync 续订和音频；Surface 丢失会额外暂停音频。`dispose()` 主动等待在途帧、销毁 scene/EGL/VSync/audio、释放 ResourceManager 和 TSFN。

## 控制

```ts
setInput('left' | 'right' | 'up' | 'down' | 'pedal' | 'brake' | 'accelerate', pressed)
triggerAction('jump' | 'trick' | 'bell' | 'honk' | 'night' | 'flow' | 'pick', x?, y?)
setCamera('orbit' | 'chase' | 'follow' | 'side' | 'cine' | 'pov' | 'firstPerson')
setSetting(name, boolean | number | string)
```

支持的 setting：

- 骑行：`cruise`、`autopilot`、`autoGear`
- 时间天气：`hour`、`night`、`dayRate`、`timeFlow`、`cloud`、`waveAmp`、`waveAmplitude`、`fog`
- 画面：`quality`、`bloom`、`bloomBoost`、`exposure`、`showFps`
- 角色：`helmet`、`glasses`、`scarf`、`lookMouse`
- 声音：`volume`、`music`、`musicVolume`

未知 setting 会抛出 `RangeError`，避免静默拼写错误。

## HUD

`getSnapshot()` 与 100 ms 周期 `hud` 事件均返回：

```ts
interface HudSnapshot {
  speedKmh: number
  cadence: number
  gear: number
  gearCount: number
  distanceKm: number
  fish: number
  achievements: number
  achievementTotal: number
  hour: number
  fps: number
  quality: string
  camera: string
  night: boolean
  started: boolean
  paused: boolean
}
```

`gear` 为 UI 友好的 1-based 值。`fish` 与 Web HUD 保持一致，表示总分而不是物理鱼条数。

## 事件

### hud

```ts
{ type: 'hud', snapshot: HudSnapshot }
```

### toast

```ts
{ type: 'toast', message: string }
```

### score

```ts
{
  type: 'score',
  score: number,
  delta: number,
  golden: boolean,
  x: number,
  y: number
}
```

`x/y` 是 top-left origin、0..1 normalized 的嘴部坐标。

### achievement

```ts
{
  type: 'achievement',
  id: string,
  icon: string,
  title: string,
  detail: string
}
```

14 项映射：

| id | icon | title | detail |
|---|---|---|---|
| fish1 | 🐟 | 第一条鱼 | 张嘴就是干饭 |
| golden | 🌟 | 金色传说 | 吞下了一条金鱼 (+5) |
| fish10 | 🎣 | 十鱼到手 | 喉囊开始沉甸甸了 |
| fish50 | 🏆 | 海岸渔王 | 累计 50 条鱼 |
| jump | 🦘 | 起飞！ | 第一次跳跃 |
| trick | 🪽 | 放手特技 | 展翅 + 抬前轮 |
| trick3 | 🎪 | 杂技鹈鹕 | 完成 3 次特技 |
| speed30 | 💨 | 时速 30 | 风在耳边呼啸 |
| speed45 | ⚡ | 疾风鹈鹕 | 时速突破 45 km/h |
| km1 | 🛣️ | 骑行 1 公里 | 海岸线才刚开始 |
| km5 | 🗺️ | 骑行 5 公里 | 真正的长途鹈鹕 |
| night | 🌙 | 夜骑 | 星光与路灯作伴 |
| bell10 | 🔔 | 铃铃铃 | 按铃 10 次，路人已让开 |
| honk | 📢 | 嘎——！ | 鹈鹕的呐喊 |

### cameraFlash

```ts
{ type: 'cameraFlash', intensity: number, golden: boolean, x: number, y: number }
```

用于 fish、trick 和里程碑成就的 ArkUI overlay；native scene 不依赖 ArkUI 是否消费该事件。

### seaJumper

```ts
{ type: 'seaJumper', x: number, y: number }
```

表示触摸 pick 命中远海。当前 staging scene 没有动态 jumper 注入 API，因此 bridge 发出事件并触发 splash 音效，ArkUI/未来 scene adapter 可绘制跃鱼。

### screenshot

```ts
{
  type: 'screenshot',
  success: boolean,
  pixels?: ArrayBuffer,
  width: number,
  height: number,
  message?: string
}
```

`pixels` 为 `width * height * 4` 字节的 RGBA8，row-major，top-left origin。请求在下一次 render frame、swap 前完成。失败时 `success=false`，width/height 为 0，并可带 message。

### error

```ts
{ type: 'error', code: string, message: string }
```

## 线程语义

所有事件均通过一个 bounded N-API TSFN 非阻塞投递。Native 不在调用 ArkTS callback 时持有 engine/EGL mutex；队列满或 callback 已释放时 payload 由 native 回收。
