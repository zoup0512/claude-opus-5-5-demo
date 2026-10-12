declare module 'libpelican.so' {
  export interface InitializeOptions {
    resourceManager?: Object;
    quality?: string;
    camera?: string;
    night?: boolean;
  }

  export type SettingValue = boolean | number | string;

  export interface HudSnapshot {
    speedKmh: number;
    cadence: number;
    gear: number;
    gearCount: number;
    distanceKm: number;
    fish: number;
    achievements: number;
    achievementTotal: number;
    hour: number;
    fps: number;
    quality: string;
    camera: string;
    night: boolean;
    started: boolean;
    paused: boolean;
  }

  export interface HudEvent {
    type: 'hud';
    snapshot: HudSnapshot;
  }

  export interface ToastEvent {
    type: 'toast';
    message: string;
  }

  export interface ScoreEvent {
    type: 'score';
    score: number;
    delta: number;
    golden?: boolean;
    x?: number;
    y?: number;
  }

  export interface AchievementEvent {
    type: 'achievement';
    icon?: string;
    title: string;
    detail: string;
    current: number;
    total: number;
  }

  export interface CameraFlashEvent {
    type: 'cameraFlash';
    durationMs?: number;
    intensity?: number;
  }

  export interface SeaJumperEvent {
    type: 'seaJumper';
    message?: string;
    x?: number;
    y?: number;
  }

  export interface ScreenshotEvent {
    type: 'screenshot';
    path: string;
    success: boolean;
    width?: number;
    height?: number;
    pixels?: ArrayBuffer;
  }

  export interface ErrorEvent {
    type: 'error';
    code: string;
    message: string;
  }

  export type PelicanEvent = HudEvent | ToastEvent | ScoreEvent | AchievementEvent |
    CameraFlashEvent | SeaJumperEvent | ScreenshotEvent | ErrorEvent;
  export type PelicanEventCallback = (event: PelicanEvent) => void;

  export interface PelicanModule {
    initialize(options?: InitializeOptions): boolean;
    start(withSound: boolean): boolean;
    setPaused(paused: boolean): void;
    setInput(name: string, pressed: boolean): void;
    triggerAction(action: string, x?: number, y?: number): void;
    setCamera(camera: string): void;
    setSetting(name: string, value: SettingValue): void;
    getSnapshot(): HudSnapshot;
    setEventCallback(callback: PelicanEventCallback | null): void;
    requestScreenshot(): void;
    dispose(): void;
  }

  const pelican: PelicanModule;
  export default pelican;
}
