import { LAYOUTS, MAPS } from 'D:/Code/workspace/harmony/harmony-QQSpeed/entry/src/main/ets/common/Config.ets';
import { Track } from 'D:/Code/workspace/harmony/harmony-QQSpeed/entry/src/main/ets/game/Track.ets';
import { AICar } from 'D:/Code/workspace/harmony/harmony-QQSpeed/entry/src/main/ets/game/AI.ets';
import { PlayerCar, InputState } from 'D:/Code/workspace/harmony/harmony-QQSpeed/entry/src/main/ets/game/Vehicle.ets';
import { mulberry32, wrapAngle } from 'D:/Code/workspace/harmony/harmony-QQSpeed/entry/src/main/ets/common/Util.ets';

for (const map of MAPS) {
  const track = new Track(LAYOUTS[map.layout], map.bridgeY);
  // 1) 控制点偏离检查
  const pts = LAYOUTS[map.layout].points;
  let maxDev = 0;
  for (const cp of pts) {
    let best = 1e9;
    for (let i = 0; i < track.N; i++) {
      const d = Math.hypot(track.px[i] - cp[0], track.pz[i] - cp[1], (track.py[i] - (cp[2] || 0)) * 3);
      if (d < best) best = d;
    }
    if (best > maxDev) maxDev = best;
  }
  // 2) 曲率分布
  let cmax = 0;
  let csum = 0;
  for (let i = 0; i < track.N; i++) {
    const c = Math.abs(track.curv[i]);
    if (c > cmax) cmax = c;
    csum += c;
  }
  // 3) 控制段折线长度 vs 采样长度
  let plen = 0;
  for (let i = 0; i < pts.length; i++) {
    const a = pts[i];
    const b = pts[(i + 1) % pts.length];
    plen += Math.hypot(b[0] - a[0], b[1] - a[1]);
  }
  console.log(`[${map.id}] len=${track.length.toFixed(0)} ctrlPolyline=${plen.toFixed(0)} ctrlDev=${maxDev.toFixed(1)}m curvMax=${cmax.toFixed(4)} curvAvg=${(csum / track.N).toFixed(4)}`);
}

// AI 诊断：前 30 秒 vt 与 s
{
  const map = MAPS[0];
  const track = new Track(LAYOUTS[map.layout], map.bridgeY);
  const ai = new AICar(track, 'AI', 1.0, mulberry32(7));
  ai.reset(-14, 5.5);
  const DT = 1 / 120;
  for (let step = 0; step < 30 * 120; step++) {
    ai.update(DT, true, step * DT, 1);
    if (step % (5 * 120) === 0) {
      const cAhead = track.curvAhead(ai.dist, 18 + ai.s * 1.25);
      const vCorner = Math.sqrt(46 / Math.max(Math.abs(cAhead), 1e-4));
      console.log(`t=${(step / 120).toFixed(0)}s s=${ai.s.toFixed(1)} d=${ai.dist.toFixed(0)} cAhead=${cAhead.toFixed(4)} vCorner=${vCorner.toFixed(0)} lat=${ai.lat.toFixed(1)}`);
    }
  }
}
// 玩家诊断
{
  const map = MAPS[0];
  const track = new Track(LAYOUTS[map.layout], map.bridgeY);
  const P = new PlayerCar(track, '我');
  P.reset(-20, -5);
  const inp = new InputState();
  const tmp = track.freshSample();
  const DT = 1 / 120;
  for (let step = 0; step < 30 * 120; step++) {
    const s2 = track.sample(P.d + 25, tmp);
    const want = Math.atan2(s2.x - P.x, s2.z - P.z);
    const e = wrapAngle(want - P.h);
    inp.up = true;
    inp.left = e > 0.04;
    inp.right = e < -0.04;
    inp.shift = false;
    P.update(DT, inp, true, false);
    P.events.length = 0;
    if (step % (5 * 120) === 0) {
      const pr = track.project(P.x, P.y, P.z, P.hint, track.freshSample());
      console.log(`t=${(step / 120).toFixed(0)}s s=${P.s.toFixed(1)} d=${P.d.toFixed(0)} lat=${pr.lat.toFixed(1)} e=${e.toFixed(2)} wrong=${P.wrongWay.toFixed(1)}`);
    }
  }
}
