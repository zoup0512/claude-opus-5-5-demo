import {
  CameraMode,
  ControlKey,
  GameAction,
  GameBridgeCallbacks,
  GameSettings,
  GameTelemetry,
  ScreenshotRequest
} from '../model/GameModels';

export interface GameBridge {
  connect(callbacks: GameBridgeCallbacks): void;
  disconnect(): void;
  start(withSound: boolean): void;
  setControl(key: ControlKey, pressed: boolean): void;
  perform(action: GameAction): void;
  setCamera(mode: CameraMode): void;
  updateSettings(settings: GameSettings): void;
  requestScreenshot(request: ScreenshotRequest): Promise<boolean>;
  setPaused(paused: boolean): void;
  setHudVisible(visible: boolean): void;
  surfaceReady(surfaceId: string): void;
  surfaceDestroyed(): void;
  getTelemetry(): GameTelemetry;
}
