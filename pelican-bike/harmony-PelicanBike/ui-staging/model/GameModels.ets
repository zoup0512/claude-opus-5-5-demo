export enum CameraMode {
  ORBIT = 'orbit',
  CHASE = 'chase',
  SIDE = 'side',
  CINE = 'cine',
  POV = 'pov'
}

export enum GameAction {
  JUMP = 'jump',
  TRICK = 'trick',
  BELL = 'bell',
  HONK = 'honk',
  NEXT_TIME = 'night',
  TOGGLE_PAUSE = 'pause'
}

export enum ControlKey {
  LEFT = 'left',
  RIGHT = 'right',
  BRAKE = 'down',
  ACCELERATE = 'up'
}

export enum QualityLevel {
  LOW = 'low',
  MEDIUM = 'medium',
  HIGH = 'high',
  ULTRA = 'ultra'
}

export enum GlassesMode {
  AUTO = 'auto',
  ON = 'on',
  OFF = 'off'
}

export enum ToolAction {
  SCREENSHOT = 'screenshot',
  MUSIC = 'music',
  SHARE = 'share',
  IMMERSIVE = 'immersive',
  SETTINGS = 'settings',
  HELP = 'help',
  GITHUB = 'github',
  X = 'x'
}

export class CameraOption {
  readonly id: CameraMode;
  readonly label: string;

  constructor(id: CameraMode, label: string) {
    this.id = id;
    this.label = label;
  }
}

export class ToolOption {
  readonly id: ToolAction;
  readonly icon: string;
  readonly label: string;

  constructor(id: ToolAction, icon: string, label: string) {
    this.id = id;
    this.icon = icon;
    this.label = label;
  }
}

export class IntroChip {
  readonly id: string;
  readonly label: string;

  constructor(id: string, label: string) {
    this.id = id;
    this.label = label;
  }
}

export class HelpItem {
  readonly keyLabel: string;
  readonly text: string;

  constructor(keyLabel: string, text: string) {
    this.keyLabel = keyLabel;
    this.text = text;
  }
}

export class SelectChoice {
  readonly value: string;
  readonly label: string;

  constructor(value: string, label: string) {
    this.value = value;
    this.label = label;
  }
}

export class GameSettings {
  cruise: number = 7.5;
  autopilot: boolean = true;
  autoGear: boolean = true;
  hour: number = 17.35;
  dayRate: number = 0.025;
  timeFlow: boolean = true;
  cloud: number = 0.42;
  waveAmp: number = 1.0;
  fog: number = 1.0;
  quality: QualityLevel = QualityLevel.MEDIUM;
  bloom: boolean = true;
  bloomBoost: number = 1.0;
  exposure: number = 1.0;
  showFps: boolean = false;
  helmet: boolean = true;
  glasses: GlassesMode = GlassesMode.AUTO;
  scarf: boolean = true;
  lookMouse: boolean = true;
  volume: number = 0.8;
  music: boolean = true;
  musicVolume: number = 0.55;

  copy(): GameSettings {
    const next: GameSettings = new GameSettings();
    next.cruise = this.cruise;
    next.autopilot = this.autopilot;
    next.autoGear = this.autoGear;
    next.hour = this.hour;
    next.dayRate = this.dayRate;
    next.timeFlow = this.timeFlow;
    next.cloud = this.cloud;
    next.waveAmp = this.waveAmp;
    next.fog = this.fog;
    next.quality = this.quality;
    next.bloom = this.bloom;
    next.bloomBoost = this.bloomBoost;
    next.exposure = this.exposure;
    next.showFps = this.showFps;
    next.helmet = this.helmet;
    next.glasses = this.glasses;
    next.scarf = this.scarf;
    next.lookMouse = this.lookMouse;
    next.volume = this.volume;
    next.music = this.music;
    next.musicVolume = this.musicVolume;
    return next;
  }
}

export class GameTelemetry {
  speedKmh: number = 0;
  cadence: number = 0;
  gear: number = 3;
  gearCount: number = 5;
  distanceKm: number = 0;
  fishCount: number = 0;
  achievementCount: number = 0;
  achievementTotal: number = 14;
  hour: number = 17.3;
  camera: CameraMode = CameraMode.CINE;
  cameraLabel: string = '电影运镜';
  fps: number = 60;
  qualityLabel: string = '均衡';
  pixelRatio: number = 1.25;
  paused: boolean = false;
  isNight: boolean = false;

  copy(): GameTelemetry {
    const next: GameTelemetry = new GameTelemetry();
    next.speedKmh = this.speedKmh;
    next.cadence = this.cadence;
    next.gear = this.gear;
    next.gearCount = this.gearCount;
    next.distanceKm = this.distanceKm;
    next.fishCount = this.fishCount;
    next.achievementCount = this.achievementCount;
    next.achievementTotal = this.achievementTotal;
    next.hour = this.hour;
    next.camera = this.camera;
    next.cameraLabel = this.cameraLabel;
    next.fps = this.fps;
    next.qualityLabel = this.qualityLabel;
    next.pixelRatio = this.pixelRatio;
    next.paused = this.paused;
    next.isNight = this.isNight;
    return next;
  }
}

export class AchievementEvent {
  readonly icon: string;
  readonly title: string;
  readonly detail: string;
  readonly current: number;
  readonly total: number;

  constructor(icon: string, title: string, detail: string, current: number, total: number) {
    this.icon = icon;
    this.title = title;
    this.detail = detail;
    this.current = current;
    this.total = total;
  }
}

export class ScoreEvent {
  readonly text: string;
  readonly golden: boolean;
  readonly normalizedX: number;
  readonly normalizedY: number;
  readonly fishCount: number;

  constructor(text: string, golden: boolean, normalizedX: number, normalizedY: number, fishCount: number) {
    this.text = text;
    this.golden = golden;
    this.normalizedX = normalizedX;
    this.normalizedY = normalizedY;
    this.fishCount = fishCount;
  }
}

export class FlashCutEvent {
  readonly durationMs: number;

  constructor(durationMs: number) {
    this.durationMs = durationMs;
  }
}

export class ScreenshotRequest {
  readonly fileName: string;
  readonly includeOverlay: boolean;

  constructor(fileName: string, includeOverlay: boolean) {
    this.fileName = fileName;
    this.includeOverlay = includeOverlay;
  }
}

export class ScreenshotFrame {
  readonly success: boolean;
  readonly path: string;
  readonly width: number;
  readonly height: number;
  readonly pixels: ArrayBuffer | undefined;

  constructor(success: boolean, path: string = '', width: number = 0, height: number = 0,
    pixels: ArrayBuffer | undefined = undefined) {
    this.success = success;
    this.path = path;
    this.width = width;
    this.height = height;
    this.pixels = pixels;
  }
}

export class ScreenshotResult {
  readonly success: boolean;
  readonly message: string;
  readonly uri: string;

  constructor(success: boolean, message: string, uri: string = '') {
    this.success = success;
    this.message = message;
    this.uri = uri;
  }
}

export class SystemResult {
  readonly success: boolean;
  readonly message: string;

  constructor(success: boolean, message: string) {
    this.success = success;
    this.message = message;
  }
}

export class GameBridgeCallbacks {
  readonly onTelemetry: (telemetry: GameTelemetry) => void;
  readonly onAchievement: (event: AchievementEvent) => void;
  readonly onScore: (event: ScoreEvent) => void;
  readonly onFlashCut: (event: FlashCutEvent) => void;
  readonly onScreenshot: (frame: ScreenshotFrame) => void;
  readonly onMessage: (message: string) => void;

  constructor(onTelemetry: (telemetry: GameTelemetry) => void,
    onAchievement: (event: AchievementEvent) => void,
    onScore: (event: ScoreEvent) => void,
    onFlashCut: (event: FlashCutEvent) => void,
    onScreenshot: (frame: ScreenshotFrame) => void = (_frame: ScreenshotFrame): void => {},
    onMessage: (message: string) => void = (_message: string): void => {}) {
    this.onTelemetry = onTelemetry;
    this.onAchievement = onAchievement;
    this.onScore = onScore;
    this.onFlashCut = onFlashCut;
    this.onScreenshot = onScreenshot;
    this.onMessage = onMessage;
  }
}

export const CAMERA_OPTIONS: ReadonlyArray<CameraOption> = [
  new CameraOption(CameraMode.ORBIT, '自由环绕'),
  new CameraOption(CameraMode.CHASE, '追随'),
  new CameraOption(CameraMode.SIDE, '侧面跟拍'),
  new CameraOption(CameraMode.CINE, '电影运镜'),
  new CameraOption(CameraMode.POV, '鹈鹕视角')
];

export const TOOL_OPTIONS: ReadonlyArray<ToolOption> = [
  new ToolOption(ToolAction.SCREENSHOT, '▣', '截图'),
  new ToolOption(ToolAction.MUSIC, '♫', '音乐'),
  new ToolOption(ToolAction.SHARE, '↗', '复制分享链接'),
  new ToolOption(ToolAction.IMMERSIVE, '⛶', '沉浸式'),
  new ToolOption(ToolAction.SETTINGS, '⚙', '参数面板'),
  new ToolOption(ToolAction.HELP, '?', '帮助'),
  new ToolOption(ToolAction.GITHUB, 'GH', 'GitHub 源码'),
  new ToolOption(ToolAction.X, '𝕏', '作者主页')
];

export const INTRO_CHIPS: ReadonlyArray<IntroChip> = [
  new IntroChip('model', '程序化建模'),
  new IntroChip('ik', '双骨骼 IK 踩踏'),
  new IntroChip('cloth', 'Verlet 布料围巾'),
  new IntroChip('ocean', 'Gerstner 海浪'),
  new IntroChip('cycle', '昼夜循环'),
  new IntroChip('audio', '合成音效 + 生成式音乐'),
  new IntroChip('fish', '抓鱼小游戏')
];

export const HELP_ITEMS: ReadonlyArray<HelpItem> = [
  new HelpItem('W / ↑', '加速'),
  new HelpItem('S / ↓', '刹车，滑行有棘轮声'),
  new HelpItem('A / D', '左右变道抓鱼'),
  new HelpItem('空格', '跳跃'),
  new HelpItem('T', '放手展翅 + 抬前轮'),
  new HelpItem('B', '按车铃'),
  new HelpItem('H', '鹈鹕大叫'),
  new HelpItem('C', '切换镜头'),
  new HelpItem('Q / E', '手动换挡'),
  new HelpItem('N', '时间快进 3 小时'),
  new HelpItem('M', '音乐开关'),
  new HelpItem('K / F', '截图 / 沉浸式'),
  new HelpItem('U', '隐藏界面'),
  new HelpItem('P', '暂停')
];

export const QUALITY_CHOICES: ReadonlyArray<SelectChoice> = [
  new SelectChoice(QualityLevel.LOW, '流畅'),
  new SelectChoice(QualityLevel.MEDIUM, '均衡'),
  new SelectChoice(QualityLevel.HIGH, '精美'),
  new SelectChoice(QualityLevel.ULTRA, '极致')
];

export const GLASSES_CHOICES: ReadonlyArray<SelectChoice> = [
  new SelectChoice(GlassesMode.AUTO, '自动'),
  new SelectChoice(GlassesMode.ON, '戴上'),
  new SelectChoice(GlassesMode.OFF, '摘下')
];

export function cameraLabel(mode: CameraMode): string {
  for (let index: number = 0; index < CAMERA_OPTIONS.length; index += 1) {
    const item: CameraOption = CAMERA_OPTIONS[index];
    if (item.id === mode) {
      return item.label;
    }
  }
  return '自由环绕';
}

export function qualityLabel(level: QualityLevel): string {
  for (let index: number = 0; index < QUALITY_CHOICES.length; index += 1) {
    const item: SelectChoice = QUALITY_CHOICES[index];
    if (item.value === level) {
      return item.label;
    }
  }
  return '精美';
}

export function formatClock(hourValue: number): string {
  let hour: number = Math.floor(hourValue) % 24;
  if (hour < 0) {
    hour += 24;
  }
  const minute: number = Math.floor((hourValue - Math.floor(hourValue)) * 60 + 0.0001);
  const hourText: string = hour < 10 ? '0' + hour.toString() : hour.toString();
  const minuteText: string = minute < 10 ? '0' + minute.toString() : minute.toString();
  return hourText + ':' + minuteText;
}
