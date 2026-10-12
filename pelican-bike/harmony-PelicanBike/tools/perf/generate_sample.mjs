#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const output = process.argv[2] ? path.resolve(process.argv[2]) : path.join(scriptDir, 'sample_hilog.txt');
const lines = [
  '10-04 12:00:00.000  4210  4277 I A0f00/PelicanBike com.example.pelican I boot complete',
  '10-04 12:00:00.010  4210  4277 I A0f00/PelicanBike com.example.pelican I PEL_PERF ' + JSON.stringify({
    v: 1,
    event: 'begin',
    runId: 'SAMPLE-NOT-DEVICE-001',
    scenario: 'soak10m',
    quality: 'high',
    tsMs: 0,
    synthetic: true,
    device: { model: 'SAMPLE', width: 1320, height: 2856 },
  }),
];

for (let i = 0; i < 60; i += 1) {
  const tsMs = i * 10000;
  const fps = 58.8 + Math.sin(i * 0.47) * 0.7 + (i % 17 === 0 ? -1.0 : 0);
  const frameCpuMs = 7.1 + Math.sin(i * 0.31) * 0.6;
  const frameGpuMs = 11.0 + Math.cos(i * 0.29) * 0.8;
  const frameMs = Math.max(frameCpuMs, frameGpuMs) + 0.5;
  const heapMiB = 94.0 + i * 0.018 + Math.sin(i * 0.3) * 0.4;
  const rssMiB = 286.0 + i * 0.06 + Math.cos(i * 0.2) * 0.8;
  const gpuMiB = 145.0 + i * 0.025 + Math.sin(i * 0.17) * 0.6;
  const record = {
    v: 1,
    event: 'sample',
    runId: 'SAMPLE-NOT-DEVICE-001',
    scenario: 'soak10m',
    quality: 'high',
    tsMs,
    frame: i * 600,
    fps: Number(fps.toFixed(3)),
    frameCpuMs: Number(frameCpuMs.toFixed(3)),
    frameGpuMs: Number(frameGpuMs.toFixed(3)),
    frameMs: Number(frameMs.toFixed(3)),
    drawCalls: 182 + (i % 5),
    triangles: 612000 + (i % 7) * 1800,
    heapMiB: Number(heapMiB.toFixed(3)),
    rssMiB: Number(rssMiB.toFixed(3)),
    gpuMiB: Number(gpuMiB.toFixed(3)),
    distanceM: Number((i * 75.1).toFixed(3)),
    hour: Number(((17.35 + i * 0.4) % 24).toFixed(3)),
    surfaceWidth: 1122,
    surfaceHeight: 2428,
    resources: {
      textures: 34,
      buffers: 168 + (i >= 40 ? 1 : 0),
      framebuffers: 9,
      renderbuffers: 4,
      programs: 18,
      vaos: 71,
      glErrors: 0,
      contextLosses: 0,
    },
  };
  lines.push(`10-04 12:${String(Math.floor(tsMs / 60000)).padStart(2, '0')}:${String(Math.floor((tsMs % 60000) / 1000)).padStart(2, '0')}.000  4210  4277 I A0f00/PelicanBike com.example.pelican I PEL_PERF ${JSON.stringify(record)}`);
  if (i === 18) lines.push('10-04 12:03:01.000  4210  4277 I A0f00/Unrelated com.example.pelican I unrelated log line');
}

lines.push('10-04 12:10:00.000  4210  4277 I A0f00/PelicanBike com.example.pelican I PEL_PERF ' + JSON.stringify({
  v: 1,
  event: 'end',
  runId: 'SAMPLE-NOT-DEVICE-001',
  scenario: 'soak10m',
  quality: 'high',
  tsMs: 600000,
  result: 'pass',
  checks: {
    finite_state: true,
    resources: true,
    errors: true,
  },
  synthetic: true,
}));
lines.push('10-04 12:10:00.100  4210  4277 I A0f00/PelicanBike com.example.pelican I sample finished; no device claim');

fs.mkdirSync(path.dirname(output), { recursive: true });
fs.writeFileSync(output, `${lines.join('\n')}\n`);
console.log(`wrote synthetic fixture: ${output}`);
