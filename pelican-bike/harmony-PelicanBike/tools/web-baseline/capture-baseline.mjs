import { createRequire } from 'node:module';
import { spawnSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import { mkdir, rm, writeFile } from 'node:fs/promises';
import http from 'node:http';
import path from 'node:path';

const SOURCE_DIR = process.env.PELICAN_SOURCE_DIR || 'D:/workspace/My/h5/claude-opus-5-5-demo/pelican-bike';
const OUTPUT_DIR = process.env.PELICAN_BASELINE_DIR || 'D:/workspace/My/harmony/harmony-PelicanBike/docs/web-baseline';
const CHROME = process.env.PELICAN_CHROME || 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const EXTERNAL_BASE_URL = process.env.PELICAN_BASE_URL || '';
const VIEWPORT = { width: 1440, height: 900 };
const COMMON = {
  autostart: '1',
  freeze: '1',
  dt: '0.0166667',
  q: 'high',
  speed: '7.5',
};
const framesForSeconds = (seconds) => Math.round(seconds / Number(COMMON.dt));

const scenarios = [
  { file: '01-day-12-orbit.png', label: 'day(12/orbit)', time: 12, cam: 'orbit', setup: ({ p }) => p.view(2.8, 0.55, 4.5, 37, 0, 0, 0), settleFrames: 6 },
  { file: '02-sunset-17.35-orbit.png', label: 'sunset(17.35/orbit)', time: 17.35, cam: 'orbit', setup: ({ p }) => p.view(2.8, 0.55, 4.5, 37, 0, 0, 0), settleFrames: 6 },
  { file: '03-night-23-orbit.png', label: 'night(23/orbit)', time: 23, cam: 'orbit', setup: ({ p }) => p.view(2.8, 0.55, 4.5, 37, 0, 0, 0), settleFrames: 6 },
  { file: '04-chase.png', label: 'chase', time: 17.35, cam: 'chase', setup: ({ p }) => p.setCamMode('chase', true), settleFrames: 18 },
  { file: '05-side.png', label: 'side', time: 17.35, cam: 'side', setup: ({ p }) => p.setCamMode('side', true), settleFrames: 18 },
  {
    file: '06-cine.png', label: 'cine', time: 17.35, cam: 'cine', settleFrames: framesForSeconds(2),
    setup: ({ p }) => { p.setCamMode('cine', true); p.cine.shot = 0; p.cine.t = 0; },
  },
  { file: '07-pov.png', label: 'pov', time: 17.35, cam: 'pov', setup: ({ p }) => p.setCamMode('pov', true), settleFrames: 12 },
  {
    file: '08-jump.png', label: '跳跃', time: 17.35, cam: 'orbit', settleFrames: framesForSeconds(0.28),
    setup: ({ p }) => { p.view(2.65, 0.72, 4.25, 36, 0, 0.08, 0); p.jump(); },
  },
  {
    file: '09-trick.png', label: '特技', time: 17.35, cam: 'orbit', settleFrames: framesForSeconds(0.65),
    setup: ({ p }) => { p.view(2.65, 0.72, 4.25, 36, 0, 0.08, 0); p.trick(); },
  },
  {
    file: '10-fish-normal-gulp.png', label: '普通鱼吞食', time: 17.35, cam: 'orbit', settleFrames: framesForSeconds(0.08),
    setup: ({ p }) => {
      p.view(2.05, 0.5, 3.25, 32, 0.1, 0.15, 0);
      const source = p.bike.anchors.basket.children.find((node) => node.isMesh && node.geometry?.attributes?.color);
      if (!source) throw new Error('Basket fish mesh unavailable');
      const fish = source.clone();
      fish.material = source.material.clone();
      p.pelican.mouth.add(fish);
      fish.position.set(0.18, -0.01, 0);
      fish.rotation.set(0, Math.PI / 2, 0);
      fish.scale.setScalar(1.25);
      fish.material.color.set('#ffffff');
      fish.material.emissive.set('#1f6b8f');
      fish.material.emissiveIntensity = 0.45;
      p.pelican.gulp();
    },
  },
  {
    file: '11-fish-golden-gulp.png', label: '金鱼吞食', time: 17.35, cam: 'orbit', settleFrames: framesForSeconds(0.08),
    setup: ({ p }) => {
      p.view(2.05, 0.5, 3.25, 32, 0.1, 0.15, 0);
      const source = p.bike.anchors.basket.children.find((node) => node.isMesh && node.geometry?.attributes?.color);
      if (!source) throw new Error('Basket fish mesh unavailable');
      const fish = source.clone();
      fish.material = source.material.clone();
      p.pelican.mouth.add(fish);
      fish.position.set(0.18, -0.01, 0);
      fish.rotation.set(0, Math.PI / 2, 0);
      fish.scale.setScalar(1.25);
      fish.material.color.set('#ffcf3f');
      fish.material.emissive.set('#ff9500');
      fish.material.emissiveIntensity = 0.9;
      p.S.fish = 5;
      p.S.golden = 1;
      p.pelican.gulp();
    },
  },
  {
    file: '12-offshore-jumping-fish.png', label: '远海跃鱼', time: 17.35, cam: 'orbit', settleFrames: framesForSeconds(0.45),
    setup: ({ p }) => { p.view(2.8, 1.45, 5.2, 36, 4.3, -0.3, -19); p.launchJumper(4.2, -19); },
  },
];

function run(command, args, options = {}) {
  const result = spawnSync(command, args, { cwd: SOURCE_DIR, stdio: 'inherit', shell: false, ...options });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`${command} ${args.join(' ')} exited with ${result.status}`);
}

function createStaticServer(root) {
  return http.createServer((request, response) => {
    const url = new URL(request.url, 'http://127.0.0.1');
    const relative = decodeURIComponent(url.pathname) === '/' ? 'index.html' : decodeURIComponent(url.pathname).replace(/^\/+/, '');
    const file = path.resolve(root, relative);
    if (file !== root && !file.startsWith(`${root}${path.sep}`)) {
      response.writeHead(403);
      response.end('forbidden');
      return;
    }
    import('node:fs').then(({ readFile }) => readFile(file, (error, data) => {
      if (error) {
        response.writeHead(404);
        response.end('not found');
        return;
      }
      response.writeHead(200, { 'Content-Type': file.endsWith('.html') ? 'text/html; charset=utf-8' : 'application/octet-stream', 'Cache-Control': 'no-store' });
      response.end(data);
    }));
  });
}

async function main() {
  await mkdir(OUTPUT_DIR, { recursive: true });
  const nodeModules = path.join(SOURCE_DIR, 'node_modules');
  const dist = path.join(SOURCE_DIR, 'dist');
  const hadNodeModules = existsSync(nodeModules);
  const hadDist = existsSync(dist);
  let server;
  let browser;

  try {
    if (!existsSync(path.join(nodeModules, 'playwright-core'))) {
      const npmCli = process.env.PELICAN_NPM_CLI || (process.platform === 'win32' ? 'C:/Program Files/nodejs/node_modules/npm/bin/npm-cli.js' : '/usr/local/lib/node_modules/npm/bin/npm-cli.js');
      run(process.execPath, [npmCli, 'ci', '--registry=https://registry.npmjs.org/', '--replace-registry-host=always', '--fetch-retries=4']);
    }
    if (!EXTERNAL_BASE_URL) run(process.execPath, ['build.mjs']);

    const require = createRequire(import.meta.url);
    const { chromium } = require(path.join(nodeModules, 'playwright-core'));

    let baseUrl = EXTERNAL_BASE_URL;
    if (!baseUrl) {
      server = createStaticServer(path.resolve(dist));
      await new Promise((resolve, reject) => {
        server.once('error', reject);
        server.listen(0, '127.0.0.1', resolve);
      });
      const address = server.address();
      baseUrl = `http://127.0.0.1:${address.port}/`;
    }

    browser = await chromium.launch({
      executablePath: CHROME,
      headless: true,
      args: ['--ignore-gpu-blocklist', '--enable-webgl', '--use-angle=swiftshader', '--disable-dev-shm-usage', '--hide-scrollbars'],
    });

    const manifest = [];
    for (const scenario of scenarios) {
      const context = await browser.newContext({ viewport: VIEWPORT, deviceScaleFactor: 1, locale: 'zh-CN', colorScheme: 'dark', reducedMotion: 'no-preference' });
      try {
        const page = await context.newPage();
        const errors = [];
        page.on('pageerror', (error) => errors.push(`pageerror: ${error.message}`));
        page.on('console', (message) => { if (message.type() === 'error') errors.push(`console: ${message.text()}`); });

        const url = new URL(baseUrl);
        for (const [key, value] of Object.entries(COMMON)) url.searchParams.set(key, value);
        url.searchParams.set('time', String(scenario.time));
        url.searchParams.set('cam', scenario.cam);
        const response = await page.goto(url.toString(), { waitUntil: 'domcontentloaded', timeout: 30_000 });
        if (!response?.ok()) throw new Error(`${scenario.file}: HTTP ${response?.status() ?? 'no response'}`);
        await page.waitForFunction(() => Boolean(window.__pelican && document.body.classList.contains('ready') && document.querySelector('canvas')), null, { timeout: 30_000 });

        const state = await page.evaluate(async ({ label, settleFrames, setupSource }) => {
          const p = window.__pelican;
          p.settings.hour = Number(new URLSearchParams(location.search).get('time'));
          p.settings.timeFlow = false;
          p.settings.autopilot = false;
          p.settings.cruise = 7.5;
          p.S.nextFishAt = 1e9;
          p.S.lastSteer = 1e9;
          document.querySelector('#toasts')?.replaceChildren();
          document.querySelectorAll('.pop').forEach((node) => node.remove());
          const setup = (0, eval)(`(${setupSource})`);
          setup({ p });
          for (let i = 0; i < settleFrames; i++) await new Promise(requestAnimationFrame);
          p.S.paused = true;
          await new Promise(requestAnimationFrame);
          await new Promise((resolve) => setTimeout(resolve, 60));
          return {
            label,
            search: location.search,
            viewport: [innerWidth, innerHeight],
            canvas: [document.querySelector('canvas').width, document.querySelector('canvas').height],
            hour: p.settings.hour,
            cam: document.querySelector('[data-cam].on')?.dataset.cam || null,
            speedMps: p.S.speed,
            speedKmh: p.S.speed * 3.6,
            distance: p.S.distance,
            lane: p.S.lane,
            t: p.S.t,
            airborne: p.S.airborne,
            y: p.S.y,
            vy: p.S.vy,
            trick: p.S.trick,
            trickT: p.S.trickT,
            fishScore: p.S.fish,
            goldenCount: p.S.golden,
            fps: p.fps,
            webgl: p.renderer.capabilities.isWebGL2 ? 'WebGL2' : 'WebGL1',
            bodyClass: document.body.className,
          };
        }, { label: scenario.label, settleFrames: scenario.settleFrames, setupSource: scenario.setup.toString() });

        await page.screenshot({ path: path.join(OUTPUT_DIR, scenario.file), type: 'png', animations: 'allow' });
        manifest.push({ file: scenario.file, ...state, errors });
        console.log(`${scenario.file} | ${scenario.label} | ${state.cam} | t=${state.t.toFixed(3)} | errors=${errors.length}`);
      } finally {
        await context.close();
      }
    }

    await writeFile(path.join(OUTPUT_DIR, 'capture-manifest.json'), `${JSON.stringify({ generatedAt: new Date().toISOString(), baseUrl, viewport: VIEWPORT, commonParams: COMMON, captures: manifest }, null, 2)}\n`, 'utf8');
    console.log(`Wrote ${manifest.length} PNG files and capture-manifest.json to ${OUTPUT_DIR}`);
  } finally {
    if (browser) await browser.close();
    if (server) await new Promise((resolve) => server.close(resolve));
    if (!hadDist && existsSync(dist)) await rm(dist, { recursive: true, force: true });
    if (!hadNodeModules && existsSync(nodeModules)) await rm(nodeModules, { recursive: true, force: true });
  }
}

await main();
