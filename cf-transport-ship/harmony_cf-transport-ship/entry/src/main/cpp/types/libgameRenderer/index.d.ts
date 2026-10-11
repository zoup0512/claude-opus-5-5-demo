/**
 * libgameRenderer.so —— 运输船 3D 渲染原生模块
 * ArkTS 侧负责游戏逻辑，每帧把相机/骨骼/粒子等数据打包进 Float32Array 交给原生层绘制。
 */
export const createTexture: (id: number, width: number, height: number, pixelsRGBA: Uint8Array) => void;
export const uploadMesh: (id: number, texId: number, flags: number,
  matParams: Float32Array, vdata: Float32Array, idata: Uint32Array) => void;
export const renderFrame: (frame: Float32Array) => void;
export const surfaceReady: () => boolean;
export const viewSize: () => number;
