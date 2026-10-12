import { createHash } from 'node:crypto';
import { createServer } from 'node:http';
import { access, cp, mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { constants as fsConstants } from 'node:fs';
import { basename, dirname, join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { tmpdir } from 'node:os';

const TOOL_DIR = dirname(new URL(import.meta.url).pathname.replace(/^\/(?:([A-Za-z]):)/, '$1:'));
const DEFAULT_SOURCE = 'D:\\workspace\\My\\h5\\claude-opus-5-5-demo\\pelican-bike';
const DEFAULT_TARGET_ROOT = resolve(TOOL_DIR, '..', '..');
const DEFAULT_OUTPUT = join(DEFAULT_TARGET_ROOT, 'generated-assets');
const SOURCE = resolve(process.env.PELICAN_SOURCE || DEFAULT_SOURCE);
const OUTPUT = resolve(process.env.PELICAN_ASSET_OUTPUT || DEFAULT_OUTPUT);
const PAGE_EXPORTER = join(TOOL_DIR, 'page-exporter.js');

const args = new Set(process.argv.slice(2));
const keepTemp = args.has('--keep-temp');

function log(message) {
  process.stdout.write(`[asset-export] ${message}\n`);
}

function pathFromFileUrl(url) {
  return new URL(url).pathname.replace(/^\/(?:([A-Za-z]):)/, '$1:');
}

async function assertFile(path) {
  await access(path, fsConstants.R_OK);
  return path;
}

async function findBrowser() {
  const candidates = [
    process.env.PELICAN_CHROMIUM,
    'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',
    'C:\\Program Files (x86)\\Google\\Chrome\\Application\\chrome.exe',
    'C:\\Program Files\\Microsoft\\Edge\\Application\\msedge.exe',
    'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe',
    process.env.LOCALAPPDATA && join(process.env.LOCALAPPDATA, 'Google', 'Chrome', 'Application', 'chrome.exe'),
    process.env.LOCALAPPDATA && join(process.env.LOCALAPPDATA, 'Microsoft', 'Edge', 'Application', 'msedge.exe'),
  ].filter(Boolean);
  for (const candidate of candidates) {
    try {
      await assertFile(candidate);
      return candidate;
    } catch {}
  }
  throw new Error('No Chromium executable found; set PELICAN_CHROMIUM');
}

async function resolveDependency(name) {
  const candidates = [
    join(SOURCE, 'node_modules', name),
    process.env.PELICAN_DEPS && join(resolve(process.env.PELICAN_DEPS), 'node_modules', name),
    join(TOOL_DIR, '.tmp-deps', 'node_modules', name),
  ].filter(Boolean);
  for (const candidate of candidates) {
    try {
      await assertFile(join(candidate, 'package.json'));
      return candidate;
    } catch {}
  }
  try {
    const url = import.meta.resolve(name);
    const resolvedPath = pathFromFileUrl(url);
    let dir = dirname(resolvedPath);
    while (dir !== dirname(dir)) {
      try {
        await assertFile(join(dir, 'package.json'));
        const pkg = JSON.parse(await readFile(join(dir, 'package.json'), 'utf8'));
        if (pkg.name === name) return dir;
      } catch {}
      dir = dirname(dir);
    }
  } catch {}
  throw new Error(`Dependency ${name} is unavailable. Run npm ci in the source project or set PELICAN_DEPS to a temporary npm prefix.`);
}

async function loadEsbuild(esbuildRoot) {
  const pkg = JSON.parse(await readFile(join(esbuildRoot, 'package.json'), 'utf8'));
  const entry = pkg.module || pkg.main || 'lib/main.js';
  return import(pathToFileURL(join(esbuildRoot, entry)).href);
}

function injectionFooter() {
  return `
;window.__assetExportHook = {
  THREE,
  scene,
  fishGeometry,
  textureFactories: {
    makeRoadTextures: __assetMakeRoadTextures,
    makeFeatherTexture: __assetMakeFeatherTexture,
    makeWickerTexture: __assetMakeWickerTexture,
    makeSpriteTexture: __assetMakeSpriteTexture,
    makeDecalTexture: __assetMakeDecalTexture,
    makeSignTexture: __assetMakeSignTexture,
    makeStripeTexture: __assetMakeStripeTexture,
  },
};
`;
}

function injectionImports() {
  return `
import {
  makeRoadTextures as __assetMakeRoadTextures,
  makeFeatherTexture as __assetMakeFeatherTexture,
  makeWickerTexture as __assetMakeWickerTexture,
  makeSpriteTexture as __assetMakeSpriteTexture,
  makeDecalTexture as __assetMakeDecalTexture,
  makeSignTexture as __assetMakeSignTexture,
  makeStripeTexture as __assetMakeStripeTexture,
} from './textures.js';
`;
}

async function buildTemporaryPage(workDir, esbuildRoot) {
  const { build } = await loadEsbuild(esbuildRoot);
  let main = await readFile(join(SOURCE, 'src', 'main.js'), 'utf8');
  main = injectionImports() + main + injectionFooter();
  const entry = join(workDir, 'main.injected.mjs');
  await writeFile(entry, main);
  const result = await build({
    entryPoints: [entry],
    bundle: true,
    format: 'iife',
    minify: false,
    write: false,
    target: ['es2020'],
    legalComments: 'none',
    absWorkingDir: SOURCE,
    nodePaths: [join(SOURCE, 'node_modules')],
    plugins: [
      {
        name: 'source-relative-injected-entry',
        setup(buildApi) {
          buildApi.onResolve({ filter: /^\.\// }, ({ path, importer }) => {
            if (importer === entry) return { path: join(SOURCE, 'src', path) };
            return null;
          });
        },
      },
    ],
  });
  let js = result.outputFiles[0].text.replace(/<\/script/gi, '<\\/script');
  let html = await readFile(join(SOURCE, 'index.template.html'), 'utf8');
  html = html.replace('<!--OG_IMAGE-->', '').replace('/*APP_JS*/', () => js);
  await writeFile(join(workDir, 'index.html'), html);
}

function mimeType(path) {
  if (path.endsWith('.html')) return 'text/html; charset=utf-8';
  if (path.endsWith('.js') || path.endsWith('.mjs')) return 'text/javascript; charset=utf-8';
  if (path.endsWith('.json')) return 'application/json; charset=utf-8';
  return 'application/octet-stream';
}

async function startServer(root) {
  const server = createServer(async (req, res) => {
    try {
      const pathname = decodeURIComponent(new URL(req.url, 'http://127.0.0.1').pathname);
      const rel = pathname === '/' ? 'index.html' : pathname.replace(/^\/+/, '');
      const path = resolve(root, rel);
      if (!path.startsWith(resolve(root))) throw new Error('Path escape');
      const data = await readFile(path);
      res.writeHead(200, { 'content-type': mimeType(path), 'cache-control': 'no-store' });
      res.end(data);
    } catch (error) {
      res.writeHead(404, { 'content-type': 'text/plain; charset=utf-8' });
      res.end(String(error));
    }
  });
  await new Promise((resolvePromise, reject) => {
    const onError = (error) => reject(error);
    server.once('error', onError);
    server.listen(38080, '127.0.0.1', () => {
      server.off('error', onError);
      resolvePromise();
    });
  });
  const address = server.address();
  return { server, url: `http://127.0.0.1:${address.port}/?q=low&autostart=1&freeze=1&dt=0` };
}

function decodeFile(file) {
  if (file.encoding === 'base64') return Buffer.from(file.data, 'base64');
  if (file.encoding === 'utf8') return Buffer.from(file.data, 'utf8');
  if (file.encoding === 'dataUrl') {
    const match = /^data:[^;,]+(?:;[^;,]+)*;base64,(.*)$/s.exec(file.data);
    if (!match) throw new Error(`Unsupported data URL for ${file.path}`);
    return Buffer.from(match[1], 'base64');
  }
  throw new Error(`Unsupported file encoding ${file.encoding}`);
}

function stableObject(value) {
  if (Array.isArray(value)) return value.map(stableObject);
  if (value && typeof value === 'object') {
    const out = {};
    for (const key of Object.keys(value).sort()) out[key] = stableObject(value[key]);
    return out;
  }
  return value;
}

function stableJson(value) {
  return JSON.stringify(stableObject(value), null, 2) + '\n';
}

async function sha256(buffer) {
  return createHash('sha256').update(buffer).digest('hex');
}

async function writeResult(result) {
  const staging = `${OUTPUT}.staging-${process.pid}`;
  await rm(staging, { recursive: true, force: true });
  await mkdir(staging, { recursive: true });
  const hashes = {};
  for (const file of result.files) {
    const target = join(staging, file.path);
    await mkdir(dirname(target), { recursive: true });
    const data = decodeFile(file);
    await writeFile(target, data);
    hashes[file.path.replace(/\\/g, '/')] = { byteLength: data.byteLength, sha256: await sha256(data) };
  }
  const manifest = result.manifest;
  for (const buffer of manifest.buffers) Object.assign(buffer, hashes[buffer.path]);
  for (const texture of manifest.textures) {
    const raw = hashes[texture.buffer];
    const png = hashes[texture.png];
    texture.sha256 = raw.sha256;
    texture.pngByteLength = png.byteLength;
    texture.pngSha256 = png.sha256;
  }
  manifest.stats.binaryBytes = manifest.buffers.reduce((s, b) => s + b.byteLength, 0);
  manifest.stats.pngBytes = manifest.textures.reduce((s, t) => s + t.pngByteLength, 0);
  manifest.files = Object.entries(hashes).map(([path, meta]) => ({ path, ...meta }));
  const manifestBytes = Buffer.from(stableJson(manifest), 'utf8');
  await writeFile(join(staging, 'manifest.json'), manifestBytes);
  await rm(OUTPUT, { recursive: true, force: true });
  await mkdir(dirname(OUTPUT), { recursive: true });
  await cp(staging, OUTPUT, { recursive: true, force: true });
  await rm(staging, { recursive: true, force: true });
  return manifest;
}

async function main() {
  await assertFile(join(SOURCE, 'src', 'main.js'));
  await assertFile(PAGE_EXPORTER);
  const [esbuildRoot, playwrightRoot, browser] = await Promise.all([
    resolveDependency('esbuild'),
    resolveDependency('playwright-core'),
    findBrowser(),
  ]);
  const playwrightPkg = JSON.parse(await readFile(join(playwrightRoot, 'package.json'), 'utf8'));
  const playwrightEntry = playwrightPkg.main || 'index.js';
  const playwrightModule = await import(pathToFileURL(join(playwrightRoot, playwrightEntry)).href);
  const chromium = playwrightModule.chromium || playwrightModule.default?.chromium;
  if (!chromium) throw new Error(`playwright-core at ${playwrightRoot} did not expose chromium`);
  const workDir = await mkdtemp(join(tmpdir(), 'pelican-asset-export-'));
  let server;
  let browserInstance;
  try {
    log(`source ${SOURCE}`);
    log(`temporary build ${workDir}`);
    await buildTemporaryPage(workDir, esbuildRoot);
    const served = await startServer(workDir);
    server = served.server;
    log(`launching ${basename(browser)}`);
    browserInstance = await chromium.launch({
      executablePath: browser,
      headless: true,
      args: ['--use-angle=swiftshader', '--enable-webgl', '--ignore-gpu-blocklist', '--disable-dev-shm-usage'],
    });
    const page = await browserInstance.newPage({ viewport: { width: 800, height: 600 }, deviceScaleFactor: 1 });
    const pageErrors = [];
    page.on('pageerror', (error) => pageErrors.push(String(error?.stack || error)));
    page.on('console', (message) => {
      if (message.type() === 'error') pageErrors.push(`console: ${message.text()}`);
    });
    await page.goto(served.url, { waitUntil: 'domcontentloaded', timeout: 30_000 });
    await page.waitForFunction(() => window.__pelican && window.__assetExportHook, null, { timeout: 30_000 });
    await page.addScriptTag({ path: PAGE_EXPORTER });
    await page.waitForFunction(() => typeof window.__runPelicanAssetExport === 'function', null, { timeout: 10_000 });
    log('serializing geometry, hierarchy, materials, anchors, and procedural textures');
    const result = await page.evaluate(() => window.__runPelicanAssetExport());
    if (pageErrors.length) log(`browser reported ${pageErrors.length} non-fatal console/page error(s)`);
    const manifest = await writeResult(result);
    log(`wrote ${manifest.stats.assetCount} assets, ${manifest.stats.geometryCount} geometries, ${manifest.stats.textureCount} textures`);
    log(`${manifest.stats.vertexCount} vertices, ${manifest.stats.triangleCount} triangles, ${manifest.stats.binaryBytes} binary bytes`);
    log(`output ${OUTPUT}`);
  } finally {
    if (browserInstance) await browserInstance.close().catch(() => {});
    if (server) await new Promise((resolvePromise) => server.close(resolvePromise));
    if (!keepTemp) await rm(workDir, { recursive: true, force: true });
    else log(`kept temporary build ${workDir}`);
  }
}

main().catch((error) => {
  console.error(error?.stack || error);
  process.exitCode = 1;
});
