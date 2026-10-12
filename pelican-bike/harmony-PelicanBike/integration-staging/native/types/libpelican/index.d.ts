export interface InitializeOptions {
  /** Stage UI context ResourceManager object, consumed by native rawfile APIs. */
  resourceManager?: Object;
  quality?: 'low' | 'medium' | 'high' | 'ultra' | string;
  camera?: 'orbit' | 'chase' | 'follow' | 'side' | 'cine' | 'pov' | 'firstPerson' | string;
  night?: boolean;
  cruise?: number;
  autopilot?: boolean;
  autoGear?: boolean;
  hour?: number;
  dayRate?: number;
  timeFlow?: boolean;
  cloud?: number;
  waveAmp?: number;
  fog?: number;
  bloom?: boolean;
  bloomBoost?: number;
  exposure?: number;
  showFps?: boolean;
  helmet?: boolean;
  glasses?: 'auto' | 'on' | 'off' | string;
  scarf?: boolean;
  lookMouse?: boolean;
  volume?: number;
  music?: boolean;
  musicVolume?: number;
}

export type SettingValue = boolean | number | string;
export type InputName = 'left' | 'right' | 'up' | 'down' | 'pedal' | 'brake' | 'accelerate' | string;
export type ActionName = 'jump' | 'trick' | 'bell' | 'honk' | 'night' | 'flow' | 'pick' | string;

export interface HudSnapshot {
  speedKmh: number;
  cadence: number;
  /** One-based gear number for display. */
  gear: number;
  gearCount: number;
  distanceKm: number;
  /** Score; normal fish add 1 and golden fish add 5. */
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

export type PelicanEventType =
  | 'hud'
  | 'toast'
  | 'score'
  | 'achievement'
  | 'cameraFlash'
  | 'seaJumper'
  | 'screenshot'
  | 'error';

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
  golden: boolean;
  /** Pelican mouth screen position, normalized from top-left. */
  x: number;
  /** Pelican mouth screen position, normalized from top-left. */
  y: number;
}

export interface AchievementEvent {
  type: 'achievement';
  id: string;
  icon: string;
  title: string;
  detail: string;
}

export interface CameraFlashEvent {
  type: 'cameraFlash';
  intensity: number;
  golden: boolean;
  x: number;
  y: number;
}

export interface SeaJumperEvent {
  type: 'seaJumper';
  x: number;
  y: number;
}

export interface ScreenshotEvent {
  type: 'screenshot';
  success: boolean;
  /** Top-left-origin tightly packed RGBA8 pixels. */
  pixels?: ArrayBuffer;
  width: number;
  height: number;
  message?: string;
}

export interface ErrorEvent {
  type: 'error';
  code: string;
  message: string;
}

export type PelicanEvent =
  | HudEvent
  | ToastEvent
  | ScoreEvent
  | AchievementEvent
  | CameraFlashEvent
  | SeaJumperEvent
  | ScreenshotEvent
  | ErrorEvent;

export type PelicanEventCallback = (event: PelicanEvent) => void;

export const initialize: (options?: InitializeOptions) => boolean;
export const start: (withSound: boolean) => boolean;
export const setPaused: (paused: boolean) => void;
export const setInput: (name: InputName, pressed: boolean) => void;
export const triggerAction: (action: ActionName, x?: number, y?: number) => void;
export const setCamera: (camera: string) => void;
export const setSetting: (name: string, value: SettingValue) => void;
export const getSnapshot: () => HudSnapshot;
export const setEventCallback: (callback: PelicanEventCallback | null) => void;
export const requestScreenshot: () => void;
export const dispose: () => void;
