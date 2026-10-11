/**
 * 3D 数学库：Vec3 + 4x4 矩阵（列主序，与 OpenGL 一致）
 */

export class Vec3 {
  x: number = 0;
  y: number = 0;
  z: number = 0;

  constructor(x: number = 0, y: number = 0, z: number = 0) {
    this.x = x;
    this.y = y;
    this.z = z;
  }

  set(x: number, y: number, z: number): Vec3 {
    this.x = x;
    this.y = y;
    this.z = z;
    return this;
  }

  copy(v: Vec3): Vec3 {
    this.x = v.x;
    this.y = v.y;
    this.z = v.z;
    return this;
  }

  clone(): Vec3 {
    return new Vec3(this.x, this.y, this.z);
  }

  add(v: Vec3): Vec3 {
    this.x += v.x;
    this.y += v.y;
    this.z += v.z;
    return this;
  }

  sub(v: Vec3): Vec3 {
    this.x -= v.x;
    this.y -= v.y;
    this.z -= v.z;
    return this;
  }

  scale(s: number): Vec3 {
    this.x *= s;
    this.y *= s;
    this.z *= s;
    return this;
  }

  addScaled(v: Vec3, s: number): Vec3 {
    this.x += v.x * s;
    this.y += v.y * s;
    this.z += v.z * s;
    return this;
  }

  length(): number {
    return Math.sqrt(this.x * this.x + this.y * this.y + this.z * this.z);
  }

  lengthSq(): number {
    return this.x * this.x + this.y * this.y + this.z * this.z;
  }

  normalize(): Vec3 {
    const l = this.length();
    if (l > 1e-9) {
      this.x /= l;
      this.y /= l;
      this.z /= l;
    }
    return this;
  }

  dot(v: Vec3): number {
    return this.x * v.x + this.y * v.y + this.z * v.z;
  }

  cross(a: Vec3, b: Vec3): Vec3 {
    const x = a.y * b.z - a.z * b.y;
    const y = a.z * b.x - a.x * b.z;
    const z = a.x * b.y - a.y * b.x;
    this.x = x;
    this.y = y;
    this.z = z;
    return this;
  }

  distanceTo(v: Vec3): number {
    const dx = this.x - v.x;
    const dy = this.y - v.y;
    const dz = this.z - v.z;
    return Math.sqrt(dx * dx + dy * dy + dz * dz);
  }

  lerp(v: Vec3, t: number): Vec3 {
    this.x += (v.x - this.x) * t;
    this.y += (v.y - this.y) * t;
    this.z += (v.z - this.z) * t;
    return this;
  }

  lerpVectors(a: Vec3, b: Vec3, t: number): Vec3 {
    this.x = a.x + (b.x - a.x) * t;
    this.y = a.y + (b.y - a.y) * t;
    this.z = a.z + (b.z - a.z) * t;
    return this;
  }
}

// 全局复用的临时向量（单线程内使用，避免每帧分配）
export const TMP_V1 = new Vec3();
export const TMP_V2 = new Vec3();
export const TMP_V3 = new Vec3();
export const TMP_V4 = new Vec3();

export function clamp(v: number, a: number, b: number): number {
  return v < a ? a : v > b ? b : v;
}

export function lerp(a: number, b: number, t: number): number {
  return a + (b - a) * t;
}

export function wrapPi(a: number): number {
  while (a > Math.PI) {
    a -= Math.PI * 2;
  }
  while (a < -Math.PI) {
    a += Math.PI * 2;
  }
  return a;
}

/**
 * 4x4 矩阵：m[col*4 + row]，列主序
 */
export class Mat4 {
  m: Float32Array;

  constructor() {
    this.m = new Float32Array(16);
    this.m[0] = 1;
    this.m[5] = 1;
    this.m[10] = 1;
    this.m[15] = 1;
  }

  identity(): Mat4 {
    const m = this.m;
    m[0] = 1; m[1] = 0; m[2] = 0; m[3] = 0;
    m[4] = 0; m[5] = 1; m[6] = 0; m[7] = 0;
    m[8] = 0; m[9] = 0; m[10] = 1; m[11] = 0;
    m[12] = 0; m[13] = 0; m[14] = 0; m[15] = 1;
    return this;
  }

  copyFrom(o: Mat4): Mat4 {
    this.m.set(o.m);
    return this;
  }

  /** out = this * o（先应用 o 的变换） */
  multiply(o: Mat4): Mat4 {
    const a = this.m;
    const b = o.m;
    const r = new Float32Array(16);
    for (let c = 0; c < 4; c++) {
      for (let ro = 0; ro < 4; ro++) {
        r[c * 4 + ro] = a[ro] * b[c * 4] + a[4 + ro] * b[c * 4 + 1] + a[8 + ro] * b[c * 4 + 2] + a[12 + ro] * b[c * 4 + 3];
      }
    }
    this.m.set(r);
    return this;
  }

  /** 平移 × 旋转（欧拉 XYZ：R = Rx·Ry·Rz） */
  compose(t: Vec3, rx: number, ry: number, rz: number): Mat4 {
    const cx = Math.cos(rx), sx = Math.sin(rx);
    const cy = Math.cos(ry), sy = Math.sin(ry);
    const cz = Math.cos(rz), sz = Math.sin(rz);
    // R = Rx * Ry * Rz
    const m = this.m;
    m[0] = cy * cz;
    m[1] = sx * sy * cz + cx * sz;
    m[2] = -cx * sy * cz + sx * sz;
    m[3] = 0;
    m[4] = -cy * sz;
    m[5] = -sx * sy * sz + cx * cz;
    m[6] = cx * sy * sz + sx * cz;
    m[7] = 0;
    m[8] = sy;
    m[9] = -sx * cy;
    m[10] = cx * cy;
    m[11] = 0;
    m[12] = t.x;
    m[13] = t.y;
    m[14] = t.z;
    m[15] = 1;
    return this;
  }

  /** 平移 × 旋转 × 缩放（欧拉 XYZ） */
  composeScale(t: Vec3, rx: number, ry: number, rz: number, sx: number, sy: number, sz: number): Mat4 {
    this.compose(t, rx, ry, rz);
    const m = this.m;
    for (let i = 0; i < 3; i++) {
      m[i] *= sx;
      m[4 + i] *= sy;
      m[8 + i] *= sz;
    }
    return this;
  }

  /** 平移 × 基向量正交基（right/up/fwd 为列） */
  basis(t: Vec3, right: Vec3, up: Vec3, fwd: Vec3): Mat4 {
    const m = this.m;
    m[0] = right.x; m[1] = right.y; m[2] = right.z; m[3] = 0;
    m[4] = up.x; m[5] = up.y; m[6] = up.z; m[7] = 0;
    m[8] = fwd.x; m[9] = fwd.y; m[10] = fwd.z; m[11] = 0;
    m[12] = t.x; m[13] = t.y; m[14] = t.z; m[15] = 1;
    return this;
  }

  /** 逆矩阵（gl-matrix 公式），失败则保持单位阵。就地计算，无分配 */
  invert(): Mat4 {
    const a = this.m;
    const a00 = a[0], a01 = a[1], a02 = a[2], a03 = a[3];
    const a10 = a[4], a11 = a[5], a12 = a[6], a13 = a[7];
    const a20 = a[8], a21 = a[9], a22 = a[10], a23 = a[11];
    const a30 = a[12], a31 = a[13], a32 = a[14], a33 = a[15];
    const b00 = a00 * a11 - a01 * a10;
    const b01 = a00 * a12 - a02 * a10;
    const b02 = a00 * a13 - a03 * a10;
    const b03 = a01 * a12 - a02 * a11;
    const b04 = a01 * a13 - a03 * a11;
    const b05 = a02 * a13 - a03 * a12;
    const b06 = a20 * a31 - a21 * a30;
    const b07 = a20 * a32 - a22 * a30;
    const b08 = a20 * a33 - a23 * a30;
    const b09 = a21 * a32 - a22 * a31;
    const b10 = a21 * a33 - a23 * a31;
    const b11 = a22 * a33 - a23 * a32;
    let det = b00 * b11 - b01 * b10 + b02 * b09 + b03 * b08 - b04 * b07 + b05 * b06;
    if (Math.abs(det) < 1e-12) {
      return this.identity();
    }
    det = 1.0 / det;
    const t0 = (a11 * b11 - a12 * b10 + a13 * b09) * det;
    const t1 = (a02 * b10 - a01 * b11 - a03 * b09) * det;
    const t2 = (a31 * b05 - a32 * b04 + a33 * b03) * det;
    const t3 = (a22 * b04 - a21 * b05 - a23 * b03) * det;
    const t4 = (a12 * b08 - a10 * b11 - a13 * b07) * det;
    const t5 = (a00 * b11 - a02 * b08 + a03 * b07) * det;
    const t6 = (a32 * b02 - a30 * b05 - a33 * b01) * det;
    const t7 = (a20 * b05 - a22 * b02 + a23 * b01) * det;
    const t8 = (a10 * b10 - a11 * b08 + a13 * b06) * det;
    const t9 = (a01 * b08 - a00 * b10 - a03 * b06) * det;
    const t10 = (a30 * b04 - a31 * b02 + a33 * b00) * det;
    const t11 = (a21 * b02 - a20 * b04 - a23 * b00) * det;
    const t12 = (a11 * b07 - a10 * b09 - a12 * b06) * det;
    const t13 = (a00 * b09 - a01 * b07 + a02 * b06) * det;
    const t14 = (a31 * b01 - a30 * b03 - a32 * b00) * det;
    const t15 = (a20 * b03 - a21 * b01 + a22 * b00) * det;
    a[0] = t0; a[1] = t1; a[2] = t2; a[3] = t3;
    a[4] = t4; a[5] = t5; a[6] = t6; a[7] = t7;
    a[8] = t8; a[9] = t9; a[10] = t10; a[11] = t11;
    a[12] = t12; a[13] = t13; a[14] = t14; a[15] = t15;
    return this;
  }

  transformPoint(v: Vec3, out: Vec3): Vec3 {
    const m = this.m;
    const x = v.x, y = v.y, z = v.z;
    const w = m[3] * x + m[7] * y + m[11] * z + m[15] || 1;
    out.x = (m[0] * x + m[4] * y + m[8] * z + m[12]) / w;
    out.y = (m[1] * x + m[5] * y + m[9] * z + m[13]) / w;
    out.z = (m[2] * x + m[6] * y + m[10] * z + m[14]) / w;
    return out;
  }

  transformDir(v: Vec3, out: Vec3): Vec3 {
    const m = this.m;
    const x = v.x, y = v.y, z = v.z;
    out.x = m[0] * x + m[4] * y + m[8] * z;
    out.y = m[1] * x + m[5] * y + m[9] * z;
    out.z = m[2] * x + m[6] * y + m[10] * z;
    return out.normalize();
  }

  /** 旋转部分变换方向（不归一化） */
  rotateDir(v: Vec3, out: Vec3): Vec3 {
    const m = this.m;
    const x = v.x, y = v.y, z = v.z;
    out.x = m[0] * x + m[4] * y + m[8] * z;
    out.y = m[1] * x + m[5] * y + m[9] * z;
    out.z = m[2] * x + m[6] * y + m[10] * z;
    return out;
  }
}

/** 透视投影（fovY 为垂直视场角，弧度） */
export function perspective(out: Mat4, fovY: number, aspect: number, near: number, far: number): Mat4 {
  const f = 1.0 / Math.tan(fovY / 2);
  const nf = 1 / (near - far);
  const m = out.m;
  m[0] = f / aspect; m[1] = 0; m[2] = 0; m[3] = 0;
  m[4] = 0; m[5] = f; m[6] = 0; m[7] = 0;
  m[8] = 0; m[9] = 0; m[10] = (far + near) * nf; m[11] = -1;
  m[12] = 0; m[13] = 0; m[14] = 2 * far * near * nf; m[15] = 0;
  return out;
}

/**
 * 相机视图矩阵。约定与原版一致：
 * forward = (-sin(yaw)·cos(pitch), sin(pitch), -cos(yaw)·cos(pitch))
 */
export function viewFromYPR(out: Mat4, pos: Vec3, yaw: number, pitch: number, roll: number): Mat4 {
  const cp = Math.cos(pitch);
  const fwd = TMP_V1.set(-Math.sin(yaw) * cp, Math.sin(pitch), -Math.cos(yaw) * cp);
  const right = TMP_V2.set(Math.cos(yaw), 0, -Math.sin(yaw));
  const up = TMP_V3.cross(right, fwd).normalize();
  if (roll !== 0) {
    const cr = Math.cos(roll);
    const sr = Math.sin(roll);
    const rx = right.x * cr + up.x * sr;
    const ry = right.y * cr + up.y * sr;
    const rz = right.z * cr + up.z * sr;
    const ux = up.x * cr - right.x * sr;
    const uy = up.y * cr - right.y * sr;
    const uz = up.z * cr - right.z * sr;
    right.set(rx, ry, rz);
    up.set(ux, uy, uz);
  }
  const m = out.m;
  m[0] = right.x; m[4] = right.y; m[8] = right.z; m[12] = -right.dot(pos);
  m[1] = up.x; m[5] = up.y; m[9] = up.z; m[13] = -up.dot(pos);
  m[2] = -fwd.x; m[6] = -fwd.y; m[10] = -fwd.z; m[14] = fwd.dot(pos);
  m[3] = 0; m[7] = 0; m[11] = 0; m[15] = 1;
  return out;
}

/** 相机观察目标（用于菜单环绕与死亡镜头） */
export function lookAt(out: Mat4, eye: Vec3, target: Vec3, upWorld: Vec3): Mat4 {
  const fwd = TMP_V1.copy(target).sub(eye).normalize();
  const right = TMP_V2.cross(fwd, upWorld).normalize();
  const up = TMP_V3.cross(right, fwd).normalize();
  const m = out.m;
  m[0] = right.x; m[4] = right.y; m[8] = right.z; m[12] = -right.dot(eye);
  m[1] = up.x; m[5] = up.y; m[9] = up.z; m[13] = -up.dot(eye);
  m[2] = -fwd.x; m[6] = -fwd.y; m[10] = -fwd.z; m[14] = fwd.dot(eye);
  m[3] = 0; m[7] = 0; m[11] = 0; m[15] = 1;
  return out;
}
