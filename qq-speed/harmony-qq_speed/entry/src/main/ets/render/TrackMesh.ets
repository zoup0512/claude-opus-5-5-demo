// 赛道几何：路面 / 标线 / 护栏 / 路缘 / 起点线 / 加速带 / 桥墩 / 隧道 / 路肩
// 按采样分块构建 + 远近两级 LOD
import { MapCfg } from '../common/Config';
import { Track, TrackSample, BoostPad } from '../game/Track';
import { Palette, parseHex } from './Palette';
import { Mesh, MeshBuilder, addBox } from './Mesh';

const CHUNK: number = 16; // 每块 16 个采样

export class TrackMeshes {
  near: Mesh[] = [];
  far: Mesh[] = [];
  extras: Mesh[] = []; // 隧道等不依赖距离的内容
  tunnelRanges: number[][] = [];

  build(track: Track, map: MapCfg, pal: Palette): void {
    const theme = map.track;
    const hw = track.halfW;
    // 路面基色
    const roadBase: Record<string, number> = {
      'asphalt': 0x43474f,
      'flagstone': 0x968e7f,
      'sandstone': 0xc39c67,
      'plate': 0xc9d3e2,
    };
    const roadDark = pal.add(Math.round(roadBase[theme.road] * 0.92));
    const roadCol = pal.add(roadBase[theme.road]);
    const lineWhite = pal.add(0xf2f2f2);
    const lineYellow = pal.add(0xe8c33a);
    const lineBlue = pal.add(0x2aa8ff);
    const lineBlueA = pal.add(0x2f7fd8);
    const wallCol: Record<string, number> = {
      'city': 0x6d7484,
      'aegean': 0xece7dc,
      'egypt': 0xd6b274,
      'snow': 0xdfeaf6,
    };
    const wallTop: Record<string, number> = {
      'city': 0x8b93a4,
      'aegean': 0xf6f2e8,
      'egypt': 0xe4c384,
      'snow': 0xeef4fb,
    };
    const wallC = pal.add(wallCol[theme.wall]);
    const wallT = pal.add(wallTop[theme.wall]);
    const wallStripe = pal.add(theme.wall === 'city' ? 0x3d4c66 : theme.wall === 'aegean' ? 0x2f7fd8 : theme.wall === 'egypt' ? 0x8a6a34 : 0xa8c4e0);
    const deckC = pal.add(theme.deckColor);
    const curbA = pal.add(parseHex(theme.curbA));
    const curbB = pal.add(parseHex(theme.curbB));
    const shoulderC = pal.add(theme.road === 'flagstone' ? 0xa89f8d : 0x8e9481);

    const H = track.wallH;
    const th = 0.6;

    for (let c0 = 0; c0 < track.N; c0 += CHUNK) {
      const c1 = Math.min(track.N, c0 + CHUNK);
      const bn = new MeshBuilder(pal);
      const bf = new MeshBuilder(pal);
      // ---- 近层：路面 + 路缘逐采样；标线/护栏/路肩 4 采样合段（面数 ≈3× 削减）----
      for (let i = c0; i < c1; i++) {
        const j = (i + 1) % track.N;
        const sbi = Math.sin(track.bank[i]);
        const sbj = Math.sin(track.bank[j]);
        // 路面
        const dark = (i % 8) >= 6;
        bn.quad(
          track.px[i] + track.rx[i] * -hw, track.py[i] + -hw * sbi, track.pz[i] + track.rz[i] * -hw,
          track.px[i] + track.rx[i] * hw, track.py[i] + hw * sbi, track.pz[i] + track.rz[i] * hw,
          track.px[j] + track.rx[j] * hw, track.py[j] + hw * sbj, track.pz[j] + track.rz[j] * hw,
          track.px[j] + track.rx[j] * -hw, track.py[j] + -hw * sbj, track.pz[j] + track.rz[j] * -hw,
          dark ? roadDark : roadCol, -1);
        // 弯心路缘（红白/主题色，逐采样保持弯道贴合）
        const innerSide = track.curv[i] > 0.011 ? -1 : track.curv[i] < -0.011 ? 1 : 0;
        if (innerSide !== 0) {
          const o0 = innerSide * (hw - 1.3);
          const o1 = innerSide * hw;
          const cc = (Math.floor(i / 3) % 2) === 0 ? curbA : curbB;
          bn.quad(
            track.px[i] + track.rx[i] * o0, track.py[i] + o0 * sbi + 0.04, track.pz[i] + track.rz[i] * o0,
            track.px[i] + track.rx[i] * o1, track.py[i] + o1 * sbi + 0.04, track.pz[i] + track.rz[i] * o1,
            track.px[j] + track.rx[j] * o1, track.py[j] + o1 * sbj + 0.04, track.pz[j] + track.rz[j] * o1,
            track.px[j] + track.rx[j] * o0, track.py[j] + o0 * sbj + 0.04, track.pz[j] + track.rz[j] * o0,
            cc, -1);
        }
      }
      // ---- 近层合段：标线 8 采样 / 护栏路肩 4 采样 ----
      for (let i = c0; i < c1; i += 8) {
        const j8 = (i + 8) % track.N;
        const sbi = Math.sin(track.bank[i]);
        const sbj = Math.sin(track.bank[j8]);
        const lift = 0.055;
        if (theme.road === 'asphalt' || theme.road === 'plate') {
          // 中心双黄线
          for (const off of [-0.35, 0.35]) {
            bn.quad(
              track.px[i] + track.rx[i] * off, track.py[i] + off * sbi + lift, track.pz[i] + track.rz[i] * off,
              track.px[i] + track.rx[i] * (off + 0.18), track.py[i] + (off + 0.18) * sbi + lift, track.pz[i] + track.rz[i] * (off + 0.18),
              track.px[j8] + track.rx[j8] * (off + 0.18), track.py[j8] + (off + 0.18) * sbj + lift, track.pz[j8] + track.rz[j8] * (off + 0.18),
              track.px[j8] + track.rx[j8] * off, track.py[j8] + off * sbj + lift, track.pz[j8] + track.rz[j8] * off,
              lineYellow, -1);
          }
          // 两侧白线
          for (const side of [-1, 1]) {
            const o = side * (hw - 0.75);
            bn.quad(
              track.px[i] + track.rx[i] * o, track.py[i] + o * sbi + lift, track.pz[i] + track.rz[i] * o,
              track.px[i] + track.rx[i] * (o + side * 0.22), track.py[i] + (o + side * 0.22) * sbi + lift, track.pz[i] + track.rz[i] * (o + side * 0.22),
              track.px[j8] + track.rx[j8] * (o + side * 0.22), track.py[j8] + (o + side * 0.22) * sbj + lift, track.pz[j8] + track.rz[j8] * (o + side * 0.22),
              track.px[j8] + track.rx[j8] * o, track.py[j8] + o * sbj + lift, track.pz[j8] + track.rz[j8] * o,
              lineWhite, -1);
          }
          // 虚线车道线（每 16 采样一段）
          if ((i % 16) === 0) {
            const jm = (i + 2) % track.N;
            const sbm = Math.sin(track.bank[jm]);
            for (const off of [-hw / 2, hw / 2]) {
              bn.quad(
                track.px[i] + track.rx[i] * off, track.py[i] + off * sbi + lift, track.pz[i] + track.rz[i] * off,
                track.px[i] + track.rx[i] * (off + 0.15), track.py[i] + (off + 0.15) * sbi + lift, track.pz[i] + track.rz[i] * (off + 0.15),
                track.px[jm] + track.rx[jm] * (off + 0.15), track.py[jm] + (off + 0.15) * sbm + lift, track.pz[jm] + track.rz[jm] * (off + 0.15),
                track.px[jm] + track.rx[jm] * off, track.py[jm] + off * sbm + lift, track.pz[jm] + track.rz[jm] * off,
                lineWhite, -1);
            }
          }
          // 霓虹边（城市蓝）
          if (theme.road === 'asphalt') {
            for (const side of [-1, 1]) {
              const o = side * (hw - 0.28);
              bn.quad(
                track.px[i] + track.rx[i] * o, track.py[i] + o * sbi + lift, track.pz[i] + track.rz[i] * o,
                track.px[i] + track.rx[i] * (o + side * 0.14), track.py[i] + (o + side * 0.14) * sbi + lift, track.pz[i] + track.rz[i] * (o + side * 0.14),
                track.px[j8] + track.rx[j8] * (o + side * 0.14), track.py[j8] + (o + side * 0.14) * sbj + lift, track.pz[j8] + track.rz[j8] * (o + side * 0.14),
                track.px[j8] + track.rx[j8] * o, track.py[j8] + o * sbj + lift, track.pz[j8] + track.rz[j8] * o,
                lineBlue, 1.5);
            }
          }
        } else {
          // 石板路：蓝色路缘线
          for (const side of [-1, 1]) {
            const o = side * (hw - 0.3);
            bn.quad(
              track.px[i] + track.rx[i] * o, track.py[i] + o * sbi + lift, track.pz[i] + track.rz[i] * o,
              track.px[i] + track.rx[i] * (o + side * 0.3), track.py[i] + (o + side * 0.3) * sbi + lift, track.pz[i] + track.rz[i] * (o + side * 0.3),
              track.px[j8] + track.rx[j8] * (o + side * 0.3), track.py[j8] + (o + side * 0.3) * sbj + lift, track.pz[j8] + track.rz[j8] * (o + side * 0.3),
              track.px[j8] + track.rx[j8] * o, track.py[j8] + o * sbj + lift, track.pz[j8] + track.rz[j8] * o,
              lineBlueA, -1);
          }
        }
      }
      // ---- 护栏/路肩：4 采样一段 ----
      for (let i = c0; i < c1; i += 4) {
        const j = (i + 4) % track.N;
        const sbi = Math.sin(track.bank[i]);
        const sbj = Math.sin(track.bank[j]);
        // 护栏（内立面 + 顶盖）
        for (const side of [-1, 1]) {
          const li = side * hw;
          const lo = side * (hw + th);
          const yi = track.py[i] + li * sbi;
          const yo = track.py[i] + lo * sbi;
          const yj = track.py[j] + li * sbj;
          const yoj = track.py[j] + lo * sbj;
          if (side < 0) {
            bn.quad(
              track.px[j] + track.rx[j] * li, yj, track.pz[j] + track.rz[j] * li,
              track.px[j] + track.rx[j] * li, yj + H, track.pz[j] + track.rz[j] * li,
              track.px[i] + track.rx[i] * li, yi + H, track.pz[i] + track.rz[i] * li,
              track.px[i] + track.rx[i] * li, yi, track.pz[i] + track.rz[i] * li,
              (i % 10) < 5 ? wallC : wallStripe, -1);
          } else {
            bn.quad(
              track.px[i] + track.rx[i] * li, yi, track.pz[i] + track.rz[i] * li,
              track.px[i] + track.rx[i] * li, yi + H, track.pz[i] + track.rz[i] * li,
              track.px[j] + track.rx[j] * li, yj + H, track.pz[j] + track.rz[j] * li,
              track.px[j] + track.rx[j] * li, yj, track.pz[j] + track.rz[j] * li,
              (i % 10) < 5 ? wallC : wallStripe, -1);
          }
          bn.quad(
            track.px[i] + track.rx[i] * li, yi + H, track.pz[i] + track.rz[i] * li,
            track.px[i] + track.rx[i] * lo, yo + H, track.pz[i] + track.rz[i] * lo,
            track.px[j] + track.rx[j] * lo, yoj + H, track.pz[j] + track.rz[j] * lo,
            track.px[j] + track.rx[j] * li, yj + H, track.pz[j] + track.rz[j] * li,
            wallT, -1);
          // 桥段外侧裙板
          if (track.bridge[i] === 1 || track.bridge[j] === 1) {
            const base = 1.6;
            if (side > 0) {
              bn.quad(
                track.px[i] + track.rx[i] * lo, yo + H, track.pz[i] + track.rz[i] * lo,
                track.px[i] + track.rx[i] * lo, track.py[i] - base, track.pz[i] + track.rz[i] * lo,
                track.px[j] + track.rx[j] * lo, track.py[j] - base, track.pz[j] + track.rz[j] * lo,
                track.px[j] + track.rx[j] * lo, yoj + H, track.pz[j] + track.rz[j] * lo,
                deckC, -1);
            } else {
              bn.quad(
                track.px[j] + track.rx[j] * lo, yoj + H, track.pz[j] + track.rz[j] * lo,
                track.px[j] + track.rx[j] * lo, track.py[j] - base, track.pz[j] + track.rz[j] * lo,
                track.px[i] + track.rx[i] * lo, track.py[i] - base, track.pz[i] + track.rz[i] * lo,
                track.px[i] + track.rx[i] * lo, yo + H, track.pz[i] + track.rz[i] * lo,
                deckC, -1);
            }
          }
        }
        // 路肩（桥段不铺）
        if (theme.shoulderWidth > 0 && track.bridge[i] === 0) {
          const w = theme.shoulderWidth;
          for (const side of [-1, 1]) {
            const o0 = side * (hw + th);
            const o1 = side * (hw + th + w);
            bn.quad(
              track.px[i] + track.rx[i] * o0, track.py[i] + side * hw * sbi - 0.02, track.pz[i] + track.rz[i] * o0,
              track.px[i] + track.rx[i] * o1, track.py[i] + side * hw * sbi - 0.17, track.pz[i] + track.rz[i] * o1,
              track.px[j] + track.rx[j] * o1, track.py[j] + side * hw * sbj - 0.17, track.pz[j] + track.rz[j] * o1,
              track.px[j] + track.rx[j] * o0, track.py[j] + side * hw * sbj - 0.02, track.pz[j] + track.rz[j] * o0,
              shoulderC, -1);
          }
        }
      }
      // ---- 远层：每 10 个采样一条路面 ----
      for (let i = c0; i < c1; i += 10) {
        const j = (i + 10) % track.N;
        const sbi = Math.sin(track.bank[i]);
        const sbj = Math.sin(track.bank[j]);
        bf.quad(
          track.px[i] + track.rx[i] * -hw, track.py[i] + -hw * sbi, track.pz[i] + track.rz[i] * -hw,
          track.px[i] + track.rx[i] * hw, track.py[i] + hw * sbi, track.pz[i] + track.rz[i] * hw,
          track.px[j] + track.rx[j] * hw, track.py[j] + hw * sbj, track.pz[j] + track.rz[j] * hw,
          track.px[j] + track.rx[j] * -hw, track.py[j] + -hw * sbj, track.pz[j] + track.rz[j] * -hw,
          roadCol, -1);
        for (const side of [-1, 1]) {
          const li = side * hw;
          const yi = track.py[i] + li * sbi;
          const yj = track.py[j] + li * sbj;
          if (side < 0) {
            bf.quad(
              track.px[j] + track.rx[j] * li, yj, track.pz[j] + track.rz[j] * li,
              track.px[j] + track.rx[j] * li, yj + H, track.pz[j] + track.rz[j] * li,
              track.px[i] + track.rx[i] * li, yi + H, track.pz[i] + track.rz[i] * li,
              track.px[i] + track.rx[i] * li, yi, track.pz[i] + track.rz[i] * li,
              wallC, -1);
          } else {
            bf.quad(
              track.px[i] + track.rx[i] * li, yi, track.pz[i] + track.rz[i] * li,
              track.px[i] + track.rx[i] * li, yi + H, track.pz[i] + track.rz[i] * li,
              track.px[j] + track.rx[j] * li, yj + H, track.pz[j] + track.rz[j] * li,
              track.px[j] + track.rx[j] * li, yj, track.pz[j] + track.rz[j] * li,
              wallC, -1);
          }
        }
      }
      this.near.push(bn.build(180));
      this.far.push(bf.build(520));
    }

    // ---- 起点线（checker）----
    const s = new TrackSample();
    const chA = pal.add(parseHex(theme.checkerA));
    const chB = pal.add(parseHex(theme.checkerB));
    const bStart = new MeshBuilder(pal);
    const cols = 8;
    for (let row = 0; row < 2; row++) {
      for (let k = 0; k < cols; k++) {
        const d0 = row * 1.6;
        const d1 = d0 + 1.6;
        const lat0 = -hw + 0.3 + (k / cols) * (2 * hw - 0.6);
        const lat1 = lat0 + (2 * hw - 0.6) / cols;
        const col = ((k + row) % 2) === 0 ? chA : chB;
        this.ribbon(bStart, track, 0 + d0, 0 + d1, lat0, lat1, col, 0.06);
      }
    }
    this.extras.push(bStart.build(500));

    // ---- 加速带 ----
    const bp = new MeshBuilder(pal);
    const boostCol = pal.add(parseHex(theme.boostColor));
    const boostCol2 = pal.add(0xffffff);
    for (const pad of theme.boostPads) {
      const d = track.dAt(pad[0], pad[1]);
      const padObj = new BoostPad();
      padObj.d = d;
      padObj.lat = 0;
      padObj.len = 11;
      padObj.halfW = 2.8;
      track.boostPads.push(padObj);
      this.ribbon(bp, track, d - 5.5, d + 5.5, -2.8, 2.8, boostCol, 0.07);
      // 箭头（白）
      for (let k = 0; k < 3; k++) {
        const dd = d - 4 + k * 3.4;
        this.ribbon(bp, track, dd, dd + 1.2, -1.6, 1.6, boostCol2, 0.08);
      }
    }
    if (theme.boostPads.length > 0) this.extras.push(bp.build(500));

    // ---- 隧道 ----
    for (const tn of theme.tunnels) {
      let d0 = track.dAt(tn[0], tn[1]);
      let d1 = track.dAt(tn[2], tn[3]);
      if (d1 < d0) d1 += track.length;
      this.buildTunnel(track, pal, map, d0, d1);
    }

    // ---- 桥墩 ----
    if (map.bridgeY < 900) {
      const bPil = new MeshBuilder(pal);
      const pilC = pal.add(theme.deckColor);
      for (let i = 0; i < track.N; i += 12) {
        if (track.bridge[i] === 0) continue;
        const x = track.px[i];
        const z = track.pz[i];
        const y = track.py[i];
        const gy = this.groundYAt === null ? y - 10 : this.groundYAt(x, z);
        const top = y - 1.6;
        if (top - gy < 1.2) continue;
        addBox(bPil, x, (gy + top) / 2, z, 3.2, top - gy + 0.5, 3.2, track.hd[i], pilC, pilC, pilC);
      }
      this.extras.push(bPil.build(700));
    }
  }

  groundYAt: ((x: number, z: number) => number) | null = null;

  // 沿路丝带（d0→d1，lat0→lat1）
  private ribbon(b: MeshBuilder, track: Track, d0: number, d1: number, lat0: number, lat1: number,
    col: number, lift: number): void {
    const segs = Math.max(1, Math.ceil((d1 - d0) / 2));
    const s = new TrackSample();
    for (let k = 0; k < segs; k++) {
      const da = d0 + (d1 - d0) * (k / segs);
      const db = d0 + (d1 - d0) * ((k + 1) / segs);
      track.sample(da, s);
      const a0x = s.x + s.rx * lat0;
      const a0y = s.y + lat0 * Math.sin(s.bank) + lift;
      const a0z = s.z + s.rz * lat0;
      const a1x = s.x + s.rx * lat1;
      const a1y = s.y + lat1 * Math.sin(s.bank) + lift;
      const a1z = s.z + s.rz * lat1;
      track.sample(db, s);
      b.quad(a0x, a0y, a0z, a1x, a1y, a1z,
        s.x + s.rx * lat1, s.y + lat1 * Math.sin(s.bank) + lift, s.z + s.rz * lat1,
        s.x + s.rx * lat0, s.y + lat0 * Math.sin(s.bank) + lift, s.z + s.rz * lat0,
        col, -1);
    }
  }

  private buildTunnel(track: Track, pal: Palette, map: MapCfg, d0: number, d1: number): void {
    const b = new MeshBuilder(pal);
    const hw = track.halfW + 0.6;
    const hTop = 9.5;
    const innerC = pal.add(0x5a5148);
    const innerLit = pal.add(0xffe9b0);
    const outerC = pal.add(map.track.tunnelOuter);
    const segs = Math.ceil((d1 - d0) / 3);
    const M = 9;
    const s = new TrackSample();
    // 内拱面 + 外拱面
    for (let k = 0; k < segs; k++) {
      const sa = new TrackSample();
      const sb2 = new TrackSample();
      track.sample(d0 + ((d1 - d0) * k) / segs, sa);
      track.sample(d0 + ((d1 - d0) * (k + 1)) / segs, sb2);
      for (let m = 0; m < M; m++) {
        const a0 = Math.PI * (m / M);
        const a1 = Math.PI * ((m + 1) / M);
        const lit = (m % 3) === 1 && (k % 4) === 0;
        const col = lit ? innerLit : innerC;
        // 内拱
        this.archQuad(b, sa, sb2, a0, a1, hw, hTop, col, map.track.tunnelOuter !== 0 ? false : false);
        // 外拱（略大、颜色 outer）
        this.archQuad(b, sa, sb2, a0, a1, hw + 2.5, hTop + 2.5, outerC, true);
      }
    }
    // 洞口门框
    for (const dd of [d0, d1]) {
      track.sample(dd, s);
      const frameC = pal.add(0xe8e2d4);
      for (const side of [-1, 1]) {
        addBox(b, s.x + s.rx * side * (hw + 0.8), s.y + 5, s.z + s.rz * side * (hw + 0.8),
          1.8, 10, 2.4, s.hd, frameC, frameC, frameC);
      }
      addBox(b, s.x, s.y + 10.4, s.z, (hw + 1.6) * 2, 1.8, 2.4, s.hd, frameC, frameC, frameC);
    }
    this.extras.push(b.build(900));
    track.tunnels.push([d0, d1]);
    this.tunnelRanges.push([d0, d1]);
  }

  private archQuad(b: MeshBuilder, sa: TrackSample, sb: TrackSample, a0: number, a1: number,
    hw: number, hTop: number, col: number, flip: boolean): void {
    const p = (st: TrackSample, a: number): number[] => {
      const lat = -Math.cos(a) * hw;
      const y = st.y + 1.25 + Math.sin(a) * (hTop - 1.25);
      return [st.x + st.rx * lat, y, st.z + st.rz * lat];
    };
    const A0 = p(sa, a0);
    const A1 = p(sa, a1);
    const B0 = p(sb, a0);
    const B1 = p(sb, a1);
    if (flip) {
      b.quad(A1[0], A1[1], A1[2], A0[0], A0[1], A0[2], B0[0], B0[1], B0[2], B1[0], B1[1], B1[2], col, -1);
    } else {
      b.quad(A0[0], A0[1], A0[2], A1[0], A1[1], A1[2], B1[0], B1[1], B1[2], B0[0], B0[1], B0[2], col, -1);
    }
  }
}
