// 游戏引擎：状态机 / 主循环 / 相机 / 碰撞 / 排名 / 事件 / 渲染编排（自 H5 版 main.js 移植）
import { clamp, lerp, damp, dampAngle, wrapAngle, mulberry32, formatTime } from '../common/Util';
import { MAPS, DIFFS, QUALITY, CAR_SKINS, AI_NAMES, MapCfg, mapById, LAYOUTS } from '../common/Config';
import { Track, TrackSample } from './Track';
import { PlayerCar, InputState, TUNE } from './Vehicle';
import { AICar } from './AI';
import { RacerBase } from './RacerBase';
import { ItemSystem, ItemHost } from './Items';
import { ParticlePool, SkidMarks, MsgList, SpeedLines } from './Effects';
import { AudioSys } from './Audio';
import { Renderer, CloudDot } from '../render/Renderer';
import { Terrain } from '../render/Terrain';
import { TrackMeshes } from '../render/TrackMesh';
import { PropsBuilder } from '../render/Props';
import { Palette, parseHex } from '../render/Palette';
import { Mesh, MeshBuilder, Mat34, addBox, addPrism } from '../render/Mesh';
import { CarVisual, buildCarVisual, CarPose, carPartMatrix, matMulInto } from '../render/CarModel';

export const DT: number = 1 / 120;

export class GameSettings {
  map: string = 'city';
  mode: string = 'speed';
  skin: number = 0;
  laps: number = 2;
  diff: number = 1;
  quality: string = 'mid';
  song: number = 0;
}

export function qualityPct(id: string): number {
  return id === 'low' ? 0.62 : id === 'high' ? 1.0 : 0.8;
}

export class StandingRow {
  name: string = '';
  me: boolean = false;
  fin: boolean = false;
  color: string = '#ffffff';
}

export class HudData {
  lap: string = '1/3';
  time: string = '00:00.00';
  best: string = '--:--.--';
  kmh: number = 0;
  rank: number = 1;
  total: number = 6;
  gauge: number = 0;
  nitro: number = 0;
  standings: StandingRow[] = [];
  items: string[] = [];
  itemMode: boolean = false;
  nitroOn: boolean = false;
  smallOn: boolean = false;
}

export class ResultRow {
  pos: number = 0;
  name: string = '';
  total: string = '';
  best: string = '';
  me: boolean = false;
}

export class ResultData {
  title: string = '';
  win: boolean = false;
  stats: string[] = [];
  rows: ResultRow[] = [];
}

export interface GameSink {
  onState(state: string): void;
  onHud(data: HudData): void;
  onProgress(p: number, text: string): void;
  onResult(res: ResultData): void;
  onSong(name: string): void;
  requestSettings(): GameSettings;
  saveSettings(s: GameSettings): void;
}

// 触屏输入桥
export class InputBridge {
  left: boolean = false;
  right: boolean = false;
  down: boolean = false;
  shift: boolean = false;
  nitroEdge: boolean = false;
  boostEdge: boolean = false;
  swapEdge: boolean = false;
  resetEdge: boolean = false;

  build(racing: boolean): InputState {
    const s = new InputState();
    s.up = racing; // 触屏模式比赛中自动油门
    s.down = this.down;
    s.left = this.left;
    s.right = this.right;
    s.shift = this.shift;
    s.upPressed = racing ? this.boostEdge : false;
    s.wPressed = this.boostEdge;
    s.nitroPressed = this.nitroEdge;
    s.swapPressed = this.swapEdge;
    s.resetPressed = this.resetEdge;
    this.nitroEdge = false;
    this.boostEdge = false;
    this.swapEdge = false;
    this.resetEdge = false;
    return s;
  }
}

class CarEntry {
  racer: RacerBase;
  visual: CarVisual;
  pose: CarPose = new CarPose();
  pitchVis: number = 0;
  rollVis: number = 0;
  leanRoll: number = 0;
  leanPitch: number = 0;
  steerVis: number = 0;
  wheelSpin: number = 0;

  constructor(racer: RacerBase, visual: CarVisual) {
    this.racer = racer;
    this.visual = visual;
  }
}

export class GameApp implements ItemHost {
  sink: GameSink;
  renderer: Renderer;
  mmCtx: CanvasRenderingContext2D | null = null; // 小地图
  spCtx: CanvasRenderingContext2D | null = null; // 码表
  settings: GameSettings = new GameSettings();
  state: string = 'boot'; // boot/loading/menu/countdown/race/finish/paused
  input: InputBridge = new InputBridge();
  audio: AudioSys = new AudioSys();
  // 关卡
  map: MapCfg = MAPS[0];
  track: Track | null = null;
  terrain: Terrain | null = null;
  trackMeshes: TrackMeshes | null = null;
  props: Mesh[] = [];
  // 道具可视化
  boxMesh: Mesh | null = null;
  missileMesh: Mesh | null = null;
  bananaMesh: Mesh | null = null;
  // 比赛实体
  racers: RacerBase[] = [];
  cars: CarEntry[] = [];
  player: PlayerCar | null = null;
  items: ItemSystem | null = null;
  itemMode: boolean = false;
  standings: RacerBase[] = [];
  // 循环
  private timer: number = -1;
  private lastT: number = 0;
  time: number = 0;
  raceTime: number = 0;
  private acc: number = 0;
  // 相机
  camMode: number = 0;
  camX = 0; camY = 50; camZ = 0;
  camYaw: number = 0;
  camFov: number = 66;
  private lookX = 0; private lookY = 0; private lookZ = 0;
  shake: number = 0;
  private demoT: number = 0;
  private demoTarget: number = 0;
  // 倒计时
  private cdT: number = 0;
  private cdShown: number = -1;
  cdText: string = '';
  private startBoostReady: boolean = false;
  private startTried: boolean = false;
  // 结算
  private firstFinish: number = -1;
  private finishT: number = 0;
  resultShown: boolean = false;
  warnText: string = '';
  finalText: string = '';
  private missileWarn: number = 0;
  private pausedFrom: string = 'race';
  // 特效
  smoke: ParticlePool = new ParticlePool(700);
  glow: ParticlePool = new ParticlePool(700);
  skids: SkidMarks = new SkidMarks(900);
  msgs: MsgList = new MsgList();
  lines: SpeedLines = new SpeedLines();
  snow: ParticlePool = new ParticlePool(260);
  private snowSpawn: number = 0;
  // HUD 节流
  private hudTick: number = 0;
  private mmT: number = 0;
  // 加载状态
  private loadStep: number = 0;
  private loadPhase: number = 0;
  private loadTerrain: Terrain | null = null;
  pendingMap: string = '';
  private carCache: Map<number, CarVisual> = new Map<number, CarVisual>();
  private tmpSample: TrackSample = new TrackSample();
  private tmp2: TrackSample = new TrackSample();
  private pr: number[] = [0, 0, 0];

  constructor(renderer: Renderer, sink: GameSink) {
    this.renderer = renderer;
    this.sink = sink;
    const s = sink.requestSettings();
    if (s !== null) this.settings = s;
    this.applyQuality();
  }

  applyQuality(): void {
    for (const q of QUALITY) {
      if (q.id === this.settings.quality) {
        this.renderer.viewScale = q.view;
        this.renderer.lowGfx = q.id !== 'high';
      }
    }
  }

  start(): void {
    if (this.timer >= 0) return;
    this.lastT = Date.now();
    this.timer = setInterval(() => {
      const now = Date.now();
      const dt = Math.min(0.05, (now - this.lastT) / 1000);
      this.lastT = now;
      this.tick(dt);
    }, 16);
  }

  stop(): void {
    if (this.timer >= 0) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  tick(dt: number): void {
    if (this.state === 'loading') {
      this.loadTick();
      this.renderLoading();
      return;
    }
    if (this.state === 'boot') return;
    this.time += dt;
    if (this.state !== 'paused') this.step(dt);
    this.render(dt);
    // 帧率自动降档：最近 90 帧里超过一半慢于 40ms 时降一级画质（启动 8 秒后才生效）
    if (dt > 0.04) this.slowFrames++;
    this.slowWin++;
    if (this.frameNo > 480 && this.slowWin >= 90) {
      if (this.slowFrames > 45) {
        const q = this.settings.quality;
        if (q === 'high') this.setAutoQuality('mid');
        else if (q === 'mid') this.setAutoQuality('low');
      }
      this.slowFrames = 0;
      this.slowWin = 0;
    }
  }

  private slowFrames: number = 0;
  private slowWin: number = 0;

  // 画质变化时的 UI 回调（Index 更新画布分辨率）
  onQualityChange: (pct: number) => void = (pct: number) => {
  };

  private setAutoQuality(id: string): void {
    this.settings.quality = id;
    this.applyQuality();
    this.sink.saveSettings(this.settings);
    if (this.onQualityChange) {
      this.onQualityChange(id === 'low' ? 0.62 : id === 'high' ? 1.0 : 0.8);
    }
    for (const q of QUALITY) {
      if (q.id === id) {
        this.msgs.push('已自动切换到「' + q.name + '」画质', '#7af0ff', true);
        break;
      }
    }
  }

  // ---------- 关卡加载 ----------
  loadMap(id: string): void {
    this.pendingMap = id;
    this.state = 'loading';
    this.loadStep = 0;
    this.loadPhase = 0;
    this.racers.length = 0;
    this.cars.length = 0;
    this.player = null;
    this.items = null;
    this.sink.onState('loading');
    this.sink.onProgress(0, '正在生成赛道：' + mapById(id).name);
  }

  private loadTick(): void {
    const map = mapById(this.pendingMap);
    if (this.loadPhase === 0) {
      this.map = map;
      const renderer = this.renderer;
      renderer.palette = new Palette();
      renderer.palette.fogColor = parseHex(map.fogColor);
      renderer.mountains = [];
      renderer.clouds = [];
      renderer.skyTop = map.sky.top;
      renderer.skyHorizon = map.sky.horizon;
      renderer.sunX = map.sky.sun[0];
      renderer.sunY = map.sky.sun[1];
      renderer.sunZ = map.sky.sun[2];
      renderer.sunColor = map.sky.sunColor;
      renderer.fogNear = map.fogNear;
      renderer.fogFar = map.fogFar;
      const track = new Track(LAYOUTS[map.layout], map.bridgeY);
      this.track = track;
      const pal = renderer.palette;
      pal.setSun(map.sky.sun[0], map.sky.sun[1], map.sky.sun[2]);
      const terrain = new Terrain(map, track, pal, map.id.charCodeAt(0) * 31 + 7);
      this.loadTerrain = terrain;
      this.loadPhase = 1;
      this.loadStep = 0;
      return;
    }
    if (this.loadPhase === 1) {
      const terrain = this.loadTerrain;
      if (terrain === null) return;
      if (this.loadStep === 0) terrain.setupOases();
      const that = this;
      const done = terrain.build(this.loadStep, (p: number) => {
        that.sink.onProgress(0.15 + p * 0.5, '正在生成地形…');
      });
      this.loadStep++;
      if (done) {
        this.loadPhase = 2;
        this.terrain = terrain;
        this.sink.onProgress(0.7, '正在铺设赛道…');
      }
      return;
    }
    if (this.loadPhase === 2) {
      const track = this.track as Track;
      const terrain = this.terrain as Terrain;
      const tm = new TrackMeshes();
      tm.groundYAt = (x: number, z: number): number => terrain.heightAt(x, z);
      tm.build(track, this.map, this.renderer.palette);
      this.trackMeshes = tm;
      terrain.buildMountains(mulberry32(map.id.length * 31 + 5), this.renderer);
      const rc = mulberry32(99);
      for (let i = 0; i < 22; i++) {
        const c = new CloudDot();
        c.angle = rc() * Math.PI * 2;
        c.dist = 900 + rc() * 1500;
        c.y = 180 + rc() * 380;
        c.size = 220 + rc() * 380;
        c.alpha = 0.55 + rc() * 0.3;
        this.renderer.clouds.push(c);
      }
      this.renderer.mapCx = track.cx;
      this.renderer.mapCz = track.cz;
      this.sink.onProgress(0.85, '正在布置场景…');
      this.loadPhase = 3;
      return;
    }
    if (this.loadPhase === 3) {
      const track = this.track as Track;
      const terrain = this.terrain as Terrain;
      this.props = PropsBuilder.build(this.map, track, terrain, this.renderer.palette);
      this.buildItemMeshes();
      this.skids.clear();
      this.smoke.clear();
      this.glow.clear();
      this.sink.onProgress(1, '完成');
      this.state = 'menu';
      this.sink.onState('menu');
      this.audio.setSong(this.map.bgm);
      this.settings.song = this.map.bgm;
      this.sink.saveSettings(this.settings);
      this.startDemo();
    }
  }

  private buildItemMeshes(): void {
    const pal = this.renderer.palette;
    const b = new MeshBuilder(pal, true);
    const boxC = pal.add(0x55c8ff);
    const boxC2 = pal.add(0x1d6ff2);
    addBox(b, 0, 0, 0, 1.8, 1.8, 1.8, 0, boxC, boxC2, boxC);
    this.boxMesh = b.build(400);
    // 导弹：沿 +Z（弹头朝前）
    const b2 = new MeshBuilder(pal, true);
    const white = pal.add(0xffffff);
    const red = pal.add(0xff3030);
    const n = 8;
    for (let k = 0; k < n; k++) {
      const a0 = (k / n) * Math.PI * 2;
      const a1 = ((k + 1) / n) * Math.PI * 2;
      const y0 = Math.cos(a0) * 0.22;
      const x0 = Math.sin(a0) * 0.22;
      const y1 = Math.cos(a1) * 0.22;
      const x1 = Math.sin(a1) * 0.22;
      b2.quad(x0, y0, -0.8, x1, y1, -0.8, x1, y1, 0.8, x0, y0, 0.8, white, -1);
      b2.quad(x0, y0, 0.8, x1, y1, 0.8, 0, 0, 1.3, 0, 0, 1.3, red, -1);
    }
    this.missileMesh = b2.build(600);
    const b3 = new MeshBuilder(pal, true);
    const yel = pal.add(0xffd400);
    const yelD = pal.add(0xd9a800);
    addPrism(b3, 0, 0, 0, 0.55, 0.35, 0.16, 7, 0, yel, yelD, yelD);
    this.bananaMesh = b3.build(300);
  }

  private renderLoading(): void {
    const g = this.renderer.ctx;
    g.fillStyle = '#0a142e';
    g.fillRect(0, 0, this.renderer.W, this.renderer.H);
  }

  // ---------- 车手 ----------
  private carVisual(skinIndex: number): CarVisual {
    const hit = this.carCache.get(skinIndex);
    if (hit !== undefined) return hit;
    const cv = buildCarVisual(CAR_SKINS[skinIndex % CAR_SKINS.length], this.renderer.palette);
    this.carCache.set(skinIndex, cv);
    return cv;
  }

  makeRacers(withPlayer: boolean): void {
    this.racers.length = 0;
    this.cars.length = 0;
    this.player = null;
    const S = this.settings;
    const rnd = mulberry32((Date.now() & 0xffff) + 7);
    const diff = DIFFS[S.diff];
    const skins: number[] = [];
    for (let i = 0; i < CAR_SKINS.length; i++) {
      if (i !== S.skin) skins.push(i);
    }
    for (let i = skins.length - 1; i > 0; i--) {
      const j = Math.floor(rnd() * (i + 1));
      const t = skins[i];
      skins[i] = skins[j];
      skins[j] = t;
    }
    const names = AI_NAMES.slice();
    for (let i = names.length - 1; i > 0; i--) {
      const j = Math.floor(rnd() * (i + 1));
      const t = names[i];
      names[i] = names[j];
      names[j] = t;
    }
    const total = 6;
    const playerSlot = withPlayer ? 3 : -1;
    let ai = 0;
    for (let k = 0; k < total; k++) {
      const d = -14 - Math.floor(k / 2) * 11;
      const lat = (k % 2 ? 1 : -1) * 5.5;
      let r: RacerBase;
      let skinIndex: number;
      if (k === playerSlot) {
        const p = new PlayerCar(this.track as Track, '我');
        p.reset(d, lat);
        r = p;
        this.player = p;
        skinIndex = S.skin;
      } else {
        const skin = withPlayer ? skins[ai % skins.length] : (k + S.skin) % CAR_SKINS.length;
        const skill = lerp(diff.skill[0], diff.skill[1], withPlayer ? rnd() : 0.8 + rnd() * 0.2);
        const a = new AICar(this.track as Track, names[ai % names.length], skill, rnd);
        a.reset(d, lat);
        r = a;
        skinIndex = skin;
      }
      r.slot = k;
      r.lapTimes = [];
      r.items = [];
      r.itemTimer = 2 + rnd() * 2;
      r.finished = false;
      r.finishTime = 0;
      r.skinIndex = skinIndex;
      if (r.isPlayer) {
        const p = r as PlayerCar;
        p.lapsDone = -1;
        p.owed = true;
        p.half = false;
        p.lastD = p.d;
      }
      this.racers.push(r);
      this.cars.push(new CarEntry(r, this.carVisual(skinIndex)));
      ai++;
    }
    for (const r of this.racers) this.updateProgress(r, true);
    this.standings = this.racers.slice();
  }

  startDemo(): void {
    if (this.track === null) return;
    this.state = 'menu';
    this.makeRacers(false);
    this.raceTime = 0;
    this.demoTarget = 0;
    this.demoT = 0;
    this.items = null;
  }

  startRace(): void {
    if (this.state === 'loading' || this.track === null) return;
    this.itemMode = this.settings.mode === 'item';
    this.makeRacers(true);
    this.items = this.itemMode
      ? new ItemSystem(this.track as Track, this, mulberry32(Date.now() & 0xffff))
      : null;
    this.msgs.clear();
    this.lines.clear();
    this.skids.clear();
    this.state = 'countdown';
    this.cdT = 0;
    this.cdShown = -1;
    this.cdText = '';
    this.raceTime = 0;
    this.firstFinish = -1;
    this.startBoostReady = false;
    this.startTried = false;
    this.resultShown = false;
    this.finishT = 0;
    const P = this.player as PlayerCar;
    this.camYaw = P.h;
    this.snapCamera();
    this.audio.setSong(this.settings.song);
    this.audio.startMusic();
    this.sink.onState('countdown');
  }

  toMenu(): void {
    this.state = 'menu';
    this.sink.onState('menu');
    this.audio.silence();
    this.startDemo();
  }

  togglePause(): void {
    if (this.state === 'race' || this.state === 'countdown' || this.state === 'finish') {
      this.pausedFrom = this.state;
      this.state = 'paused';
      this.sink.onState('paused');
      this.audio.silence();
    } else if (this.state === 'paused') {
      this.state = this.pausedFrom;
      this.sink.onState(this.state);
      this.lastT = Date.now();
    }
  }

  cycleCamera(): void {
    this.camMode = (this.camMode + 1) % 3;
  }

  // ---------- 主循环 ----------
  private step(dt: number): void {
    const st = this.state;
    const racing = st === 'race';
    const inp = this.input.build(racing || st === 'countdown');
    if (st === 'countdown') {
      this.cdT += dt;
      const n = Math.floor(this.cdT);
      if (n !== this.cdShown && n <= 3) {
        this.cdShown = n;
        this.cdText = n < 3 ? String(3 - n) : 'GO!';
        this.audio.play(n < 3 ? 'count' : 'go', 0);
      }
      if (inp.upPressed && !this.startTried) {
        this.startTried = true;
        if (this.cdT > 2.72) this.startBoostReady = true;
      }
      if (this.cdT >= 3) {
        this.state = 'race';
        this.sink.onState('race');
        this.raceTime = 0;
        if (this.startBoostReady) this.applyStartBoost();
        const that = this;
        setTimeout(() => {
          that.cdText = '';
        }, 700);
      }
    }
    if (st === 'finish' || st === 'race' || st === 'menu') this.raceTime += dt;

    const P = this.player;
    let pin = inp;
    if (P !== null) {
      if (P.finished || this.resultShown) pin = this.autopilot(P);
      if (inp.resetPressed && racing && !P.finished) this.resetPlayer();
      if (this.itemMode && racing && !P.finished && this.items !== null) {
        if (inp.nitroPressed) this.items.use(P);
        if (inp.swapPressed) this.items.swap(P);
      }
    }
    const active = racing || st === 'finish';
    const aiActive = racing || st === 'menu' || st === 'finish';
    this.acc += dt;
    let first = true;
    while (this.acc >= DT) {
      this.acc -= DT;
      if (P !== null) {
        const useIn = first ? pin : this.stripEdges(pin);
        P.update(DT, useIn, active, this.itemMode);
      }
      first = false;
      for (const r of this.racers) {
        if (r.isPlayer) continue;
        const a = r as AICar;
        a.update(DT, aiActive, this.raceTime, this.rubber(r));
      }
      this.collide();
    }
    for (const e of this.cars) this.syncVisual(e, dt);
    for (const r of this.racers) this.updateProgress(r, false);
    this.standings = this.racers.slice().sort((a: RacerBase, b: RacerBase): number => {
      if (a.finished && b.finished) return a.finishTime - b.finishTime;
      if (a.finished) return -1;
      if (b.finished) return 1;
      return b.progress - a.progress;
    });
    if (this.items !== null && (racing || st === 'finish')) {
      this.items.update(dt, this.racers, this.standings);
      for (const r of this.racers) {
        if (!r.isPlayer && !r.finished) this.items.aiThink(r, dt);
      }
    }
    if (P !== null) this.handleEvents(P);
    this.emitEffects(dt);
    this.smoke.update(dt);
    this.glow.update(dt);
    this.msgs.update(dt);
    if (this.map.snowfall) this.snowTick(dt);
    if (P !== null && (racing || st === 'finish' || st === 'countdown')) this.updateHud();
    if (racing || st === 'finish') this.checkRaceEnd(dt);
    if (P !== null && st !== 'menu') {
      this.audio.setEngine(Math.min(1.2, Math.abs(P.s) / TUNE.vmaxNitro), P.throttle, P.boosting,
        P.drifting && !P.airborne, true);
    } else {
      this.audio.silence();
    }
  }

  private stripEdges(pin: InputState): InputState {
    const s = new InputState();
    s.up = pin.up;
    s.down = pin.down;
    s.left = pin.left;
    s.right = pin.right;
    s.shift = pin.shift;
    return s;
  }

  private snowTick(dt: number): void {
    this.snowSpawn += dt * 60;
    const cam = this.renderer;
    while (this.snowSpawn > 0) {
      this.snowSpawn--;
      const a = Math.random() * Math.PI * 2;
      const r = Math.random() * 40;
      this.snow.emit(cam.camX + Math.sin(a) * r, cam.camY + 18 + Math.random() * 10, cam.camZ + Math.cos(a) * r,
        (Math.random() - 0.5) * 2, -2.4 - Math.random() * 1.6, (Math.random() - 0.5) * 2,
        4 + Math.random() * 2, 0.28, 0.28, 1, 1, 1, 0.55, 0, 0);
    }
    this.snow.update(dt);
  }

  private rubber(r: RacerBase): number {
    const P = this.player;
    if (P === null || this.state === 'menu') return 1;
    const diff = DIFFS[this.settings.diff];
    const gap = r.progress - P.progress;
    if (gap > 0) return Math.max(diff.rubber[0], 1 - gap * 0.00045);
    return Math.min(diff.rubber[1], 1 - gap * 0.0004);
  }

  private applyStartBoost(): void {
    const P = this.player as PlayerCar;
    P.startBoost = 1.4;
    P.s = Math.max(P.s, 16);
    this.msgs.push('起步加速!', '#ffd23a', false);
    this.audio.play('small', 0);
  }

  private resetPlayer(): void {
    const P = this.player as PlayerCar;
    const tr = this.track as Track;
    const s = tr.sample(P.d, new TrackSample());
    const keepLap = P.lapsDone;
    const owed = P.owed;
    const half = P.half;
    const gauge = P.gauge;
    const nitroCount = P.nitroCount;
    P.reset(P.d, clamp(P.lat, -4, 4));
    P.lapsDone = keepLap;
    P.owed = owed;
    P.half = half;
    P.gauge = gauge;
    P.nitroCount = nitroCount;
    P.lastD = P.d;
    P.h = s.hd;
    P.m = s.hd;
    P.s = 12;
    this.msgs.push('复位', '#ffffff', true);
  }

  private autopilot(P: PlayerCar): InputState {
    const s = (this.track as Track).sample(P.d + 18, this.tmpSample);
    const want = Math.atan2(s.x - P.x, s.z - P.z);
    const e = wrapAngle(want - P.h);
    const inp = new InputState();
    inp.up = Math.abs(P.s) < 38;
    inp.left = e > 0.04;
    inp.right = e < -0.04;
    return inp;
  }

  // ---------- 进度 / 圈数 ----------
  private updateProgress(r: RacerBase, init: boolean): void {
    const tr = this.track as Track;
    const L = tr.length;
    if (r.isPlayer) {
      const p = r as PlayerCar;
      const d = p.d;
      if (!init) {
        if (p.lastD > 0.75 * L && d < 0.25 * L) {
          if (p.owed) {
            p.lapsDone++;
            p.owed = false;
          } else if (p.half) {
            p.lapsDone++;
            p.half = false;
            this.onLap(r);
          }
        } else if (p.lastD < 0.25 * L && d > 0.75 * L) {
          p.lapsDone--;
          p.owed = true;
        }
        if (d > 0.4 * L && d < 0.6 * L) p.half = true;
      }
      p.lastD = d;
      r.progress = p.lapsDone * L + d;
    } else {
      const laps = Math.floor(r.dist / L);
      if (!init && laps > r.lapsDone && laps >= 1) {
        r.lapsDone = laps;
        this.onLap(r);
      }
      r.lapsDone = laps;
      r.progress = r.dist;
    }
  }

  private onLap(r: RacerBase): void {
    if (this.state !== 'race' && this.state !== 'finish') return;
    const t = this.raceTime - r.lapStart;
    r.lapStart = this.raceTime;
    r.lapTimes.push(t);
    const laps = this.settings.laps;
    if (r.lapsDone >= laps && !r.finished) {
      r.finished = true;
      r.finishTime = this.raceTime;
      if (this.firstFinish < 0) this.firstFinish = this.raceTime;
      if (r.isPlayer) {
        this.msgs.push('完成比赛!', '#ffd23a', false);
        this.audio.play('finish', 0);
        this.state = 'finish';
        this.sink.onState('finish');
        this.finishT = 0;
      }
      return;
    }
    if (r.isPlayer) {
      let best = Infinity;
      for (const lt of r.lapTimes) {
        if (lt < best) best = lt;
      }
      this.audio.play('lap', 0);
      const extra = t <= best && r.lapTimes.length > 1 ? ' 最佳!' : '';
      this.msgs.push('第 ' + r.lapsDone + ' 圈 ' + formatTime(t) + extra, '#6dff9e', true);
      if (r.lapsDone === laps - 1) {
        const that = this;
        setTimeout(() => {
          that.msgs.push('最后一圈!', '#ff5fa8', false);
        }, 900);
      }
    }
  }

  private checkRaceEnd(dt: number): void {
    const P = this.player;
    if (this.resultShown || P === null) return;
    if (this.state === 'finish') {
      this.finishT += dt;
      let allDone = true;
      for (const r of this.racers) {
        if (!r.finished) allDone = false;
      }
      if (this.finishT > 4 && (allDone || this.raceTime - this.firstFinish > 10 || this.finishT > 12)) {
        this.showResults();
      }
      return;
    }
    if (this.firstFinish >= 0 && !P.finished) {
      const left = 10 - (this.raceTime - this.firstFinish);
      this.finalText = '有车手已冲线！剩余 ' + Math.max(0, Math.ceil(left)) + ' 秒';
      if (left <= 0) this.showResults();
    }
  }

  private showResults(): void {
    this.resultShown = true;
    this.finalText = '';
    const res = new ResultData();
    const P = this.player as PlayerCar;
    const place = this.standings.indexOf(P) + 1;
    res.title = !P.finished ? '未完成比赛' : place === 1 ? '冠军！' : '第 ' + place + ' 名';
    res.win = P.finished && place === 1;
    const st = P.stats;
    const statPairs: string[][] = [
      ['漂移', String(st.drift)], ['小喷', String(st.small)], ['完美小喷', String(st.perfect)],
      ['双喷', String(st.double)], ['氮气', String(st.nitro)], ['最高时速', String(Math.round(st.top))],
      ['碰撞', String(st.crash)],
    ];
    for (const sp of statPairs) res.stats.push(sp[1] + ' ' + sp[0]);
    const L = (this.track as Track).length;
    for (let i = 0; i < this.standings.length; i++) {
      const r = this.standings[i];
      const row = new ResultRow();
      row.pos = i + 1;
      row.name = r.name;
      let best = 0;
      if (r.lapTimes.length > 0) {
        best = r.lapTimes[0];
        for (const lt of r.lapTimes) {
          if (lt < best) best = lt;
        }
      }
      row.best = formatTime(best);
      row.me = r.isPlayer;
      row.total = r.finished ? formatTime(r.finishTime)
        : '未完成 (' + Math.floor(Math.max(0, Math.min(99, (r.progress / L) * 100 / this.settings.laps))) + '%)';
      res.rows.push(row);
    }
    const that = this;
    setTimeout(() => {
      that.sink.onResult(res);
    }, 500);
  }

  racerAhead(r: RacerBase): RacerBase | null {
    const i = this.standings.indexOf(r);
    return i > 0 ? this.standings[i - 1] : null;
  }

  // ---------- 碰撞 ----------
  private collide(): void {
    const rs = this.racers;
    const R = 3.1;
    for (let i = 0; i < rs.length; i++) {
      for (let j = i + 1; j < rs.length; j++) {
        const a = rs[i];
        const b = rs[j];
        const dx = b.x - a.x;
        const dz = b.z - a.z;
        const d2 = dx * dx + dz * dz;
        if (d2 > R * R || Math.abs(a.y - b.y) > 2.5) continue;
        const d = Math.sqrt(d2) || 0.01;
        const nx = dx / d;
        const nz = dz / d;
        const over = R - d;
        this.pushRacer(a, -nx * over * 0.5, -nz * over * 0.5);
        this.pushRacer(b, nx * over * 0.5, nz * over * 0.5);
        const va = this.vel(a);
        const vb = this.vel(b);
        const rel = (vb[0] - va[0]) * nx + (vb[1] - va[1]) * nz;
        if (rel < 0) {
          const imp = -rel * 0.5;
          this.kick(a, -nx * imp, -nz * imp);
          this.kick(b, nx * imp, nz * imp);
          if ((a.isPlayer || b.isPlayer) && imp > 3) {
            this.audio.play('crash', imp);
            this.shake = Math.max(this.shake, 0.3);
            this.sparks((a.x + b.x) / 2, (a.y + b.y) / 2 + 0.6, (a.z + b.z) / 2, 10);
          }
        }
      }
    }
  }

  private vel(r: RacerBase): number[] {
    if (r.isPlayer) {
      return [Math.sin(r.m) * r.s, Math.cos(r.m) * r.s];
    }
    const s = (this.track as Track).sample(r.dist, this.tmp2);
    return [s.tx * r.s + s.rx * r.latV, s.tz * r.s + s.rz * r.latV];
  }

  private pushRacer(r: RacerBase, px: number, pz: number): void {
    if (r.isPlayer) {
      r.x += px;
      r.z += pz;
      return;
    }
    const s = (this.track as Track).sample(r.dist, this.tmp2);
    r.lat += px * s.rx + pz * s.rz;
    r.pushD += px * s.tx + pz * s.tz;
  }

  private kick(r: RacerBase, vx: number, vz: number): void {
    if (r.isPlayer) {
      const cx = Math.sin(r.m) * r.s + vx;
      const cz = Math.cos(r.m) * r.s + vz;
      const ns = Math.hypot(cx, cz);
      if (r.s >= 0 && ns > 0.5) {
        r.s = ns;
        r.m = Math.atan2(cx, cz);
      }
      return;
    }
    const s = (this.track as Track).sample(r.dist, this.tmp2);
    r.s = Math.max(0, r.s + vx * s.tx + vz * s.tz);
    r.latV += vx * s.rx + vz * s.rz;
  }

  hitRacer(r: RacerBase, kind: string): void {
    if (r.shield > 0) {
      r.shield = 0;
      this.sfx('shield', r);
      if (r.isPlayer) this.msgs.push('天使护体!', '#ffe28a', true);
      return;
    }
    r.spin = kind === 'missile' ? 1.3 : 1.0;
    r.s *= 0.35;
    if (kind === 'missile') {
      r.airborne = true;
      r.vy = 8;
    }
    if (r.isPlayer) {
      const p = r as PlayerCar;
      p.endDrift(false);
      this.msgs.push(kind === 'missile' ? '被导弹击中!' : '踩到香蕉皮!', '#ff4b4b', false);
      this.shake = 0.8;
    }
    this.sfx(kind === 'missile' ? 'boom' : 'banana', r);
  }

  sfx(name: string, r: RacerBase): void {
    const P = this.player;
    if (P === null) return;
    const d = Math.hypot(r.x - P.x, r.z - P.z);
    if (d < 120) this.audio.play(name, 0);
  }

  onItemGet(): void {
    this.audio.play('item', 0);
  }

  onMissileLock(): void {
    this.missileWarn = 1.6;
    this.audio.play('wrong', 0);
  }

  burst(x: number, y: number, z: number, color: number): void {
    const r = ((color >> 16) & 255) / 255;
    const g = ((color >> 8) & 255) / 255;
    const b = (color & 255) / 255;
    for (let i = 0; i < 22; i++) {
      this.glow.emit(x, y, z, (Math.random() - 0.5) * 14, (Math.random() - 0.2) * 10, (Math.random() - 0.5) * 14,
        0.5 + Math.random() * 0.3, 1.2, 0.2, r, g, b, 1, 6, 2);
    }
  }

  explode(x: number, y: number, z: number): void {
    for (let i = 0; i < 30; i++) {
      this.glow.emit(x, y, z, (Math.random() - 0.5) * 22, Math.random() * 14, (Math.random() - 0.5) * 22,
        0.5 + Math.random() * 0.5, 3, 0.5, 1, 0.5 + Math.random() * 0.4, 0.15, 1, 10, 2);
    }
    for (let i = 0; i < 14; i++) {
      this.smoke.emit(x, y, z, (Math.random() - 0.5) * 8, Math.random() * 6, (Math.random() - 0.5) * 8,
        1.2 + Math.random(), 3, 9, 0.3, 0.3, 0.32, 0.6, -1, 1.5);
    }
  }

  trail(x: number, y: number, z: number): void {
    this.glow.emit(x, y, z, (Math.random() - 0.5), (Math.random() - 0.5), (Math.random() - 0.5),
      0.25, 1.2, 0.2, 1, 0.6, 0.2, 1, 0, 0);
    this.smoke.emit(x, y, z, (Math.random() - 0.5), Math.random(), (Math.random() - 0.5),
      0.8, 0.8, 3, 0.85, 0.85, 0.88, 0.4, 0, 0);
  }

  sparks(x: number, y: number, z: number, n: number): void {
    for (let i = 0; i < n; i++) {
      this.glow.emit(x, y, z, (Math.random() - 0.5) * 16, Math.random() * 7, (Math.random() - 0.5) * 16,
        0.4 + Math.random() * 0.4, 0.5, 0.1, 1, 0.75 + Math.random() * 0.25, 0.3, 1, 18, 1);
    }
  }

  dust(x: number, y: number, z: number): void {
    for (let i = 0; i < 20; i++) {
      this.smoke.emit(x + (Math.random() - 0.5) * 3, y + 0.3, z + (Math.random() - 0.5) * 3,
        (Math.random() - 0.5) * 8, Math.random() * 2, (Math.random() - 0.5) * 8,
        1 + Math.random(), 2, 6, 0.85, 0.8, 0.72, 0.5, -0.5, 1.5);
    }
  }

  boostBurst(r: RacerBase, color: number): void {
    const cr = ((color >> 16) & 255) / 255;
    const cg = ((color >> 8) & 255) / 255;
    const cb = (color & 255) / 255;
    const bx = r.x - Math.sin(r.h) * 2.5;
    const bz = r.z - Math.cos(r.h) * 2.5;
    for (let i = 0; i < 24; i++) {
      this.glow.emit(bx, r.y + 0.6, bz,
        (Math.random() - 0.5) * 10 - Math.sin(r.h) * 10, Math.random() * 4,
        (Math.random() - 0.5) * 10 - Math.cos(r.h) * 10,
        0.35 + Math.random() * 0.3, 1.6, 0.2, cr, cg, cb, 1, 0, 3);
    }
  }

  // ---------- 玩家事件 ----------
  private handleEvents(P: PlayerCar): void {
    const st = P.stats;
    if (P.speedKmh > st.top) st.top = P.speedKmh;
    for (const e of P.events) {
      if (e.type === 'driftStart') st.drift++;
      else if (e.type === 'smallBoost' || e.type === 'landBoost') {
        st.small++;
        if (e.perfect) st.perfect++;
        this.msgs.push(e.perfect ? '完美小喷!' : e.type === 'landBoost' ? '落地喷!' : '小喷!', '#ff9a1f', false);
        this.audio.play('small', 0);
        this.boostBurst(P, 0xffa040);
      } else if (e.type === 'double') {
        st.double++;
        this.msgs.push('双喷!!', '#ff5fa8', false);
        this.audio.play('double', 0);
      } else if (e.type === 'nitro') {
        st.nitro++;
        this.msgs.push('氮气加速!', '#27c7ff', false);
        this.audio.play('nitro', 0);
        this.boostBurst(P, 0x39a8ff);
        this.shake = Math.max(this.shake, 0.25);
      } else if (e.type === 'gaugeFull') {
        this.msgs.push('集气完成 +1 N₂O', '#7af0ff', true);
        this.audio.play('gauge', 0);
      } else if (e.type === 'crash') {
        st.crash++;
        this.audio.play('crash', e.p0);
        this.shake = Math.max(this.shake, Math.min(0.9, e.p0 * 0.05));
        this.sparks(e.x, P.y + 0.6, e.z, 18);
      } else if (e.type === 'scrape') {
        if (Math.random() < 0.3) this.sparks(e.x, P.y + 0.5, e.z, 2);
        if (Math.random() < 0.08) this.audio.play('scrape', 0);
      } else if (e.type === 'land') {
        if (e.p0 > 0.25) {
          this.audio.play('land', 0);
          this.shake = Math.max(this.shake, 0.3);
          this.dust(P.x, P.y, P.z);
        }
      } else if (e.type === 'pad') {
        this.msgs.push('加速带!', '#27c7ff', true);
        this.audio.play('pad', 0);
      }
    }
    P.events.length = 0;
  }

  // ---------- 特效发射 ----------
  private emitEffects(dt: number): void {
    const R = Math.random;
    for (const e of this.cars) {
      const r = e.racer;
      const far = (r.x - this.renderer.camX) * (r.x - this.renderer.camX)
        + (r.z - this.renderer.camZ) * (r.z - this.renderer.camZ) > 250 * 250;
      const h = r.h;
      const fxv = Math.sin(h);
      const fzv = Math.cos(h);
      const lx = Math.cos(h);
      const lz = -Math.sin(h);
      const sp = Math.abs(r.s);
      const drifting = r.drifting && !r.airborne && sp > 10;
      for (let w = 0; w < 2; w++) {
        const sx = w ? 0.93 : -0.93;
        const wx = r.x + lx * sx - fxv * 1.38;
        const wz = r.z + lz * sx - fzv * 1.38;
        const key = (r.isPlayer ? 'p' : String(r.slot)) + '-' + String(w);
        if (drifting) {
          this.skids.add(key, wx, r.y, wz, lx, lz, 0.2, r.isPlayer ? 1 : 0.7);
          if (!far) {
            const rate = (r.isPlayer ? 30 : 12) * dt;
            let n = Math.floor(rate);
            if (R() < rate - n) n++;
            for (let k = 0; k < n; k++) {
              this.smoke.emit(wx + (R() - 0.5) * 0.6, r.y + 0.25, wz + (R() - 0.5) * 0.6,
                (R() - 0.5) * 2 - fxv * sp * 0.08, 0.8 + R() * 1.2, (R() - 0.5) * 2 - fzv * sp * 0.08,
                0.8 + R() * 0.7, 1.3, 5 + R() * 2, 0.95, 0.95, 0.97, r.isPlayer ? 0.42 : 0.3, -0.6, 1.2);
            }
            if (r.isPlayer && R() < 0.5) {
              this.glow.emit(wx, r.y + 0.2, wz, (R() - 0.5) * 3, R() * 3, (R() - 0.5) * 3,
                0.25, 0.5, 0.1, 0.5, 0.85, 1, 1, 8, 1);
            }
          }
        } else this.skids.cut(key);
      }
      const nitro = r.nitroTime > 0;
      const small = r.smallBoost > 0 || r.padTime > 0 || r.startBoost > 0;
      if ((nitro || small) && !far) {
        for (const sx of [-0.42, 0.42]) {
          const ex = r.x + lx * sx - fxv * 2.6;
          const ez = r.z + lz * sx - fzv * 2.6;
          const n = nitro ? 2 : 1;
          for (let k = 0; k < n; k++) {
            const cr = nitro ? (R() < 0.5 ? 0.3 : 0.85) : 1;
            const cg = nitro ? (R() < 0.5 ? 0.7 : 0.95) : 0.6;
            const cb = nitro ? 1 : 0.2;
            this.glow.emit(ex, r.y + 0.45, ez,
              -fxv * 6 + (R() - 0.5) * 2, R() * 1.5, -fzv * 6 + (R() - 0.5) * 2,
              0.18 + R() * 0.1, nitro ? 1.3 : 0.9, 0.2, cr, cg, cb, 1, 0, 0);
          }
        }
      }
      if (r.isPlayer && r.magnet > 0 && r.magnetTarget !== null && !far) {
        const t = r.magnetTarget;
        for (let k = 0; k < 3; k++) {
          const f = R();
          this.glow.emit(lerp(r.x, t.x, f), lerp(r.y, t.y, f) + 1, lerp(r.z, t.z, f), 0, 0, 0,
            0.12, 0.8, 0.3, 0.8, 0.4, 1, 1, 0, 0);
        }
      }
    }
  }

  // ---------- 车辆姿态同步 ----------
  private syncVisual(e: CarEntry, dt: number): void {
    const r = e.racer;
    const tr = this.track as Track;
    const i = clamp(r.hint, 0, tr.N - 1);
    const rel = r.h - tr.hd[i];
    const slopeAlong = tr.slope[i] * Math.cos(rel);
    const bankAlong = tr.bank[i] * Math.cos(rel);
    let pitchT: number;
    if (r.isPlayer) {
      const p = r as PlayerCar;
      pitchT = p.airborne ? clamp(-p.vy * 0.012, -0.3, 0.3) : -Math.atan(slopeAlong);
      e.rollVis = damp(e.rollVis, -bankAlong, 10, dt);
      const sp = Math.abs(p.s);
      const lean = p.drifting ? p.driftDir * 0.07 : p.steer * 0.045 * clamp(sp / 30, 0, 1);
      const pitchDyn = p.throttle > 0 && sp < 30 ? -0.025 : p.throttle < 0 && p.s > 5 ? 0.04 : 0;
      e.leanRoll = damp(e.leanRoll, lean, 8, dt);
      e.leanPitch = damp(e.leanPitch, pitchDyn - (p.nitroTime > 0 ? 0.02 : 0), 6, dt);
      e.steerVis = p.drifting ? -p.driftDir * 0.3 : p.steer * 0.38;
      e.wheelSpin += (p.s * dt) / 0.47;
    } else {
      const a = r as AICar;
      pitchT = a.airborne ? clamp(-a.vy * 0.012, -0.3, 0.3) : -Math.atan(a.slope * Math.cos(rel));
      e.rollVis = damp(e.rollVis, -a.bank * Math.cos(rel), 10, dt);
      e.leanRoll = damp(e.leanRoll, a.drifting ? a.driftDir * 0.07 : 0, 6, dt);
      e.leanPitch = damp(e.leanPitch, 0, 6, dt);
      e.steerVis = a.drifting ? -a.driftDir * 0.3 : clamp(wrapAngle(a.yawOff) * 2, -0.4, 0.4);
      e.wheelSpin += (a.s * dt) / 0.47;
    }
    e.pitchVis = damp(e.pitchVis, pitchT, 10, dt);
    e.pose.set(r.x, r.y, r.z, r.h + r.spinAng, e.pitchVis, e.rollVis, e.leanRoll, e.leanPitch, e.steerVis, e.wheelSpin);
  }

  // ---------- 相机 ----------
  private snapCamera(): void {
    const P = this.player;
    if (P === null) return;
    this.camYaw = P.h;
    this.camX = P.x - Math.sin(P.h) * 9;
    this.camY = P.y + 3.4;
    this.camZ = P.z - Math.cos(P.h) * 9;
    this.lookX = P.x;
    this.lookY = P.y + 1;
    this.lookZ = P.z;
  }

  private updateCamera(dt: number): void {
    const st = this.state;
    let target: RacerBase | null = this.player;
    if (st === 'menu') {
      this.demoT += dt;
      if (this.demoT > 9) {
        this.demoT = 0;
        this.demoTarget = (this.demoTarget + 1) % Math.max(1, this.racers.length);
      }
      target = this.racers.length > 0 ? this.racers[this.demoTarget] : null;
    }
    if (target === null) return;
    const tx = target.x;
    const ty = target.y;
    const tz = target.z;
    if (st === 'menu' || (st === 'finish' && this.resultShown)) {
      const a = this.time * 0.25 + this.demoTarget;
      const wx = tx + Math.sin(a) * 11;
      const wy = ty + 3.2 + Math.sin(this.time * 0.4) * 1.2;
      const wz = tz + Math.cos(a) * 11;
      const k = 1 - Math.exp(-3 * dt);
      this.camX = lerp(this.camX, wx, k);
      this.camY = lerp(this.camY, wy, k);
      this.camZ = lerp(this.camZ, wz, k);
      this.lookX = tx;
      this.lookY = ty + 1;
      this.lookZ = tz;
      this.camFov = damp(this.camFov, 55, 3, dt);
      return;
    }
    const P = target;
    const modes: number[][] = [
      [8.2, 3.0, 5, 1.3],
      [12.5, 4.6, 6, 1.5],
      [5.2, 1.9, 8, 1.1],
    ];
    const m = modes[this.camMode];
    const yawT = P.s >= 0 ? P.m + wrapAngle(P.h - P.m) * 0.35 : P.h;
    this.camYaw = dampAngle(this.camYaw, yawT, P.drifting ? 4.5 : 7, dt);
    const boostPull = P.nitroTime > 0 ? 1.6 : P.smallBoost > 0 ? 0.8 : 0;
    const dist = m[0] + Math.abs(P.s) * 0.018 + boostPull;
    const wx = P.x - Math.sin(this.camYaw) * dist;
    let wy = P.y + m[1];
    const wz = P.z - Math.cos(this.camYaw) * dist;
    const terrain = this.terrain;
    if (terrain !== null) {
      const gy = terrain.heightAt(wx, wz) + 1.0;
      if (wy < gy) wy = gy;
    }
    if (P.airborne && wy < P.y + m[1]) wy = P.y + m[1];
    const k = 1 - Math.exp(-14 * dt);
    this.camX = lerp(this.camX, wx, k);
    this.camY = damp(this.camY, wy, 8, dt);
    this.camZ = lerp(this.camZ, wz, k);
    const lx = P.x + Math.sin(this.camYaw) * m[2];
    const ly = P.y + m[3];
    const lz = P.z + Math.cos(this.camYaw) * m[2];
    const k2 = 1 - Math.exp(-18 * dt);
    this.lookX = lerp(this.lookX, lx, k2);
    this.lookY = lerp(this.lookY, ly, k2);
    this.lookZ = lerp(this.lookZ, lz, k2);
    if (this.shake > 0) {
      const kk = this.shake * this.shake;
      this.camX += (Math.random() - 0.5) * kk * 1.2;
      this.camY += (Math.random() - 0.5) * kk * 1.0;
      this.camZ += (Math.random() - 0.5) * kk * 1.2;
      this.shake = Math.max(0, this.shake - dt * 1.8);
    }
    if (P.nitroTime > 0) {
      this.camX += (Math.random() - 0.5) * 0.06;
      this.camY += (Math.random() - 0.5) * 0.06;
    }
    const fovT = 66 + Math.abs(P.s) * 0.12 + (P.nitroTime > 0 ? 9 : 0) + (P.smallBoost > 0 ? 4 : 0);
    this.camFov = damp(this.camFov, fovT, 4, dt);
  }

  // ---------- 渲染 ----------
  private fpsSmooth: number = 60;
  private frameNo: number = 0;
  private msGeoAcc: number = 0;
  private msFlushAcc: number = 0;
  private msPartsAcc: number = 0;

  private render(dt: number): void {
    if (this.track === null) return;
    this.frameNo++;
    this.fpsSmooth = this.fpsSmooth * 0.95 + (1 / Math.max(0.001, dt)) * 0.05;
    const r = this.renderer;
    const tGeo0 = Date.now();
    this.updateCamera(dt);
    const camPitch = Math.atan2(this.lookY - this.camY,
      Math.hypot(this.lookX - this.camX, this.lookZ - this.camZ));
    const camYaw = Math.atan2(this.lookX - this.camX, this.lookZ - this.camZ);
    r.setCamera(this.camX, this.camY, this.camZ, camYaw, camPitch, this.camFov);
    r.drawSky();
    r.drawClouds();
    r.drawMountains();
    const water = this.map.water;
    if (water !== null && !water.local) {
      r.drawWater(water.y, water.deep, water.color, this.time);
    }
    const tSky = Date.now();
    r.clearList();
    const terrain = this.terrain;
    if (terrain !== null) terrain.render(r);
    const tTer = Date.now();
    const tm = this.trackMeshes;
    if (tm !== null) {
      for (const mesh of tm.near) r.drawMesh(mesh, null, 0);
      for (const mesh of tm.far) r.drawMesh(mesh, null, 0);
      for (const mesh of tm.extras) r.drawMesh(mesh, null, 0);
    }
    for (const mesh of this.props) r.drawMesh(mesh, null, 0);
    const tMesh = Date.now();
    this.renderItems();
    for (const e of this.cars) this.renderCar(e);
    // 绿洲水面（埃及）
    if (terrain !== null && water !== null && water.local) {
      const wc = r.palette.add(parseHex(water.color));
      for (const o of terrain.oases) {
        const n = 10;
        const rad = o[2] + 8;
        const wy = water.y + 0.1;
        for (let k = 0; k < n; k++) {
          const a0 = (k / n) * Math.PI * 2;
          const a1 = ((k + 1) / n) * Math.PI * 2;
          r.pushWorldQuad(
            o[0] + Math.sin(a0) * rad, wy, o[1] + Math.cos(a0) * rad,
            o[0] + Math.sin(a1) * rad, wy, o[1] + Math.cos(a1) * rad,
            o[0], wy, o[1],
            o[0], wy, o[1],
            wc, 1.1);
        }
      }
    }
    const tFlush0 = Date.now();
    r.flushGeometry();
    const tParts0 = Date.now();
    r.drawSkids(this.skids);
    r.drawParticles(this.smoke, false);
    if (this.map.snowfall) r.drawParticles(this.snow, false);
    r.drawParticles(this.glow, true);
    const tParts1 = Date.now();
    this.renderOverlays(dt);
    this.renderMiniSpeed();
    // 性能统计：每 120 帧向 hilog 输出一次
    this.msSkyAcc += (tSky - tGeo0);
    this.msTerAcc += (tTer - tSky);
    this.msMeshAcc += (tMesh - tTer);
    this.msCarAcc += (tFlush0 - tMesh);
    this.msFlushAcc += r.getFlushMs();
    this.msPartsAcc += (tParts1 - tParts0);
    if (this.frameNo % 120 === 0) {
      const st = r.stat;
      console.info(`[PERF] fps=${this.fpsSmooth.toFixed(0)} sky=${(this.msSkyAcc / 120).toFixed(1)} ` +
        `ter=${(this.msTerAcc / 120).toFixed(1)} mesh=${(this.msMeshAcc / 120).toFixed(1)} ` +
        `car=${(this.msCarAcc / 120).toFixed(1)} flush=${(this.msFlushAcc / 120).toFixed(1)} ` +
        `parts=${(this.msPartsAcc / 120).toFixed(1)}ms faces=${st.facesPushed} fills=${st.fills} W=${r.W}x${r.H}`);
      this.msSkyAcc = 0;
      this.msTerAcc = 0;
      this.msMeshAcc = 0;
      this.msCarAcc = 0;
      this.msFlushAcc = 0;
      this.msPartsAcc = 0;
    }
  }

  private msSkyAcc: number = 0;
  private msTerAcc: number = 0;
  private msMeshAcc: number = 0;
  private msCarAcc: number = 0;

  private renderItems(): void {
    const r = this.renderer;
    const it = this.items;
    if (it === null) return;
    if (this.boxMesh !== null) {
      for (const b of it.boxes) {
        if (!b.visible) continue;
        const mat = Mat34.compose(b.x, b.y + Math.sin(this.time * 2 + b.x) * 0.2, b.z,
          b.spin, Math.sin(b.spin * 0.8) * 0.25, 0);
        r.drawMesh(this.boxMesh, mat, 0);
      }
    }
    if (this.bananaMesh !== null) {
      for (const bn of it.bananas) {
        const mat = Mat34.compose(bn.x, bn.y, bn.z, bn.age * 1.5, 0, 0);
        r.drawMesh(this.bananaMesh, mat, 0);
      }
    }
    if (this.missileMesh !== null) {
      for (const m of it.missiles) {
        const yaw = Math.atan2(m.dx, m.dz);
        const pitch = -Math.asin(clamp(m.dy, -1, 1));
        const mat = Mat34.compose(m.x, m.y, m.z, yaw, pitch, 0);
        r.drawMesh(this.missileMesh, mat, 0);
      }
    }
  }

  private renderCar(e: CarEntry): void {
    const r = this.renderer;
    const car = e.racer;
    const dx = car.x - r.camX;
    const dz = car.z - r.camZ;
    const distSq = dx * dx + dz * dz;
    // 底盘光（近处才画，光晕大时才有意义）
    if (distSq < 60 * 60 && r.project(car.x, car.y + 0.1, car.z, this.pr)) {
      const rr = (2.9 / this.pr[2]) * r.focal;
      if (rr > 5) {
        const g = r.ctx;
        const glow = e.visual.skin.glow;
        const hex = '#' + '000000'.substring(0, 6 - glow.toString(16).length) + glow.toString(16);
        g.globalAlpha = 0.28;
        g.fillStyle = hex;
        g.beginPath();
        g.ellipse(this.pr[0], this.pr[1], rr, rr * 0.45, 0, 0, Math.PI * 2);
        g.fill();
        g.globalAlpha = 1;
      }
    }
    const dynYaw = car.h + car.spinAng;
    // 远车（>150m）画简化车身（~18 面），近车画全部件（车轮 >110m 跳过）
    if (distSq > 150 * 150 && e.visual.simpleBody !== null) {
      matMulInto(e.pose.scratch, e.pose.root, e.pose.lean);
      r.drawMesh(e.visual.simpleBody, e.pose.scratch, dynYaw);
    } else {
      for (const part of e.visual.parts) {
        if (part.mode >= 2 && distSq > 110 * 110) continue;
        const mat = carPartMatrix(e.visual, e.pose, part);
        r.drawMesh(part.mesh, mat, dynYaw);
      }
    }
    // 护盾
    if (car.shield > 0 && r.project(car.x, car.y + 0.8, car.z, this.pr)) {
      const rr = (3.2 / this.pr[2]) * r.focal;
      if (rr > 4) {
        const g = r.ctx;
        g.globalAlpha = 0.22 + Math.sin(this.time * 8) * 0.06;
        g.fillStyle = '#ffe28a';
        g.beginPath();
        g.arc(this.pr[0], this.pr[1], rr, 0, Math.PI * 2);
        g.fill();
        g.globalAlpha = 0.8;
        g.strokeStyle = '#ffe28a';
        g.lineWidth = 2;
        g.stroke();
        g.globalAlpha = 1;
      }
    }
    // 名字标签：限距 + 每 3 帧 + 帧率低时去描边（文字渲染在低端机很贵）
    if (!car.isPlayer && distSq < 300 * 300 && this.frameNo % 3 === 0) {
      r.labelStroke = this.fpsSmooth >= 45;
      r.drawLabel(car.name, car.x, car.y + 2.6, car.z, 20, false, '#ffffff');
    }
  }

  private renderOverlays(dt: number): void {
    const r = this.renderer;
    const g = r.ctx;
    const W = r.W;
    const H = r.H;
    const P = this.player;
    // 速度线（合批：单路径一次 stroke）
    if (P !== null && (this.state === 'race' || this.state === 'finish')) {
      const k = clamp((Math.abs(P.s) - 42) / 30, 0, 1) * 0.6 + (P.nitroTime > 0 ? 0.6 : 0) + (P.smallBoost > 0 ? 0.25 : 0);
      this.lines.update(dt, k);
      if (this.lines.items.length > 0) {
        const cx = W / 2;
        const cy = H * 0.45;
        const D = Math.hypot(W, H) / 2;
        g.strokeStyle = P.nitroTime > 0 ? '#bfe9ff' : '#ffffff';
        g.globalAlpha = Math.min(1, k * 1.2) * 0.4;
        g.lineWidth = 1.8 * (W / 1400);
        g.beginPath();
        for (const L of this.lines.items) {
          g.moveTo(cx + Math.cos(L.a) * L.r * D, cy + Math.sin(L.a) * L.r * D * 0.75);
          g.lineTo(cx + Math.cos(L.a) * (L.r + L.l) * D, cy + Math.sin(L.a) * (L.r + L.l) * D * 0.75);
        }
        g.stroke();
        g.globalAlpha = 1;
      }
    }
    // 飘字消息（低画质去掉 shadowBlur 发光，只留描边）
    if (this.msgs.items.length > 0) {
      g.textAlign = 'center';
      g.textBaseline = 'middle';
      let idx = 0;
      for (const m of this.msgs.items) {
        const t = m.t;
        const scale = t < 0.12 ? lerp(2.2, 1, t / 0.12) : t > 0.9 ? lerp(1, 0.9, (t - 0.9) / 0.25) : 1;
        const alpha = t > 0.85 ? Math.max(0, 1 - (t - 0.85) / 0.3) : 1;
        const size = (m.small ? 26 : 44) * scale * (W / 900);
        g.font = 'italic 900 ' + size + 'px sans-serif';
        g.globalAlpha = alpha;
        g.lineWidth = size * 0.14;
        g.strokeStyle = 'rgba(0,0,0,0.5)';
        const yy = H * 0.3 + idx * size * 1.3 - (t > 0.85 ? (t - 0.85) * 80 : 0);
        g.strokeText(m.text, W / 2, yy);
        if (!r.lowGfx) {
          g.shadowColor = m.color;
          g.shadowBlur = 18;
        }
        g.fillStyle = m.color;
        g.fillText(m.text, W / 2, yy);
        g.shadowBlur = 0;
        g.globalAlpha = 1;
        idx++;
      }
    }
    // 倒计时
    if (this.cdText !== '') {
      const size = 180 * (W / 900);
      g.font = 'italic 900 ' + size + 'px sans-serif';
      g.textAlign = 'center';
      g.textBaseline = 'middle';
      g.lineWidth = size * 0.03;
      g.strokeStyle = 'rgba(90,40,0,0.85)';
      g.strokeText(this.cdText, W / 2, H / 2);
      if (!r.lowGfx) {
        g.shadowColor = '#ff8a00';
        g.shadowBlur = 40;
      }
      g.fillStyle = '#ffffff';
      g.fillText(this.cdText, W / 2, H / 2);
      g.shadowBlur = 0;
    }
    // 性能叠层（左上角小字）
    {
      const st = r.stat;
      g.font = '600 11px monospace';
      g.textAlign = 'left';
      g.textBaseline = 'top';
      g.fillStyle = 'rgba(255,255,255,0.85)';
      g.fillText(`FPS ${this.fpsSmooth.toFixed(0)}  F${st.facesPushed} P${st.facesFilled} DR${st.fills}`, 8, 4);
    }
    // 警告
    let warn: string = '';
    if (P !== null && P.wrongWay > 1.2 && this.state === 'race') warn = '⚠ 方向错误！';
    if (this.missileWarn > 0) {
      this.missileWarn -= dt;
      warn = '⚠ 导弹锁定！';
    }
    this.warnText = warn;
    if (warn !== '') {
      const size = 30 * (W / 900);
      g.font = '900 ' + size + 'px sans-serif';
      g.textAlign = 'center';
      g.fillStyle = Math.floor(this.time * 4) % 2 === 0 ? '#ff4b4b' : '#ff8888';
      g.fillText(warn, W / 2, H * 0.2);
    }
    if (this.finalText !== '') {
      const size = 22 * (W / 900);
      g.font = '700 ' + size + 'px sans-serif';
      g.textAlign = 'center';
      g.fillStyle = '#ffd23a';
      g.fillText(this.finalText, W / 2, 90 * (H / 500));
    }
  }

  // ---------- 小地图 / 码表 ----------
  private mmTransform(x: number, z: number, W: number): number[] {
    const track = this.track as Track;
    const pad = 26;
    const sc = (W - pad * 2) / Math.max(track.maxX - track.minX, track.maxZ - track.minZ);
    return [W / 2 + (x - track.cx) * sc, W / 2 - (z - track.cz) * sc];
  }

  private renderMiniSpeed(): void {
    if (this.time - this.mmT < 0.1) return;
    this.mmT = this.time;
    const P = this.player;
    if (P === null) return;
    const mm = this.mmCtx;
    if (mm !== null) {
      const W = mm.width;
      const track = this.track as Track;
      mm.clearRect(0, 0, W, W);
      mm.lineJoin = 'round';
      mm.beginPath();
      for (let i = 0; i <= track.N; i += 4) {
        const k = i % track.N;
        const pt = this.mmTransform(track.px[k], track.pz[k], W);
        if (i === 0) mm.moveTo(pt[0], pt[1]);
        else mm.lineTo(pt[0], pt[1]);
      }
      mm.closePath();
      mm.strokeStyle = 'rgba(0,0,0,0.55)';
      mm.lineWidth = 14;
      mm.stroke();
      mm.strokeStyle = 'rgba(255,255,255,0.92)';
      mm.lineWidth = 8;
      mm.stroke();
      mm.strokeStyle = 'rgba(39,199,255,0.9)';
      mm.lineWidth = 4;
      for (let i = 0; i < track.N; i += 2) {
        if (track.bridge[i] === 0) continue;
        const p1 = this.mmTransform(track.px[i], track.pz[i], W);
        const j = (i + 1) % track.N;
        const p2 = this.mmTransform(track.px[j], track.pz[j], W);
        mm.beginPath();
        mm.moveTo(p1[0], p1[1]);
        mm.lineTo(p2[0], p2[1]);
        mm.stroke();
      }
      for (const e of this.cars) {
        const rc = e.racer;
        if (rc.isPlayer) continue;
        const pt = this.mmTransform(rc.x, rc.z, W);
        const body = CAR_SKINS[rc.skinIndex % CAR_SKINS.length].body;
        const hex = '#' + '000000'.substring(0, 6 - body.toString(16).length) + body.toString(16);
        mm.fillStyle = hex;
        mm.strokeStyle = '#fff';
        mm.lineWidth = 3;
        mm.beginPath();
        mm.arc(pt[0], pt[1], 8, 0, Math.PI * 2);
        mm.fill();
        mm.stroke();
      }
      const pt = this.mmTransform(P.x, P.z, W);
      mm.save();
      mm.translate(pt[0], pt[1]);
      mm.rotate(P.h + Math.PI);
      mm.fillStyle = '#ffd23a';
      mm.strokeStyle = '#000';
      mm.lineWidth = 3;
      mm.beginPath();
      mm.moveTo(0, 16);
      mm.lineTo(11, -11);
      mm.lineTo(0, -5);
      mm.lineTo(-11, -11);
      mm.closePath();
      mm.fill();
      mm.stroke();
      mm.restore();
    }
    const sp = this.spCtx;
    if (sp !== null) {
      const W = sp.width;
      const c = W / 2;
      const R = W * 0.4;
      sp.clearRect(0, 0, W, W);
      const a0 = Math.PI * 0.75;
      const sweep = Math.PI * 1.5;
      const maxK = 300;
      sp.lineCap = 'round';
      sp.lineWidth = 24;
      sp.strokeStyle = 'rgba(8,20,50,0.7)';
      sp.beginPath();
      sp.arc(c, c, R, a0, a0 + sweep);
      sp.stroke();
      const f = Math.min(1, P.speedKmh / maxK);
      sp.lineWidth = 16;
      sp.strokeStyle = P.nitroTime > 0 ? '#7ae4ff' : '#ffd23a';
      sp.beginPath();
      sp.arc(c, c, R, a0, a0 + sweep * f);
      sp.stroke();
      sp.lineWidth = 3;
      sp.strokeStyle = 'rgba(255,255,255,0.7)';
      sp.fillStyle = 'rgba(255,255,255,0.75)';
      sp.font = 'italic 900 20px sans-serif';
      sp.textAlign = 'center';
      sp.textBaseline = 'middle';
      for (let k = 0; k <= 10; k++) {
        const a = a0 + (sweep * k) / 10;
        const r1 = R - 24;
        const r2 = R - (k % 2 ? 32 : 40);
        sp.beginPath();
        sp.moveTo(c + Math.cos(a) * r1, c + Math.sin(a) * r1);
        sp.lineTo(c + Math.cos(a) * r2, c + Math.sin(a) * r2);
        sp.stroke();
        if (k % 2 === 0) sp.fillText(String(k * 30), c + Math.cos(a) * (R - 58), c + Math.sin(a) * (R - 58));
      }
    }
  }

  // ---------- HUD ----------
  private updateHud(): void {
    this.hudTick++;
    if (this.hudTick % 4 !== 0) return;
    const P = this.player;
    if (P === null) return;
    const laps = this.settings.laps;
    const d = new HudData();
    d.itemMode = this.itemMode;
    d.lap = String(clamp(P.lapsDone + 1, 1, laps)) + '/' + String(laps);
    d.time = formatTime(P.finished ? P.finishTime : this.state === 'countdown' ? 0 : this.raceTime);
    let best = 0;
    if (P.lapTimes.length > 0) {
      best = P.lapTimes[0];
      for (const lt of P.lapTimes) {
        if (lt < best) best = lt;
      }
    }
    d.best = formatTime(best);
    d.kmh = P.speedKmh;
    d.rank = this.standings.indexOf(P) + 1;
    d.total = this.racers.length;
    d.gauge = P.gauge;
    d.nitro = P.nitroCount;
    d.nitroOn = P.nitroTime > 0;
    d.smallOn = P.smallBoost > 0 || P.startBoost > 0 || P.padTime > 0;
    for (let i = 0; i < this.standings.length; i++) {
      const rc = this.standings[i];
      const row = new StandingRow();
      row.name = rc.name;
      row.me = rc.isPlayer;
      row.fin = rc.finished;
      const body = CAR_SKINS[rc.skinIndex % CAR_SKINS.length].body;
      row.color = '#' + '000000'.substring(0, 6 - body.toString(16).length) + body.toString(16);
      d.standings.push(row);
    }
    if (this.itemMode) {
      for (const it of P.items) d.items.push(it);
    }
    this.sink.onHud(d);
  }
}
