import {
  CameraMode,
  ControlKey,
  GameAction,
  GameBridgeCallbacks,
  GameSettings,
  GameTelemetry,
  ScreenshotRequest
} from '../model/GameModels';
import { GameBridge } from './GameBridge';

export interface NativeGamePort {
  attach(callbacks: GameBridgeCallbacks): void;
  detach(): void;
  sendStart(withSound: boolean): void;
  sendControl(key: ControlKey, pressed: boolean): void;
  sendAction(action: GameAction): void;
  sendCamera(mode: CameraMode): void;
  sendSettings(settings: GameSettings): void;
  sendScreenshotRequest(request: ScreenshotRequest): Promise<boolean>;
  sendPaused(paused: boolean): void;
  sendHudVisible(visible: boolean): void;
  bindSurface(surfaceId: string): void;
  unbindSurface(): void;
  readTelemetry(): GameTelemetry;
}

export class NativeGameBridgeAdapter implements GameBridge {
  private readonly port: NativeGamePort;

  constructor(port: NativeGamePort) {
    this.port = port;
  }

  connect(callbacks: GameBridgeCallbacks): void {
    this.port.attach(callbacks);
  }

  disconnect(): void {
    this.port.detach();
  }

  start(withSound: boolean): void {
    this.port.sendStart(withSound);
  }

  setControl(key: ControlKey, pressed: boolean): void {
    this.port.sendControl(key, pressed);
  }

  perform(action: GameAction): void {
    this.port.sendAction(action);
  }

  setCamera(mode: CameraMode): void {
    this.port.sendCamera(mode);
  }

  updateSettings(settings: GameSettings): void {
    this.port.sendSettings(settings.copy());
  }

  requestScreenshot(request: ScreenshotRequest): Promise<boolean> {
    return this.port.sendScreenshotRequest(request);
  }

  setPaused(paused: boolean): void {
    this.port.sendPaused(paused);
  }

  setHudVisible(visible: boolean): void {
    this.port.sendHudVisible(visible);
  }

  surfaceReady(surfaceId: string): void {
    this.port.bindSurface(surfaceId);
  }

  surfaceDestroyed(): void {
    this.port.unbindSurface();
  }

  getTelemetry(): GameTelemetry {
    return this.port.readTelemetry();
  }
}
