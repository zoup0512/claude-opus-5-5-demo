#!/usr/bin/env node
import { createHash } from 'node:crypto';
import { mkdir, readFile, rename, rm, stat, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(SCRIPT_DIR, '..', '..');
const DEFAULT_MANIFEST = path.join(REPO_ROOT, 'generated-assets', 'manifest.json');
const DEFAULT_OUTPUT = path.join(REPO_ROOT, 'packed-assets', 'pelican_assets.pak');

const HEADER_SIZE = 96;
const SECTION_SIZE = 32;
const FORMAT_VERSION = 1;
const INDEX_VERSION = 1;
const ENDIAN_TAG = 0x01020304;
const SECTION = Object.freeze({
  STRINGS: 1,
  BLOBS: 2,
  GEOMETRIES: 3,
  TEXTURES: 4,
  MATERIALS: 5,
  ASSETS: 6,
  NODES: 7,
  CHILDREN: 8,
  NODE_MATERIALS: 9,
  ANCHORS: 10,
  ROLES: 11,
  INSTANCES: 12,
  DATA: 13,
});
const TYPE_NAME = Object.freeze(Object.fromEntries(Object.entries(SECTION).map(([k, v]) => [v, k])));
const INVALID = 0xffffffff;
const BLOB_KIND = Object.freeze({ geometry: 1, texture: 2, instances: 3 });
const NODE_TYPE = Object.freeze({ Group: 1, Mesh: 2, InstancedMesh: 3, Object3D: 4, SpotLight: 5 });
const MATERIAL_TYPE = Object.freeze({ MeshBasicMaterial: 1, MeshStandardMaterial: 2, MeshPhysicalMaterial: 3 });
const COLOR_SPACE = Object.freeze({ linear: 0, srgb: 1 });
const SLOT = Object.freeze({ map: 1, bumpMap: 2 });
const ATTR = Object.freeze({ position: 1, normal: 2, uv: 3, color: 4, index: 5, morphPosition: 6 });

function usage() {
  console.log(`Usage: node pack.mjs [--manifest <manifest.json>] [--output <pelican_assets.pak>]\n\nDefaults:\n  manifest: ${DEFAULT_MANIFEST}\n  output:   ${DEFAULT_OUTPUT}`);
}

function parseArgs(argv) {
  let manifest = DEFAULT_MANIFEST;
  let output = DEFAULT_OUTPUT;
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === '--manifest') manifest = path.resolve(argv[++i] ?? '');
    else if (arg === '--output') output = path.resolve(argv[++i] ?? '');
    else if (arg === '--help' || arg === '-h') { usage(); process.exit(0); }
    else throw new Error(`unknown argument: ${arg}`);
  }
  return { manifest, output };
}

function align(value, alignment = 16) {
  return Math.ceil(value / alignment) * alignment;
}

function sha256(data) {
  return createHash('sha256').update(data).digest();
}

function hex(data) {
  return Buffer.from(data).toString('hex');
}

function crc32(data) {
  let crc = 0xffffffff;
  for (const value of data) {
    crc ^= value;
    for (let bit = 0; bit < 8; bit++) crc = (crc >>> 1) ^ ((crc & 1) ? 0xedb88320 : 0);
  }
  return (crc ^ 0xffffffff) >>> 0;
}

function finiteNumber(value, label) {
  if (typeof value !== 'number' || !Number.isFinite(value)) throw new Error(`${label} must be finite`);
  return value;
}

function finiteArray(value, count, label) {
  if (!Array.isArray(value) || value.length !== count) throw new Error(`${label} must have ${count} elements`);
  return value.map((item, index) => finiteNumber(item, `${label}[${index}]`));
}

function u32(value, label) {
  if (!Number.isInteger(value) || value < 0 || value > 0xffffffff) throw new Error(`${label} is not uint32`);
  return value >>> 0;
}

function bool(value) {
  return value ? 1 : 0;
}

function writeU64LE(buffer, offset, value) {
  buffer.writeBigUInt64LE(BigInt(value), offset);
}

class RecordWriter {
  constructor(recordSize, count) {
    this.recordSize = recordSize;
    this.buffer = Buffer.alloc(recordSize * count);
  }
  offset(index) { return index * this.recordSize; }
  u8(base, rel, value) { this.buffer.writeUInt8(value >>> 0, base + rel); }
  u16(base, rel, value) { this.buffer.writeUInt16LE(value >>> 0, base + rel); }
  i32(base, rel, value) { this.buffer.writeInt32LE(value | 0, base + rel); }
  u32(base, rel, value) { this.buffer.writeUInt32LE(value >>> 0, base + rel); }
  f32(base, rel, value) { this.buffer.writeFloatLE(finiteNumber(value, `record@${base}+${rel}`), base + rel); }
  u64(base, rel, value) { writeU64LE(this.buffer, base + rel, value); }
}

class StringTable {
  constructor() {
    this.parts = [];
    this.offsets = new Map();
    this.size = 0;
    this.add('');
  }
  add(text) {
    const value = String(text ?? '');
    if (this.offsets.has(value)) return this.offsets.get(value);
    const encoded = Buffer.from(`${value}\0`, 'utf8');
    const offset = this.size;
    this.offsets.set(value, offset);
    this.parts.push(encoded);
    this.size += encoded.length;
    return offset;
  }
  build() { return Buffer.concat(this.parts, this.size); }
}

function expect(condition, message) {
  if (!condition) throw new Error(message);
}

function validateManifestTop(manifest) {
  expect(manifest.format === 'PEL_ASSET_BIN', `unsupported manifest format ${manifest.format}`);
  expect(manifest.version === 1, `unsupported manifest version ${manifest.version}`);
  expect(manifest.binaryEncoding?.byteOrder === 'little-endian', 'manifest must be little-endian');
  expect(Array.isArray(manifest.assets), 'assets missing');
  expect(Array.isArray(manifest.buffers), 'buffers missing');
  expect(Array.isArray(manifest.geometries), 'geometries missing');
  expect(Array.isArray(manifest.materials), 'materials missing');
  expect(Array.isArray(manifest.textures), 'textures missing');
}

async function loadReferencedInputs(manifestPath, manifest) {
  const baseDir = path.dirname(manifestPath);
  expect(Array.isArray(manifest.files), 'files list missing');
  const files = new Map();
  for (const record of manifest.files) {
    expect(typeof record.path === 'string' && record.path.length > 0, 'referenced file path missing');
    expect(!files.has(record.path), `duplicate referenced file path ${record.path}`);
    const fullPath = path.resolve(baseDir, record.path);
    const relative = path.relative(baseDir, fullPath);
    expect(relative !== '..' && !relative.startsWith(`..${path.sep}`) && !path.isAbsolute(relative), `file escapes manifest directory: ${record.path}`);
    const data = await readFile(fullPath);
    expect(data.length === record.byteLength, `${record.path}: expected ${record.byteLength} bytes, got ${data.length}`);
    const digest = sha256(data);
    expect(hex(digest) === String(record.sha256).toLowerCase(), `${record.path}: SHA256 mismatch`);
    files.set(record.path, { ...record, data, digest });
  }

  const referenced = new Set();
  const loadedBuffers = manifest.buffers.map((record) => {
    const file = files.get(record.path);
    expect(file, `buffer is absent from files[]: ${record.path}`);
    expect(file.byteLength === record.byteLength, `${record.path}: buffers/files byteLength disagree`);
    expect(String(file.sha256).toLowerCase() === String(record.sha256).toLowerCase(), `${record.path}: buffers/files SHA256 disagree`);
    referenced.add(record.path);
    return { ...record, data: file.data, digest: file.digest };
  });
  for (const texture of manifest.textures) {
    const raw = files.get(texture.buffer);
    const png = files.get(texture.png);
    expect(raw, `${texture.id}: raw texture is absent from files[]`);
    expect(png, `${texture.id}: PNG is absent from files[]`);
    expect(raw.byteLength === texture.byteLength && String(raw.sha256).toLowerCase() === String(texture.sha256).toLowerCase(), `${texture.id}: raw texture metadata disagree`);
    expect(png.byteLength === texture.pngByteLength && String(png.sha256).toLowerCase() === String(texture.pngSha256).toLowerCase(), `${texture.id}: PNG metadata disagree`);
    referenced.add(texture.buffer);
    referenced.add(texture.png);
  }
  for (const filePath of files.keys()) expect(referenced.has(filePath), `files[] entry is not referenced by buffers/textures: ${filePath}`);
  return { loadedBuffers, fileCount: files.size };
}

function resolveSlice(slice, blobByPath, label, expectedType, expectedItemSize) {
  if (!slice) return null;
  const blob = blobByPath.get(slice.buffer);
  expect(blob, `${label}: unknown buffer ${slice.buffer}`);
  const offset = u32(slice.byteOffset, `${label}.byteOffset`);
  const byteLength = u32(slice.byteLength, `${label}.byteLength`);
  const count = u32(slice.count, `${label}.count`);
  const itemSize = u32(slice.itemSize, `${label}.itemSize`);
  expect(slice.componentType === expectedType, `${label}: expected ${expectedType}, got ${slice.componentType}`);
  expect(itemSize === expectedItemSize, `${label}: expected itemSize ${expectedItemSize}, got ${itemSize}`);
  expect(slice.littleEndian === true, `${label}: must be little-endian`);
  expect(offset + byteLength <= blob.data.length, `${label}: slice is out of bounds`);
  expect(byteLength === count * itemSize * 4, `${label}: byteLength/count/itemSize mismatch`);
  return { blob: blob.index, offset, byteLength, count, itemSize, normalized: bool(slice.normalized) };
}

function scanFloatSlice(blobData, slice, label) {
  for (let offset = slice.offset; offset < slice.offset + slice.byteLength; offset += 4) {
    if (!Number.isFinite(blobData.readFloatLE(offset))) throw new Error(`${label}: non-finite float at byte ${offset}`);
  }
}

function generateRoles(manifest) {
  const roles = [];
  const unresolved = [];
  const add = (assetId, role, nodeId, confidence, basis) => {
    if (!nodeId) { unresolved.push({ asset: assetId, role, reason: basis }); return; }
    roles.push({ assetId, role, nodeId, confidence, basis });
  };
  for (const asset of manifest.assets) {
    const byId = new Map(asset.nodes.map((node) => [node.id, node]));
    const children = (id) => byId.get(id)?.children ?? [];
    const groups = asset.nodes.filter((node) => node.type === 'Group');
    for (const [anchorName, nodeId] of Object.entries(asset.anchors ?? {})) {
      add(asset.id, `anchor.${anchorName}`, nodeId, 100, 'exported manifest anchor');
    }
    if (asset.id === 'bicycle') {
      const root = byId.get(asset.rootNode);
      const requiredAnchorNames = ['basket', 'bell', 'gripL', 'gripR', 'pedalL', 'pedalR'];
      const hasReliableSemanticAnchors = requiredAnchorNames.every((name) => typeof asset.anchors?.[name] === 'string' && byId.has(asset.anchors[name]));
      if (!hasReliableSemanticAnchors) {
        for (const role of [
          'wheel.rear.root', 'wheel.rear.spin', 'front.steer', 'wheel.front.root', 'wheel.front.spin',
          'crank', 'pedal.left', 'pedal.right', 'chain.instances', 'basket', 'bell', 'grip.left', 'grip.right',
        ]) add(asset.id, role, null, 0, 'required bicycle anchors are missing; relationship-only identification is ambiguous');
        continue;
      }
      const wheelRoots = groups.filter((node) => node.children.length === 1 && byId.get(node.children[0])?.type === 'Group' && byId.get(node.children[0])?.children.length === 10);
      const rearWheel = wheelRoots.find((node) => node.parent === root.id && node.localTransform.position[0] < 0);
      const rearSpin = rearWheel && byId.get(rearWheel.children[0]);
      const steer = groups.find((node) => node.parent === root.id && node.children.length >= 15 && Object.values(asset.anchors ?? {}).filter((id) => byId.get(id)?.parent === node.id || byId.get(byId.get(id)?.parent ?? '')?.parent === node.id).length >= 4);
      const frontHubCarrier = steer && children(steer.id).map((id) => byId.get(id)).find((node) => node?.type === 'Group' && node.children.length === 1 && byId.get(node.children[0])?.type === 'Group');
      const frontSpin = frontHubCarrier && byId.get(frontHubCarrier.children[0]);
      const crank = groups.find((node) => node.parent === root.id && node.children.length === 8 && Math.abs(node.localTransform.position[0] + 0.06) < 1e-4);
      const instanced = asset.nodes.find((node) => node.type === 'InstancedMesh');
      add(asset.id, 'wheel.rear.root', rearWheel?.id, 98, 'root child with nested 10-part wheel at negative X hub');
      add(asset.id, 'wheel.rear.spin', rearSpin?.id, 99, 'sole child of rear wheel root');
      add(asset.id, 'front.steer', steer?.id, 99, 'root child containing front wheel, grips, bell and basket anchors');
      add(asset.id, 'wheel.front.root', frontHubCarrier?.id, 98, 'steer child at front hub containing wheel spin group');
      add(asset.id, 'wheel.front.spin', frontSpin?.id, 99, 'sole child of front wheel root');
      add(asset.id, 'crank', crank?.id, 98, '8-child root group centered on bottom bracket');
      add(asset.id, 'pedal.left', asset.anchors?.pedalL, 100, 'exported pedalL anchor');
      add(asset.id, 'pedal.right', asset.anchors?.pedalR, 100, 'exported pedalR anchor');
      add(asset.id, 'chain.instances', instanced?.id, 100, 'only InstancedMesh in bicycle asset');
      add(asset.id, 'basket', asset.anchors?.basket, 100, 'exported basket anchor');
      add(asset.id, 'bell', asset.anchors?.bell, 100, 'exported bell anchor');
      add(asset.id, 'grip.left', asset.anchors?.gripL, 100, 'exported gripL anchor');
      add(asset.id, 'grip.right', asset.anchors?.gripR, 100, 'exported gripR anchor');
    } else if (asset.id === 'pelican') {
      const root = byId.get(asset.rootNode);
      const requiredAnchorNames = ['body', 'head', 'beakTip', 'mouth', 'scarfKnot'];
      const hasReliableSemanticAnchors = requiredAnchorNames.every((name) => typeof asset.anchors?.[name] === 'string' && byId.has(asset.anchors[name]));
      if (!hasReliableSemanticAnchors) {
        for (const role of [
          'body', 'tail', 'neck.dynamicMesh', 'head', 'beak.root', 'beak.upperPivot', 'jaw', 'pouch',
          'wing.left.shoulder', 'wing.left.elbow', 'wing.left.wrist',
          'wing.right.shoulder', 'wing.right.elbow', 'wing.right.wrist',
          'leg.left.thigh', 'leg.left.knee', 'leg.left.shin', 'leg.left.ankle', 'leg.left.foot',
          'leg.right.thigh', 'leg.right.knee', 'leg.right.shin', 'leg.right.ankle', 'leg.right.foot',
        ]) add(asset.id, role, null, 0, 'required pelican anchors are missing; relationship-only identification is ambiguous');
        continue;
      }
      const body = byId.get(asset.anchors?.body);
      const head = byId.get(asset.anchors?.head);
      const beak = head && children(head.id).map((id) => byId.get(id)).find((node) => node?.type === 'Group' && children(node.id).includes(asset.anchors?.beakTip) && children(node.id).includes(asset.anchors?.mouth));
      const jawCandidates = beak ? children(beak.id).map((id) => byId.get(id)).filter((node) => node?.type === 'Group') : [];
      const jaw = jawCandidates.find((node) => children(node.id).some((id) => byId.get(id)?.morphTargetInfluences?.length));
      const upper = jawCandidates.find((node) => node.id !== jaw?.id && node.children.length === 1);
      const pouch = jaw && children(jaw.id).map((id) => byId.get(id)).find((node) => node?.morphTargetInfluences?.length);
      const tail = body && children(body.id).map((id) => byId.get(id)).find((node) => node?.type === 'Group' && node.children.length === 7);
      const wingGroups = groups.filter((node) => node.parent === root.id && [2, 3, 7].includes(node.children.length) && Math.abs(node.localTransform.position[2]) >= 0.16 && node.localTransform.position[1] > 0.8);
      const bySide = (sign, count) => wingGroups.find((node) => Math.sign(node.localTransform.position[2]) === sign && node.children.length === count);
      const legMeshes = asset.nodes.filter((node) => node.parent === root.id && node.type === 'Mesh' && node.localTransform.position[1] < 0.9 && Math.abs(node.localTransform.position[2]) >= 0.08);
      const legSide = (sign) => legMeshes.filter((node) => Math.sign(node.localTransform.position[2]) === sign).sort((a, b) => b.localTransform.position[1] - a.localTransform.position[1]);
      const leftLeg = legSide(-1);
      const rightLeg = legSide(1);
      add(asset.id, 'body', body?.id, 100, 'exported body anchor');
      add(asset.id, 'tail', tail?.id, 98, '7-feather group under body');
      add(asset.id, 'neck.dynamicMesh', asset.nodes.find((node) => node.id !== head?.id && node.parent === root.id && node.geometry && node.materials?.includes('material_18') && node.localTransform.position.every((v) => v === 0))?.id, 85, 'root mesh with neutral transform and white neck material; geometry is static snapshot only');
      add(asset.id, 'head', head?.id, 100, 'exported head anchor');
      add(asset.id, 'beak.root', beak?.id, 99, 'head child containing beakTip and mouth anchors');
      add(asset.id, 'beak.upperPivot', upper?.id, 98, 'single-mesh sibling of morph-bearing jaw group');
      add(asset.id, 'jaw', jaw?.id, 99, 'beak child containing lower beak and morph-bearing pouch');
      add(asset.id, 'pouch', pouch?.id, 100, 'only node with morph influences');
      add(asset.id, 'wing.left.shoulder', bySide(-1, 2)?.id, 97, 'negative-Z symmetric 2-child wing joint');
      add(asset.id, 'wing.left.elbow', bySide(-1, 3)?.id, 97, 'negative-Z symmetric 3-child wing joint');
      add(asset.id, 'wing.left.wrist', bySide(-1, 7)?.id, 97, 'negative-Z symmetric 7-child wing joint');
      add(asset.id, 'wing.right.shoulder', bySide(1, 2)?.id, 97, 'positive-Z symmetric 2-child wing joint');
      add(asset.id, 'wing.right.elbow', bySide(1, 3)?.id, 97, 'positive-Z symmetric 3-child wing joint');
      add(asset.id, 'wing.right.wrist', bySide(1, 7)?.id, 97, 'positive-Z symmetric 7-child wing joint');
      for (const [side, nodes] of [['left', leftLeg], ['right', rightLeg]]) {
        add(asset.id, `leg.${side}.thigh`, nodes[0]?.id, 92, `${side} symmetric root mesh, highest leg segment`);
        add(asset.id, `leg.${side}.knee`, nodes[1]?.id, 92, `${side} symmetric root mesh, second-highest leg segment`);
        add(asset.id, `leg.${side}.shin`, nodes[2]?.id, 92, `${side} symmetric root mesh, middle leg segment`);
        add(asset.id, `leg.${side}.ankle`, nodes[3]?.id, 92, `${side} symmetric root mesh, lower leg segment`);
        add(asset.id, `leg.${side}.foot`, nodes[4]?.id, 92, `${side} symmetric root mesh, lowest leg segment`);
      }
    }
  }
  const seen = new Set();
  for (const role of roles) {
    const key = `${role.assetId}\0${role.role}`;
    expect(!seen.has(key), `duplicate role ${role.assetId}:${role.role}`);
    seen.add(key);
  }
  return { roles, unresolved };
}

function createSections(manifest, loadedBuffers, sourceManifestSha) {
  const strings = new StringTable();
  const blobs = loadedBuffers.map((buffer, index) => ({ ...buffer, index, kind: BLOB_KIND[buffer.usage] ?? 0 }));
  const blobByPath = new Map(blobs.map((blob) => [blob.path, blob]));
  const geometryById = new Map(manifest.geometries.map((item, index) => [item.id, index]));
  const textureById = new Map(manifest.textures.map((item, index) => [item.id, index]));
  const materialById = new Map(manifest.materials.map((item, index) => [item.id, index]));
  const assetById = new Map(manifest.assets.map((item, index) => [item.id, index]));
  const allNodes = manifest.assets.flatMap((asset) => asset.nodes.map((node) => ({ asset, node })));
  const nodeById = new Map(allNodes.map((item, index) => [item.node.id, index]));
  expect(nodeById.size === allNodes.length, 'duplicate node ids');

  const children = [];
  const nodeMaterials = [];
  const anchors = [];
  const instances = [];
  const geometryPrepared = [];

  for (const geometry of manifest.geometries) {
    const attrs = {};
    for (const [name, itemSize] of [['position', 3], ['normal', 3], ['uv', 2], ['color', 3]]) {
      if (geometry.attributes?.[name]) {
        attrs[name] = resolveSlice(geometry.attributes[name], blobByPath, `${geometry.id}.${name}`, 'float32', itemSize);
        scanFloatSlice(blobs[attrs[name].blob].data, attrs[name], `${geometry.id}.${name}`);
      }
    }
    expect(attrs.position && attrs.normal, `${geometry.id}: position and normal are required`);
    expect(attrs.position.count === geometry.vertexCount, `${geometry.id}: vertexCount mismatch`);
    for (const [name, slice] of Object.entries(attrs)) expect(slice.count === geometry.vertexCount, `${geometry.id}.${name}: count mismatch`);
    const index = resolveSlice(geometry.index, blobByPath, `${geometry.id}.index`, 'uint32', 1);
    expect(index.count === geometry.indexCount, `${geometry.id}: indexCount mismatch`);
    const indexBlob = blobs[index.blob].data;
    for (let offset = index.offset; offset < index.offset + index.byteLength; offset += 4) {
      expect(indexBlob.readUInt32LE(offset) < geometry.vertexCount, `${geometry.id}: index out of range`);
    }
    const morphs = geometry.morphTargets?.position ?? [];
    expect(morphs.length <= 1, `${geometry.id}: only one position morph target is supported by index v1`);
    const morph = morphs[0] ? resolveSlice(morphs[0], blobByPath, `${geometry.id}.morph.position[0]`, 'float32', 3) : null;
    if (morph) {
      expect(morph.count === geometry.vertexCount, `${geometry.id}: morph count mismatch`);
      scanFloatSlice(blobs[morph.blob].data, morph, `${geometry.id}.morph.position[0]`);
    }
    const groups = geometry.groups ?? [];
    expect(groups.length <= 6, `${geometry.id}: index v1 supports at most 6 material groups`);
    for (const [indexValue, group] of groups.entries()) {
      expect(Number.isInteger(group.start) && Number.isInteger(group.count) && Number.isInteger(group.materialIndex), `${geometry.id}.groups[${indexValue}] invalid`);
      expect(group.start + group.count <= geometry.indexCount, `${geometry.id}.groups[${indexValue}] out of range`);
    }
    const boundsMin = finiteArray(geometry.bounds.min, 3, `${geometry.id}.bounds.min`);
    const boundsMax = finiteArray(geometry.bounds.max, 3, `${geometry.id}.bounds.max`);
    const sphereCenter = finiteArray(geometry.bounds.sphere.center, 3, `${geometry.id}.bounds.sphere.center`);
    const radius = finiteNumber(geometry.bounds.sphere.radius, `${geometry.id}.bounds.sphere.radius`);
    expect(radius >= 0, `${geometry.id}: negative sphere radius`);
    geometryPrepared.push({ geometry, attrs, index, morph, groups, boundsMin, boundsMax, sphereCenter, radius });
  }

  const assetRecords = manifest.assets.map((asset, assetIndex) => {
    expect(assetById.get(asset.id) === assetIndex, 'asset index mismatch');
    const firstNode = allNodes.findIndex((item) => item.asset === asset);
    expect(firstNode !== -1, `${asset.id}: no nodes`);
    expect(nodeById.has(asset.rootNode), `${asset.id}: invalid rootNode`);
    const firstAnchor = anchors.length;
    for (const [name, nodeId] of Object.entries(asset.anchors ?? {})) {
      expect(nodeById.has(nodeId), `${asset.id}: anchor ${name} refers to missing node ${nodeId}`);
      anchors.push({ asset: assetIndex, name, node: nodeById.get(nodeId) });
    }
    return { asset, firstNode, firstAnchor, anchorCount: anchors.length - firstAnchor };
  });

  const nodeRecords = allNodes.map(({ asset, node }) => {
    const firstChild = children.length;
    for (const childId of node.children ?? []) {
      expect(nodeById.has(childId), `${node.id}: missing child ${childId}`);
      expect(allNodes[nodeById.get(childId)].node.parent === node.id, `${node.id}: child ${childId} parent mismatch`);
      children.push(nodeById.get(childId));
    }
    const firstMaterial = nodeMaterials.length;
    for (const materialId of node.materials ?? []) {
      expect(materialById.has(materialId), `${node.id}: missing material ${materialId}`);
      nodeMaterials.push(materialById.get(materialId));
    }
    let instanceIndex = INVALID;
    if (node.instances) {
      const slice = resolveSlice(node.instances.matrices, blobByPath, `${node.id}.instances.matrices`, 'float32', 16);
      expect(slice.count === node.instances.count, `${node.id}: instance count mismatch`);
      scanFloatSlice(blobs[slice.blob].data, slice, `${node.id}.instances.matrices`);
      instanceIndex = instances.length;
      instances.push({ node: nodeById.get(node.id), ...slice });
    }
    if (node.parent !== null) expect(nodeById.has(node.parent), `${node.id}: missing parent ${node.parent}`);
    if (node.geometry !== null) expect(geometryById.has(node.geometry), `${node.id}: missing geometry ${node.geometry}`);
    const transform = node.localTransform;
    const position = finiteArray(transform.position, 3, `${node.id}.position`);
    const quaternion = finiteArray(transform.quaternion, 4, `${node.id}.quaternion`);
    const scale = finiteArray(transform.scale, 3, `${node.id}.scale`);
    const morphInfluence = node.morphTargetInfluences?.[0] ?? 0;
    finiteNumber(morphInfluence, `${node.id}.morphTargetInfluences[0]`);
    return { asset, node, firstChild, firstMaterial, instanceIndex, position, quaternion, scale, morphInfluence };
  });

  const { roles, unresolved } = generateRoles(manifest);
  for (const role of roles) {
    expect(assetById.has(role.assetId), `role ${role.role}: missing asset ${role.assetId}`);
    expect(nodeById.has(role.nodeId), `role ${role.role}: missing node ${role.nodeId}`);
  }

  let dataSize = 0;
  for (const blob of blobs) {
    dataSize = align(dataSize, 16);
    blob.dataOffset = dataSize;
    dataSize += blob.data.length;
    blob.crc32 = crc32(blob.data);
  }
  const dataSection = Buffer.alloc(dataSize);
  for (const blob of blobs) blob.data.copy(dataSection, blob.dataOffset);

  const stringOffset = (value) => strings.add(value);
  for (const blob of blobs) { stringOffset(blob.path); stringOffset(blob.id); }
  for (const item of manifest.geometries) stringOffset(item.id);
  for (const item of manifest.textures) { stringOffset(item.id); stringOffset(item.name); }
  for (const item of manifest.materials) { stringOffset(item.id); stringOffset(item.name); }
  for (const item of manifest.assets) { stringOffset(item.id); stringOffset(item.name); }
  for (const { node } of allNodes) { stringOffset(node.id); stringOffset(node.name); }
  for (const anchor of anchors) stringOffset(anchor.name);
  for (const role of roles) { stringOffset(role.role); stringOffset(role.basis); }

  const blobWriter = new RecordWriter(64, blobs.length);
  blobs.forEach((blob, index) => {
    const o = blobWriter.offset(index);
    blobWriter.u32(o, 0, stringOffset(blob.path));
    blobWriter.u32(o, 4, stringOffset(blob.id));
    blobWriter.u32(o, 8, blob.kind);
    blobWriter.u32(o, 12, blob.crc32);
    blobWriter.u64(o, 16, blob.dataOffset);
    blobWriter.u64(o, 24, blob.data.length);
    blob.digest.copy(blobWriter.buffer, o + 32);
  });

  const geometryWriter = new RecordWriter(264, geometryPrepared.length);
  const writeSlice = (writer, base, rel, slice, kind) => {
    if (!slice) {
      writer.u32(base, rel + 0, INVALID);
      writer.u32(base, rel + 4, 0);
      writer.u32(base, rel + 8, 0);
      writer.u32(base, rel + 12, 0);
      writer.u16(base, rel + 16, 0);
      writer.u8(base, rel + 18, 0);
      writer.u8(base, rel + 19, 0);
      return;
    }
    writer.u32(base, rel + 0, slice.blob);
    writer.u32(base, rel + 4, slice.offset);
    writer.u32(base, rel + 8, slice.byteLength);
    writer.u32(base, rel + 12, slice.count);
    writer.u16(base, rel + 16, slice.itemSize);
    writer.u8(base, rel + 18, kind);
    writer.u8(base, rel + 19, slice.normalized);
  };
  geometryPrepared.forEach((item, index) => {
    const o = geometryWriter.offset(index);
    const { geometry, attrs, morph, groups } = item;
    geometryWriter.u32(o, 0, stringOffset(geometry.id));
    geometryWriter.u32(o, 4, geometry.vertexCount);
    geometryWriter.u32(o, 8, geometry.indexCount);
    geometryWriter.u32(o, 12, geometry.triangleCount);
    geometryWriter.u32(o, 16, geometry.drawRange.start);
    geometryWriter.u32(o, 20, geometry.drawRange.count);
    geometryWriter.u16(o, 24, groups.length);
    geometryWriter.u16(o, 26, geometry.morphTargetsRelative ? 1 : 0);
    writeSlice(geometryWriter, o, 28, attrs.position, ATTR.position);
    writeSlice(geometryWriter, o, 48, attrs.normal, ATTR.normal);
    writeSlice(geometryWriter, o, 68, attrs.uv, ATTR.uv);
    writeSlice(geometryWriter, o, 88, attrs.color, ATTR.color);
    writeSlice(geometryWriter, o, 108, item.index, ATTR.index);
    writeSlice(geometryWriter, o, 128, morph, ATTR.morphPosition);
    item.boundsMin.forEach((v, i) => geometryWriter.f32(o, 148 + i * 4, v));
    item.boundsMax.forEach((v, i) => geometryWriter.f32(o, 160 + i * 4, v));
    item.sphereCenter.forEach((v, i) => geometryWriter.f32(o, 172 + i * 4, v));
    geometryWriter.f32(o, 184, item.radius);
    groups.forEach((group, groupIndex) => {
      const rel = 188 + groupIndex * 12;
      geometryWriter.u32(o, rel + 0, group.start);
      geometryWriter.u32(o, rel + 4, group.count);
      geometryWriter.u16(o, rel + 8, group.materialIndex);
      geometryWriter.u16(o, rel + 10, 0);
    });
  });

  const textureWriter = new RecordWriter(96, manifest.textures.length);
  manifest.textures.forEach((texture, index) => {
    const o = textureWriter.offset(index);
    const blob = blobByPath.get(texture.buffer);
    expect(blob, `${texture.id}: missing raw texture buffer ${texture.buffer}`);
    expect(texture.pixelFormat === 'rgba8' && texture.channels === 4, `${texture.id}: only RGBA8 textures are supported`);
    expect(texture.byteLength === texture.width * texture.height * 4, `${texture.id}: RGBA8 byteLength mismatch`);
    expect(texture.rowStride === texture.width * 4, `${texture.id}: rowStride mismatch`);
    expect(texture.rowOrder === 'top-to-bottom', `${texture.id}: unsupported row order`);
    const center = finiteArray(texture.center, 2, `${texture.id}.center`);
    const offset = finiteArray(texture.offset, 2, `${texture.id}.offset`);
    const repeat = finiteArray(texture.repeat, 2, `${texture.id}.repeat`);
    textureWriter.u32(o, 0, stringOffset(texture.id));
    textureWriter.u32(o, 4, stringOffset(texture.name));
    textureWriter.u32(o, 8, blob.index);
    textureWriter.u32(o, 12, texture.width);
    textureWriter.u32(o, 16, texture.height);
    textureWriter.u32(o, 20, texture.rowStride);
    textureWriter.u32(o, 24, blob.crc32);
    textureWriter.u16(o, 28, texture.wrapS);
    textureWriter.u16(o, 30, texture.wrapT);
    textureWriter.u16(o, 32, texture.minFilter);
    textureWriter.u16(o, 34, texture.magFilter);
    textureWriter.u8(o, 36, COLOR_SPACE[texture.colorSpace] ?? 0);
    textureWriter.u8(o, 37, bool(texture.flipY));
    textureWriter.u8(o, 38, bool(texture.premultiplyAlpha));
    textureWriter.u8(o, 39, 4);
    textureWriter.f32(o, 40, repeat[0]); textureWriter.f32(o, 44, repeat[1]);
    textureWriter.f32(o, 48, offset[0]); textureWriter.f32(o, 52, offset[1]);
    textureWriter.f32(o, 56, center[0]); textureWriter.f32(o, 60, center[1]);
    textureWriter.f32(o, 64, texture.rotation);
    blob.digest.copy(textureWriter.buffer, o + 68, 0, 28);
  });

  const materialWriter = new RecordWriter(192, manifest.materials.length);
  const writeBinding = (writer, base, rel, binding, slotType) => {
    if (!binding) { writer.u32(base, rel + 0, INVALID); return; }
    expect(textureById.has(binding.texture), `material binding: missing texture ${binding.texture}`);
    const repeat = finiteArray(binding.repeat, 2, 'material texture repeat');
    const offset = finiteArray(binding.offset, 2, 'material texture offset');
    const center = finiteArray(binding.center, 2, 'material texture center');
    writer.u32(base, rel + 0, textureById.get(binding.texture));
    writer.u16(base, rel + 4, binding.wrapS);
    writer.u16(base, rel + 6, binding.wrapT);
    writer.u16(base, rel + 8, binding.minFilter);
    writer.u16(base, rel + 10, binding.magFilter);
    writer.u8(base, rel + 12, bool(binding.flipY));
    writer.u8(base, rel + 13, slotType);
    writer.u16(base, rel + 14, 0);
    writer.f32(base, rel + 16, repeat[0]); writer.f32(base, rel + 20, repeat[1]);
    writer.f32(base, rel + 24, offset[0]); writer.f32(base, rel + 28, offset[1]);
    writer.f32(base, rel + 32, center[0]); writer.f32(base, rel + 36, center[1]);
    writer.f32(base, rel + 40, binding.rotation);
  };
  manifest.materials.forEach((material, index) => {
    const o = materialWriter.offset(index);
    const p = material.parameters ?? {};
    const color = finiteArray(material.color, 3, `${material.id}.color`);
    const emissive = finiteArray(material.emissive, 3, `${material.id}.emissive`);
    const attenuation = p.attenuationColor ? finiteArray(p.attenuationColor, 3, `${material.id}.attenuationColor`) : [1, 1, 1];
    const sheen = p.sheenColor ? finiteArray(p.sheenColor, 3, `${material.id}.sheenColor`) : [0, 0, 0];
    materialWriter.u32(o, 0, stringOffset(material.id));
    materialWriter.u32(o, 4, stringOffset(material.name));
    materialWriter.u8(o, 8, MATERIAL_TYPE[material.type] ?? 0);
    materialWriter.u8(o, 9, bool(material.transparent));
    materialWriter.u8(o, 10, bool(material.depthTest));
    materialWriter.u8(o, 11, bool(material.depthWrite));
    materialWriter.u8(o, 12, bool(material.vertexColors));
    materialWriter.u8(o, 13, bool(material.flatShading));
    materialWriter.u8(o, 14, bool(material.wireframe));
    materialWriter.u8(o, 15, material.side);
    materialWriter.u16(o, 16, material.blending);
    materialWriter.u16(o, 18, 0);
    color.forEach((v, i) => materialWriter.f32(o, 20 + i * 4, v));
    emissive.forEach((v, i) => materialWriter.f32(o, 32 + i * 4, v));
    materialWriter.f32(o, 44, material.emissiveIntensity);
    materialWriter.f32(o, 48, material.opacity);
    materialWriter.f32(o, 52, material.alphaTest);
    const scalar = (name, fallback) => p[name] == null ? fallback : finiteNumber(p[name], `${material.id}.${name}`);
    materialWriter.f32(o, 56, scalar('roughness', 1));
    materialWriter.f32(o, 60, scalar('metalness', 0));
    materialWriter.f32(o, 64, scalar('clearcoat', 0));
    materialWriter.f32(o, 68, scalar('clearcoatRoughness', 0));
    materialWriter.f32(o, 72, scalar('ior', 1.5));
    materialWriter.f32(o, 76, scalar('reflectivity', 0.5));
    materialWriter.f32(o, 80, scalar('transmission', 0));
    materialWriter.f32(o, 84, scalar('thickness', 0));
    materialWriter.f32(o, 88, scalar('attenuationDistance', -1));
    attenuation.forEach((v, i) => materialWriter.f32(o, 92 + i * 4, v));
    materialWriter.f32(o, 104, scalar('sheen', 0));
    materialWriter.f32(o, 108, scalar('sheenRoughness', 1));
    sheen.forEach((v, i) => materialWriter.f32(o, 112 + i * 4, v));
    materialWriter.f32(o, 124, scalar('bumpScale', 1));
    materialWriter.f32(o, 128, scalar('displacementScale', 1));
    materialWriter.f32(o, 132, scalar('displacementBias', 0));
    materialWriter.f32(o, 136, scalar('polygonOffsetFactor', 0));
    materialWriter.f32(o, 140, scalar('polygonOffsetUnits', 0));
    writeBinding(materialWriter, o, 144, material.textures?.map, SLOT.map);
    writeBinding(materialWriter, o, 188, material.textures?.bumpMap, SLOT.bumpMap);
  });

  // Binding 2 overlaps record end above; use a 236-byte final material layout instead.
  const finalMaterialWriter = new RecordWriter(236, manifest.materials.length);
  for (let index = 0; index < manifest.materials.length; index++) {
    materialWriter.buffer.copy(finalMaterialWriter.buffer, finalMaterialWriter.offset(index), materialWriter.offset(index), materialWriter.offset(index) + 188);
    writeBinding(finalMaterialWriter, finalMaterialWriter.offset(index), 144, manifest.materials[index].textures?.map, SLOT.map);
    writeBinding(finalMaterialWriter, finalMaterialWriter.offset(index), 188, manifest.materials[index].textures?.bumpMap, SLOT.bumpMap);
  }

  const assetWriter = new RecordWriter(32, assetRecords.length);
  assetRecords.forEach((item, index) => {
    const o = assetWriter.offset(index);
    assetWriter.u32(o, 0, stringOffset(item.asset.id));
    assetWriter.u32(o, 4, stringOffset(item.asset.name));
    assetWriter.u32(o, 8, nodeById.get(item.asset.rootNode));
    assetWriter.u32(o, 12, item.firstNode);
    assetWriter.u32(o, 16, item.asset.nodes.length);
    assetWriter.u32(o, 20, item.firstAnchor);
    assetWriter.u32(o, 24, item.anchorCount);
    assetWriter.u32(o, 28, 0);
  });

  const nodeWriter = new RecordWriter(104, nodeRecords.length);
  nodeRecords.forEach((item, index) => {
    const { asset, node } = item;
    const o = nodeWriter.offset(index);
    nodeWriter.u32(o, 0, stringOffset(node.id));
    nodeWriter.u32(o, 4, stringOffset(node.name));
    nodeWriter.u32(o, 8, assetById.get(asset.id));
    nodeWriter.u32(o, 12, node.parent === null ? INVALID : nodeById.get(node.parent));
    nodeWriter.u32(o, 16, item.firstChild);
    nodeWriter.u16(o, 20, node.children.length);
    nodeWriter.u8(o, 22, NODE_TYPE[node.type] ?? 0);
    let flags = 0;
    flags |= bool(node.visible) << 0;
    flags |= bool(node.castShadow) << 1;
    flags |= bool(node.receiveShadow) << 2;
    nodeWriter.u8(o, 23, flags);
    nodeWriter.u32(o, 24, node.geometry === null ? INVALID : geometryById.get(node.geometry));
    nodeWriter.u32(o, 28, item.firstMaterial);
    nodeWriter.u16(o, 32, node.materials.length);
    nodeWriter.u16(o, 34, node.morphTargetInfluences?.length ?? 0);
    nodeWriter.u32(o, 36, item.instanceIndex);
    nodeWriter.i32(o, 40, node.renderOrder);
    item.position.forEach((v, i) => nodeWriter.f32(o, 44 + i * 4, v));
    item.quaternion.forEach((v, i) => nodeWriter.f32(o, 56 + i * 4, v));
    item.scale.forEach((v, i) => nodeWriter.f32(o, 72 + i * 4, v));
    nodeWriter.f32(o, 84, item.morphInfluence);
  });

  const childBuffer = Buffer.alloc(children.length * 4);
  children.forEach((value, index) => childBuffer.writeUInt32LE(value, index * 4));
  const nodeMaterialBuffer = Buffer.alloc(nodeMaterials.length * 4);
  nodeMaterials.forEach((value, index) => nodeMaterialBuffer.writeUInt32LE(value, index * 4));

  const anchorWriter = new RecordWriter(16, anchors.length);
  anchors.forEach((anchor, index) => {
    const o = anchorWriter.offset(index);
    anchorWriter.u32(o, 0, anchor.asset);
    anchorWriter.u32(o, 4, stringOffset(anchor.name));
    anchorWriter.u32(o, 8, anchor.node);
    anchorWriter.u32(o, 12, 0);
  });

  const roleWriter = new RecordWriter(24, roles.length);
  roles.forEach((role, index) => {
    const o = roleWriter.offset(index);
    roleWriter.u32(o, 0, assetById.get(role.assetId));
    roleWriter.u32(o, 4, stringOffset(role.role));
    roleWriter.u32(o, 8, nodeById.get(role.nodeId));
    roleWriter.u8(o, 12, role.confidence);
    roleWriter.u8(o, 13, 0);
    roleWriter.u16(o, 14, 0);
    roleWriter.u32(o, 16, stringOffset(role.basis));
    roleWriter.u32(o, 20, 0);
  });

  const instanceWriter = new RecordWriter(32, instances.length);
  instances.forEach((instance, index) => {
    const o = instanceWriter.offset(index);
    instanceWriter.u32(o, 0, instance.node);
    instanceWriter.u32(o, 4, instance.blob);
    instanceWriter.u32(o, 8, instance.offset);
    instanceWriter.u32(o, 12, instance.byteLength);
    instanceWriter.u32(o, 16, instance.count);
    instanceWriter.u16(o, 20, instance.itemSize);
    instanceWriter.u16(o, 22, 0);
    instanceWriter.u32(o, 24, 0);
    instanceWriter.u32(o, 28, 0);
  });

  const stringBuffer = strings.build();
  const sections = [
    { type: SECTION.STRINGS, recordSize: 1, count: stringBuffer.length, data: stringBuffer },
    { type: SECTION.BLOBS, recordSize: 64, count: blobs.length, data: blobWriter.buffer },
    { type: SECTION.GEOMETRIES, recordSize: 264, count: geometryPrepared.length, data: geometryWriter.buffer },
    { type: SECTION.TEXTURES, recordSize: 96, count: manifest.textures.length, data: textureWriter.buffer },
    { type: SECTION.MATERIALS, recordSize: 236, count: manifest.materials.length, data: finalMaterialWriter.buffer },
    { type: SECTION.ASSETS, recordSize: 32, count: assetRecords.length, data: assetWriter.buffer },
    { type: SECTION.NODES, recordSize: 104, count: nodeRecords.length, data: nodeWriter.buffer },
    { type: SECTION.CHILDREN, recordSize: 4, count: children.length, data: childBuffer },
    { type: SECTION.NODE_MATERIALS, recordSize: 4, count: nodeMaterials.length, data: nodeMaterialBuffer },
    { type: SECTION.ANCHORS, recordSize: 16, count: anchors.length, data: anchorWriter.buffer },
    { type: SECTION.ROLES, recordSize: 24, count: roles.length, data: roleWriter.buffer },
    { type: SECTION.INSTANCES, recordSize: 32, count: instances.length, data: instanceWriter.buffer },
    { type: SECTION.DATA, recordSize: 1, count: dataSection.length, data: dataSection },
  ];
  for (const section of sections) section.crc32 = crc32(section.data);
  return { sections, roles, unresolved, sourceManifestSha };
}

function assemblePak(model) {
  const { sections, sourceManifestSha } = model;
  const sectionTableOffset = HEADER_SIZE;
  const sectionTableLength = sections.length * SECTION_SIZE;
  let cursor = align(sectionTableOffset + sectionTableLength, 16);
  for (const section of sections) {
    section.offset = cursor;
    section.length = section.data.length;
    cursor = align(cursor + section.length, 16);
  }
  const fileSize = cursor;
  const output = Buffer.alloc(fileSize);
  const sectionTable = Buffer.alloc(sectionTableLength);
  sections.forEach((section, index) => {
    const o = index * SECTION_SIZE;
    sectionTable.writeUInt32LE(section.type, o + 0);
    sectionTable.writeUInt32LE(section.recordSize, o + 4);
    writeU64LE(sectionTable, o + 8, section.offset);
    writeU64LE(sectionTable, o + 16, section.length);
    sectionTable.writeUInt32LE(section.count, o + 24);
    sectionTable.writeUInt32LE(section.crc32, o + 28);
    section.data.copy(output, section.offset);
  });
  sectionTable.copy(output, sectionTableOffset);

  output.write('PELICAN\0', 0, 'ascii');
  output.writeUInt16LE(FORMAT_VERSION, 8);
  output.writeUInt16LE(INDEX_VERSION, 10);
  output.writeUInt16LE(HEADER_SIZE, 12);
  output.writeUInt16LE(SECTION_SIZE, 14);
  output.writeUInt32LE(ENDIAN_TAG, 16);
  output.writeUInt32LE(sections.length, 20);
  writeU64LE(output, 24, sectionTableOffset);
  writeU64LE(output, 32, sectionTableLength);
  writeU64LE(output, 40, fileSize);
  output.writeUInt32LE(crc32(sectionTable), 48);
  output.writeUInt32LE(0, 52);
  sourceManifestSha.copy(output, 56);
  output.writeUInt32LE(0, 88);
  output.writeUInt32LE(0, 92);
  output.writeUInt32LE(crc32(output.subarray(0, HEADER_SIZE)), 88);
  output.writeUInt32LE(0, 92);
  output.writeUInt32LE(crc32(output), 92);
  return output;
}

async function atomicWrite(filePath, data) {
  await mkdir(path.dirname(filePath), { recursive: true });
  const temp = `${filePath}.tmp-${process.pid}-${Date.now()}`;
  await writeFile(temp, data);
  await rm(filePath, { force: true });
  await rename(temp, filePath);
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const manifestBytes = await readFile(args.manifest);
  const manifest = JSON.parse(manifestBytes.toString('utf8'));
  validateManifestTop(manifest);
  const { loadedBuffers, fileCount } = await loadReferencedInputs(args.manifest, manifest);
  const model = createSections(manifest, loadedBuffers, sha256(manifestBytes));
  const pak = assemblePak(model);
  await atomicWrite(args.output, pak);
  const info = await stat(args.output);
  const dataBytes = loadedBuffers.reduce((sum, item) => sum + item.data.length, 0);
  console.log(`packed ${manifest.assets.length} assets, ${manifest.stats.nodeCount} nodes, ${manifest.geometries.length} geometries, ${manifest.textures.length} textures`);
  console.log(`${manifest.stats.vertexCount} vertices, ${manifest.stats.triangleCount} triangles, ${dataBytes} payload bytes; verified ${fileCount} referenced files`);
  console.log(`${model.roles.length} stable roles, ${model.unresolved.length} unresolved roles`);
  console.log(`${args.output} ${info.size} bytes sha256=${hex(sha256(pak))}`);
  console.log('sections:', model.sections.map((section) => `${TYPE_NAME[section.type]}=${section.length}`).join(', '));
}

main().catch((error) => {
  console.error(`asset-packer: ${error.stack || error.message}`);
  process.exitCode = 1;
});
