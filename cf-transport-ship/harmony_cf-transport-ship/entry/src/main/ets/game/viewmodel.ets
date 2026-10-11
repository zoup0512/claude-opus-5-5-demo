/**
 * 第一人称武器视模型：枪体姿态弹簧动画（移植自原版 viewmodel.js，简化：整体枪体运动 + 拔枪/换弹/近战/投掷动作）。
 * 输出 vm 相机空间的模型矩阵与枪口火焰参数，由 Game 装入帧缓冲。
 */
import { Mat4, Vec3, clamp } from './math3d';
import { buildGun } from './guns';

const HIP: Map<string, number[]> = new Map<string, number[]>([
  ['ak47', [0.165, -0.175, -0.55, 0.045, 0.165, 0.02]],
  ['m4a1', [0.16, -0.18, -0.54, 0.045, 0.165, 0.02]],
  ['awm', [0.17, -0.185, -0.6, 0.04, 0.15, 0.02]],
  ['mp5', [0.155, -0.165, -0.5, 0.05, 0.17, 0.02]],
  ['deagle', [0.085, -0.115, -0.4, 0.05, 0.1, 0]],
  ['knife', [0.17, -0.15, -0.34, 0.35, -0.25, 0.55]],
  ['he', [0.13, -0.12, -0.3, 0.1, -0.2, 0.2]]
]);
const KICK: Map<string, number[]> = new Map<string, number[]>([
  ['ak47', [0.04, 0.07]], ['m4a1', [0.032, 0.05]], ['awm', [0.09, 0.2]], ['mp5', [0.024, 0.035]],
  ['deagle', [0.05, 0.22]], ['knife', [0.01, 0.02]], ['he', [0.01, 0.02]]
]);

function ease(t: number): number {
  return t * t * (3 - 2 * t);
}

function seg(f: number, a: number, b: number): number {
  return Math.min(1, Math.max(0, (f - a) / (b - a)));
}

export interface VMStateInput {
  speed: number;
  onGround: boolean;
  crouch: boolean;
  lookDX: number;
  lookDY: number;
}

export class ViewModel {
  id: string = '';
  model: Mat4 = new Mat4();
  muzzleWorld: Vec3 = new Vec3();   // vm 相机空间枪口位置
  flashT: number = 0;
  flashSize: number = 0.2;
  visible: boolean = true;
  // 动画状态
  private t: number = 0;
  private kick: number = 0;
  private kickV: number = 0;
  private kickRot: number = 0;
  private kickRotV: number = 0;
  private swayX: number = 0;
  private swayY: number = 0;
  private bobT: number = 0;
  private bobK: number = 0;
  private land: number = 0;
  private drawT: number = 1;
  private drawDur: number = 0.5;
  private animType: string = '';
  private animT: number = 0;
  private animDur: number = 0;
  private animEmpty: boolean = false;
  private animDir: number = 1;
  private gone: boolean = false;   // 手雷投掷后隐藏

  equip(id: string, drawTime: number): void {
    this.id = id;
    this.drawT = 0;
    this.drawDur = drawTime || 0.5;
    this.animType = '';
    this.kick = this.kickV = this.kickRot = this.kickRotV = 0;
    this.gone = false;
  }

  fire(): void {
    const k = KICK.get(this.id) !== undefined ? KICK.get(this.id) as number[] : [0.03, 0.05];
    this.kickV += k[0] * 38;
    this.kickRotV += k[1] * 38;
    this.flashT = 0.05;
    const sc = this.id === 'awm' ? 1.6 : this.id === 'deagle' ? 1.2 : this.id === 'mp5' ? 0.8 : 1;
    this.flashSize = 0.16 * sc * (0.8 + Math.random() * 0.45);
    if (this.id === 'awm') {
      this.animType = 'bolt';
      this.animT = 0;
      this.animDur = 1.3;
    }
  }

  reload(dur: number, empty: boolean): void {
    this.animType = 'reload';
    this.animT = 0;
    this.animDur = dur;
    this.animEmpty = empty;
  }

  melee(heavy: boolean): void {
    this.animType = heavy ? 'stab' : 'slash';
    this.animT = 0;
    this.animDur = heavy ? 0.85 : 0.38;
    this.animDir = Math.random() > 0.5 ? 1 : -1;
  }

  throwNade(): void {
    this.animType = 'throw';
    this.animT = 0;
    this.animDur = 0.75;
  }

  setVisible(v: boolean): void {
    this.visible = v;
  }

  update(dt: number, st: VMStateInput): void {
    this.t += dt;
    if (this.id.length === 0) {
      return;
    }
    const hip = HIP.get(this.id) !== undefined ? HIP.get(this.id) as number[] : HIP.get('ak47') as number[];
    // 后坐弹簧
    const k1 = 260, d1 = 26;
    this.kickV += (-k1 * this.kick - d1 * this.kickV) * dt;
    this.kick += this.kickV * dt;
    this.kickRotV += (-k1 * this.kickRot - d1 * this.kickRotV) * dt;
    this.kickRot += this.kickRotV * dt;
    // 视角惯性摆动
    const tx = clamp(-st.lookDX * 0.00055, -0.05, 0.05);
    const ty = clamp(-st.lookDY * 0.00055, -0.04, 0.04);
    this.swayX += (tx - this.swayX) * Math.min(1, dt * 9);
    this.swayY += (ty - this.swayY) * Math.min(1, dt * 9);
    // 行走晃动
    const moving = st.onGround && st.speed > 0.5;
    this.bobK += ((moving ? Math.min(1, st.speed / 6) : 0) - this.bobK) * Math.min(1, dt * 6);
    this.bobT += dt * (5 + st.speed * 1.2) * (moving ? 1 : 0.3);
    const bx = Math.sin(this.bobT) * 0.011 * this.bobK;
    const by = -Math.abs(Math.cos(this.bobT)) * 0.009 * this.bobK;
    const breathe = Math.sin(this.t * 1.6) * 0.0018;
    this.land *= Math.exp(-dt * 8);
    // 拔枪
    this.drawT = Math.min(1, this.drawT + dt / this.drawDur);
    const dr = 1 - ease(this.drawT);
    let px = hip[0] + bx + this.swayX;
    let py = hip[1] + by + breathe + this.swayY - dr * 0.22 - this.land * 0.03 - (st.crouch ? 0.006 : 0);
    let pz = hip[2] + this.kick;
    let rx = hip[3] + this.kickRot - dr * 0.9 + this.swayY * 1.5;
    let ry = hip[4] + this.swayX * 2;
    let rz = hip[5] + (st.crouch ? -0.03 : 0) + bx * 2;
    // 动作动画
    if (this.animType.length > 0) {
      this.animT += dt;
      const f = Math.min(1, this.animT / this.animDur);
      const a = this.animType;
      if (a === 'reload') {
        const tilt = ease(seg(f, 0, 0.15)) * (1 - ease(seg(f, 0.85, 1)));
        rz += tilt * 0.45;
        rx += tilt * 0.18;
        py -= tilt * 0.03;
        px -= tilt * 0.02;
        if (this.animEmpty) {
          const bf = seg(f, 0.74, 0.92);
          rz -= Math.sin(bf * Math.PI) * 0.1;
        }
      } else if (a === 'bolt') {
        const f2 = seg(f, 0.15, 0.85);
        rz += Math.sin(f2 * Math.PI) * 0.18;
        rx += Math.sin(f2 * Math.PI) * 0.06;
        py -= Math.sin(f2 * Math.PI) * 0.015;
      } else if (a === 'slash') {
        const s = Math.sin(f * Math.PI);
        const dir = this.animDir;
        ry += dir * (f - 0.5) * -2.2;
        rz += dir * s * -0.6;
        px += dir * (0.5 - f) * 0.12;
        pz -= s * 0.08;
        rx += s * 0.3;
      } else if (a === 'stab') {
        const wind = ease(seg(f, 0, 0.35));
        const thrust = ease(seg(f, 0.35, 0.55));
        const ret = ease(seg(f, 0.65, 1));
        pz += wind * 0.08 - thrust * 0.22 + ret * 0.14;
        rx += wind * -0.4 + thrust * 0.9 - ret * 0.5;
        py += wind * 0.05 - thrust * 0.04;
      } else if (a === 'throw') {
        const wind = ease(seg(f, 0.3, 0.55));
        const thr = ease(seg(f, 0.55, 0.8));
        py += wind * 0.08 - thr * 0.12;
        pz += wind * 0.1 - thr * 0.3;
        rx += wind * 0.8 - thr * 1.6;
        if (f > 0.72) {
          this.gone = true;
        }
      }
      if (f >= 1) {
        this.animType = '';
        if (a === 'throw') {
          this.gone = true;
        }
      }
    }
    this.model.compose(new Vec3(px, py, pz), rx, ry, rz);
    // 枪口位置
    if (this.flashT > 0) {
      this.flashT -= dt;
    }
    const gun = buildGun(this.id);
    this.muzzleWorld.copy(gun.muzzle);
    this.model.transformPoint(this.muzzleWorld, this.muzzleWorld);
  }

  isGone(): boolean {
    return this.gone;
  }
}
