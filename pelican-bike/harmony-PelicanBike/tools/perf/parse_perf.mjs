#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';

const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const DEFAULT_CONFIG = path.join(SCRIPT_DIR, 'perf_config.json');
const PROTOCOL_PREFIX = 'PEL_PERF ';

const METRIC_ALIASES = {
  fps: ['fps'],
  frameCpuMs: ['frameCpuMs', 'frameCpu'],
  frameGpuMs: ['frameGpuMs', 'frameGpu'],
  frameMs: ['frameMs', 'frameTotalMs'],
  drawCalls: ['drawCalls'],
  triangles: ['triangles'],
  heapMiB: ['heapMiB', 'heapMB', 'heap'],
  rssMiB: ['rssMiB', 'rssMB', 'rss'],
  gpuMiB: ['gpuMiB', 'gpuMemoryMiB', 'gpuMemoryMB', 'gpuMemory'],
};

const COUNT_ALIASES = {
  textures: ['textures', 'textureCount'],
  buffers: ['buffers', 'bufferCount'],
  framebuffers: ['framebuffers', 'framebufferCount', 'fbos'],
  renderbuffers: ['renderbuffers', 'renderbufferCount', 'rbos'],
  programs: ['programs', 'programCount'],
  vaos: ['vaos', 'vaoCount'],
  glErrors: ['glErrors', 'glErrorCount'],
  contextLosses: ['contextLosses', 'contextLossCount'],
};

function usage(exitCode = 0) {
  const text = `Usage:
  node parse_perf.mjs --input <hilog.txt> [--output-json report.json] [--output-md report.md]
                     [--config perf_config.json] [--quality high] [--scenario soak10m]
                     [--source device|sample] [--strict]
  node parse_perf.mjs --self-test

The parser accepts arbitrary hilog prefixes and extracts each line containing:
  PEL_PERF {"v":1,...}
`;
  (exitCode === 0 ? console.log : console.error)(text);
  process.exit(exitCode);
}

function parseArgs(argv) {
  const out = { strict: false, selfTest: false };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '--help' || arg === '-h') usage(0);
    if (arg === '--strict') { out.strict = true; continue; }
    if (arg === '--self-test') { out.selfTest = true; continue; }
    if (!arg.startsWith('--')) throw new Error(`Unexpected argument: ${arg}`);
    const key = arg.slice(2).replace(/-([a-z])/g, (_, c) => c.toUpperCase());
    if (i + 1 >= argv.length || argv[i + 1].startsWith('--')) throw new Error(`Missing value for ${arg}`);
    out[key] = argv[++i];
  }
  return out;
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, 'utf8'));
}

function finiteNumber(value) {
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  if (typeof value === 'string' && value.trim() !== '') {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) return parsed;
  }
  return undefined;
}

function firstNumber(object, keys) {
  for (const key of keys) {
    const value = finiteNumber(object?.[key]);
    if (value !== undefined) return value;
  }
  return undefined;
}

function percentile(values, quantile) {
  if (!values.length) return null;
  const sorted = [...values].sort((a, b) => a - b);
  const index = (sorted.length - 1) * quantile;
  const lo = Math.floor(index);
  const hi = Math.ceil(index);
  if (lo === hi) return sorted[lo];
  const weight = index - lo;
  return sorted[lo] * (1 - weight) + sorted[hi] * weight;
}

function round(value, digits = 3) {
  if (value === null || value === undefined || !Number.isFinite(value)) return null;
  const factor = 10 ** digits;
  return Math.round(value * factor) / factor;
}

function linearSlopePerMinute(points) {
  const valid = points.filter((point) => Number.isFinite(point.t) && Number.isFinite(point.v));
  if (valid.length < 2) return null;
  const t0 = valid[0].t;
  const xs = valid.map((point) => (point.t - t0) / 60000);
  const ys = valid.map((point) => point.v);
  const meanX = xs.reduce((sum, value) => sum + value, 0) / xs.length;
  const meanY = ys.reduce((sum, value) => sum + value, 0) / ys.length;
  let numerator = 0;
  let denominator = 0;
  for (let i = 0; i < xs.length; i += 1) {
    numerator += (xs[i] - meanX) * (ys[i] - meanY);
    denominator += (xs[i] - meanX) ** 2;
  }
  return denominator > 0 ? numerator / denominator : null;
}

function stat(values) {
  if (!values.length) return { count: 0, min: null, p05: null, median: null, p95: null, p99: null, max: null, mean: null };
  return {
    count: values.length,
    min: round(Math.min(...values)),
    p05: round(percentile(values, 0.05)),
    median: round(percentile(values, 0.50)),
    p95: round(percentile(values, 0.95)),
    p99: round(percentile(values, 0.99)),
    max: round(Math.max(...values)),
    mean: round(values.reduce((sum, value) => sum + value, 0) / values.length),
  };
}

function firstAndLast(points, trimRatio = 0.10) {
  if (!points.length) return { first: null, last: null, delta: null };
  const count = Math.max(1, Math.floor(points.length * trimRatio));
  const firstValues = points.slice(0, count).map((point) => point.v);
  const lastValues = points.slice(-count).map((point) => point.v);
  const first = percentile(firstValues, 0.50);
  const last = percentile(lastValues, 0.50);
  return { first: round(first), last: round(last), delta: round(last - first) };
}

function parseLog(text, strict = false) {
  const records = [];
  const parseErrors = [];
  const lines = text.split(/\r?\n/);
  for (let index = 0; index < lines.length; index += 1) {
    const line = lines[index];
    let cursor = line.indexOf(PROTOCOL_PREFIX);
    while (cursor !== -1) {
      const raw = line.slice(cursor + PROTOCOL_PREFIX.length).trim();
      try {
        const value = JSON.parse(raw);
        if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('payload is not an object');
        if (value.v !== 1) throw new Error(`unsupported protocol version ${String(value.v)}`);
        records.push({ ...value, __line: index + 1, __raw: line });
      } catch (error) {
        parseErrors.push({ line: index + 1, message: error.message, raw });
      }
      break;
    }
  }
  if (strict && parseErrors.length) throw new Error(`Found ${parseErrors.length} malformed PEL_PERF line(s)`);
  return { records, parseErrors, totalLines: lines.length };
}

function normalizeRecords(records) {
  let fallbackTime = 0;
  return records.map((record, index) => {
    const explicitTime = firstNumber(record, ['tsMs', 'elapsedMs']);
    const time = explicitTime ?? fallbackTime;
    fallbackTime = time + 1000;
    const gpu = record.gpu && typeof record.gpu === 'object' ? record.gpu : {};
    const resources = record.resources && typeof record.resources === 'object' ? record.resources : {};
    const normalized = {
      raw: record,
      index,
      line: record.__line,
      v: record.v,
      event: typeof record.event === 'string' ? record.event : 'sample',
      runId: typeof record.runId === 'string' ? record.runId : undefined,
      scenario: typeof record.scenario === 'string' ? record.scenario : undefined,
      quality: typeof record.quality === 'string' ? record.quality : undefined,
      phase: typeof record.phase === 'string' ? record.phase : undefined,
      tsMs: time,
      frame: firstNumber(record, ['frame']),
      distanceM: firstNumber(record, ['distanceM', 'distance']),
      hour: firstNumber(record, ['hour']),
      surfaceWidth: firstNumber(record, ['surfaceWidth', 'width']),
      surfaceHeight: firstNumber(record, ['surfaceHeight', 'height']),
      checks: record.checks && typeof record.checks === 'object' ? record.checks : undefined,
      result: typeof record.result === 'string' ? record.result.toLowerCase() : undefined,
      reason: typeof record.reason === 'string' ? record.reason : undefined,
    };
    for (const [metric, aliases] of Object.entries(METRIC_ALIASES)) normalized[metric] = firstNumber(record, aliases);
    for (const [metric, aliases] of Object.entries(COUNT_ALIASES)) normalized[metric] = firstNumber(resources, aliases) ?? firstNumber(gpu, aliases) ?? firstNumber(record, aliases);
    return normalized;
  });
}

function collectValues(samples, key) {
  return samples.map((sample) => sample[key]).filter(Number.isFinite);
}

function pointSeries(samples, key) {
  return samples.filter((sample) => Number.isFinite(sample[key])).map((sample) => ({ t: sample.tsMs, v: sample[key] }));
}

function resourceSummary(samples, key) {
  const points = pointSeries(samples, key);
  const edges = firstAndLast(points);
  return { ...stat(points.map((point) => point.v)), ...edges, growthPerMin: round(linearSlopePerMinute(points)) };
}

function makeCheck(id, status, actual, expected, detail = '') {
  return { id, status, actual, expected, detail };
}

function evaluate(records, config, options) {
  const normalized = normalizeRecords(records);
  const samples = normalized.filter((record) => record.event === 'sample');
  const begin = normalized.find((record) => record.event === 'begin');
  const end = [...normalized].reverse().find((record) => record.event === 'end');
  const hostEnd = [...normalized].reverse().find((record) => record.event === 'host_end');
  const quality = options.quality || begin?.quality || samples.find((sample) => sample.quality)?.quality || 'high';
  const scenario = options.scenario || begin?.scenario || end?.scenario || samples.find((sample) => sample.scenario)?.scenario || hostEnd?.scenario || 'unknown';
  const profile = config.qualityProfiles[quality];
  if (!profile) throw new Error(`Unknown quality profile: ${quality}`);
  const thresholds = config.thresholds;
  const targetFps = profile.targetFps;
  const minFps = profile.minimumFps;
  const frameBudgetMs = 1000 / targetFps;
  const fpsValues = collectValues(samples, 'fps');
  const cpuValues = collectValues(samples, 'frameCpuMs');
  const gpuValues = collectValues(samples, 'frameGpuMs');
  const frameValues = samples.map((sample) => Number.isFinite(sample.frameMs) ? sample.frameMs : (Number.isFinite(sample.frameCpuMs) && Number.isFinite(sample.frameGpuMs) ? Math.max(sample.frameCpuMs, sample.frameGpuMs) : undefined)).filter(Number.isFinite);
  const durationMs = samples.length > 1 ? samples[samples.length - 1].tsMs - samples[0].tsMs : 0;
  const belowMinimum = fpsValues.filter((value) => value < minFps).length;
  const hitches = frameValues.filter((value) => value > frameBudgetMs * thresholds.frameTotalMs.hitchMultiplier).length;
  const stats = {
    sampleCount: samples.length,
    durationMs: round(durationMs, 0),
    durationSeconds: round(durationMs / 1000),
    fps: stat(fpsValues),
    frameCpuMs: stat(cpuValues),
    frameGpuMs: stat(gpuValues),
    frameMs: stat(frameValues),
    drawCalls: stat(collectValues(samples, 'drawCalls')),
    triangles: stat(collectValues(samples, 'triangles')),
    heapMiB: resourceSummary(samples, 'heapMiB'),
    rssMiB: resourceSummary(samples, 'rssMiB'),
    gpuMiB: resourceSummary(samples, 'gpuMiB'),
    resources: {},
    belowMinimumFpsCount: belowMinimum,
    belowMinimumFpsRatio: fpsValues.length ? round(belowMinimum / fpsValues.length, 5) : null,
    hitchCount: hitches,
    hitchRatio: frameValues.length ? round(hitches / frameValues.length, 5) : null,
  };
  for (const key of ['textures', 'buffers', 'framebuffers', 'renderbuffers', 'programs', 'vaos', 'glErrors', 'contextLosses']) stats.resources[key] = resourceSummary(samples, key);

  const checks = [];
  const addNumericMax = (id, value, max, unit = '') => {
    if (value === null || value === undefined) checks.push(makeCheck(id, 'SKIP', value, `<= ${max}${unit}`, 'metric absent'));
    else checks.push(makeCheck(id, value <= max ? 'PASS' : 'FAIL', value, `<= ${max}${unit}`));
  };
  const addNumericMin = (id, value, min, unit = '') => {
    if (value === null || value === undefined) checks.push(makeCheck(id, 'SKIP', value, `>= ${min}${unit}`, 'metric absent'));
    else checks.push(makeCheck(id, value >= min ? 'PASS' : 'FAIL', value, `>= ${min}${unit}`));
  };

  checks.push(makeCheck('sample_count', samples.length >= thresholds.minimumSamples ? 'PASS' : 'FAIL', samples.length, `>= ${thresholds.minimumSamples}`));
  addNumericMin('fps_median', stats.fps.median, targetFps * thresholds.fps.medianRatioMin, ' fps');
  addNumericMin('fps_p05', stats.fps.p05, targetFps * thresholds.fps.p05RatioMin, ' fps');
  addNumericMax('fps_below_minimum_ratio', stats.belowMinimumFpsRatio, thresholds.fps.belowMinimumRatioMax);
  addNumericMax('frame_cpu_p95', stats.frameCpuMs.p95, thresholds.frameCpuMs.p95MaxByQuality[quality], ' ms');
  addNumericMax('frame_gpu_p95', stats.frameGpuMs.p95, thresholds.frameGpuMs.p95MaxByQuality[quality], ' ms');
  addNumericMax('frame_total_p99', stats.frameMs.p99, frameBudgetMs * thresholds.frameTotalMs.p99BudgetMultiplier, ' ms');
  addNumericMax('hitch_ratio', stats.hitchRatio, thresholds.frameTotalMs.hitchRatioMax);
  addNumericMax('draw_calls_max', stats.drawCalls.max, thresholds.drawCalls.maxByQuality[quality]);
  addNumericMax('triangles_max', stats.triangles.max, thresholds.triangles.maxByQuality[quality]);
  addNumericMax('heap_max', stats.heapMiB.max, thresholds.heap.maxMiB, ' MiB');
  addNumericMax('heap_growth_per_min', stats.heapMiB.growthPerMin, thresholds.heap.growthMiBPerMinMax, ' MiB/min');
  addNumericMax('heap_net_growth', stats.heapMiB.delta, thresholds.heap.netGrowthMiBMax, ' MiB');
  addNumericMax('rss_max', stats.rssMiB.max, thresholds.rss.maxMiB, ' MiB');
  addNumericMax('rss_growth_per_min', stats.rssMiB.growthPerMin, thresholds.rss.growthMiBPerMinMax, ' MiB/min');
  addNumericMax('rss_net_growth', stats.rssMiB.delta, thresholds.rss.netGrowthMiBMax, ' MiB');
  addNumericMax('gpu_memory_max', stats.gpuMiB.max, thresholds.gpuMemory.maxMiB, ' MiB');
  addNumericMax('gpu_memory_growth_per_min', stats.gpuMiB.growthPerMin, thresholds.gpuMemory.growthMiBPerMinMax, ' MiB/min');
  addNumericMax('gpu_memory_net_growth', stats.gpuMiB.delta, thresholds.gpuMemory.netGrowthMiBMax, ' MiB');
  for (const [key, maxGrowth] of Object.entries({
    textures: thresholds.resourceGrowth.texturesMax,
    buffers: thresholds.resourceGrowth.buffersMax,
    framebuffers: thresholds.resourceGrowth.framebuffersMax,
    renderbuffers: thresholds.resourceGrowth.renderbuffersMax,
    programs: thresholds.resourceGrowth.programsMax,
    vaos: thresholds.resourceGrowth.vaosMax,
  })) addNumericMax(`${key}_growth`, stats.resources[key].delta, maxGrowth);
  addNumericMax('gl_errors', stats.resources.glErrors.max, thresholds.errors.glErrorsMax);
  addNumericMax('context_losses', stats.resources.contextLosses.max, thresholds.errors.contextLossesMax);

  const endRequired = thresholds.scenario.requiredEndEvent;
  checks.push(makeCheck('end_event', !endRequired || Boolean(end) ? 'PASS' : 'FAIL', end?.result ?? null, 'PEL_PERF end event'));
  if (end?.result) checks.push(makeCheck('engine_result', end.result === 'pass' ? 'PASS' : 'FAIL', end.result, 'pass', end.reason || ''));
  const engineChecks = end?.checks || {};
  for (const [name, value] of Object.entries(engineChecks)) {
    const passed = value === true || value === 'pass' || value === 'PASS' || (typeof value === 'number' && value > 0);
    checks.push(makeCheck(`engine_${name}`, passed ? 'PASS' : 'FAIL', value, 'truthy/pass'));
  }
  const hostChecks = hostEnd?.checks || {};
  for (const [name, value] of Object.entries(hostChecks)) {
    if (typeof value !== 'boolean' && typeof value !== 'string') continue;
    const passed = value === true || value === 'pass' || value === 'PASS';
    checks.push(makeCheck(`host_${name}`, passed ? 'PASS' : 'FAIL', value, 'true/pass'));
  }

  const requiredGroups = thresholds.scenario.requiredChecks[scenario] || [];
  const groupMatchers = {
    sample_count: ['sample_count'],
    fps: ['fps_median', 'fps_p05', 'fps_below_minimum_ratio'],
    frame_cpu: ['frame_cpu_p95'],
    frame_gpu: ['frame_gpu_p95'],
    frame_time: ['frame_total_p99', 'hitch_ratio'],
    heap: ['heap_max', 'heap_growth_per_min', 'heap_net_growth'],
    gpu_memory: ['gpu_memory_max', 'gpu_memory_growth_per_min', 'gpu_memory_net_growth'],
    resources: ['textures_growth', 'buffers_growth', 'framebuffers_growth', 'renderbuffers_growth', 'programs_growth', 'vaos_growth'],
    errors: ['gl_errors', 'context_losses'],
  };
  const checkById = new Map(checks.map((check) => [check.id, check]));
  for (const group of requiredGroups) {
    const ids = groupMatchers[group];
    if (ids) {
      const absent = ids.filter((id) => !checkById.has(id) || checkById.get(id).status === 'SKIP');
      if (absent.length) checks.push(makeCheck(`required_${group}`, 'FAIL', absent.join(', '), 'all metrics present', 'required metric group incomplete'));
    } else {
      const directId = `engine_${group}`;
      const aliases = [group];
      if (group === 'resources') aliases.push('resource_stable');
      if (group === 'errors') aliases.push('no_errors');
      if (group === 'finite_state') aliases.push('finite');
      const present = aliases.some((name) => checkById.has(`engine_${name}`) || (end?.checks && Object.hasOwn(end.checks, name)));
      if (!present) checks.push(makeCheck(`required_${group}`, 'FAIL', null, 'engine end.checks entry', 'scenario-specific engine completion check absent; host actions alone cannot prove renderer recovery'));
    }
  }

  const failed = checks.filter((check) => check.status === 'FAIL');
  const skipped = checks.filter((check) => check.status === 'SKIP');
  const overall = failed.length ? 'FAIL' : (skipped.length ? 'INCOMPLETE' : 'PASS');
  return {
    schemaVersion: 1,
    generatedAt: new Date().toISOString(),
    source: options.source || 'unknown',
    synthetic: (options.source || '').toLowerCase() === 'sample',
    deviceSourceLabel: (options.source || '').toLowerCase() === 'device',
    deviceResultClaimed: (options.source || '').toLowerCase() === 'device' && Boolean(begin) && Boolean(end),
    run: { runId: begin?.runId || end?.runId || samples[0]?.runId || hostEnd?.runId || null, scenario, quality, targetFps, minimumFps: minFps, beginEvent: begin?.raw || null, endEvent: end?.raw || null, hostEndEvent: hostEnd?.raw || null },
    parse: options.parse,
    stats,
    checks,
    summary: { overall, passCount: checks.filter((check) => check.status === 'PASS').length, failCount: failed.length, skipCount: skipped.length },
  };
}

function markdown(report) {
  const note = report.synthetic
    ? '> 注意：本报告来自样例日志，仅验证采集协议、解析器、阈值与报告链路；不是设备实测结果。'
    : report.deviceResultClaimed
      ? '> 数据源标记为 device，且存在 engine begin/end；仍须与原始 hilog、设备标识和伴随诊断文件一起保存。'
      : report.deviceSourceLabel
        ? '> 数据源虽标记为 device，但缺少完整 engine begin/end，不能引用为设备通过结果。'
        : '> 数据源未标记为 device，不得引用为真机性能结论。';
  const s = report.stats;
  const lines = [
    '# Pelican Bike 性能稳定性报告',
    '', note, '',
    `- 结论：**${report.summary.overall}**`,
    `- 场景：\`${report.run.scenario}\``,
    `- 画质：\`${report.run.quality}\`（目标 ${report.run.targetFps} FPS）`,
    `- 样本：${s.sampleCount}，覆盖 ${s.durationSeconds ?? 0} 秒`,
    `- 来源：\`${report.source}\`${report.synthetic ? '（synthetic）' : ''}`,
    '',
    '## 核心统计', '',
    '| 指标 | p05 | median | p95 | p99 | max |',
    '| --- | ---: | ---: | ---: | ---: | ---: |',
    `| FPS | ${s.fps.p05 ?? '-'} | ${s.fps.median ?? '-'} | ${s.fps.p95 ?? '-'} | ${s.fps.p99 ?? '-'} | ${s.fps.max ?? '-'} |`,
    `| Frame CPU ms | ${s.frameCpuMs.p05 ?? '-'} | ${s.frameCpuMs.median ?? '-'} | ${s.frameCpuMs.p95 ?? '-'} | ${s.frameCpuMs.p99 ?? '-'} | ${s.frameCpuMs.max ?? '-'} |`,
    `| Frame GPU ms | ${s.frameGpuMs.p05 ?? '-'} | ${s.frameGpuMs.median ?? '-'} | ${s.frameGpuMs.p95 ?? '-'} | ${s.frameGpuMs.p99 ?? '-'} | ${s.frameGpuMs.max ?? '-'} |`,
    `| Frame total ms | ${s.frameMs.p05 ?? '-'} | ${s.frameMs.median ?? '-'} | ${s.frameMs.p95 ?? '-'} | ${s.frameMs.p99 ?? '-'} | ${s.frameMs.max ?? '-'} |`,
    `| Draw calls | ${s.drawCalls.p05 ?? '-'} | ${s.drawCalls.median ?? '-'} | ${s.drawCalls.p95 ?? '-'} | ${s.drawCalls.p99 ?? '-'} | ${s.drawCalls.max ?? '-'} |`,
    `| Triangles | ${s.triangles.p05 ?? '-'} | ${s.triangles.median ?? '-'} | ${s.triangles.p95 ?? '-'} | ${s.triangles.p99 ?? '-'} | ${s.triangles.max ?? '-'} |`,
    '',
    '## 内存与资源趋势', '',
    '| 指标 | 首段中位数 | 末段中位数 | 净增长 | 线性趋势/分钟 | 峰值 |',
    '| --- | ---: | ---: | ---: | ---: | ---: |',
    `| Heap MiB | ${s.heapMiB.first ?? '-'} | ${s.heapMiB.last ?? '-'} | ${s.heapMiB.delta ?? '-'} | ${s.heapMiB.growthPerMin ?? '-'} | ${s.heapMiB.max ?? '-'} |`,
    `| RSS MiB | ${s.rssMiB.first ?? '-'} | ${s.rssMiB.last ?? '-'} | ${s.rssMiB.delta ?? '-'} | ${s.rssMiB.growthPerMin ?? '-'} | ${s.rssMiB.max ?? '-'} |`,
    `| GPU MiB | ${s.gpuMiB.first ?? '-'} | ${s.gpuMiB.last ?? '-'} | ${s.gpuMiB.delta ?? '-'} | ${s.gpuMiB.growthPerMin ?? '-'} | ${s.gpuMiB.max ?? '-'} |`,
  ];
  for (const [key, value] of Object.entries(s.resources)) lines.push(`| ${key} | ${value.first ?? '-'} | ${value.last ?? '-'} | ${value.delta ?? '-'} | ${value.growthPerMin ?? '-'} | ${value.max ?? '-'} |`);
  lines.push('', '## 判定', '', '| 状态 | 检查 | 实际值 | 阈值/期望 | 说明 |', '| --- | --- | --- | --- | --- |');
  for (const check of report.checks) lines.push(`| ${check.status} | \`${check.id}\` | ${check.actual ?? '-'} | ${check.expected ?? '-'} | ${check.detail || ''} |`);
  if (report.parse.parseErrors?.length) {
    lines.push('', '## 解析错误', '');
    for (const error of report.parse.parseErrors) lines.push(`- 第 ${error.line} 行：${error.message}`);
  }
  lines.push('', '## 口径', '', '- `PEL_PERF` 为主引擎自报；外部 HDC/hidumper 数据应由采样脚本转写为同协议的 `event="sample"` 或保留在伴随原始文件中。', '- `INCOMPLETE` 表示没有失败项，但缺少非当前场景必需的指标；它不是 PASS。', '- 只有来源标为 `device` 且保留原始 hilog/诊断文件的报告，才可作为设备结果。', '');
  return `${lines.join('\n')}\n`;
}

function ensureParent(filePath) {
  fs.mkdirSync(path.dirname(path.resolve(filePath)), { recursive: true });
}

function selfTest() {
  const samplePath = path.join(SCRIPT_DIR, 'sample_hilog.txt');
  if (!fs.existsSync(samplePath)) throw new Error(`Missing self-test fixture: ${samplePath}`);
  const config = readJson(DEFAULT_CONFIG);
  const parsed = parseLog(fs.readFileSync(samplePath, 'utf8'), true);
  const report = evaluate(parsed.records, config, { quality: 'high', scenario: 'soak10m', source: 'sample', parse: { ...parsed, records: undefined } });
  if (parsed.records.length < 20) throw new Error('Self-test fixture did not produce enough records');
  if (report.summary.overall !== 'PASS') {
    const failed = report.checks.filter((check) => check.status === 'FAIL').map((check) => check.id).join(', ');
    throw new Error(`Self-test expected PASS but got ${report.summary.overall}: ${failed}`);
  }
  if (!report.synthetic || report.deviceSourceLabel || report.deviceResultClaimed) throw new Error('Self-test source labelling is unsafe');
  console.log(`self-test PASS: ${parsed.records.length} records, ${report.stats.sampleCount} samples, overall=${report.summary.overall}`);
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.selfTest) { selfTest(); return; }
  if (!args.input) usage(2);
  const configPath = path.resolve(args.config || DEFAULT_CONFIG);
  const inputPath = path.resolve(args.input);
  const config = readJson(configPath);
  const parsed = parseLog(fs.readFileSync(inputPath, 'utf8'), args.strict);
  if (!parsed.records.length) throw new Error(`No ${PROTOCOL_PREFIX.trim()} records found in ${inputPath}`);
  const parseMeta = { totalLines: parsed.totalLines, recordCount: parsed.records.length, parseErrors: parsed.parseErrors };
  const report = evaluate(parsed.records, config, { quality: args.quality, scenario: args.scenario, source: args.source || 'unknown', parse: parseMeta });
  const jsonText = `${JSON.stringify(report, null, 2)}\n`;
  const markdownText = markdown(report);
  if (args.outputJson) { ensureParent(args.outputJson); fs.writeFileSync(args.outputJson, jsonText); }
  if (args.outputMd) { ensureParent(args.outputMd); fs.writeFileSync(args.outputMd, markdownText); }
  if (!args.outputJson && !args.outputMd) process.stdout.write(jsonText);
  else console.log(`report ${report.summary.overall}: ${parsed.records.length} records -> ${args.outputJson || '-'}, ${args.outputMd || '-'}`);
  if (report.summary.overall === 'FAIL') process.exitCode = 1;
  else if (args.strict && report.summary.overall !== 'PASS') process.exitCode = 2;
}

try {
  main();
} catch (error) {
  console.error(`parse_perf: ${error.message}`);
  process.exitCode = 2;
}
