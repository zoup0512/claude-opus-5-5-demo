(() => {
  'use strict';

  const MAGIC = 'PEL_ASSET_BIN';
  const FORMAT_VERSION = 1;
  const seenNames = new Map();

  function align(value, multiple) {
    return Math.ceil(value / multiple) * multiple;
  }

  function finiteNumber(value, fallback = 0) {
    return Number.isFinite(value) ? value : fallback;
  }

  function array3(v) {
    return [finiteNumber(v.x), finiteNumber(v.y), finiteNumber(v.z)];
  }

  function array4(v) {
    return [finiteNumber(v.x), finiteNumber(v.y), finiteNumber(v.z), finiteNumber(v.w, 1)];
  }

  function colorArray(c) {
    return c ? [finiteNumber(c.r), finiteNumber(c.g), finiteNumber(c.b)] : [1, 1, 1];
  }

  function makeSafeName(label, fallback) {
    let base = String(label || fallback || 'asset')
      .normalize('NFKD')
      .replace(/[^A-Za-z0-9._-]+/g, '_')
      .replace(/^_+|_+$/g, '')
      .toLowerCase();
    if (!base) base = fallback || 'asset';
    const n = seenNames.get(base) || 0;
    seenNames.set(base, n + 1);
    return n ? `${base}_${n + 1}` : base;
  }

  function scalarValue(value) {
    if (value === undefined || value === null) return undefined;
    if (typeof value === 'number' || typeof value === 'boolean' || typeof value === 'string') return value;
    return undefined;
  }

  function vec2Value(v, fallback = [0, 0]) {
    return v && Number.isFinite(v.x) && Number.isFinite(v.y) ? [v.x, v.y] : fallback;
  }

  function materialRecord(mat, id, textureIds) {
    const rec = {
      id,
      name: mat.name || id,
      type: mat.type || 'Material',
      color: colorArray(mat.color),
      emissive: colorArray(mat.emissive || { r: 0, g: 0, b: 0 }),
      emissiveIntensity: finiteNumber(mat.emissiveIntensity, 1),
      opacity: finiteNumber(mat.opacity, 1),
      transparent: !!mat.transparent,
      alphaTest: finiteNumber(mat.alphaTest, 0),
      side: finiteNumber(mat.side, 0),
      depthTest: mat.depthTest !== false,
      depthWrite: mat.depthWrite !== false,
      vertexColors: !!mat.vertexColors,
      wireframe: !!mat.wireframe,
      flatShading: !!mat.flatShading,
      blending: finiteNumber(mat.blending, 1),
      parameters: {},
      textures: {},
    };
    for (const key of [
      'roughness',
      'metalness',
      'clearcoat',
      'clearcoatRoughness',
      'sheen',
      'sheenRoughness',
      'bumpScale',
      'normalScale',
      'displacementScale',
      'displacementBias',
      'reflectivity',
      'ior',
      'transmission',
      'thickness',
      'attenuationDistance',
      'polygonOffsetFactor',
      'polygonOffsetUnits',
    ]) {
      const v = scalarValue(mat[key]);
      if (v !== undefined) rec.parameters[key] = v;
    }
    for (const key of ['map', 'bumpMap', 'normalMap', 'roughnessMap', 'metalnessMap', 'alphaMap', 'emissiveMap', 'aoMap']) {
      const tex = mat[key];
      if (!tex || !textureIds.has(tex)) continue;
      rec.textures[key] = {
        texture: textureIds.get(tex),
        wrapS: tex.wrapS,
        wrapT: tex.wrapT,
        magFilter: tex.magFilter,
        minFilter: tex.minFilter,
        flipY: tex.flipY !== false,
        repeat: vec2Value(tex.repeat, [1, 1]),
        offset: vec2Value(tex.offset, [0, 0]),
        center: vec2Value(tex.center, [0, 0]),
        rotation: finiteNumber(tex.rotation, 0),
      };
    }
    if (mat.sheenColor) rec.parameters.sheenColor = colorArray(mat.sheenColor);
    if (mat.attenuationColor) rec.parameters.attenuationColor = colorArray(mat.attenuationColor);
    return rec;
  }

  function copyAttribute(attr) {
    const count = attr.count;
    const itemSize = attr.itemSize;
    const out = new Float32Array(count * itemSize);
    for (let i = 0; i < count; i++) {
      for (let j = 0; j < itemSize; j++) out[i * itemSize + j] = finiteNumber(attr.getComponent(i, j));
    }
    return out;
  }

  function copyIndex(index, vertexCount) {
    if (index) {
      const out = new Uint32Array(index.count);
      for (let i = 0; i < index.count; i++) out[i] = index.getX(i) >>> 0;
      return out;
    }
    const out = new Uint32Array(vertexCount);
    for (let i = 0; i < vertexCount; i++) out[i] = i;
    return out;
  }

  function computeBounds(position) {
    const min = [Infinity, Infinity, Infinity];
    const max = [-Infinity, -Infinity, -Infinity];
    for (let i = 0; i < position.length; i += 3) {
      for (let k = 0; k < 3; k++) {
        const v = position[i + k];
        min[k] = Math.min(min[k], v);
        max[k] = Math.max(max[k], v);
      }
    }
    const center = min.map((v, i) => (v + max[i]) * 0.5);
    let radiusSq = 0;
    for (let i = 0; i < position.length; i += 3) {
      const dx = position[i] - center[0];
      const dy = position[i + 1] - center[1];
      const dz = position[i + 2] - center[2];
      radiusSq = Math.max(radiusSq, dx * dx + dy * dy + dz * dz);
    }
    return { min, max, sphere: { center, radius: Math.sqrt(radiusSq) } };
  }

  function pushBuffer(chunks, typed, meta) {
    const data = new Uint8Array(typed.buffer, typed.byteOffset, typed.byteLength).slice();
    chunks.push({ data, meta });
    return meta;
  }

  function serializeGeometry(geometry, id, fileName, nodesUsingGeometry) {
    const source = geometry.clone();
    if (!source.getAttribute('position')) throw new Error(`Geometry ${id} has no position attribute`);
    if (!source.getAttribute('normal')) source.computeVertexNormals();
    const posAttr = source.getAttribute('position');
    const vertexCount = posAttr.count;
    const chunks = [];
    const attributes = {};
    let cursor = 0;
    const addFloat = (name, attr, kind = 'attribute') => {
      if (!attr) return;
      const typed = copyAttribute(attr);
      cursor = align(cursor, 4);
      const meta = {
        buffer: fileName,
        byteOffset: cursor,
        byteLength: typed.byteLength,
        componentType: 'float32',
        littleEndian: true,
        count: attr.count,
        itemSize: attr.itemSize,
        normalized: !!attr.normalized,
      };
      pushBuffer(chunks, typed, meta);
      cursor += typed.byteLength;
      if (kind === 'attribute') attributes[name] = meta;
      return meta;
    };
    const position = copyAttribute(posAttr);
    cursor = align(cursor, 4);
    attributes.position = pushBuffer(chunks, position, {
      buffer: fileName,
      byteOffset: cursor,
      byteLength: position.byteLength,
      componentType: 'float32',
      littleEndian: true,
      count: posAttr.count,
      itemSize: posAttr.itemSize,
      normalized: !!posAttr.normalized,
    });
    cursor += position.byteLength;
    addFloat('normal', source.getAttribute('normal'));
    addFloat('uv', source.getAttribute('uv'));
    addFloat('color', source.getAttribute('color'));

    const indexArray = copyIndex(source.index, vertexCount);
    cursor = align(cursor, 4);
    const index = pushBuffer(chunks, indexArray, {
      buffer: fileName,
      byteOffset: cursor,
      byteLength: indexArray.byteLength,
      componentType: 'uint32',
      littleEndian: true,
      count: indexArray.length,
      itemSize: 1,
      normalized: false,
    });
    cursor += indexArray.byteLength;

    const morphTargets = {};
    for (const [semantic, list] of Object.entries(source.morphAttributes || {})) {
      if (!Array.isArray(list) || !list.length) continue;
      morphTargets[semantic] = list.map((attr, targetIndex) => {
        cursor = align(cursor, 4);
        const typed = copyAttribute(attr);
        const meta = pushBuffer(chunks, typed, {
          name: source.morphTargetDictionary ? Object.keys(source.morphTargetDictionary).find((k) => source.morphTargetDictionary[k] === targetIndex) || `target_${targetIndex}` : `target_${targetIndex}`,
          buffer: fileName,
          byteOffset: cursor,
          byteLength: typed.byteLength,
          componentType: 'float32',
          littleEndian: true,
          count: attr.count,
          itemSize: attr.itemSize,
          normalized: !!attr.normalized,
        });
        cursor += typed.byteLength;
        return meta;
      });
    }

    const out = new Uint8Array(cursor);
    for (const chunk of chunks) out.set(chunk.data, chunk.meta.byteOffset);
    const triangles = Math.floor(indexArray.length / 3);
    const groups = (source.groups || []).map((g) => ({ start: g.start >>> 0, count: g.count >>> 0, materialIndex: g.materialIndex >>> 0 }));
    const drawRange = {
      start: source.drawRange?.start ?? 0,
      count: Number.isFinite(source.drawRange?.count) ? source.drawRange.count : indexArray.length,
    };
    return {
      bytes: out,
      record: {
        id,
        buffer: fileName,
        primitiveMode: 'triangles',
        vertexCount,
        indexCount: indexArray.length,
        triangleCount: triangles,
        attributes,
        index,
        morphTargets,
        morphTargetsRelative: !!source.morphTargetsRelative,
        groups,
        drawRange,
        bounds: computeBounds(position),
        usedByNodes: nodesUsingGeometry,
      },
    };
  }

  function objectType(obj) {
    if (obj.isInstancedMesh) return 'InstancedMesh';
    if (obj.isSkinnedMesh) return 'SkinnedMesh';
    if (obj.isMesh) return 'Mesh';
    if (obj.isLineSegments) return 'LineSegments';
    if (obj.isLine) return 'Line';
    if (obj.isPoints) return 'Points';
    if (obj.isSprite) return 'Sprite';
    if (obj.isLight) return obj.type || 'Light';
    if (obj.isCamera) return obj.type || 'Camera';
    if (obj.isGroup) return 'Group';
    return obj.type || 'Object3D';
  }

  function serializeTree(root, assetId, geometryIds, materialIds) {
    const nodes = [];
    const nodeIds = new Map();
    const geometryUsage = new Map();
    let serial = 0;
    root.traverse((obj) => {
      const nodeId = `${assetId}/n${serial++}`;
      nodeIds.set(obj, nodeId);
      if (obj.geometry) {
        const list = geometryUsage.get(obj.geometry) || [];
        list.push(nodeId);
        geometryUsage.set(obj.geometry, list);
      }
    });
    root.traverse((obj) => {
      const nodeId = nodeIds.get(obj);
      const materialList = Array.isArray(obj.material) ? obj.material : obj.material ? [obj.material] : [];
      const rec = {
        id: nodeId,
        name: obj.name || '',
        type: objectType(obj),
        parent: obj === root ? null : nodeIds.get(obj.parent) || null,
        children: obj.children.map((c) => nodeIds.get(c)),
        visible: obj.visible !== false,
        castShadow: !!obj.castShadow,
        receiveShadow: !!obj.receiveShadow,
        renderOrder: obj.renderOrder || 0,
        localTransform: {
          position: array3(obj.position),
          quaternion: array4(obj.quaternion),
          scale: array3(obj.scale),
        },
        geometry: obj.geometry ? geometryIds.get(obj.geometry) : null,
        materials: materialList.map((m) => materialIds.get(m)).filter(Boolean),
      };
      if (obj.morphTargetInfluences) rec.morphTargetInfluences = Array.from(obj.morphTargetInfluences, (v) => finiteNumber(v));
      if (obj.isInstancedMesh) {
        const matrices = new Float32Array(obj.count * 16);
        const matrix = obj.instanceMatrix.array;
        matrices.set(matrix.subarray(0, obj.count * 16));
        rec.instances = { count: obj.count, matrices };
        if (obj.instanceColor) {
          const colors = new Float32Array(obj.count * obj.instanceColor.itemSize);
          colors.set(obj.instanceColor.array.subarray(0, colors.length));
          rec.instances.colors = colors;
          rec.instances.colorItemSize = obj.instanceColor.itemSize;
        }
      }
      nodes.push(rec);
    });
    return { rootNode: nodeIds.get(root), nodes, nodeIds, geometryUsage };
  }

  function resolveTextureCanvas(texture) {
    if (!texture) return null;
    const image = texture.source?.data || texture.image;
    if (!image) return null;
    if (typeof HTMLCanvasElement !== 'undefined' && image instanceof HTMLCanvasElement) return image;
    if (typeof OffscreenCanvas !== 'undefined' && image instanceof OffscreenCanvas) return image;
    if (typeof ImageBitmap !== 'undefined' && image instanceof ImageBitmap) {
      const c = document.createElement('canvas');
      c.width = image.width;
      c.height = image.height;
      c.getContext('2d').drawImage(image, 0, 0);
      return c;
    }
    return null;
  }

  function canvasRgba(texture, id, fileName) {
    const canvas = resolveTextureCanvas(texture);
    if (!canvas) throw new Error(`Texture ${id} is not backed by a readable canvas`);
    const width = canvas.width;
    const height = canvas.height;
    const ctx = canvas.getContext('2d', { willReadFrequently: true });
    const imageData = ctx.getImageData(0, 0, width, height);
    const bytes = new Uint8Array(imageData.data.buffer.slice(0));
    const pngDataUrl = canvas.toDataURL('image/png');
    return {
      bytes,
      pngDataUrl,
      record: {
        id,
        name: id,
        buffer: fileName,
        width,
        height,
        channels: 4,
        pixelFormat: 'rgba8',
        rowOrder: 'top-to-bottom',
        rowStride: width * 4,
        byteLength: bytes.byteLength,
        colorSpace: texture.colorSpace === 'srgb' || String(texture.colorSpace).toLowerCase().includes('srgb') ? 'srgb' : 'linear',
        wrapS: texture.wrapS,
        wrapT: texture.wrapT,
        magFilter: texture.magFilter,
        minFilter: texture.minFilter,
        flipY: texture.flipY !== false,
        premultiplyAlpha: !!texture.premultiplyAlpha,
        repeat: vec2Value(texture.repeat, [1, 1]),
        offset: vec2Value(texture.offset, [0, 0]),
        center: vec2Value(texture.center, [0, 0]),
        rotation: finiteNumber(texture.rotation, 0),
      },
    };
  }

  function mat4Buffer(root, fileName) {
    root.updateMatrixWorld(true);
    const list = [];
    root.traverse((obj) => {
      if (!obj.isInstancedMesh) return;
      list.push(obj);
    });
    if (!list.length) return { bytes: new Uint8Array(), entries: [] };
    let totalFloats = 0;
    for (const mesh of list) totalFloats += mesh.count * 16 + (mesh.instanceColor ? mesh.count * mesh.instanceColor.itemSize : 0);
    const out = new Float32Array(totalFloats);
    const entries = [];
    let p = 0;
    for (const mesh of list) {
      const matrixFloats = mesh.count * 16;
      out.set(mesh.instanceMatrix.array.subarray(0, matrixFloats), p);
      const rec = {
        nodeObject: mesh,
        matrices: {
          buffer: fileName,
          byteOffset: p * 4,
          byteLength: matrixFloats * 4,
          componentType: 'float32',
          littleEndian: true,
          count: mesh.count,
          itemSize: 16,
        },
      };
      p += matrixFloats;
      if (mesh.instanceColor) {
        const n = mesh.count * mesh.instanceColor.itemSize;
        out.set(mesh.instanceColor.array.subarray(0, n), p);
        rec.colors = {
          buffer: fileName,
          byteOffset: p * 4,
          byteLength: n * 4,
          componentType: 'float32',
          littleEndian: true,
          count: mesh.count,
          itemSize: mesh.instanceColor.itemSize,
        };
        p += n;
      }
      entries.push(rec);
    }
    return { bytes: new Uint8Array(out.buffer), entries };
  }

  function textureSignature(texture) {
    const canvas = resolveTextureCanvas(texture);
    if (!canvas) return null;
    const ctx = canvas.getContext('2d', { willReadFrequently: true });
    const sample = ctx.getImageData(0, 0, canvas.width, canvas.height).data;
    let h1 = 2166136261 >>> 0;
    let h2 = 0x9e3779b9 >>> 0;
    for (let i = 0; i < sample.length; i++) {
      const v = sample[i];
      h1 = Math.imul(h1 ^ v, 16777619) >>> 0;
      h2 = (Math.imul(h2 ^ (v + i), 2246822519) + 3266489917) >>> 0;
    }
    return `${canvas.width}x${canvas.height}:${h1.toString(16).padStart(8, '0')}${h2.toString(16).padStart(8, '0')}`;
  }

  function collectTexturesAndMaterials(assetRoots, namedTextures) {
    const materialSet = new Set();
    const textureCandidates = new Set(namedTextures.map((x) => x.texture));
    for (const { root } of assetRoots) {
      root.traverse((obj) => {
        const list = Array.isArray(obj.material) ? obj.material : obj.material ? [obj.material] : [];
        for (const mat of list) {
          materialSet.add(mat);
          for (const key of ['map', 'bumpMap', 'normalMap', 'roughnessMap', 'metalnessMap', 'alphaMap', 'emissiveMap', 'aoMap']) {
            if (mat[key]) textureCandidates.add(mat[key]);
          }
        }
      });
    }
    const canonicalBySignature = new Map();
    const canonicalForTexture = new Map();
    const textureSet = new Set();
    for (const texture of textureCandidates) {
      const signature = textureSignature(texture) || `uuid:${texture.uuid}`;
      let canonical = canonicalBySignature.get(signature);
      if (!canonical) {
        canonical = texture;
        canonicalBySignature.set(signature, canonical);
        textureSet.add(canonical);
      }
      canonicalForTexture.set(texture, canonical);
    }
    return { textureSet, materialSet, canonicalForTexture };
  }

  function buildAnchorMap(assetId, provided, nodeIds) {
    const out = {};
    for (const [name, obj] of Object.entries(provided || {})) {
      if (!obj || !nodeIds.has(obj)) continue;
      out[name] = nodeIds.get(obj);
    }
    return out;
  }

  async function exportAssets() {
    const hook = window.__assetExportHook;
    if (!hook) throw new Error('window.__assetExportHook was not injected');
    const api = window.__pelican;
    if (!api?.bike?.group || !api?.pelican?.root) throw new Error('window.__pelican did not initialize');

    api.settings.timeFlow = false;
    api.settings.cruise = 0;
    api.S.speed = 0;
    api.S.paused = true;
    api.bike.update({ wheelAngle: 0, crankAngle: 0, steerAngle: 0, speed: 0, night: 0 });

    const fishRoot = new hook.THREE.Group();
    fishRoot.name = 'fish';
    const fishMaterial = new hook.THREE.MeshStandardMaterial({ vertexColors: true, metalness: 0.6, roughness: 0.25, emissive: new hook.THREE.Color('#1f6b8f'), emissiveIntensity: 0.45, side: hook.THREE.DoubleSide });
    const fishMesh = new hook.THREE.Mesh(hook.fishGeometry(), fishMaterial);
    fishMesh.name = 'fishMesh';
    fishRoot.add(fishMesh);

    const assetRoots = [
      { id: 'bicycle', root: api.bike.group, anchors: api.bike.anchors },
      {
        id: 'pelican',
        root: api.pelican.root,
        anchors: {
          body: api.pelican.body,
          head: api.pelican.head,
          beakTip: api.pelican.beakTip,
          mouth: api.pelican.mouth,
          scarfKnot: api.pelican.knot,
        },
      },
      { id: 'fish', root: fishRoot, anchors: { origin: fishRoot } },
    ];

    const road = hook.textureFactories.makeRoadTextures();
    const textureDefs = [
      { id: 'road_color', texture: road.map, usage: 'baseColor' },
      { id: 'road_bump', texture: road.bump, usage: 'height' },
      { id: 'feather_bump', texture: hook.textureFactories.makeFeatherTexture(), usage: 'height' },
      { id: 'wicker', texture: hook.textureFactories.makeWickerTexture(), usage: 'baseColor' },
      { id: 'sprite', texture: hook.textureFactories.makeSpriteTexture(), usage: 'sprite' },
      { id: 'decal_pelicano', texture: hook.textureFactories.makeDecalTexture('PELICANO'), usage: 'baseColorAlpha' },
      { id: 'sign_crossing', texture: hook.textureFactories.makeSignTexture('crossing'), usage: 'baseColorAlpha' },
      { id: 'sign_speed', texture: hook.textureFactories.makeSignTexture('speed'), usage: 'baseColorAlpha' },
      { id: 'sign_fish', texture: hook.textureFactories.makeSignTexture('fish'), usage: 'baseColorAlpha' },
      { id: 'lighthouse_stripes', texture: hook.textureFactories.makeStripeTexture(['#f4f1ea', '#c9302c'], 6), usage: 'baseColor' },
    ];

    const { textureSet, materialSet, canonicalForTexture } = collectTexturesAndMaterials(assetRoots, textureDefs);
    const textureIds = new Map();
    for (const def of textureDefs) {
      const canonical = canonicalForTexture.get(def.texture) || def.texture;
      if (!textureIds.has(canonical)) textureIds.set(canonical, def.id);
      textureIds.set(def.texture, textureIds.get(canonical));
    }
    let autoTexture = 0;
    for (const texture of textureSet) {
      if (!textureIds.has(texture)) textureIds.set(texture, `texture_auto_${++autoTexture}`);
    }
    for (const [texture, canonical] of canonicalForTexture) textureIds.set(texture, textureIds.get(canonical));
    const materialIds = new Map();
    let materialSerial = 0;
    for (const material of materialSet) materialIds.set(material, `material_${++materialSerial}`);

    const geometrySet = new Set();
    for (const { root } of assetRoots) root.traverse((obj) => obj.geometry && geometrySet.add(obj.geometry));
    const geometryIds = new Map();
    let geometrySerial = 0;
    for (const geometry of geometrySet) geometryIds.set(geometry, `geometry_${++geometrySerial}`);

    const treeData = [];
    const usage = new Map();
    for (const asset of assetRoots) {
      const tree = serializeTree(asset.root, asset.id, geometryIds, materialIds);
      for (const [geometry, nodes] of tree.geometryUsage) {
        const list = usage.get(geometry) || [];
        list.push(...nodes);
        usage.set(geometry, list);
      }
      treeData.push({ ...asset, ...tree });
    }

    const files = [];
    const buffers = [];
    const geometries = [];
    for (const geometry of geometrySet) {
      const id = geometryIds.get(geometry);
      const fileName = `geometry/${makeSafeName(id, 'geometry')}.bin`;
      const packed = serializeGeometry(geometry, id, fileName, usage.get(geometry) || []);
      files.push({ path: fileName, kind: 'binary', data: packed.bytes });
      buffers.push({ id: `buffer_${id}`, path: fileName, byteLength: packed.bytes.byteLength, usage: 'geometry' });
      geometries.push(packed.record);
    }

    const textures = [];
    const namedByTexture = new Map();
    for (const def of textureDefs) {
      const canonical = canonicalForTexture.get(def.texture) || def.texture;
      if (!namedByTexture.has(canonical)) namedByTexture.set(canonical, def);
    }
    for (const texture of textureSet) {
      const id = textureIds.get(texture);
      const rawPath = `textures/${id}.rgba8`;
      const packed = canvasRgba(texture, id, rawPath);
      const def = namedByTexture.get(texture);
      packed.record.usage = def?.usage || 'materialTexture';
      packed.record.png = `textures/${id}.png`;
      files.push({ path: rawPath, kind: 'binary', data: packed.bytes });
      files.push({ path: packed.record.png, kind: 'dataUrl', data: packed.pngDataUrl });
      buffers.push({ id: `buffer_${id}`, path: rawPath, byteLength: packed.bytes.byteLength, usage: 'texture' });
      textures.push(packed.record);
    }

    const materials = [];
    for (const material of materialSet) materials.push(materialRecord(material, materialIds.get(material), textureIds));

    const assets = [];
    for (const tree of treeData) {
      const instanceFile = `instances/${tree.id}.bin`;
      const packedInstances = mat4Buffer(tree.root, instanceFile);
      if (packedInstances.bytes.byteLength) {
        files.push({ path: instanceFile, kind: 'binary', data: packedInstances.bytes });
        buffers.push({ id: `buffer_instances_${tree.id}`, path: instanceFile, byteLength: packedInstances.bytes.byteLength, usage: 'instances' });
        const byObject = new Map(packedInstances.entries.map((e) => [e.nodeObject, e]));
        tree.root.traverse((obj) => {
          const entry = byObject.get(obj);
          if (!entry) return;
          const rec = tree.nodes.find((n) => n.id === tree.nodeIds.get(obj));
          rec.instances = { count: obj.count, matrices: entry.matrices };
          if (entry.colors) rec.instances.colors = entry.colors;
        });
      }
      assets.push({
        id: tree.id,
        name: tree.root.name || tree.id,
        rootNode: tree.rootNode,
        nodes: tree.nodes,
        anchors: buildAnchorMap(tree.id, tree.anchors, tree.nodeIds),
      });
    }

    const totalVertices = geometries.reduce((s, g) => s + g.vertexCount, 0);
    const totalTriangles = geometries.reduce((s, g) => s + g.triangleCount, 0);
    const manifest = {
      format: MAGIC,
      version: FORMAT_VERSION,
      generator: {
        name: 'pelican-bike-asset-exporter',
        source: location.href,
        threeRevision: hook.THREE.REVISION,
        coordinateSystem: 'right-handed; +X forward, +Y up, +Z rider-left in source scene',
        matrixLayout: 'column-major (Three.js/OpenGL convention)',
        units: 'meters',
      },
      binaryEncoding: {
        byteOrder: 'little-endian',
        float: 'IEEE-754 float32',
        index: 'uint32',
        alignment: 4,
      },
      buffers,
      geometries,
      textures,
      materials,
      assets,
      stats: {
        assetCount: assets.length,
        nodeCount: assets.reduce((s, a) => s + a.nodes.length, 0),
        geometryCount: geometries.length,
        materialCount: materials.length,
        textureCount: textures.length,
        vertexCount: totalVertices,
        triangleCount: totalTriangles,
        binaryBytes: buffers.reduce((s, b) => s + b.byteLength, 0),
      },
    };

    const transport = files.map((f) => {
      if (f.kind === 'binary') {
        let binary = '';
        const bytes = f.data;
        const step = 0x8000;
        for (let i = 0; i < bytes.length; i += step) binary += String.fromCharCode(...bytes.subarray(i, i + step));
        return { path: f.path, encoding: 'base64', data: btoa(binary) };
      }
      if (f.kind === 'dataUrl') return { path: f.path, encoding: 'dataUrl', data: f.data };
      return { path: f.path, encoding: 'utf8', data: f.data };
    });
    return { manifest, files: transport };
  }

  window.__runPelicanAssetExport = exportAssets;
})();
