import {
  action,
  SingletonAction,
  type WillAppearEvent,
} from "@elgato/streamdeck";

const ICON_PATH = "imgs/stats-bg";

/**
 * RPi5B 系統狀態：靜態暗灰背景 + setTitle 顯示動態文字。
 * setImage 只在 onWillAppear 呼叫一次。
 */
@action({ UUID: "com.duofilm.claude-monitor.system-stats" })
export class SystemStatsAction extends SingletonAction {
  private lastTemp = -1;
  private lastRam = -1;
  private lastTitle = "";

  override async onWillAppear(ev: WillAppearEvent): Promise<void> {
    await ev.action.setImage(ICON_PATH);
    await ev.action.setTitle(this.buildTitle());
  }

  updateStats(temp: number, ram: number): void {
    if (temp === this.lastTemp && ram === this.lastRam) return;
    this.lastTemp = temp;
    this.lastRam = ram;
    const title = this.buildTitle();
    if (title === this.lastTitle) return;
    this.lastTitle = title;
    for (const a of this.actions) {
      a.setTitle(title);
    }
  }

  private buildTitle(): string {
    if (this.lastTemp < 0) return "RPi5B\n--\n--";
    return `RPi5B\n${this.lastTemp}°C\nRAM ${this.lastRam}%`;
  }
}
