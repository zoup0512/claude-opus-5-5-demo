import {
  AchievementEvent,
  CAMERA_OPTIONS,
  CameraMode,
  CameraOption,
  ControlKey,
  FlashCutEvent,
  GameAction,
  GameBridgeCallbacks,
  GameSettings,
  GameTelemetry,
  ScoreEvent,
  ScreenshotFrame,
  ScreenshotRequest,
  SystemResult,
  ToolAction
} from '../model/GameModels';
import { GameBridge } from '../bridge/GameBridge';
import { MockGameBridge } from '../bridge/MockGameBridge';
import {
  PreviewSystemCapabilityAdapter,
  SystemCapabilityAdapter
} from '../bridge/SystemCapabilityAdapter';
import { BrandPanel } from '../components/BrandPanel';
import { CameraBar } from '../components/CameraBar';
import { GameSurface } from '../components/GameSurface';
import { HelpDialog } from '../components/HelpDialog';
import { HudHints } from '../components/HudHints';
import { IntroOverlay } from '../components/IntroOverlay';
import { KeyboardInputLayer } from '../components/KeyboardInputLayer';
import { RideDashboard } from '../components/RideDashboard';
import { ScorePanel } from '../components/ScorePanel';
import { SettingsDrawer } from '../components/SettingsDrawer';
import { SystemToast } from '../components/SystemToast';
import { ToolBar } from '../components/ToolBar';
import { TouchControls } from '../components/TouchControls';
import {
  CinematicOverlay,
  FpsBadge,
  ScorePopOverlay,
  ToastOverlay
} from '../components/TransientEffects';
import { PelicanBreakpoints, PelicanColors, PelicanMetrics } from '../theme/PelicanTheme';

const GITHUB_URL: string = 'https://github.com/riba2534/claude-opus-5-5-demo';
const AUTHOR_URL: string = 'https://x.com/riba2534';

@Component
export struct PelicanBikePage {
  previewMode: boolean = false;
  @StorageProp('windowWidth') storedWindowWidth: number = 720;
  @StorageProp('windowHeight') storedWindowHeight: number = 1280;
  @StorageProp('safeTop') storedSafeTop: number = 0;
  @StorageProp('safeBottom') storedSafeBottom: number = 0;
  @StorageProp('safeLeft') storedSafeLeft: number = 0;
  @StorageProp('safeRight') storedSafeRight: number = 0;
  @StorageLink('pelicanAppForeground') @Watch('onAppForegroundChange') appForeground: boolean = true;
  @StorageLink('pelicanPendingHour') @Watch('onPendingHourChange') pendingHour: number = -1;
  @StorageLink('pelicanPendingCamera') @Watch('onPendingCameraChange') pendingCamera: string = '';

  @State private windowWidth: number = 720;
  @State private windowHeight: number = 1280;
  @State private started: boolean = false;
  @State private hudVisible: boolean = true;
  @State private helpVisible: boolean = false;
  @State private settingsVisible: boolean = false;
  @State private immersiveEnabled: boolean = true;
  @State private telemetry: GameTelemetry = new GameTelemetry();
  @State private settings: GameSettings = new GameSettings();
  @State private achievementToast: AchievementEvent | undefined = undefined;
  @State private scoreEvent: ScoreEvent | undefined = undefined;
  @State private flashVisible: boolean = false;
  @State private systemMessage: string = '';
  @State private userPaused: boolean = false;
  @State private initialCamera: CameraMode = CameraMode.CINE;

  gameBridge: GameBridge = new MockGameBridge();
  systemAdapter: SystemCapabilityAdapter = new PreviewSystemCapabilityAdapter();
  private achievementTimer: number = -1;
  private scoreTimer: number = -1;
  private flashTimer: number = -1;
  private systemTimer: number = -1;
  private pendingScreenshotRequest: ScreenshotRequest | undefined = undefined;

  aboutToAppear(): void {
    this.windowWidth = this.storedWindowWidth;
    this.windowHeight = this.storedWindowHeight;
    const callbacks: GameBridgeCallbacks = new GameBridgeCallbacks(
      (telemetry: GameTelemetry): void => {
        this.telemetry = telemetry.copy();
      },
      (event: AchievementEvent): void => {
        this.showAchievement(event);
      },
      (event: ScoreEvent): void => {
        this.showScore(event);
      },
      (event: FlashCutEvent): void => {
        this.showFlash(event.durationMs);
      },
      (frame: ScreenshotFrame): void => {
        this.handleScreenshotFrame(frame);
      },
      (message: string): void => {
        this.showSystemMessage(message);
      }
    );
    this.gameBridge.connect(callbacks);
    this.consumePendingHour();
    this.consumePendingCamera();
    this.gameBridge.updateSettings(this.settings);
    this.gameBridge.setCamera(this.initialCamera);
  }

  aboutToDisappear(): void {
    this.releaseContinuousInputs();
    this.gameBridge.setPaused(true);
    this.gameBridge.disconnect();
    this.clearTimers();
  }

  onAppForegroundChange(): void {
    if (!this.started) {
      return;
    }
    if (this.appForeground) {
      this.gameBridge.setPaused(this.userPaused);
    } else {
      this.releaseContinuousInputs();
      this.gameBridge.setPaused(true);
    }
  }

  onPendingHourChange(): void {
    this.consumePendingHour();
  }

  onPendingCameraChange(): void {
    this.consumePendingCamera();
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      GameSurface({
        previewMode: this.previewMode,
        onSurfaceReady: (surfaceId: string): void => {
          this.gameBridge.surfaceReady(surfaceId);
        },
        onSurfaceDestroyed: (): void => {
          this.gameBridge.surfaceDestroyed();
        }
      })

      if (this.started) {
        KeyboardInputLayer({
          enabled: !this.helpVisible && !this.settingsVisible,
          onControl: (key: ControlKey, pressed: boolean): void => {
            this.gameBridge.setControl(key, pressed);
          },
          onAction: (action: GameAction): void => {
            this.handleGameAction(action);
          },
          onCycleCamera: (): void => {
            this.cycleCamera();
          },
          onMusic: (): void => {
            this.toggleMusic();
          },
          onScreenshot: (): void => {
            this.takeScreenshot();
          },
          onImmersive: (): void => {
            this.toggleImmersive();
          },
          onToggleHud: (): void => {
            this.toggleHud();
          }
        })
      }

      CinematicOverlay({
        active: this.started && this.telemetry.camera === CameraMode.CINE,
        flashVisible: this.flashVisible,
        barHeight: this.telemetry.camera === CameraMode.CINE ? this.windowHeight * 0.09 : 0
      })

      if (this.started && this.hudVisible) {
        this.hudLayer();
      }

      ToastOverlay({ event: this.achievementToast, safeTop: this.safeTop() })
      ScorePopOverlay({ event: this.scoreEvent, widthValue: this.windowWidth, heightValue: this.windowHeight })
      SystemToast({ message: this.systemMessage, safeTop: this.safeTop() })

      if (!this.started) {
        IntroOverlay({
          widthValue: this.windowWidth,
          heightValue: this.windowHeight,
          safeTop: this.safeTop(),
          safeBottom: this.safeBottom(),
          compact: this.isCompact(),
          shortHeight: this.isShortHeight(),
          tinyHeight: this.isTinyHeight(),
          onStart: (withSound: boolean): void => {
            this.startRide(withSound);
          },
          onOpenGitHub: (): void => {
            this.openLink(GITHUB_URL);
          },
          onOpenAuthor: (): void => {
            this.openLink(AUTHOR_URL);
          }
        })
      }

      if (this.helpVisible) {
        HelpDialog({
          widthValue: this.windowWidth,
          heightValue: this.windowHeight,
          onClose: (): void => {
            this.helpVisible = false;
          }
        })
      }

      if (this.settingsVisible) {
        SettingsDrawer({
          settings: this.settings,
          widthValue: this.windowWidth,
          heightValue: this.windowHeight,
          safeTop: this.safeTop(),
          safeBottom: this.safeBottom(),
          onSettingsChange: (settings: GameSettings): void => {
            this.applySettings(settings);
          },
          onClose: (): void => {
            this.settingsVisible = false;
          }
        })
      }
    }
    .id('pelican-page-root')
    .width('100%')
    .height('100%')
    .backgroundColor(PelicanColors.BACKGROUND)
    .expandSafeArea([SafeAreaType.SYSTEM, SafeAreaType.CUTOUT],
      [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM, SafeAreaEdge.START, SafeAreaEdge.END])
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.updateWindowSize(newArea);
    })
  }

  @Builder
  private hudLayer() {
    Stack() {
      BrandPanel({ widthValue: this.windowWidth, compact: this.isCompact() })
        .align(Alignment.TopStart)
        .translate({ x: this.leftInset(), y: this.topInset() })

      if (this.windowWidth >= 560) {
        ToolBar({
          compact: this.isCompact(),
          availableWidth: this.toolBarWidth(),
          musicEnabled: this.settings.music,
          settingsOpen: this.settingsVisible,
          immersiveEnabled: this.immersiveEnabled,
          onAction: (action: ToolAction): void => {
            this.handleToolAction(action);
          }
        })
        .align(Alignment.TopEnd)
        .translate({ x: -this.rightInset(), y: this.topInset() })
      } else {
        ToolBar({
          compact: true,
          availableWidth: this.toolBarWidth(),
          musicEnabled: this.settings.music,
          settingsOpen: this.settingsVisible,
          immersiveEnabled: this.immersiveEnabled,
          onAction: (action: ToolAction): void => {
            this.handleToolAction(action);
          }
        })
        .align(Alignment.TopCenter)
        .translate({ y: this.topInset() + 48 })
      }

      CameraBar({
        activeCamera: this.telemetry.camera,
        compact: this.windowWidth < PelicanBreakpoints.NARROW,
        maxWidth: this.cameraBarWidth(),
        onSelect: (mode: CameraMode): void => {
          this.gameBridge.setCamera(mode);
        }
      })
      .align(this.windowWidth >= PelicanBreakpoints.NARROW ? Alignment.TopCenter : Alignment.TopStart)
      .translate({
        x: this.windowWidth >= PelicanBreakpoints.NARROW ? 0 : this.leftInset(),
        y: this.cameraBarTop()
      })

      RideDashboard({
        telemetry: this.telemetry,
        compact: this.windowWidth < PelicanBreakpoints.NARROW || this.isShortHeight(),
        showStats: this.windowWidth > PelicanBreakpoints.COMPACT && !this.isTinyHeight()
      })
      .align(Alignment.BottomStart)
      .translate({ x: this.leftInset(), y: -this.bottomInset() })
      .opacity(this.telemetry.camera === CameraMode.CINE ? 0.35 : 1.0)

      ScorePanel({
        telemetry: this.telemetry,
        compact: this.windowWidth < PelicanBreakpoints.NARROW,
        showTime: this.windowWidth >= PelicanBreakpoints.NARROW && !this.isShortHeight(),
        timeFlow: this.settings.timeFlow,
        onHourChange: (hour: number): void => {
          const next: GameSettings = this.settings.copy();
          next.hour = hour;
          this.applySettings(next);
        },
        onToggleFlow: (): void => {
          const next: GameSettings = this.settings.copy();
          next.timeFlow = !next.timeFlow;
          this.applySettings(next);
        }
      })
      .align(Alignment.BottomEnd)
      .translate({ x: -this.rightInset(), y: -this.bottomInset() })
      .opacity(this.telemetry.camera === CameraMode.CINE ? 0.35 : 1.0)

      if (this.windowWidth >= PelicanBreakpoints.HIDE_HINTS && !this.isShortHeight()) {
        HudHints()
          .align(Alignment.BottomCenter)
          .translate({ y: -this.bottomInset() })
          .opacity(this.telemetry.camera === CameraMode.CINE ? 0.35 : 1.0)
      }

      if (this.settings.showFps) {
        FpsBadge({
          fps: this.telemetry.fps,
          qualityLabel: this.telemetry.qualityLabel,
          pixelRatio: this.telemetry.pixelRatio
        })
        .align(Alignment.TopEnd)
        .translate({ x: -this.rightInset(), y: this.topInset() + 56 })
      }

      if (this.showTouchControls()) {
        TouchControls({
          compact: this.windowWidth < PelicanBreakpoints.NARROW || this.isShortHeight(),
          safeLeft: this.safeLeft(),
          safeRight: this.safeRight(),
          safeBottom: this.safeBottom(),
          bottomOffset: this.touchBottomOffset(),
          onControl: (key: ControlKey, pressed: boolean): void => {
            this.gameBridge.setControl(key, pressed);
          },
          onAction: (action: GameAction): void => {
            this.handleGameAction(action);
          }
        })
      }
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.Transparent)
  }

  private updateWindowSize(area: Area): void {
    if (typeof area.width === 'number') {
      this.windowWidth = area.width;
      AppStorage.setOrCreate('windowWidth', area.width);
    }
    if (typeof area.height === 'number') {
      this.windowHeight = area.height;
      AppStorage.setOrCreate('windowHeight', area.height);
    }
  }

  private startRide(withSound: boolean): void {
    const next: GameSettings = this.settings.copy();
    next.music = withSound;
    this.settings = next;
    this.started = true;
    this.gameBridge.updateSettings(next);
    this.gameBridge.start(withSound);
    this.gameBridge.setCamera(this.initialCamera);
    this.showSystemMessage(withSound ? '出发！触屏按钮支持多点同时操作' : '已静音进入，工具栏可重新开启音乐');
  }

  private handleGameAction(action: GameAction): void {
    if (action === GameAction.TOGGLE_PAUSE) {
      this.userPaused = !this.userPaused;
      if (this.appForeground) {
        this.gameBridge.setPaused(this.userPaused);
      }
      this.showSystemMessage(this.userPaused ? '已暂停' : '继续骑行');
      return;
    }
    this.gameBridge.perform(action);
  }

  private handleToolAction(action: ToolAction): void {
    switch (action) {
      case ToolAction.SCREENSHOT:
        this.takeScreenshot();
        break;
      case ToolAction.MUSIC:
        this.toggleMusic();
        break;
      case ToolAction.SHARE:
        this.shareCurrentView();
        break;
      case ToolAction.IMMERSIVE:
        this.toggleImmersive();
        break;
      case ToolAction.SETTINGS:
        this.settingsVisible = !this.settingsVisible;
        break;
      case ToolAction.HELP:
        this.helpVisible = !this.helpVisible;
        break;
      case ToolAction.GITHUB:
        this.openLink(GITHUB_URL);
        break;
      case ToolAction.X:
        this.openLink(AUTHOR_URL);
        break;
      default:
        break;
    }
  }

  private applySettings(settings: GameSettings): void {
    this.settings = settings.copy();
    this.gameBridge.updateSettings(this.settings);
  }

  private toggleMusic(): void {
    const next: GameSettings = this.settings.copy();
    next.music = !next.music;
    this.applySettings(next);
    this.showSystemMessage(next.music ? '生成式音乐已开启' : '音乐已关闭');
  }

  private toggleHud(): void {
    this.hudVisible = !this.hudVisible;
    this.gameBridge.setHudVisible(this.hudVisible);
  }

  private takeScreenshot(): void {
    const request: ScreenshotRequest = new ScreenshotRequest('pelican-ride-' + Date.now().toString() + '.png', false);
    this.pendingScreenshotRequest = request;
    this.gameBridge.requestScreenshot(request).then((accepted: boolean): void => {
      if (!accepted) {
        this.pendingScreenshotRequest = undefined;
        this.showSystemMessage('Native 渲染器未接受截图请求');
      } else {
        this.showSystemMessage('正在生成截图…');
      }
    });
  }

  private handleScreenshotFrame(frame: ScreenshotFrame): void {
    const request: ScreenshotRequest | undefined = this.pendingScreenshotRequest;
    this.pendingScreenshotRequest = undefined;
    if (request === undefined) {
      return;
    }
    this.systemAdapter.saveScreenshot(request, frame).then((result): void => {
      this.showSystemMessage(result.message);
    });
  }

  private shareCurrentView(): void {
    const deepLink: string = 'pelicanbike://ride?time=' + this.telemetry.hour.toFixed(2) +
      '&cam=' + this.telemetry.camera;
    this.systemAdapter.copyText(deepLink).then((result: SystemResult): void => {
      this.showSystemMessage(result.success ? '已复制当前骑行深链' : result.message);
    });
  }

  private openLink(url: string): void {
    this.systemAdapter.openLink(url).then((result: SystemResult): void => {
      this.showSystemMessage(result.message);
    });
  }

  private toggleImmersive(): void {
    const target: boolean = !this.immersiveEnabled;
    this.systemAdapter.setImmersive(target).then((result: SystemResult): void => {
      if (result.success) {
        this.immersiveEnabled = target;
      }
      this.showSystemMessage(result.message);
    });
  }

  private cycleCamera(): void {
    let currentIndex: number = 0;
    for (let index: number = 0; index < CAMERA_OPTIONS.length; index += 1) {
      const option: CameraOption = CAMERA_OPTIONS[index];
      if (option.id === this.telemetry.camera) {
        currentIndex = index;
        break;
      }
    }
    const nextIndex: number = (currentIndex + 1) % CAMERA_OPTIONS.length;
    this.gameBridge.setCamera(CAMERA_OPTIONS[nextIndex].id);
  }

  private showAchievement(event: AchievementEvent): void {
    this.achievementToast = event;
    if (this.achievementTimer >= 0) {
      clearTimeout(this.achievementTimer);
    }
    this.achievementTimer = setTimeout(() => {
      this.achievementToast = undefined;
      this.achievementTimer = -1;
    }, 3200);
  }

  private showScore(event: ScoreEvent): void {
    this.scoreEvent = event;
    if (this.scoreTimer >= 0) {
      clearTimeout(this.scoreTimer);
    }
    this.scoreTimer = setTimeout(() => {
      this.scoreEvent = undefined;
      this.scoreTimer = -1;
    }, 1100);
  }

  private showFlash(durationMs: number): void {
    this.flashVisible = true;
    if (this.flashTimer >= 0) {
      clearTimeout(this.flashTimer);
    }
    this.flashTimer = setTimeout(() => {
      this.flashVisible = false;
      this.flashTimer = -1;
    }, durationMs);
  }

  private showSystemMessage(message: string): void {
    this.systemMessage = message;
    if (this.systemTimer >= 0) {
      clearTimeout(this.systemTimer);
    }
    this.systemTimer = setTimeout(() => {
      this.systemMessage = '';
      this.systemTimer = -1;
    }, 2200);
  }

  private consumePendingHour(): void {
    const value: number = this.pendingHour;
    if (value < 0 || value > 24) {
      return;
    }
    const next: GameSettings = this.settings.copy();
    next.hour = value === 24 ? 0 : value;
    this.settings = next;
    this.gameBridge.updateSettings(next);
    this.pendingHour = -1;
  }

  private consumePendingCamera(): void {
    const value: string = this.pendingCamera;
    const mode: CameraMode | undefined = this.parseCameraMode(value);
    if (mode === undefined) {
      return;
    }
    this.initialCamera = mode;
    this.gameBridge.setCamera(mode);
    this.pendingCamera = '';
  }

  private parseCameraMode(value: string): CameraMode | undefined {
    if (value === CameraMode.ORBIT) {
      return CameraMode.ORBIT;
    }
    if (value === CameraMode.CHASE) {
      return CameraMode.CHASE;
    }
    if (value === CameraMode.SIDE) {
      return CameraMode.SIDE;
    }
    if (value === CameraMode.CINE) {
      return CameraMode.CINE;
    }
    if (value === CameraMode.POV) {
      return CameraMode.POV;
    }
    return undefined;
  }

  private releaseContinuousInputs(): void {
    this.gameBridge.setControl(ControlKey.LEFT, false);
    this.gameBridge.setControl(ControlKey.RIGHT, false);
    this.gameBridge.setControl(ControlKey.BRAKE, false);
    this.gameBridge.setControl(ControlKey.ACCELERATE, false);
  }

  private clearTimers(): void {
    if (this.achievementTimer >= 0) {
      clearTimeout(this.achievementTimer);
    }
    if (this.scoreTimer >= 0) {
      clearTimeout(this.scoreTimer);
    }
    if (this.flashTimer >= 0) {
      clearTimeout(this.flashTimer);
    }
    if (this.systemTimer >= 0) {
      clearTimeout(this.systemTimer);
    }
  }

  private isCompact(): boolean {
    return this.windowWidth <= PelicanBreakpoints.COMPACT;
  }

  private isShortHeight(): boolean {
    return this.windowHeight < PelicanBreakpoints.SHORT_HEIGHT;
  }

  private isTinyHeight(): boolean {
    return this.windowHeight < PelicanBreakpoints.TINY_HEIGHT;
  }

  private safeTop(): number {
    return Math.max(0, this.storedSafeTop);
  }

  private safeBottom(): number {
    return Math.max(0, this.storedSafeBottom);
  }

  private safeLeft(): number {
    return Math.max(0, this.storedSafeLeft);
  }

  private safeRight(): number {
    return Math.max(0, this.storedSafeRight);
  }

  private leftInset(): number {
    return Math.max(PelicanMetrics.EDGE, this.safeLeft() + PelicanMetrics.EDGE_SMALL);
  }

  private rightInset(): number {
    return Math.max(PelicanMetrics.EDGE, this.safeRight() + PelicanMetrics.EDGE_SMALL);
  }

  private topInset(): number {
    return Math.max(PelicanMetrics.SAFE_FALLBACK_TOP, this.safeTop() + 8);
  }

  private bottomInset(): number {
    return Math.max(PelicanMetrics.SAFE_FALLBACK_BOTTOM, this.safeBottom() + 10);
  }

  private cameraBarTop(): number {
    if (this.windowWidth >= PelicanBreakpoints.NARROW) {
      return this.topInset();
    }
    if (this.windowWidth < PelicanBreakpoints.COMPACT) {
      return this.topInset() + 96;
    }
    return this.topInset() + 58;
  }

  private cameraBarWidth(): number {
    if (this.windowWidth >= PelicanBreakpoints.NARROW) {
      return Math.min(520, this.windowWidth * 0.48);
    }
    return Math.max(300, this.windowWidth - this.leftInset() - this.rightInset());
  }

  private toolBarWidth(): number {
    const available: number = this.windowWidth - this.leftInset() - this.rightInset();
    return Math.min(Math.max(300, available), 420);
  }

  private showTouchControls(): boolean {
    return !this.isTinyHeight() && this.windowWidth <= 1180;
  }

  private touchBottomOffset(): number {
    if (this.isShortHeight()) {
      return 84;
    }
    return this.windowWidth < PelicanBreakpoints.NARROW ? 118 : 150;
  }
}
