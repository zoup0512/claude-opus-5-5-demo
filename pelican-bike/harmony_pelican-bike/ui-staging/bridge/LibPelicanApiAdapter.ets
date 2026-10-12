import pelican from 'libpelican.so';
import {
  HudSnapshot,
  InitializeOptions,
  PelicanEvent,
  SettingValue
} from 'libpelican.so';
import {
  NativeEventType,
  NativeHudSnapshot,
  NativeInitializeOptions,
  NativePelicanEvent,
  PelicanNativeApi
} from './PelicanNativeTypes';

export class LibPelicanApiAdapter implements PelicanNativeApi {
  initialize(options?: NativeInitializeOptions): boolean {
    if (options === undefined) {
      return pelican.initialize();
    }
    const nativeOptions: InitializeOptions = {
      resourceManager: options.resourceManager,
      quality: options.quality,
      camera: options.camera,
      night: options.night
    };
    return pelican.initialize(nativeOptions);
  }

  start(withSound: boolean): boolean {
    return pelican.start(withSound);
  }

  setPaused(paused: boolean): void {
    pelican.setPaused(paused);
  }

  setInput(name: string, pressed: boolean): void {
    pelican.setInput(name, pressed);
  }

  triggerAction(action: string, x?: number, y?: number): void {
    if (x !== undefined && y !== undefined) {
      pelican.triggerAction(action, x, y);
      return;
    }
    pelican.triggerAction(action);
  }

  setCamera(camera: string): void {
    pelican.setCamera(camera);
  }

  setSetting(name: string, value: boolean | number | string): void {
    const settingValue: SettingValue = value;
    pelican.setSetting(name, settingValue);
  }

  getSnapshot(): NativeHudSnapshot {
    return this.copySnapshot(pelican.getSnapshot());
  }

  setEventCallback(callback: ((event: NativePelicanEvent) => void) | null): void {
    if (callback === null) {
      pelican.setEventCallback(null);
      return;
    }
    pelican.setEventCallback((event: PelicanEvent): void => {
      callback(this.copyEvent(event));
    });
  }

  requestScreenshot(): void {
    pelican.requestScreenshot();
  }

  dispose(): void {
    pelican.dispose();
  }

  private copySnapshot(snapshot: HudSnapshot): NativeHudSnapshot {
    const result: NativeHudSnapshot = new NativeHudSnapshot();
    result.speedKmh = snapshot.speedKmh;
    result.cadence = snapshot.cadence;
    result.gear = snapshot.gear;
    result.gearCount = snapshot.gearCount;
    result.distanceKm = snapshot.distanceKm;
    result.fish = snapshot.fish;
    result.achievements = snapshot.achievements;
    result.achievementTotal = snapshot.achievementTotal;
    result.hour = snapshot.hour;
    result.fps = snapshot.fps;
    result.quality = snapshot.quality;
    result.camera = snapshot.camera;
    result.night = snapshot.night;
    result.started = snapshot.started;
    result.paused = snapshot.paused;
    return result;
  }

  private copyEvent(event: PelicanEvent): NativePelicanEvent {
    const result: NativePelicanEvent = new NativePelicanEvent();
    if (event.type === 'hud') {
      result.type = NativeEventType.HUD;
      result.snapshot = this.copySnapshot(event.snapshot);
    } else if (event.type === 'toast') {
      result.type = NativeEventType.TOAST;
      result.message = event.message;
    } else if (event.type === 'score') {
      result.type = NativeEventType.SCORE;
      result.score = event.score;
      result.delta = event.delta;
      result.golden = event.golden === undefined ? false : event.golden;
      result.x = event.x === undefined ? 0.56 : event.x;
      result.y = event.y === undefined ? 0.42 : event.y;
    } else if (event.type === 'achievement') {
      result.type = NativeEventType.ACHIEVEMENT;
      result.icon = event.icon === undefined ? '' : event.icon;
      result.title = event.title;
      result.detail = event.detail;
      result.current = event.current;
      result.total = event.total;
    } else if (event.type === 'cameraFlash') {
      result.type = NativeEventType.CAMERA_FLASH;
      result.durationMs = event.durationMs === undefined ? 380 : event.durationMs;
      result.intensity = event.intensity === undefined ? 1 : event.intensity;
    } else if (event.type === 'seaJumper') {
      result.type = NativeEventType.SEA_JUMPER;
      result.message = event.message === undefined ? '海面有鱼跃出' : event.message;
      result.x = event.x === undefined ? 0.5 : event.x;
      result.y = event.y === undefined ? 0.5 : event.y;
    } else if (event.type === 'screenshot') {
      result.type = NativeEventType.SCREENSHOT;
      result.path = event.path;
      result.success = event.success;
      result.width = event.width === undefined ? 0 : event.width;
      result.height = event.height === undefined ? 0 : event.height;
      result.pixels = event.pixels;
    } else {
      result.type = NativeEventType.ERROR;
      result.code = event.code;
      result.message = event.message;
    }
    return result;
  }
}
