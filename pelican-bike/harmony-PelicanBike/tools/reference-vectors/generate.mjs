import { createHash } from 'node:crypto';
import { readFile, mkdir, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import * as THREE from 'three';
import { ImprovedNoise } from 'three/addons/math/ImprovedNoise.js';

const HERE = dirname(fileURLToPath(import.meta.url));
export const TARGET_ROOT = resolve(HERE, '..', '..');
export const SOURCE_ROOT = resolve(
  process.env.PELICAN_BIKE_SOURCE_ROOT ||
    resolve(HERE, '..', '..', '..', '..', 'h5', 'claude-opus-5-5-demo', 'pelican-bike'),
);
export const GOLDEN_PATH = resolve(TARGET_ROOT, 'docs', 'reference-vectors', 'pelican-bike-golden.json');

export const SOURCE_FILES = Object.freeze({
  util: resolve(SOURCE_ROOT, 'src', 'util.js'),
  ocean: resolve(SOURCE_ROOT, 'src', 'ocean.js'),
  world: resolve(SOURCE_ROOT, 'src', 'world.js'),
  main: resolve(SOURCE_ROOT, 'src', 'main.js'),
  bicycle: resolve(SOURCE_ROOT, 'src', 'bicycle.js'),
});

const sha256 = (data) => createHash('sha256').update(data).digest('hex');
const stripExport = (text) => text.replace(/^export\s+/, '');

function findStatementEnd(source, start) {
  let paren = 0;
  let bracket = 0;
  let brace = 0;
  let mode = 'code';
  let escaped = false;

  for (let i = start; i < source.length; i++) {
    const ch = source[i];
    const next = source[i + 1];

    if (mode === 'lineComment') {
      if (ch === '\n') mode = 'code';
      continue;
    }
    if (mode === 'blockComment') {
      if (ch === '*' && next === '/') {
        mode = 'code';
        i++;
      }
      continue;
    }
    if (mode !== 'code') {
      if (escaped) {
        escaped = false;
        continue;
      }
      if (ch === '\\') {
        escaped = true;
        continue;
      }
      if ((mode === 'single' && ch === "'") || (mode === 'double' && ch === '"') || (mode === 'template' && ch === '`')) {
        mode = 'code';
      }
      continue;
    }

    if (ch === '/' && next === '/') {
      mode = 'lineComment';
      i++;
      continue;
    }
    if (ch === '/' && next === '*') {
      mode = 'blockComment';
      i++;
      continue;
    }
    if (ch === "'") {
      mode = 'single';
      continue;
    }
    if (ch === '"') {
      mode = 'double';
      continue;
    }
    if (ch === '`') {
      mode = 'template';
      continue;
    }
    if (ch === '(') paren++;
    else if (ch === ')') paren--;
    else if (ch === '[') bracket++;
    else if (ch === ']') bracket--;
    else if (ch === '{') brace++;
    else if (ch === '}') brace--;
    else if (ch === ';' && paren === 0 && bracket === 0 && brace === 0) return i + 1;
  }
  throw new Error(`Could not find statement terminator after offset ${start}`);
}

function findMatchingBrace(source, open) {
  let depth = 0;
  let mode = 'code';
  let escaped = false;

  for (let i = open; i < source.length; i++) {
    const ch = source[i];
    const next = source[i + 1];

    if (mode === 'lineComment') {
      if (ch === '\n') mode = 'code';
      continue;
    }
    if (mode === 'blockComment') {
      if (ch === '*' && next === '/') {
        mode = 'code';
        i++;
      }
      continue;
    }
    if (mode !== 'code') {
      if (escaped) {
        escaped = false;
        continue;
      }
      if (ch === '\\') {
        escaped = true;
        continue;
      }
      if ((mode === 'single' && ch === "'") || (mode === 'double' && ch === '"') || (mode === 'template' && ch === '`')) {
        mode = 'code';
      }
      continue;
    }

    if (ch === '/' && next === '/') {
      mode = 'lineComment';
      i++;
      continue;
    }
    if (ch === '/' && next === '*') {
      mode = 'blockComment';
      i++;
      continue;
    }
    if (ch === "'") {
      mode = 'single';
      continue;
    }
    if (ch === '"') {
      mode = 'double';
      continue;
    }
    if (ch === '`') {
      mode = 'template';
      continue;
    }
    if (ch === '{') depth++;
    else if (ch === '}') {
      depth--;
      if (depth === 0) return i;
    }
  }
  throw new Error(`Could not match brace at offset ${open}`);
}

function extractConst(source, name) {
  const escapedName = name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const match = new RegExp(`(?:export\\s+)?const\\s+${escapedName}\\s*=`).exec(source);
  if (!match) throw new Error(`Missing const declaration: ${name}`);
  return stripExport(source.slice(match.index, findStatementEnd(source, match.index)));
}

function extractFunction(source, name) {
  const escapedName = name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const match = new RegExp(`(?:export\\s+)?function\\s+${escapedName}\\s*\\(`).exec(source);
  if (!match) throw new Error(`Missing function declaration: ${name}`);
  const open = source.indexOf('{', match.index + match[0].length);
  if (open < 0) throw new Error(`Missing body for function: ${name}`);
  return stripExport(source.slice(match.index, findMatchingBrace(source, open) + 1));
}

function normalizeCode(text) {
  return text.replace(/\s+/g, ' ').trim();
}

async function loadSources() {
  const entries = await Promise.all(
    Object.entries(SOURCE_FILES).map(async ([key, path]) => [key, await readFile(path, 'utf8')]),
  );
  return Object.fromEntries(entries);
}

function compileUtil(source) {
  const body = [
    extractConst(source, 'TAU'),
    extractConst(source, 'clamp'),
    extractConst(source, 'lerp'),
    extractConst(source, 'smoothstep'),
    extractConst(source, 'damp'),
    extractFunction(source, 'mulberry32'),
    extractConst(source, '_dir'),
    extractConst(source, '_bend'),
    extractFunction(source, 'solveTwoBone'),
    'return { TAU, clamp, lerp, smoothstep, damp, mulberry32, solveTwoBone };',
  ].join('\n\n');
  return new Function('THREE', `"use strict";\n${body}`)(THREE);
}

function compileOcean(source) {
  const body = [
    extractConst(source, 'SEA_LEVEL'),
    extractConst(source, 'SHORE_Z'),
    extractConst(source, 'WAVES'),
    extractFunction(source, 'wavePhases'),
    extractFunction(source, 'waveHeight'),
    'return { SEA_LEVEL, SHORE_Z, WAVES, wavePhases, waveHeight };',
  ].join('\n\n');
  return new Function(`"use strict";\n${body}`)();
}

function compileWorld(source, util) {
  const body = [
    extractConst(source, 'perlin'),
    extractFunction(source, 'fbm2'),
    extractFunction(source, 'terrainHeight'),
    'return { terrainHeight };',
  ].join('\n\n');
  return new Function('ImprovedNoise', 'smoothstep', `"use strict";\n${body}`)(ImprovedNoise, util.smoothstep);
}

function compileRideFactory(mainSource, bicycleSource, utilSource) {
  const body = [
    extractConst(utilSource, 'TAU'),
    extractConst(utilSource, 'clamp'),
    extractConst(utilSource, 'lerp'),
    extractConst(utilSource, 'damp'),
    extractConst(bicycleSource, 'WHEEL_R'),
    extractConst(bicycleSource, 'GEARS'),
    extractConst(mainSource, 'S'),
    extractFunction(mainSource, 'updateRide'),
    extractFunction(mainSource, 'jump'),
    'return { S, updateRide, jump, WHEEL_R, GEARS, TAU };',
  ].join('\n\n');

  const construct = new Function(
    'settings',
    'keys',
    'audio',
    'nextFish',
    'rider',
    'wheelieRoot',
    'bike',
    'env',
    'burstDust',
    'unlock',
    `"use strict";\n${body}`,
  );

  return function createRideRuntime(overrides = {}) {
    const settings = {
      cruise: 7.5,
      autopilot: false,
      autoGear: true,
      ...overrides,
    };
    const keys = {};
    const audio = {
      enabled: false,
      ctx: { currentTime: 0 },
      click() {},
      thump() {},
      whoosh() {},
    };
    const rider = {
      position: { x: 0, y: 0, z: 0, set(x, y, z) { this.x = x; this.y = y; this.z = z; } },
      rotation: { x: 0, y: 0, z: 0, set(x, y, z) { this.x = x; this.y = y; this.z = z; } },
      updateMatrixWorld() {},
    };
    const wheelieRoot = { rotation: { z: 0 } };
    const bike = { update() {} };
    const env = { night: 0 };
    const runtime = construct(
      settings,
      keys,
      audio,
      () => null,
      rider,
      wheelieRoot,
      bike,
      env,
      () => {},
      () => {},
    );
    runtime.settings = settings;
    runtime.keys = keys;
    runtime.rider = rider;
    runtime.wheelieRoot = wheelieRoot;
    runtime.S.started = true;
    return runtime;
  };
}

function compileFishFactory(mainSource, util) {
  const body = [
    extractConst(mainSource, 'LANES'),
    'const rnd = mulberry32(2024);',
    extractFunction(mainSource, 'spawnFish'),
    'return { LANES, spawnFish };',
  ].join('\n\n');
  const construct = new Function(
    'mulberry32',
    'TAU',
    'fishes',
    'S',
    'fishMat',
    'goldMat',
    `"use strict";\n${body}`,
  );
  return (fishes, state, fishMat, goldMat) => construct(util.mulberry32, util.TAU, fishes, state, fishMat, goldMat);
}

function buildPrimitiveVectors(util) {
  const clampCases = [
    { args: [-3, -1, 2] },
    { args: [-1, -1, 2] },
    { args: [0.25, -1, 2] },
    { args: [2, -1, 2] },
    { args: [9, -1, 2] },
    { args: [1e-12, 0, 1] },
  ].map((entry) => ({ ...entry, value: util.clamp(...entry.args) }));

  const lerpCases = [
    { args: [0, 10, 0] },
    { args: [0, 10, 0.25] },
    { args: [-5, 7, 0.5] },
    { args: [10, -2, 1] },
    { args: [2, 6, -0.5] },
    { args: [2, 6, 1.5] },
  ].map((entry) => ({ ...entry, value: util.lerp(...entry.args) }));

  const dampCases = [
    { args: [0, 10, 6, 1 / 60] },
    { args: [10, -5, 0.7, 0.25] },
    { args: [-2, 8, 4, 1] },
    { args: [3, 9, 0, 1 / 60] },
    { args: [3, 9, 10, 0] },
    { args: [1e6, -1e6, 0.001, 12.5] },
  ].map((entry) => ({ ...entry, value: util.damp(...entry.args) }));

  const smoothstepCases = [
    { args: [0, 1, -1] },
    { args: [0, 1, 0] },
    { args: [0, 1, 0.25] },
    { args: [0, 1, 0.5] },
    { args: [0, 1, 0.75] },
    { args: [0, 1, 1] },
    { args: [0, 1, 2] },
    { args: [3.8, 28, 16] },
    { args: [1, -1, 0.25] },
  ].map((entry) => ({ ...entry, value: util.smoothstep(...entry.args) }));

  return { clamp: clampCases, lerp: lerpCases, damp: dampCases, smoothstep: smoothstepCases };
}

function buildMulberryVectors(util) {
  const rng = util.mulberry32(0);
  const first32 = Array.from({ length: 32 }, () => rng());
  const seeded = [1, -1, 2024, 0x7fffffff].map((seed) => {
    const next = util.mulberry32(seed);
    return { seed, first8: Array.from({ length: 8 }, () => next()) };
  });
  return { algorithm: 'mulberry32', seed: 0, first32, additionalSeeds: seeded };
}

function buildWaveVectors(ocean) {
  const phaseInputs = [
    [0, 0],
    [12.5, 0],
    [0, 3.25],
    [123.456, 7.89],
    [-987.65, 42],
    [36000.125, 600],
    [1e6, 86400],
    [1e12, 1e9],
  ];
  const phaseCases = phaseInputs.map(([distance, time]) => {
    const doubleOut = ocean.wavePhases(distance, time, new Array(ocean.WAVES.length).fill(0));
    const floatOut = ocean.wavePhases(distance, time, new Float32Array(ocean.WAVES.length));
    return { distance, time, float64: Array.from(doubleOut), float32: Array.from(floatOut) };
  });

  const heightInputs = [
    [0, ocean.SHORE_Z, 0, 1],
    [12.5, -10, 3.25, 1],
    [-55, -30, 17.5, 0.65],
    [80, -80, 9.75, 1.4],
    [36000.125, -14.1, 600, 1],
    [-36000.125, -45, 600, 1],
    [1e6, -120, 86400, 1.8],
    [-1e9, -500, 1e7, 0.3],
    [3.5, 4, 2, 1],
    [99.9, -200, -12.25, 2.2],
    [0, -15.6, 0, 0],
    [-0.001, -13.6, 0.001, 1],
  ];
  const heightCases = heightInputs.map(([x, z, time, amp]) => ({
    x,
    z,
    time,
    amp,
    value: ocean.waveHeight(x, z, time, amp),
  }));

  return {
    seaLevel: ocean.SEA_LEVEL,
    shoreZ: ocean.SHORE_Z,
    waves: ocean.WAVES.map((wave, index) => ({
      index,
      direction: [wave[0], wave[1]],
      steepness: wave[2],
      wavelength: wave[3],
      speedMultiplier: wave[4],
    })),
    wavePhases: phaseCases,
    waveHeight: heightCases,
  };
}

function buildTerrainVectors(world) {
  const inputs = [
    ['road_edge_negative_epsilon', 0, -0.001],
    ['road_edge_zero', 0, 0],
    ['beach_near', 1.25, -3.2],
    ['dune_start', -7.5, -3.6],
    ['dune_mid', 13.75, -6.5],
    ['wet_sand', -21.2, -9],
    ['shore_guard', 42, -13],
    ['deep_beach', -88, -30],
    ['far_sea_terrain', 125, -250],
    ['hill_start', 3.5, 3.8],
    ['hill_blend', -17.25, 16],
    ['hill_full', 99.5, 28],
    ['mountain', -250.75, 115],
    ['positive_long_36k', 36000.125, 72],
    ['negative_long_36k', -36000.125, 72],
    ['positive_million', 1e6, 48],
    ['negative_million', -1e6, -8],
    ['positive_billion', 1e9, 128],
    ['negative_billion', -1e9, -128],
    ['extreme_positive', 1e12, 1e6],
    ['extreme_negative', -1e12, -1e6],
  ];
  return inputs.map(([id, x, z]) => ({ id, x, z, value: world.terrainHeight(x, z) }));
}

function buildIkVectors(util) {
  const cases = [
    { id: 'reachable_planar', A: [0, 0, 0], T: [1.2, 0.4, 0], a: 1, b: 1, pole: [0, 1, 0] },
    { id: 'unreachable_clamped', A: [0, 0, 0], T: [3, 0, 0], a: 1, b: 1, pole: [0, 1, 0] },
    { id: 'inside_min_reach', A: [0, 0, 0], T: [0.1, 0, 0], a: 1.2, b: 0.4, pole: [0, 0, 1] },
    { id: 'parallel_pole_fallback', A: [0, 0, 0], T: [1, 0, 0], a: 0.8, b: 0.8, pole: [2, 0, 0] },
    { id: 'negative_bend', A: [0.5, -0.25, 1], T: [-0.4, 1.1, -0.7], a: 1.4, b: 1.1, pole: [0, -1, 0.25] },
    { id: 'three_dimensional', A: [-4, 2, 7], T: [3, -1, 5], a: 5.5, b: 4.2, pole: [0.3, 0.8, -0.5] },
    { id: 'zero_target_delta', A: [2, 3, 4], T: [2, 3, 4], a: 1, b: 1, pole: [0, 0, 1] },
  ];

  return cases.map((entry) => {
    const A = new THREE.Vector3(...entry.A);
    const T = new THREE.Vector3(...entry.T);
    const pole = new THREE.Vector3(...entry.pole);
    const outMid = new THREE.Vector3();
    const outEnd = new THREE.Vector3();
    const reachable = util.solveTwoBone(A, T, entry.a, entry.b, pole, outMid, outEnd);
    return { ...entry, reachable, outMid: outMid.toArray(), outEnd: outEnd.toArray() };
  });
}

const RIDE_DT = 1 / 60;
const RIDE_FRAMES = 10 * 60;
const RIDE_COLUMNS = [
  'frame',
  'time',
  'speed',
  'distance',
  'lane',
  'laneV',
  'latAcc',
  'lean',
  'steer',
  'y',
  'vy',
  'airborne',
  'gear',
  'cadence',
  'wheel',
  'crank',
  'pedaling',
  'accel',
  'wheelie',
];

function rideRow(frame, S) {
  return [
    frame,
    S.time,
    S.speed,
    S.distance,
    S.lane,
    S.laneV,
    S.latAcc,
    S.lean,
    S.steer,
    S.y,
    S.vy,
    S.airborne,
    S.gear,
    S.cadence,
    S.wheel,
    S.crank,
    S.pedaling,
    S.accel,
    S.wheelie,
  ];
}

function buildRideVectors(createRideRuntime) {
  const definitions = [
    {
      id: 'acceleration',
      description: 'Hold accelerate for all 10 seconds.',
      input(t, keys) { keys.up = t < 10; },
    },
    {
      id: 'braking',
      description: 'Hold brake for all 10 seconds.',
      input(t, keys) { keys.down = t < 10; },
    },
    {
      id: 'cruise',
      description: 'No longitudinal or lateral input; cruise controller converges to 7.5 m/s.',
      input() {},
    },
    {
      id: 'lateral',
      description: 'Right for 0-2 s, left for 4-6 s, neutral otherwise.',
      input(t, keys) {
        keys.right = t < 2;
        keys.left = t >= 4 && t < 6;
      },
    },
    {
      id: 'jump',
      description: 'Trigger jump immediately before fixed-step frame 1, then coast.',
      beforeFrame(frame, runtime) { if (frame === 1) runtime.jump(); },
      input() {},
    },
  ];

  const scenarios = definitions.map((definition) => {
    const runtime = createRideRuntime({ cruise: 7.5, autopilot: false, autoGear: true });
    const rows = [rideRow(0, runtime.S)];
    for (let frame = 1; frame <= RIDE_FRAMES; frame++) {
      const tBefore = (frame - 1) * RIDE_DT;
      for (const key of Object.keys(runtime.keys)) runtime.keys[key] = false;
      definition.input(tBefore, runtime.keys);
      definition.beforeFrame?.(frame, runtime);
      runtime.S.t += RIDE_DT;
      runtime.S.time += RIDE_DT;
      runtime.updateRide(RIDE_DT);
      rows.push(rideRow(frame, runtime.S));
    }
    return {
      id: definition.id,
      description: definition.description,
      settings: { cruise: 7.5, autopilot: false, autoGear: true },
      rows,
    };
  });

  return {
    dt: RIDE_DT,
    durationSeconds: 10,
    frames: RIDE_FRAMES,
    columns: RIDE_COLUMNS,
    scenarios,
  };
}

function buildGearVectors(createRideRuntime) {
  const base = createRideRuntime();
  const { GEARS, WHEEL_R, TAU } = base;
  const speedForCadence = (cadence, ratio) => cadence * (TAU / 60) * WHEEL_R * ratio;
  const evaluate = (gear, speed) => {
    const runtime = createRideRuntime({ cruise: 7.5, autopilot: false, autoGear: true });
    runtime.S.gear = gear;
    runtime.S.speed = speed;
    runtime.S.time = 9;
    runtime.S.t = 9;
    runtime.S.lastGearManual = -99;
    const ratioBefore = GEARS[gear][0] / GEARS[gear][1];
    const wheelRpm = (speed / WHEEL_R) * 60 / TAU;
    const cadenceBefore = wheelRpm / ratioBefore;
    runtime.updateRide(0);
    return {
      speed,
      cadenceBefore,
      outputGear: runtime.S.gear,
      outputCadence: runtime.S.cadence,
    };
  };

  const epsilon = 1e-7;
  const gears = GEARS.map(([ring, cog], gear) => {
    const ratio = ring / cog;
    const lowSpeed = speedForCadence(68, ratio);
    const highSpeed = speedForCadence(102, ratio);
    const probes = (boundary) => [-epsilon, 0, epsilon].map((delta) => ({ delta, ...evaluate(gear, boundary + delta) }));
    return {
      gear,
      displayGear: gear + 1,
      ring,
      cog,
      ratio,
      cadenceBandRpm: [68, 102],
      lowBoundarySpeed: lowSpeed,
      highBoundarySpeed: highSpeed,
      lowBoundaryProbes: probes(lowSpeed),
      highBoundaryProbes: probes(highSpeed),
    };
  });

  return {
    targetCadenceRpm: 86,
    shiftCadenceBandRpm: [68, 102],
    probeEpsilonMetersPerSecond: epsilon,
    gears,
  };
}

function makeFishStub() {
  return {
    active: false,
    caught: -1,
    x: 0,
    y: 0,
    z: 0,
    golden: false,
    phase: 0,
    mesh: {
      material: null,
      visible: false,
      scale: { value: 1, setScalar(value) { this.value = value; } },
    },
    halo: {
      material: {
        color: { value: null, set(value) { this.value = value; } },
      },
    },
  };
}

function buildFishVectors(createFishRuntime) {
  const fishes = [makeFishStub()];
  const S = { distance: 0 };
  const fishMat = { id: 'normal' };
  const goldMat = { id: 'golden' };
  const runtime = createFishRuntime(fishes, S, fishMat, goldMat);
  const spawns = [];

  for (let index = 0; index < 32; index++) {
    const fish = fishes[0];
    fish.active = false;
    S.distance = index * 100;
    const ahead = index === 0 ? 32 : 85;
    runtime.spawnFish(ahead);
    spawns.push({
      index,
      distance: S.distance,
      ahead,
      x: fish.x,
      lane: fish.z,
      y: fish.y,
      golden: fish.golden,
      phase: fish.phase,
      material: fish.mesh.material.id,
      haloColor: fish.halo.material.color.value,
    });
  }

  return {
    seed: 2024,
    lanes: runtime.LANES,
    goldenProbability: 0.12,
    spawns,
  };
}

function buildAchievementVectors(mainSource) {
  const definitions = new Function(`"use strict";\n${extractConst(mainSource, 'ACH')}\nreturn ACH;`)();
  const jumpSource = extractFunction(mainSource, 'jump');
  const trickSource = extractFunction(mainSource, 'trick');
  const ringBellSource = extractFunction(mainSource, 'ringBell');
  const honkSource = extractFunction(mainSource, 'honk');
  const fishThresholdSource = normalizeCode(mainSource.slice(mainSource.indexOf("unlock('fish1');"), mainSource.indexOf("if (S.fish >= 50) unlock('fish50');") + "if (S.fish >= 50) unlock('fish50');".length));
  const hudThresholdSource = normalizeCode(mainSource.slice(mainSource.indexOf("if (kmh >= 30)"), mainSource.indexOf("if (info.night > 0.8") + "if (info.night > 0.8 && S.started && S.time > 5) unlock('night');".length));
  const has = (source, fragment) => {
    if (!source.includes(fragment)) throw new Error(`Achievement source fragment changed or missing: ${fragment}`);
    return fragment;
  };
  const thresholdCases = [
    { id: 'fish1', kind: 'event', metric: 'successful fish catches', threshold: 1, sourceCondition: has(fishThresholdSource, "unlock('fish1');") },
    { id: 'golden', kind: 'event', metric: 'golden fish catches', threshold: 1, sourceCondition: has(fishThresholdSource, "if (f.golden) unlock('golden');") },
    { id: 'fish10', kind: 'gte', metric: 'S.fish', threshold: 10, probes: [9, 10, 11], sourceCondition: has(fishThresholdSource, "if (S.fish >= 10) unlock('fish10');") },
    { id: 'fish50', kind: 'gte', metric: 'S.fish', threshold: 50, probes: [49, 50, 51], sourceCondition: has(fishThresholdSource, "if (S.fish >= 50) unlock('fish50');") },
    { id: 'jump', kind: 'event', metric: 'successful jumps', threshold: 1, sourceCondition: has(jumpSource, "unlock('jump');") },
    { id: 'trick', kind: 'event', metric: 'successful tricks', threshold: 1, sourceCondition: has(trickSource, "unlock('trick');") },
    { id: 'trick3', kind: 'gte', metric: 'S.tricks', threshold: 3, probes: [2, 3, 4], sourceCondition: has(trickSource, "if (S.tricks >= 3) unlock('trick3');") },
    { id: 'speed30', kind: 'gte', metric: 'speedKmh', threshold: 30, thresholdMetersPerSecond: 30 / 3.6, probes: [29.999, 30, 30.001], sourceCondition: has(hudThresholdSource, "if (kmh >= 30) unlock('speed30');") },
    { id: 'speed45', kind: 'gte', metric: 'speedKmh', threshold: 45, thresholdMetersPerSecond: 45 / 3.6, probes: [44.999, 45, 45.001], sourceCondition: has(hudThresholdSource, "if (kmh >= 45) unlock('speed45');") },
    { id: 'km1', kind: 'gte', metric: 'S.distance', threshold: 1000, probes: [999.999, 1000, 1000.001], sourceCondition: has(hudThresholdSource, "if (S.distance >= 1000) unlock('km1');") },
    { id: 'km5', kind: 'gte', metric: 'S.distance', threshold: 5000, probes: [4999.999, 5000, 5000.001], sourceCondition: has(hudThresholdSource, "if (S.distance >= 5000) unlock('km5');") },
    { id: 'night', kind: 'all', metric: ['info.night', 'S.started', 'S.time'], threshold: [0.8, true, 5], strict: ['>', '===', '>'], sourceCondition: has(hudThresholdSource, "if (info.night > 0.8 && S.started && S.time > 5) unlock('night');") },
    { id: 'bell10', kind: 'gte', metric: 'S.bells', threshold: 10, probes: [9, 10, 11], sourceCondition: has(ringBellSource, "if (S.bells >= 10) unlock('bell10');") },
    { id: 'honk', kind: 'event', metric: 'honks', threshold: 1, sourceCondition: has(honkSource, "unlock('honk');") },
  ];
  return { count: Object.keys(definitions).length, definitions, thresholds: thresholdCases };
}

export function serializeGolden(golden) {
  return `${JSON.stringify(golden, null, 2)}\n`;
}

export async function buildGolden() {
  const sources = await loadSources();
  const util = compileUtil(sources.util);
  const ocean = compileOcean(sources.ocean);
  const world = compileWorld(sources.world, util);
  const createRideRuntime = compileRideFactory(sources.main, sources.bicycle, sources.util);
  const createFishRuntime = compileFishFactory(sources.main, util);

  return {
    schema: 'pelican-bike-reference-vectors/v1',
    provenance: {
      sourceProject: 'claude-opus-5-5-demo/pelican-bike',
      sourceFiles: Object.fromEntries(
        Object.entries(sources).map(([key, text]) => [key, { path: `src/${key}.js`, sha256: sha256(text) }]),
      ),
      execution: {
        directSourceExtraction: [
          'clamp',
          'lerp',
          'damp',
          'smoothstep',
          'mulberry32',
          'solveTwoBone',
          'wavePhases',
          'waveHeight',
          'fbm2',
          'terrainHeight',
          'updateRide',
          'jump',
          'spawnFish',
        ],
        transcribedSourceConditions: ['achievement thresholds'],
        externalParityDependency: 'three@0.186.0 ImprovedNoise',
      },
    },
    numericModel: {
      javascriptNumber: 'IEEE-754 binary64',
      wavePhaseStorage: 'Both binary64 calculation output and app-equivalent Float32Array storage are recorded.',
      rideIntegrator: { fixedDt: RIDE_DT, frames: RIDE_FRAMES, durationSeconds: 10 },
      recommendedTolerance: {
        exact: ['booleans', 'integers', 'gear indices', 'Mulberry32 values when represented as binary64'],
        generalAbs: 1e-12,
        generalRel: 1e-12,
        float32WavePhaseAbs: 2e-6,
        terrainAbs: 1e-9,
        rideAbs: 1e-9,
      },
    },
    primitives: buildPrimitiveVectors(util),
    mulberry32: buildMulberryVectors(util),
    gerstner: buildWaveVectors(ocean),
    terrainHeight: buildTerrainVectors(world),
    solveTwoBone: buildIkVectors(util),
    rideTrajectories: buildRideVectors(createRideRuntime),
    automaticGears: buildGearVectors(createRideRuntime),
    fishRandomSequence: buildFishVectors(createFishRuntime),
    achievements: buildAchievementVectors(sources.main),
  };
}

async function main() {
  const golden = await buildGolden();
  const serialized = serializeGolden(golden);
  await mkdir(dirname(GOLDEN_PATH), { recursive: true });
  await writeFile(GOLDEN_PATH, serialized, 'utf8');
  console.log(`wrote ${GOLDEN_PATH}`);
  console.log(`sha256 ${sha256(serialized)}`);
}

const invokedPath = process.argv[1] ? pathToFileURL(resolve(process.argv[1])).href : '';
if (invokedPath === import.meta.url) {
  main().catch((error) => {
    console.error(error.stack || error);
    process.exitCode = 1;
  });
}
