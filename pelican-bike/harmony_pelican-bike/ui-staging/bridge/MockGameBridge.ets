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
import { GameBridge } from './GameBridge';

export class MockGameBridge implements GameBridge {
  private callbacks: GameBridgeCallbacks | undefined = undefined;
  private settings: GameSettings = new GameSettings();
  private telemetry: GameTelemetry = new GameTelemetry();
  private timerId: number = -1;
  private started: boolean = false;
  private hudVisible: boolean = true;
  private accelerate: boolean = false;
  private brake: boolean = false;
  private left: boolean = false;
  private right: boolean = false;
  private tickCount: number = 0;

  connect(callbacks: GameBridgeCallbacks): void {
    this.callbacks = callbacks;
    this.emitTelemetry();
  }

  disconnect(): void {
    this.stopTimer();
    this.callbacks = undefined;
  }

  start(withSound: boolean): void {
    this.started = true;
    this.settings.music = withSound;
    this.telemetry.paused = false;
    this.startTimer();
    this.emitTelemetry();
  }

  setControl(key: ControlKey, pressed: boolean): void {
    switch (key) {
      case ControlKey.ACCELERATE:
        this.accelerate = pressed;
        break;
      case ControlKey.BRAKE:
        this.brake = pressed;
        break;
      case ControlKey.LEFT:
        this.left = pressed;
        break;
      case ControlKey.RIGHT:
        this.right = pressed;
        break;
      default:
        break;
    }
  }

  perform(action: GameAction): void {
    if (!this.started) {
      return;
    }
    switch (action) {
      case GameAction.JUMP:
        this.emitAchievement(new AchievementEvent('跃', '起飞！', '第一次跳跃', 1, 14));
        break;
      case GameAction.TRICK:
        this.emitAchievement(new AchievementEvent('翼', '放手特技', '展翅 + 抬前轮', 2, 14));
        break;
      case GameAction.BELL:
        if (this.tickCount % 3 === 0) {
          this.emitAchievement(new AchievementEvent('铃', '铃铃铃', '车铃会提醒前方行人', 3, 14));
        }
        break;
      case GameAction.HONK:
        this.emitAchievement(new AchievementEvent('声', '嘎——！', '鹈鹕的呐喊', 4, 14));
        break;
      case GameAction.NEXT_TIME:
        this.telemetry.hour = (this.telemetry.hour + 3) % 24;
        this.settings.hour = this.telemetry.hour;
        this.updateNight();
        this.emitTelemetry();
        break;
      case GameAction.TOGGLE_PAUSE:
        this.setPaused(!this.telemetry.paused);
        break;
      default:
        break;
    }
  }

  setCamera(mode: CameraMode): void {
    this.telemetry.camera = mode;
    this.telemetry.cameraLabel = cameraLabel(mode);
    this.emitTelemetry();
    if (mode === CameraMode.CINE) {
      this.emitFlashCut(new FlashCutEvent(380));
    }
  }

  updateSettings(settings: GameSettings): void {
    this.settings = settings.copy();
    this.telemetry.hour = this.settings.hour;
    this.telemetry.qualityLabel = qualityLabel(this.settings.quality);
    this.telemetry.pixelRatio = this.pixelRatioFor(this.settings.quality);
    this.updateNight();
    this.emitTelemetry();
  }

  requestScreenshot(request: ScreenshotRequest): Promise<boolean> {
    const accepted: boolean = request.fileName.length > 0;
    if (accepted) {
      const callbacks: GameBridgeCallbacks | undefined = this.callbacks;
      if (callbacks !== undefined) {
        callbacks.onScreenshot(new ScreenshotFrame(true, 'preview://' + request.fileName));
      }
    }
    return Promise.resolve(accepted);
  }

  setPaused(paused: boolean): void {
    this.telemetry.paused = paused;
    this.emitTelemetry();
  }

  setHudVisible(visible: boolean): void {
    this.hudVisible = visible;
  }

  surfaceReady(surfaceId: string): void {
    if (surfaceId.length > 0) {
      this.emitTelemetry();
    }
  }

  surfaceDestroyed(): void {
    this.stopTimer();
  }

  getTelemetry(): GameTelemetry {
    return this.telemetry.copy();
  }

  private startTimer(): void {
    this.stopTimer();
    this.timerId = setInterval(() => {
      this.tick();
    }, 100);
  }

  private stopTimer(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  private tick(): void {
    if (!this.started || this.telemetry.paused) {
      return;
    }
    this.tickCount += 1;
    let targetSpeed: number = this.settings.cruise * 3.6;
    if (this.accelerate) {
      targetSpeed += 18;
    }
    if (this.brake) {
      targetSpeed = 2;
    }
    if (this.left || this.right) {
      targetSpeed -= 1.5;
    }
    const speedDelta: number = (targetSpeed - this.telemetry.speedKmh) * 0.10;
    this.telemetry.speedKmh = Math.max(0, Math.min(55, this.telemetry.speedKmh + speedDelta));
    this.telemetry.cadence = Math.max(0, this.telemetry.speedKmh * 2.55);
    this.telemetry.gear = Math.max(1, Math.min(5, Math.ceil(this.telemetry.speedKmh / 11)));
    this.telemetry.distanceKm += this.telemetry.speedKmh / 36000;
    this.telemetry.fps = 58 + Math.sin(this.tickCount * 0.2) * 2;
    if (this.settings.timeFlow) {
      this.telemetry.hour = (this.telemetry.hour + this.settings.dayRate * 0.1) % 24;
      this.settings.hour = this.telemetry.hour;
    }
    this.updateNight();

    if (this.tickCount % 55 === 0) {
      const golden: boolean = this.tickCount % 165 === 0;
      const points: number = golden ? 5 : 1;
      this.telemetry.fishCount += points;
      this.emitScore(new ScoreEvent(golden ? '+5 金鱼!' : '+1', golden, 0.56, 0.42, this.telemetry.fishCount));
    }
    if (this.telemetry.camera === CameraMode.CINE && this.tickCount % 65 === 0) {
      this.emitFlashCut(new FlashCutEvent(380));
    }
    if (this.hudVisible) {
      this.emitTelemetry();
    }
  }

  private updateNight(): void {
    const hour: number = this.telemetry.hour;
    this.telemetry.isNight = hour < 5.5 || hour >= 19.5;
  }

  private emitTelemetry(): void {
    const callbacks: GameBridgeCallbacks | undefined = this.callbacks;
    if (callbacks !== undefined) {
      callbacks.onTelemetry(this.telemetry.copy());
    }
  }

  private emitAchievement(event: AchievementEvent): void {
    this.telemetry.achievementCount = Math.min(this.telemetry.achievementTotal, event.current);
    const callbacks: GameBridgeCallbacks | undefined = this.callbacks;
    if (callbacks !== undefined) {
      callbacks.onAchievement(event);
      callbacks.onTelemetry(this.telemetry.copy());
    }
  }

  private emitScore(event: ScoreEvent): void {
    const callbacks: GameBridgeCallbacks | undefined = this.callbacks;
    if (callbacks !== undefined) {
      callbacks.onScore(event);
      callbacks.onTelemetry(this.telemetry.copy());
    }
  }

  private emitFlashCut(event: FlashCutEvent): void {
    const callbacks: GameBridgeCallbacks | undefined = this.callbacks;
    if (callbacks !== undefined) {
      callbacks.onFlashCut(event);
    }
  }

  private pixelRatioFor(level: QualityLevel): number {
    switch (level) {
      case QualityLevel.LOW:
        return 0.8;
      case QualityLevel.MEDIUM:
        return 1.25;
      case QualityLevel.HIGH:
        return 1.75;
      case QualityLevel.ULTRA:
        return 2.25;
      default:
        return 1.0;
    }
  }
}
