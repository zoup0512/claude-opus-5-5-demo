/**
 * 对局主控：初始化、流程、战斗逻辑、帧构建与渲染提交。移植自原版 game.js。
 * 帧数据布局与 cpp/renderer.cpp 的常量一一对应。
 */
import nrender from 'libgameRenderer.so';
import { Vec3, Mat4, perspective, viewFromYPR, lookAt } from './math3d';
import { World, NavGrid, RayHit, PenHit } from './physics';
import { WEAPONS, weaponDef, WeaponState, WeaponDef, jitterDir } from './weapons';
import { buildMap, MapBuild, TEX_SOLDIER, TEX_GUNWEAR, TEX_CONTAINER_BASE, MESH_SOLDIER_BL, MESH_SOLDIER_GR,
  MESH_HANG } from './mapdata';
import * as tex from './textures';
import { buildGun, gunMeshId, GUN_IDS } from './guns';
import { buildSoldierGeometry } from './character';
import { Actor, GameHooks, GameOptsRef } from './actor';
import { Player } from './player';
import { Bot, BOT_NAMES } from './bots';
import { Effects, DecalRing, Particles } from './effects';
import { ViewModel } from './viewmodel';
import { audioSys } from './audio';

// ---------- 帧布局常量（与 C++ 一致） ----------
const F_FLAGS = 0;
const F_WORLDVP = 1;
const F_CAMPOS = 17;
const F_VMACTIVE = 20;
const F_VMVP = 21;
const F_SUNDIR = 37;
const F_SUNCOL = 40;
const F_HEMISKY = 43;
const F_HEMIGND = 46;
const F_FOGCOL = 49;
const F_FOGDEN = 52;
const F_TIME = 53;
const F_NSOLDIER = 54;
const F_NQUAD = 55;
const F_NPART = 56;
const F_OCEAN = 57;
const F_VMMESH = 58;
const F_VMMODEL = 59;
const F_NDYN = 75;
const F_SOLDIERS = 80;
const S_STRIDE = 322;
const F_DYN = F_SOLDIERS + 16 * S_STRIDE;
const D_STRIDE = 17;
const F_QUADS = F_DYN + 12 * D_STRIDE;
const Q_STRIDE = 24;
const F_PARTS = F_QUADS + 320 * Q_STRIDE;
const P_STRIDE = 9;
const FRAME_FLOATS = F_PARTS + 1200 * P_STRIDE;

// 特效纹理 id
const TEX_GLOW = 50;
const TEX_PUFF = 51;
const TEX_FLASH = 52;
const TEX_TRACER = 53;
const TEX_HOLE_M = 54;
const TEX_HOLE_W = 55;
const TEX_BLOOD = 56;
const TEX_SCORCH = 57;
const TEX_TAG_BASE = 100;

const MULTI = ['', '', '双杀', '三杀', '四杀', '五杀', '六杀！', '无人能挡', '超神'];

export class GameOptions implements GameOptsRef {
  team: string = 'BL';
  primary: string = 'ak47';
  size: number = 6;
  diff: string = 'normal';
  goal: number = 50;
  tod: string = 'day';
  sens: number = 1.0;
  fov: number = 78;
  vol: number = 0.8;
}

export class KillFeedItem {
  killer: string = '';
  killerTeam: string = '';
  victim: string = '';
  victimTeam: string = '';
  wid: string = '';
  hs: boolean = false;
  wall: boolean = false;
  mine: boolean = false;
  t: number = 0;
}

export class DmgDirItem {
  ang: number = 0;
  t: number = 0;

  constructor(ang: number, t: number) {
    this.ang = ang;
    this.t = t;
  }
}

export class RadarRect {
  x: number;
  z: number;
  hx: number;
  hz: number;
  yaw: number;
  top: number;
  mesh: boolean;

  constructor(x: number, z: number, hx: number, hz: number, yaw: number, top: number, mesh: boolean) {
    this.x = x;
    this.z = z;
    this.hx = hx;
    this.hz = hz;
    this.yaw = yaw;
    this.top = top;
    this.mesh = mesh;
  }
}

export class EndInfo {
  win: number = -1; // 1 胜 0 负 -1 平
  sBL: number = 0;
  sGR: number = 0;
  mvp: string = '';
  mine: string = '';
}

/** HUD 状态（UI 轮询） */
export class HudState {
  screen: string = 'loading'; // loading | menu | pause | end | loadout | game
  loadProgress: number = 0;
  loadText: string = '';
  scoreBL: number = 0;
  scoreGR: number = 0;
  timeLeft: number = 600;
  goal: number = 50;
  myTeam: string = 'BL';
  hp: number = 100;
  armor: number = 100;
  alive: boolean = true;
  weaponName: string = '';
  weaponHudName: string = '';
  mag: number = 0;
  reserve: number = 0;
  reloading: boolean = false;
  weaponId: string = '';
  slots: string[] = [];
  slotCur: number = 0;
  slotsT: number = 0;
  hitT: number = 0;
  hitKind: number = 0; // 0 普通 1 爆头 2 击杀
  dmgDirs: DmgDirItem[] = [];
  killFeed: KillFeedItem[] = [];
  badgeText: string = '';
  badgeSub: string = '';
  badgeT: number = 0;
  toastText: string = '';
  toastT: number = 0;
  centerBig: string = '';
  centerSmall: string = '';
  respawnIn: number = 0;
  protectT: number = 0;
  aimName: string = '';
  aimTeam: string = '';
  announceText: string = '';
  announceT: number = 0;
  fps: number = 0;
  scopeLevel: number = 0;
  spreadPx: number = 0;
  dmgFlash: number = 0;
  lowHp: number = 0;
  deathK: number = 0;
  protectK: number = 0;
  endInfo: EndInfo = new EndInfo();
  boardOpen: boolean = false;
}

interface TimerItem {
  t: number;
  fn: () => void;
}

interface Nade {
  pos: Vec3;
  vel: Vec3;
  fuse: number;
  owner: Actor;
  spinX: number;
  spinY: number;
  rotX: number;
  rotY: number;
}

interface TagEntry {
  actor: Actor;
  texId: number;
}

const _v1 = new Vec3();
const _v2 = new Vec3();
const _v3 = new Vec3();
const _v4 = new Vec3();
const _m1 = new Mat4();
const _m2 = new Mat4();
const _m3 = new Mat4();
const UP = new Vec3(0, 1, 0);

export class Game implements GameHooks {
  opts: GameOptions = new GameOptions();
  hud: HudState = new HudState();
  world: World = new World();
  nav: NavGrid = new NavGrid(new World(), 0, 0, 1, 1, 1, 0.4); // init 中替换为真实网格
  actors: Actor[] = [];
  player: Player | null = null;
  time: number = 0;
  frame: number = 0;
  playing: boolean = false;
  paused: boolean = false;
  ended: boolean = false;
  inLoadout: boolean = false;
  scoreBL: number = 0;
  scoreGR: number = 0;
  goal: number = 50;
  timeLeft: number = 600;
  fx: Effects = new Effects();
  vm: ViewModel = new ViewModel();
  rayScratch: RayHit = new RayHit();
  private timers: TimerItem[] = [];
  private nades: Nade[] = [];
  private tags: TagEntry[] = [];
  private frameBuf: Float32Array = new Float32Array(FRAME_FLOATS);
  private viewW: number = 1280;
  private viewH: number = 720;
  private aspect: number = 16 / 9;
  // 相机
  camPos: Vec3 = new Vec3(-20, 12, 30);
  camYaw: number = 0;
  camPitch: number = 0;
  camRoll: number = 0;
  camFov: number = 78;
  private camLookAt: Vec3 = new Vec3(0, 2, 0);
  private camIsLookAt: boolean = true;
  private realTime: number = 0;
  private lastTick: number = 0;
  private mapData: MapBuild | null = null;
  radarRects: RadarRect[] = [];
  private aimTarget: Actor | null = null;
  private killedBy: string = '';
  private fpsAcc: number = 0;
  private fpsN: number = 0;
  private shipSpeed: number = 6.5;
  private sunDir: Vec3 = new Vec3(0.5, 0.7, 0.3);
  private tod: string = 'day';
  private gunMuzzle: Vec3 = new Vec3();
  private hangT: number = 0;
  private lastSlotShown: number = -1;
  running: boolean = false;

  /** 分步初始化（UI 显示进度） */
  async init(onProgress: (p: number, text: string) => void): Promise<void> {
    // 等待原生 surface
    onProgress(0.05, '等待渲染表面');
    for (let i = 0; i < 100; i++) {
      if (nrender.surfaceReady()) {
        break;
      }
      await sleep(60);
    }
    const vs = nrender.viewSize();
    this.viewW = (vs >> 16) & 0xffff;
    this.viewH = vs & 0xffff;
    if (this.viewH > 0) {
      this.aspect = this.viewW / this.viewH;
    }
    onProgress(0.12, '生成纹理');
    await sleep(1);
    this.uploadTextures();
    onProgress(0.45, '搭建运输船');
    await sleep(1);
    this.mapData = buildMap(this.world);
    this.uploadMapMeshes();
    onProgress(0.62, '士兵与武器模型');
    await sleep(1);
    this.uploadActorMeshes();
    onProgress(0.72, '天空与海洋');
    await sleep(1);
    this.fx.initAmbient(this.mapData.funnelTop);
    onProgress(0.85, '计算寻路网格');
    await sleep(1);
    this.nav = new NavGrid(this.world, -36.2, -12.1, 36.2, 12.1, 0.5, 0.42);
    this.buildRadar();
    onProgress(0.95, '音频引擎');
    await sleep(1);
    await audioSys.init();
    audioSys.setVolume(this.opts.vol);
    this.applyTod(this.opts.tod);
    // 菜单环绕相机初始值
    this.camPos.set(-20, 12, 30);
    this.camIsLookAt = true;
    this.camLookAt.set(-4, 1.5, 0);
    onProgress(1, '完成');
    this.hud.screen = 'menu';
  }

  private uploadTextures(): void {
    const up = (id: number, t: tex.TexData): void => {
      nrender.createTexture(id, t.w, t.h, t.pixels);
    };
    up(1, tex.makeWhite());
    up(2, tex.makeDeck());
    for (let i = 0; i < 8; i++) {
      up(10 + i, tex.makeContainer(i));
    }
    up(20, tex.makeCrate('wood', 200));
    up(21, tex.makeCrate('wood', 201));
    up(22, tex.makeCrate('wood', 202));
    up(23, tex.makeCrate('ammo', 203));
    up(24, tex.makeCrate('metal', 204));
    up(30, tex.makeHull());
    up(31, tex.makeBulkhead());
    up(32, tex.makeSuperWall());
    up(40, tex.makeFence());
    up(41, tex.makeGrating());
    up(50, tex.makeGlow());
    up(51, tex.makePuff());
    up(52, tex.makeFlash());
    up(53, tex.makeTracer());
    up(54, tex.makeHoleMetal());
    up(55, tex.makeHoleWood());
    up(56, tex.makeBlood());
    up(57, tex.makeScorch());
    up(60, tex.makeSoldierFabric());
    up(61, tex.makeGunWear());
    up(62, tex.makeGunWood());
  }

  private uploadMapMeshes(): void {
    const md = this.mapData as MapBuild;
    let meshId = 200;
    md.batches.forEach((batch, key) => {
      const def = md.matDefs.get(key);
      if (def === undefined || batch.count() === 0) {
        return;
      }
      const vd = batch.build(def.color[0], def.color[1], def.color[2]);
      const matP = new Float32Array([1, 1, 1, def.rough, def.metal, def.emis, 0, 0]);
      nrender.uploadMesh(meshId, def.tex, def.flags, matP, vd.vdata, vd.idata);
      meshId++;
    });
    // 吊着的集装箱（动态摆动）
    const hangBatch = md.batches.get('c5');
    if (hangBatch !== undefined && hangBatch.count() > 0) {
      const vd = hangBatch.build(1, 1, 1);
      const matP = new Float32Array([1, 1, 1, 0.65, 0.3, 0, 0, 0]);
      nrender.uploadMesh(MESH_HANG, TEX_CONTAINER_BASE + 5, 0, matP, vd.vdata, vd.idata);
      md.batches.delete('c5');
    }
  }

  private uploadActorMeshes(): void {
    for (const team of ['BL', 'GR']) {
      const g = buildSoldierGeometry(team);
      const meshId = team === 'BL' ? MESH_SOLDIER_BL : MESH_SOLDIER_GR;
      const matP = new Float32Array([1, 1, 1, 0.82, 0.05, 0, 0, 0]);
      nrender.uploadMesh(meshId, TEX_SOLDIER, 8, matP, g.vdata, g.idata);
    }
    for (const id of GUN_IDS) {
      const gm = buildGun(id);
      const matP = new Float32Array([1, 1, 1, 0.45, 0.6, 0, 0, 0]);
      nrender.uploadMesh(gunMeshId(id), TEX_GUNWEAR, 0, matP, gm.vd.vdata, gm.vd.idata);
    }
    // 手雷单独一份（带放大）——直接复用枪械 he 网格
    void MESH_GRENADE;
  }

  private buildRadar(): void {
    this.radarRects = [];
    const cols = this.world.colliders;
    const sorted = cols.filter((k) => k.solid && k.top > 0.3 && k.bottom < 2 && k.hx < 30 && k.tag !== 'deck');
    sorted.sort((a, b) => a.top - b.top);
    for (const k of sorted) {
      if (k.bullet === 'pass' && k.surface !== 'mesh') {
        continue;
      }
      this.radarRects.push(new RadarRect(k.x, k.z, k.hx, k.hz, k.yaw, k.top, k.surface === 'mesh'));
    }
  }

  private applyTod(name: string): void {
    this.tod = name;
    const f = this.frameBuf;
    if (name === 'dusk') {
      this.sunDir.set(0.42, 0.16, 0.34).normalize();
      f[F_SUNDIR] = this.sunDir.x;
      f[F_SUNDIR + 1] = this.sunDir.y;
      f[F_SUNDIR + 2] = this.sunDir.z;
      f[F_SUNCOL] = 2.4;
      f[F_SUNCOL + 1] = 1.45;
      f[F_SUNCOL + 2] = 0.85;
      f[F_HEMISKY] = 0.85;
      f[F_HEMISKY + 1] = 0.62;
      f[F_HEMISKY + 2] = 0.52;
      f[F_HEMIGND] = 0.2;
      f[F_HEMIGND + 1] = 0.18;
      f[F_HEMIGND + 2] = 0.24;
      f[F_FOGCOL] = 0.78;
      f[F_FOGCOL + 1] = 0.55;
      f[F_FOGCOL + 2] = 0.42;
      f[F_FOGDEN] = 0.0013;
    } else {
      this.sunDir.set(0.55, 0.75, 0.36).normalize();
      f[F_SUNDIR] = this.sunDir.x;
      f[F_SUNDIR + 1] = this.sunDir.y;
      f[F_SUNDIR + 2] = this.sunDir.z;
      f[F_SUNCOL] = 2.9;
      f[F_SUNCOL + 1] = 2.72;
      f[F_SUNCOL + 2] = 2.45;
      f[F_HEMISKY] = 0.62;
      f[F_HEMISKY + 1] = 0.7;
      f[F_HEMISKY + 2] = 0.8;
      f[F_HEMIGND] = 0.3;
      f[F_HEMIGND + 1] = 0.33;
      f[F_HEMIGND + 2] = 0.38;
      f[F_FOGCOL] = 0.66;
      f[F_FOGCOL + 1] = 0.76;
      f[F_FOGCOL + 2] = 0.84;
      f[F_FOGDEN] = 0.0011;
    }
  }

  // ================= 流程 =================
  startMatch(): void {
    const o = this.opts;
    audioSys.init();
    audioSys.setVolume(o.vol);
    audioSys.startAmbient();
    audioSys.playUI('start');
    this.actors = [];
    this.nades = [];
    this.tags = [];
    this.timers = [];
    this.scoreBL = 0;
    this.scoreGR = 0;
    this.goal = o.goal;
    this.timeLeft = 600;
    this.applyTod(o.tod);
    const my = o.team;
    const other = my === 'BL' ? 'GR' : 'BL';
    const names: string[] = BOT_NAMES.slice();
    // 洗牌
    for (let i = names.length - 1; i > 0; i--) {
      const j = (Math.random() * (i + 1)) | 0;
      const t = names[i];
      names[i] = names[j];
      names[j] = t;
    }
    let id = 0;
    const player = new Player(this, id++, '我', my);
    player.primary = o.primary;
    this.player = player;
    this.actors.push(player);
    const N = o.size;
    const prim = (team: string, i: number): string => {
      if (i === 1 && N >= 4) {
        return 'awm';
      }
      if (i === 3 && N >= 6) {
        return 'mp5';
      }
      if (i === 5) {
        return team === 'BL' ? 'm4a1' : 'ak47';
      }
      return team === 'BL' ? 'ak47' : 'm4a1';
    };
    let tagIdx = 0;
    for (const team of [my, other]) {
      const count = team === my ? N - 1 : N;
      for (let i = 0; i < count; i++) {
        const name = names.length > 0 ? names.pop() as string : `Bot${id}`;
        const b = new Bot(this, id++, name, team, o.diff);
        b.primary = prim(team, team === my ? i + 1 : i);
        this.actors.push(b);
        if (team === my) {
          const texId = TEX_TAG_BASE + (tagIdx++);
          const td = tex.makeNameTag(b.name, b.team);
          nrender.createTexture(texId, td.w, td.h, td.pixels);
          this.tags.push({ actor: b, texId });
        }
      }
    }
    for (const a of this.actors) {
      this.spawnActor(a, true);
    }
    this.vm.equip(player.weapon().id, 0.6);
    this.playing = true;
    this.paused = false;
    this.ended = false;
    this.lastSlotShown = -1;
    this.hud.screen = 'game';
    this.timers.push({
      t: this.time + 0.4, fn: () => {
        this.announce('Go go go!');
      }
    });
    this.toast(`团队竞技 · 率先达到 ${this.goal} 击杀的队伍获胜`, 3.5);
  }

  spawnActor(a: Actor, first: boolean): void {
    const spawns = this.mapData !== null ? this.mapData.spawns.get(a.team) : undefined;
    if (spawns === undefined) {
      return;
    }
    let best = spawns[0];
    let bestScore = -1e9;
    for (const p of spawns) {
      let sc = Math.random() * 3;
      for (const o of this.actors) {
        if (!o.alive || o === a) {
          continue;
        }
        const d = Math.hypot(o.pos.x - p.x, o.pos.z - p.z);
        if (d < 1.2) {
          sc -= 100;
        }
        if (o.team !== a.team) {
          sc += Math.min(d, 40) * 0.1;
        }
      }
      if (sc > bestScore) {
        bestScore = sc;
        best = p;
      }
    }
    a.spawn(best.x, best.z, best.yaw);
    if (a instanceof Bot) {
      a.onSpawn();
    }
    if (a.isPlayer) {
      const p = a as Player;
      p.deathCam = null;
      this.vm.equip(a.weapon().id, first ? 0.6 : 0.5);
      audioSys.setLowHealth(false);
    }
  }

  pause(): void {
    this.paused = true;
    this.hud.screen = 'pause';
  }

  resume(): void {
    this.paused = false;
    this.hud.screen = 'game';
  }

  quitToMenu(): void {
    this.playing = false;
    this.paused = false;
    this.ended = true;
    audioSys.stopAmbient();
    audioSys.setLowHealth(false);
    this.actors = [];
    this.tags = [];
    this.player = null;
    this.hud.screen = 'menu';
  }

  toggleLoadout(): void {
    if (!this.playing) {
      return;
    }
    if (this.inLoadout) {
      this.closeLoadout();
      return;
    }
    this.inLoadout = true;
    this.hud.screen = 'loadout';
  }

  closeLoadout(): void {
    this.inLoadout = false;
    this.hud.screen = 'game';
  }

  chooseLoadout(id: string): void {
    const p = this.player;
    if (p === null) {
      return;
    }
    p.nextPrimary = id;
    this.opts.primary = id;
    const inSpawn = p.alive && (p.team === 'BL' ? p.pos.x < -28.3 : p.pos.x > 28.3);
    if (inSpawn) {
      p.primary = id;
      const seed = Math.random() * 6;
      const nw = new WeaponState(id);
      nw.patternSeed = seed;
      p.inv[0] = nw;
      p.slot = 0;
      p.readyAt = this.time + weaponDef(id).draw;
      p.soldier.setWeapon(id);
      this.vm.equip(id, weaponDef(id).draw);
      this.toast(`已更换为 ${weaponDef(id).name}`, 1.5);
    } else {
      this.toast(`复活后使用 ${weaponDef(id).name}`, 1.5);
    }
    audioSys.playUI('buy');
  }

  onOption(k: string, v: number | string): void {
    if (k === 'vol') {
      audioSys.setVolume(v as number);
    }
    if (k === 'tod') {
      this.applyTod(v as string);
    }
  }

  endMatch(): void {
    this.ended = true;
    this.playing = false;
    const p = this.player;
    if (p === null) {
      return;
    }
    const my = p.team;
    const other = my === 'BL' ? 'GR' : 'BL';
    const myScore = my === 'BL' ? this.scoreBL : this.scoreGR;
    const otherScore = other === 'BL' ? this.scoreBL : this.scoreGR;
    const win = myScore === otherScore ? -1 : myScore > otherScore ? 1 : 0;
    this.hud.endInfo.win = win;
    this.hud.endInfo.sBL = this.scoreBL;
    this.hud.endInfo.sGR = this.scoreGR;
    // MVP
    let mvp: Actor | null = null;
    let bestV = -1;
    for (const a of this.actors) {
      const v = a.stats.k * 2 - a.stats.d + a.stats.hs;
      if (v > bestV) {
        bestV = v;
        mvp = a;
      }
    }
    this.hud.endInfo.mvp = mvp !== null ? `${mvp.name}（${mvp.stats.k} 杀 / ${mvp.stats.hs} 爆头）` : '';
    const acc = p.stats.shots > 0 ? ((p.stats.hits / p.stats.shots) * 100).toFixed(1) : '0';
    this.hud.endInfo.mine = `${p.stats.k} 击杀 · ${p.stats.d} 死亡 · ${p.stats.hs} 爆头 · 命中率 ${acc}%`;
    this.hud.screen = 'end';
    audioSys.playUI('roundEnd');
    audioSys.setLowHealth(false);
    this.announce(win === 1 ? 'Mission accomplished' : win === -1 ? 'Draw' : 'Mission failed');
  }

  // ================= 战斗（GameHooks） =================
  onJump(a: Actor): void {
    audioSys.playJump(a.isPlayer ? null : a.pos);
  }

  onLand(a: Actor, sp: number): void {
    audioSys.playLand(a.isPlayer ? null : a.pos, a.ground !== null ? a.ground.surface : 'metal', Math.min(1, sp / 10));
  }

  onFootstep(a: Actor): void {
    if (!a.isPlayer && a.pos.distanceTo(this.camPos) > 30) {
      return;
    }
    audioSys.playFootstep(a.isPlayer ? null : a.pos, a.ground !== null ? a.ground.surface : 'metal');
    for (const b of this.actors) {
      if (b instanceof Bot && b.team !== a.team && b.pos.distanceTo(a.pos) < 12) {
        b.hear(a.pos, false);
      }
    }
  }

  onSwitch(a: Actor): void {
    if (!a.isPlayer) {
      return;
    }
    this.vm.equip(a.weapon().id, a.weapon().def.draw);
    audioSys.playWeaponSwitch(a.weapon().id);
  }

  onReloadStart(a: Actor, empty: boolean): void {
    if (!a.isPlayer) {
      return;
    }
    const d = a.weapon().def;
    const t = this.time;
    const id = d.id;
    this.vm.reload(d.reload, empty);
    this.timers.push({
      t: t + d.reload * 0.2, fn: () => {
        audioSys.playReload(id, 'magout');
      }
    });
    this.timers.push({
      t: t + d.reload * 0.6, fn: () => {
        audioSys.playReload(id, 'magin');
      }
    });
    if (empty) {
      this.timers.push({
        t: t + d.reload * 0.82, fn: () => {
          audioSys.playReload(id, id === 'awm' ? 'bolt' : 'boltback');
        }
      });
    }
  }

  onScope(a: Actor): void {
    if (a.isPlayer) {
      audioSys.playScope(a.scoped > 0);
    }
  }

  onDryFire(a: Actor): void {
    if (a.isPlayer) {
      audioSys.playDryFire();
    }
  }

  onGrenadeStart(a: Actor): void {
    if (a.isPlayer) {
      this.vm.throwNade();
      audioSys.playGrenadePin();
    }
  }

  fireWeapon(a: Actor, ws: WeaponState, spread: number): void {
    const d = ws.def;
    const eye = a.eye(_v1);
    const dir = a.forward(_v2);
    jitterDir(dir, spread, Math.random);
    let muzzle: Vec3;
    if (a.isPlayer) {
      const right = _v3.set(Math.cos(this.camYaw), 0, -Math.sin(this.camYaw));
      muzzle = _v4.copy(this.camPos).addScaledVector(dir, 0.9).addScaledVector(right, 0.14);
      muzzle.y -= 0.1;
      this.vm.fire();
      audioSys.playShot(d.id, null);
      if (Math.random() < 0.5) {
        audioSys.playShellDrop(null);
      }
    } else {
      // 第三人称枪口
      const gun = buildGun(a.soldier.gunId.length > 0 ? a.soldier.gunId : 'ak47');
      a.soldier.gunWorld(_m1);
      this.gunMuzzle.copy(gun.muzzle);
      _m1.transformPoint(this.gunMuzzle, this.gunMuzzle);
      muzzle = this.gunMuzzle;
      this.fx.muzzle(muzzle, dir, d.type === 'sniper' ? 1.6 : d.type === 'smg' ? 0.8 : 1);
      a.soldier.kick();
      audioSys.playShot(d.id, muzzle);
    }
    a.radarT = 1.6;
    for (const b of this.actors) {
      if (b !== a && b instanceof Bot && b.team !== a.team && b.pos.distanceTo(a.pos) < 45) {
        b.hear(a.pos, true);
      }
    }
    const end = this.traceBullet(a, eye, dir, d);
    if (!a.isPlayer || Math.random() < 0.35 || d.type === 'sniper') {
      this.fx.tracer(muzzle, end);
    }
    // 子弹掠过玩家
    const p = this.player;
    if (p !== null && p.alive && a !== p && a.team !== p.team) {
      const hp = p.eye(_v3);
      const t = _v4.copy(hp).sub(eye).dot(dir);
      if (t > 2 && t < eye.distanceTo(end)) {
        const cx = eye.x + dir.x * t - hp.x;
        const cy = eye.y + dir.y * t - hp.y;
        const cz = eye.z + dir.z * t - hp.z;
        if (cx * cx + cy * cy + cz * cz < 1.69) {
          audioSys.playBulletWhiz(_v3);
        }
      }
    }
  }

  traceBullet(shooter: Actor, o: Vec3, dir: Vec3, d: WeaponDef): Vec3 {
    const range = d.range;
    const hits: PenHit[] = this.world.raycastAll(o.x, o.y, o.z, dir.x, dir.y, dir.z, range);
    let power = d.pen;
    let mul = 1;
    let wall = false;
    let from = 0;
    this.frame++;
    const end = new Vec3();
    for (let i = 0; i <= hits.length; i++) {
      const h = i < hits.length ? hits[i] : null;
      const lim = h !== null ? h.t : range;
      // 角色命中
      let best: Actor | null = null;
      let bestT = lim;
      let part: string | null = null;
      for (const a of this.actors) {
        if (!a.alive || a === shooter || a.team === shooter.team) {
          continue;
        }
        const r = a.soldier.hitTest(o.x, o.y, o.z, dir.x, dir.y, dir.z, bestT, this.frame);
        if (r !== null && r.t > from - 0.01 && r.t < bestT) {
          best = a;
          bestT = r.t;
          part = r.part;
        }
      }
      if (best !== null && part !== null) {
        const pt = _v3.copy(o).addScaledVector(dir, bestT);
        const partMul = part === 'head' ? d.headMul : part === 'arm' || part === 'leg' ? d.limbMul : 1;
        const dmg = d.dmg * mul * Math.pow(d.falloff, bestT / 10) * partMul;
        this.fx.impact(pt, -dir.x, -dir.y, -dir.z, 'flesh', dir.x, dir.y, dir.z);
        audioSys.playImpact(pt, 'flesh');
        this.damage(best, shooter, dmg, part, d.id, dir, wall);
        return end.copy(pt);
      }
      if (h === null) {
        break;
      }
      const pt = _v3.copy(o).addScaledVector(dir, h.t);
      const mat = h.collider.mat;
      this.fx.impact(pt, h.nx, h.ny, h.nz, mat, dir.x, dir.y, dir.z);
      if (pt.distanceTo(this.camPos) < 40) {
        audioSys.playImpact(pt, mat === 'wood' ? 'wood' : 'metal');
      }
      if (h.collider.bullet === 'pen') {
        const thick = h.exit - h.t;
        const cost = thick * (mat === 'wood' ? 1.0 : 1.9);
        if (power > cost) {
          power -= cost;
          mul *= 0.6;
          wall = true;
          from = h.exit;
          continue;
        }
      } else if (Math.random() < 0.08 && mat === 'metal') {
        audioSys.playRicochet(pt);
      }
      return end.copy(pt);
    }
    return end.copy(o).addScaledVector(dir, range);
  }

  melee(a: Actor, heavy: boolean): void {
    const d = weaponDef('knife');
    const range = heavy ? d.rangeHeavy : d.rangeLight;
    const eye = a.eye(_v1);
    const base = a.forward(_v2);
    if (a.isPlayer) {
      this.vm.melee(heavy);
    }
    this.frame++;
    let hitActor: Actor | null = null;
    let hitT = 0;
    let hitPart: string | null = null;
    let hitDir: Vec3 | null = null;
    for (const off of [0, 0.12, -0.12, 0.24, -0.24]) {
      const dir = _v3.copy(base);
      // 绕 Y 旋转 off
      const c = Math.cos(off), s = Math.sin(off);
      const nx = dir.x * c + dir.z * s;
      const nz = -dir.x * s + dir.z * c;
      dir.x = nx;
      dir.z = nz;
      for (const b of this.actors) {
        if (!b.alive || b === a || b.team === a.team) {
          continue;
        }
        const r = b.soldier.hitTest(eye.x, eye.y, eye.z, dir.x, dir.y, dir.z, range, this.frame);
        if (r !== null && (hitActor === null || r.t < hitT)) {
          hitActor = b;
          hitT = r.t;
          hitPart = r.part;
          hitDir = _v4.copy(dir);
        }
      }
      if (hitActor !== null) {
        break;
      }
    }
    const delay = heavy ? 0.33 : 0.1;
    const hd = hitDir !== null ? hitDir.clone() : null;
    const ha = hitActor;
    const hp = hitPart;
    const ht = hitT;
    const eyeC = eye.clone();
    const baseC = base.clone();
    this.timers.push({
      t: this.time + delay, fn: () => {
        if (!a.alive) {
          return;
        }
        if (ha !== null && hd !== null && ha.alive) {
          const vf = ha.forward(new Vec3());
          vf.y = 0;
          vf.normalize();
          const flatX = hd.x;
          const flatZ = hd.z;
          const fl = Math.hypot(flatX, flatZ) || 1;
          const back = vf.x * (flatX / fl) + vf.z * (flatZ / fl) > 0.5;
          let dmg = heavy ? d.dmgHeavy : d.dmgLight;
          if (back) {
            dmg *= heavy ? 2 : 1.6;
          }
          if (hp === 'head') {
            dmg *= 1.3;
          }
          const pt = new Vec3().copy(eyeC).addScaledVector(hd, ht);
          this.fx.impact(pt, -hd.x, -hd.y, -hd.z, 'flesh', hd.x, hd.y, hd.z);
          audioSys.playKnife(heavy ? 'heavy' : 'light', 'flesh', a.isPlayer ? null : eyeC);
          this.damage(ha, a, dmg, hp !== null ? hp : 'chest', 'knife', hd, false, true);
        } else {
          const w = this.world.raycast(eyeC.x, eyeC.y, eyeC.z, baseC.x, baseC.y, baseC.z, range, 'bullet',
            this.rayScratch);
          if (w !== null) {
            const pt = new Vec3().copy(eyeC).addScaledVector(baseC, w.t);
            this.fx.impact(pt, w.nx, w.ny, w.nz, w.collider.mat, baseC.x, baseC.y, baseC.z);
            audioSys.playKnife(heavy ? 'heavy' : 'light', 'wall', a.isPlayer ? null : eyeC);
          } else {
            audioSys.playKnife(heavy ? 'heavy' : 'light', 'miss', a.isPlayer ? null : eyeC);
          }
        }
      }
    });
  }

  throwGrenade(a: Actor): void {
    const eye = a.eye(_v1);
    const dir = a.forward(_v2);
    const right = _v3.set(Math.cos(a.yaw), 0, -Math.sin(a.yaw));
    const pos = new Vec3().copy(eye).addScaledVector(dir, 0.5).addScaledVector(right, 0.12);
    const vel = new Vec3().copy(dir).scale(16);
    vel.y += 2.8;
    vel.addScaledVector(a.vel, 0.6);
    this.nades.push({
      pos, vel, fuse: weaponDef('he').fuse, owner: a,
      spinX: Math.random() * 10, spinY: Math.random() * 10, rotX: 0, rotY: 0
    });
    audioSys.playGrenadeThrow();
    for (const b of this.actors) {
      if (b instanceof Bot && b.team !== a.team && b.pos.distanceTo(pos) < 20) {
        b.hear(pos, false);
      }
    }
  }

  private updateNades(dt: number): void {
    const W = this.world;
    for (let i = this.nades.length - 1; i >= 0; i--) {
      const n = this.nades[i];
      n.fuse -= dt;
      const steps = 3;
      const h = dt / steps;
      for (let s = 0; s < steps; s++) {
        n.vel.y -= 14 * h;
        const sp = n.vel.length();
        if (sp < 1e-4) {
          continue;
        }
        const dx = n.vel.x / sp, dy = n.vel.y / sp, dz = n.vel.z / sp;
        const L = sp * h + 0.07;
        const hit = W.raycast(n.pos.x, n.pos.y, n.pos.z, dx, dy, dz, L, 'move', this.rayScratch);
        if (hit !== null) {
          const nn = _v1.set(hit.nx, hit.ny, hit.nz);
          n.pos.addScaledVector(_v2.set(dx, dy, dz), Math.max(0, hit.t - 0.07));
          const vn = n.vel.dot(nn);
          n.vel.addScaledVector(nn, -1.45 * vn);
          n.vel.scale(0.55);
          if (Math.abs(vn) > 2) {
            audioSys.playGrenadeBounce(n.pos);
          }
          if (nn.y > 0.7 && Math.abs(n.vel.y) < 1.2) {
            n.vel.y = 0;
            n.vel.x *= 0.8;
            n.vel.z *= 0.8;
          }
          n.spinX *= 0.6;
          n.spinY *= 0.6;
        } else {
          n.pos.addScaledVector(n.vel, h);
        }
      }
      n.rotX += n.spinX * dt;
      n.rotY += n.spinY * dt;
      if (n.fuse <= 0) {
        this.explode(n.pos, n.owner);
        this.nades.splice(i, 1);
      }
    }
  }

  explode(p: Vec3, owner: Actor): void {
    const d = weaponDef('he');
    this.fx.explosion(p);
    audioSys.playExplosion(p);
    const camD = this.camPos.distanceTo(p);
    this.fx.shake = Math.max(this.fx.shake, Math.max(0, 1.4 - camD / 18));
    for (const a of this.actors) {
      if (!a.alive) {
        continue;
      }
      if (a.team === owner.team && a !== owner) {
        continue;
      }
      const c = a.soldier.chestWorld(_v1);
      const dist = c.distanceTo(p);
      if (dist > d.radius) {
        continue;
      }
      const dir = _v2.copy(c).sub(p);
      const L = dir.length();
      dir.scale(1 / (L || 1));
      const blocked = this.world.raycast(p.x, p.y + 0.2, p.z, dir.x, dir.y, dir.z, Math.max(0, L - 0.3), 'bullet',
        this.rayScratch);
      let dmg = d.dmg * Math.pow(1 - dist / d.radius, 1.1);
      if (blocked !== null) {
        dmg *= 0.2;
      }
      if (dmg > 1) {
        this.damage(a, owner, dmg, 'chest', 'he', dir, false);
      }
    }
    for (const b of this.actors) {
      if (b instanceof Bot && b.pos.distanceTo(p) < 40) {
        b.hear(p, true);
      }
    }
  }

  damage(v: Actor, att: Actor | null, amt: number, part: string, wid: string, dir: Vec3, wall: boolean,
    meleeHit: boolean = false): void {
    if (!v.alive || v.protectT > 0) {
      return;
    }
    if (att !== null && att !== v && att.team === v.team) {
      return;
    }
    const def = WEAPONS.get(wid);
    let hpD = amt;
    if (v.armor > 0 && part !== 'leg') {
      const ap = def !== undefined ? def.armorPen : 0.75;
      hpD = amt * ap;
      v.armor = Math.max(0, v.armor - amt * (1 - ap) * 1.4);
    }
    v.hp -= hpD;
    v.lastAttacker = att;
    v.lastHurt = this.time;
    const killed = v.hp <= 0;
    if (att !== null && att !== v) {
      att.stats.hits++;
    }
    if (v.isPlayer) {
      if (att !== null && att !== v) {
        const ang = Math.atan2(-(att.pos.x - v.pos.x), -(att.pos.z - v.pos.z));
        this.hud.dmgDirs.push(new DmgDirItem(ang, 1.4));
        if (this.hud.dmgDirs.length > 6) {
          this.hud.dmgDirs.shift();
        }
      }
      v.aimPunch += Math.min(0.05, hpD * 0.0012);
      audioSys.playHurt(Math.min(100, hpD));
      this.hud.dmgFlash = Math.min(1.2, this.hud.dmgFlash + hpD / 45);
      if (v.hp <= 30 && !killed) {
        audioSys.setLowHealth(true);
      }
    } else if (v instanceof Bot) {
      v.onDamaged(att);
    }
    const p = this.player;
    if (att !== null && att.isPlayer && att !== v) {
      this.hud.hitT = killed ? 0.45 : 0.22;
      this.hud.hitKind = killed ? 2 : part === 'head' ? 1 : 0;
      audioSys.playHitmarker(part === 'head');
    }
    if (killed) {
      this.kill(v, att, wid, part === 'head' && !meleeHit, wall, dir);
    }
  }

  kill(v: Actor, att: Actor | null, wid: string, hs: boolean, wall: boolean, dir: Vec3): void {
    v.alive = false;
    v.hp = 0;
    v.deadT = 0;
    v.respawnT = 4.0;
    v.stats.d++;
    v.scoped = 0;
    v.soldier.die(dir.x, dir.z, hs);
    audioSys.playDeath(v.soldier.chestWorld(_v1));
    const p = this.player;
    if (att !== null && att !== v) {
      att.stats.k++;
      if (hs) {
        att.stats.hs++;
      }
      if (att.team === 'BL') {
        this.scoreBL++;
      } else {
        this.scoreGR++;
      }
      att.multi = this.time - att.lastKillT < 5 ? att.multi + 1 : 1;
      att.lastKillT = this.time;
      att.streak++;
    }
    // 击杀信息
    const kf = new KillFeedItem();
    kf.killer = att !== null && att !== v ? att.name : '';
    kf.killerTeam = att !== null && att !== v ? att.team : '';
    kf.victim = v.name;
    kf.victimTeam = v.team;
    kf.wid = wid;
    kf.hs = hs;
    kf.wall = wall;
    kf.mine = att === p || v === p;
    kf.t = this.realTime;
    this.hud.killFeed.unshift(kf);
    while (this.hud.killFeed.length > 6) {
      this.hud.killFeed.pop();
    }
    if (att !== null && att === p && v !== p) {
      const m = Math.min(att.multi, 8);
      let text = '击杀';
      let sub = `击杀 ${v.name}`;
      if (m >= 2) {
        text = MULTI[m];
        sub = MULTI[m] + ' · ' + sub;
        this.timers.push({
          t: this.time + 0.15, fn: () => {
            this.announce('MULTI KILL');
          }
        });
      } else if (hs) {
        text = '爆头';
        sub = '爆头 · ' + sub;
        this.timers.push({
          t: this.time + 0.15, fn: () => {
            this.announce('HEADSHOT');
          }
        });
      } else if (wid === 'knife') {
        text = '刀杀';
        sub = '刀杀 · ' + sub;
      } else if (wid === 'he') {
        text = '手雷击杀';
        sub = '手雷击杀 · ' + sub;
      } else if (wall) {
        text = '穿墙击杀';
        sub = '穿墙击杀 · ' + sub;
      }
      this.hud.badgeText = text;
      this.hud.badgeSub = sub;
      this.hud.badgeT = 2.2;
      audioSys.playKillConfirm(hs);
    }
    if (v === p && p !== null) {
      p.startDeathCam(att);
      audioSys.setLowHealth(false);
      const wdef = WEAPONS.get(wid);
      const wn = wdef !== undefined ? wdef.name : wid;
      this.killedBy = att !== null && att !== v
        ? `被 ${att.name} 用 ${wn}${hs ? ' 爆头' : ''}击杀` : '你阵亡了';
    }
    this.fx.bloodSplat(v.pos);
    if (this.scoreBL >= this.goal || this.scoreGR >= this.goal) {
      this.timers.push({
        t: this.time + 1.2, fn: () => {
          if (this.playing) {
            this.endMatch();
          }
        }
      });
    }
  }

  announce(text: string): void {
    this.hud.announceText = text;
    this.hud.announceT = 2.2;
    audioSys.announce(text);
  }

  toast(text: string, dur: number): void {
    this.hud.toastText = text;
    this.hud.toastT = dur;
  }

  // ================= 主循环 =================
  startLoop(): void {
    this.running = true;
    this.lastTick = Date.now();
  }

  tick(): void {
    const now = Date.now();
    let dt = (now - this.lastTick) / 1000;
    this.lastTick = now;
    if (dt > 0.1) {
      dt = 0.1;
    }
    if (dt <= 0) {
      return;
    }
    this.realTime += dt;
    this.fpsAcc += dt;
    this.fpsN++;
    if (this.fpsAcc > 1) {
      this.hud.fps = Math.round(this.fpsN / this.fpsAcc);
      this.fpsAcc = 0;
      this.fpsN = 0;
    }
    const active = this.playing && !this.paused;
    if (active) {
      this.simulate(dt);
    } else if (!this.playing) {
      // 菜单：环绕运输船
      const t = this.realTime * 0.045;
      this.camPos.set(Math.cos(t) * 46 - 6, 13 + Math.sin(t * 2.1) * 3, Math.sin(t) * 34);
      this.camLookAt.set(-4, 1.5, 0);
      this.camIsLookAt = true;
      this.camFov = 60;
    } else {
      // 暂停时保持相机
    }
    this.updateCamera(active ? dt : 0);
    this.fx.update(dt, this.realTime, this.shipSpeed);
    this.updateHudTimers(dt);
    if (this.player !== null && this.player.consumeLoadout()) {
      this.toggleLoadout();
    }
    this.buildFrame(dt);
    nrender.renderFrame(this.frameBuf);
    // 音频监听者
    const fwd = _v1.set(-Math.sin(this.camYaw), 0, -Math.cos(this.camYaw));
    audioSys.setListener(this.camPos, fwd);
  }

  private simulate(dt: number): void {
    this.time += dt;
    this.timeLeft -= dt;
    for (let i = this.timers.length - 1; i >= 0; i--) {
      if (this.time >= this.timers[i].t) {
        const f = this.timers[i].fn;
        this.timers.splice(i, 1);
        f();
      }
    }
    const p = this.player;
    if (p !== null) {
      p.update(dt);
    }
    for (const a of this.actors) {
      if (a.isPlayer) {
        continue;
      }
      (a as Bot).update(dt);
    }
    for (const a of this.actors) {
      a.radarT = Math.max(0, a.radarT - dt);
      if (a.alive) {
        a.protectT = Math.max(0, a.protectT - dt);
        a.soldier.update(dt, a.animState(), a.pos, a.yaw);
      } else {
        a.deadT += dt;
        a.soldier.update(dt, null, a.pos, a.yaw);
        a.respawnT -= dt;
        if (a.respawnT <= 0 && !this.ended) {
          this.spawnActor(a, false);
        }
      }
    }
    this.updateNades(dt);
    if (this.timeLeft <= 0 && !this.ended) {
      this.endMatch();
    }
  }

  private updateCamera(dt: number): void {
    const p = this.player;
    if (p === null || !this.playing) {
      return;
    }
    if (!p.alive) {
      const dc = p.deathCam;
      if (dc !== null) {
        dc.t += dt;
        const k = Math.min(1, dc.t * 1.2);
        const e = 1 - (1 - k) * (1 - k);
        this.camPos.lerpVectors(dc.from, dc.to, e);
        if (dc.killer !== null && dc.killer.alive) {
          dc.killer.soldier.headWorld(_v1);
          dc.look.lerp(_v1, Math.min(1, dt * 3));
        }
        this.camLookAt.copy(dc.look);
        this.camIsLookAt = true;
      }
      this.camFov += (this.opts.fov - this.camFov) * Math.min(1, dt * 8);
      return;
    }
    // 视角晃动
    const sp = p.onGround ? p.speed : 0;
    const bobK = Math.min(1, sp / 6) * (p.scoped ? 0.2 : 1);
    const by = Math.abs(Math.sin(p.bobT)) * 0.028 * bobK;
    const bx = Math.cos(p.bobT) * 0.012 * bobK;
    const shake = this.fx.shake * 0.06;
    this.camYaw = p.yaw + p.punchY * 0.75;
    this.camPitch = p.pitch + p.punchP * 0.75 + p.aimPunch;
    p.eye(this.camPos);
    this.camPos.y += by - p.land + (Math.random() - 0.5) * shake;
    const sy = Math.sin(p.yaw), cy = Math.cos(p.yaw);
    this.camPos.x += cy * bx + (Math.random() - 0.5) * shake;
    this.camPos.z += -sy * bx;
    this.camRoll = 0;
    this.camIsLookAt = false;
    // FOV：狙击镜
    const w = p.weapon();
    let fov = this.opts.fov;
    if (w !== undefined && w.def.type === 'sniper' && p.scoped) {
      fov = w.def.zoom[p.scoped - 1];
    }
    const fk = p.scoped ? 1 : Math.min(1, dt * 10);
    this.camFov += (fov - this.camFov) * fk;
  }

  private updateHudTimers(dt: number): void {
    const h = this.hud;
    if (h.hitT > 0) {
      h.hitT -= dt;
    }
    for (let i = h.dmgDirs.length - 1; i >= 0; i--) {
      h.dmgDirs[i].t -= dt;
      if (h.dmgDirs[i].t <= 0) {
        h.dmgDirs.splice(i, 1);
      }
    }
    if (h.toastT > 0) {
      h.toastT -= dt;
    }
    if (h.badgeT > 0) {
      h.badgeT -= dt;
    }
    if (h.announceT > 0) {
      h.announceT -= dt;
    }
    if (h.slotsT > 0) {
      h.slotsT -= dt;
    }
    // 击杀信息 7 秒后过期
    for (let i = h.killFeed.length - 1; i >= 0; i--) {
      if (this.realTime - h.killFeed[i].t > 7) {
        h.killFeed.splice(i, 1);
      }
    }
    h.dmgFlash = Math.max(0, h.dmgFlash - dt * 1.6);
  }

  // ================= 帧构建 =================
  private buildFrame(dt: number): void {
    const f = this.frameBuf;
    const p = this.player;
    // 相机矩阵
    perspective(_m1, this.camFov * Math.PI / 180, this.aspect, 0.05, 800);
    if (this.camIsLookAt) {
      lookAt(_m2, this.camPos, this.camLookAt, UP);
    } else {
      viewFromYPR(_m2, this.camPos, this.camYaw, this.camPitch, this.camRoll);
    }
    _m3.copyFrom(_m1);
    _m3.multiply(_m2);
    f.set(_m3.m, F_WORLDVP);
    f[F_CAMPOS] = this.camPos.x;
    f[F_CAMPOS + 1] = this.camPos.y;
    f[F_CAMPOS + 2] = this.camPos.z;
    f[F_FLAGS] = 1;
    f[F_TIME] = this.realTime;
    f[F_OCEAN] = 1;
    // 武器层
    let vmOn = false;
    if (p !== null && this.playing && p.alive && !this.vm.isGone() &&
      !(p.scoped > 0 && p.weapon() !== undefined && p.weapon().def.type === 'sniper')) {
      vmOn = true;
    }
    f[F_VMACTIVE] = vmOn ? 1 : 0;
    if (vmOn && p !== null) {
      perspective(_m1, 58 * Math.PI / 180, this.aspect, 0.01, 50);
      f.set(_m1.m, F_VMVP);
      f[F_VMMESH] = gunMeshId(p.weapon().id);
      f.set(this.vm.model.m, F_VMMODEL);
    } else {
      f[F_VMMESH] = 0;
    }
    // 士兵
    let ns = 0;
    for (const a of this.actors) {
      if (ns >= 16) {
        break;
      }
      if (a.isPlayer && a.alive) {
        continue; // 第一人称不画自己
      }
      if (!a.alive && a.deadT > 5.8) {
        continue; // 尸体淡出
      }
      const base = F_SOLDIERS + ns * S_STRIDE;
      for (let b = 0; b < 19; b++) {
        f.set(a.soldier.skin[b].m, base + b * 16);
      }
      const flicker = !a.isPlayer && a.protectT > 0 && Math.sin(this.realTime * 30) > 0.3;
      f[base + 304] = (!a.alive || !flicker) ? (a.team === 'BL' ? 1 : 2) : 0;
      const gunId = a.soldier.gunId.length > 0 && a.alive ? gunMeshId(a.soldier.gunId) : 0;
      f[base + 305] = gunId;
      if (gunId > 0) {
        a.soldier.gunWorld(_m1);
        f.set(_m1.m, base + 306);
      }
      ns++;
    }
    f[F_NSOLDIER] = ns;
    // 手雷（动态网格）
    let nd = 0;
    for (const n of this.nades) {
      if (nd >= 12) {
        break;
      }
      _m1.composeScale(n.pos, n.rotX, n.rotY, 0, 1.3, 1.3, 1.3);
      const base = F_DYN + nd * D_STRIDE;
      f[base] = gunMeshId('he');
      f.set(_m1.m, base + 1);
      nd++;
    }
    // 吊着的集装箱摆动
    if (nd < 12 && this.mapData !== null) {
      this.hangT += dt;
      _m1.copyFrom(this.mapData.hangBase);
      _m2.compose(new Vec3(0, 0, 0), Math.sin(this.hangT * 0.4 + 1) * 0.012, 0, Math.sin(this.hangT * 0.55) * 0.018);
      _m1.multiply(_m2);
      const base = F_DYN + nd * D_STRIDE;
      f[base] = MESH_HANG;
      f.set(_m1.m, base + 1);
      nd++;
    }
    f[F_NDYN] = nd;
    // 四边形
    let nq = 0;
    const pushQuad = (cx: number, cy: number, cz: number, dx: number, dy: number, dz: number, len: number,
      width: number, r: number, g: number, b: number, a: number, u0: number, v0: number, u1: number, v1: number,
      mode: number, flags: number, texId: number): void => {
      if (nq >= 320) {
        return;
      }
      const q = F_QUADS + nq * Q_STRIDE;
      f[q] = cx;
      f[q + 1] = cy;
      f[q + 2] = cz;
      f[q + 3] = dx;
      f[q + 4] = dy;
      f[q + 5] = dz;
      f[q + 6] = len;
      f[q + 7] = width;
      f[q + 8] = r;
      f[q + 9] = g;
      f[q + 10] = b;
      f[q + 11] = a;
      f[q + 12] = u0;
      f[q + 13] = v0;
      f[q + 14] = u1;
      f[q + 15] = v1;
      f[q + 16] = mode;
      f[q + 17] = flags;
      f[q + 18] = texId;
      nq++;
    };
    // 曳光
    const speed = 380;
    for (const tr of this.fx.tracers) {
      const head = Math.min(tr.len, tr.t * speed);
      const tail = Math.max(0, head - 7);
      if (tail >= tr.len) {
        continue;
      }
      const mid = _v1.set(tr.x + tr.dx * (head + tail) / 2, tr.y + tr.dy * (head + tail) / 2,
        tr.z + tr.dz * (head + tail) / 2);
      const dist = mid.distanceTo(this.camPos);
      pushQuad(mid.x, mid.y, mid.z, tr.dx, tr.dy, tr.dz, head - tail, 0.018 + dist * 0.0012,
        1, 0.88, 0.63, Math.min(1, 0.9 - tr.t * 0.4), 0, 0, 1, 1, 4, 1, TEX_TRACER);
    }
    // 第三人称枪口火焰
    for (const fl of this.fx.flashes) {
      pushQuad(fl.x, fl.y, fl.z, 0, 1, 0, 0.45 * fl.big, 0.45 * fl.big, 1, 0.85, 0.63, 1, 0, 0, 1, 1, 0, 1,
        TEX_FLASH);
    }
    // 贴花
    const decalPass = (ring: DecalRing, texId: number): void => {
      for (const d of ring.items) {
        if (d.age > 30) {
          continue;
        }
        pushQuad(d.x, d.y, d.z, d.nx, d.ny, d.nz, d.size, d.size, 1, 1, 1, 1, 0, 0, 1, 1, 1, 0, texId);
      }
    };
    decalPass(this.fx.decalsMetal, TEX_HOLE_M);
    decalPass(this.fx.decalsWood, TEX_HOLE_W);
    decalPass(this.fx.decalsBlood, TEX_BLOOD);
    decalPass(this.fx.decalsScorch, TEX_SCORCH);
    // 队友名牌
    if (p !== null && this.playing) {
      for (const t of this.tags) {
        const a = t.actor;
        if (!a.alive || a.pos.distanceTo(this.camPos) > 45) {
          continue;
        }
        a.soldier.headWorld(_v1);
        _v1.y += 0.42;
        pushQuad(_v1.x, _v1.y, _v1.z, 0, 1, 0, 1.3, 0.244, 1, 1, 1, 0.85, 0, 0, 1, 1, 2, 2, t.texId);
      }
    }
    // 武器层枪口火焰
    if (vmOn && this.vm.flashT > 0) {
      const m = this.vm.muzzleWorld;
      pushQuad(m.x, m.y, m.z, 0, 1, 0, this.vm.flashSize, this.vm.flashSize, 1, 0.88, 0.66, 1, 0, 0, 1, 1, 3, 1,
        TEX_FLASH);
    }
    f[F_NQUAD] = nq;
    // 粒子
    let np = 0;
    const partPass = (ps: Particles, texId: number): void => {
      for (const p2 of ps.pool) {
        if (!p2.use || np >= 1200) {
          continue;
        }
        const t = p2.life / p2.max;
        const o = F_PARTS + np * P_STRIDE;
        f[o] = p2.x;
        f[o + 1] = p2.y;
        f[o + 2] = p2.z;
        f[o + 3] = p2.s0 + (p2.s1 - p2.s0) * t;
        f[o + 4] = p2.r;
        f[o + 5] = p2.g;
        f[o + 6] = p2.b;
        f[o + 7] = p2.a0 + (p2.a1 - p2.a0) * t;
        f[o + 8] = texId;
        np++;
      }
    };
    partPass(this.fx.add, TEX_GLOW);
    partPass(this.fx.smoke, TEX_PUFF);
    f[F_NPART] = np;
    // 视模型更新
    if (vmOn && p !== null) {
      this.vm.update(dt, {
        speed: p.speed, onGround: p.onGround, crouch: p.crouch, lookDX: p.lookDX, lookDY: p.lookDY
      });
    }
    this.updateHud();
  }

  private updateHud(): void {
    const p = this.player;
    const h = this.hud;
    if (p === null || !this.playing) {
      return;
    }
    h.scoreBL = this.scoreBL;
    h.scoreGR = this.scoreGR;
    h.goal = this.goal;
    h.timeLeft = Math.max(0, this.timeLeft);
    h.myTeam = p.team;
    h.hp = Math.max(0, Math.ceil(p.hp));
    h.armor = Math.max(0, Math.ceil(p.armor));
    h.alive = p.alive;
    h.protectT = p.protectT;
    const w = p.weapon();
    if (w !== undefined) {
      h.weaponId = w.id;
      h.weaponName = w.def.name;
      h.weaponHudName = w.def.id.toUpperCase();
      if (w.def.type === 'melee') {
        h.mag = -1;
        h.reserve = 0;
      } else {
        h.mag = w.mag;
        h.reserve = w.reserve;
      }
      h.reloading = w.isReloading();
    }
    h.slots = p.inv.map((x) => x.def.name);
    if (p.slot !== this.lastSlotShown) {
      this.lastSlotShown = p.slot;
      h.slotsT = 2.2;
    }
    h.slotCur = p.slot;
    h.scopeLevel = p.scoped;
    if (w !== undefined && w.def.spread !== null) {
      const sp = Math.min(0.12, w.spreadAcc + w.def.spread.base * 2 +
        (p.speed > 0.6 ? w.def.spread.move * Math.min(1, p.speed / 5.7) : 0) +
        (p.onGround ? 0 : w.def.spread.air * 0.5)) * (p.crouch ? 0.7 : 1);
      h.spreadPx = Math.tan(sp) / Math.tan(this.camFov * Math.PI / 360) * this.viewH / 2;
    } else {
      h.spreadPx = 0;
    }
    // 低血/死亡屏幕效果
    h.lowHp = p.alive && p.hp <= 35 ? (35 - p.hp) / 35 : 0;
    h.deathK = !p.alive ? Math.min(1, p.deadT * 2) : 0;
    h.protectK = p.alive ? Math.min(1, p.protectT) : 0;
    if (!p.alive && p.respawnT > 0) {
      h.centerBig = this.killedBy.length > 0 ? this.killedBy : '你阵亡了';
      h.centerSmall = `${p.respawnT.toFixed(1)} 秒后复活`;
      h.respawnIn = p.respawnT;
    } else {
      h.centerBig = '';
      h.centerSmall = '';
      h.respawnIn = 0;
    }
    // 准星目标名
    if (p.alive && this.frame % 4 === 0) {
      const o = this.camPos;
      const dir = _v1.set(-Math.sin(this.camYaw) * Math.cos(this.camPitch), Math.sin(this.camPitch),
        -Math.cos(this.camYaw) * Math.cos(this.camPitch));
      const wh = this.world.raycast(o.x, o.y, o.z, dir.x, dir.y, dir.z, 80, 'sight', this.rayScratch);
      const lim = wh !== null ? wh.t : 80;
      let best: Actor | null = null;
      let bt = lim;
      for (const a of this.actors) {
        if (a === p || !a.alive) {
          continue;
        }
        const r = a.soldier.hitTest(o.x, o.y, o.z, dir.x, dir.y, dir.z, bt, this.frame);
        if (r !== null) {
          best = a;
          bt = r.t;
        }
      }
      this.aimTarget = best;
    }
    if (this.aimTarget !== null && this.aimTarget.alive) {
      h.aimName = this.aimTarget.name;
      h.aimTeam = this.aimTarget.team;
    } else {
      h.aimName = '';
      h.aimTeam = '';
    }
  }

  scoreboard(): void {
    this.hud.boardOpen = !this.hud.boardOpen;
  }

  /** 计分板行（UI 拉取） */
  boardRows(): BoardRow[] {
    const rows: BoardRow[] = [];
    for (const a of this.actors) {
      rows.push(new BoardRow(a.name, a.team, a.stats.k, a.stats.d, a.stats.hs, a.ping, a.isPlayer, !a.alive));
    }
    rows.sort((x, y) => y.k - x.k || x.d - y.d);
    return rows;
  }
}

export class BoardRow {
  name: string = '';
  team: string = '';
  k: number = 0;
  d: number = 0;
  hs: number = 0;
  ping: number = 0;
  me: boolean = false;
  dead: boolean = false;

  constructor(name: string, team: string, k: number, d: number, hs: number, ping: number, me: boolean,
    dead: boolean) {
    this.name = name;
    this.team = team;
    this.k = k;
    this.d = d;
    this.hs = hs;
    this.ping = ping;
    this.me = me;
    this.dead = dead;
  }
}

function sleep(ms: number): Promise<void> {
  return new Promise<void>((resolve) => {
    setTimeout(resolve, ms);
  });
}
