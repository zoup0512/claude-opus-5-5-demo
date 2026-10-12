import { resourceManager } from '@kit.LocalizationKit';
import {
  AchievementEvent,
  CameraMode,
  ControlKey,
  FlashCutEvent,
  GameAction,
  GameBridgeCallbacks,
  GameSettings,
  GameTelemetry,
  QualityLevel,
  ScoreEvent,
  ScreenshotFrame,
  ScreenshotRequest,
  cameraLabel,
  qualityLabel
} from '../model/GameModels';
import { NativeGamePort } from './NativeGameBridgeAdapter';
import {
  NativeEventType,
  NativeHudSnapshot,
  NativeInitializeOptions,
  NativePelicanEvent,
  PelicanNativeApi
} from './PelicanNativeTypes';

export class LibPelicanPort implements NativeGamePort {
  private readonly nativeApi: PelicanNativeApi;
  private readonly resourceManager: resourceManager.ResourceManager;
  private callbacks: GameBridgeCallbacks | undefined = undefined;
  private initialized: boolean = false;
  private settings: GameSettings = new GameSettings();
  private camera: CameraMode = CameraMode.CINE;

  constructor(nativeApi: PelicanNativeApi, manager: resourceManager.ResourceManager) {
    this.nativeApi = nativeApi;
    this.resourceManager = manager;
  }

  attach(callbacks: GameBridgeCallbacks): void {
    this.callbacks = callbacks;
    this.initializeIfNeeded();
    this.nativeApi.setEventCallback((event: NativePelicanEvent): void => {
      this.handleNativeEvent(event);
    });
  }

  detach(): void {
    this.nativeApi.setEventCallback(null);
    this.callbacks = undefined;
    this.nativeApi.dispose();
    this.initialized = false;
  }

  sendStart(withSound: boolean): void {
    this.initializeIfNeeded();
    this.nativeApi.start(withSound);
  }

  sendControl(key: ControlKey, pressed: boolean): void {
    this.nativeApi.setInput(this.nativeInputName(key), pressed);
  }

  sendAction(action: GameAction): void {
    this.nativeApi.triggerAction(this.nativeActionName(action));
  }

  sendCamera(mode: CameraMode): void {
    this.camera = mode;
    this.nativeApi.setCamera(this.nativeCameraName(mode));
  }

  sendSettings(settings: GameSettings): void {
    this.settings = settings.copy();
    this.nativeApi.setSetting('cruise', settings.cruise);
    this.nativeApi.setSetting('autopilot', settings.autopilot);
    this.nativeApi.setSetting('autoGear', settings.autoGear);
    this.nativeApi.setSetting('hour', settings.hour);
    this.nativeApi.setSetting('dayRate', settings.dayRate);
    this.nativeApi.setSetting('timeFlow', settings.timeFlow);
    this.nativeApi.setSetting('cloud', settings.cloud);
    this.nativeApi.setSetting('waveAmp', settings.waveAmp);
    this.nativeApi.setSetting('fog', settings.fog);
    this.nativeApi.setSetting('quality', settings.quality);
    this.nativeApi.setSetting('bloom', settings.bloom);
    this.nativeApi.setSetting('bloomBoost', settings.bloomBoost);
    this.nativeApi.setSetting('exposure', settings.exposure);
    this.nativeApi.setSetting('showFps', settings.showFps);
    this.nativeApi.setSetting('helmet', settings.helmet);
    this.nativeApi.setSetting('glasses', settings.glasses);
    this.nativeApi.setSetting('scarf', settings.scarf);
    this.nativeApi.setSetting('lookMouse', settings.lookMouse);
    this.nativeApi.setSetting('volume', settings.volume);
    this.nativeApi.setSetting('music', settings.music);
    this.nativeApi.setSetting('musicVolume', settings.musicVolume);
  }

  sendScreenshotRequest(_request: ScreenshotRequest): Promise<boolean> {
    this.nativeApi.requestScreenshot();
    return Promise.resolve(true);
  }

  sendPaused(paused: boolean): void {
    this.nativeApi.setPaused(paused);
  }

  sendHudVisible(_visible: boolean): void {
    // Current native bridge has no HUD visibility API. ArkUI owns HUD visibility.
  }

  bindSurface(_surfaceId: string): void {
    // XComponent libraryname:'pelican' injects OH_NATIVE_XCOMPONENT_OBJ automatically.
  }

  unbindSurface(): void {
    // Surface lifecycle is owned by the native XComponent callbacks.
  }

  readTelemetry(): GameTelemetry {
    return this.toTelemetry(this.nativeApi.getSnapshot());
  }

  private initializeIfNeeded(): void {
    if (this.initialized) {
      return;
    }
    const options: NativeInitializeOptions = new NativeInitializeOptions(
      this.resourceManager,
      this.settings.quality,
      this.nativeCameraName(this.camera),
      false
    );
    this.initialized = this.nativeApi.initialize(options);
  }

  private handleNativeEvent(event: NativePelicanEvent): void {
    const callbacks: GameBridgeCallbacks | undefined = this.callbacks;
    if (callbacks === undefined) {
      return;
    }
    switch (event.type) {
      case NativeEventType.HUD:
        if (event.snapshot !== undefined) {
          callbacks.onTelemetry(this.toTelemetry(event.snapshot));
        }
        break;
      case NativeEventType.TOAST:
        callbacks.onMessage(event.message);
        break;
      case NativeEventType.SCORE:
        callbacks.onScore(new ScoreEvent(
          event.golden ? '+' + event.delta.toFixed(0) + ' 金鱼!' : '+' + event.delta.toFixed(0),
          event.golden,
          event.x,
          event.y,
          event.score
        ));
        break;
      case NativeEventType.ACHIEVEMENT:
        callbacks.onAchievement(new AchievementEvent(
          event.icon,
          event.title,
          event.detail,
          event.current,
          event.total
        ));
        break;
      case NativeEventType.CAMERA_FLASH:
        callbacks.onFlashCut(new FlashCutEvent(event.durationMs));
        break;
      case NativeEventType.SEA_JUMPER:
        callbacks.onMessage(event.message);
        break;
      case NativeEventType.SCREENSHOT:
        callbacks.onScreenshot(new ScreenshotFrame(
          event.success,
          event.path,
          event.width,
          event.height,
          event.pixels
        ));
        break;
      case NativeEventType.ERROR:
        callbacks.onMessage(event.code.length > 0 ? event.code + ': ' + event.message : event.message);
        break;
      default:
        break;
    }
  }

  private toTelemetry(snapshot: NativeHudSnapshot): GameTelemetry {
    const telemetry: GameTelemetry = new GameTelemetry();
    telemetry.speedKmh = snapshot.speedKmh;
    telemetry.cadence = snapshot.cadence;
    telemetry.gear = snapshot.gear;
    telemetry.gearCount = snapshot.gearCount;
    telemetry.distanceKm = snapshot.distanceKm;
    telemetry.fishCount = snapshot.fish;
    telemetry.achievementCount = snapshot.achievements;
    telemetry.achievementTotal = snapshot.achievementTotal;
    telemetry.hour = snapshot.hour;
    telemetry.camera = this.cameraFromNative(snapshot.camera);
    telemetry.cameraLabel = cameraLabel(telemetry.camera);
    telemetry.fps = snapshot.fps;
    telemetry.qualityLabel = qualityLabel(this.qualityFromNative(snapshot.quality));
    telemetry.pixelRatio = this.pixelRatioFor(this.qualityFromNative(snapshot.quality));
    telemetry.paused = snapshot.paused;
    telemetry.isNight = snapshot.night;
    return telemetry;
  }

  private nativeInputName(key: ControlKey): string {
    switch (key) {
      case ControlKey.ACCELERATE:
        return 'pedal';
      case ControlKey.BRAKE:
        return 'brake';
      case ControlKey.LEFT:
        return 'left';
      case ControlKey.RIGHT:
        return 'right';
      default:
        return '';
    }
  }

  private nativeActionName(action: GameAction): string {
    switch (action) {
      case GameAction.JUMP:
        return 'jump';
      case GameAction.TRICK:
        return 'trick';
      case GameAction.BELL:
        return 'bell';
      case GameAction.HONK:
        return 'honk';
      case GameAction.NEXT_TIME:
        return 'night';
      case GameAction.TOGGLE_PAUSE:
        return 'pause';
      default:
        return '';
    }
  }

  private nativeCameraName(mode: CameraMode): string {
    switch (mode) {
      case CameraMode.CHASE:
        return 'chase';
      case CameraMode.POV:
        return 'pov';
      case CameraMode.ORBIT:
        return 'orbit';
      case CameraMode.SIDE:
        return 'side';
      case CameraMode.CINE:
        return 'cine';
      default:
        return 'orbit';
    }
  }

  private cameraFromNative(value: string): CameraMode {
    if (value === 'chase' || value === 'follow') {
      return CameraMode.CHASE;
    }
    if (value === 'pov' || value === 'firstPerson') {
      return CameraMode.POV;
    }
    if (value === 'side') {
      return CameraMode.SIDE;
    }
    if (value === 'cine') {
      return CameraMode.CINE;
    }
    return CameraMode.ORBIT;
  }

  private qualityFromNative(value: string): QualityLevel {
    if (value === QualityLevel.LOW) {
      return QualityLevel.LOW;
    }
    if (value === QualityLevel.HIGH) {
      return QualityLevel.HIGH;
    }
    if (value === QualityLevel.ULTRA) {
      return QualityLevel.ULTRA;
    }
    return QualityLevel.MEDIUM;
  }

  private pixelRatioFor(level: QualityLevel): number {
    if (level === QualityLevel.LOW) {
      return 0.8;
    }
    if (level === QualityLevel.HIGH) {
      return 1.75;
    }
    if (level === QualityLevel.ULTRA) {
      return 2.25;
    }
    return 1.25;
  }
}
