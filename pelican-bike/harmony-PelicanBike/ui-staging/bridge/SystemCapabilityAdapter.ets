import { ScreenshotFrame, ScreenshotRequest, ScreenshotResult, SystemResult } from '../model/GameModels';

export interface SystemCapabilityAdapter {
  copyText(text: string): Promise<SystemResult>;
  openLink(link: string): Promise<SystemResult>;
  setImmersive(enabled: boolean): Promise<SystemResult>;
  saveScreenshot(request: ScreenshotRequest, frame: ScreenshotFrame): Promise<ScreenshotResult>;
}

export class PreviewSystemCapabilityAdapter implements SystemCapabilityAdapter {
  private immersive: boolean = false;

  copyText(text: string): Promise<SystemResult> {
    const success: boolean = text.length > 0;
    return Promise.resolve(new SystemResult(success, success ? 'Preview：已模拟复制' : '没有可复制的内容'));
  }

  openLink(link: string): Promise<SystemResult> {
    const success: boolean = link.indexOf('http') === 0;
    return Promise.resolve(new SystemResult(success, success ? 'Preview：已模拟打开链接' : '链接格式无效'));
  }

  setImmersive(enabled: boolean): Promise<SystemResult> {
    this.immersive = enabled;
    return Promise.resolve(new SystemResult(true, this.immersive ? 'Preview：已进入沉浸式' : 'Preview：已退出沉浸式'));
  }

  saveScreenshot(request: ScreenshotRequest, _frame: ScreenshotFrame): Promise<ScreenshotResult> {
    const success: boolean = request.fileName.length > 0;
    const message: string = success ? 'Preview：已模拟保存截图' : '截图文件名无效';
    return Promise.resolve(new ScreenshotResult(success, message));
  }
}
