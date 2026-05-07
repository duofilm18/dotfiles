import {
  action,
  SingletonAction,
  type WillAppearEvent,
} from "@elgato/streamdeck";

const ICON_PATH = "imgs/stats-bg";
const STALE_AFTER_MS = 90_000;

/**
 * Windows PC 狀態：靜態暗灰背景 + setTitle 顯示動態文字。
 * setImage 只在 onWillAppear 呼叫一次；之後純 setTitle。
 */
@action({ UUID: "com.duofilm.claude-monitor.win-stats" })
export class WinStatsAction extends SingletonAction {
  private lastTemp = 0;
  private lastFreq = 0;
  private lastRam = 0;
  private staleTimer: ReturnType<typeof setTimeout> | null = null;
  private hasRecentData = false;
  private lastTitle = "";

  override async onWillAppear(ev: WillAppearEvent): Promise<void> {
    await ev.action.setImage(ICON_PATH);
    await ev.action.setTitle(this.buildTitle());
  }

  updateStats(temp: number, freq: number, ram: number): void {
    this.lastTemp = temp;
    this.lastFreq = freq;
    this.lastRam = ram;
    this.hasRecentData = true;
    this.resetStaleTimer();
    this.broadcastIfChanged();
  }

  private resetStaleTimer(): void {
    if (this.staleTimer) clearTimeout(this.staleTimer);
    this.staleTimer = setTimeout(() => {
      this.hasRecentData = false;
      this.broadcastIfChanged();
    }, STALE_AFTER_MS);
  }

  private broadcastIfChanged(): void {
    const title = this.buildTitle();
    if (title === this.lastTitle) return;
    this.lastTitle = title;
    for (const a of this.actions) {
      a.setTitle(title);
    }
  }

  private buildTitle(): string {
    if (!this.hasRecentData) return "Win PC\nOFFLINE\n--";
    const ghz = (this.lastFreq / 1000).toFixed(1);
    return `Win PC\n${this.lastTemp}°C\n${ghz}GHz`;
  }
}
