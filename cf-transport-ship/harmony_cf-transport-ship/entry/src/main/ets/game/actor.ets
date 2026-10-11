/**
 * 角色基类：移动物理 + 武器状态机（玩家与机器人共用）。移植自原版 actor.js。
 */
import { Vec3, clamp } from './math3d';
import { World, NavGrid, Collider, RayHit, MoveEntity } from './physics';
import { WeaponState, currentSpread, recoilKick } from './weapons';
import { Soldier, SoldierAnimState } from './character';

export const STAND_H = 1.8;
export const CROUCH_H = 1.15;
export const EYE_STAND = 1.62;
export const EYE_CROUCH = 1.05;
const GRAV = 19;
const JUMP_V = 6.6;
const RUN = 5.7;

/** 游戏选项（Game 实现并提供给角色层） */
export interface GameOptsRef {
  team: string;
  primary: string;
  diff: string;
  size: number;
  goal: number;
  tod: string;
  sens: number;
  fov: number;
  vol: number;
}

/** 角色层对 Game 的依赖接口（game.ets 实现，避免循环导入） */
export interface GameHooks {
  time: number;
  world: World;
  nav: NavGrid;
  actors: Actor[];
  opts: GameOptsRef;
  rayScratch: RayHit;
  onJump(a: Actor): void;
  onLand(a: Actor, sp: number): void;
  onFootstep(a: Actor): void;
  onSwitch(a: Actor): void;
  onReloadStart(a: Actor, empty: boolean): void;
  onScope(a: Actor): void;
  onDryFire(a: Actor): void;
  onGrenadeStart(a: Actor): void;
  fireWeapon(a: Actor, w: WeaponState, spread: number): void;
  melee(a: Actor, heavy: boolean): void;
  throwGrenade(a: Actor): void;
  toast(text: string, dur: number): void;
}

export class ActorStats {
  k: number = 0;
  d: number = 0;
  hs: number = 0;
  shots: number = 0;
  hits: number = 0;
}

export class WeaponInput {
  fire: boolean = false;
  firePressed: boolean = false;
  alt: boolean = false;
  altPressed: boolean = false;
  reload: boolean = false;
  sw: number = -1;
}

export class Actor implements MoveEntity {
  game: GameHooks;
  id: number;
  name: string;
  team: string;
  isPlayer: boolean = false;
  pos: Vec3 = new Vec3();
  vel: Vec3 = new Vec3();
  radius: number = 0.36;
  height: number = STAND_H;
  stepHeight: number = 0.42;
  onGround: boolean = false;
  ground: Collider | null = null;
  crouch: boolean = false;
  eyeH: number = EYE_STAND;
  yaw: number = 0;
  pitch: number = 0;
  punchP: number = 0;
  punchY: number = 0;
  aimPunch: number = 0;
  hp: number = 100;
  armor: number = 100;
  alive: boolean = false;
  deadT: number = 0;
  respawnT: number = 0;
  protectT: number = 0;
  inv: WeaponState[] = [];
  slot: number = 0;
  lastSlot: number = 1;
  readyAt: number = 0;
  stats: ActorStats = new ActorStats();
  streak: number = 0;
  lastKillT: number = -99;
  multi: number = 0;
  radarT: number = 0;
  ping: number = 20 + ((Math.random() * 40) | 0);
  primary: string = 'ak47';
  nextPrimary: string = '';
  soldier: Soldier;
  stepDist: number = 0;
  scoped: number = 0;
  scopeReady: boolean = false;
  scopeT: number = 0;
  reScope: number = 0;
  lastHurt: number = -99;
  lastAttacker: Actor | null = null;
  walk: boolean = false;
  pendingThrow: number = 0;
  autoSwitchAt: number = 0;
  jumpCD: number = 0;
  speed: number = 0;
  landed: boolean = false;
  landSpeed: number = 0;
  stepped: number = 0;
  recoilControl: number = 1;

  constructor(game: GameHooks, id: number, name: string, team: string, isPlayer: boolean) {
    this.game = game;
    this.id = id;
    this.name = name;
    this.team = team;
    this.isPlayer = isPlayer;
    this.soldier = new Soldier(team);
  }

  weapon(): WeaponState {
    return this.inv[this.slot];
  }

  eye(out: Vec3): Vec3 {
    return out.set(this.pos.x, this.pos.y + this.eyeH, this.pos.z);
  }

  forward(out: Vec3): Vec3 {
    const p = this.pitch + this.punchP;
    const y = this.yaw + this.punchY;
    return out.set(-Math.sin(y) * Math.cos(p), Math.sin(p), -Math.cos(y) * Math.cos(p));
  }

  giveLoadout(primary: string): void {
    this.primary = primary || this.primary;
    this.inv = [new WeaponState(this.primary), new WeaponState('deagle'), new WeaponState('knife'),
      new WeaponState('he')];
    for (const w of this.inv) {
      w.patternSeed = Math.random() * 6;
    }
    this.slot = 0;
    this.lastSlot = 1;
    this.readyAt = this.game.time + 0.3;
    this.soldier.setWeapon(this.primary);
  }

  spawn(x: number, z: number, yaw: number): void {
    this.pos.set(x, 0.02, z);
    this.vel.set(0, 0, 0);
    this.yaw = yaw;
    this.pitch = 0;
    this.punchP = 0;
    this.punchY = 0;
    this.hp = 100;
    this.armor = 100;
    this.alive = true;
    this.deadT = 0;
    this.crouch = false;
    this.height = STAND_H;
    this.eyeH = EYE_STAND;
    this.protectT = 3;
    this.onGround = true;
    const pri = this.nextPrimary.length > 0 ? this.nextPrimary : this.primary;
    this.giveLoadout(pri);
    this.soldier.reset();
    this.scoped = 0;
    this.scopeReady = false;
    this.streak = 0;
  }

  /** wish：世界坐标系期望移动方向（长度 0..1） */
  move(dt: number, wishX: number, wishZ: number, jump: boolean, crouch: boolean, walk: boolean): void {
    const g = this.game;
    const w = this.weapon();
    const spMul = w !== undefined ? w.def.speed : 1;
    // 下蹲 / 起身
    if (crouch && !this.crouch) {
      this.crouch = true;
      this.height = CROUCH_H;
      if (!this.onGround) {
        this.pos.y += STAND_H - CROUCH_H - 0.1;
      }
    } else if (!crouch && this.crouch) {
      if (this.onGround) {
        if (!g.world.blocked(this.pos.x, this.pos.y + 0.05, this.pos.z, this.radius * 0.95, STAND_H - 0.05)) {
          this.crouch = false;
          this.height = STAND_H;
        }
      } else {
        const drop = STAND_H - CROUCH_H - 0.1;
        if (!g.world.blocked(this.pos.x, this.pos.y - drop, this.pos.z, this.radius * 0.95, STAND_H)) {
          this.crouch = false;
          this.height = STAND_H;
          this.pos.y -= drop;
        }
      }
    }
    this.eyeH += ((this.crouch ? EYE_CROUCH : EYE_STAND) - this.eyeH) * Math.min(1, dt * 14);
    const maxSpd = RUN * spMul * (this.crouch ? 0.42 : walk ? 0.5 : 1) * (this.scoped ? 0.55 : 1);
    const wl = Math.hypot(wishX, wishZ);
    const wx = wl > 0 ? wishX / wl : 0;
    const wz = wl > 0 ? wishZ / wl : 0;
    const wishSpeed = maxSpd * Math.min(1, wl);
    const v = this.vel;
    if (this.onGround) {
      const sp = Math.hypot(v.x, v.z);
      if (sp > 0) {
        const drop = Math.max(sp, 1.5) * 9 * dt;
        const ns = Math.max(0, sp - drop) / sp;
        v.x *= ns;
        v.z *= ns;
      }
      const cur = v.x * wx + v.z * wz;
      const add = wishSpeed - cur;
      if (add > 0) {
        const acc = Math.min(11 * dt * wishSpeed, add);
        v.x += acc * wx;
        v.z += acc * wz;
      }
      if (jump && this.jumpCD <= 0) {
        v.y = JUMP_V;
        this.onGround = false;
        this.jumpCD = 0.35;
        g.onJump(this);
      }
    } else {
      const ws = Math.min(wishSpeed, 1.2);
      const cur = v.x * wx + v.z * wz;
      const add = ws - cur;
      if (add > 0) {
        const acc = Math.min(12 * dt * ws, add);
        v.x += acc * wx;
        v.z += acc * wz;
      }
    }
    this.jumpCD -= dt;
    v.y -= GRAV * dt;
    g.world.move(this, dt);
    // 角色之间的实体碰撞（只推开自己）
    for (const o of g.actors) {
      if (o === this || !o.alive) {
        continue;
      }
      const dx = this.pos.x - o.pos.x, dz = this.pos.z - o.pos.z;
      const d2 = dx * dx + dz * dz;
      const R = this.radius + o.radius - 0.05;
      if (d2 < R * R && d2 > 1e-6 && Math.abs(this.pos.y - o.pos.y) < 1.6) {
        const d = Math.sqrt(d2);
        const push = (R - d) * 0.5;
        const nx = dx / d, nz = dz / d;
        if (!g.world.blocked(this.pos.x + nx * push, this.pos.y + 0.05, this.pos.z + nz * push, this.radius * 0.9,
          this.height - 0.1)) {
          this.pos.x += nx * push;
          this.pos.z += nz * push;
        }
      }
    }
    if (this.landed && this.landSpeed > 3) {
      g.onLand(this, this.landSpeed);
    }
    // 脚步
    const hs = Math.hypot(v.x, v.z);
    this.speed = hs;
    if (this.onGround && hs > 2.6 && !walk && !this.crouch) {
      this.stepDist += hs * dt;
      if (this.stepDist > 2.3) {
        this.stepDist = 0;
        g.onFootstep(this);
      }
    }
    // 防卡死
    if (this.pos.y < -3) {
      this.pos.y = 0.1;
      this.vel.set(0, 0, 0);
    }
  }

  /** 武器逻辑 */
  weaponUpdate(dt: number, inp: WeaponInput): void {
    const g = this.game;
    const now = g.time;
    // 切枪
    if (inp.sw >= 0 && inp.sw !== this.slot && this.inv[inp.sw] !== undefined) {
      const tgt = this.inv[inp.sw];
      if (!(tgt.def.type === 'grenade' && tgt.mag <= 0)) {
        this.weapon().reloadUntil = 0;
        this.lastSlot = this.slot;
        this.slot = inp.sw;
        this.readyAt = now + tgt.def.draw;
        this.scoped = 0;
        this.scopeReady = false;
        this.soldier.setWeapon(tgt.id);
        g.onSwitch(this);
      }
    }
    const w = this.weapon();
    const d = w.def;
    // 散布恢复
    if (d.spread !== null) {
      if (now - w.lastShot > 60 / d.rpm * 1.2) {
        w.spreadAcc *= Math.exp(-d.spread.recover * dt);
      }
      if (now - w.lastShot > 0.28) {
        w.shotsFired = 0;
      }
    }
    // 后坐恢复
    if (d.recoil !== null && now - w.lastShot > 60 / d.rpm + 0.05) {
      const k = Math.exp(-d.recoil.recover * dt);
      this.punchP *= k;
      this.punchY *= k;
    }
    this.aimPunch *= Math.exp(-dt * 10);
    // 换弹完成
    if (w.isReloading() && now >= w.reloadUntil) {
      w.finishReload();
    }
    // 狙击镜
    if (d.type === 'sniper') {
      if (inp.altPressed && now >= this.readyAt && !w.isReloading() && now >= w.boltUntil) {
        this.scoped = (this.scoped + 1) % 3;
        this.scopeT = now;
        this.scopeReady = false;
        g.onScope(this);
      }
      if (this.scoped && now - this.scopeT > 0.18) {
        this.scopeReady = true;
      }
      if (this.reScope && now >= w.boltUntil && !w.isReloading()) {
        this.scoped = this.reScope;
        this.reScope = 0;
        this.scopeT = now;
        this.scopeReady = false;
        g.onScope(this);
      }
    }
    if (now < this.readyAt) {
      return;
    }
    // 换弹
    if (inp.reload && w.canReload()) {
      this.startReload();
    }
    if (w.isReloading()) {
      return;
    }
    if (d.type === 'melee') {
      if (now >= w.nextFire) {
        if (inp.fire) {
          w.nextFire = now + d.rateLight;
          g.melee(this, false);
        } else if (inp.alt) {
          w.nextFire = now + d.rateHeavy;
          g.melee(this, true);
        }
      }
      return;
    }
    if (d.type === 'grenade') {
      if (this.pendingThrow > 0) {
        this.pendingThrow -= dt;
        if (this.pendingThrow <= 0) {
          g.throwGrenade(this);
          w.mag = 0;
          this.readyAt = now + 0.4;
          this.autoSwitchAt = now + 0.45;
        }
        return;
      }
      if (this.autoSwitchAt && now >= this.autoSwitchAt) {
        this.autoSwitchAt = 0;
        const back = this.inv[this.lastSlot] !== undefined && this.lastSlot !== 3 ? this.lastSlot : 0;
        const wi = new WeaponInput();
        wi.sw = back;
        this.weaponUpdate(0, wi);
        return;
      }
      if (inp.firePressed && w.mag > 0) {
        this.pendingThrow = 0.52;
        g.onGrenadeStart(this);
      }
      return;
    }
    // 枪械
    const trigger = d.auto ? inp.fire : inp.firePressed;
    if (!trigger || now < w.nextFire || now < w.boltUntil) {
      return;
    }
    if (w.mag <= 0) {
      if (inp.firePressed) {
        g.onDryFire(this);
      }
      if (w.canReload()) {
        this.startReload();
      }
      return;
    }
    w.mag--;
    w.lastShot = now;
    w.nextFire = now + 60 / d.rpm;
    this.stats.shots++;
    const spread = currentSpread(w, {
      speed: this.speed, onGround: this.onGround, crouch: this.crouch, scoped: this.scoped > 0,
      scopeReady: this.scopeReady
    });
    g.fireWeapon(this, w, spread);
    // 后坐
    const kicks = recoilKick(w, Math.random);
    const up = kicks[0];
    const side = kicks[1];
    const ctl = this.recoilControl;
    this.punchP = Math.min(d.recoil !== null ? d.recoil.upMax : 0.1, this.punchP + up * ctl);
    this.punchY += side * ctl;
    w.shotsFired++;
    if (d.spread !== null) {
      w.spreadAcc = Math.min(d.spread.max, w.spreadAcc + d.spread.perShot);
    }
    this.protectT = 0;
    if (d.type === 'sniper') {
      w.boltUntil = now + d.bolt;
      if (this.scoped) {
        this.reScope = this.scoped;
        this.scoped = 0;
        this.scopeReady = false;
      }
    }
    if (w.mag === 0 && w.canReload() && !this.isPlayer) {
      this.startReload();
    }
  }

  startReload(): void {
    const w = this.weapon();
    if (!w.canReload()) {
      return;
    }
    w.reloadUntil = this.game.time + w.def.reload;
    this.scoped = 0;
    this.scopeReady = false;
    this.reScope = 0;
    this.game.onReloadStart(this, w.mag === 0);
  }

  /** 士兵动画（由 Game 每帧调用，统一驱动） */
  animState(): SoldierAnimState {
    const fwd = (this.vel.x * -Math.sin(this.yaw) + this.vel.z * -Math.cos(this.yaw)) / Math.max(0.01, this.speed);
    return {
      speed: this.speed, fwd, crouch: this.crouch, pitch: this.pitch + this.punchP, onGround: this.onGround,
      reloading: this.weapon() !== undefined ? this.weapon().isReloading() : false
    };
  }
}

export function clampPitch(v: number): number {
  return clamp(v, -1.5, 1.5);
}
