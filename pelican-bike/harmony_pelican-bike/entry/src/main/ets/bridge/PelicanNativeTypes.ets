import { resourceManager } from '@kit.LocalizationKit';

export class NativeInitializeOptions {
  readonly resourceManager: resourceManager.ResourceManager;
  readonly quality: string;
  readonly camera: string;
  readonly night: boolean;

  constructor(manager: resourceManager.ResourceManager, quality: string, camera: string, night: boolean) {
    this.resourceManager = manager;
    this.quality = quality;
    this.camera = camera;
    this.night = night;
  }
}

export class NativeHudSnapshot {
  speedKmh: number = 0;
  cadence: number = 0;
  gear: number = 3;
  gearCount: number = 5;
  distanceKm: number = 0;
  fish: number = 0;
  achievements: number = 0;
  achievementTotal: number = 14;
  hour: number = 17.35;
  fps: number = 0;
  quality: string = 'medium';
  camera: string = 'cine';
  night: boolean = false;
  started: boolean = false;
  paused: boolean = false;
}

export enum NativeEventType {
  HUD = 'hud',
  TOAST = 'toast',
  SCORE = 'score',
  ACHIEVEMENT = 'achievement',
  CAMERA_FLASH = 'cameraFlash',
  SEA_JUMPER = 'seaJumper',
  SCREENSHOT = 'screenshot',
  ERROR = 'error'
}

export class NativePelicanEvent {
  type: NativeEventType = NativeEventType.HUD;
  snapshot: NativeHudSnapshot | undefined = undefined;
  message: string = '';
  score: number = 0;
  delta: number = 0;
  golden: boolean = false;
  x: number = 0.56;
  y: number = 0.42;
  icon: string = '';
  title: string = '';
  detail: string = '';
  current: number = 0;
  total: number = 14;
  durationMs: number = 380;
  intensity: number = 1;
  path: string = '';
  success: boolean = false;
  code: string = '';
  width: number = 0;
  height: number = 0;
  pixels: ArrayBuffer | undefined = undefined;
}

export interface PelicanNativeApi {
  initialize(options?: NativeInitializeOptions): boolean;
  start(withSound: boolean): boolean;
  setPaused(paused: boolean): void;
  setInput(name: string, pressed: boolean): void;
  triggerAction(action: string, x?: number, y?: number): void;
  setCamera(camera: string): void;
  setSetting(name: string, value: boolean | number | string): void;
  getSnapshot(): NativeHudSnapshot;
  setEventCallback(callback: ((event: NativePelicanEvent) => void) | null): void;
  requestScreenshot(): void;
  dispose(): void;
}
