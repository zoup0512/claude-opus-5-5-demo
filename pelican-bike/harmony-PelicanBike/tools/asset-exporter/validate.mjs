import { createHash } from 'node:crypto';
import { access, readFile } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';

const TOOL_DIR = dirname(new URL(import.meta.url).pathname.replace(/^\/(?:([A-Za-z]):)/, '$1:'));
const DEFAULT_ROOT = resolve(TOOL_DIR, '..', '..', 'generated-assets');
const ROOT = resolve(process.env.PELICAN_ASSET_OUTPUT || process.argv[2] || DEFAULT_ROOT);
const MANIFEST_PATH = join(ROOT, 'manifest.json');
const failures = [];
const warnings = [];
const fileCache = new Map();

function fail(message) {
  failures.push(message);
}

function assert(condition, message) {
  if (!condition) fail(message);
}

async function getFile(relPath) {
  const normalized = relPath.replace(/\\/g, '/');
  if (!fileCache.has(normalized)) fileCache.set(normalized, readFile(join(ROOT, normalized)));
  return fileCache.get(normalized);
}

function sha256(data) {
  return createHash('sha256').update(data).digest('hex');
}

function componentSize(type) {
  if (type === 'float32' || type === 'uint32') return 4;
  throw new Error(`Unsupported componentType ${type}`);
}

async function validateSlice(label, ref, expectedFileLengths) {
  assert(ref && typeof ref === 'object', `${label}: missing reference`);
  if (!ref || typeof ref !== 'object') return null;
  assert(typeof ref.buffer === 'string' && ref.buffer, `${label}: buffer path missing`);
  assert(Number.isInteger(ref.byteOffset) && ref.byteOffset >= 0, `${label}: invalid byteOffset`);
  assert(Number.isInteger(ref.byteLength) && ref.byteLength >= 0, `${label}: invalid byteLength`);
  assert(Number.isInteger(ref.count) && ref.count >= 0, `${label}: invalid count`);
  assert(Number.isInteger(ref.itemSize) && ref.itemSize > 0, `${label}: invalid itemSize`);
  const size = componentSize(ref.componentType);
  assert(ref.byteLength === ref.count * ref.itemSize * size, `${label}: byteLength does not match count/itemSize/type`);
  assert(ref.byteOffset % size === 0, `${label}: unaligned byteOffset`);
  let data;
  try {
    data = await getFile(ref.buffer);
  } catch (error) {
    fail(`${label}: cannot read ${ref.buffer}: ${error.message}`);
    return null;
  }
  if (expectedFileLengths.has(ref.buffer)) assert(data.byteLength === expectedFileLengths.get(ref.buffer), `${label}: ${ref.buffer} size mismatch`);
  assert(ref.byteOffset + ref.byteLength <= data.byteLength, `${label}: slice exceeds ${ref.buffer}`);
  if (ref.byteOffset + ref.byteLength > data.byteLength) return null;
  return { data, view: new DataView(data.buffer, data.byteOffset + ref.byteOffset, ref.byteLength), size };
}

async function validateFloatRef(label, ref, expectedFileLengths, { finite = true, min = -Infinity, max = Infinity } = {}) {
  const slice = await validateSlice(label, ref, expectedFileLengths);
  if (!slice || ref.componentType !== 'float32') {
    if (ref?.componentType !== 'float32') fail(`${label}: expected float32`);
    return null;
  }
  let observedMin = Infinity;
  let observedMax = -Infinity;
  for (let i = 0; i < ref.count * ref.itemSize; i++) {
    const value = slice.view.getFloat32(i * 4, true);
    if (finite && !Number.isFinite(value)) fail(`${label}: non-finite value at component ${i}`);
    if (value < min || value > max) fail(`${label}: value ${value} outside [${min}, ${max}] at component ${i}`);
    observedMin = Math.min(observedMin, value);
    observedMax = Math.max(observedMax, value);
  }
  return { observedMin, observedMax };
}

async function validateIndex(label, ref, expectedFileLengths, vertexCount) {
  const slice = await validateSlice(label, ref, expectedFileLengths);
  if (!slice || ref.componentType !== 'uint32') {
    if (ref?.componentType !== 'uint32') fail(`${label}: expected uint32`);
    return;
  }
  for (let i = 0; i < ref.count; i++) {
    const value = slice.view.getUint32(i * 4, true);
    if (value >= vertexCount) fail(`${label}: index ${value} >= vertexCount ${vertexCount} at ${i}`);
  }
}

function validateTransform(label, transform) {
  for (const [name, expected] of [['position', 3], ['quaternion', 4], ['scale', 3]]) {
    const values = transform?.[name];
    assert(Array.isArray(values) && values.length === expected, `${label}: ${name} must contain ${expected} numbers`);
    if (Array.isArray(values)) values.forEach((v, i) => assert(Number.isFinite(v), `${label}: ${name}[${i}] is not finite`));
  }
  if (Array.isArray(transform?.quaternion)) {
    const q = transform.quaternion;
    const len = Math.hypot(q[0], q[1], q[2], q[3]);
    assert(Math.abs(len - 1) < 1e-3, `${label}: quaternion is not normalized (${len})`);
  }
}

async function main() {
  await access(MANIFEST_PATH);
  const manifestData = await readFile(MANIFEST_PATH);
  const manifest = JSON.parse(manifestData.toString('utf8'));
  assert(manifest.format === 'PEL_ASSET_BIN', 'manifest.format must be PEL_ASSET_BIN');
  assert(manifest.version === 1, 'manifest.version must be 1');
  assert(manifest.binaryEncoding?.byteOrder === 'little-endian', 'binary byte order must be little-endian');
  assert(manifest.binaryEncoding?.float === 'IEEE-754 float32', 'float encoding must be float32');
  assert(manifest.binaryEncoding?.index === 'uint32', 'index encoding must be uint32');

  const expectedFileLengths = new Map();
  const fileRecords = new Map((manifest.files || []).map((f) => [f.path, f]));
  for (const file of manifest.files || []) {
    assert(!expectedFileLengths.has(file.path), `duplicate manifest.files path ${file.path}`);
    expectedFileLengths.set(file.path, file.byteLength);
    try {
      const data = await getFile(file.path);
      assert(data.byteLength === file.byteLength, `${file.path}: byteLength mismatch`);
      assert(sha256(data) === file.sha256, `${file.path}: SHA256 mismatch`);
    } catch (error) {
      fail(`${file.path}: ${error.message}`);
    }
  }

  const bufferPaths = new Set();
  for (const buffer of manifest.buffers || []) {
    assert(!bufferPaths.has(buffer.path), `duplicate buffer path ${buffer.path}`);
    bufferPaths.add(buffer.path);
    assert(fileRecords.has(buffer.path), `buffer ${buffer.id} missing manifest.files record`);
    try {
      const data = await getFile(buffer.path);
      assert(data.byteLength === buffer.byteLength, `buffer ${buffer.id}: byteLength mismatch`);
      assert(sha256(data) === buffer.sha256, `buffer ${buffer.id}: SHA256 mismatch`);
    } catch (error) {
      fail(`buffer ${buffer.id}: ${error.message}`);
    }
  }

  const geometryIds = new Set();
  let vertexCount = 0;
  let triangleCount = 0;
  for (const geometry of manifest.geometries || []) {
    assert(!geometryIds.has(geometry.id), `duplicate geometry id ${geometry.id}`);
    geometryIds.add(geometry.id);
    assert(geometry.primitiveMode === 'triangles', `${geometry.id}: primitiveMode must be triangles`);
    const pos = geometry.attributes?.position;
    assert(pos?.count === geometry.vertexCount && pos?.itemSize === 3, `${geometry.id}: position layout mismatch`);
    await validateFloatRef(`${geometry.id}.position`, pos, expectedFileLengths);
    if (geometry.attributes.normal) await validateFloatRef(`${geometry.id}.normal`, geometry.attributes.normal, expectedFileLengths, { min: -1.001, max: 1.001 });
    if (geometry.attributes.uv) await validateFloatRef(`${geometry.id}.uv`, geometry.attributes.uv, expectedFileLengths);
    if (geometry.attributes.color) await validateFloatRef(`${geometry.id}.color`, geometry.attributes.color, expectedFileLengths, { min: -0.001, max: 1.001 });
    await validateIndex(`${geometry.id}.index`, geometry.index, expectedFileLengths, geometry.vertexCount);
    assert(geometry.indexCount === geometry.index.count, `${geometry.id}: indexCount mismatch`);
    assert(geometry.indexCount % 3 === 0, `${geometry.id}: triangle index count is not divisible by 3`);
    assert(geometry.triangleCount === geometry.indexCount / 3, `${geometry.id}: triangleCount mismatch`);
    for (const [semantic, targets] of Object.entries(geometry.morphTargets || {})) {
      for (let i = 0; i < targets.length; i++) {
        const target = targets[i];
        assert(target.count === geometry.vertexCount, `${geometry.id}.${semantic}[${i}]: count mismatch`);
        await validateFloatRef(`${geometry.id}.${semantic}[${i}]`, target, expectedFileLengths);
      }
    }
    for (const [name, values] of Object.entries(geometry.bounds || {})) {
      if (name === 'sphere') {
        values.center?.forEach((v, i) => assert(Number.isFinite(v), `${geometry.id}.bounds.sphere.center[${i}] non-finite`));
        assert(Number.isFinite(values.radius) && values.radius >= 0, `${geometry.id}.bounds.sphere.radius invalid`);
      } else values?.forEach((v, i) => assert(Number.isFinite(v), `${geometry.id}.bounds.${name}[${i}] non-finite`));
    }
    vertexCount += geometry.vertexCount;
    triangleCount += geometry.triangleCount;
  }

  const textureIds = new Set();
  for (const texture of manifest.textures || []) {
    assert(!textureIds.has(texture.id), `duplicate texture id ${texture.id}`);
    textureIds.add(texture.id);
    assert(Number.isInteger(texture.width) && texture.width > 0, `${texture.id}: invalid width`);
    assert(Number.isInteger(texture.height) && texture.height > 0, `${texture.id}: invalid height`);
    assert(texture.channels === 4 && texture.pixelFormat === 'rgba8', `${texture.id}: expected RGBA8`);
    assert(texture.rowStride === texture.width * 4, `${texture.id}: invalid rowStride`);
    assert(texture.byteLength === texture.width * texture.height * 4, `${texture.id}: raw byteLength mismatch`);
    try {
      const raw = await getFile(texture.buffer);
      assert(raw.byteLength === texture.byteLength, `${texture.id}: raw file size mismatch`);
      assert(sha256(raw) === texture.sha256, `${texture.id}: raw SHA256 mismatch`);
      const png = await getFile(texture.png);
      assert(png.byteLength === texture.pngByteLength, `${texture.id}: PNG size mismatch`);
      assert(sha256(png) === texture.pngSha256, `${texture.id}: PNG SHA256 mismatch`);
      const sig = png.subarray(0, 8).toString('hex');
      assert(sig === '89504e470d0a1a0a', `${texture.id}: invalid PNG signature`);
    } catch (error) {
      fail(`${texture.id}: ${error.message}`);
    }
  }

  const materialIds = new Set();
  for (const material of manifest.materials || []) {
    assert(!materialIds.has(material.id), `duplicate material id ${material.id}`);
    materialIds.add(material.id);
    for (const [slot, binding] of Object.entries(material.textures || {})) {
      assert(binding && typeof binding === 'object', `${material.id}.${slot}: invalid texture binding`);
      const textureId = binding?.texture;
      assert(textureIds.has(textureId), `${material.id}.${slot}: unknown texture ${textureId}`);
      for (const [name, expected] of [['repeat', 2], ['offset', 2], ['center', 2]]) {
        const values = binding?.[name];
        assert(Array.isArray(values) && values.length === expected, `${material.id}.${slot}.${name}: invalid transform`);
        values?.forEach((v, i) => assert(Number.isFinite(v), `${material.id}.${slot}.${name}[${i}] non-finite`));
      }
      assert(Number.isFinite(binding?.rotation), `${material.id}.${slot}.rotation non-finite`);
    }
    for (const [name, values] of [['color', material.color], ['emissive', material.emissive]]) {
      assert(Array.isArray(values) && values.length === 3, `${material.id}.${name}: invalid color`);
      values?.forEach((v, i) => assert(Number.isFinite(v), `${material.id}.${name}[${i}] non-finite`));
    }
  }

  const assetIds = new Set();
  let nodeCount = 0;
  for (const asset of manifest.assets || []) {
    assert(!assetIds.has(asset.id), `duplicate asset id ${asset.id}`);
    assetIds.add(asset.id);
    const nodeIds = new Set(asset.nodes.map((n) => n.id));
    assert(nodeIds.has(asset.rootNode), `${asset.id}: rootNode not found`);
    for (const [anchor, nodeId] of Object.entries(asset.anchors || {})) assert(nodeIds.has(nodeId), `${asset.id}: anchor ${anchor} points to unknown node ${nodeId}`);
    for (const node of asset.nodes) {
      validateTransform(`${asset.id}:${node.id}`, node.localTransform);
      if (node.parent !== null) assert(nodeIds.has(node.parent), `${node.id}: unknown parent ${node.parent}`);
      for (const child of node.children || []) assert(nodeIds.has(child), `${node.id}: unknown child ${child}`);
      if (node.geometry) assert(geometryIds.has(node.geometry), `${node.id}: unknown geometry ${node.geometry}`);
      for (const material of node.materials || []) assert(materialIds.has(material), `${node.id}: unknown material ${material}`);
      if (node.instances) {
        assert(Number.isInteger(node.instances.count) && node.instances.count >= 0, `${node.id}: invalid instance count`);
        assert(node.instances.matrices?.count === node.instances.count && node.instances.matrices?.itemSize === 16, `${node.id}: invalid instance matrices layout`);
        await validateFloatRef(`${node.id}.instances.matrices`, node.instances.matrices, expectedFileLengths);
        if (node.instances.colors) {
          assert(node.instances.colors.count === node.instances.count, `${node.id}: instance color count mismatch`);
          await validateFloatRef(`${node.id}.instances.colors`, node.instances.colors, expectedFileLengths, { min: -0.001, max: 1.001 });
        }
      }
    }
    nodeCount += asset.nodes.length;
  }

  assert(manifest.stats.assetCount === assetIds.size, 'stats.assetCount mismatch');
  assert(manifest.stats.nodeCount === nodeCount, 'stats.nodeCount mismatch');
  assert(manifest.stats.geometryCount === geometryIds.size, 'stats.geometryCount mismatch');
  assert(manifest.stats.materialCount === materialIds.size, 'stats.materialCount mismatch');
  assert(manifest.stats.textureCount === textureIds.size, 'stats.textureCount mismatch');
  assert(manifest.stats.vertexCount === vertexCount, 'stats.vertexCount mismatch');
  assert(manifest.stats.triangleCount === triangleCount, 'stats.triangleCount mismatch');
  assert(manifest.stats.binaryBytes === (manifest.buffers || []).reduce((s, b) => s + b.byteLength, 0), 'stats.binaryBytes mismatch');
  assert(manifest.stats.pngBytes === (manifest.textures || []).reduce((s, t) => s + t.pngByteLength, 0), 'stats.pngBytes mismatch');

  for (const warning of warnings) console.warn(`warning: ${warning}`);
  if (failures.length) {
    for (const failure of failures) console.error(`error: ${failure}`);
    throw new Error(`Validation failed with ${failures.length} error(s)`);
  }
  console.log(`validated ${assetIds.size} assets, ${nodeCount} nodes, ${geometryIds.size} geometries, ${textureIds.size} textures`);
  console.log(`${vertexCount} vertices, ${triangleCount} triangles, ${manifest.stats.binaryBytes} binary bytes`);
  console.log(`manifest ${MANIFEST_PATH}`);
}

main().catch((error) => {
  console.error(error?.stack || error);
  process.exitCode = 1;
});
