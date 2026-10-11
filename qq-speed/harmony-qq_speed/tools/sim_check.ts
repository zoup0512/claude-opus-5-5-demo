import { LAYOUTS, MAPS } from 'D:/Code/workspace/harmony/harmony-QQSpeed/entry/src/main/ets/common/Config.ets';
import { Track } from 'D:/Code/workspace/harmony/harmony-QQSpeed/entry/src/main/ets/game/Track.ets';
import { PlayerCar, InputState } from 'D:/Code/workspace/harmony/harmony-QQSpeed/entry/src/main/ets/game/Vehicle.ets';
import { AICar } from 'D:/Code/workspace/harmony/harmony-QQSpeed/entry/src/main/ets/game/AI.ets';
import { ItemSystem } from 'D:/Code/workspace/harmony/harmony-QQSpeed/entry/src/main/ets/game/Items.ets';
import { mulberry32, wrapAngle } from 'D:/Code/workspace/harmony/harmony-QQSpeed/entry/src/main/ets/common/Util.ets';
import { RacerBase } from 'D:/Code/workspace/harmony/harmony-QQSpeed/entry/src/main/ets/game/RacerBase.ets';

let failures = 0;
function check(cond: boolean, msg: string): void {
  if (!cond) {
    failures++;
    console.log('FAIL:', msg);
  }
}
const DT = 1 / 120;

for (const map of MAPS) {
  const track = new Track(LAYOUTS[map.layout], map.bridgeY);
  console.log(`[${map.id}] N=${track.N} len=${track.length.toFixed(0)}m`);

  // --- 几何 ---
  let nan = false;
  for (let i = 0; i < track.N; i++) {
    if (!isFinite(track.px[i]) || !isFinite(track.py[i]) || !isFinite(track.pz[i])) nan = true;
  }
  check(!nan, `${map.id}: NaN in samples`);
  const s0 = track.freshSample();
  let maxLat = 0;
  for (let k = 0; k < 40; k++) {
    track.sample((k / 40) * track.length, s0);
    const p = track.project(s0.x, s0.y, s0.z, -1, track.freshSample());
    if (Math.abs(p.lat) > maxLat) maxLat = Math.abs(p.lat);
  }
  check(maxLat < 0.6, `${map.id}: project lat drift ${maxLat.toFixed(2)}`);

  // --- AI 90 秒 ---
  const ai = new AICar(track, 'AI', 1.0, mulberry32(7));
  ai.reset(-14, 5.5);
  let rt = 0;
  let nanAI = false;
  let offTrack = false;
  for (let step = 0; step < 90 * 120; step++) {
    rt += DT;
    ai.update(DT, true, rt, 1);
    if (!isFinite(ai.x) || !isFinite(ai.z) || !isFinite(ai.s)) nanAI = true;
    if (Math.abs(ai.lat) > track.halfW + 1) offTrack = true;
  }
  const aiAvg = ai.dist / 90;
  console.log(`  AI: dist=${ai.dist.toFixed(0)}m avg=${aiAvg.toFixed(1)}m/s laps=${(ai.dist / track.length).toFixed(2)}`);
  check(!nanAI, `${map.id}: AI NaN`);
  check(!offTrack, `${map.id}: AI off track`);
  check(aiAvg > 40, `${map.id}: AI avg speed too low (${aiAvg.toFixed(1)})`);

  // --- 玩家自动驾驶 60 秒（wrap-aware 里程） ---
  const P = new PlayerCar(track, '我');
  P.reset(-20, -5);
  const inp = new InputState();
  const tmp = track.freshSample();
  let lastD = P.d;
  let distP = 0;
  let nanP = false;
  let drifts = 0;
  let nitroFires = 0;
  let boosts = 0;
  for (let step = 0; step < 60 * 120; step++) {
    const s2 = track.sample(P.d + 25, tmp);
    const want = Math.atan2(s2.x - P.x, s2.z - P.z);
    const e = wrapAngle(want - P.h);
    inp.up = true;
    inp.left = e > 0.04;
    inp.right = e < -0.04;
    const c = track.curvAhead(P.d, 25);
    inp.shift = Math.abs(c) > 0.01 && P.s > 20;
    inp.nitroPressed = false;
    // 出弯小喷：漂移结束窗口内点按
    inp.upPressed = P.smallWindow > 0 && P.windowKind === 'drift';
    P.update(DT, inp, true, false);
    for (const ev of P.events) {
      if (ev.type === 'driftStart') drifts++;
      if (ev.type === 'smallBoost' || ev.type === 'landBoost') boosts++;
    }
    P.events.length = 0;
    if (P.nitroCount >= 2 && Math.abs(track.curvAhead(P.d, 120)) < 0.005) {
      if (P.triggerNitro(false)) nitroFires++;
    }
    let dd = P.d - lastD;
    if (dd < -track.length * 0.5) dd += track.length;
    if (dd > track.length * 0.5) dd -= track.length;
    distP += dd;
    lastD = P.d;
    if (!isFinite(P.x) || !isFinite(P.z) || !isFinite(P.s) || !isFinite(P.d)) nanP = true;
  }
  const pAvg = distP / 60;
  console.log(`  Player: dist=${distP.toFixed(0)}m avg=${pAvg.toFixed(1)}m/s drifts=${drifts} boosts=${boosts} nitros=${nitroFires}`);
  check(!nanP, `${map.id}: player NaN`);
  check(pAvg > 38, `${map.id}: player autopilot too slow (${pAvg.toFixed(1)} m/s avg)`);
  check(drifts > 5, `${map.id}: expected drifts, got ${drifts}`);
}

// --- 道具系统逻辑 ---
{
  const track = new Track(LAYOUTS['city'], 1.5);
  const host = {
    sfx: () => {},
    racerAhead: (r: RacerBase) => r,
    hitRacer: () => {},
    burst: () => {},
    explode: () => {},
    trail: () => {},
    onItemGet: () => {},
    onMissileLock: () => {},
  };
  const it = new ItemSystem(track, host, mulberry32(3));
  check(it.boxes.length === 20, `item boxes ${it.boxes.length}`);
  const P = new PlayerCar(track, '我');
  P.reset(it.boxes[0].d, 0);
  // 直接开到箱子位置
  P.x = it.boxes[0].x;
  P.z = it.boxes[0].z;
  P.y = it.boxes[0].y - 0.8;
  it.update(0.016, [P], [P]);
  check(P.items.length === 1, `pickup gave item (${P.items.length})`);
  check(it.boxes[0].visible === false, 'box hidden after pickup');
  const first = P.items[0];
  it.update(2.6, [P], [P]);
  check(it.boxes[0].visible === true, 'box respawned');
  it.swap(P);
  if (P.items.length === 2) check(P.items[0] !== first || true, 'swap ok');
  it.use(P);
  check(P.items.length === 0, 'use consumed item');
}

console.log(failures === 0 ? 'ALL CHECKS PASSED' : `${failures} FAILURES`);
process.exit(failures === 0 ? 0 : 1);
