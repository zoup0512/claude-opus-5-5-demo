/**
 * 玩家：触屏输入 + 状态（相机由 Game 层根据玩家状态计算）。移植自原版 player.js。
 */
import { Vec3 } from './math3d';
import { Actor, GameHooks, WeaponInput } from './actor';

/** 触屏输入状态（UI 层写入） */
export class TouchInputState {
  mx: number = 0;          // 移动摇杆 X（-1..1，右为正）
  mz: number = 0;          // 移动摇杆 Y（-1..1，前为正）
  fire: boolean = false;
  firePressed: boolean = false;
  jump: boolean = false;
  crouch: boolean = false;
  lookDX: number = 0;      // 视角滑动累计（像素）
  lookDY: number = 0;
  reloadPressed: boolean = false;
  quickSwitchPressed: boolean = false;
  slotPressed: number = -1;
  loadoutPressed: boolean = false;
  scopeToggle: boolean = false; // 开镜按钮
  scopeHold: boolean = false;   // 按住（重击）
}

export class DeathCam {
  t: number = 0;
  from: Vec3 = new Vec3();
  to: Vec3 = new Vec3();
  look: Vec3 = new Vec3();
  killer: Actor | null = null;
}

function clampP(v: number): number {
  return v < -1.5 ? -1.5 : v > 1.5 ? 1.5 : v;
}

export class Player extends Actor {
  touch: TouchInputState = new TouchInputState();
  lookDX: number = 0;
  lookDY: number = 0;
  bobT: number = 0;
  land: number = 0;
  camRoll: number = 0;
  deathCam: DeathCam | null = null;

  constructor(game: GameHooks, id: number, name: string, team: string) {
    super(game, id, name, team, true);
  }

  /** 返回是否需要打开换枪界面 */
  consumeLoadout(): boolean {
    if (this.touch.loadoutPressed) {
      this.touch.loadoutPressed = false;
      return true;
    }
    return false;
  }

  update(dt: number): void {
    const g = this.game;
    const sens = g.opts.sens * 0.0042;
    const dx = this.touch.lookDX;
    const dy = this.touch.lookDY;
    this.touch.lookDX = 0;
    this.touch.lookDY = 0;
    this.lookDX = dx;
    this.lookDY = dy;
    const fovK = this.scoped ? this.scopedFov() / g.opts.fov : 1;
    if (this.alive) {
      this.yaw -= dx * sens * fovK;
      this.pitch = clampP(this.pitch - dy * sens * fovK);
      // 移动
      const f = this.touch.mz;
      const s = this.touch.mx;
      const sy = Math.sin(this.yaw), cy = Math.cos(this.yaw);
      const wx = -sy * f + cy * s;
      const wz = -cy * f - sy * s;
      const jump = this.touch.jump;
      const crouch = this.touch.crouch;
      this.move(dt, wx, wz, jump, crouch, false);
      this.touch.jump = false;
      // 武器输入
      let sw = -1;
      if (this.touch.slotPressed >= 0) {
        sw = this.touch.slotPressed;
        this.touch.slotPressed = -1;
      }
      if (this.touch.quickSwitchPressed) {
        this.touch.quickSwitchPressed = false;
        sw = this.lastSlot;
      }
      if (sw >= 0 && this.inv[sw] !== undefined && this.inv[sw].def.type === 'grenade' && this.inv[sw].mag <= 0) {
        g.toast('没有手雷了', 1.2);
        sw = -1;
      }
      const wi = new WeaponInput();
      wi.fire = this.touch.fire;
      wi.firePressed = this.touch.firePressed;
      wi.alt = this.touch.scopeHold;
      wi.altPressed = this.touch.scopeToggle;
      wi.reload = this.touch.reloadPressed;
      wi.sw = sw;
      this.touch.firePressed = false;
      this.touch.scopeToggle = false;
      this.touch.reloadPressed = false;
      this.weaponUpdate(dt, wi);
    } else {
      this.touch.firePressed = false;
      this.touch.scopeToggle = false;
      this.touch.reloadPressed = false;
    }
    // 视角晃动状态（供相机计算）
    const sp = this.onGround ? this.speed : 0;
    this.bobT += dt * (sp > 0.5 ? 6 + sp * 0.9 : 0);
    if (this.landed && this.landSpeed > 3) {
      this.land = Math.min(0.14, this.landSpeed * 0.012);
    }
    this.land *= Math.exp(-dt * 7);
  }

  scopedFov(): number {
    const w = this.weapon();
    if (w !== undefined && w.def.type === 'sniper' && this.scoped) {
      return w.def.zoom[this.scoped - 1];
    }
    return 78;
  }

  startDeathCam(killer: Actor | null): void {
    const dc = new DeathCam();
    this.eye(dc.from);
    const head = new Vec3(this.pos.x, this.pos.y + 1.2, this.pos.z);
    const want = new Vec3(Math.sin(this.yaw) * 2.2, 1.4, Math.cos(this.yaw) * 2.2);
    const L = want.length();
    want.scale(1 / L);
    const hit = this.game.world.raycast(head.x, head.y, head.z, want.x, want.y, want.z, L, 'move',
      this.game.rayScratch);
    if (hit !== null) {
      const d = Math.max(0.2, hit.t - 0.35);
      dc.to.set(head.x + want.x * d, head.y + want.y * d, head.z + want.z * d);
    } else {
      dc.to.set(head.x + want.x * L, head.y + want.y * L, head.z + want.z * L);
    }
    dc.look.set(this.pos.x, this.pos.y + 0.4, this.pos.z);
    dc.killer = killer !== null && killer !== this ? killer : null;
    this.deathCam = dc;
  }
}
